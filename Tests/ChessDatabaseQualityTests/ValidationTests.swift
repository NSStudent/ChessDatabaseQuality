import FischerCore
import Foundation
import Testing
@testable import ChessDatabaseQuality

private func analyze(_ pgn: String) -> AnalyzedGame {
    let chunks = PGNGameSplitter.chunks(in: Data(pgn.utf8))
    return GameAnalyzer().analyze(chunks[0])
}

private func kinds(_ game: AnalyzedGame) -> Set<ValidationIssueKind> {
    Set(game.issues.map(\.kind))
}

private let roster = """
[Event "Test"]
[Site "Here"]
[Date "2024.01.02"]
[Round "1"]
[White "White, A"]
[Black "Black, B"]

"""

struct ValidationTests {
    @Test func resultContradictingMate() {
        let game = analyze(roster + "[Result \"1-0\"]\n\n1. f3 e5 2. g4 Qh4# 1-0\n")
        #expect(kinds(game) == [.resultContradictsMate])
    }

    @Test func mateWithTheRightResultIsClean() {
        let game = analyze(roster + "[Result \"0-1\"]\n\n1. f3 e5 2. g4 Qh4# 0-1\n")
        #expect(game.issues.isEmpty)
        #expect(game.moves.count == 4)
        #expect(game.positionKeys.count == 5)
    }

    @Test func illegalMoveCutsTheGame() {
        let game = analyze(roster + "[Result \"1-0\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Ke3 Nf6 1-0\n")
        #expect(kinds(game) == [.illegalMove])
        #expect(game.moves.count == 4)
        let issue = game.issues.first { $0.kind == .illegalMove }
        #expect(issue?.ply == 5)
        #expect(issue?.detail.hasPrefix("3. Ke3") == true)
    }

    @Test func stalemateWithDecisiveResult() {
        let game = analyze(roster + "[Result \"1-0\"]\n\n1. e3 a5 2. Qh5 Ra6 3. Qxa5 h5 4. h4 Rah6 5. Qxc7 f6 6. Qxd7+ Kf7 7. Qxb7 Qd3 8. Qxb8 Qh7 9. Qxc8 Kg6 10. Qe6 1-0\n")
        #expect(kinds(game) == [.resultContradictsStalemate])
    }

    @Test func noMovesWithDecisiveResult() {
        let game = analyze(roster + "[Result \"1-0\"]\n\n1-0\n")
        #expect(kinds(game) == [.noMovesDecisiveResult])
    }

    @Test func truncatedMovetext() {
        let game = analyze(roster + "[Result \"1-0\"]\n\n1. d4 d5 2. c4\n")
        #expect(kinds(game) == [.missingTermination])
    }

    @Test func tagProblems() {
        let pgn = """
        [Event "Test"]
        [Date "2023.02.29"]
        [White "A, B"]
        [Black "C, D"]
        [Result "1-0"]
        [WhiteElo "3100"]
        [BlackElo "abc"]
        [PlyCount "7"]

        1. e4 e5 1-0
        """
        let game = analyze(pgn)
        #expect(kinds(game) == [.impossibleDate, .eloOutOfRange, .missingRequiredTag, .plyCountMismatch])
        #expect(game.issues.first { $0.kind == .missingRequiredTag }?.detail == "Site, Round")
        #expect(game.whiteElo == nil)
    }

    @Test func movetextNoise() {
        let scanned = MovetextScanner.scan("1.e4 {a comment (with) parens} e5 (1...c5 2.Nf3) 2.Nf3!? $1 Nc6 ; rest\n% escape line\n3.Bb5 a6 e.p. 1/2-1/2")
        #expect(scanned.moves == ["e4", "e5", "Nf3!?", "Nc6", "Bb5", "a6"])
        #expect(scanned.termination == "1/2-1/2")
        #expect(!scanned.isUnbalanced)
        #expect(MovetextScanner.scan("1. e4 { open").isUnbalanced)
        #expect(MovetextScanner.scan("1. e4 (1. d4").isUnbalanced)
    }

    @Test func dates() {
        #expect(PGNDate("2024.??.??").isCompatible(with: PGNDate("2024.05.01")))
        #expect(!PGNDate("2024.05.02").isCompatible(with: PGNDate("2024.05.01")))
        #expect(PGNDate("????.??.??").isUnknown)
        #expect(PGNDate("2024/05/01").isWellFormed)
        #expect(PGNDate("2024.13.01").impossibility(latestYear: 2026) != nil)
        #expect(PGNDate("2024.02.29").impossibility(latestYear: 2026) == nil)
        #expect(PGNDate("2023.02.29").impossibility(latestYear: 2026) != nil)
        #expect(PGNDate("3024.01.01").impossibility(latestYear: 2026) != nil)
        #expect(!PGNDate("24 May 2024").isWellFormed)
        let date = PGNDate("2024.05.??")
        #expect(PGNDate(packed: date.packed) == date)
    }

    @Test func positionKeyIgnoresMoveOrder() throws {
        var a = Game()
        for san in ["Nf3", "Nf6", "d4", "d5"] { try a.execute(resolvedMove: a.resolve(san: san)) }
        var b = Game()
        for san in ["d4", "d5", "Nf3", "Nf6"] { try b.execute(resolvedMove: b.resolve(san: san)) }
        #expect(GameAnalyzer.positionKey(a) == GameAnalyzer.positionKey(b))
        var c = Game()
        for san in ["d4", "d5", "Nf3"] { try c.execute(resolvedMove: c.resolve(san: san)) }
        #expect(GameAnalyzer.positionKey(a) != GameAnalyzer.positionKey(c))
    }
}
