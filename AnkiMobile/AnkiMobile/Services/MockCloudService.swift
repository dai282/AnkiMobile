//
//  MockCloudService.swift
//  AnkiMobile
//
//  A stand-in for the eventual AnkiWeb sync engine. It only does the two things v1
//  cares about — pull decks and sync progress — with simulated delays. No network.
//

import Foundation
import SwiftData

struct SyncSummary {
    let reviewsSynced: Int
    let decksTouched: Int
    let duration: Double
}

struct SyncStage {
    let text: String
    let progress: Double
}

@MainActor
enum MockCloudService {

    /// The staged progress messages shown while "syncing".
    static let syncStages: [SyncStage] = [
        SyncStage(text: "Connecting to AnkiWeb endpoints…", progress: 0.25),
        SyncStage(text: "Comparing local and cloud revision trees…", progress: 0.60),
        SyncStage(text: "Transferring changed review states…", progress: 0.88),
        SyncStage(text: "Finalizing database consistency…", progress: 1.0),
    ]

    /// Simulates pushing local review progress to AnkiWeb, reporting each stage.
    static func syncProgress(
        context: ModelContext,
        onStage: @escaping (SyncStage) -> Void
    ) async -> SyncSummary {
        for stage in syncStages {
            onStage(stage)
            try? await Task.sleep(for: .milliseconds(450))
        }
        let totalCards = (try? context.fetchCount(FetchDescriptor<Card>())) ?? 0
        return SyncSummary(reviewsSynced: min(totalCards, 42), decksTouched: 3, duration: 0.8)
    }

    /// Simulates pulling a new deck (with a handful of cards) down from the cloud.
    @discardableResult
    static func pullDecks(context: ModelContext) async -> Deck {
        try? await Task.sleep(for: .milliseconds(900))

        let deckCount = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
        let deck = Deck(
            name: "Neuroscience Essentials \(deckCount)",
            subtitle: "Pulled from AnkiWeb",
            iconSystemName: "brain.head.profile",
            isDownloaded: true,
            sizeMB: 5.4,
            sortOrder: deckCount
        )
        context.insert(deck)

        for i in 0..<8 {
            let card = Card(
                front: "Neuro prompt \(i + 1)",
                back: "Answer for neuroscience card \(i + 1).",
                tags: ["Neuroscience"],
                deck: deck,
                state: .new,
                due: .now
            )
            context.insert(card)
        }

        try? context.save()
        return deck
    }
}
