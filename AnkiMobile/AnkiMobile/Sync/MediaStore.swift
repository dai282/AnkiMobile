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
}
