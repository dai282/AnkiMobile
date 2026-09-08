//
//  Zstd.swift
//  AnkiMobile
//
//  Thin Swift wrapper over the C `libzstd` (facebook/zstd) for the Anki sync
//  protocol, which zstd-compresses request bodies and responses. Compression uses
//  the one-shot API; decompression is streaming, because Anki's server writes
//  frames without an embedded content size.
//

import Foundation
import libzstd

enum Zstd {
    enum ZstdError: Error { case compressionFailed, decompressionFailed }

    /// One-shot compression at the given level (3 matches Anki's default-ish).
    static func compress(_ data: Data, level: Int32 = 3) throws -> Data {
        let bound = ZSTD_compressBound(data.count)
        var dst = Data(count: bound)
        let written = dst.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                ZSTD_compress(dstPtr.baseAddress, bound, srcPtr.baseAddress, data.count, level)
            }
        }
        if ZSTD_isError(written) != 0 { throw ZstdError.compressionFailed }
        return dst.prefix(written)
    }

    /// Streaming decompression (handles frames with unknown content size).
    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard let dstream = ZSTD_createDStream() else { throw ZstdError.decompressionFailed }
        defer { ZSTD_freeDStream(dstream) }
        _ = ZSTD_initDStream(dstream)

        let outCapacity = ZSTD_DStreamOutSize()
        var outChunk = Data(count: outCapacity)
        var result = Data()

        try data.withUnsafeBytes { (rawIn: UnsafeRawBufferPointer) in
            var inBuffer = ZSTD_inBuffer(src: rawIn.baseAddress, size: data.count, pos: 0)
            while inBuffer.pos < inBuffer.size {
                let lastInPos = inBuffer.pos
                let produced: Int = try outChunk.withUnsafeMutableBytes { (rawOut: UnsafeMutableRawBufferPointer) in
                    var outBuffer = ZSTD_outBuffer(dst: rawOut.baseAddress, size: outCapacity, pos: 0)
                    let code = ZSTD_decompressStream(dstream, &outBuffer, &inBuffer)
                    if ZSTD_isError(code) != 0 { throw ZstdError.decompressionFailed }
                    if outBuffer.pos > 0, let base = rawOut.baseAddress {
                        result.append(base.assumingMemoryBound(to: UInt8.self), count: outBuffer.pos)
                    }
                    return outBuffer.pos
                }
                // Guard against a stall (no input consumed and no output produced).
                if produced == 0 && inBuffer.pos == lastInPos { break }
            }
        }
        return result
    }
}
