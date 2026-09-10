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
}
