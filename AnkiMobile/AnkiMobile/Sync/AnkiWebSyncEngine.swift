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
    /// Returns the parsed meta plus the endpoint that ultimately served it — AnkiWeb
    /// redirects the first call to your account's regional shard, and the rest of the
    /// sync must stay on that host.
    func fetchMeta(_ credentials: SyncCredentials, sessionKey: String? = nil) async throws -> (meta: ServerMeta, host: String) {
        let body = try JSONSerialization.data(withJSONObject: ["v": syncVersion, "cv": clientVersion])
        let (data, resolvedHost) = try await send(method: "meta", host: credentials.host, hostKey: credentials.hostKey, body: body, sessionKey: sessionKey)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let meta = ServerMeta(
            modified: (object["mod"] as? NSNumber)?.intValue ?? 0,
            schema: (object["scm"] as? NSNumber)?.intValue ?? 0,
            usn: (object["usn"] as? NSNumber)?.intValue ?? 0,
            serverMessage: object["msg"] as? String ?? "",
            shouldContinue: object["cont"] as? Bool ?? true,
            empty: object["empty"] as? Bool ?? false
        )
        return (meta, resolvedHost)
    }

    // MARK: Pull / progress (built incrementally across V2.2 / V2.3)

    /// Full-sync download: fetches the entire collection as a `.anki2` SQLite file.
    func downloadCollection(host: String, hostKey: String, sessionKey: String) async throws -> Data {
        let (data, _) = try await send(method: "download", host: host,
                                       hostKey: hostKey, body: Data("{}".utf8), sessionKey: sessionKey)
        return data
    }

    /// Downloads the given media files (by Anki filename) via `/msync/` into the MediaStore,
    /// skipping any already present. Best-effort: returns the number newly stored. Uses the
    /// already-resolved shard `host`. (V2.7b — media download; playback wired in V2.7a.)
    @discardableResult
    func downloadMedia(filenames: [String], host: String, hostKey: String,
                       onProgress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) async throws -> Int {
        let needed = Array(Set(filenames)).filter { MediaStore.existingURL(for: $0) == nil }
        guard !needed.isEmpty else { return 0 }

        let skey = sessionKey()
        // begin — validates the media session; response is JsonResult { data:{usn,sk}, err }.
        let beginBody = try JSONSerialization.data(withJSONObject: ["v": clientVersion])
        let (beginData, _) = try await send(method: "begin", host: host, hostKey: hostKey, body: beginBody, sessionKey: skey, service: "msync")
        if let err = jsonObject(beginData)["err"] as? String, !err.isEmpty {
            throw SyncError.network(err)
        }

        var stored = 0
        onProgress(0, needed.count)
        for batch in needed.chunked(into: 25) {
            let body = try JSONSerialization.data(withJSONObject: ["files": batch])
            let (zip, _) = try await send(method: "downloadFiles", host: host, hostKey: hostKey, body: body, sessionKey: skey, service: "msync")
            for (name, data) in MediaZip.extract(zip) {
                try? MediaStore.write(data, filename: name)
                stored += 1
            }
            onProgress(stored, needed.count)
        }
        print("[media] downloaded \(stored) file(s) of \(needed.count) requested")
        return stored
    }

    func pullDecks(into context: ModelContext, credentials: SyncCredentials,
                   onStage: @escaping (SyncStage) -> Void) async throws -> PullResult {
        let skey = sessionKey()
        onStage(SyncStage(text: "Checking server…", progress: 0.05))
        let (meta, host) = try await fetchMeta(credentials, sessionKey: skey)
        if !meta.shouldContinue {
            throw SyncError.network(meta.serverMessage.isEmpty ? "Server refused sync." : meta.serverMessage)
        }
        if meta.empty {
            return PullResult(deckName: "Server has no decks to pull yet", newCards: 0, sizeMB: 0)
        }

        // First sync from our (non-Anki) local store = full download. Stay on the host meta resolved to.
        onStage(SyncStage(text: "Downloading collection…", progress: 0.15))
        let dbBytes = try await downloadCollection(host: host, hostKey: credentials.hostKey, sessionKey: skey)

        // Persist the collection as the sync source of truth (not a temp file).
        try CollectionStore.ensureDirectory()
        CollectionStore.reset()
        try dbBytes.write(to: CollectionStore.collectionURL)

        // Materialize into our SwiftData store for the UI.
        onStage(SyncStage(text: "Importing cards…", progress: 0.4))
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

        // Fetch referenced media (audio) so the speaker button can play it, unless the user
        // turned media syncing off. Best-effort — never fail the pull over media. Media is the
        // long tail, so map it to 0.5→1.0.
        let mediaSyncing = UserDefaults.standard.object(forKey: "mediaSyncing") as? Bool ?? true
        onStage(SyncStage(text: "Downloading media…", progress: 0.5))
        if mediaSyncing {
        do {
            try await downloadMedia(filenames: summary.audioFiles, host: host, hostKey: credentials.hostKey) { done, total in
                let fraction = total > 0 ? Double(done) / Double(total) : 1
                onStage(SyncStage(text: "Downloading media \(done)/\(total)…", progress: 0.5 + 0.5 * fraction))
            }
        } catch { print("[media] download failed: \(error.localizedDescription)") }
        }

        onStage(SyncStage(text: "Done", progress: 1))
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
            throw SyncError.network("No decks to sync yet — use Download Decks first.")
        }
        let skey = sessionKey()   // one stable key for the whole stateful sync
        let hostKey = credentials.hostKey
        let store = try AnkiCollectionSyncStore(path: CollectionStore.collectionURL.path)

        onStage(SyncStage(text: "Checking server…", progress: 0.05))
        // Stay on whatever host meta resolved to (AnkiWeb shard) for the whole stateful sync.
        let (meta, host) = try await fetchMeta(credentials, sessionKey: skey)
        if !meta.shouldContinue {
            throw SyncError.network(meta.serverMessage.isEmpty ? "Server refused sync." : meta.serverMessage)
        }

        let local = try store.collectionMeta()
        if meta.schema != local.scm {
            throw SyncError.fullSyncRequired("The collection changed structurally on the server (schema mismatch). Choose which copy to keep.")
        }

        let serverUsn = meta.usn
        let localIsNewer = local.mod > meta.modified

        // Two-way progress sync. Run the handshake if EITHER side has changes: local
        // reviews to push (dirty usn=-1 rows) OR the server has moved since our last
        // sync (its mod differs from ours). Only skip when both sides are even.
        let cards = try store.pendingCardArrays(usn: serverUsn)
        let revlog = try store.pendingRevlogArrays(usn: serverUsn)
        let pendingDecks = try store.pendingDeckArrays(usn: serverUsn)
        let haveLocalChanges = !cards.isEmpty || !revlog.isEmpty || !pendingDecks.isEmpty
        let serverMoved = meta.modified != local.mod
        if !haveLocalChanges && !serverMoved {
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

            // 2. applyChanges — send our changed decks (per-deck new-card counters) so the
            //    server/desktop reflect new cards studied in-app; reconcile the server's.
            onStage(SyncStage(text: "Exchanging changes…", progress: 0.3))
            let changesBody = try JSONSerialization.data(withJSONObject: [
                "changes": ["models": [], "decks": [pendingDecks, []], "tags": []]
            ])
            let (changesData, _) = try await send(method: "applyChanges", host: host, hostKey: hostKey, body: changesBody, sessionKey: skey)
            try guardNoNewStructuralObjects(jsonObject(changesData), store: store)
            try store.stampPushedDecks(usn: serverUsn)   // clear usn=-1 on pushed decks before sanity

            // 3. chunk — download server changes until done, applying each to our collection.
            onStage(SyncStage(text: "Downloading updates…", progress: 0.45))
            var reviewsPulled = 0
            while true {
                let (chunkData, _) = try await send(method: "chunk", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
                let chunk = jsonObject(chunkData)
                let revlogRows = rowList(chunk["revlog"]), cardRows = rowList(chunk["cards"]), noteRows = rowList(chunk["notes"])
                try store.applyServerRevlog(revlogRows)
                try store.applyServerCards(cardRows)
                try store.applyServerNotes(noteRows)
                // Count reviews (revlog rows) as the "pulled" unit — symmetric with the pushed
                // count. One study pulls a card row + a revlog row; reporting reviews avoids
                // double-counting the paired card update.
                reviewsPulled += revlogRows.count
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
                throw SyncError.fullSyncRequired("The local and server collections disagree after merge. Choose which copy to keep.")
            }

            // 6. finish — commit; response is the new collection mod time (a bare number).
            onStage(SyncStage(text: "Finalizing…", progress: 0.92))
            let (finishData, _) = try await send(method: "finish", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
            let newMod = parseNumber(finishData) ?? local.mod
            try store.finalize(usn: serverUsn + 1, mod: newMod)

            // Re-project the merged collection into SwiftData so anything pulled down
            // during this sync (new cards, updated scheduling) shows up in the UI.
            onStage(SyncStage(text: "Applying changes…", progress: 0.97))
            let reader = try AnkiCollectionReader(path: CollectionStore.collectionURL.path)
            let projected = try CollectionImporter(reader: reader, context: context).importAll()

            let sync = SyncState.ensure(in: context)
            sync.lastSyncedUsn = serverUsn + 1
            sync.lastSyncMod = newMod
            try? context.save()

            _ = projected  // re-projection side-effect: SwiftData now reflects the merged collection
            print("[sync] pushed cards=\(cards.count) revlog=\(revlog.count); pulled reviews=\(reviewsPulled); anchor usn=\(serverUsn + 1) mod=\(newMod)")
            onStage(SyncStage(text: "Done", progress: 1))
            return SyncSummary(reviewsSynced: revlog.count, decksTouched: decksTouched, duration: 0, reviewsPulled: reviewsPulled)
        } catch {
            print("[sync] failed: \(error.localizedDescription)")
            // Release the server-side transaction so a retry can start cleanly.
            _ = try? await send(method: "abort", host: host, hostKey: hostKey, body: emptyBody, sessionKey: skey)
            throw error
        }
    }

    /// Force Upload: make our local collection the server's authoritative copy (Anki's full
    /// upload). Prepares the collection (clear pending usns/graves, bump usn + schema), then
    /// POSTs the whole `.anki2` to `/sync/upload`. The server validates and replaces its file.
    func forceUpload(in context: ModelContext, credentials: SyncCredentials) async throws {
        guard CollectionStore.exists else {
            throw SyncError.network("Nothing to upload — use Download Decks first.")
        }

        // Prepare + checkpoint in a scope so the connection closes before we read the file.
        do {
            let store = try AnkiCollectionSyncStore(path: CollectionStore.collectionURL.path)
            try store.prepareForFullUpload(now: .now)
            store.close()
        }

        // Resolve the account's shard first, so the (potentially large) upload body isn't
        // sent twice through a redirect.
        let skey = sessionKey()
        let (_, host) = try await fetchMeta(credentials, sessionKey: skey)
        let bytes = try Data(contentsOf: CollectionStore.collectionURL)
        let (response, _) = try await send(method: "upload", host: host,
                                           hostKey: credentials.hostKey, body: bytes, sessionKey: skey)
        let text = (String(data: response, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("OK") else {
            throw SyncError.network(text.isEmpty ? "Upload was rejected by the server." : text)
        }

        // Local is now authoritative and matches the server; refresh our anchor.
        let store = try AnkiCollectionSyncStore(path: CollectionStore.collectionURL.path)
        let meta = try store.collectionMeta()
        let sync = SyncState.ensure(in: context)
        sync.lastSyncedUsn = meta.usn
        sync.lastSyncMod = meta.mod
        sync.schemaMod = meta.scm
        sync.hasCollection = true
        try? context.save()
        print("[upload] forced full upload OK; anchor usn=\(meta.usn) mod=\(meta.mod) scm=\(meta.scm)")
    }

    /// Read-only ahead/behind check: local unsynced reviews vs whether the server has moved
    /// past our recorded anchor. Best-effort — never throws.
    func checkStatus(in context: ModelContext, credentials: SyncCredentials) async -> SyncStatus {
        var status = SyncStatus()
        status.hasCollection = CollectionStore.exists
        status.localPending = CollectionStore.pendingReviewCount()

        // Read the persisted collection's mod (0 if nothing pulled yet). We still probe the
        // server below either way, so a fresh install reports the true online status instead of
        // defaulting to "can't reach the server".
        let localMod: Int
        if status.hasCollection, let store = try? AnkiCollectionSyncStore(path: CollectionStore.collectionURL.path) {
            localMod = (try? store.collectionMeta().mod) ?? 0
        } else {
            localMod = 0
        }

        do {
            let (meta, _) = try await fetchMeta(credentials, sessionKey: sessionKey())
            status.reachable = true
            // Nothing downloaded yet → the cloud has decks to pull. Otherwise use the SAME signal
            // syncProgress gates on (meta.mod vs the persisted col.mod), so "behind" always
            // corresponds to a sync that will actually run and then clear it.
            status.serverAhead = !status.hasCollection || (status.localPending == 0 && meta.modified != localMod)
        } catch {
            status.reachable = false
        }
        return status
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

    /// Updates to existing decks/note types are fine to ignore (sanity only compares row
    /// counts, which don't change). But a *brand-new* deck or note type is unmergeable —
    /// its cards/notes would reference something we don't have — so bail and point the user
    /// at Download Decks. We detect "new" by comparing ids against what we already hold.
    private func guardNoNewStructuralObjects(_ changes: [String: Any], store: AnkiCollectionSyncStore) throws {
        let models = (changes["models"] as? [[String: Any]]) ?? []
        let decks = ((changes["decks"] as? [Any])?.first as? [[String: Any]]) ?? []

        let localDeckIDs = try store.idSet(table: "decks")
        let localModelIDs = try store.idSet(table: "notetypes")
        let newDecks = decks.compactMap { anyID($0["id"]) }.contains { !localDeckIDs.contains($0) }
        let newModels = models.compactMap { anyID($0["id"]) }.contains { !localModelIDs.contains($0) }

        if newDecks || newModels {
            throw SyncError.fullSyncRequired("The server has new decks or note types this app can't merge yet. Choose which copy to keep.")
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

    /// Deck/notetype ids arrive as strings in the schema-11 payloads; cards/graves as numbers.
    private func anyID(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
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
    private func send(method: String, host: String, hostKey: String, body: Data, sessionKey: String? = nil, service: String = "sync") async throws -> (Data, String) {
        var baseHost = normalizedHost(host)
        let skey = sessionKey ?? self.sessionKey()
        let compressed = try Zstd.compress(body)

        for _ in 0..<4 {
            guard let url = URL(string: baseHost)?
                .appendingPathComponent(service)
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
            case 301, 302, 303, 307, 308:
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let newBase = Self.baseURLString(from: location) else {
                    throw SyncError.network("Server redirected without a valid location.")
                }
                print("[sync] \(http.statusCode) redirect \(baseHost) → \(newBase) (via \(location))")
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
            // Default to https for real servers; only local dev hosts are plain http.
            let isLocal = trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1")
            trimmed = (isLocal ? "http://" : "https://") + trimmed
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
