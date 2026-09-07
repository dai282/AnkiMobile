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
    /// Whether this entry has been pushed to the cloud yet (used by V2 sync).
    var synced: Bool

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
        self.synced = false
        self.card = card
    }
}
