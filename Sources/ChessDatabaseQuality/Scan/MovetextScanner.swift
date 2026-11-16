//
//  MovetextScanner.swift
//  ChessDatabaseQuality
//

/// The main line of a movetext, without comments, variations, NAGs or
/// move numbers.
public struct ScannedMovetext: Sendable, Hashable {
    /// SAN tokens of the main line, as written (annotation glyphs kept).
    public var moves: [String] = []
    /// `1-0`, `0-1`, `1/2-1/2` or `*` when the main line ends with one.
    public var termination: String?
    /// Main-line tokens after the termination marker.
    public var tokensAfterTermination = 0
    /// A `{` comment or a `(` variation is not closed.
    public var isUnbalanced = false
}

/// A byte-level scanner of PGN movetext.
public enum MovetextScanner {
    public static func scan(_ text: String) -> ScannedMovetext {
        var result = ScannedMovetext()
        var token: [UInt8] = []
        token.reserveCapacity(16)
        var inBrace = false
        var inLineComment = false
        var inEscape = false
        var atLineStart = true
        var depth = 0

        func flush() {
            defer { token.removeAll(keepingCapacity: true) }
            guard depth == 0, !token.isEmpty else { return }
            classify(token, into: &result)
        }

        for byte in text.utf8 {
            if byte == 0x0A || byte == 0x0D {
                if !inBrace { flush() }
                inLineComment = false
                inEscape = false
                atLineStart = true
                continue
            }
            let wasLineStart = atLineStart
            atLineStart = false
            if inLineComment || inEscape { continue }
            if inBrace {
                if byte == UInt8(ascii: "}") { inBrace = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "%") where wasLineStart:
                inEscape = true
            case UInt8(ascii: "{"):
                flush()
                inBrace = true
            case UInt8(ascii: ";"):
                flush()
                inLineComment = true
            case UInt8(ascii: "("):
                flush()
                depth += 1
            case UInt8(ascii: ")"):
                flush()
                if depth == 0 { result.isUnbalanced = true } else { depth -= 1 }
            case UInt8(ascii: " "), UInt8(ascii: "\t"):
                flush()
            default:
                token.append(byte)
            }
        }
        flush()
        if inBrace || depth > 0 { result.isUnbalanced = true }
        return result
    }

    private static let results: [[UInt8]: String] = [
        Array("1-0".utf8): "1-0", Array("0-1".utf8): "0-1", Array("1/2-1/2".utf8): "1/2-1/2",
        Array("*".utf8): "*", Array("½-½".utf8): "1/2-1/2", Array("1/2".utf8): "1/2-1/2",
    ]

    private static func classify(_ raw: [UInt8], into result: inout ScannedMovetext) {
        if let outcome = results[raw] {
            if result.termination == nil { result.termination = outcome } else { result.tokensAfterTermination += 1 }
            return
        }
        var token = raw[...]
        // Move numbers, possibly glued to the move: "12.", "12...", "12.Nf3".
        let digits = token.prefix { $0 >= 0x30 && $0 <= 0x39 }
        if !digits.isEmpty {
            let afterDigits = token.dropFirst(digits.count)
            let dots = afterDigits.prefix { $0 == UInt8(ascii: ".") }
            if !dots.isEmpty { token = afterDigits.dropFirst(dots.count) }
        }
        // Leading dots of "...Nf6".
        while token.first == UInt8(ascii: ".") { token = token.dropFirst() }
        guard let first = token.first else { return }
        if first == UInt8(ascii: "$") { return }
        if token.allSatisfy({ $0 == UInt8(ascii: "!") || $0 == UInt8(ascii: "?") }) { return }
        if token.elementsEqual("e.p.".utf8) || token.elementsEqual("ep".utf8) { return }
        if let dollar = token.firstIndex(of: UInt8(ascii: "$")) { token = token[..<dollar] }
        guard !token.isEmpty else { return }
        if result.termination != nil {
            result.tokensAfterTermination += 1
            return
        }
        result.moves.append(String(decoding: token, as: UTF8.self))
    }
}
