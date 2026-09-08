//
//  AnkiSchema.swift
//  AnkiMobile
//
//  Constants and small helpers for representing our local model in Anki's shape
//  when we sync. See docs/SYNC_MAPPING.md. No networking here — pure conversion.
//

import Foundation

enum AnkiSchema {
    /// The single fixed "Basic" notetype every card is attached to for sync.
    /// (Anki notetype ids are millisecond integers; this one is arbitrary but stable.)
    static let basicNotetypeId = 1_600_000_000_000
    static let basicNotetypeName = "Basic (AnkiMobile)"
    static let fieldNames = ["Front", "Back"]

    /// The 0x1f unit separator Anki uses between note fields.
    static let fieldSeparator = "\u{1f}"

    /// Joins a card's front/back into Anki's `flds` string.
    static func joinedFields(front: String, back: String) -> String {
        [front, back].joined(separator: fieldSeparator)
    }

    /// Splits an Anki `flds` string back into (front, back).
    static func splitFields(_ flds: String) -> (front: String, back: String) {
        let parts = flds.components(separatedBy: fieldSeparator)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    /// Anki encodes deck hierarchy in the name using "::", e.g. "Medical::Pharmacology".
    static func fullDeckName(for deck: Deck) -> String {
        var components = [deck.name]
        var current = deck.parent
        while let parent = current {
            components.insert(parent.name, at: 0)
            current = parent.parent
        }
        return components.joined(separator: "::")
    }

    /// Maps our `CardState` to Anki's (type, queue) integer pair.
    static func typeAndQueue(for state: CardState) -> (type: Int, queue: Int) {
        switch state {
        case .new: return (0, 0)        // New
        case .learning: return (1, 1)   // Learn
        case .review: return (2, 2)     // Review
        }
    }

    /// Anki's ease factor is 10× the percentage (2.5 → 2500).
    static func factor(fromEase ease: Double) -> Int {
        Int((ease * 1000).rounded())
    }

    /// Converts a review card's due date to Anki's "days since collection creation".
    static func reviewDue(_ due: Date, creationEpoch: Int) -> Int {
        let days = (Int(due.timeIntervalSince1970) - creationEpoch) / 86_400
        return max(0, days)
    }
}
