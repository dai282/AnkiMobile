//
//  Card.swift
//  AnkiMobile
//
//  A single flashcard with SM-2 scheduling state.
//

import Foundation
import SwiftData

/// The scheduling state a card is in, mirroring Anki's queue types.
enum CardState: Int, Codable {
    case new = 0
    case learning = 1
    case review = 2
}

@Model
final class Card {
    var id: UUID
    var front: String
    var back: String
    var tags: [String]

    // MARK: Scheduling
    /// Backing storage for `state` (SwiftData persists the raw Int).
    var stateRaw: Int
    /// When this card next becomes due.
    var due: Date
    /// Current review interval in days (0 while in learning).
    var interval: Int
    /// Ease factor (SM-2), typically starts at 2.5.
    var ease: Double
    /// Total number of times answered.
    var reps: Int
    /// Number of times the card lapsed (Again on a review card).
    var lapses: Int
    /// Index into the learning steps while in the learning queue.
    var learningStep: Int

    // MARK: Flags
    var isStarred: Bool
    var isFlagged: Bool

    var createdAt: Date

    // MARK: Sync scaffolding (see docs/SYNC_MAPPING.md)
    /// Anki-native integer ids, assigned lazily on first pull/sync.
    var ankiCardId: Int? = nil
    var ankiNoteId: Int? = nil
    /// Update sequence number: -1 means "changed locally, not yet synced".
    var usn: Int = -1
    /// Last-modified time (epoch seconds), used for sync conflict resolution.
    var mod: Int = 0

    @Relationship var deck: Deck?

    /// Type-safe accessor over `stateRaw`.
    var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    init(
        front: String,
        back: String,
        tags: [String] = [],
        deck: Deck? = nil,
        state: CardState = .new,
        due: Date = .now
    ) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.tags = tags
        self.stateRaw = state.rawValue
        self.due = due
        self.interval = 0
        self.ease = 2.5
        self.reps = 0
        self.lapses = 0
        self.learningStep = 0
        self.isStarred = false
        self.isFlagged = false
        self.createdAt = .now
        self.mod = Int(Date.now.timeIntervalSince1970)
        self.deck = deck
    }

    /// Marks the card as changed locally so the next sync will push it.
    func markDirty(at now: Date = .now) {
        usn = -1
        mod = Int(now.timeIntervalSince1970)
    }
}
