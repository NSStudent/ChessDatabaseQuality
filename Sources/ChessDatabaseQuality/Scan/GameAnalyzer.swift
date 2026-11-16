//
//  GameAnalyzer.swift
//  ChessDatabaseQuality
//

import FischerCore
import Foundation

/// Validation thresholds.
public struct ValidationOptions: Sendable {
    /// Valid Elo range. `0` and empty values mean «unrated» and are ignored.
    public var eloRange = 1000...2900
    public var minimumYear = 1475
    /// Dates after this year are impossible. Defaults to next year.
    public var latestYear = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1
    /// Tags that must be present (the seven tag roster).
    public var requiredTags: [String] = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

    public init() {}
}

/// Everything learned from one game of the source.
public struct AnalyzedGame: Sendable {
    public var index: Int
    public var byteOffset: Int64
    public var byteLength: Int
    /// `false` when the tag section could not be read; the game is skipped.
    public var isReadable: Bool
    public var white: PlayerName
    public var black: PlayerName
    public var whiteFideID: Int?
    public var blackFideID: Int?
    public var whiteElo: Int?
    public var blackElo: Int?
    public var date: PGNDate
    public var event: String
    public var headerScore: Int
    /// Legal moves read; the game is cut at the first illegal move.
    public var moves: [UInt16]
    /// Start position and the position after each move.
    public var positionKeys: [UInt64]
    public var startHash: UInt64
    public var issues: [ValidationIssue]

    /// `White - Black, Event, Date`.
    public var label: String {
        let w = white.raw.isEmpty ? "?" : white.raw, b = black.raw.isEmpty ? "?" : black.raw
        return "\(w) – \(b), \(event.isEmpty ? "?" : event), \(date)"
    }

    public func summary() -> GameSummary {
        GameSummary(
            id: Int64(index), white: PlayerKey(white), black: PlayerKey(black), date: date,
            headerScore: headerScore, startHash: startHash, moves: moves, positionKeys: positionKeys
        )
    }

    public var gameIssues: GameIssues {
        GameIssues(gameIndex: index, byteOffset: byteOffset, label: label, issues: issues)
    }
}

/// Reads, replays and validates one game.
public struct GameAnalyzer: Sendable {
    public var options: ValidationOptions

    public init(options: ValidationOptions = ValidationOptions()) {
        self.options = options
    }

    public func analyze(_ chunk: PGNGameChunk) -> AnalyzedGame {
        var game = AnalyzedGame(
            index: chunk.index, byteOffset: chunk.startByteOffset,
            byteLength: Int(chunk.endByteOffset - chunk.startByteOffset), isReadable: true,
            white: PlayerName(""), black: PlayerName(""), date: PGNDate(nil), event: "",
            headerScore: 0, moves: [], positionKeys: [], startHash: 0, issues: []
        )
        let basic: BasicPGNGame
        do {
            basic = try chunk.basicGame()
        } catch {
            game.isReadable = false
            let firstLine = chunk.text.prefix { $0 != "\n" }.prefix(100)
            game.issues.append(ValidationIssue(.unreadableGame, "cabecera ilegible: «\(firstLine)»"))
            return game
        }
        var tags: [String: String] = [:]
        for (tag, value) in basic.tags { tags[tag.rawValue] = value }
        analyzeTags(tags, into: &game)
        replay(movetext: basic.movetext, tags: tags, into: &game)
        return game
    }

    // MARK: Tags

