import Testing
@testable import ChessDatabaseQuality

struct PlayerNameTests {
    @Test(arguments: [
        ("Carlsen, Magnus", "Carlsen, M."),
        ("Carlsen, Magnus", "Magnus Carlsen"),
        ("Carlsen, Magnus", "M. Carlsen"),
        ("Carlsen, Magnus", "Carlsen M"),
        ("Carlsen, Magnus", "CARLSEN, Magnus"),
        ("Carlsen, Magnus", "GM Magnus Carlsen"),
        ("Carlsen, Magnus", "Carlsen, Magnus (NOR)"),
        ("van Wely, Loek", "Wely, Loek van"),
        ("van Wely, Loek", "Loek van Wely"),
        ("van Wely, Loek", "Van Wely, L."),
        ("Al-Modiahki, Mohamad", "Al Modiahki, M."),
        ("Ćmilytė, Viktorija", "Cmilyte, Viktorija"),
        ("Nguyen, Duc Tri", "Nguyen Duc Tri"),
        ("Grischuk, Alexander", "Grishchuk, Aleksandr"),
        ("Karpov, Anatoly", "Karpow, Anatolij"),
        ("Karpov, Anatoly", "Карпов, Анатолий"),
        ("Yakovenko, Dmitry", "Jakovenko, Dmitrij"),
        ("Tukmakov, Vladimir", "Toukmakov, Wladimir"),
        ("Vachier-Lagrave, Maxime", "Vachier Lagrave, M."),
        ("Müller, Jürgen", "Mueller, Juergen"),
        ("Yang, Le", "Le Yang"),
        ("Zhang, Xiao", "Xiao Zhang"),
        ("Ding, Liren", "Liren Ding"),
    ])
    func sameMatchKey(_ a: String, _ b: String) {
        #expect(PlayerName(a).matchKey == PlayerName(b).matchKey, "\(PlayerName(a).matchKey) vs \(PlayerName(b).matchKey)")
    }

    @Test func differentPeopleKeepDifferentKeys() {
        #expect(PlayerName("Carlsen, Magnus").matchKey != PlayerName("Carlsen, Henrik").matchKey)
        #expect(PlayerName("Kasparov, Garry").matchKey != PlayerName("Karpov, Anatoly").matchKey)
        #expect(PlayerName("Zhang, Wei").matchKey != PlayerName("Yang, Wei").matchKey)
        #expect(PlayerName("Zhu, Chen").matchKey != PlayerName("Yu, Chen").matchKey)
        #expect(PlayerName("Hou, Yifan").matchKey != PlayerName("Hu, Yifan").matchKey)
    }

    @Test func splitsSurnameAndGivenNames() {
        let name = PlayerName("Wely, Loek van")
        #expect(name.surname == ["van", "wely"])
        #expect(name.given == ["loek"])
        #expect(name.normalized == "van wely, loek")
        #expect(name.coreSurname == ["wely"])

        let initials = PlayerName("Fischer, R. J.")
        #expect(initials.given == ["r", "j"])
        #expect(initials.firstInitial == "r")

        let vietnamese = PlayerName("Le Quang Liem")
        #expect(vietnamese.surname == ["le"])
        #expect(vietnamese.given == ["quang", "liem"])
    }

    @Test(arguments: ["?", "", "NN", "N.N.", "N N", "-", "Unknown", "??"])
    func unknownPlayers(_ raw: String) {
        #expect(PlayerName(raw).isUnknown)
        #expect(PlayerName(raw).matchKey.isEmpty)
    }

    @Test func tokenSetKeyIgnoresOrder() {
        #expect(PlayerName("Ding Liren").tokenSetKey == PlayerName("Liren Ding").tokenSetKey)
        #expect(PlayerName("Ding, L.").tokenSetKey == nil)
    }

    @Test func transliterationKey() {
        let key = NameFolding.transliterationKey
        #expect(key("sergey") == key("sergei"))
        #expect(key("sergej") == key("sergei"))
        #expect(key("aleksandr") == key("alexandr"))
        #expect(key("grischuk") == key("grishchuk"))
        #expect(key("khalifman") == key("halifman"))
        #expect(key("karpoff") == key("karpov"))
        #expect(key("kasparov") != key("karpov"))
    }

    @Test func folding() {
        #expect(NameFolding.fold("Łukasz Ćwiek") == "lukasz cwiek")
        #expect(NameFolding.fold("Straße") == "strasse")
        #expect(NameFolding.fold("Bjørn") == "bjorn")
    }

    @Test func jaroWinkler() {
        #expect(abs(JaroWinkler.similarity("martha", "marhta") - 0.961) < 0.001)
        #expect(abs(JaroWinkler.similarity("dixon", "dicksonx") - 0.813) < 0.001)
        #expect(JaroWinkler.similarity("abc", "abc") == 1)
        #expect(JaroWinkler.similarity("abc", "xyz") == 0)
    }
}
