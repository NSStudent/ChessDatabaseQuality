//
//  HealthReport.swift
//  ChessDatabaseQuality
//

/// «Salud de la base»: counts of each validation problem with examples.
public struct HealthReport: Sendable, Codable, Hashable {
    public struct Example: Sendable, Codable, Hashable {
        public var gameIndex: Int
        public var byteOffset: Int64
        public var label: String
        public var detail: String
        public var ply: Int?
    }

    public struct Entry: Sendable, Codable, Hashable {
        public var kind: ValidationIssueKind
        /// Number of games with this problem.
        public var games: Int
        public var examples: [Example]
    }

    public var gamesRead = 0
    /// Games with no problem at all.
    public var cleanGames = 0
    /// Games skipped because they could not be read.
    public var skippedGames = 0
    /// Games cut at an illegal move.
    public var truncatedGames = 0
    public private(set) var entries: [ValidationIssueKind: Entry] = [:]
    public var examplesPerKind: Int

    public init(examplesPerKind: Int = 5) {
        self.examplesPerKind = examplesPerKind
    }

    /// Adds the result of validating one game.
    public mutating func record(_ game: GameIssues) {
        gamesRead += 1
        guard !game.issues.isEmpty else {
            cleanGames += 1
            return
        }
        var kinds = Set<ValidationIssueKind>()
        for issue in game.issues {
            guard kinds.insert(issue.kind).inserted else { continue }
            var entry = entries[issue.kind] ?? Entry(kind: issue.kind, games: 0, examples: [])
            entry.games += 1
            if entry.examples.count < examplesPerKind {
                entry.examples.append(Example(
                    gameIndex: game.gameIndex, byteOffset: game.byteOffset, label: game.label,
                    detail: issue.detail, ply: issue.ply
                ))
            }
            entries[issue.kind] = entry
        }
        if kinds.contains(.unreadableGame) { skippedGames += 1 }
        if kinds.contains(.illegalMove) { truncatedGames += 1 }
    }

    /// Entries ordered by severity, then by kind.
    public var sortedEntries: [Entry] {
        entries.values.sorted { ($0.kind.severity, $0.kind) < ($1.kind.severity, $1.kind) }
    }

    public func count(_ kind: ValidationIssueKind) -> Int { entries[kind]?.games ?? 0 }
}
