//
//  StableHash.swift
//  ChessDatabaseQuality
//

/// Stable, process-independent 64-bit hashes.
///
/// Swift's `Hasher` is seeded per process, so it cannot be used for keys
/// that are written to disk or compared between runs. Everything in this
/// package hashes with SplitMix64 and FNV-1a instead.
public enum StableHash {
    /// The SplitMix64 finalizer: a fast bijective mixer with good avalanche.
    @inline(__always)
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Folds `value` into `hash`. Order dependent.
    @inline(__always)
    public static func combine(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        mix(hash ^ (value &* 0xFF51_AFD7_ED55_8CCD))
    }

    /// The 64-bit FNV-1a hash of the UTF-8 bytes of `text`.
    public static func fnv1a64(_ text: some StringProtocol) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