    private func analyzeTags(_ tags: [String: String], into game: inout AnalyzedGame) {
        let missing = options.requiredTags.filter { tags[$0] == nil }
        if !missing.isEmpty {
            game.issues.append(ValidationIssue(.missingRequiredTag, missing.joined(separator: ", ")))
        }
        game.white = PlayerName(tags["White"] ?? "")
        game.black = PlayerName(tags["Black"] ?? "")
        game.event = tags["Event"] ?? ""

        let date = PGNDate(tags["Date"])
        game.date = date
        if !date.isWellFormed {
            game.issues.append(ValidationIssue(.malformedDate, "Date «\(tags["Date"] ?? "")»"))
        } else if let problem = date.impossibility(minimumYear: options.minimumYear, latestYear: options.latestYear) {
            game.issues.append(ValidationIssue(.impossibleDate, "Date «\(tags["Date"] ?? "")»: \(problem)"))
        }

        var eloProblems: [String] = []
        func elo(_ name: String) -> Int? {
            guard let raw = tags[name]?.trimmingCharacters(in: .whitespaces),
                  !MergeProposalBuilder.isPlaceholder(raw, tag: name) else { return nil }
            guard let value = Int(raw) else {
                eloProblems.append("\(name) «\(raw)»")
                return nil
            }
            guard options.eloRange.contains(value) else {
                eloProblems.append("\(name) \(value)")
                return nil
            }
            return value
        }
        game.whiteElo = elo("WhiteElo")
        game.blackElo = elo("BlackElo")
        if !eloProblems.isEmpty {
            game.issues.append(ValidationIssue(.eloOutOfRange, eloProblems.joined(separator: ", ")))
        }
        func fide(_ name: String) -> Int? {
            tags[name].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
        }
        game.whiteFideID = fide("WhiteFideId")
        game.blackFideID = fide("BlackFideId")

        if let result = tags["Result"], !["1-0", "0-1", "1/2-1/2", "*"].contains(result.trimmingCharacters(in: .whitespaces)) {
            game.issues.append(ValidationIssue(.invalidResult, "Result «\(result)»"))
        }

        var score = 0
        for (name, value) in tags where !MergeProposalBuilder.isPlaceholder(value, tag: name) { score += 1 }
        score += (game.whiteFideID == nil ? 0 : 2) + (game.blackFideID == nil ? 0 : 2)
        score += (game.whiteElo == nil ? 0 : 1) + (game.blackElo == nil ? 0 : 1)
        score += date.completeness
        if game.event.count > 3 { score += 1 }
        game.headerScore = score
    }

    // MARK: Moves

    private func replay(movetext: String, tags: [String: String], into game: inout AnalyzedGame) {
        let scanned = MovetextScanner.scan(movetext)
        let resultTag = tags["Result"]?.trimmingCharacters(in: .whitespaces)

        if scanned.isUnbalanced {
            game.issues.append(ValidationIssue(.unbalancedMovetext, "llaves o paréntesis sin cerrar"))
        }
        if scanned.termination == nil {
            game.issues.append(ValidationIssue(.missingTermination, "el movetext acaba sin resultado tras \(scanned.moves.count) medias jugadas"))
        } else if let resultTag, let termination = scanned.termination, resultTag != termination,
                  ["1-0", "0-1", "1/2-1/2", "*"].contains(resultTag) {
            game.issues.append(ValidationIssue(.resultTagMismatch, "Result «\(resultTag)», movetext «\(termination)»"))
        }

        var board: Game
        if let fen = tags["FEN"], !fen.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let position = Position(fen: fen.trimmingCharacters(in: .whitespaces)),
                  let loaded = try? Game(position: position) else {
                game.issues.append(ValidationIssue(.invalidFEN, "FEN «\(fen)»"))
                return
            }
            board = loaded
            game.startHash = StableHash.fnv1a64(position.fen())
        } else {
            board = Game()
        }

