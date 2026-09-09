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

    // MARK: Meta handshake

    /// Server-reported collection metadata (see Anki's `SyncMeta`).
    struct ServerMeta {
        let modified: Int      // "mod" (ms)
        let schema: Int        // "scm" (ms)
        let usn: Int           // "usn"
        let serverMessage: String  // "msg"
        let shouldContinue: Bool   // "cont"
        let empty: Bool            // "empty"
    }

    /// Performs the `meta` handshake, which reveals the server's usn/schema and whether
    /// the remote collection is empty — the basis for deciding what (if anything) to pull.
    func fetchMeta(_ credentials: SyncCredentials) async throws -> ServerMeta {
        let body = try JSONSerialization.data(withJSONObject: ["v": syncVersion, "cv": clientVersion])
        let (data, _) = try await send(method: "meta", host: credentials.host, hostKey: credentials.hostKey, body: body)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ServerMeta(
            modified: (object["mod"] as? NSNumber)?.intValue ?? 0,
            schema: (object["scm"] as? NSNumber)?.intValue ?? 0,
            usn: (object["usn"] as? NSNumber)?.intValue ?? 0,
            serverMessage: object["msg"] as? String ?? "",
            shouldContinue: object["cont"] as? Bool ?? true,
            empty: object["empty"] as? Bool ?? false
        )
    }

    // MARK: Pull / progress (built incrementally across V2.2 / V2.3)

    /// Full-sync download: fetches the entire collection as a `.anki2` SQLite file.
    func downloadCollection(_ credentials: SyncCredentials) async throws -> Data {
        let (data, _) = try await send(method: "download", host: credentials.host,
                                       hostKey: credentials.hostKey, body: Data("{}".utf8))
        return data
    }

    func pullDecks(into context: ModelContext, credentials: SyncCredentials) async throws -> PullResult {
        let meta = try await fetchMeta(credentials)
        if !meta.shouldContinue {
            throw SyncError.network(meta.serverMessage.isEmpty ? "Server refused sync." : meta.serverMessage)
        }
        if meta.empty {
            return PullResult(deckName: "Server has no decks to pull yet", newCards: 0, sizeMB: 0)
        }

        // First sync from our (non-Anki) local store = full download.
        let dbBytes = try await downloadCollection(credentials)

        // Persist the collection as the sync source of truth (not a temp file).
        try CollectionStore.ensureDirectory()
        CollectionStore.reset()
        try dbBytes.write(to: CollectionStore.collectionURL)

        // Materialize into our SwiftData store for the UI.
        let reader = try AnkiCollectionReader(path: CollectionStore.collectionURL.path)
        let crt = (try? reader.creationEpoch()) ?? 0
        let summary = try CollectionImporter(reader: reader, context: context).importAll()

        // Record the sync anchor (server state we're now at) for future incremental push.
        let sync = SyncState.ensure(in: context)
        sync.lastSyncedUsn = meta.usn
        sync.lastSyncMod = meta.modified
        sync.schemaMod = meta.schema
        sync.creationEpoch = crt
        sync.hasCollection = true
        try? context.save()

        print("[pull] imported decks=\(summary.decks) cards=\(summary.cards); persisted \(CollectionStore.collectionURL.lastPathComponent); anchor usn=\(meta.usn) mod=\(meta.modified) scm=\(meta.schema)")

        let mb = Double(dbBytes.count) / (1024 * 1024)
        return PullResult(deckName: summary.topDeckName, newCards: summary.cards, sizeMB: mb)
    }

    func syncProgress(
        in context: ModelContext,
        credentials: SyncCredentials,
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
