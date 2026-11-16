//
//  Fabricator.swift
//  ChessDatabaseQuality
//

import FischerCore
import Foundation

/// What the fabricator planted, to measure recall.
public struct FabricationTruth: Sendable, Codable, CustomStringConvertible {
    public struct Planted: Sendable, Codable, Hashable {
        /// Index of the original game in the output file.
        public var original: Int
        /// Index of the fabricated game in the output file.
        public var copy: Int
        /// `exact`, `subsumed`, `near-position`, `near-minhash`, `repeated-draw`
        /// (must NOT be grouped) or a validation issue kind.
        public var kind: String
    }

    public var originals = 0
    public var games = 0
    public var planted: [Planted] = []

    public var description: String {
        var counts: [String: Int] = [:]
        for item in planted { counts[item.kind, default: 0] += 1 }
        return "partidas \(games) (originales \(originals)); " + counts.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}

/// Builds a PGN with planted duplicates, name variants and broken games
/// from the clean games of a source file.
public struct Fabricator {
    var state: UInt64

    public init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return StableHash.mix(state)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    struct Source {
        var tags: [(String, String)]
        var sans: [String]
    }

    /// Reads up to `games` readable, legal games of at least 50 plies.
    static func sources(from url: URL, games: Int) throws -> [Source] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var chunker = PGNByteChunker()
        var result: [Source] = []
        let analyzer = GameAnalyzer()
        while result.count < games, let block = try handle.read(upToCount: 1 << 20), !block.isEmpty {
            for chunk in chunker.consume(block) where result.count < games {
                let analyzed = analyzer.analyze(chunk)
                guard analyzed.isReadable, analyzed.moves.count >= 50,
                      !analyzed.issues.contains(where: { $0.kind.severity != .info }),
                      !analyzed.white.isUnknown, !analyzed.black.isUnknown,
                      analyzed.date.completeness == 3,
                      let basic = try? chunk.basicGame() else { continue }
                var tags = basic.tags.map { ($0.key.rawValue, $0.value) }
                tags.sort { lhs, rhs in
                    let roster = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
                    return (roster.firstIndex(of: lhs.0) ?? 99, lhs.0) < (roster.firstIndex(of: rhs.0) ?? 99, rhs.0)
                }
                result.append(Source(tags: tags, sans: MovetextScanner.scan(basic.movetext).moves))
            }
        }
        return result
    }

    static func write(tags: [(String, String)], sans: [String], result: String, comment: String? = nil, wrap: Int = 80) -> String {
        var text = tags.map { "[\($0.0) \"\($0.1)\"]" }.joined(separator: "\n") + "\n\n"
        var line = ""
        var tokens: [String] = []
        for (index, san) in sans.enumerated() {
            if index % 2 == 0 { tokens.append("\(index / 2 + 1).") }
            tokens.append(san)
            if index == 3, let comment { tokens.append("{\(comment)}") }
        }
        tokens.append(result)
        for token in tokens {
            if !line.isEmpty, line.count + token.count + 1 > wrap {
                text += line + "\n"
                line = ""
            }
            line += line.isEmpty ? token : " " + token
        }
        return text + line + "\n\n"
    }

    static func value(_ tags: [(String, String)], _ name: String) -> String? {
        tags.first { $0.0 == name }?.1
    }

    static func setting(_ tags: [(String, String)], _ name: String, _ value: String?) -> [(String, String)] {
        var copy = tags.filter { $0.0 != name }
        if let value {
            let index = tags.firstIndex { $0.0 == name } ?? copy.count
            copy.insert((name, value), at: min(index, copy.count))
        }
        return copy
    }

    /// A spelling of `name` with the same match key.
    mutating func variant(of name: String) -> String {
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let transliterated = Self.transliterate(name)
        var options: [String] = []
        if parts.count == 2, !parts[1].isEmpty {
            options.append("\(parts[1]) \(parts[0])")
            options.append("\(parts[0]), \(parts[1].prefix(1)).")
            options.append("\(parts[0].uppercased()), \(parts[1])")
        }
        let folded = name.folding(options: .diacriticInsensitive, locale: nil)
        if folded != name { options.append(folded) }
        if transliterated != name { options.append(transliterated) }
        guard !options.isEmpty else { return name }
        return options[int(0...(options.count - 1))]
    }

    static func transliterate(_ name: String) -> String {
        for (from, to) in [("ks", "x"), ("x", "ks"), ("ey", "ei"), ("ei", "ey"), ("sch", "sh"), ("ov", "ow"), ("v,", "ff,")] {
            if name.contains(from) { return name.replacingOccurrences(of: from, with: to) }
        }
        return name
    }

