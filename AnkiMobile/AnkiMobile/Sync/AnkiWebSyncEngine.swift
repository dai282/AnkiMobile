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
    func fetchMeta(_ credentials: SyncCredentials, sessionKey: String? = nil) async throws -> ServerMeta {
        let body = try JSONSerialization.data(withJSONObject: ["v": syncVersion, "cv": clientVersion])
        let (data, _) = try await send(method: "meta", host: credentials.host, hostKey: credentials.hostKey, body: body, sessionKey: sessionKey)
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

        print("[pull] imported decks=\(summary.decks) cards=\(summary.cards) new=\(summary.newCards); persisted \(CollectionStore.collectionURL.lastPathComponent); anchor usn=\(meta.usn) mod=\(meta.modified) scm=\(meta.schema)")

        let mb = Double(dbBytes.count) / (1024 * 1024)
        return PullResult(deckName: summary.topDeckName, newCards: summary.newCards, sizeMB: mb)
    }

    /// Pushes locally-reviewed cards + revlog to the server via Anki's stateful normal
    /// sync (protocol v11), driven off the persisted collection's dirty (usn = -1) rows:
    /// meta → start → applyChanges → chunk(down) → applyChunk(up) → sanityCheck2 → finish.
    /// We only ever review cards, so decks/notetypes/tags/graves are never dirty — the
    /// unchunked-changes payload is empty, which collapses the flow to cards + revlog.
    func syncProgress(
        in context: ModelContext,
        credentials: SyncCredentials,
        onStage: @escaping (SyncStage) -> Void
    ) async throws -> SyncSummary {
        guard CollectionStore.exists else {
            throw SyncError.network("No collection to sync yet — pull decks first.")
        }
        let skey = sessionKey()   // one stable key for the whole stateful sync
        let host = credentials.host, hostKey = credentials.hostKey
        let store = try AnkiCollectionSyncStore(path: CollectionStore.collectionURL.path)

        onStage(SyncStage(text: "Checking server…", progress: 0.05))
        let meta = try await fetchMeta(credentials, sessionKey: skey)
        if !meta.shouldContinue {
            throw SyncError.network(meta.serverMessage.isEmpty ? "Server refused sync." : meta.serverMessage)
        }

        let local = try store.collectionMeta()
        if meta.schema != local.scm {
            throw SyncError.network("The collection changed structurally on the server. Please Pull Decks again.")
        }

        let serverUsn = meta.usn
        let localIsNewer = local.mod > meta.modified

        // "Sync Progress" only pushes review changes. If nothing is dirty locally we're
        // already in sync, so skip the handshake entirely (and the pointless round-trip).
        let cards = try store.pendingCardArrays(usn: serverUsn)
        let revlog = try store.pendingRevlogArrays(usn: serverUsn)
        if cards.isEmpty && revlog.isEmpty {
            onStage(SyncStage(text: "Already up to date", progress: 1))
            return SyncSummary(reviewsSynced: 0, decksTouched: 0, duration: 0)
        }
        let decksTouched = try store.pendingDeckIDs().count

        do {
            // 1. start — exchange deletions. We have none; apply any the server reports.
            onStage(SyncStage(text: "Starting sync…", progress: 0.15))
            let startBody = try JSONSerialization.data(withJSONObject: ["minUsn": local.usn, "lnewer": localIsNewer])
            let (startData, _) = try await send(method: "start", host: host, hostKey: hostKey, body: startBody, sessionKey: skey)
            let graves = jsonObject(startData)
            try store.applyServerGraves(cards: intList(graves["cards"]), notes: intList(graves["notes"]), decks: intList(graves["decks"]))

            // 2. applyChanges — send empty unchunked changes; reconcile the server's.
            onStage(SyncStage(text: "Exchanging changes…", progress: 0.3))
            let changesBody = try JSONSerialization.data(withJSONObject: ["changes": ["models": [], "decks": [[], []], "tags": []]])
            let (changesData, _) = try await send(method: "applyChanges", host: host, hostKey: hostKey, body: changesBody, sessionKey: skey)
            try guardNoStructuralServerChanges(jsonObject(changesData))

            // 3. chunk — download server changes until done (usually nothing for a solo user).
            onStage(SyncStage(text: "Downloading updates…", progress: 0.45))
            while true {
                let (chunkData, _) = try await send(method: "chunk", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
                let chunk = jsonObject(chunkData)
                try store.applyServerRevlog(rowList(chunk["revlog"]))
                try store.applyServerCards(rowList(chunk["cards"]))
                try store.applyServerNotes(rowList(chunk["notes"]))
                if (chunk["done"] as? Bool) ?? false { break }
            }

            // 4. applyChunk — upload our changed cards + revlog (chunks of ≤250 items).
            onStage(SyncStage(text: "Uploading progress…", progress: 0.6))
            try await uploadChunks(cards: cards, revlog: revlog, host: host, hostKey: hostKey, sessionKey: skey)
            try store.stampPushed(usn: serverUsn)   // clear usn=-1 before sanity check

            // 5. sanityCheck2 — server compares table counts (due counts & graves ignored).
            onStage(SyncStage(text: "Verifying…", progress: 0.8))
            let c = try store.sanityCounts()
            let sanityBody = try JSONSerialization.data(withJSONObject: [
                "client": [[0, 0, 0], c.cards, c.notes, c.revlog, c.graves, c.notetypes, c.decks, c.deckConfig]
            ])
            let (sanityData, _) = try await send(method: "sanityCheck2", host: host, hostKey: hostKey, body: sanityBody, sessionKey: skey)
            if (jsonObject(sanityData)["status"] as? String) != "ok" {
                throw SyncError.network("Server sanity check failed. A fresh Pull Decks may be required.")
            }

            // 6. finish — commit; response is the new collection mod time (a bare number).
            onStage(SyncStage(text: "Finalizing…", progress: 0.92))
            let (finishData, _) = try await send(method: "finish", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
            let newMod = parseNumber(finishData) ?? local.mod
            try store.finalize(usn: serverUsn + 1, mod: newMod)

            let sync = SyncState.ensure(in: context)
            sync.lastSyncedUsn = serverUsn + 1
            sync.lastSyncMod = newMod
            try? context.save()

            print("[sync] pushed cards=\(cards.count) revlog=\(revlog.count); anchor usn=\(serverUsn + 1) mod=\(newMod)")
            onStage(SyncStage(text: "Done", progress: 1))
            return SyncSummary(reviewsSynced: revlog.count, decksTouched: decksTouched, duration: 0)
        } catch {
            // Release the server-side transaction so a retry can start cleanly.
            _ = try? await send(method: "abort", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
            throw error
        }
    }

    /// Sends our pending cards + revlog in `applyChunk` requests, always finishing with a
    /// `done: true` chunk (Anki sends one even when there is nothing to upload).
    private func uploadChunks(cards: [[Any]], revlog: [[Any]], host: String, hostKey: String, sessionKey: String) async throws {
        let chunkSize = 250
        var cardQueue = cards, revlogQueue = revlog
        repeat {
            var batchRevlog: [[Any]] = [], batchCards: [[Any]] = []
            var room = chunkSize
            while room > 0, !revlogQueue.isEmpty { batchRevlog.append(revlogQueue.removeLast()); room -= 1 }
            while room > 0, !cardQueue.isEmpty { batchCards.append(cardQueue.removeLast()); room -= 1 }
            let done = cardQueue.isEmpty && revlogQueue.isEmpty
            let body = try JSONSerialization.data(withJSONObject: [
                "chunk": ["done": done, "cards": batchCards, "revlog": batchRevlog]
            ])
            _ = try await send(method: "applyChunk", host: host, hostKey: hostKey, body: body, sessionKey: sessionKey)
            if done { break }
        } while true
    }

    /// We can send empty decks/notetypes/tags, but we can't *merge* structural changes the
    /// server sends back — so bail clearly and let the user re-pull if that ever happens.
    private func guardNoStructuralServerChanges(_ changes: [String: Any]) throws {
        let models = (changes["models"] as? [Any])?.count ?? 0
        let tags = (changes["tags"] as? [Any])?.count ?? 0
        let decksTuple = changes["decks"] as? [Any]
        let decks = (decksTuple?.first as? [Any])?.count ?? 0
        let deckConfig = (decksTuple?.dropFirst().first as? [Any])?.count ?? 0
        if models + tags + decks + deckConfig > 0 {
            throw SyncError.network("The server has deck or note-type changes this app can't merge yet. Please Pull Decks again.")
        }
    }

    // MARK: JSON helpers

    private var emptyBody: Data { Data("{}".utf8) }

    private func jsonObject(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func intList(_ value: Any?) -> [Int] {
        (value as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
    }

    private func rowList(_ value: Any?) -> [[Any]] {
        (value as? [[Any]]) ?? []
    }

    private func parseNumber(_ data: Data) -> Int? {
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), let n = Int(s) {
            return n
        }
        if let n = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? NSNumber {
            return n.intValue
        }
        return nil
    }

    // MARK: HTTP plumbing

    private let redirectBlocker = RedirectBlocker()

    /// POSTs to `{host}/sync/{method}` with the `anki-sync` header and a zstd body,
    /// following 308 host-moves manually. Returns the decompressed response and the
    /// host that ultimately served it.
    /// A stateful normal sync must reuse ONE session key across all its requests, so the
    /// server can correlate start → chunk → finish. `sessionKey` defaults to a fresh random
    /// key, which is correct for the one-shot login/meta/download calls.
    private func send(method: String, host: String, hostKey: String, body: Data, sessionKey: String? = nil) async throws -> (Data, String) {
        var baseHost = normalizedHost(host)
        let skey = sessionKey ?? self.sessionKey()
        let compressed = try Zstd.compress(body)

        for _ in 0..<4 {
            guard let url = URL(string: baseHost)?
                .appendingPathComponent("sync")
                .appendingPathComponent(method) else {
                throw SyncError.network("Invalid server URL.")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(try syncHeader(hostKey: hostKey, sessionKey: skey), forHTTPHeaderField: "anki-sync")
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

    private func syncHeader(hostKey: String, sessionKey: String) throws -> String {
        let header: [String: Any] = [
            "v": syncVersion,
            "k": hostKey,
            "c": clientVersion,
            "s": sessionKey,
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
