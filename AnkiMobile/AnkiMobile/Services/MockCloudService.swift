//
//  MockCloudService.swift
//  AnkiMobile
//
//  A stand-in `SyncEngine` for v1. It does the two things v1 cares about — pull
//  decks and sync progress — with simulated delays. No network. It will be joined
//  (and eventually replaced in production) by a real AnkiWeb engine in V2.
//

import Foundation
import SwiftData

@MainActor
struct MockSyncEngine: SyncEngine {

    /// The staged progress messages shown while "syncing".
    private let stages: [SyncStage] = [
        SyncStage(text: "Connecting to AnkiWeb endpoints…", progress: 0.25),
        SyncStage(text: "Comparing local and cloud revision trees…", progress: 0.60),
        SyncStage(text: "Transferring changed review states…", progress: 0.88),
        SyncStage(text: "Finalizing database consistency…", progress: 1.0),
    ]

    func logIn(username: String, password: String, host: String) async throws -> SyncCredentials {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            throw SyncError.emptyField
        }
        try? await Task.sleep(for: .milliseconds(700))
        // The mock accepts any non-empty credentials and returns a fake host key.
        return SyncCredentials(username: username, hostKey: "mock-host-key", host: host)
    }

    func syncProgress(
        in context: ModelContext,
        credentials: SyncCredentials,
        onStage: @escaping (SyncStage) -> Void
    ) async throws -> SyncSummary {
        for stage in stages {
            onStage(stage)
            try? await Task.sleep(for: .milliseconds(450))
        }
        // Use unsynced review logs (usn == -1) as the stand-in for "reviews synced".
        let unsynced = (try? context.fetchCount(
            FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.usn == -1 })
        )) ?? 0
        return SyncSummary(reviewsSynced: min(unsynced, 999), decksTouched: 3, duration: 0.8)
    }

    func forceUpload(in context: ModelContext, credentials: SyncCredentials) async throws {
        try? await Task.sleep(for: .milliseconds(500))
        // The mock has no server; treat force-upload as a successful no-op.
    }

    func checkStatus(in context: ModelContext, credentials: SyncCredentials) async -> SyncStatus {
        let pending = (try? context.fetchCount(
            FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.usn == -1 })
        )) ?? 0
        return SyncStatus(localPending: pending, serverAhead: false, reachable: true, hasCollection: true)
    }

    @discardableResult
    func pullDecks(into context: ModelContext, credentials: SyncCredentials,
                   onStage: @escaping (SyncStage) -> Void) async throws -> PullResult {
        onStage(SyncStage(text: "Downloading decks…", progress: 0.4))
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

        let newCards = 8
        for i in 0..<newCards {
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
        return PullResult(deckName: deck.name, newCards: newCards, sizeMB: deck.sizeMB)
    }
}