    /// A misspelling of the surname that changes its match key: two
    /// letters swapped, or a letter inserted.
    mutating func typo(of name: String) -> String {
        let key = PlayerName(name).matchKey
        var characters = Array(name)
        let surnameEnd = characters.firstIndex(of: ",") ?? characters.count
        if surnameEnd >= 4 {
            for _ in 0..<12 {
                var candidate = characters
                let index = int(1...(surnameEnd - 2))
                guard candidate[index].isLetter, candidate[index + 1].isLetter else { continue }
                candidate.swapAt(index, index + 1)
                let text = String(candidate)
                if PlayerName(text).matchKey != key { return text }
            }
        }
        characters.insert("r", at: min(2, surnameEnd))
        return String(characters)
    }

    /// Writes the fabricated file and returns what was planted.
    public mutating func fabricate(source: URL, output: URL, games: Int) throws -> FabricationTruth {
        let sources = try Self.sources(from: source, games: games)
        var truth = FabricationTruth(originals: sources.count)
        var text = ""
        var index = 0
        func emit(_ game: String) -> Int {
            text += game
            defer { index += 1 }
            return index
        }

        for (number, source) in sources.enumerated() {
            let result = Self.value(source.tags, "Result") ?? "*"
            let original = emit(Self.write(tags: source.tags, sans: source.sans, result: result))
            let white = Self.value(source.tags, "White") ?? "?"
            let black = Self.value(source.tags, "Black") ?? "?"

            switch number % 8 {
            case 0:
                // Exact: reformatted, comment, other spellings, fewer tags.
                var tags = Self.setting(source.tags, "White", variant(of: white))
                tags = Self.setting(tags, "Black", variant(of: black))
                tags = Self.setting(tags, "WhiteFideId", nil)
                tags = Self.setting(tags, "Event", String((Self.value(tags, "Event") ?? "?").prefix(8)))
                let copy = emit(Self.write(tags: tags, sans: source.sans, result: result, comment: "copia", wrap: 60))
                truth.planted.append(.init(original: original, copy: copy, kind: "exact"))
            case 1:
                // Subsumed: the first moves only, result unknown.
                let length = source.sans.count - int(4...20)
                var tags = Self.setting(source.tags, "Result", "*")
                tags = Self.setting(tags, "PlyCount", String(length))
                tags = Self.setting(tags, "BlackElo", nil)
                let copy = emit(Self.write(tags: tags, sans: Array(source.sans.prefix(length)), result: "*"))
                truth.planted.append(.init(original: original, copy: copy, kind: "subsumed"))
            case 2:
                // Near by position: same first 42+ plies, then other moves.
                let keep = min(source.sans.count - 2, 42 + int(0...4))
                var game = Game()
                for san in source.sans.prefix(keep) { if let resolved = try? game.resolve(san: san) { try? game.execute(resolvedMove: resolved, considerHalfmoves: false) } }
                var sans = Array(source.sans.prefix(keep))
                let originalNext = source.sans[keep]
                for step in 0..<int(1...3) {
                    let legal = game.legalMoves(considerHalfmoves: false)
                    guard !legal.isEmpty else { break }
                    var choice = legal[int(0...(legal.count - 1))]
                    if step == 0, let san = try? game.san(for: choice), san.description == originalNext, legal.count > 1 {
                        choice = legal.first { (try? game.san(for: $0))?.description != originalNext } ?? choice
                    }
                    guard let san = try? game.san(for: choice) else { break }
                    sans.append(san.description)
                    try? game.execute(resolvedMove: choice, considerHalfmoves: false)
                }
                let tags = Self.setting(Self.setting(source.tags, "Result", "1/2-1/2"), "PlyCount", String(sans.count))
                let copy = emit(Self.write(tags: tags, sans: sans, result: "1/2-1/2"))
                truth.planted.append(.init(original: original, copy: copy, kind: "near-position"))
            case 3:
                // Near by MinHash: surname misspelled, so the pair differs.
                let tags = Self.setting(source.tags, "White", typo(of: white))
                let copy = emit(Self.write(tags: tags, sans: source.sans, result: result))
                truth.planted.append(.init(original: original, copy: copy, kind: "near-minhash"))
            case 4:
                // Repeated short draw: same pair and moves, another year. Not a duplicate.
                let sans = Array(source.sans.prefix(16))
                let year = Int((Self.value(source.tags, "Date") ?? "2000").prefix(4)) ?? 2000
                var first = Self.setting(source.tags, "Date", "\(year - 3).01.10")
                first = Self.setting(Self.setting(first, "Result", "1/2-1/2"), "PlyCount", "16")
                var second = Self.setting(first, "Date", "\(year - 1).06.20")
                second = Self.setting(second, "Round", "9")
                let a = emit(Self.write(tags: first, sans: sans, result: "1/2-1/2"))
                let b = emit(Self.write(tags: second, sans: sans, result: "1/2-1/2"))
                truth.planted.append(.init(original: a, copy: b, kind: "repeated-draw"))
            case 5:
                // Broken games, one problem each.
                let broken = number / 8 % 6
                switch broken {
                case 0:
                    var sans = source.sans
                    sans[20] = "Ke8"
                    let copy = emit(Self.write(tags: Self.setting(source.tags, "Round", "x\(number)"), sans: sans, result: result))
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.illegalMove.rawValue))
                case 1:
                    // Header cut in the middle of a tag.
                    let game = "[Event \"Fabricated\"]\n[Site \"?\"]\n[Date \"2020.01.01\"]\n[White \"\(white.prefix(4))\n"
                        + "[Black \"\(black)\"]\n[Result \"\(result)\"]\n\n" + Self.write(tags: [], sans: Array(source.sans.prefix(10)), result: result)
                        .trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                    let copy = emit(game)
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.unreadableGame.rawValue))
                case 2:
                    let tags = [("Event", "Fabricated"), ("Site", "?"), ("Date", "2020.01.01"), ("Round", "\(number)"),
                                ("White", white), ("Black", black), ("Result", "1-0")]
                    let copy = emit(Self.write(tags: tags, sans: ["f3", "e5", "g4", "Qh4#"], result: "1-0"))
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.resultContradictsMate.rawValue))
                case 3:
                    let tags = Self.setting(Self.setting(source.tags, "Round", "x\(number)"), "PlyCount", "0")
                    let copy = emit(Self.write(tags: tags, sans: [], result: "1-0").replacingOccurrences(of: "[Result \"\(result)\"]", with: "[Result \"1-0\"]"))
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.noMovesDecisiveResult.rawValue))
                case 4:
                    var tags = Self.setting(source.tags, "Date", "2025.02.30")
                    tags = Self.setting(Self.setting(tags, "WhiteElo", "4000"), "Round", "x\(number)")
                    tags = Self.setting(Self.setting(tags, "Site", nil), "White", typo(of: typo(of: white)) + "x")
                    let copy = emit(Self.write(tags: tags, sans: Array(source.sans.prefix(12)), result: result))
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.impossibleDate.rawValue))
                default:
                    let tags = Self.setting(source.tags, "Round", "x\(number)")
                    var game = Self.write(tags: tags, sans: Array(source.sans.prefix(30)), result: result)
                    game = String(game.dropLast(result.count + 2)) + "\n\n"
                    let copy = emit(game)
                    truth.planted.append(.init(original: original, copy: copy, kind: ValidationIssueKind.missingTermination.rawValue))
                }
            default:
                break
            }
        }
        truth.games = index
        try Data(text.utf8).write(to: output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(truth).write(to: output.appendingPathExtension("truth.json"))
        return truth
    }
}

