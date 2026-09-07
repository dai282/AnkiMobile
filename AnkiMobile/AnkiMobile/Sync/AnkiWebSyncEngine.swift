//
//  AnkiWebSyncEngine.swift
//  AnkiMobile
//
//  Real AnkiWeb / self-hosted sync engine. V2.1b implements login (hostKey);
//  pull and progress sync are implemented in later increments.
//
//  Wire format (verified against Anki's rslib, sync version 11):
//    POST {host}/sync/hostKey
//    Header `anki-sync: {"v":11,"k":"<hkey>","c":"<clientVer>","s":"<sessionKey>"}`
//    Body: zstd(JSON)   Response: zstd(JSON)
//

import Foundation
import SwiftData

@MainActor
struct AnkiWebSyncEngine: SyncEngine {
    private let syncVersion = 11
    private let clientVersion = "ankimobile,1.0,ios"
    private let session = URLSession(configuration: .default)

    // MARK: Login

    func logIn(username: String, password: String, host: String) async throws -> SyncCredentials {
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty else { throw SyncError.emptyField }

        let url = try endpoint(host, method: "hostKey")
        let payload = try JSONSerialization.data(withJSONObject: ["u": user, "p": password])
        let response = try await post(url, hostKey: "", body: payload)

        let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
        guard let key = object?["key"] as? String, !key.isEmpty else {
            throw SyncError.invalidCredentials
        }
        return SyncCredentials(username: user, hostKey: key, host: normalizedHost(host))
    }

    // MARK: Not yet implemented (later V2 increments)

    func pullDecks(into context: ModelContext) async throws -> PullResult {
        throw SyncError.notImplemented
    }

    func syncProgress(
        in context: ModelContext,
        onStage: @escaping (SyncStage) -> Void
    ) async throws -> SyncSummary {
        throw SyncError.notImplemented
    }

    // MARK: HTTP plumbing

    /// Performs a POST to a sync endpoint with the `anki-sync` header and a zstd body,
    /// returning the zstd-decompressed response bytes.
    private func post(_ url: URL, hostKey: String, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(try syncHeader(hostKey: hostKey), forHTTPHeaderField: "anki-sync")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Zstd.compress(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.network("No HTTP response from server.")
        }
        switch http.statusCode {
        case 200:
            return try Zstd.decompress(data)
        case 403:
            throw SyncError.invalidCredentials
        default:
            let text = String(data: (try? Zstd.decompress(data)) ?? data, encoding: .utf8) ?? ""
            throw SyncError.network("Server returned \(http.statusCode). \(text)")
        }
    }

    private func syncHeader(hostKey: String) throws -> String {
        let header: [String: Any] = [
            "v": syncVersion,
            "k": hostKey,
            "c": clientVersion,
            "s": sessionKey(),
        ]
        let data = try JSONSerialization.data(withJSONObject: header)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func endpoint(_ host: String, method: String) throws -> URL {
        guard let base = URL(string: normalizedHost(host)) else {
            throw SyncError.network("Invalid server URL.")
        }
        return base.appendingPathComponent("sync").appendingPathComponent(method)
    }

    private func normalizedHost(_ host: String) -> String {
        var trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { trimmed = AuthController.defaultHost }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private func sessionKey() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}
