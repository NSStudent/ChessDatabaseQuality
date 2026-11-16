//
//  PlayerName.swift
//  ChessDatabaseQuality
//

import Foundation

/// A player name split into surname and given names, folded to ASCII.
///
/// Accepts the forms found in PGN databases and gives them the same keys:
///
/// | Input | `normalized` | `matchKey` |
/// |---|---|---|
/// | `Carlsen, Magnus` | `carlsen, magnus` | `carlsen,m` |
/// | `Carlsen, M.` | `carlsen, m` | `carlsen,m` |
/// | `Magnus Carlsen` | `carlsen, magnus` | `carlsen,m` |
/// | `van Wely, Loek` / `Wely, Loek van` / `Loek van Wely` | `van wely, loek` | `vely,l` |
/// | `Al-Modiahki, Mohamad` / `Al Modiahki, M.` | `al modiahki, …` | `modiahki,m` |
/// | `Nguyen Duc Tri` / `Nguyen, Duc Tri` | `nguyen, duc tri` | `nguyen,d` |
/// | `Fernandez Garcia, Jose` / `Jose Fernandez Garcia` | … | `garcia,i` |
/// | `Yang, Le` / `Le Yang` | … | `le+yang` |
///
/// The surname key drops particles (`van`, `de`, `al`…) and applies
/// ``NameFolding/transliterationKey(_:)``, so `Grischuk` and `Grishchuk`
/// share it. Keys are for matching only.
public struct PlayerName: Hashable, Sendable, Codable {
    /// The tag value as read.
    public let raw: String
    /// Folded surname tokens, particles included: `["van", "wely"]`.
    public let surname: [String]
    /// Folded given-name tokens; initials are one letter: `["m"]`.
    public let given: [String]

    /// Surname particles that are not part of the surname key.
    public static let particles: Set<String> = [
        "van", "der", "den", "de", "del", "della", "dello", "la", "le", "les", "du", "des", "di", "da",
        "dos", "das", "do", "von", "zu", "ter", "ten", "al", "el", "ben", "bin", "ibn", "abu", "y", "e", "st",
    ]

    /// Family names written first without a comma (Vietnamese, Chinese,
    /// Korean): `Nguyen Thanh Thuy Tien` is surname `nguyen`.
    public static let surnameFirstFamilies: Set<String> = [
        "nguyen", "tran", "le", "pham", "hoang", "huynh", "phan", "vu", "vo", "dang", "bui", "do", "ho",
        "ngo", "duong", "ly", "dao", "dinh", "truong", "lam", "mai", "trinh", "luong", "ta",
        "wang", "li", "zhang", "liu", "chen", "yang", "zhao", "huang", "zhou", "wu", "xu", "sun", "ma",
        "zhu", "hu", "guo", "he", "lin", "luo", "gao", "zheng", "liang", "xie", "song", "tang", "han",
        "feng", "deng", "cao", "peng", "zeng", "xiao", "tian", "dong", "pan", "yuan", "cai", "jiang",
        "yu", "ding", "wei", "ye", "bu", "ni", "tan", "lu", "qin", "hou", "shen", "zhai",
        "kim", "lee", "park", "choi", "jung", "kang", "cho", "yoon", "jang", "lim",
    ]

    static let unknownForms: Set<String> = ["", "?", "??", "???", "nn", "n n", "unknown", "-", "--", "x", "anonymous", "noname"]
    static let titles: Set<String> = ["gm", "im", "fm", "cm", "wgm", "wim", "wfm", "wcm", "dr", "prof", "mr", "mrs", "ms"]

