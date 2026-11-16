import Testing
@testable import ChessDatabaseQuality

struct PlayerDirectoryTests {
    @Test func sameFideIDIsCertain() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Le Phan Hoang Quan"), fideID: 12432881, elo: 2184, year: 2025)
        directory.observe(PlayerName("Phan Hoang Quan, Le"), fideID: 12432881, elo: 2190, year: 2025)
        let proposals = directory.aliasProposals()
        #expect(proposals.count == 1)
        #expect(proposals.first?.confidence == .certain)
    }

    @Test func initialsAndTransliterationAreLikely() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Aleksandrov, Aleksej"), fideID: 13500139, elo: 2409, year: 2024)
        directory.observe(PlayerName("Aleksandrov, Aleksej"), fideID: 13500139, elo: 2420, year: 2025)
        directory.observe(PlayerName("Alexandrov, A."), fideID: nil, elo: 2400, year: 2025)
        directory.observe(PlayerName("Aleksandrov, Alexei"), fideID: nil, elo: nil, year: nil)
        let proposals = directory.aliasProposals()
        #expect(proposals.count == 3)
        let likely = proposals.filter { $0.confidence == .likely }
        #expect(likely.contains { $0.alias.normalized == "alexandrov, a" })
        // The spelling with the FIDE ID and full given name is canonical.
        #expect(likely.allSatisfy { $0.canonical.normalized == "aleksandrov, aleksej" })
    }

    @Test func differentFideIDsAreNeverAliases() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Wang, Hao"), fideID: 8603405, elo: 2700, year: 2020)
        directory.observe(PlayerName("Wang, H."), fideID: 8601234, elo: 2700, year: 2020)
        #expect(directory.aliasProposals().isEmpty)
    }

    @Test func eloGapRejectsAlias() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Smith, John"), fideID: nil, elo: 2500, year: 2020)
        directory.observe(PlayerName("Smith, J."), fideID: nil, elo: 1500, year: 2020)
        #expect(directory.aliasProposals().isEmpty)
    }

    @Test func similarSpellingIsPossibleWithoutContext() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Nepomniachtchi, Ian"), fideID: nil, elo: nil, year: nil)
        directory.observe(PlayerName("Nepomnyashchy, Ian"), fideID: nil, elo: nil, year: nil)
        let proposals = directory.aliasProposals()
        #expect(proposals.count == 1)
        #expect(proposals.first?.confidence == .possible)
    }

    @Test func swappedOrderIsProposed() {
        var directory = PlayerDirectory()
        directory.observe(PlayerName("Ding Liren"), fideID: 8603677, elo: 2780, year: 2023)
        directory.observe(PlayerName("Liren, Ding"), fideID: nil, elo: 2780, year: 2023)
        let proposals = directory.aliasProposals()
        #expect(proposals.count == 1)
        #expect(proposals.first?.reasons.contains("mismos nombres en otro orden") == true)
    }
}
