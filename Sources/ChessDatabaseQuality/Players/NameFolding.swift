//
//  NameFolding.swift
//  ChessDatabaseQuality
//

import Foundation

/// Text folding used by player name normalization.
public enum NameFolding {
    /// Lowercases, converts other scripts to Latin, removes diacritics and
    /// rewrites letters that do not decompose (`ß`, `ø`, `ł`, `æ`…).
    ///
    /// ```swift
    /// NameFolding.fold("Ćmilyte, Viktorija") // "cmilyte, viktorija"
    /// NameFolding.fold("Карпов, Анатолий")   // "karpov, anatolij"
    /// ```
    public static func fold(_ text: String) -> String {
        var value = text
        if value.unicodeScalars.contains(where: { $0.value > 0x24F }) {
            value = value.applyingTransform(.toLatin, reverse: false) ?? value
        }
        value = value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        guard value.unicodeScalars.contains(where: { !$0.isASCII }) else { return value }
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for character in value {
            switch character {
            case "ß": result += "ss"
            case "ø": result += "o"
            case "æ": result += "ae"
            case "œ": result += "oe"
            case "ł": result += "l"
            case "đ", "ð": result += "d"
            case "þ": result += "th"
            case "ı": result += "i"
            case "ʼ", "’", "‘", "`", "´", "ʻ": result += "'"
            case "‐", "‑", "–", "—": result += "-"
            default:
                if character.isASCII { result.append(character) }
                else if character.isLetter {
                    // Last resort for letters without a decomposition.
                    let latin = String(character).applyingTransform(.toLatin, reverse: false)?
                        .folding(options: .diacriticInsensitive, locale: nil) ?? ""
                    result += latin.filter(\.isASCII)
                } else if character.isWhitespace {
                    result.append(" ")
                }
            }
        }
        return result
    }

    /// A transliteration-insensitive spelling of a lowercase ASCII token, so
    /// the usual romanizations of Russian, Ukrainian, Serbian, German or
    /// French sources compare equal:
    ///
    /// | Variants | Key |
    /// |---|---|
    /// | Aleksandr, Alexander, Alexandr | `alexandr` / `alexander` |
    /// | Sergey, Sergei, Sergej | `sergei` |
    /// | Grischuk, Grishchuk | `grishuk` |
    /// | Karpow, Karpoff, Karpov | `karpov` |
    /// | Toukmakov, Tukmakov | `tukmakov` |
    /// | Yakovenko, Jakovenko | `iakovenko` |
    /// | Khalifman, Halifman | `halifman` |
    ///
    /// It is a matching key, not a spelling: never show it. East Asian
    /// family names (``PlayerName/surnameFirstFamilies``) are kept as they
    /// are, because pinyin `zh`, `y` and `ou` are distinct sounds: `Zhu`,
    /// `Yu`, `Zhang`, `Yang`, `Hou` and `Hu` are different surnames.
    public static func transliterationKey(_ token: String) -> String {
        guard !token.isEmpty else { return token }
        if PlayerName.surnameFirstFamilies.contains(token) { return token }
        var s = token.filter { $0.isLetter }
        // Order matters: longer clusters first.
        let rules: [(String, String)] = [
            ("shch", "sh"), ("tsch", "ch"), ("sch", "sh"), ("tch", "ch"), ("tsj", "ch"), ("cz", "ch"),
            ("dzh", "j"), ("zh", "j"), ("dj", "j"), ("sz", "sh"),
            ("ks", "x"), ("kh", "h"), ("ph", "f"), ("th", "t"), ("ck", "k"),
            ("ou", "u"), ("w", "v"), ("ue", "u"), ("oe", "o"), ("ae", "a"),
        ]
        for (from, to) in rules where s.contains(from) {
            s = s.replacingOccurrences(of: from, with: to)
        }
        if s.hasSuffix("ff") { s = String(s.dropLast(2)) + "v" }
        // j and y as vowels or semivowels all become i: Sergej, Sergey -> sergei.
        s = s.replacingOccurrences(of: "j", with: "i").replacingOccurrences(of: "y", with: "i")
        // Collapse doubled letters: Aleksandr/Alexsandr, Iurii/Yuri.
        var collapsed = ""
        collapsed.reserveCapacity(s.utf8.count)
        var previous: Character?
        for character in s where character != previous {
            collapsed.append(character)
            previous = character
        }
        return collapsed
    }
}
