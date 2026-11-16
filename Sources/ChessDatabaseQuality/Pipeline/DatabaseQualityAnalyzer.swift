//
//  DatabaseQualityAnalyzer.swift
//  ChessDatabaseQuality
//

import FischerCore
import Foundation

/// Options of a full analysis.
public struct QualityOptions: Sendable {
    public var validation = ValidationOptions()
    public var duplicates = DuplicateOptions()
    public var aliases = AliasOptions()
    /// Games read and analyzed in parallel per batch.
    public var batchSize = 8192
    public var concurrency = ProcessInfo.processInfo.activeProcessorCount
    /// Bytes read from the file at a time.
    public var readBlockSize: Int = 4 << 20
    /// Examples per validation problem in the report.
    public var examplesPerKind = 5
    /// Duplicate groups with a merge proposal in the report, per relation.
    public var duplicateExamples = 4
    /// Alias proposals in the report, per confidence.
    public var aliasExamples = 8
    /// Keep the problems of every game in ``QualityAnalysis/gameIssues``.
    public var collectGameIssues = true
    /// Where the duplicate detector spills its partitions. A temporary
    /// directory by default.
    public var workDirectory: URL?

    public init() {}
}

public struct QualityProgress: Sendable {
    public enum Phase: String, Sendable { case scanning, duplicates, aliases, report }
    public var phase: Phase
    public var bytesRead: Int64
    public var totalBytes: Int64
    public var gamesRead: Int
}

/// The result of ``DatabaseQualityAnalyzer/analyze(fileAt:progress:)``.
public struct QualityAnalysis: Sendable {
    public var report: QualityReport
    public var duplicateGroups: [DuplicateGroup]
    public var aliasProposals: [AliasProposal]
    /// Games with at least one problem (empty when
    /// ``QualityOptions/collectGameIssues`` is `false`).
    public var gameIssues: [GameIssues]
    /// Reads games back from the source, for merge proposals.
    public var source: SourceGameReader
}

/// Validates a PGN file, finds duplicates and proposes player aliases in
/// one streaming pass.
///
/// ```swift
/// let analysis = try await DatabaseQualityAnalyzer().analyze(fileAt: url)
/// print(analysis.report.markdown())
/// for group in analysis.duplicateGroups {
///     let proposal = try analysis.source.mergeProposal(for: group)
/// }
/// ```
///
/// The file is read in blocks and split with `PGNByteChunker`; each batch
/// of games is analyzed in parallel and folded into the health report, the
/// player directory and the ``DuplicateDetector``, which spills to disk. A
/// game whose header cannot be read is reported and skipped; the file is
/// never aborted.
public struct DatabaseQualityAnalyzer: Sendable {
    public var options: QualityOptions

    public init(options: QualityOptions = QualityOptions()) {
        self.options = options
    }

    /// Analyzes PGN text (written to a temporary file first).
    public func analyze(pgn text: String) async throws -> QualityAnalysis {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cdq-\(UUID().uuidString).pgn")
        try Data(text.utf8).write(to: url)
        return try await analyze(fileAt: url)
    }

    private struct Processed: Sendable {
        var game: AnalyzedGame
        var fingerprint: DuplicateFingerprint?
    }

