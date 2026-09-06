//
//  SampleData.swift
//  AnkiMobile
//
//  Seeds a set of realistic decks and cards on first launch so the app is
//  immediately usable. Includes two top-level decks — one downloaded and one
//  "Cloud Only" — to demonstrate the download-gated study flow.
//

import Foundation
import SwiftData

enum SampleData {

    /// Seeds sample decks only if the store is empty.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
        guard existing == 0 else { return }
        seed(context)
    }

    static func seed(_ context: ModelContext) {
        let now = Date.now

        // Parent deck 1 — DOWNLOADED — with two subdecks.
        let medical = Deck(name: "Medical & USMLE Step 1",
                           subtitle: "2 subdecks • High cadence",
                           iconSystemName: "cross.case.fill",
                           isHighCadence: true, isDownloaded: true, sizeMB: 26.2, sortOrder: 0)
        let pharma = Deck(name: "Pharmacology",
                          subtitle: "Medical :: Pharmacology",
                          iconSystemName: "pills.fill",
                          isHighCadence: true, isDownloaded: true, sizeMB: 14.2, sortOrder: 0, parent: medical)
        let patho = Deck(name: "Pathology",
                         subtitle: "Medical :: Pathology",
                         iconSystemName: "allergens",
                         isHighCadence: true, isDownloaded: true, sizeMB: 12, sortOrder: 1, parent: medical)
        medical.lastStudied = now.addingDays(-1)

        // Parent deck 2 — CLOUD ONLY (not downloaded) — with two subdecks.
        let language = Deck(name: "Language Learning",
                            subtitle: "2 subdecks • Cloud Only",
                            iconSystemName: "globe",
                            isHighCadence: false, isDownloaded: false, sizeMB: 38, sortOrder: 1)
        let japanese = Deck(name: "Japanese (JLPT N2)",
                            subtitle: "Language :: Japanese",
                            iconSystemName: "character.book.closed.fill",
                            isHighCadence: false, isDownloaded: false, sizeMB: 22, sortOrder: 0, parent: language)
        let mandarin = Deck(name: "Mandarin Chinese (HSK 4)",
                            subtitle: "Language :: Mandarin",
                            iconSystemName: "character.bubble.fill",
                            isHighCadence: false, isDownloaded: false, sizeMB: 16, sortOrder: 1, parent: language)

        // A downloaded top-level deck with no subdecks.
        let cs = Deck(name: "Computer Science & Algorithms",
                      subtitle: "Data structures & complexity",
                      iconSystemName: "terminal.fill",
                      isHighCadence: false, isDownloaded: true, sizeMB: 12, sortOrder: 2)

        [medical, pharma, patho, language, japanese, mandarin, cs].forEach { context.insert($0) }

        populate(pharma, context: context, new: 12, learning: 6, review: 45,
                 topic: "Pharmacology", now: now, authored: Self.pharmaCards)
        populate(patho, context: context, new: 18, learning: 4, review: 60,
                 topic: "Pathology", now: now, authored: Self.pathoCards)
        populate(japanese, context: context, new: 4, learning: 6, review: 35,
                 topic: "Japanese", now: now, authored: Self.jpCards)
        populate(mandarin, context: context, new: 10, learning: 3, review: 20,
                 topic: "Mandarin", now: now, authored: Self.mandarinCards)
        populate(cs, context: context, new: 8, learning: 2, review: 24,
                 topic: "Algorithms", now: now, authored: Self.csCards)

        try? context.save()
    }

    // MARK: - Population helper

    private typealias Authored = (front: String, back: String, tags: [String])

    private static func populate(_ deck: Deck, context: ModelContext,
                                 new: Int, learning: Int, review: Int,
                                 topic: String, now: Date, authored: [Authored]) {
        var reviewRemaining = review

        // Authored cards go in first, as mature review cards due now.
        for (i, item) in authored.enumerated() where reviewRemaining > 0 {
            let card = Card(front: item.front, back: item.back, tags: item.tags,
                            deck: deck, state: .review, due: now)
            card.interval = 15 + i
            card.reps = 6
            context.insert(card)
            reviewRemaining -= 1
        }

        for i in 0..<max(0, reviewRemaining) {
            let card = Card(front: "\(topic) — review prompt \(i + 1)",
                            back: "Concise answer for \(topic) review item \(i + 1).",
                            tags: [topic], deck: deck, state: .review, due: now)
            card.interval = 7
            card.reps = 3
            context.insert(card)
        }

        for i in 0..<learning {
            let card = Card(front: "\(topic) — learning item \(i + 1)",
                            back: "Answer for \(topic) learning item \(i + 1).",
                            tags: [topic], deck: deck, state: .learning, due: now)
            context.insert(card)
        }

        for i in 0..<new {
            let card = Card(front: "\(topic) — new card \(i + 1)",
                            back: "Answer for \(topic) new card \(i + 1).",
                            tags: [topic], deck: deck, state: .new, due: now)
            context.insert(card)
        }
    }

    // MARK: - Authored content

    private static let pharmaCards: [Authored] = [
        ("Mechanism of Action of SGLT-2 Inhibitors\n(e.g., Dapagliflozin, Empagliflozin)?",
         "Inhibits Sodium-Glucose Cotransporter 2 in the renal proximal convoluted tubule, blocking glucose and sodium reabsorption — promoting glucosuria and natriuresis.\n\n• Reduces HbA1c (~0.5–1.0%), modest weight loss, lowers systolic BP.\n• Cardio- and nephroprotective in HFrEF and CKD.",
         ["Endocrinology", "Renal"]),
        ("First-line treatment for anaphylaxis?",
         "Intramuscular epinephrine (0.3–0.5 mg of 1:1000) into the anterolateral thigh. Repeat every 5–15 min as needed.",
         ["Emergency", "Immunology"]),
        ("Mechanism of beta-blockers in heart failure?",
         "Blunt chronic sympathetic overactivation, reducing heart rate and myocardial oxygen demand, and reverse pathological remodeling — improving survival in HFrEF.",
         ["Cardiology"]),
        ("Classic adverse effect of ACE inhibitors?",
         "Dry cough (from bradykinin accumulation) and angioedema. Also hyperkalemia and first-dose hypotension.",
         ["Cardiology", "Renal"]),
        ("Antidote for warfarin overdose with major bleeding?",
         "4-factor prothrombin complex concentrate (PCC) plus IV vitamin K. FFP if PCC unavailable.",
         ["Hematology"]),
    ]

    private static let pathoCards: [Authored] = [
        ("What defines a granuloma?",
         "A focal collection of activated (epithelioid) macrophages, often with a rim of lymphocytes and multinucleated giant cells. Seen in TB, sarcoidosis, and fungal infection.",
         ["Immunology"]),
        ("Reversible vs irreversible cell injury — key hallmark?",
         "Irreversibility is marked by mitochondrial damage and membrane defects → massive calcium influx. Nuclear changes: pyknosis, karyorrhexis, karyolysis.",
         ["General Pathology"]),
    ]

    private static let csCards: [Authored] = [
        ("Average time complexity of quicksort?",
         "O(n log n) on average; O(n²) worst case (already-sorted input with poor pivot). Space O(log n) for recursion.",
         ["Sorting"]),
        ("What is a hash collision and how is it resolved?",
         "Two keys mapping to the same bucket. Resolved via separate chaining (linked lists) or open addressing (linear/quadratic probing, double hashing).",
         ["Data Structures"]),
    ]

    private static let jpCards: [Authored] = [
        ("だいじょうぶ (大丈夫) means?",
         "\"It's okay / all right / fine.\" Common reassurance; also used to politely decline.",
         ["Vocabulary"]),
        ("Difference between は and が (topic vs subject)?",
         "は marks the topic (known/contextual), が marks the grammatical subject (new information or emphasis).",
         ["Grammar"]),
    ]

    private static let mandarinCards: [Authored] = [
        ("你好 (nǐ hǎo) means?",
         "\"Hello.\" The standard everyday greeting.",
         ["Vocabulary"]),
        ("What are the four Mandarin tones?",
         "1st: high level (ā), 2nd: rising (á), 3rd: dipping (ǎ), 4th: falling (à) — plus a neutral tone.",
         ["Pronunciation"]),
    ]
}
