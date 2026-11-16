//
//  DuplicateDetector.swift
//  ChessDatabaseQuality
//

import Foundation

/// Thresholds of the duplicate detector. The defaults are the criteria
/// documented in the README.
public struct DuplicateOptions: Sendable {
    /// Number of pair partitions spilled to disk. Each one is loaded alone,
    /// so memory is about `games / partitions` records.
    public var partitions = 64
    /// Number of partitions of the LSH band index.
    public var bandPartitions = 16
    /// Near duplicates: same pair and same position at this ply (or at the
    /// last ply of shorter games).
    public var nearPly = 40
    /// Two games with the same moves and the same pair but different known
    /// dates are kept apart (a repeated short draw), unless they are at
    /// least this long.
    public var longGamePlies = 60
    /// Shortest game that can be subsumed or near-matched by position.
    public var minimumPrefixPlies = 8
    /// When a player is unknown (`?`, `NN`), games shorter than this are
    /// never paired.
    public var unknownPlayersMinimumPlies = 30
    /// MinHash slots (`bands × rows`).
    public var minHashSize = 32
    /// LSH bands; `minHashSize / bands` rows per band.
    public var bands = 8
    /// MinHash skips the opening: positions before this ply are not used.
    public var minHashStartPly = 10
    /// Games with fewer positions after `minHashStartPly` get no signature.
    public var minHashMinimumPositions = 20
    /// Estimated Jaccard similarity from which two games are near duplicates.
    public var jaccardThreshold = 0.8
    /// LSH buckets larger than this are skipped (common theory).
    public var maximumBucketSize = 64
    /// Surname similarity (Jaro-Winkler) for a player of a MinHash
    /// candidate to count as the same player.
    public var surnameSimilarity = 0.88
    /// Lower similarity accepted for the other player of the candidate
    /// (misspellings such as `Butt` / `Btut`), with the same initial.
    public var weakSurnameSimilarity = 0.7

    public init() {}
}

/// How a duplicate relates to the game it duplicates.
public enum DuplicateRelation: String, Sendable, Codable, Hashable {
    /// Same pair, same moves.
    case exact
    /// Same pair, its moves are a prefix of the other game's moves.
    case subsumed
    /// Same pair and same position at ply 40, or MinHash of positions.
    case near
}

/// Which rule found a near duplicate.
public enum NearDuplicateMethod: String, Sendable, Codable, Hashable {
    case positionAtPly
    case minHash
}

public struct DuplicateMember: Sendable, Codable, Hashable {
    public var id: Int64
    public var relation: DuplicateRelation
    /// The game this one duplicates (the keeper or another member).
    public var duplicateOf: Int64
    public var method: NearDuplicateMethod?
}

/// Games that are the same game. Keep `keeper`, merge the headers and
/// remove `members`.
public struct DuplicateGroup: Sendable, Codable, Hashable {
    public var keeper: Int64
    public var members: [DuplicateMember]

    public var ids: [Int64] { [keeper] + members.map(\.id) }
}

public struct DuplicateStatistics: Sendable, Codable, Hashable {
    public var games = 0
    public var groups = 0
    /// Games to remove because they are exact duplicates.
    public var exact = 0
    /// Games to remove because they are a prefix of another game.
    public var subsumed = 0
    /// Games to remove because they are near duplicates.
    public var near = 0
    public var nearByPosition = 0
    public var nearByMinHash = 0
    public var gamesWithSignature = 0
    public var lshCandidatePairs = 0
    public var lshSkippedBuckets = 0
}

public struct DuplicateResult: Sendable {
    public var groups: [DuplicateGroup]
    public var statistics: DuplicateStatistics
}

/// Finds exact, subsumed and near duplicates in millions of games with
/// bounded memory.
///
/// Feed the games in batches with ``add(_:)-(GameSummary)`` and call
/// ``finish()`` once. Records are spilled to `workDirectory`:
///
/// - **pair partitions**: games are hashed by their normalized pair
///   (White key, Black key) into ``DuplicateOptions/partitions`` files. Each
///   file is loaded alone and, inside each pair, exact duplicates are found
///   with a hash of the moves, subsumed games by looking up the rolling hash
///   of every prefix, and near duplicates by the position at ply 40. All
///   linear in the number of moves.
/// - **LSH band index**: the MinHash signature is cut into bands; games
///   that share a band hash are candidates, verified with the signature
///   (memory-mapped), the players and the date.
///
/// Resident memory is a few bytes per game for the union-find plus one
/// partition.
public final class DuplicateDetector {
    public let options: DuplicateOptions
    public let workDirectory: URL
    private let ownsDirectory: Bool
    private var pairWriters: [BinaryFileWriter] = []
    private var bandWriters: [BinaryFileWriter] = []
    private let metaWriter: BinaryFileWriter
    private let signatureWriter: BinaryFileWriter
    private var nameIDs: [PlayerKey: UInt32] = [:]
    private var names: [PlayerKey] = []
    private var finished = false
    public private(set) var count = 0
    private var signatures = 0

