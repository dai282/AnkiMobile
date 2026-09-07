//
//  ReviewLog.swift
//  AnkiMobile
//
//  One entry per card rating. This is the record that a future AnkiWeb "sync
//  progress" step will push upstream, so it mirrors the fields Anki's revlog keeps
//  (button pressed, interval before/after, ease, and card state transition).
//

import Foundation
import SwiftData

@Model
final class ReviewLog {
    var id: UUID
    var reviewedAt: Date

    /// Grading button pressed (see `Rating`).
    var ratingRaw: Int
    /// Interval (days) before this review — Anki's `lastIvl`.
    var lastInterval: Int
    /// Interval (days) after this review — Anki's `ivl`.
    var interval: Int
    /// Ease factor after this review — Anki's `factor`.
    var ease: Double
    /// Card state before / after (see `CardState`).
    var stateBeforeRaw: Int
    var stateAfterRaw: Int

    /// Denormalized card id, kept even if the card is later removed.
    var cardID: UUID
    /// Milliseconds spent answering — Anki's revlog `time` (0 until we track it).
    /// Declaration default lets SwiftData migrate existing rows.
    var timeTakenMs: Int = 0
    /// Anki-native revlog id (ms timestamp), assigned on sync.
    var ankiRevlogId: Int? = nil
    /// Update sequence number: -1 means "not yet pushed to the cloud".
    var usn: Int = -1

    @Relationship var card: Card?

    var rating: Rating { Rating(rawValue: ratingRaw) ?? .good }
    var stateBefore: CardState { CardState(rawValue: stateBeforeRaw) ?? .new }
    var stateAfter: CardState { CardState(rawValue: stateAfterRaw) ?? .review }

    init(
        card: Card,
        rating: Rating,
        lastInterval: Int,
        interval: Int,
        ease: Double,
        stateBefore: CardState,
        stateAfter: CardState,
        timeTakenMs: Int = 0,
        reviewedAt: Date = .now
    ) {
        self.id = UUID()
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.lastInterval = lastInterval
        self.interval = interval
        self.ease = ease
        self.stateBeforeRaw = stateBefore.rawValue
        self.stateAfterRaw = stateAfter.rawValue
        self.cardID = card.id
        self.timeTakenMs = timeTakenMs
        self.usn = -1
        self.card = card
    }
}
