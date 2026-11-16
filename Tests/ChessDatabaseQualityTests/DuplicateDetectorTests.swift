import Testing
@testable import ChessDatabaseQuality

/// Synthetic games: the position after each move is a hash of the moves so
/// far, so two games share a position exactly when they share the prefix.
private func game(
    _ id: Int64, _ white: String, _ black: String, date: String = "2024.05.01",
    moves: [UInt16], header: Int = 5
) -> GameSummary {
    var keys: [UInt64] = [StableHash.mix(1)]
    for move in moves { keys.append(StableHash.combine(keys.last!, UInt64(move))) }
    return GameSummary(
        id: id, white: PlayerKey(PlayerName(white)), black: PlayerKey(PlayerName(black)),
        date: PGNDate(date), headerScore: header, moves: moves, positionKeys: keys
    )
}

private func moves(_ seed: UInt64, _ count: Int) -> [UInt16] {
    (0..<count).map { UInt16(truncatingIfNeeded: StableHash.mix(seed &* 1000 &+ UInt64($0))) & 0x7FFF }
}

private func detect(_ games: [GameSummary]) throws -> DuplicateResult {
    var options = DuplicateOptions()
    options.partitions = 3
    options.bandPartitions = 2
    let detector = try DuplicateDetector(options: options)
    detector.add(games)
    return try detector.finish()
}

private func member(_ result: DuplicateResult, _ id: Int64) -> DuplicateMember? {
    result.groups.lazy.flatMap(\.members).first { $0.id == id }
}

struct DuplicateDetectorTests {
    let base = moves(1, 80)

    @Test func exactDuplicatesWithOtherSpellings() throws {
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", moves: base, header: 9),
            game(1, "Magnus Carlsen", "Caruana, F.", date: "2024.??.??", moves: base, header: 4),
            game(2, "Carlsen, Magnus", "Nakamura, Hikaru", moves: moves(2, 80)),
        ])
        #expect(result.groups.count == 1)
        #expect(result.groups.first?.keeper == 0)
        #expect(member(result, 1)?.relation == .exact)
        #expect(result.statistics.exact == 1)
    }

    @Test func subsumedGameIsAPrefix() throws {
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", moves: base),
            game(1, "Carlsen, M.", "Caruana, Fabiano", moves: Array(base.prefix(30)), header: 12),
        ])
        #expect(member(result, 1)?.relation == .subsumed)
        #expect(member(result, 1)?.duplicateOf == 0)
        #expect(result.groups.first?.keeper == 0)
    }

    @Test func nearDuplicateBySamePositionAtPly40() throws {
        let other = Array(base.prefix(40)) + moves(9, 12)
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", moves: base),
            game(1, "Carlsen, Magnus", "Caruana, Fabiano", moves: other),
        ])
        #expect(member(result, 1)?.relation == .near)
        #expect(member(result, 1)?.method == .positionAtPly)
    }

    @Test func nearDuplicateByMinHashAcrossMisspelledPair() throws {
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", moves: base),
            game(1, "Carslen, Magnus", "Caruana, Fabiano", moves: base),
            // Same moves, unrelated players: not a duplicate.
            game(2, "Smith, John", "Doe, Jane", moves: base),
        ])
        #expect(member(result, 1)?.relation == .near)
        #expect(member(result, 1)?.method == .minHash)
        #expect(member(result, 2) == nil)
        #expect(result.groups.first?.keeper != 2)
    }

    @Test func doubleSurnameInWesternOrderIsExact() throws {
        let result = try detect([
            game(0, "Fernandez Garcia, Jose Miguel", "Martin Clemente, Joel", moves: base),
            game(1, "Jose Miguel Fernandez Garcia", "Martin Clemente, J.", moves: base),
        ])
        #expect(member(result, 1)?.relation == .exact)
    }

    @Test func reorderedThreeWordNameIsFoundByMinHash() throws {
        let result = try detect([
            game(0, "Mohd Tarmizi, Nur Uzma", "Toh, Ding Yu", moves: base),
            game(1, "Mohd Tarmizi, N.", "Ding Yu Toh", moves: base),
        ])
        #expect(member(result, 1)?.relation == .near)
        #expect(member(result, 1)?.method == .minHash)
    }

    @Test func repeatedShortDrawOnOtherDatesIsNotADuplicate() throws {
        let draw = moves(3, 16)
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", date: "2019.01.10", moves: draw),
            game(1, "Carlsen, Magnus", "Caruana, Fabiano", date: "2021.06.20", moves: draw),
        ])
        #expect(result.groups.isEmpty)
    }

    @Test func longGameOnAnotherDateIsStillExact() throws {
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", date: "2019.01.10", moves: base),
            game(1, "Carlsen, Magnus", "Caruana, Fabiano", date: "2019.01.11", moves: base),
        ])
        #expect(member(result, 1)?.relation == .exact)
    }

    @Test func unknownPlayersNeedLongGames() throws {
        let short = moves(4, 20)
        let result = try detect([
            game(0, "?", "?", moves: short),
            game(1, "NN", "?", moves: short),
            game(2, "?", "?", moves: base),
            game(3, "?", "N.N.", moves: base),
        ])
        #expect(result.groups.count == 1)
        #expect(Set(result.groups[0].ids) == [2, 3])
    }

    @Test func chainsCollapseIntoOneGroup() throws {
        let result = try detect([
            game(0, "Carlsen, Magnus", "Caruana, Fabiano", moves: base),
            game(1, "Carlsen, Magnus", "Caruana, Fabiano", moves: base),
            game(2, "Carlsen, Magnus", "Caruana, Fabiano", moves: Array(base.prefix(50))),
            game(3, "Carslen, Magnus", "Caruana, Fabiano", moves: Array(base.prefix(50))),
        ])
        #expect(result.groups.count == 1)
        #expect(result.groups[0].members.count == 3)
        #expect(result.statistics.exact + result.statistics.subsumed + result.statistics.near == 3)
    }

    @Test func manyGamesManyPartitions() throws {
        var games: [GameSummary] = []
        for index in 0..<2000 {
            games.append(game(Int64(index), "Player\(index % 97), A", "Rival\(index % 89), B", moves: moves(UInt64(index), 60)))
        }
        // Plant ten exact duplicates.
        for index in 0..<10 {
            var copy = games[index * 100]
            copy.id = Int64(10_000 + index)
            games.append(copy)
        }
        let result = try detect(games)
        #expect(result.statistics.exact == 10)
        #expect(result.groups.count == 10)
        #expect(result.statistics.games == 2010)
    }
}