    static let metaStride = 32

    public init(options: DuplicateOptions = DuplicateOptions(), workDirectory: URL? = nil) throws {
        precondition(options.minHashSize % options.bands == 0, "minHashSize must be a multiple of bands")
        self.options = options
        let fileManager = FileManager.default
        if let workDirectory {
            self.workDirectory = workDirectory
            ownsDirectory = false
        } else {
            self.workDirectory = fileManager.temporaryDirectory.appendingPathComponent("cdq-\(UUID().uuidString)")
            ownsDirectory = true
        }
        try fileManager.createDirectory(at: self.workDirectory, withIntermediateDirectories: true)
        for index in 0..<options.partitions {
            pairWriters.append(try BinaryFileWriter(url: self.workDirectory.appendingPathComponent("pair-\(index).bin"), capacity: 1 << 18))
        }
        for index in 0..<options.bandPartitions {
            bandWriters.append(try BinaryFileWriter(url: self.workDirectory.appendingPathComponent("band-\(index).bin"), capacity: 1 << 18))
        }
        metaWriter = try BinaryFileWriter(url: self.workDirectory.appendingPathComponent("meta.bin"))
        signatureWriter = try BinaryFileWriter(url: self.workDirectory.appendingPathComponent("signatures.bin"))
    }

    deinit {
        if ownsDirectory { try? FileManager.default.removeItem(at: workDirectory) }
    }

    private func nameID(_ key: PlayerKey) -> UInt32 {
        if let id = nameIDs[key] { return id }
        let id = UInt32(names.count)
        names.append(key)
        nameIDs[key] = id
        return id
    }

    public func add(_ summary: GameSummary) {
        add(DuplicateFingerprint(summary, options: options))
    }

    public func add(_ summaries: [GameSummary]) {
        for summary in summaries { add(summary) }
    }

    /// Adds a game whose fingerprint was computed elsewhere (in parallel).
    public func add(_ fingerprint: DuplicateFingerprint) {
        precondition(!finished, "add after finish")
        let index = UInt32(count)
        count += 1
        let plies = UInt16(min(fingerprint.moves.count, Int(UInt16.max)))
        let header = UInt16(clamping: fingerprint.headerScore)
        let date = fingerprint.date.packed

        metaWriter.write(fingerprint.id)
        metaWriter.write(nameID(fingerprint.white))
        metaWriter.write(nameID(fingerprint.black))
        metaWriter.write(date)
        metaWriter.write(plies)
        metaWriter.write(header)
        metaWriter.write(UInt8(fingerprint.signature == nil ? 0 : 1))
        metaWriter.write(UInt8(0))
        metaWriter.write(UInt16(0))
        metaWriter.write(UInt32(0))

        let pairKey = StableHash.combine(StableHash.fnv1a64(fingerprint.white.matchKey), StableHash.fnv1a64(fingerprint.black.matchKey))
        let unknown: UInt8 = fingerprint.white.isUnknown || fingerprint.black.isUnknown ? 1 : 0
        let writer = pairWriters[Int(pairKey % UInt64(options.partitions))]
        writer.write(index)
        writer.write(pairKey)
        writer.write(fingerprint.startHash)
        writer.write(fingerprint.nearKey)
        writer.write(UInt16(fingerprint.nearPly))
        writer.write(plies)
        writer.write(date)
        writer.write(header)
        writer.write(unknown)
        writer.write(Array(fingerprint.moves.prefix(Int(plies))))

        if let signature = fingerprint.signature {
            precondition(signature.count == options.minHashSize)
            signatures += 1
            signatureWriter.write(signature)
            let rows = options.minHashSize / options.bands
            for band in 0..<options.bands {
                let hash = MinHash.bandHash(signature, band: band, rows: rows)
                let bandWriter = bandWriters[Int(hash % UInt64(options.bandPartitions))]
                bandWriter.write(hash)
                bandWriter.write(index)
            }
        } else {
            signatureWriter.write([UInt32](repeating: 0, count: options.minHashSize))
        }
    }

