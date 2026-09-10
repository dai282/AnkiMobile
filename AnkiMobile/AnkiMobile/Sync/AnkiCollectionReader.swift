//
//  AnkiCollectionReader.swift
//  AnkiMobile
//
//  Read-only access to a downloaded Anki `.anki2` SQLite collection using the
//  built-in SQLite3 C API (no third-party dependency). Used by the pull flow to
//  inspect and later materialize the downloaded collection.
//

import Foundation
import SQLite3

final class AnkiCollectionReader {
    enum ReaderError: LocalizedError {
        case cannotOpen(String)
        case query(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let p): return "Couldn't open collection at \(p)."
            case .query(let sql): return "Query failed: \(sql)"
            }
        }
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        // Open read-write: Anki collections are in WAL journal mode, and opening a WAL
        // database read-only fails without its -wal/-shm sidecars. The file is our own
        // disposable temp copy, so letting SQLite manage the journal is safe.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? path
            sqlite3_close(db)
            throw ReaderError.cannotOpen(message)
        }
        registerAnkiCollations(on: db)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    /// Names of all tables in the collection (useful for schema inspection).
    func tableNames() throws -> [String] {
        var names: [String] = []
        try forEachRow("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") { stmt in
            if let c = sqlite3_column_text(stmt, 0) { names.append(String(cString: c)) }
        }
        return names
    }

    /// Row count of a table (table name is internal/trusted).
    func count(_ table: String) throws -> Int {
        try scalarInt("SELECT count(*) FROM \(table)")
    }

    // MARK: - Anki collection queries (modern schema 18)

    /// Collection creation time in epoch seconds (`col.crt`) — used to decode review `due`.
    func creationEpoch() throws -> Int {
        try scalarInt("SELECT crt FROM col LIMIT 1")
    }

    /// All decks as (id, full `::`-delimited name).
    func decks() throws -> [(id: Int, name: String)] {
        var out: [(Int, String)] = []
        try forEachRow("SELECT id, name FROM decks") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            out.append((id, name))
        }
        return out
    }

    /// Notes keyed by id → (fields joined by 0x1f, space-delimited tags).
    func notesByID() throws -> [Int: (flds: String, tags: String)] {
        var map: [Int: (String, String)] = [:]
        try forEachRow("SELECT id, flds, tags FROM notes") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            let flds = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let tags = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            map[id] = (flds, tags)
        }
        return map
    }

    struct CardRow {
        let id, nid, did, type, queue, due, ivl, factor, reps, lapses: Int
    }

    /// All cards with their scheduling columns.
    func cardRows() throws -> [CardRow] {
        var out: [CardRow] = []
        try forEachRow("SELECT id,nid,did,type,queue,due,ivl,factor,reps,lapses FROM cards") { stmt in
            out.append(CardRow(
                id: Int(sqlite3_column_int64(stmt, 0)),
                nid: Int(sqlite3_column_int64(stmt, 1)),
                did: Int(sqlite3_column_int64(stmt, 2)),
                type: Int(sqlite3_column_int64(stmt, 3)),
                queue: Int(sqlite3_column_int64(stmt, 4)),
                due: Int(sqlite3_column_int64(stmt, 5)),
                ivl: Int(sqlite3_column_int64(stmt, 6)),
                factor: Int(sqlite3_column_int64(stmt, 7)),
                reps: Int(sqlite3_column_int64(stmt, 8)),
                lapses: Int(sqlite3_column_int64(stmt, 9))
            ))
        }
        return out
    }

    /// A single text value, or nil.
    func scalarText(_ sql: String) throws -> String? {
        var value: String?
        try forEachRow(sql, stopAfterFirst: true) { stmt in
            if let c = sqlite3_column_text(stmt, 0) { value = String(cString: c) }
        }
        return value
    }

    // MARK: - Primitives

    private func scalarInt(_ sql: String) throws -> Int {
        var value = 0
        try forEachRow(sql, stopAfterFirst: true) { stmt in
            value = Int(sqlite3_column_int64(stmt, 0))
        }
        return value
    }

    /// Prepares `sql`, steps it, and invokes `body` for each row.
    private func forEachRow(_ sql: String, stopAfterFirst: Bool = false, _ body: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ReaderError.query(sql)
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            body(stmt)
            if stopAfterFirst { break }
        }
    }
}