struct MergeProposalTests {
    @Test func keepsTheBestHeader() {
        let group = DuplicateGroup(keeper: 1, members: [DuplicateMember(id: 2, relation: .exact, duplicateOf: 1)])
        let tags: [Int64: [String: String]] = [
            1: ["Event": "Ch", "Site": "?", "Date": "2024.??.??", "White": "Carlsen, M.", "Black": "Caruana, Fabiano",
                "Result": "1-0", "WhiteElo": "2830", "PlyCount": "80"],
            2: ["Event": "Norway Chess 2024", "Site": "Stavanger NOR", "Date": "2024.05.27", "White": "Carlsen, Magnus",
                "WhiteFideId": "1503014", "Black": "Caruana, Fabiano", "Result": "1-0", "WhiteElo": "2831", "PlyCount": "79"],
        ]
        let proposal = MergeProposalBuilder.proposal(for: group, tags: tags)
        let value = { name in proposal.tags.first { $0.name == name }?.value }
        #expect(value("Event") == "Norway Chess 2024")
        #expect(value("Site") == "Stavanger NOR")
        #expect(value("Date") == "2024.05.27")
        #expect(value("White") == "Carlsen, Magnus")
        #expect(value("WhiteFideId") == "1503014")
        #expect(value("WhiteElo") == "2830")
        #expect(value("PlyCount") == "80")
        #expect(Array(proposal.tags.prefix(6).map(\.name)) == ["Event", "Site", "Date", "White", "Black", "Result"])
        #expect(proposal.conflicts.map(\.name) == ["WhiteElo"])
        #expect(proposal.remove == [2])
        #expect(Set(proposal.improvedTags) == ["Event", "Site", "Date", "White", "WhiteFideId"])
    }
}