    // MARK: - Finish

    private struct Record {
        var index: Int
        var pairKey: UInt64
        var startHash: UInt64
        var nearKey: UInt64
        var nearPly: Int
        var plies: Int
        var date: PGNDate
        var header: Int
        var unknown: Bool
        var moves: [UInt16]
    }

    private struct State {
        var parent: [Int32]
        var relation: [UInt8]      // 0 none, 1 exact, 2 subsumed
        var duplicateOf: [Int32]
        var nearMethod: [UInt8]    // bit 0 position, bit 1 MinHash

        init(count: Int) {
            parent = (0..<count).map { Int32($0) }
            relation = [UInt8](repeating: 0, count: count)
            duplicateOf = [Int32](repeating: -1, count: count)
            nearMethod = [UInt8](repeating: 0, count: count)
        }

        mutating func find(_ x: Int) -> Int {
            var root = x
            while Int(parent[root]) != root { root = Int(parent[root]) }
            var current = x
            while Int(parent[current]) != root {
                let next = Int(parent[current])
                parent[current] = Int32(root)
                current = next
            }
            return root
        }

        @discardableResult
        mutating func union(_ a: Int, _ b: Int) -> Bool {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return false }
            if ra < rb { parent[rb] = Int32(ra) } else { parent[ra] = Int32(rb) }
            return true
        }
    }

    /// Runs the detection and returns the groups. Call once.
    public func finish() throws -> DuplicateResult {
        precondition(!finished, "finish called twice")
        finished = true
        for writer in pairWriters + bandWriters + [metaWriter, signatureWriter] { try writer.close() }

        var statistics = DuplicateStatistics()
        statistics.games = count
        statistics.gamesWithSignature = signatures
        var state = State(count: count)

        for writer in pairWriters {
            let records = try readRecords(writer.url)
            try? FileManager.default.removeItem(at: writer.url)
            processPartition(records, state: &state)
        }

        if count > 0 {
            let meta = try MappedRecords(url: metaWriter.url, stride: Self.metaStride)
            let signatureData = try MappedRecords(url: signatureWriter.url, stride: options.minHashSize * 4)
            for writer in bandWriters {
                try processBands(writer.url, meta: meta, signatures: signatureData, state: &state, statistics: &statistics)
                try? FileManager.default.removeItem(at: writer.url)
            }
            return buildGroups(meta: meta, state: &state, statistics: statistics)
        }
        return DuplicateResult(groups: [], statistics: statistics)
    }

    private func readRecords(_ url: URL) throws -> [Record] {
        var cursor = BinaryCursor(try Data(contentsOf: url))
        var records: [Record] = []
        while !cursor.isAtEnd {
            let index = Int(cursor.read(UInt32.self))
            let pairKey = cursor.read(UInt64.self)
            let startHash = cursor.read(UInt64.self)
            let nearKey = cursor.read(UInt64.self)
            let nearPly = Int(cursor.read(UInt16.self))
            let plies = Int(cursor.read(UInt16.self))
            let date = PGNDate(packed: cursor.read(UInt32.self))
            let header = Int(cursor.read(UInt16.self))
            let unknown = cursor.read(UInt8.self) != 0
            let moves = cursor.readUInt16Array(count: plies)
            records.append(Record(
                index: index, pairKey: pairKey, startHash: startHash, nearKey: nearKey, nearPly: nearPly,
                plies: plies, date: date, header: header, unknown: unknown, moves: moves
            ))
        }
        return records
    }

    private func processPartition(_ records: [Record], state: inout State) {
        var groups: [UInt64: [Int]] = [:]
        for (position, record) in records.enumerated() { groups[record.pairKey, default: []].append(position) }
        for (_, members) in groups where members.count > 1 {
            processPair(members.map { records[$0] }, state: &state)
        }
    }

    private func eligible(_ record: Record) -> Bool {
        !record.unknown || record.plies >= options.unknownPlayersMinimumPlies
    }

    /// Exact, subsumed and position-at-ply duplicates inside one pair.
    private func processPair(_ records: [Record], state: inout State) {
        let prefixes = records.map { DuplicateFingerprint.prefixHashes(startHash: $0.startHash, moves: $0.moves) }
        func better(_ a: Int, _ b: Int) -> Bool {
            (records[a].plies, records[a].header, -records[a].index) > (records[b].plies, records[b].header, -records[b].index)
        }

        // Exact: same moves from the same start.
        var byFull: [UInt64: [Int]] = [:]
        for position in records.indices where eligible(records[position]) {
            byFull[prefixes[position][records[position].plies], default: []].append(position)
        }
        for (_, members) in byFull where members.count > 1 {
            var representatives: [Int] = []
            for position in members.sorted(by: better) {
                let record = records[position]
                if let representative = representatives.first(where: {
                    records[$0].moves == record.moves
                        && (records[$0].date.isCompatible(with: record.date) || record.plies >= options.longGamePlies)
                }) {
                    state.relation[record.index] = 1
                    state.duplicateOf[record.index] = Int32(records[representative].index)
                    state.union(record.index, records[representative].index)
                } else {
                    representatives.append(position)
                }
            }
        }

        // Subsumed: the moves of A are a strict prefix of the moves of B.
        var candidates: [UInt64: [Int]] = [:]
        for position in records.indices
        where state.relation[records[position].index] == 0 && eligible(records[position])
            && records[position].plies >= options.minimumPrefixPlies {
            candidates[prefixes[position][records[position].plies], default: []].append(position)
        }
        if !candidates.isEmpty {
            let containers = records.indices.filter { state.relation[records[$0].index] == 0 }
                .sorted(by: better)
            for container in containers where state.relation[records[container].index] == 0 {
                let long = records[container]
                guard long.plies > options.minimumPrefixPlies else { continue }
                for length in options.minimumPrefixPlies..<long.plies {
                    guard let shorts = candidates[prefixes[container][length]] else { continue }
                    for position in shorts {
                        let short = records[position]
                        guard short.plies == length, state.relation[short.index] == 0, position != container,
                              short.date.isCompatible(with: long.date),
                              long.moves.starts(with: short.moves) else { continue }
                        state.relation[short.index] = 2
                        state.duplicateOf[short.index] = Int32(long.index)
                        state.union(short.index, long.index)
                    }
                }
            }
        }

        // Near: same position at ply 40 (or at the end of shorter games).
        var byNear: [UInt64: [Int]] = [:]
        for position in records.indices
        where state.relation[records[position].index] == 0 && eligible(records[position])
            && records[position].nearPly >= options.minimumPrefixPlies {
            let record = records[position]
            byNear[StableHash.combine(record.nearKey, UInt64(record.nearPly)), default: []].append(position)
        }
        for (_, members) in byNear where members.count > 1 {
            var representatives: [Int] = []
            for position in members.sorted(by: better) {
                let record = records[position]
                if let representative = representatives.first(where: { records[$0].date.isCompatible(with: record.date) }) {
                    if state.union(record.index, records[representative].index) {
                        state.nearMethod[record.index] |= 1
                        state.nearMethod[records[representative].index] |= 1
                    }
                } else {
                    representatives.append(position)
                }
            }
        }
    }

    private enum PlayerMatch { case different, unknown, weak, same }

    private func match(_ a: PlayerKey, _ b: PlayerKey) -> PlayerMatch {
        if a.isUnknown || b.isUnknown { return .unknown }
        if a.matchKey == b.matchKey { return .same }
        if let tokens = a.tokenSetKey, tokens == b.tokenSetKey { return .same }
        guard a.initial.isEmpty || b.initial.isEmpty || a.initial == b.initial else { return .different }
        let similarity = max(
            JaroWinkler.similarity(a.surnameKey, b.surnameKey),
            JaroWinkler.similarity(a.foldedSurname, b.foldedSurname)
        )
        if similarity >= options.surnameSimilarity { return .same }
        if similarity >= options.weakSurnameSimilarity { return .weak }
        // One surname inside the other: `Garcia` / `Fernandez Garcia`, `Amor` / `Ben Amor`.
        let short = a.surnameKey.count <= b.surnameKey.count ? a.surnameKey : b.surnameKey
        let long = a.surnameKey.count <= b.surnameKey.count ? b.surnameKey : a.surnameKey
        return short.count >= 4 && long.contains(short) ? .weak : .different
    }

    private func processBands(
        _ url: URL, meta: MappedRecords, signatures: MappedRecords,
        state: inout State, statistics: inout DuplicateStatistics
    ) throws {
        let data = try Data(contentsOf: url)
        let entryCount = data.count / 12
        guard entryCount > 1 else { return }
        var entries: [(hash: UInt64, index: Int32)] = []
        entries.reserveCapacity(entryCount)
        var cursor = BinaryCursor(data)
        for _ in 0..<entryCount {
            let hash = cursor.read(UInt64.self)
            let index = Int32(cursor.read(UInt32.self))
            entries.append((hash, index))
        }
        entries.sort { ($0.hash, $0.index) < ($1.hash, $1.index) }

        let size = options.minHashSize
        func signature(_ index: Int) -> [UInt32] {
            (0..<size).map { signatures.read(index, at: $0 * 4, as: UInt32.self) }
        }
        var start = 0
        while start < entries.count {
            var end = start + 1
            while end < entries.count, entries[end].hash == entries[start].hash { end += 1 }
            let bucket = end - start
            if bucket > options.maximumBucketSize {
                statistics.lshSkippedBuckets += 1
            } else if bucket > 1 {
                let members = entries[start..<end].map { Int($0.index) }
                let memberSignatures = members.map(signature)
                for i in 0..<members.count {
                    for j in (i + 1)..<members.count {
                        let a = members[i], b = members[j]
                        guard state.find(a) != state.find(b) else { continue }
                        statistics.lshCandidatePairs += 1
                        guard verifyNear(a, b, meta: meta) else { continue }
                        guard MinHash.similarity(memberSignatures[i], memberSignatures[j]) >= options.jaccardThreshold else { continue }
                        state.union(a, b)
                        state.nearMethod[a] |= 2
                        state.nearMethod[b] |= 2
                    }
                }
            }
            start = end
        }
    }

    private func verifyNear(_ a: Int, _ b: Int, meta: MappedRecords) -> Bool {
        let dateA = PGNDate(packed: meta.read(a, at: 16, as: UInt32.self))
        let dateB = PGNDate(packed: meta.read(b, at: 16, as: UInt32.self))
        guard dateA.isCompatible(with: dateB) else { return false }
        let white = match(names[Int(meta.read(a, at: 8, as: UInt32.self))], names[Int(meta.read(b, at: 8, as: UInt32.self))])
        let black = match(names[Int(meta.read(a, at: 12, as: UInt32.self))], names[Int(meta.read(b, at: 12, as: UInt32.self))])
        // One player must match; the other may be a misspelling or unknown.
        if white == .different || black == .different { return false }
        return white == .same || black == .same
    }

    private func buildGroups(meta: MappedRecords, state: inout State, statistics: DuplicateStatistics) -> DuplicateResult {
        var statistics = statistics
        var members: [Int: [Int]] = [:]
        var sizes = [Int32](repeating: 0, count: count)
        var roots = [Int32](repeating: 0, count: count)
        for index in 0..<count {
            let root = state.find(index)
            roots[index] = Int32(root)
            sizes[root] += 1
        }
        for index in 0..<count where sizes[Int(roots[index])] > 1 {
            members[Int(roots[index]), default: []].append(index)
        }
        sizes = []
        roots = []

        func id(_ index: Int) -> Int64 { meta.read(index, at: 0, as: Int64.self) }
        func quality(_ index: Int) -> (Int, Int, Int) {
            (Int(meta.read(index, at: 20, as: UInt16.self)), Int(meta.read(index, at: 22, as: UInt16.self)), -index)
        }

        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(members.count)
        for (_, component) in members {
            let free = component.filter { state.relation[$0] == 0 }
            guard let keeper = free.max(by: { quality($0) < quality($1) }) else { continue }
            var group = DuplicateGroup(keeper: id(keeper), members: [])
            for index in component where index != keeper {
                switch state.relation[index] {
                case 1:
                    group.members.append(DuplicateMember(id: id(index), relation: .exact, duplicateOf: id(Int(state.duplicateOf[index])), method: nil))
                    statistics.exact += 1
                case 2:
                    group.members.append(DuplicateMember(id: id(index), relation: .subsumed, duplicateOf: id(Int(state.duplicateOf[index])), method: nil))
                    statistics.subsumed += 1
                default:
                    let method: NearDuplicateMethod = state.nearMethod[index] & 1 != 0 ? .positionAtPly : .minHash
                    group.members.append(DuplicateMember(id: id(index), relation: .near, duplicateOf: id(keeper), method: method))
                    statistics.near += 1
                    if method == .positionAtPly { statistics.nearByPosition += 1 } else { statistics.nearByMinHash += 1 }
                }
            }
            group.members.sort { $0.id < $1.id }
            groups.append(group)
        }
        groups.sort { $0.keeper < $1.keeper }
        statistics.groups = groups.count
        return DuplicateResult(groups: groups, statistics: statistics)
    }
}