    public init(_ raw: String) {
        self.raw = raw
        var text = raw
        // Drop "(NOR)", "[2850]" and similar trailing context.
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        let folded = NameFolding.fold(text)
        let compactUnknown = folded.filter { $0.isLetter || $0 == "?" || $0 == "-" || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
        if Self.unknownForms.contains(compactUnknown) || Self.unknownForms.contains(folded.filter { $0.isLetter || $0 == "?" }) {
            surname = []
            given = []
            return
        }

        func tokens(_ part: Substring) -> [String] {
            var cleaned = ""
            for character in part {
                if character.isLetter { cleaned.append(character) }
                else if character == "'" { continue }
                else { cleaned.append(" ") }
            }
            return cleaned.split(separator: " ").map(String.init)
        }

        var surnameTokens: [String]
        var givenTokens: [String]
        if let comma = folded.firstIndex(of: ",") {
            surnameTokens = tokens(folded[..<comma])
            givenTokens = tokens(folded[folded.index(after: comma)...])
            // "Wely, Loek van": trailing particles belong to the surname.
            var moved: [String] = []
            while let last = givenTokens.last, givenTokens.count > 1, Self.particles.contains(last) {
                moved.insert(givenTokens.removeLast(), at: 0)
            }
            surnameTokens = moved + surnameTokens
            if surnameTokens.isEmpty {
                surnameTokens = givenTokens
                givenTokens = []
            }
        } else {
            var all = tokens(folded[...])
            if all.count > 1, Self.titles.contains(all[0]) { all.removeFirst() }
            let isInitial: (String) -> Bool = { $0.count == 1 }
            if all.count <= 1 {
                surnameTokens = all
                givenTokens = []
            } else if let firstFull = all.firstIndex(where: { !isInitial($0) }),
                      firstFull > 0, !all[firstFull...].contains(where: isInitial) {
                // "M. Carlsen", "J R Capablanca".
                givenTokens = Array(all[..<firstFull])
                surnameTokens = Array(all[firstFull...])
            } else if let firstInitial = all.firstIndex(where: isInitial), firstInitial > 0,
                      all[firstInitial...].allSatisfy(isInitial) {
                // "Carlsen M", "Garcia Lopez J A".
                surnameTokens = Array(all[..<firstInitial])
                givenTokens = Array(all[firstInitial...])
            } else if Self.surnameFirstFamilies.contains(all[0]) {
                surnameTokens = [all[0]]
                givenTokens = Array(all.dropFirst())
            } else {
                // "Loek van Wely": last token plus the particles before it.
                var start = all.count - 1
                while start > 1, Self.particles.contains(all[start - 1]) { start -= 1 }
                surnameTokens = Array(all[start...])
                givenTokens = Array(all[..<start])
            }
        }
        surname = surnameTokens
        given = givenTokens
    }

    /// `true` for `?`, `NN`, empty and similar placeholders.
    public var isUnknown: Bool { surname.isEmpty }

    /// `surname, given`, folded: `van wely, loek`.
    public var normalized: String {
        given.isEmpty ? surname.joined(separator: " ") : surname.joined(separator: " ") + ", " + given.joined(separator: " ")
    }

    /// Surname tokens without particles, unless the surname is only particles.
    public var coreSurname: [String] {
        let core = surname.filter { !Self.particles.contains($0) }
        return core.isEmpty ? surname : core
    }

    /// Core surname folded but not transliterated, tokens joined: `wely`.
    public var foldedSurname: String { coreSurname.joined() }

    /// Transliteration key of the core surname, tokens joined: `vely`.
    public var surnameKey: String {
        coreSurname.map(NameFolding.transliterationKey).joined()
    }

    /// First letter of the first given name after transliteration
    /// (`Wladimir` and `Vladimir` both give `v`), or empty.
    public var firstInitial: String {
        given.first.map { String(NameFolding.transliterationKey($0).prefix(1)) } ?? ""
    }

    /// Key used to pair games of the same player: surname key plus first
    /// initial (`carlsen,m`). Empty for unknown players.
    ///
    /// Two-word East Asian names are written in both orders (`Yang, Le`,
    /// `Le Yang`), so when a name is exactly two full words and one of them
    /// is in ``surnameFirstFamilies`` the key ignores the order: `le+iang`.
    public var matchKey: String {
        if isUnknown { return "" }
        let words = surname + given
        if words.count == 2, words.allSatisfy({ $0.count > 1 }), words.contains(where: Self.surnameFirstFamilies.contains) {
            return words.map(NameFolding.transliterationKey).sorted().joined(separator: "+")
        }
        return lastSurnameKey + "," + firstInitial
    }

    /// Transliteration key of the last core surname token. The pairing key
    /// uses it because double surnames in Western order are ambiguous:
    /// `Jose Miguel Fernandez Garcia` is read as surname `garcia`, and so is
    /// `Fernandez Garcia, Jose Miguel` for this key.
    public var lastSurnameKey: String {
        coreSurname.last.map(NameFolding.transliterationKey) ?? ""
    }

    /// Keys used to block alias candidates: the first and the last three
    /// letters of the surname key, each with the first initial. A typo or a
    /// transliteration difference rarely touches both ends, and
    /// `Garcia Lopez, J.` and `Garcia, Jose` share the first block.
    public var blockKeys: [String] {
        let key = surnameKey
        guard !key.isEmpty else { return [] }
        return ["<" + key.prefix(3) + "," + firstInitial, ">" + key.suffix(3) + "," + firstInitial]
    }

    /// Order-free key of every full token, only when there are no initials:
    /// `Ding Liren` and `Liren Ding` share it. `nil` otherwise.
    public var tokenSetKey: String? {
        let all = surname + given
        guard all.count >= 2, all.allSatisfy({ $0.count > 1 }) else { return nil }
        return all.filter { !Self.particles.contains($0) }.map(NameFolding.transliterationKey).sorted().joined(separator: " ")
    }

    /// The given names as a transliteration key string, initials kept.
    public var givenKey: [String] { given.map(NameFolding.transliterationKey) }
}
