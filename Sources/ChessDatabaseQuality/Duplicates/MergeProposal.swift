//
//  MergeProposal.swift
//  ChessDatabaseQuality
//

import Foundation

public struct TagValue: Sendable, Codable, Hashable {
    public var name: String
    public var value: String
    /// The game the value was taken from.
    public var source: Int64
}

public struct TagConflict: Sendable, Codable, Hashable {
    public var name: String
    public var values: [String]
}

/// How to merge a duplicate group: keep the moves of `keeper`, use `tags`
/// as its header and remove `remove`.
public struct MergeProposal: Sendable, Codable, Hashable {
    public var keeper: Int64
    public var remove: [Int64]
    /// Seven tag roster first, then the rest by name.
    public var tags: [TagValue]
    /// Tags whose real values disagree; the proposal keeps the first one.
    public var conflicts: [TagConflict]
    /// Tags taken from a game other than the keeper.
    public var improvedTags: [String] {
        tags.filter { $0.source != keeper }.map(\.name)
    }
}

/// Builds merge proposals: the moves of the keeper and, for each tag, the
/// best value of the group.
///
/// - `Date`: the most complete (`2025.03.14` over `2025.??.??`).
/// - `Event`, `Site`: the longest real value («evento completo»).
/// - `White`, `Black`: the most complete spelling (full given names over
///   initials), preferring the game that carries the FIDE ID.
/// - `WhiteFideId`, `BlackFideId`, `WhiteElo`, `BlackElo`, `WhiteTitle`…:
///   the keeper's, or the first real value in the group.
/// - `Result`: the keeper's unless it is `*`.
/// - Every other tag: the keeper's, or the first real value in the group.
///
/// Placeholders (`?`, `????.??.??`, empty, `-`, Elo `0`) never win.
public enum MergeProposalBuilder {
    static let roster = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

    public static func isPlaceholder(_ value: String, tag: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "?" || $0 == "." || $0 == "-" }) { return true }
        if tag.hasSuffix("Elo") || tag.hasSuffix("FideId") { return Int(trimmed) == 0 }
        if tag == "Result" { return trimmed == "*" }
        return false
    }

    /// - Parameters:
    ///   - group: The duplicate group.
    ///   - tags: The header of each game of the group, by id.
    public static func proposal(for group: DuplicateGroup, tags: [Int64: [String: String]]) -> MergeProposal {
        let ids = group.ids
        let keeper = group.keeper
        var names = Set<String>()
        for id in ids { if let header = tags[id] { names.formUnion(header.keys) } }

        var merged: [TagValue] = []
        var conflicts: [TagConflict] = []
        for name in names {
            let candidates: [(id: Int64, value: String)] = ids.compactMap { id in
                guard let value = tags[id]?[name], !isPlaceholder(value, tag: name) else { return nil }
                return (id, value.trimmingCharacters(in: .whitespaces))
            }
            guard let chosen = choose(name, candidates: candidates, keeper: keeper, tags: tags) else {
                if let value = tags[keeper]?[name] { merged.append(TagValue(name: name, value: value, source: keeper)) }
                continue
            }
            merged.append(TagValue(name: name, value: chosen.value, source: chosen.id))
            let distinct = candidates.map(\.value).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if distinct.count > 1, conflicting(name, distinct) {
                conflicts.append(TagConflict(name: name, values: [chosen.value] + distinct.filter { $0 != chosen.value }))
            }
        }
        merged.sort { lhs, rhs in
            let l = roster.firstIndex(of: lhs.name) ?? roster.count, r = roster.firstIndex(of: rhs.name) ?? roster.count
            return (l, lhs.name) < (r, rhs.name)
        }
        conflicts.sort { $0.name < $1.name }
        return MergeProposal(keeper: keeper, remove: group.members.map(\.id), tags: merged, conflicts: conflicts)
    }

    private static func choose(
        _ name: String, candidates: [(id: Int64, value: String)], keeper: Int64, tags: [Int64: [String: String]]
    ) -> (id: Int64, value: String)? {
        guard !candidates.isEmpty else { return nil }
        let keeperFirst = candidates.sorted { ($0.id == keeper ? 0 : 1) < ($1.id == keeper ? 0 : 1) }
        switch name {
        case "PlyCount":
            // Describes the keeper's moves; never borrowed.
            return candidates.first { $0.id == keeper }
        case "Date", "EventDate":
            return keeperFirst.max { PGNDate($0.value).completeness < PGNDate($1.value).completeness }
                .flatMap { best in keeperFirst.first { PGNDate($0.value).completeness == PGNDate(best.value).completeness } }
        case "Event", "Site", "Annotator", "Source":
            let longest = keeperFirst.map(\.value.count).max() ?? 0
            return keeperFirst.first { $0.value.count == longest }
        case "White", "Black":
            func rank(_ candidate: (id: Int64, value: String)) -> (Int, Int, Int) {
                let parsed = PlayerName(candidate.value)
                let hasFide = tags[candidate.id]?[name + "FideId"].map { !isPlaceholder($0, tag: "FideId") } ?? false
                let initials = parsed.given.contains { $0.count == 1 } || parsed.given.isEmpty
                return (hasFide ? 1 : 0, initials ? 0 : 1, parsed.given.joined().count)
            }
            let best = keeperFirst.map(rank).max { $0 < $1 }!
            return keeperFirst.first { rank($0) == best }
        default:
            return keeperFirst.first
        }
    }

    /// Tags whose disagreement is reported. Provenance tags (`Source`,
    /// `ImportDate`, `IdentityEvidence…`) and layout tags are not.
    public static let checkedTags: Set<String> = [
        "Event", "Site", "Date", "Round", "White", "Black", "Result", "WhiteElo", "BlackElo",
        "WhiteFideId", "BlackFideId", "WhiteTitle", "BlackTitle", "ECO", "FEN", "EventDate",
    ]

    private static func conflicting(_ name: String, _ values: [String]) -> Bool {
        guard checkedTags.contains(name) else { return false }
        switch name {
        case "Date", "EventDate":
            let dates = values.map(PGNDate.init)
            return dates.contains { a in dates.contains { !a.isCompatible(with: $0) } }
        case "White", "Black":
            let keys = Set(values.map { PlayerName($0).matchKey })
            return keys.count > 1
        case "Event", "Site":
            let folded = values.map { NameFolding.fold($0).filter(\.isLetter) }
            return folded.contains { a in folded.contains { !a.contains($0) && !$0.contains(a) } }
        default:
            return true
        }
    }
}
