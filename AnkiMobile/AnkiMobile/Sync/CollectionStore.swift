//
//  CollectionStore.swift
//  AnkiMobile
//
//  Location of the persisted native Anki `.anki2` collection — kept as the sync
//  source of truth so we can push incremental changes later (V2.3).
//

import Foundation

enum CollectionStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnkiCollection", isDirectory: true)
    }

    static var collectionURL: URL {
        directory.appendingPathComponent("collection.anki2")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: collectionURL.path)
    }

    /// On-disk size of the collection (including WAL/SHM sidecars), in bytes.
    static var sizeBytes: Int {
        let fm = FileManager.default
        return ["", "-wal", "-shm"].reduce(0) { sum, suffix in
            sum + ((try? fm.attributesOfItem(atPath: collectionURL.path + suffix)[.size] as? Int) ?? 0)
        }
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Removes the collection and any WAL/SHM sidecars (for a fresh full download).
    static func reset() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: collectionURL.path + suffix)
        }
    }

    /// Reviews recorded locally but not yet pushed. Used to warn before a Download/Force-Download
    /// replaces the collection and would discard them. Zero if there's no collection yet.
    static func pendingReviewCount() -> Int {
        guard exists, let store = try? AnkiCollectionSyncStore(path: collectionURL.path) else { return 0 }
        return (try? store.pendingReviewCount()) ?? 0
    }

    /// The current Anki day index for the persisted collection (0 if none).
    static func currentDayIndex(asOf now: Date = .now) -> Int {
        guard exists, let reader = try? AnkiCollectionReader(path: collectionURL.path) else { return 0 }
        return reader.currentDayIndex(now: now)
    }

    /// New cards studied today per deck (Anki id → count), read from Anki's own per-deck
    /// counter in the collection. This is the source of truth Anki uses for the New limit,
    /// so it matches desktop exactly. Counters whose day isn't today resolve to 0.
    static func newStudiedTodayByDeck(asOf now: Date = .now) -> [Int: Int] {
        guard exists, let reader = try? AnkiCollectionReader(path: collectionURL.path) else { return [:] }
        let today = reader.currentDayIndex(now: now)
        let raw = (try? reader.deckDailyNewStudied()) ?? [:]
        let resolved = raw.mapValues { $0.lastDay == today ? $0.newStudied : 0 }
        print("[limits] dayIndex=\(today) raw=\(raw) resolved=\(resolved)")
        return resolved
    }
}
