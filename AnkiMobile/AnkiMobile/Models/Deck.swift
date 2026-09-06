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
        self.parent = parent
        self.subdecks = []
        self.cards = []
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

extension Deck {
    /// True if this deck is a top-level deck (no parent).
    var isTopLevel: Bool { parent == nil }

    /// All cards belonging to this deck and, recursively, its subdecks.
    var allCards: [Card] {
        cards + subdecks.flatMap { $0.allCards }
    }

    /// Cards actually available to study — only from downloaded decks.
    /// A "Cloud Only" deck contributes no studyable cards until it is downloaded.
    var studyableCards: [Card] {
        (isDownloaded ? cards : []) + subdecks.flatMap { $0.studyableCards }
    }

    /// True when there is at least one downloaded card to study in this deck tree.
    var isStudyable: Bool { !studyableCards.isEmpty }

    /// Counts of due/new cards across this deck and its subdecks.
    func counts(asOf now: Date = .now) -> QueueCounts {
        var result = QueueCounts()
        for card in allCards {
            switch card.state {
            case .new:
                result.new += 1
            case .learning:
                if card.due <= now { result.learning += 1 }
            case .review:
                if card.due <= now { result.review += 1 }
            }
        }
        return result
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
