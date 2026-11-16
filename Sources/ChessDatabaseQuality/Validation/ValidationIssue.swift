//
//  ValidationIssue.swift
//  ChessDatabaseQuality
//

/// The kinds of problems found while validating a game.
public enum ValidationIssueKind: String, Sendable, Codable, CaseIterable, Comparable {
    /// The tag section could not be read; the game is skipped.
    case unreadableGame
    /// The `FEN` tag is not a valid position; the moves are not checked.
    case invalidFEN
    /// A move is illegal or cannot be read; the game is cut before it.
    case illegalMove
    /// The final position is checkmate but the result says otherwise.
    case resultContradictsMate
    /// The final position is stalemate but the result is decisive.
    case resultContradictsStalemate
    /// No moves and a decisive result (possibly a forfeit).
    case noMovesDecisiveResult
    /// The movetext does not end with a result: truncated PGN.
    case missingTermination
    /// The `Result` tag and the result at the end of the movetext differ.
    case resultTagMismatch
    /// The `PlyCount` tag does not match the moves read.
    case plyCountMismatch
    /// A `{` comment or a `(` variation is not closed.
    case unbalancedMovetext
    /// A date that cannot exist (month 13, February 30, year 3025).
    case impossibleDate
    /// A date that is not `YYYY.MM.DD`.
    case malformedDate
    /// An Elo that is not a number or is outside the valid range.
    case eloOutOfRange
    /// One of the seven tag roster tags is missing.
    case missingRequiredTag
    /// The `Result` tag is not `1-0`, `0-1`, `1/2-1/2` or `*`.
    case invalidResult

    /// `error` breaks the game (skipped or cut); `warning` is wrong data;
    /// `info` is incomplete data.
    public var severity: Severity {
        switch self {
        case .unreadableGame, .invalidFEN, .illegalMove: .error
        case .resultContradictsMate, .resultContradictsStalemate, .noMovesDecisiveResult, .missingTermination,
             .resultTagMismatch, .impossibleDate, .eloOutOfRange, .invalidResult, .unbalancedMovetext: .warning
        case .plyCountMismatch, .malformedDate, .missingRequiredTag: .info
        }
    }

    public enum Severity: String, Sendable, Codable, Comparable {
        case error, warning, info
        private var rank: Int { self == .error ? 0 : self == .warning ? 1 : 2 }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    /// Spanish label for the «salud de la base» report.
    public var title: String {
        switch self {
        case .unreadableGame: "Partida ilegible (cabecera rota), saltada"
        case .invalidFEN: "FEN inicial no válido"
        case .illegalMove: "Jugada ilegal o ilegible (partida cortada)"
        case .resultContradictsMate: "Resultado incoherente con el mate final"
        case .resultContradictsStalemate: "Resultado decisivo con ahogado final"
        case .noMovesDecisiveResult: "0 jugadas con resultado decisivo"
        case .missingTermination: "Movetext sin resultado final (PGN truncado)"
        case .resultTagMismatch: "Etiqueta Result distinta del final del movetext"
        case .plyCountMismatch: "PlyCount distinto de las jugadas"
        case .unbalancedMovetext: "Comentario o variante sin cerrar"
        case .impossibleDate: "Fecha imposible"
        case .malformedDate: "Fecha mal formada"
        case .eloOutOfRange: "Elo fuera de rango o no numérico"
        case .missingRequiredTag: "Falta una etiqueta obligatoria"
        case .invalidResult: "Etiqueta Result no válida"
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// One problem in one game.
public struct ValidationIssue: Hashable, Sendable, Codable {
    public var kind: ValidationIssueKind
    /// Human readable detail: the move, the tag, the value.
    public var detail: String
    /// The ply (1-based) where the problem is, for move problems.
    public var ply: Int?

    public init(_ kind: ValidationIssueKind, _ detail: String, ply: Int? = nil) {
        self.kind = kind
        self.detail = detail
        self.ply = ply
    }
}

/// The problems of one game, located in the source.
public struct GameIssues: Hashable, Sendable, Codable {
    /// Zero-based index of the game in the source.
    public var gameIndex: Int
    /// Byte offset of the game in the source.
    public var byteOffset: Int64
    /// `White - Black, Event, Date`, for the report.
    public var label: String
    public var issues: [ValidationIssue]
}
