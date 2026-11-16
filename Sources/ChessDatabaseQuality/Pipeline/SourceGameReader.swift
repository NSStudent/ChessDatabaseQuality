//
//  SourceGameReader.swift
//  ChessDatabaseQuality
//

import FischerCore
import Foundation

/// Reads single games back from the PGN file by their byte offset.
public struct SourceGameReader: Sendable {
    public let url: URL
    let starts: [Int64]
    let lengths: [Int32]

    init(url: URL, starts: [Int64], lengths: [Int32]) {
        self.url = url
        self.starts = starts
        self.lengths = lengths
    }

    public var count: Int { starts.count }

    /// The PGN text of the game with index `id`.
    public func text(of id: Int64) throws -> String {
        try texts(of: [id])[id] ?? ""
    }

    public func texts(of ids: [Int64]) throws -> [Int64: String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result: [Int64: String] = [:]
        for id in ids where id >= 0 && Int(id) < starts.count {
            try handle.seek(toOffset: UInt64(starts[Int(id)]))
            let data = try handle.read(upToCount: Int(lengths[Int(id)])) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            result[id] = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// The tags of each game, by tag name.
    public func tags(of ids: [Int64]) throws -> [Int64: [String: String]] {
        var result: [Int64: [String: String]] = [:]
        for (id, text) in try texts(of: ids) {
            let chunk = PGNGameChunk(index: Int(id), text: text, startByteOffset: 0, endByteOffset: 0)
            guard let basic = try? chunk.basicGame() else { continue }
            var tags: [String: String] = [:]
            for (tag, value) in basic.tags { tags[tag.rawValue] = value }
            result[id] = tags
        }
        return result
    }

    /// The merge proposal of a duplicate group, with the headers read from
    /// the source.
    public func mergeProposal(for group: DuplicateGroup) throws -> MergeProposal {
        MergeProposalBuilder.proposal(for: group, tags: try tags(of: group.ids))
    }
}