    public func analyze(
        fileAt url: URL,
        progress: (@Sendable (QualityProgress) -> Void)? = nil
    ) async throws -> QualityAnalysis {
        let clock = ContinuousClock()
        let started = clock.now
        let totalBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        let detector = try DuplicateDetector(options: options.duplicates, workDirectory: options.workDirectory)
        var directory = PlayerDirectory()
        var health = HealthReport(examplesPerKind: options.examplesPerKind)
        var gameIssues: [GameIssues] = []
        var starts: [Int64] = []
        var lengths: [Int32] = []

        let analyzer = GameAnalyzer(options: options.validation)
        let duplicateOptions = options.duplicates
        let workers = max(1, options.concurrency)

        func process(_ batch: [PGNGameChunk]) async {
            guard !batch.isEmpty else { return }
            let sliceSize = (batch.count + workers - 1) / workers
            let results = await withTaskGroup(of: (Int, [Processed]).self) { group in
                for (slot, start) in Swift.stride(from: 0, to: batch.count, by: sliceSize).enumerated() {
                    let slice = Array(batch[start..<min(batch.count, start + sliceSize)])
                    group.addTask {
                        let processed = slice.map { chunk -> Processed in
                            var game = analyzer.analyze(chunk)
                            let fingerprint = game.isReadable
                                ? DuplicateFingerprint(game.summary(), options: duplicateOptions) : nil
                            game.positionKeys = []
                            game.moves = []
                            return Processed(game: game, fingerprint: fingerprint)
                        }
                        return (slot, processed)
                    }
                }
                var collected: [(Int, [Processed])] = []
                for await result in group { collected.append(result) }
                return collected.sorted { $0.0 < $1.0 }.flatMap(\.1)
            }
            for item in results {
                let game = item.game
                starts.append(game.byteOffset)
                lengths.append(Int32(clamping: game.byteLength))
                let issues = game.gameIssues
                health.record(issues)
                if options.collectGameIssues, !issues.issues.isEmpty { gameIssues.append(issues) }
                guard let fingerprint = item.fingerprint else { continue }
                let year = game.date.year
                directory.observe(game.white, fideID: game.whiteFideID, elo: game.whiteElo, year: year)
                directory.observe(game.black, fideID: game.blackFideID, elo: game.blackElo, year: year)
                detector.add(fingerprint)
            }
        }

        // 1. Streaming scan.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var chunker = PGNByteChunker()
        var pending: [PGNGameChunk] = []
        var bytesRead: Int64 = 0
        while true {
            let block = try handle.read(upToCount: options.readBlockSize) ?? Data()
            if block.isEmpty {
                pending += chunker.finish()
                await process(pending)
                pending = []
                break
            }
            bytesRead += Int64(block.count)
            pending += chunker.consume(block)
            if pending.count >= options.batchSize {
                await process(pending)
                pending = []
                progress?(QualityProgress(phase: .scanning, bytesRead: bytesRead, totalBytes: totalBytes, gamesRead: health.gamesRead))
            }
        }
        let scanned = clock.now

        // 2. Duplicates.
        progress?(QualityProgress(phase: .duplicates, bytesRead: bytesRead, totalBytes: totalBytes, gamesRead: health.gamesRead))
        let duplicates = try detector.finish()
        let deduplicated = clock.now

        // 3. Aliases.
        progress?(QualityProgress(phase: .aliases, bytesRead: bytesRead, totalBytes: totalBytes, gamesRead: health.gamesRead))
        let aliases = directory.aliasProposals(options: options.aliases)
        let aliased = clock.now

        // 4. Report with examples.
        progress?(QualityProgress(phase: .report, bytesRead: bytesRead, totalBytes: totalBytes, gamesRead: health.gamesRead))
        let source = SourceGameReader(url: url, starts: starts, lengths: lengths)
        let duplicateExamples = try examples(of: duplicates.groups, source: source)
        var aliasCounts: [String: Int] = [:]
        var aliasExamples: [AliasProposal] = []
        for confidence in AliasConfidence.allCases {
            let matching = aliases.filter { $0.confidence == confidence }
            aliasCounts[confidence.rawValue] = matching.count
            aliasExamples += matching.prefix(options.aliasExamples)
        }
        let finished = clock.now

        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        let report = QualityReport(
            source: url.lastPathComponent,
            fileBytes: totalBytes,
            games: health.gamesRead,
            timings: QualityReport.Timings(
                scan: seconds(scanned - started), duplicates: seconds(deduplicated - scanned),
                aliases: seconds(aliased - deduplicated), report: seconds(finished - aliased),
                total: seconds(finished - started)
            ),
            peakMemoryBytes: MemoryUsage.peakResidentBytes(),
            concurrency: workers,
            health: health,
            duplicates: duplicates.statistics,
            duplicateExamples: duplicateExamples,
            playerVariants: directory.variantCount,
            aliasCounts: aliasCounts,
            aliasExamples: aliasExamples
        )
        return QualityAnalysis(
            report: report, duplicateGroups: duplicates.groups, aliasProposals: aliases,
            gameIssues: gameIssues, source: source
        )
    }

    private func examples(of groups: [DuplicateGroup], source: SourceGameReader) throws -> [QualityReport.DuplicateExample] {
        var buckets: [String: [DuplicateGroup]] = [:]
        let order = ["exact", "subsumed", "near-positionAtPly", "near-minHash"]
        for group in groups {
            for member in group.members {
                let key = member.relation == .near ? "near-\(member.method?.rawValue ?? "minHash")" : member.relation.rawValue
                if buckets[key, default: []].count < options.duplicateExamples, !(buckets[key]?.contains(group) ?? false) {
                    buckets[key, default: []].append(group)
                }
            }
            if order.allSatisfy({ (buckets[$0]?.count ?? 0) >= options.duplicateExamples }) { break }
        }
        var result: [QualityReport.DuplicateExample] = []
        for key in order {
            for group in buckets[key] ?? [] {
                let tags = try source.tags(of: group.ids)
                let proposal = MergeProposalBuilder.proposal(for: group, tags: tags)
                let games = group.ids.map { id -> QualityReport.DuplicateExample.Game in
                    let header = tags[id] ?? [:]
                    let relation = group.members.first { $0.id == id }
                    return .init(
                        id: id,
                        relation: relation.map { $0.relation == .near ? "near (\($0.method?.rawValue ?? "?"))" : $0.relation.rawValue } ?? "keeper",
                        white: header["White"] ?? "?", black: header["Black"] ?? "?",
                        event: header["Event"] ?? "?", date: header["Date"] ?? "?",
                        result: header["Result"] ?? "?", plyCount: header["PlyCount"]
                    )
                }
                result.append(.init(kind: key, games: games, proposal: proposal))
            }
        }
        return result
    }
}

enum MemoryUsage {
    /// Peak resident set size of the process.
    static func peakResidentBytes() -> UInt64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        #if os(macOS) || os(iOS)
        return UInt64(usage.ru_maxrss)
        #else
        return UInt64(usage.ru_maxrss) * 1024
        #endif
    }
}
