import Foundation
import Testing
@testable import ChessDatabaseQuality

private func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "pgn", subdirectory: "Fixtures"))
}

struct AnalyzerTests {
    @Test func sampleFileHealthDuplicatesAndAliases() async throws {
        var options = QualityOptions()
        options.concurrency = 3
        options.batchSize = 4
        let analysis = try await DatabaseQualityAnalyzer(options: options).analyze(fileAt: try fixture("sample"))
        let report = analysis.report

        // The broken header is skipped; the games after it are still read.
        #expect(report.games == 9)
        #expect(report.health.skippedGames == 1)
        #expect(report.health.count(.unreadableGame) == 1)
        #expect(report.health.count(.illegalMove) == 1)
        #expect(report.health.count(.resultContradictsStalemate) == 1)
        #expect(report.health.count(.noMovesDecisiveResult) == 1)
        #expect(report.health.count(.missingTermination) == 1)
        #expect(report.health.count(.impossibleDate) == 1)
        #expect(report.health.count(.eloOutOfRange) == 1)
        #expect(report.health.count(.missingRequiredTag) == 1)
        #expect(report.health.count(.resultContradictsMate) == 1)
        #expect(analysis.gameIssues.count == report.games - report.health.cleanGames)

        // The Opera game: one exact copy (other spelling, comments,
        // variations) and one subsumed fragment.
        #expect(analysis.duplicateGroups.count == 1)
        let group = try #require(analysis.duplicateGroups.first)
        #expect(group.keeper == 0)
        #expect(Set(group.members.map(\.relation)) == [.exact, .subsumed])

        let proposal = try analysis.source.mergeProposal(for: group)
        let value = { name in proposal.tags.first { $0.name == name }?.value }
        #expect(value("Event") == "Paris Opera House")
        #expect(value("Date") == "1858.11.02")
        #expect(value("White") == "Morphy, Paul")
        #expect(value("Result") == "1-0")
        #expect(proposal.improvedTags == ["Event"])

        // Ivanchuk, Vassily / Ivanchuk, V. and Morphy, Paul / Morphy, P.
        let aliases = analysis.aliasProposals.map { [$0.canonical.normalized, $0.alias.normalized].sorted() }
        #expect(aliases.contains(["ivanchuk, v", "ivanchuk, vassily"]))
        #expect(aliases.contains(["morphy, p", "morphy, paul"]))

        let markdown = report.markdown()
        #expect(markdown.contains("# Salud de la base: sample.pgn"))
        #expect(markdown.contains("Jugada ilegal o ilegible"))
        _ = try report.json()
    }

    @Test func fabricatedDuplicatesAreFound() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cdq-fabricated-\(UUID().uuidString).pgn")
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: output.appendingPathExtension("truth.json"))
        }
        var fabricator = Fabricator(seed: 11)
        let truth = try fabricator.fabricate(source: try fixture("lumbras-sample"), output: output, games: 80)
        #expect(truth.originals >= 60)

        var options = QualityOptions()
        options.duplicates.partitions = 4
        options.duplicates.bandPartitions = 2
        let analysis = try await DatabaseQualityAnalyzer(options: options).analyze(fileAt: output)
        let evaluation = truth.evaluate(groups: analysis.duplicateGroups)
        #expect(evaluation.missed.isEmpty, "\(evaluation)")
        #expect(evaluation.repeatedDrawsGrouped == 0)
        #expect(evaluation.groupsJoiningOriginals == 0)
        #expect(analysis.report.health.count(.unreadableGame) == truth.planted.filter { $0.kind == "unreadableGame" }.count)
        #expect(analysis.report.health.count(.resultContradictsMate) == truth.planted.filter { $0.kind == "resultContradictsMate" }.count)
    }

    @Test func pgnTextEntryPoint() async throws {
        let analysis = try await DatabaseQualityAnalyzer().analyze(pgn: """
        [Event "A"]
        [Site "?"]
        [Date "2024.01.01"]
        [Round "1"]
        [White "A, B"]
        [Black "C, D"]
        [Result "1-0"]

        1. e4 e5 1-0
        """)
        #expect(analysis.report.games == 1)
        #expect(analysis.report.health.cleanGames == 1)
    }
}
