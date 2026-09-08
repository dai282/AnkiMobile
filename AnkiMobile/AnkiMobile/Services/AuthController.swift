//
//  AuthController.swift
//  AnkiMobile
//
//  Owns login/logout state for the Sync screen. Credentials live in the Keychain
//  (via KeychainStore); this @Observable wrapper exposes them to SwiftUI and runs
//  login/logout through the injected SyncEngine.
//

import Foundation
import Observation

@Observable
@MainActor
final class AuthController {
    private let engine: any SyncEngine

    private(set) var credentials: SyncCredentials?
    var isLoggedIn: Bool { credentials != nil }

    /// Default endpoint for development — the local self-hosted Anki sync server.
    static let defaultHost = "http://localhost:8080"

    init(engine: any SyncEngine) {
        self.engine = engine
        self.credentials = Self.loadFromKeychain()
    }

    func logIn(username: String, password: String, host: String) async throws {
        let creds = try await engine.logIn(username: username, password: password, host: host)
        saveToKeychain(creds)
        credentials = creds
    }

    func logOut() {
        KeychainStore.clearAll()
        credentials = nil
    }

    // MARK: - Keychain persistence

    private static func loadFromKeychain() -> SyncCredentials? {
        guard
            let key = KeychainStore.string(for: .syncKey),
            let host = KeychainStore.string(for: .syncHost),
            let user = KeychainStore.string(for: .username)
        else { return nil }
        return SyncCredentials(username: user, hostKey: key, host: host)
    }

    private func saveToKeychain(_ creds: SyncCredentials) {
        KeychainStore.set(creds.hostKey, for: .syncKey)
        KeychainStore.set(creds.host, for: .syncHost)
        KeychainStore.set(creds.username, for: .username)
    }
}
