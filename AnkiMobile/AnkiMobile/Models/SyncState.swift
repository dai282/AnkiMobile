//
//  SyncState.swift
//  AnkiMobile
//
//  Collection-level sync bookkeeping (a single row). Mirrors the parts of Anki's
//  `col` table we need to drive a sync: creation time, schema time, and the last
//  synced update sequence number. See docs/SYNC_MAPPING.md.
//

import Foundation
import SwiftData

@Model
final class SyncState {
    /// Collection creation time (epoch seconds) — Anki's `col.crt`. Used to convert
    /// a review card's `due` to/from Anki's "days since creation" encoding.
    var creationEpoch: Int
    /// Schema modification time (epoch millis) — Anki's `col.scm`. A mismatch forces a full sync.
    var schemaMod: Int
    /// Last update sequence number we've synced up to — Anki's `col.usn`.
    var lastSyncedUsn: Int
    /// Collection modification time at last sync (epoch millis) — Anki's `col.mod`.
    var lastSyncMod: Int

    init(now: Date = .now) {
        let secs = Int(now.timeIntervalSince1970)
        self.creationEpoch = secs
        self.schemaMod = secs * 1000
        self.lastSyncedUsn = 0
        self.lastSyncMod = 0
    }

    /// Fetches the single SyncState row, creating it if missing.
    @discardableResult
    static func ensure(in context: ModelContext) -> SyncState {
        if let existing = try? context.fetch(FetchDescriptor<SyncState>()).first {
            return existing
        }
        let state = SyncState()
        context.insert(state)
        try? context.save()
        return state
    }
}
