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

        let payload = try JSONSerialization.data(withJSONObject: ["u": user, "p": password])
        // `resolvedHost` reflects any 308 redirect (e.g. AnkiWeb's shard host), so future
        // requests go straight there.
        let (response, resolvedHost) = try await send(method: "hostKey", host: host, hostKey: "", body: payload)

        let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
        guard let key = object?["key"] as? String, !key.isEmpty else {
            throw SyncError.invalidCredentials
        }
        return SyncCredentials(username: user, hostKey: key, host: resolvedHost)
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

    private let redirectBlocker = RedirectBlocker()

    /// POSTs to `{host}/sync/{method}` with the `anki-sync` header and a zstd body,
    /// following 308 host-moves manually. Returns the decompressed response and the
    /// host that ultimately served it.
    private func send(method: String, host: String, hostKey: String, body: Data) async throws -> (Data, String) {
        var baseHost = normalizedHost(host)
        let compressed = try Zstd.compress(body)

        for _ in 0..<4 {
            guard let url = URL(string: baseHost)?
                .appendingPathComponent("sync")
                .appendingPathComponent(method) else {
                throw SyncError.network("Invalid server URL.")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(try syncHeader(hostKey: hostKey), forHTTPHeaderField: "anki-sync")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = compressed

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request, delegate: redirectBlocker)
            } catch {
                throw SyncError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else {
                throw SyncError.network("No HTTP response from server.")
            }

            switch http.statusCode {
            case 200:
                return (try Zstd.decompress(data), baseHost)
            case 301, 302, 307, 308:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let newBase = Self.baseURLString(from: location) else {
                    throw SyncError.network("Server redirected without a valid location.")
                }
                baseHost = newBase
                continue
            case 403:
                throw SyncError.invalidCredentials
            case 429:
                throw SyncError.rateLimited
            default:
                let text = String(data: (try? Zstd.decompress(data)) ?? data, encoding: .utf8) ?? ""
                throw SyncError.network("Server returned \(http.statusCode). \(text)")
            }
        }
        throw SyncError.network("Too many redirects.")
    }

    /// Extracts a bare `scheme://host[:port]` base from a redirect Location.
    private static func baseURLString(from location: String) -> String? {
        guard let comp = URLComponents(string: location), let scheme = comp.scheme, let host = comp.host else {
            return nil
        }
        return comp.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
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

/// Refuses to auto-follow redirects so `AnkiWebSyncEngine` can handle Anki's 308
/// host-move manually and remember the new endpoint. (Completion-handler form —
/// the async variant triggers a SILGen crash when bridged to ObjC.)
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
