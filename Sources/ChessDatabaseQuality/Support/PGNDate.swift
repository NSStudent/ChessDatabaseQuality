//
//  PGNDate.swift
//  ChessDatabaseQuality
//

import Foundation

/// A PGN date with optional parts, as in `2025.??.??`.
public struct PGNDate: Hashable, Sendable, Codable, CustomStringConvertible {
    public var year: Int?
    public var month: Int?
    public var day: Int?
    /// `false` when the text was not empty or `?` but could not be read as
    /// `YYYY.MM.DD` (also accepted: `-` or `/` separators and a bare year).
    public var isWellFormed: Bool

    public init(year: Int?, month: Int?, day: Int?, isWellFormed: Bool = true) {
        self.year = year
        self.month = month
        self.day = day
        self.isWellFormed = isWellFormed
    }

    /// Parses the value of a `Date` tag.
    public init(_ raw: String?) {
        self.init(year: nil, month: nil, day: nil)
        guard let raw else { return }
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text.allSatisfy({ $0 == "?" || $0 == "." }) { return }
        let parts = text.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "/" }).map(String.init)
        guard (1...3).contains(parts.count) else {
            isWellFormed = false
            return
        }
        func number(_ part: String, digits: ClosedRange<Int>) -> (value: Int?, ok: Bool) {
            if part.allSatisfy({ $0 == "?" }) { return (nil, true) }
            guard digits.contains(part.count), part.allSatisfy(\.isASCIIDigit), let value = Int(part) else {
                return (nil, false)
            }
            return (value, true)
        }
        let y = number(parts[0], digits: 4...4)
        year = y.value
        var ok = y.ok
        if parts.count > 1 {
            let m = number(parts[1], digits: 1...2)
            month = m.value
            ok = ok && m.ok
        }
        if parts.count > 2 {
            let d = number(parts[2], digits: 1...2)
            day = d.value
            ok = ok && d.ok
        }
        isWellFormed = ok
    }

    public var isUnknown: Bool { year == nil && month == nil && day == nil }

    /// Number of known parts, 0 to 3.
    public var completeness: Int {
        (year == nil ? 0 : 1) + (month == nil ? 0 : 1) + (day == nil ? 0 : 1)
    }

    /// `true` when no known part contradicts the other date: `2025.??.??`
    /// is compatible with `2025.03.14`, `????.??.??` with everything.
    public func isCompatible(with other: PGNDate) -> Bool {
        func agree(_ a: Int?, _ b: Int?) -> Bool { a == nil || b == nil || a == b }
        return agree(year, other.year) && agree(month, other.month) && agree(day, other.day)
    }

    /// Packs the date into 32 bits (0 means unknown part) for compact storage.
    public var packed: UInt32 {
        UInt32(year ?? 0) << 9 | UInt32(month ?? 0) << 5 | UInt32(day ?? 0)
    }

    public init(packed: UInt32) {
        let y = Int(packed >> 9), m = Int((packed >> 5) & 0xF), d = Int(packed & 0x1F)
        self.init(year: y == 0 ? nil : y, month: m == 0 ? nil : m, day: d == 0 ? nil : d)
    }

    /// Problems with the known parts: month 13, February 30, a year before
    /// `minimumYear` or after `latestYear`.
    public func impossibility(minimumYear: Int = 1475, latestYear: Int) -> String? {
        if let year, year < minimumYear { return "año \(year) anterior a \(minimumYear)" }
        if let year, year > latestYear { return "año \(year) en el futuro" }
        if let month, !(1...12).contains(month) { return "mes \(month)" }
        if let day {
            guard day >= 1 else { return "día \(day)" }
            let maximum: Int
            switch month {
            case nil: maximum = 31
            case 2?:
                if let year {
                    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
                    maximum = leap ? 29 : 28
                } else {
                    maximum = 29
                }
            case 4?, 6?, 9?, 11?: maximum = 30
            default: maximum = 31
            }
            if day > maximum { return "día \(day) del mes \(month.map(String.init) ?? "?")" }
        }
        return nil
    }

    public var description: String {
        func part(_ value: Int?, _ width: Int) -> String {
            guard let value else { return String(repeating: "?", count: width) }
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(part(year, 4)).\(part(month, 2)).\(part(day, 2))"
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
