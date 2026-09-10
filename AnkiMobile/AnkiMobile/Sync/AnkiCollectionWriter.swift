//
//  AnkiCollectionWriter.swift
//  AnkiMobile
//
//  Writes review results back into the persisted `.anki2` collection so they can be
//  pushed on the next sync (V2.3b). For each rating it mirrors the `cards` row,
//  appends a `revlog` entry (both flagged usn = -1 = "not yet synced"), and bumps
//  `col.mod` so the server sees the collection as changed. `col.scm` is left alone —
//  changing the schema time would force a full re-upload.
//
//  Only cards that originated from a pull (with an Anki id) can be mirrored; locally
//  seeded cards have no place in the native collection and are skipped by the caller.
//

import Foundation
import SQLite3

final class AnkiCollectionWriter {
    enum WriterError: LocalizedError {
        case cannotOpen(String)
        case exec(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let m): return "Couldn't open collection for writing: \(m)"
            case .exec(let m): return "Write failed: \(m)"
            }
        }
    }

    /// Everything needed to mirror one rating into the native collection.
    struct Review {
        // cards row
        let cardId: Int
        let type: Int
        let queue: Int
        let due: Int
        let ivl: Int
        let factor: Int
        let reps: Int
        let lapses: Int
        let cardModSeconds: Int
        // revlog row
        let revlogId: Int      // epoch ms (primary key, must be unique)
        let ease: Int          // button pressed, 1...4
        let lastIvl: Int
        let revlogType: Int    // 0 = learn, 1 = review
        let timeMs: Int
        // collection
        let collectionModMs: Int
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        // Read-write: the collection is in WAL mode (see AnkiCollectionReader) and this
        // is our own persisted copy, so letting SQLite manage the journal is safe.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? path
            sqlite3_close(db)
            throw WriterError.cannotOpen(message)
        }
        registerAnkiCollations(on: db)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    /// Applies one review atomically: update the card, append a revlog entry, bump col.mod.
    func record(_ r: Review) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            let revlogId = try uniqueRevlogId(preferred: r.revlogId)

            try run(
                """
                UPDATE cards SET type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=?, mod=?, usn=-1 \
                WHERE id=?
                """,
                [r.type, r.queue, r.due, r.ivl, r.factor, r.reps, r.lapses, r.cardModSeconds, r.cardId]
            )
            try run(
                """
                INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) \
                VALUES (?, ?, -1, ?, ?, ?, ?, ?, ?)
                """,
                [revlogId, r.cardId, r.ease, r.ivl, r.lastIvl, r.factor, r.timeMs, r.revlogType]
            )
            try run("UPDATE col SET mod=? WHERE id=1", [r.collectionModMs])

            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: - Primitives

    /// Revlog ids are millisecond timestamps; user reviews are seconds apart so collisions
    /// are unlikely, but guarantee strict monotonicity to satisfy the PRIMARY KEY.
    private func uniqueRevlogId(preferred: Int) throws -> Int {
        max(preferred, try scalarInt("SELECT COALESCE(MAX(id), 0) FROM revlog") + 1)
    }

    private func run(_ sql: String, _ params: [Int]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw WriterError.exec(lastError(sql))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in params.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), Int64(value))
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw WriterError.exec(lastError(sql))
        }
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw WriterError.exec(lastError(sql))
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw WriterError.exec(lastError(sql))
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    private func lastError(_ sql: String) -> String {
        let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return "\(message) [\(sql)]"
    }
}
