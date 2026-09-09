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

    /// Counts of due/new cards across this deck and its subdecks.
    func counts(asOf now: Date = .now) -> QueueCounts {
        allCards.queueCounts(asOf: now)
    }

    /// Builds the ordered list of cards to study for a given mode.
    /// Only downloaded cards are included.
    func studyQueue(mode: StudyMode = .all, asOf now: Date = .now, newLimit: Int = 20) -> [Card] {
        let cards = studyableCards
        let learning = cards.filter { $0.state == .learning && $0.due <= now }
            .sorted { $0.due < $1.due }
        let review = cards.filter { $0.state == .review && $0.due <= now }
            .sorted { $0.due < $1.due }
        let new = Array(cards.filter { $0.state == .new }.prefix(newLimit))

        switch mode {
        case .all: return learning + review + new
        case .newOnly: return new
        case .reviewsOnly: return review
        }
    }
}
