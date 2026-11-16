//
//  BinaryIO.swift
//  ChessDatabaseQuality
//

import Foundation

/// Appends little-endian integers to a file through a buffer.
final class BinaryFileWriter {
    let url: URL
    private let handle: FileHandle
    private var buffer: [UInt8] = []
    private let capacity: Int
    private(set) var bytesWritten: Int64 = 0

    init(url: URL, capacity: Int = 1 << 20) throws {
        self.url = url
        self.capacity = capacity
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(capacity + 4096)
    }

    @inline(__always)
    func write<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
        if buffer.count >= capacity { flushBuffer() }
    }

    func write(_ values: [UInt16]) {
        for value in values { withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) } }
        if buffer.count >= capacity { flushBuffer() }
    }

    func write(_ values: [UInt32]) {
        for value in values { withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) } }
        if buffer.count >= capacity { flushBuffer() }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        handle.write(Data(buffer))
        bytesWritten += Int64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
    }

    func close() throws {
        flushBuffer()
        try handle.close()
    }
}

/// Reads little-endian integers from a byte buffer.
struct BinaryCursor {
    let data: Data
    var offset = 0

    init(_ data: Data) { self.data = data }

    var isAtEnd: Bool { offset >= data.count }

    @inline(__always)
    mutating func read<T: FixedWidthInteger>(_: T.Type = T.self) -> T {
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += MemoryLayout<T>.size
        return T(littleEndian: value)
    }

    mutating func readUInt16Array(count: Int) -> [UInt16] {
        let size = count * 2
        let values = data.withUnsafeBytes { raw -> [UInt16] in
            (0..<count).map { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset + $0 * 2, as: UInt16.self)) }
        }
        offset += size
        return values
    }
}

/// Fixed-width records in a memory-mapped file, accessed by index.
struct MappedRecords {
    let data: Data
    let stride: Int

    init(url: URL, stride: Int) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        self.stride = stride
    }

    @inline(__always)
    func read<T: FixedWidthInteger>(_ index: Int, at field: Int, as _: T.Type = T.self) -> T {
        T(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * stride + field, as: T.self) })
    }
}
