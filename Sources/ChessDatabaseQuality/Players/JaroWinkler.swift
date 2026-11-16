//
//  JaroWinkler.swift
//  ChessDatabaseQuality
//

/// Jaro-Winkler similarity, 0 (different) to 1 (equal).
public enum JaroWinkler {
    public static func similarity(_ a: String, _ b: String, prefixScale: Double = 0.1) -> Double {
        if a == b { return 1 }
        let s = Array(a.utf8), t = Array(b.utf8)
        if s.isEmpty || t.isEmpty { return 0 }
        let window = max(0, max(s.count, t.count) / 2 - 1)
        var sMatched = [Bool](repeating: false, count: s.count)
        var tMatched = [Bool](repeating: false, count: t.count)
        var matches = 0
        for i in s.indices {
            let low = max(0, i - window), high = min(t.count - 1, i + window)
            guard low <= high else { continue }
            for j in low...high where !tMatched[j] && s[i] == t[j] {
                sMatched[i] = true
                tMatched[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        var transpositions = 0
        var k = 0
        for i in s.indices where sMatched[i] {
            while !tMatched[k] { k += 1 }
            if s[i] != t[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s.count) + m / Double(t.count) + (m - Double(transpositions / 2)) / m) / 3
        var prefix = 0
        while prefix < min(4, min(s.count, t.count)), s[prefix] == t[prefix] { prefix += 1 }
        return jaro + Double(prefix) * prefixScale * (1 - jaro)
    }
}
