//
//  MediaZip.swift
//  AnkiMobile
//
//  Minimal reader for the media `downloadFiles` zip. Anki writes those entries with
//  CompressionMethod::Stored (no compression) and back-patches sizes into the local
//  headers (seekable writer → no data descriptors), so we only need to walk the local
//  file headers and slice out the raw bytes — no inflate required.
//
//  The archive contains numbered entries ("0", "1", …) plus a "_meta" entry that maps
//  those names to the real filenames.
//

import Foundation

extension Array {
    /// Splits into consecutive chunks of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

enum MediaZip {
    /// Extracts a download zip into `[realFilename: fileData]`.
    static func extract(_ zip: Data) -> [String: Data] {
        let bytes = [UInt8](zip)
        var raw: [String: Data] = [:]   // entry name ("0", "_meta", …) → bytes
        var i = 0

        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int {
            Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }

        while i + 30 <= bytes.count, u32(i) == 0x04034b50 {   // "PK\3\4" local file header
            let compressedSize = u32(i + 18)
            let nameLen = u16(i + 26)
            let extraLen = u16(i + 28)
            let nameStart = i + 30
            let dataStart = nameStart + nameLen + extraLen
            guard dataStart + compressedSize <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<nameStart + nameLen], as: UTF8.self)
            raw[name] = Data(bytes[dataStart..<dataStart + compressedSize])
            i = dataStart + compressedSize
        }

        guard let metaData = raw["_meta"],
              let map = (try? JSONSerialization.jsonObject(with: metaData)) as? [String: String] else {
            return [:]
        }
        var out: [String: Data] = [:]
        for (entryName, realName) in map {
            if let data = raw[entryName] { out[realName] = data }
        }
        return out
    }
}
