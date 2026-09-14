//
//  MediaStore.swift
//  AnkiMobile
//
//  Location of downloaded media files (audio/images) referenced by cards. Files are
//  stored flat by their Anki filename, alongside the persisted collection. The actual
//  download over Anki's `/msync/` protocol is V2.7b; this just defines where they live
//  and how to look one up.
//

import Foundation

enum MediaStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnkiMedia", isDirectory: true)
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Local URL for a media filename, or nil if it isn't present yet.
    static func existingURL(for filename: String) -> URL? {
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes a downloaded media file into the store.
    static func write(_ data: Data, filename: String) throws {
        try ensureDirectory()
        try data.write(to: directory.appendingPathComponent(filename))
    }

    private static var contents: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    }

    static var fileCount: Int { contents.count }

    static var sizeBytes: Int {
        contents.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Deletes all downloaded media (keeps the collection). Returns the number removed.
    @discardableResult
    static func clear() -> Int {
        let files = contents
        for url in files { try? FileManager.default.removeItem(at: url) }
        return files.count
    }
}
