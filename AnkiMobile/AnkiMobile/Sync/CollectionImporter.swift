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
        /// Cards present now that weren't in the previous pull (true delta, not the re-import total).
        let newCards: Int
        let topDeckName: String
        /// All media filenames referenced by imported cards (for media download).
        let audioFiles: [String]
    }

    /// - Parameter totalBytes: the collection size to divide across decks for `sizeMB`
    ///   (see below). Pass the exact just-downloaded byte count when known, so the sum of
    ///   per-deck sizes matches what the caller reports as the pull's total size; falls back
    ///   to the on-disk file size, which can run slightly higher due to SQLite WAL/SHM
    ///   journal sidecars picked up while reading.
    func importAll(totalBytes: Int? = nil) throws -> Summary {
        let crt = (try? reader.creationEpoch()) ?? 0
        // Snapshot which Anki cards we already had before we purge + re-import, so we can
        // report how many are genuinely new rather than the full re-imported count.
        let previousCardIDs = try existingPulledCardIDs()
        try purgePreviouslyPulled()

        // Read cards/notes first so we can skip the always-present empty "Default" deck.
        let notes = try reader.notesByID()
        let cardRows = try reader.cardRows()
        let usedDeckIDs = Set(cardRows.map(\.did))

        // Note-type metadata: field names + card templates, so we render front/back the way
        // Anki does (via the template's qfmt/afmt) instead of assuming field 0 is the question.
        let fieldNames = (try? reader.noteFieldNames()) ?? [:]
        let templates = (try? reader.cardTemplates()) ?? [:]
        let noteCSS = (try? reader.noteTypeCSS()) ?? [:]

        // Per-deck new-cards/day limit: deck → config id → new.perDay (protobuf-parsed).
        let configByDeck = (try? reader.deckConfigIDs()) ?? [:]
        let perDayByConfig = (try? reader.deckConfigNewPerDay()) ?? [:]
        func newPerDay(forDeck id: Int) -> Int {
            let configID = configByDeck[id] ?? 1   // 1 = Anki's default config
            return perDayByConfig[configID] ?? 20
        }

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
            deck.newPerDay = newPerDay(forDeck: row.id)
            if let parent = parentName(of: row.name), let parentDeck = deckByNativeName[parent] {
                deck.parent = parentDeck
            }
            context.insert(deck)
            deckByAnkiId[row.id] = deck
            deckByNativeName[row.name] = deck
        }

        // Cards.
        var imported = 0
        var importedCardIDs: Set<Int> = []
        var audioFiles: Set<String> = []
        var cardCountByDeck: [Int: Int] = [:]
        for row in cardRows {
            guard let note = notes[row.nid] else { continue }
            let render = rendered(note: note, ord: row.ord, fieldNames: fieldNames,
                                  templates: templates, css: noteCSS[note.mid] ?? "")
            let cardState = state(forType: row.type)
            let card = Card(
                front: render.front,
                back: render.back,
                tags: tags(from: note.tags),
                deck: deckByAnkiId[row.did],
                state: cardState,
                due: dueDate(for: row, state: cardState, crt: crt)
            )
            card.frontHTML = render.frontHTML
            card.backHTML = render.backHTML
            card.audio = audioRefs(from: note.flds)
            audioFiles.formUnion(card.audio)
            card.interval = max(0, row.ivl)
            card.ease = row.factor > 0 ? Double(row.factor) / 1000.0 : 2.5
            card.reps = row.reps
            card.lapses = row.lapses
            card.ankiCardId = row.id
            card.ankiNoteId = row.nid
            card.usn = 0
            context.insert(card)
            imported += 1
            importedCardIDs.insert(row.id)
            cardCountByDeck[row.did, default: 0] += 1
        }

        // The downloaded collection is a single shared database file, so there's no exact
        // per-deck byte size — approximate each deck's share by its portion of the imported
        // cards, applied to the collection's real size (rather than leaving it at 0).
        let bytes = Double(totalBytes ?? CollectionStore.sizeBytes)
        if imported > 0 {
            for (ankiId, deck) in deckByAnkiId {
                let share = Double(cardCountByDeck[ankiId] ?? 0) / Double(imported)
                deck.sizeMB = share * bytes / (1024 * 1024)
            }
        }

        try context.save()

        let newCards = importedCardIDs.subtracting(previousCardIDs).count
        // A pull can bring down several unrelated top-level decks at once — name the summary
        // after the one deck when there's only one, otherwise say how many rather than
        // arbitrarily picking the first and implying that was the whole pull.
        let topLevelDecks = deckRows.filter { parentName(of: $0.name) == nil }
        let topDeckName: String
        switch topLevelDecks.count {
        case 0: topDeckName = "Collection"
        case 1: topDeckName = lastComponent(topLevelDecks[0].name)
        default: topDeckName = "\(topLevelDecks.count) decks"
        }
        return Summary(decks: deckByAnkiId.count, cards: imported, newCards: newCards,
                       topDeckName: topDeckName, audioFiles: Array(audioFiles))
    }

    /// The Anki ids of cards already imported from a previous pull.
    private func existingPulledCardIDs() throws -> Set<Int> {
        let existing = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.ankiCardId != nil }))
        return Set(existing.compactMap { $0.ankiCardId })
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

    typealias Rendered = (front: String, back: String, frontHTML: String, backHTML: String)

    /// Renders a card the way Anki does: pick the note type's template for this card's `ord`,
    /// substitute `{{Field}}` refs, and produce both a plain-text version (for list previews /
    /// fallback) and a full HTML document (note-type CSS + template markup + scripts) for the
    /// study WebView. Falls back to "field 0 = front, rest = back" if metadata is unavailable.
    private func rendered(note: (flds: String, tags: String, mid: Int), ord: Int,
                          fieldNames: [Int: [String]],
                          templates: [Int: [Int: (q: String, a: String)]],
                          css: String) -> Rendered {
        let values = note.flds.components(separatedBy: "\u{1f}")
        // The template for this ord, or the note type's first template as a fallback.
        let template = templates[note.mid]?[ord] ?? templates[note.mid]?.sorted { $0.key < $1.key }.first?.value
        guard let names = fieldNames[note.mid], let template else {
            let (f, b) = frontBack(from: note.flds)
            return (f, b, "", "")
        }

        var fields: [String: String] = [:]
        for (i, name) in names.enumerated() where i < values.count { fields[name] = values[i] }

        // Question body (with a real input box for {{type:…}}), then the answer body with
        // {{FrontSide}} resolved to a copy of the question that hides the type box (so the empty
        // field doesn't reappear above the revealed answer). `[sound:…]` is stripped — the
        // speaker button handles audio.
        let questionBody = stripSound(renderTemplate(template.q, fields: fields, frontSide: "", typeMode: .input))
        let questionForEmbed = stripSound(renderTemplate(template.q, fields: fields, frontSide: "", typeMode: .hidden))
        let answerBody = stripSound(renderTemplate(template.a, fields: fields, frontSide: questionForEmbed, typeMode: .value))

        let front = clean(questionBody)
        let back = clean(answerBody)
        if front.isEmpty && back.isEmpty {
            let (f, b) = frontBack(from: note.flds)
            return (f, b, "", "")
        }
        return (front, back,
                htmlDocument(body: questionBody, css: css, ord: ord),
                htmlDocument(body: answerBody, css: css, ord: ord))
    }

    /// Wraps rendered card markup in a full HTML document: the note type's CSS plus a dark
    /// baseline our theme can fall back to, and the `card cardN` body class Anki styles against.
    private func htmlDocument(body: String, css: String, ord: Int) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        :root { color-scheme: dark; }
        html { -webkit-text-size-adjust: 100%; }
        body { margin: 0; padding: 0; background: transparent; }
        img { max-width: 100%; height: auto; }
        a { color: #adc6ff; }
        .card { background: transparent; color: #e3e2e6; font-family: -apple-system, system-ui, sans-serif; font-size: 20px; }
        \(css)
        </style>
        </head>
        <body class="card card\(ord + 1)">
        \(body)
        </body>
        </html>
        """
    }

    /// The input box shown on the question side for a `{{type:Field}}` field, mirroring Anki's
    /// type-in-the-answer prompt. We don't grade the typed text (yet); revealing the answer shows
    /// the correct value. Kept simple and theme-neutral so deck CSS can restyle it.
    private static let typeInputHTML = """
    <div style="text-align:center;margin-top:16px;">\
    <input type="text" autocapitalize="off" autocorrect="off" spellcheck="false" \
    style="width:80%;max-width:420px;font-size:20px;padding:10px;border:1px solid #8c909e;\
    border-radius:8px;background:#1a1b1f;color:#e3e2e6;text-align:center;" \
    placeholder="Type the answer"></div>
    """

    /// Removes `[sound:…]` refs from HTML markup (audio is handled by the speaker button).
    private func stripSound(_ html: String) -> String {
        html.replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
    }

    /// How `{{type:Field}}` is rendered: an empty input box (question), nothing (when a question
    /// is embedded into the answer via {{FrontSide}}), or the field value (the answer's own slot).
    private enum TypeMode { case input, hidden, value }

    /// Minimal Anki template renderer: handles `{{#Field}}…{{/Field}}` / `{{^Field}}…{{/Field}}`
    /// conditionals, `{{FrontSide}}`, and `{{Field}}` refs. Filters like `{{hint:Field}}` /
    /// `{{cloze:Field}}` resolve to the field value; `{{type:Field}}` is special-cased so the
    /// question shows an input box rather than leaking the answer.
    private func renderTemplate(_ template: String, fields: [String: String],
                                frontSide: String, typeMode: TypeMode) -> String {
        var result = template

        // 1. Conditional sections. Repeat to resolve sequential and simply-nested blocks.
        let conditional = "\\{\\{([#^])([^}]+)\\}\\}(.*?)\\{\\{/\\2\\}\\}"
        if let regex = try? NSRegularExpression(pattern: conditional, options: [.dotMatchesLineSeparators]) {
            while let m = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                  let full = Range(m.range, in: result),
                  let typeR = Range(m.range(at: 1), in: result),
                  let nameR = Range(m.range(at: 2), in: result),
                  let bodyR = Range(m.range(at: 3), in: result) {
                let negate = result[typeR] == "^"
                let name = String(result[nameR]).trimmingCharacters(in: .whitespaces)
                let hasValue = !(fields[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let include = negate ? !hasValue : hasValue
                result.replaceSubrange(full, with: include ? String(result[bodyR]) : "")
            }
        }

        // 2. FrontSide.
        result = result.replacingOccurrences(of: "{{FrontSide}}", with: frontSide)

        // 3. Field replacements (last match first, so ranges stay valid as we mutate).
        if let regex = try? NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for m in matches.reversed() {
                guard let full = Range(m.range, in: result), let tokR = Range(m.range(at: 1), in: result) else { continue }
                let raw = String(result[tokR]).trimmingCharacters(in: .whitespaces)
                var token = raw
                if let colon = token.lastIndex(of: ":") { token = String(token[token.index(after: colon)...]) }  // strip filter prefix
                let value = fields[token] ?? ""
                let replacement: String
                if raw.hasPrefix("type:") {
                    switch typeMode {
                    case .input:  replacement = Self.typeInputHTML
                    case .hidden: replacement = ""
                    case .value:  replacement = value
                    }
                } else {
                    replacement = value
                }
                result.replaceSubrange(full, with: replacement)
            }
        }
        return result
    }

    private func frontBack(from flds: String) -> (String, String) {
        let parts = flds.components(separatedBy: "\u{1f}").map(clean)
        let front = parts.first ?? ""
        let back = parts.dropFirst().joined(separator: "\n\n")
        return (front, back)
    }

    /// Extracts media filenames from `[sound:filename]` tags across all of a note's fields,
    /// in order. `clean()` strips these from the display text; here we keep the filenames.
    private func audioRefs(from flds: String) -> [String] {
        let pattern = "\\[sound:([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(flds.startIndex..., in: flds)
        return regex.matches(in: flds, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: flds) else { return nil }
            return String(flds[r])
        }
    }

    private func tags(from raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "\u{1f}" }).map(String.init)
    }

    /// Strips HTML tags, `[sound:…]` refs, and decodes a few common entities. Line-breaking
    /// tags (`<br>`, `</div>`, `</p>`, `<hr>`) become newlines first so multi-field answers
    /// (e.g. RTK's kanji + story) don't run together.
    private func clean(_ field: String) -> String {
        var text = field.replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
        // Drop <script>/<style> blocks (content and all) before stripping remaining tags.
        text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</div>|</p>|<hr[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
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
        case .new:
            // For new cards Anki stores the introduction *position* in `due` (1, 2, 3 …), not a
            // date. Encode it as a tiny epoch so the card is available now yet the study queue can
            // sort by it and introduce cards in the same order as desktop.
            return Date(timeIntervalSince1970: TimeInterval(max(0, row.due)))
        case .learning:
            return .now  // make available immediately; precise learning-step timing is future work
        case .review:
            return Date(timeIntervalSince1970: TimeInterval(crt + row.due * 86_400))
        }
    }
}
