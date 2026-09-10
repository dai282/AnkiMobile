//
//  AnkiCollectionSyncStore.swift
//  AnkiMobile
//
//  Read/write access to the persisted `.anki2` collection for the incremental
//  push (V2.3c). Everything the normal-sync driver needs to talk to the native
//  collection lives here: reading pending (usn = -1) cards/revlog, stamping them
//  with the server's USN, computing sanity counts, applying server-sent
//  graves/chunks, and finalizing col.usn/mod.
//
//  Positional rows are exchanged as `[Any]` arrays matching Anki's serde tuple
//  order (see docs/SYNC_MAPPING.md): CardEntry has 18 elements, RevlogEntry 9,
//  NoteEntry 11.
//

import Foundation
import SQLite3

final class AnkiCollectionSyncStore {
    enum StoreError: LocalizedError {
        case cannotOpen(String)
        case query(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let m): return "Couldn't open collection: \(m)"
            case .query(let m): return "Query failed: \(m)"
            }
        }
    }

    struct CollectionMeta {
        let mod: Int   // col.mod (epoch ms)
        let scm: Int   // col.scm (epoch ms)
        let usn: Int   // col.usn
    }

    struct SanityCounts {
        let cards, notes, revlog, graves, notetypes, decks, deckConfig: Int
    }

    /// The 18 card columns in Anki's CardEntry tuple order.
    private static let cardColumns = "id,nid,did,ord,mod,usn,type,queue,due,ivl,factor,reps,lapses,left,odue,odid,flags,data"
    /// The 9 revlog columns in RevlogEntry tuple order.
    private static let revlogColumns = "id,cid,usn,ease,ivl,lastIvl,factor,time,type"
    /// The 11 note columns in NoteEntry tuple order.
    private static let noteColumns = "id,guid,mid,mod,usn,tags,flds,sfld,csum,flags,data"

    private var db: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? path
            sqlite3_close(db)
            throw StoreError.cannotOpen(message)
        }
        registerAnkiCollations(on: db)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    // MARK: - Collection metadata

    func collectionMeta() throws -> CollectionMeta {
        var meta = CollectionMeta(mod: 0, scm: 0, usn: 0)
        try forEachRow("SELECT mod, scm, usn FROM col LIMIT 1") { stmt in
            meta = CollectionMeta(
                mod: Int(sqlite3_column_int64(stmt, 0)),
                scm: Int(sqlite3_column_int64(stmt, 1)),
                usn: Int(sqlite3_column_int64(stmt, 2))
            )
        }
        return meta
    }

    /// col.usn = server_usn + 1, col.mod = server's new modification time (from `finish`).
    func finalize(usn: Int, mod: Int) throws {
        try run("UPDATE col SET usn=?, mod=? WHERE id=1", [usn, mod])
    }

    // MARK: - Local → remote (things we push)

    /// Rows for cards changed locally (usn = -1), as CardEntry tuples with `usn`
    /// replaced by the server's USN (Anki stamps entries with the server USN on send).
    func pendingCardArrays(usn serverUsn: Int) throws -> [[Any]] {
        try rows("SELECT \(Self.cardColumns) FROM cards WHERE usn=-1", usnIndex: 5, serverUsn: serverUsn, textColumns: [17])
    }

    /// Rows for revlog entries added locally (usn = -1), as RevlogEntry tuples.
    func pendingRevlogArrays(usn serverUsn: Int) throws -> [[Any]] {
        try rows("SELECT \(Self.revlogColumns) FROM revlog WHERE usn=-1", usnIndex: 2, serverUsn: serverUsn, textColumns: [])
    }

    /// Distinct deck ids among locally changed cards — used to report "decks touched".
    func pendingDeckIDs() throws -> Set<Int> {
        var ids: Set<Int> = []
        try forEachRow("SELECT DISTINCT did FROM cards WHERE usn=-1") { stmt in
            ids.insert(Int(sqlite3_column_int64(stmt, 0)))
        }
        return ids
    }

    /// Clears the pending flag on everything we just pushed by stamping the server USN.
    func stampPushed(usn serverUsn: Int) throws {
        try run("UPDATE cards SET usn=? WHERE usn=-1", [serverUsn])
        try run("UPDATE revlog SET usn=? WHERE usn=-1", [serverUsn])
    }

    // MARK: - Sanity

    func sanityCounts() throws -> SanityCounts {
        SanityCounts(
            cards: try count("cards"),
            notes: try count("notes"),
            revlog: try count("revlog"),
            graves: try count("graves"),
            notetypes: try count("notetypes"),
            decks: try count("decks"),
            deckConfig: try count("deck_config")
        )
    }

    /// The set of `id`s present in a table (e.g. decks, notetypes) — used to tell a
    /// genuinely new server object apart from an update to one we already have.
    func idSet(table: String) throws -> Set<Int> {
        var ids: Set<Int> = []
        try forEachRow("SELECT id FROM \(table)") { stmt in ids.insert(Int(sqlite3_column_int64(stmt, 0))) }
        return ids
    }

    // MARK: - Remote → local (things the server sends us)

    /// Deletes rows the server reports as deleted. (We don't record graves of our own.)
    func applyServerGraves(cards: [Int], notes: [Int], decks: [Int]) throws {
        for id in cards { try run("DELETE FROM cards WHERE id=?", [id]) }
        for id in notes { try run("DELETE FROM notes WHERE id=?", [id]) }
        for id in decks { try run("DELETE FROM decks WHERE id=?", [id]) }
    }

    /// Upserts server cards, but never clobbers a locally-pending change unless the
    /// server's copy is strictly newer (mirrors Anki's add_or_update_card_if_newer).
    func applyServerCards(_ rows: [[Any]]) throws {
        let placeholders = Array(repeating: "?", count: 18).joined(separator: ",")
        for row in rows where row.count == 18 {
            let id = anyInt(row[0]), incomingMtime = anyInt(row[4])
            guard try shouldApply(table: "cards", id: id, incomingMtime: incomingMtime) else { continue }
            try runAny("INSERT OR REPLACE INTO cards (\(Self.cardColumns)) VALUES (\(placeholders))", row)
        }
    }

    func applyServerNotes(_ rows: [[Any]]) throws {
        let placeholders = Array(repeating: "?", count: 11).joined(separator: ",")
        for row in rows where row.count == 11 {
            let id = anyInt(row[0]), incomingMtime = anyInt(row[3])
            guard try shouldApply(table: "notes", id: id, incomingMtime: incomingMtime) else { continue }
            try runAny("INSERT OR REPLACE INTO notes (\(Self.noteColumns)) VALUES (\(placeholders))", row)
        }
    }

    func applyServerRevlog(_ rows: [[Any]]) throws {
        let placeholders = Array(repeating: "?", count: 9).joined(separator: ",")
        for row in rows where row.count == 9 {
            try runAny("INSERT OR REPLACE INTO revlog (\(Self.revlogColumns)) VALUES (\(placeholders))", row)
        }
    }

    /// Apply an incoming object only if we have no local copy, our copy isn't a pending
    /// local change, or the server's copy is newer.
    private func shouldApply(table: String, id: Int, incomingMtime: Int) throws -> Bool {
        var localUsn: Int?
        var localMtime = 0
        let mtimeColumn = (table == "notes") ? "mod" : "mod"
        try forEachRow("SELECT usn, \(mtimeColumn) FROM \(table) WHERE id=? LIMIT 1", bind: [id]) { stmt in
            localUsn = Int(sqlite3_column_int64(stmt, 0))
            localMtime = Int(sqlite3_column_int64(stmt, 1))
        }
        guard let usn = localUsn else { return true }     // no local row
        if usn != -1 { return true }                       // not a pending local change
        return incomingMtime > localMtime                  // pending locally: only if server newer
    }

    // MARK: - Primitives

    private func count(_ table: String) throws -> Int {
        var value = 0
        try forEachRow("SELECT count(*) FROM \(table)") { stmt in value = Int(sqlite3_column_int64(stmt, 0)) }
        return value
    }

    /// Reads positional rows, overriding the USN column with `serverUsn` and returning
    /// the columns in `textColumns` as Strings (everything else as Int).
    private func rows(_ sql: String, usnIndex: Int, serverUsn: Int, textColumns: Set<Int>) throws -> [[Any]] {
        var out: [[Any]] = []
        try forEachRow(sql) { stmt in
            let columns = Int(sqlite3_column_count(stmt))
            var row: [Any] = []
            row.reserveCapacity(columns)
            for i in 0..<columns {
                if i == usnIndex {
                    row.append(serverUsn)
                } else if textColumns.contains(i) {
                    row.append(sqlite3_column_text(stmt, Int32(i)).map { String(cString: $0) } ?? "")
                } else {
                    row.append(Int(sqlite3_column_int64(stmt, Int32(i))))
                }
            }
            out.append(row)
        }
        return out
    }

    private func run(_ sql: String, _ params: [Int]) throws {
        try runAny(sql, params.map { $0 as Any })
    }

    /// Executes `sql`, binding Ints/NSNumbers as integers, Strings as text, NSNull as null.
    private func runAny(_ sql: String, _ params: [Any]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.query(lastError(sql))
        }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, params)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.query(lastError(sql)) }
    }

    private func forEachRow(_ sql: String, bind: [Int] = [], _ body: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.query(lastError(sql))
        }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, bind.map { $0 as Any })
        while sqlite3_step(stmt) == SQLITE_ROW { body(stmt) }
    }

    private func bindAll(_ stmt: OpaquePointer, _ params: [Any]) {
        for (i, value) in params.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case let n as Int:
                sqlite3_bind_int64(stmt, index, Int64(n))
            case let n as NSNumber:
                sqlite3_bind_int64(stmt, index, n.int64Value)
            case let s as String:
                sqlite3_bind_text(stmt, index, s, -1, ankiSQLiteTransient)
            default:
                sqlite3_bind_null(stmt, index)
            }
        }
    }

    private func anyInt(_ value: Any) -> Int {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }

    private func lastError(_ sql: String) -> String {
        let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return "\(message) [\(sql)]"
    }
}
