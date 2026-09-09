//
//  CollectionImporter.swift
//  AnkiMobile
//
//  Materializes a downloaded Anki collection (via AnkiCollectionReader) into our
//  SwiftData Deck/Card models. See docs/SYNC_MAPPING.md for the field mapping.
//
//  Scope (V2.2c): decks (from `::` names), and one Card per Anki card using the
//  note's first field as front and the rest as back. Previously-pulled decks/cards
//  are replaced so re-pulling is idempotent. Seeded/local decks (no Anki id) are kept.
//

import Foundation
import SwiftData

@MainActor
struct CollectionImporter {
    let reader: AnkiCollectionReader
    let context: ModelContext

    /// Deck names in the DB are 0x1f-separated ("::" is only the display form).
    private static let separator = "\u{1f}"
    /// Anki's always-present Default deck.
    private let defaultDeckID = 1

    struct Summary {
        let decks: Int
        let cards: Int
        let topDeckName: String
    }

    func importAll() throws -> Summary {
        let crt = (try? reader.creationEpoch()) ?? 0
        try purgePreviouslyPulled()

        // Read cards/notes first so we can skip the always-present empty "Default" deck.
        let notes = try reader.notesByID()
        let cardRows = try reader.cardRows()
        let usedDeckIDs = Set(cardRows.map(\.did))

        // Decks — create shorter paths first so parents exist before their children.
        let deckRows = try reader.decks()
            .filter { !$0.name.isEmpty }
            .filter { !($0.id == defaultDeckID && !usedDeckIDs.contains(defaultDeckID)) }
            .sorted { components($0.name).count < components($1.name).count }

        var deckByAnkiId: [Int: Deck] = [:]
        var deckByNativeName: [String: Deck] = [:]
        for (index, row) in deckRows.enumerated() {
            let deck = Deck(
                name: lastComponent(row.name),
                subtitle: humanName(row.name),
                iconSystemName: "rectangle.stack.fill",
                isDownloaded: true,
                sizeMB: 0,
                sortOrder: index
            )
            deck.ankiDeckId = row.id
            deck.usn = 0
            if let parent = parentName(of: row.name), let parentDeck = deckByNativeName[parent] {
                deck.parent = parentDeck
            }
            context.insert(deck)
            deckByAnkiId[row.id] = deck
            deckByNativeName[row.name] = deck
        }

        // Cards.
        var imported = 0
        for row in cardRows {
            guard let note = notes[row.nid] else { continue }
            let (front, back) = frontBack(from: note.flds)
            let cardState = state(forType: row.type)
            let card = Card(
                front: front,
                back: back,
                tags: tags(from: note.tags),
                deck: deckByAnkiId[row.did],
                state: cardState,
                due: dueDate(for: row, state: cardState, crt: crt)
            )
            card.interval = max(0, row.ivl)
            card.ease = row.factor > 0 ? Double(row.factor) / 1000.0 : 2.5
            card.reps = row.reps
            card.lapses = row.lapses
            card.ankiCardId = row.id
            card.ankiNoteId = row.nid
            card.usn = 0
            context.insert(card)
            imported += 1
        }

        try context.save()

        let top = deckRows.first { parentName(of: $0.name) == nil }?.name ?? "Collection"
        return Summary(decks: deckByAnkiId.count, cards: imported, topDeckName: lastComponent(top))
    }

    // MARK: - Purge

    private func purgePreviouslyPulled() throws {
        // Deleting pulled decks cascades to their cards; also clear stray pulled cards.
        let decks = try context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.ankiDeckId != nil }))
        decks.forEach(context.delete)
        let cards = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.ankiCardId != nil }))
        cards.forEach(context.delete)
    }

    // MARK: - Field / name helpers

    private func components(_ name: String) -> [String] {
        name.components(separatedBy: Self.separator)
    }

    private func lastComponent(_ name: String) -> String {
        components(name).last ?? name
    }

    private func parentName(of name: String) -> String? {
        var parts = components(name)
        guard parts.count > 1 else { return nil }
        parts.removeLast()
        return parts.joined(separator: Self.separator)
    }

    /// Display form, e.g. "Tofugu Hiragana Anki Deck :: 1: Hiragana".
    private func humanName(_ name: String) -> String {
        components(name).joined(separator: " :: ")
    }

    private func frontBack(from flds: String) -> (String, String) {
        let parts = flds.components(separatedBy: "\u{1f}").map(clean)
        let front = parts.first ?? ""
        let back = parts.dropFirst().joined(separator: "\n\n")
        return (front, back)
    }

    private func tags(from raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "\u{1f}" }).map(String.init)
    }

    /// Strips HTML tags, `[sound:…]` refs, and decodes a few common entities.
    private func clean(_ field: String) -> String {
        var text = field.replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func state(forType type: Int) -> CardState {
        switch type {
        case 1, 3: return .learning   // Learn / Relearn
        case 2: return .review
        default: return .new          // 0
        }
    }

    private func dueDate(for row: AnkiCollectionReader.CardRow, state: CardState, crt: Int) -> Date {
        switch state {
        case .new, .learning:
            return .now  // make available immediately; precise learning-step timing is future work
        case .review:
            return Date(timeIntervalSince1970: TimeInterval(crt + row.due * 86_400))
        }
    }
}
