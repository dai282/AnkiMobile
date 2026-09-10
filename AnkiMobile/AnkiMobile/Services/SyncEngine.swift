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

/// Errors surfaced by a sync engine.
enum SyncError: LocalizedError {
    case invalidCredentials
    case emptyField
    case rateLimited
    case network(String)
    case notImplemented
    /// A normal sync can't reconcile the two collections (schema change, new structural
    /// objects, or a failed sanity check). The user must choose Force Upload or Download.
    case fullSyncRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Incorrect username or password."
        case .emptyField: return "Please enter your email and password."
        case .rateLimited: return "Too many attempts. Please wait a moment and try again."
        case .network(let message): return message
        case .notImplemented: return "Not implemented yet."
        case .fullSyncRequired(let reason): return reason
        }
    }
}

/// A single stage of a progress-sync run, for driving the progress UI.
struct SyncStage {
    let text: String
    let progress: Double
}

/// The outcome of a two-way progress sync.
struct SyncSummary {
    let reviewsSynced: Int
    let decksTouched: Int
    let duration: Double
    /// Reviews pulled down from the server during the sync (symmetric with reviewsSynced).
    var reviewsPulled: Int = 0
}

/// The outcome of pulling decks from the cloud.
struct PullResult {
    let deckName: String
    let newCards: Int
    let sizeMB: Double
}

/// Credentials obtained after a successful login (Anki's `hostKey` + chosen endpoint).
struct SyncCredentials: Equatable {
    let username: String
    let hostKey: String
    let host: String
}

@MainActor
protocol SyncEngine {
    /// Log in with AnkiWeb (or a self-hosted server) credentials, returning a host key.
    func logIn(username: String, password: String, host: String) async throws -> SyncCredentials

    /// Pull decks/cards from the remote into the local store.
    func pullDecks(into context: ModelContext, credentials: SyncCredentials) async throws -> PullResult

    /// Push local review progress upstream and reconcile, reporting each stage.
    func syncProgress(
        in context: ModelContext,
        credentials: SyncCredentials,
        onStage: @escaping (SyncStage) -> Void
    ) async throws -> SyncSummary

    /// Conflict resolution: replace the *server's* collection with our local one
    /// (Anki's full upload). The counterpart "force download" is just `pullDecks`.
    func forceUpload(in context: ModelContext, credentials: SyncCredentials) async throws
}