        var moves: [UInt16] = []
        var keys: [UInt64] = []
        moves.reserveCapacity(scanned.moves.count)
        keys.reserveCapacity(scanned.moves.count + 1)
        keys.append(Self.positionKey(board))
        var truncated = false
        for (offset, san) in scanned.moves.enumerated() {
            var failure: String?
            switch board.resolveResult(san: san) {
            case .success(let resolved):
                do {
                    try board.execute(uncheckedMove: resolved.move) { resolved.promotion ?? .queen }
                    moves.append(GameSummary.encode(
                        from: resolved.move.start.rawValue, to: resolved.move.end.rawValue,
                        promotion: Self.promotionCode(resolved.promotion)
                    ))
                    keys.append(Self.positionKey(board))
                } catch {
                    failure = "jugada ilegal"
                }
            case .failure(let error):
                failure = Self.describe(error)
            }
            if let failure {
                truncated = true
                let ply = offset + 1
                let number = (ply + 1) / 2
                let notation = ply % 2 == 1 ? "\(number). \(san)" : "\(number)... \(san)"
                game.issues.append(ValidationIssue(.illegalMove, "\(notation): \(failure); cortada en \(offset) medias jugadas", ply: ply))
                break
            }
        }
        game.moves = moves
        game.positionKeys = keys

        if let plyCount = tags["PlyCount"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
           plyCount != scanned.moves.count, !truncated {
            game.issues.append(ValidationIssue(.plyCountMismatch, "PlyCount \(plyCount), jugadas \(scanned.moves.count)"))
        }

        let result = resultTag.flatMap { ["1-0", "0-1", "1/2-1/2", "*"].contains($0) ? $0 : nil } ?? scanned.termination ?? "*"
        if moves.isEmpty, scanned.moves.isEmpty, result == "1-0" || result == "0-1" {
            game.issues.append(ValidationIssue(.noMovesDecisiveResult, "0 jugadas y resultado \(result)"))
        }
        guard !truncated, !moves.isEmpty else { return }
        if board.isCheckmate {
            let expected = board.playerTurn == .white ? "0-1" : "1-0"
            if result != expected {
                game.issues.append(ValidationIssue(
                    .resultContradictsMate, "mate de las \(expected == "1-0" ? "blancas" : "negras") y resultado \(result)", ply: moves.count
                ))
            }
        } else if board.isStalemate, result == "1-0" || result == "0-1" {
            game.issues.append(ValidationIssue(.resultContradictsStalemate, "ahogado y resultado \(result)", ply: moves.count))
        }
    }

    static func describe(_ error: SANResolutionError) -> String {
        switch error {
        case .invalidNotation: "notación no válida"
        case .notFound: "no hay pieza que pueda ir ahí"
        case .illegal: "jugada ilegal"
        case .ambiguous: "jugada ambigua"
        default: "\(error)"
        }
    }

    static func promotionCode(_ promotion: PromotionPiece?) -> Int {
        switch promotion {
        case nil: 0
        case .knight?: 1
        case .bishop?: 2
        case .rook?: 3
        case .queen?: 4
        }
    }

    private static let pieces = Piece.all

    /// A stable 64-bit key of the position: placement, side to move,
    /// castling rights and en passant square.
    public static func positionKey(_ game: Game) -> UInt64 {
        var hash: UInt64 = game.playerTurn == .white ? 0x243F_6A88_85A3_08D3 : 0x1319_8A2E_0370_7344
        let board = game.board
        for piece in pieces {
            var raw: UInt64 = 0
            for square in board.bitboard(for: piece) { raw |= 1 << UInt64(square.rawValue) }
            hash = StableHash.combine(hash, raw)
        }
        var castling: UInt64 = 0
        for right in game.castlingRights {
            switch right {
            case .whiteKingside: castling |= 1
            case .whiteQueenside: castling |= 2
            case .blackKingside: castling |= 4
            case .blackQueenside: castling |= 8
            }
        }
        // The en passant square counts only when a pawn can capture there
        // (as in Polyglot keys), so transpositions get the same key.
        var enPassant: UInt64 = 0
        if let target = game.enPassantTarget {
            let capturerRank = game.playerTurn == .white ? 4 : 3
            let pawn = Piece(pawn: game.playerTurn)
            for delta in [-1, 1] {
                let file = target.file.index + delta
                guard (0..<8).contains(file), let square = Square(rawValue: file + capturerRank * 8) else { continue }
                if board[square] == pawn { enPassant = UInt64(target.rawValue + 1) }
            }
        }
        hash = StableHash.combine(hash, castling << 8 | enPassant)
        return hash
    }
}
