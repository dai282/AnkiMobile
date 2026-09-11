//
//  AnkiSQLite.swift
//  AnkiMobile
//
//  Shared SQLite helpers for working with native Anki `.anki2` collections.
//
//  Anki's schema declares a custom `unicase` collation (a Unicode case-insensitive
//  ordering) on several indexes — e.g. on decks and notes. The system SQLite we link
//  against doesn't know it, so any query that *uses* one of those indexes (such as
//  `SELECT count(*) FROM decks`, which the planner satisfies from a unicase index)
//  fails with "no such collation sequence: unicase". Registering a compatible
//  case-insensitive collation on each connection makes those queries work.
//

import Foundation
import SQLite3

/// Tells SQLite to copy a transient text binding rather than assume the buffer outlives the call.
let ankiSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func unicaseString(_ ptr: UnsafeRawPointer?, _ length: Int32) -> String {
    guard let ptr, length > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(length)), as: UTF8.self)
}

/// Registers Anki's custom collations on an open database connection. Must be called
/// right after opening, before running any query that might use a unicase index.
func registerAnkiCollations(on db: OpaquePointer?) {
    sqlite3_create_collation_v2(db, "unicase", SQLITE_UTF8, nil, { _, lLen, lPtr, rLen, rPtr in
        let left = unicaseString(lPtr, lLen)
        let right = unicaseString(rPtr, rLen)
        switch left.compare(right, options: .caseInsensitive) {
        case .orderedAscending: return -1
        case .orderedSame: return 0
        case .orderedDescending: return 1
        }
    }, nil)
}

// MARK: - Minimal protobuf read/write

/// One decoded protobuf field. For varints, `varint` holds the value; for length-delimited
/// (wire 2) and fixed 32/64-bit (wire 5/1), `bytes` holds the raw payload.
struct PBField {
    let field: Int
    let wire: Int
    var varint: UInt64 = 0
    var bytes: [UInt8] = []
}

enum Protobuf {
    static func readVarint(_ bytes: [UInt8], _ i: inout Int) -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while i < bytes.count {
            let b = bytes[i]; i += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    static func writeVarint(_ value: UInt64, into out: inout [UInt8]) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
    }

    /// Decodes a message into its ordered fields, preserving unknown fields for round-tripping.
    static func fields(_ data: [UInt8]) -> [PBField] {
        var out: [PBField] = [], i = 0
        while i < data.count {
            let tag = readVarint(data, &i)
            let field = Int(tag >> 3), wire = Int(tag & 7)
            switch wire {
            case 0: out.append(PBField(field: field, wire: 0, varint: readVarint(data, &i)))
            case 2:
                let len = Int(readVarint(data, &i))
                guard i + len <= data.count else { return out }
                out.append(PBField(field: field, wire: 2, bytes: Array(data[i..<i + len]))); i += len
            case 1:
                guard i + 8 <= data.count else { return out }
                out.append(PBField(field: field, wire: 1, bytes: Array(data[i..<i + 8]))); i += 8
            case 5:
                guard i + 4 <= data.count else { return out }
                out.append(PBField(field: field, wire: 5, bytes: Array(data[i..<i + 4]))); i += 4
            default: return out
            }
        }
        return out
    }

    static func serialize(_ fields: [PBField]) -> [UInt8] {
        var out: [UInt8] = []
        for f in fields {
            writeVarint(UInt64(f.field << 3 | f.wire), into: &out)
            switch f.wire {
            case 0: writeVarint(f.varint, into: &out)
            case 2: writeVarint(UInt64(f.bytes.count), into: &out); out.append(contentsOf: f.bytes)
            default: out.append(contentsOf: f.bytes)   // wire 1/5: raw
            }
        }
        return out
    }

    /// The varint value of a top-level field, or nil.
    static func varintField(_ field: Int, in data: [UInt8]) -> UInt64? {
        fields(data).first { $0.field == field && $0.wire == 0 }?.varint
    }

    /// `KindContainer.Normal(field 1).config_id(field 1)` from a `decks.kind` blob.
    static func configID(fromKind data: [UInt8]) -> Int? {
        guard let normal = fields(data).first(where: { $0.field == 1 && $0.wire == 2 }) else { return nil }
        return varintField(1, in: normal.bytes).map(Int.init)
    }
}
