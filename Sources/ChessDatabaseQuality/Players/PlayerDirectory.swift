//
//  PlayerDirectory.swift
//  ChessDatabaseQuality
//

import Foundation

/// One spelling of a player name in the database, with the context seen
/// next to it.
public struct PlayerVariant: Hashable, Sendable, Codable {
    /// `surname, given`, folded.
    public var normalized: String
    /// Up to three spellings as they appear in the tags.
    public var rawSamples: [String]
    public var games: Int
    /// FIDE IDs seen with this spelling (homonyms can have several).
    public var fideIDs: [Int]
    public var eloMin: Int?
    public var eloMax: Int?
    public var yearMin: Int?
    public var yearMax: Int?
}

/// How sure an alias proposal is.
public enum AliasConfidence: String, Sendable, Codable, Comparable, CaseIterable {
    /// Same FIDE ID.
    case certain
    /// Same name up to formatting, initials or transliteration, and the
    /// Elo and years agree.
    case likely
    /// Similar names without contradicting context.
    case possible

    private var rank: Int {
        switch self {
        case .certain: 0
        case .likely: 1
        case .possible: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// «Possibly the same person»: two spellings to review, with the one to keep.
public struct AliasProposal: Hashable, Sendable, Codable {
    public var canonical: PlayerVariant
    public var alias: PlayerVariant
    public var confidence: AliasConfidence
    /// Name similarity, 0 to 1.
    public var score: Double
    public var reasons: [String]
}

/// Options for ``PlayerDirectory/aliasProposals(options:)``.
public struct AliasOptions: Sendable {
    /// Minimum name similarity to propose an alias.
    public var minimumScore = 0.92
    /// Name similarity from which an alias is `likely` when the context agrees.
    public var likelyScore = 0.97
    /// Larger Elo gaps between the two spellings reject the alias.
    public var maximumEloGap = 300
    /// Larger gaps between the active years reject the alias.
    public var maximumYearGap = 20
    /// Blocks larger than this are split by the full first given name.
    public var maximumBlockSize = 400

    public init() {}
}

/// Collects every player spelling of a database and proposes aliases.
///
/// Blocking: spellings are compared only inside a block of the first three
/// letters of the transliterated surname plus first initial, a block of
/// its last three letters plus first initial, and a block of the
/// order-free token set (`Ding Liren` / `Liren Ding`). Spellings that share
/// a FIDE ID are always aliases; two spellings with different FIDE IDs are
/// never proposed, whatever the name similarity (the FIDE ID decides).
public struct PlayerDirectory: Sendable {
    struct Entry: Sendable {
        var name: PlayerName
        var variant: PlayerVariant
    }

    /// Transliteration keys computed once per spelling.
    struct Features: Sendable {
        var surnameKey: String
        var foldedSurname: String
        var surnameTokens: [String]
        var given: [String]
        /// Whether each given name is written as an initial (decided on the
        /// spelling, not on the key: `Yiyi` folds to `i` but is a name).
        var givenIsInitial: [Bool]
        var tokenSetKey: String?
        var hasInitials: Bool

        init(_ name: PlayerName) {
            surnameKey = name.surnameKey
            foldedSurname = name.foldedSurname
            surnameTokens = name.coreSurname.map(NameFolding.transliterationKey)
            given = name.givenKey
            givenIsInitial = name.given.map { $0.count == 1 }
            tokenSetKey = name.tokenSetKey
            hasInitials = givenIsInitial.contains(true)
        }

        /// Only initials, or no given name at all.
        var onlyInitials: Bool { givenIsInitial.allSatisfy { $0 } }
    }

    private var indexByNormalized: [String: Int] = [:]
    private var entries: [Entry] = []

    public init() {}

    public var variantCount: Int { entries.count }
    public var variants: [PlayerVariant] { entries.map(\.variant) }

    /// Records one appearance of a player in a game.
    public mutating func observe(_ name: PlayerName, fideID: Int?, elo: Int?, year: Int?) {
        guard !name.isUnknown else { return }
        let key = name.normalized
        let index: Int
        if let existing = indexByNormalized[key] {
            index = existing
        } else {
            index = entries.count
            indexByNormalized[key] = index
            entries.append(Entry(name: name, variant: PlayerVariant(
                normalized: key, rawSamples: [], games: 0, fideIDs: [],
                eloMin: nil, eloMax: nil, yearMin: nil, yearMax: nil
            )))
        }
        var variant = entries[index].variant
        variant.games += 1
        if variant.rawSamples.count < 3, !variant.rawSamples.contains(name.raw) {
            variant.rawSamples.append(name.raw)
        }
        if let fideID, !variant.fideIDs.contains(fideID), variant.fideIDs.count < 8 {
            variant.fideIDs.append(fideID)
            variant.fideIDs.sort()
        }
        if let elo {
            variant.eloMin = min(variant.eloMin ?? elo, elo)
            variant.eloMax = max(variant.eloMax ?? elo, elo)
        }
        if let year {
            variant.yearMin = min(variant.yearMin ?? year, year)
            variant.yearMax = max(variant.yearMax ?? year, year)
        }
        entries[index].variant = variant
    }

    /// Spellings that are possibly the same person, most certain first.
    public func aliasProposals(options: AliasOptions = AliasOptions()) -> [AliasProposal] {
        var proposals: [AliasProposal] = []
        var seen = Set<UInt64>()
        func pairKey(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }

        let features = entries.map { Features($0.name) }

        // 1. Same FIDE ID: certain.
        var byFide: [Int: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for id in entry.variant.fideIDs { byFide[id, default: []].append(index) }
        }
        for (id, members) in byFide where members.count > 1 {
            let canonical = members.max { preference(entries[$0].variant, entries[$1].variant) }!
            for member in members where member != canonical {
                guard seen.insert(pairKey(canonical, member)).inserted else { continue }
                let score = Self.nameScore(features[canonical], features[member])
                proposals.append(AliasProposal(
                    canonical: entries[canonical].variant, alias: entries[member].variant,
                    confidence: .certain, score: score, reasons: ["misma FIDE ID \(id)"]
                ))
            }
        }

        // 2. Name blocks.
        var blocks: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for block in entry.name.blockKeys { blocks[block, default: []].append(index) }
            if let tokens = entry.name.tokenSetKey { blocks["#" + tokens, default: []].append(index) }
        }
        for (_, members) in blocks where members.count > 1 {
            for group in split(members, options: options) {
                for i in 0..<group.count {
                    for j in (i + 1)..<group.count {
                        let a = group[i], b = group[j]
                        guard !seen.contains(pairKey(a, b)) else { continue }
                        if let proposal = evaluate(a, b, features: features, options: options) {
                            seen.insert(pairKey(a, b))
                            proposals.append(proposal)
                        }
                    }
                }
            }
        }
        return proposals.sorted {
            ($0.confidence, -$0.score, $0.canonical.normalized) < ($1.confidence, -$1.score, $1.canonical.normalized)
        }
    }

    private func split(_ members: [Int], options: AliasOptions) -> [[Int]] {
        guard members.count > options.maximumBlockSize else { return [members] }
        // Huge blocks ("wang,h"): only compare spellings that share the full
        // first given name, or that write it as an initial.
        var groups: [String: [Int]] = [:]
        var initialsOnly: [Int] = []
        for member in members {
            let given = entries[member].name.givenKey.first ?? ""
            if given.count <= 1 { initialsOnly.append(member) } else { groups[given, default: []].append(member) }
        }
        return groups.values.filter { $0.count > 1 } + (initialsOnly.count > 1 && initialsOnly.count <= options.maximumBlockSize ? [initialsOnly] : [])
    }

    private func evaluate(_ a: Int, _ b: Int, features: [Features], options: AliasOptions) -> AliasProposal? {
        let va = entries[a].variant, vb = entries[b].variant
        // The FIDE ID decides: different IDs are different people.
        if !va.fideIDs.isEmpty, !vb.fideIDs.isEmpty {
            return nil
        }
        let fa = features[a], fb = features[b]
        let score = Self.nameScore(fa, fb)
        guard score >= options.minimumScore else { return nil }

        var reasons: [String] = []
        var consistent = false
        if let aMin = va.eloMin, let aMax = va.eloMax, let bMin = vb.eloMin, let bMax = vb.eloMax {
            let gap = max(0, max(aMin, bMin) - min(aMax, bMax))
            if gap > options.maximumEloGap { return nil }
            if gap <= 150 { consistent = true; reasons.append("Elo compatible (\(aMin)–\(aMax) / \(bMin)–\(bMax))") }
        }
        if let aMin = va.yearMin, let aMax = va.yearMax, let bMin = vb.yearMin, let bMax = vb.yearMax {
            let gap = max(0, max(aMin, bMin) - min(aMax, bMax))
            if gap > options.maximumYearGap { return nil }
            if gap <= 2 { reasons.append("años activos compatibles") } else { consistent = false }
        }
        if fa.surnameKey == fb.surnameKey && entries[a].name.surname != entries[b].name.surname {
            reasons.append("misma transliteración del apellido")
        }
        if fa.tokenSetKey != nil, fa.tokenSetKey == fb.tokenSetKey, fa.surnameKey != fb.surnameKey {
            reasons.append("mismos nombres en otro orden")
        }
        if fa.hasInitials != fb.hasInitials {
            reasons.append("inicial frente a nombre completo")
        }
        if !va.fideIDs.isEmpty || !vb.fideIDs.isEmpty { reasons.append("FIDE ID solo en una grafía") }
        reasons.insert("similitud \(String(format: "%.2f", score))", at: 0)

        let confidence: AliasConfidence = score >= options.likelyScore && consistent ? .likely : .possible
        let (canonical, alias) = preference(va, vb) ? (vb, va) : (va, vb)
        return AliasProposal(canonical: canonical, alias: alias, confidence: confidence, score: score, reasons: reasons)
    }

    /// `true` when `b` is a better canonical spelling than `a`.
    private func preference(_ a: PlayerVariant, _ b: PlayerVariant) -> Bool {
        func rank(_ v: PlayerVariant) -> (Int, Int, Int, Int) {
            let hasInitials = v.normalized.split(separator: ",").last.map { part in
                part.split(separator: " ").contains { $0.count == 1 }
            } ?? true
            return (v.fideIDs.isEmpty ? 0 : 1, hasInitials ? 0 : 1, v.games, v.normalized.count)
        }
        return rank(a) < rank(b)
    }

    /// Name similarity: 55 % surname, 45 % given names. Initials match any
    /// name with that first letter; extra middle names are ignored.
    public static func nameScore(_ a: PlayerName, _ b: PlayerName) -> Double {
        nameScore(Features(a), Features(b))
    }

    static func nameScore(_ a: Features, _ b: Features) -> Double {
        if let ta = a.tokenSetKey, ta == b.tokenSetKey { return 1 }
        let surnameScore: Double
        if a.surnameKey == b.surnameKey {
            surnameScore = 1
        } else if isPartialSurname(a.surnameTokens, of: b.surnameTokens) || isPartialSurname(b.surnameTokens, of: a.surnameTokens) {
            // One of two surnames: `Lopez Gil` / `Lopez`, `Cinta Larga` / `Larga`.
            surnameScore = 0.95
        } else {
            surnameScore = max(
                JaroWinkler.similarity(a.surnameKey, b.surnameKey),
                JaroWinkler.similarity(a.foldedSurname, b.foldedSurname)
            )
        }
        // An initial says little: with initials only, the surname must be
        // (almost) the same.
        if (a.onlyInitials || b.onlyInitials) && surnameScore < 0.95 { return 0.55 * surnameScore }
        let ga = a.given, gb = b.given
        let givenScore: Double
        if ga.isEmpty || gb.isEmpty {
            givenScore = ga.isEmpty && gb.isEmpty ? 1 : 0.85
        } else {
            var total = 0.0
            let count = min(ga.count, gb.count)
            for i in 0..<count {
                let x = ga[i], y = gb[i]
                if a.givenIsInitial[i] || b.givenIsInitial[i] {
                    total += x.first == y.first ? 1 : 0
                } else {
                    total += JaroWinkler.similarity(x, y)
                }
            }
            givenScore = total / Double(count) * (ga.count == gb.count ? 1 : 0.98)
        }
        return 0.55 * surnameScore + 0.45 * givenScore
    }

    /// `short` is the start or the end of `long`, which has more tokens.
    private static func isPartialSurname(_ short: [String], of long: [String]) -> Bool {
        guard !short.isEmpty, short.count < long.count else { return false }
        return Array(long.prefix(short.count)) == short || Array(long.suffix(short.count)) == short
    }
}