extension FabricationTruth {
    public struct Evaluation: Sendable, Codable, CustomStringConvertible {
        /// Planted duplicates found in the same group as their original, by kind.
        public var found: [String: Int] = [:]
        public var planted: [String: Int] = [:]
        /// Planted repeated draws that were wrongly grouped.
        public var repeatedDrawsGrouped = 0
        /// Groups with two or more original games (unexpected).
        public var groupsJoiningOriginals = 0
        public var missed: [Planted] = []

        public var description: String {
            let kinds = planted.keys.sorted().map { "\($0) \(found[$0] ?? 0)/\(planted[$0] ?? 0)" }
            return "recuperadas: " + kinds.joined(separator: ", ")
                + "; empates repetidos agrupados: \(repeatedDrawsGrouped); grupos que unen originales: \(groupsJoiningOriginals)"
        }
    }

    /// Compares the planted duplicates with the groups found.
    public func evaluate(groups: [DuplicateGroup]) -> Evaluation {
        var groupOf: [Int64: Int] = [:]
        for (number, group) in groups.enumerated() { for id in group.ids { groupOf[id] = number } }
        var evaluation = Evaluation()
        var originals = Set<Int>()
        for item in planted where ["exact", "subsumed", "near-position", "near-minhash"].contains(item.kind) {
            originals.insert(item.original)
            evaluation.planted[item.kind, default: 0] += 1
            if let a = groupOf[Int64(item.original)], a == groupOf[Int64(item.copy)] {
                evaluation.found[item.kind, default: 0] += 1
            } else {
                evaluation.missed.append(item)
            }
        }
        for item in planted where item.kind == "repeated-draw" {
            if let a = groupOf[Int64(item.original)], a == groupOf[Int64(item.copy)] { evaluation.repeatedDrawsGrouped += 1 }
        }
        for group in groups where group.ids.filter({ originals.contains(Int($0)) }).count > 1 {
            evaluation.groupsJoiningOriginals += 1
        }
        return evaluation
    }
}
