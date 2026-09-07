//
//  SyncEngine.swift
//  AnkiMobile
//
//  The boundary between the app and "the cloud". v1 ships a mock implementation
//  (`MockSyncEngine`); V2 will add a real AnkiWeb implementation behind the same
//  protocol so the UI never has to change.
//

import Foundation
import SwiftData

/// A single stage of a progress-sync run, for driving the progress UI.
struct SyncStage {
    let text: String
    let progress: Double
}

/// The outcome of pushing local review progress.
struct SyncSummary {
    let reviewsSynced: Int
    let decksTouched: Int
    let duration: Double
}

/// The outcome of pulling decks from the cloud.
struct PullResult {
    let deckName: String
    let newCards: Int
    let sizeMB: Double
}

@MainActor
protocol SyncEngine {
    /// Pull decks/cards from the remote into the local store.
    func pullDecks(into context: ModelContext) async throws -> PullResult

    /// Push local review progress upstream and reconcile, reporting each stage.
    func syncProgress(
        in context: ModelContext,
        onStage: @escaping (SyncStage) -> Void
    ) async throws -> SyncSummary
}
