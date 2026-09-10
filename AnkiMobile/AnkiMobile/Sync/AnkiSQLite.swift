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
