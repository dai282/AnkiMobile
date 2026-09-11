//
//  Deck.swift
//  AnkiMobile
//
//  A deck of cards. Decks can nest (a deck may have subdecks).
//

import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID
    var name: String
    var subtitle: String
    /// SF Symbol name shown next to the deck.
    var iconSystemName: String
    var isHighCadence: Bool

    // MARK: Storage / sync (mocked in v1)
    /// True = local SQLite + media cached. False = "Cloud Only".
    var isDownloaded: Bool
    var sizeMB: Double
    var lastStudied: Date?

    /// New cards allowed per day for this deck (Anki's `deck_config.new.perDay`). Populated
    /// from the pulled collection; defaults to Anki's default. Declaration default keeps
    /// SwiftData's lightweight migration happy.
    var newPerDay: Int = 20

    var sortOrder: Int
    var createdAt: Date

    // MARK: Sync scaffolding (see docs/SYNC_MAPPING.md)
    /// Anki-native integer deck id, assigned lazily on first pull/sync.
    var ankiDeckId: Int? = nil
    /// Update sequence number: -1 means "changed locally, not yet synced".
    var usn: Int = -1
    /// Last-modified time (epoch seconds).
    var mod: Int = 0

    // MARK: Hierarchy
    var parent: Deck?
    @Relationship(deleteRule: .cascade, inverse: \Deck.parent)
    var subdecks: [Deck]

    // MARK: Cards
    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]

    init(
        name: String,
        subtitle: String = "",
        iconSystemName: String = "rectangle.stack",
        isHighCadence: Bool = false,
        isDownloaded: Bool = true,
        sizeMB: Double = 0,
        sortOrder: Int = 0,
        parent: Deck? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.isHighCadence = isHighCadence
        self.isDownloaded = isDownloaded
        self.sizeMB = sizeMB
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.mod = Int(Date.now.timeIntervalSince1970)
        self.parent = parent
        self.subdecks = []
        self.cards = []
    }

    /// Marks the deck as changed locally so the next sync will push it.
    func markDirty(at now: Date = .now) {
        usn = -1
        mod = Int(now.timeIntervalSince1970)
    }
}

// MARK: - Queue counts & study queue

/// A snapshot of how many cards fall into each study bucket.
struct QueueCounts {
    var new = 0
    var learning = 0
    var review = 0
    var total: Int { new + learning + review }

    static func + (lhs: QueueCounts, rhs: QueueCounts) -> QueueCounts {
        QueueCounts(new: lhs.new + rhs.new, learning: lhs.learning + rhs.learning, review: lhs.review + rhs.review)
    }
}


enum StudyMode {
    case all
    case newOnly
    case reviewsOnly
}

extension Array where Element == Card {
    /// Buckets cards into New / Learning / Review. Learning is counted regardless of due
    /// time (a card rated Again/Hard is still "in learning"); review counts only due cards.
    func queueCounts(asOf now: Date = .now) -> QueueCounts {
        var result = QueueCounts()
        for card in self {
            switch card.state {
            case .new: result.new += 1
            case .learning: result.learning += 1
            case .review: if card.due <= now { result.review += 1 }
            }
        }
        return result
    }
}

extension Deck {
    /// True if this deck is a top-level deck (no parent).
    var isTopLevel: Bool { parent == nil }

    /// All cards belonging to this deck and, recursively, its subdecks.
    var allCards: [Card] {
        cards + subdecks.flatMap { $0.allCards }
    }

    /// The top-level ancestor. Download state is decided here — a subdeck cannot be
    /// downloaded independently of its parent.
    var rootDeck: Deck {
        var deck = self
        while let parent = deck.parent { deck = parent }
        return deck
    }

    /// Whether this deck is available offline, following the top-level deck's download
    /// state (subdecks inherit it).
    var isEffectivelyDownloaded: Bool { rootDeck.isDownloaded }

    /// Cards actually available to study — only when the top-level deck is downloaded.
    var studyableCards: [Card] { isEffectivelyDownloaded ? allCards : [] }

    /// True when the deck is downloaded and has at least one card.
    var isStudyable: Bool { isEffectivelyDownloaded && !allCards.isEmpty }

    /// The id of this deck and all descendants (for membership checks).
    var subtreeIDs: Set<UUID> {
        var ids: Set<UUID> = [id]
        for sub in subdecks { ids.formUnion(sub.subtreeIDs) }
        return ids
    }

    /// New cards already introduced today for this deck, from Anki's own per-deck counter
    /// (`newStudiedByDeck`: Anki deck id → new_studied today). Anki propagates each new-card
    /// study up to all ancestor decks, so a deck's OWN counter already includes its subtree —
    /// we read it directly rather than summing (summing would double-count the parent).
    func newStudiedToday(_ newStudiedByDeck: [Int: Int]) -> Int {
        ankiDeckId.flatMap { newStudiedByDeck[$0] } ?? 0
    }

    /// New cards this deck may still introduce today: `newPerDay` minus new studied today.
    /// The limit applies to the deck's whole subtree using the deck's own limit — so New does
    /// NOT sum up the tree (a parent is capped by the parent's limit; children keep their own).
    func newRemainingToday(newStudiedByDeck: [Int: Int]) -> Int {
        max(0, newPerDay - newStudiedToday(newStudiedByDeck))
    }

    /// Counts across this deck and its subdecks. Learning/Review sum over the whole subtree;
    /// New is capped by this deck's daily limit (matching Anki — New doesn't add up).
    func counts(asOf now: Date = .now, newStudiedByDeck: [Int: Int] = [:]) -> QueueCounts {
        var result = allCards.queueCounts(asOf: now)
        result.new = min(result.new, newRemainingToday(newStudiedByDeck: newStudiedByDeck))
        return result
    }

    /// Builds the ordered list of cards to study for a given mode. Only downloaded cards are
    /// included; new cards respect each deck node's daily limit (via `logs`).
    func studyQueue(mode: StudyMode = .all, asOf now: Date = .now, newStudiedByDeck: [Int: Int] = [:]) -> [Card] {
        let cards = studyableCards
        // Include all learning cards regardless of their intraday due time, so the queue
        // matches how learning is counted in the deck views (queueCounts ignores due for
        // learning). Learning steps are minutes away; the session re-shows them anyway.
        let learning = cards.filter { $0.state == .learning }
            .sorted { $0.due < $1.due }
        let review = cards.filter { $0.state == .review && $0.due <= now }
            .sorted { $0.due < $1.due }
        let new = Array(cards.filter { $0.state == .new }.prefix(newRemainingToday(newStudiedByDeck: newStudiedByDeck)))

        switch mode {
        case .all: return learning + review + new
        case .newOnly: return new
        case .reviewsOnly: return review
        }
    }
}
