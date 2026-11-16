//
//  GameSummary.swift
//  ChessDatabaseQuality
//

/// The player fields used to pair games.
public struct PlayerKey: Hashable, Sendable, Codable {
    /// ``PlayerName/matchKey``: surname key plus first initial.
    public var matchKey: String
    /// ``PlayerName/surnameKey``, for fuzzy comparison.
    public var surnameKey: String
    /// First initial of the given name, or empty.
    public var initial: String
    /// ``PlayerName/tokenSetKey``: the same words in any order.
    public var tokenSetKey: String?
    /// ``PlayerName/foldedSurname``, compared too because transliteration
    /// can split a misspelling from its original (`Zhang` / `Zhnag`).
    public var foldedSurname: String

    public init(_ name: PlayerName) {
        matchKey = name.matchKey
        surnameKey = name.surnameKey
        initial = name.firstInitial
        tokenSetKey = name.tokenSetKey
        foldedSurname = name.foldedSurname
    }

    public init(matchKey: String, surnameKey: String, initial: String, tokenSetKey: String? = nil, foldedSurname: String? = nil) {
        self.matchKey = matchKey
        self.surnameKey = surnameKey
        self.initial = initial
        self.tokenSetKey = tokenSetKey
        self.foldedSurname = foldedSurname ?? surnameKey
    }

    public var isUnknown: Bool { matchKey.isEmpty }
}

/// What the duplicate detector needs from one game.
///
/// Build it from any source: the importer, a `.mcbase` row or the file
/// analyzer of this package. `moves` uses ``GameSummary/encode(from:to:promotion:)``
/// and `positionKeys` holds the key of the start position and of the
/// position after each move (`moves.count + 1` keys).
public struct GameSummary: Sendable {
    /// The caller's identifier, returned in the groups.
    public var id: Int64
    public var white: PlayerKey
    public var black: PlayerKey
    public var date: PGNDate
    /// How informative the header is; the merge keeps the best one.
    public var headerScore: Int
    /// Hash of the `FEN` tag, 0 for the standard start position.
    public var startHash: UInt64
    public var moves: [UInt16]
    public var positionKeys: [UInt64]

    public init(
        id: Int64, white: PlayerKey, black: PlayerKey, date: PGNDate, headerScore: Int,
        startHash: UInt64 = 0, moves: [UInt16], positionKeys: [UInt64]
    ) {
        self.id = id
        self.white = white
        self.black = black
        self.date = date
        self.headerScore = headerScore
        self.startHash = startHash
        self.moves = moves
        self.positionKeys = positionKeys
    }

    /// 6 bits origin, 6 bits destination, 3 bits promotion (0 none, 1 N,
    /// 2 B, 3 R, 4 Q).
    public static func encode(from: Int, to: Int, promotion: Int = 0) -> UInt16 {
        UInt16(from & 63) | UInt16(to & 63) << 6 | UInt16(promotion & 7) << 12
    }
}

/// The compact form of a ``GameSummary`` that the detector stores.
public struct DuplicateFingerprint: Sendable {
    public var id: Int64
    public var white: PlayerKey
    public var black: PlayerKey
    public var date: PGNDate
    public var headerScore: Int
    public var startHash: UInt64
    public var moves: [UInt16]
    /// Position key at ply `nearPly`, or at the last ply of shorter games.
    public var nearKey: UInt64
    public var nearPly: Int
    /// MinHash of the position keys from `minHashStartPly`, or `nil` for
    /// games too short to compare that way.
    public var signature: [UInt32]?

    public init(_ summary: GameSummary, options: DuplicateOptions) {
        id = summary.id
        white = summary.white
        black = summary.black
        date = summary.date
        headerScore = summary.headerScore
        startHash = summary.startHash
        moves = summary.moves
        let keys = summary.positionKeys
        let plies = max(0, keys.count - 1)
        nearPly = min(plies, options.nearPly)
        nearKey = keys.isEmpty ? 0 : keys[nearPly]
        let start = min(options.minHashStartPly, keys.count)
        if keys.count - start >= options.minHashMinimumPositions {
            signature = MinHash.signature(of: keys[start...], size: options.minHashSize)
        } else {
            signature = nil
        }
    }

    /// Rolling hash of the first `count` moves.
    static func prefixHashes(startHash: UInt64, moves: [UInt16]) -> [UInt64] {
        var hashes = [UInt64](repeating: 0, count: moves.count + 1)
        var hash = StableHash.mix(startHash ^ 0x5DEE_CE66_D1CE_4E5B)
        hashes[0] = hash
        for (index, move) in moves.enumerated() {
            hash = StableHash.combine(hash, UInt64(move) | UInt64(index) << 16)
            hashes[index + 1] = hash
        }
        return hashes
    }
}

/// MinHash signatures of position-key sets.
public enum MinHash {
    static func seeds(_ size: Int) -> [UInt64] {
        (0..<size).map { StableHash.mix(UInt64($0 + 1) &* 0x9E37_79B9_7F4A_7C15) }
    }

    /// The signature of `keys`: for each of `size` hash functions, the
    /// minimum hash over the set. Two signatures agree in a slot with
    /// probability equal to the Jaccard similarity of the sets.
    public static func signature(of keys: some Collection<UInt64>, size: Int) -> [UInt32] {
        let seeds = Self.seeds(size)
        var signature = [UInt32](repeating: .max, count: size)
        for key in keys {
            for slot in 0..<size {
                let value = UInt32(truncatingIfNeeded: StableHash.mix(key ^ seeds[slot]) >> 32)
                if value < signature[slot] { signature[slot] = value }
            }
        }
        return signature
    }

    /// Fraction of equal slots: the estimated Jaccard similarity.
    public static func similarity(_ a: some Collection<UInt32>, _ b: some Collection<UInt32>) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var equal = 0
        for (x, y) in zip(a, b) where x == y { equal += 1 }
        return Double(equal) / Double(a.count)
    }

    /// Hash of band `band` of `rows` slots, for locality-sensitive hashing.
    static func bandHash(_ signature: [UInt32], band: Int, rows: Int) -> UInt64 {
        var hash = StableHash.mix(UInt64(band) &+ 0xB5AD_4ECE_DA1C_E2A9)
        for slot in (band * rows)..<((band + 1) * rows) {
            hash = StableHash.combine(hash, UInt64(signature[slot]))
        }
        return hash
    }
}
