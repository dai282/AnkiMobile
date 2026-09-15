//
//  AnkiCollectionReader.swift
//  AnkiMobile
//
//  Read-only access to a downloaded Anki `.anki2` SQLite collection using the
//  built-in SQLite3 C API (no third-party dependency). Used by the pull flow to
//  inspect and later materialize the downloaded collection.
//

import Foundation
import SQLite3

final class AnkiCollectionReader {
    enum ReaderError: LocalizedError {
        case cannotOpen(String)
        case query(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let p): return "Couldn't open collection at \(p)."
            case .query(let sql): return "Query failed: \(sql)"
            }
        }
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        // Open read-write: Anki collections are in WAL journal mode, and opening a WAL
        // database read-only fails without its -wal/-shm sidecars. The file is our own
        // disposable temp copy, so letting SQLite manage the journal is safe.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? path
            sqlite3_close(db)
            throw ReaderError.cannotOpen(message)
        }
        registerAnkiCollations(on: db)
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    /// Names of all tables in the collection (useful for schema inspection).
    func tableNames() throws -> [String] {
        var names: [String] = []
        try forEachRow("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") { stmt in
            if let c = sqlite3_column_text(stmt, 0) { names.append(String(cString: c)) }
        }
        return names
    }

    /// Row count of a table (table name is internal/trusted).
    func count(_ table: String) throws -> Int {
        try scalarInt("SELECT count(*) FROM \(table)")
    }

    // MARK: - Anki collection queries (modern schema 18)

    /// Collection creation time in epoch seconds (`col.crt`) — used to decode review `due`.
    func creationEpoch() throws -> Int {
        try scalarInt("SELECT crt FROM col LIMIT 1")
    }

    /// All decks as (id, full `::`-delimited name).
    func decks() throws -> [(id: Int, name: String)] {
        var out: [(Int, String)] = []
        try forEachRow("SELECT id, name FROM decks") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            out.append((id, name))
        }
        return out
    }

    /// Notes keyed by id → (fields joined by 0x1f, space-delimited tags, notetype id `mid`).
    /// `mid` lets us look up the note type's field names and card templates so we render
    /// front/back the way Anki does (rather than assuming field 0 is the question).
    func notesByID() throws -> [Int: (flds: String, tags: String, mid: Int)] {
        var map: [Int: (String, String, Int)] = [:]
        try forEachRow("SELECT id, flds, tags, mid FROM notes") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            let flds = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let tags = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let mid = Int(sqlite3_column_int64(stmt, 3))
            map[id] = (flds, tags, mid)
        }
        return map
    }

    struct CardRow {
        let id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses: Int
    }

    /// All cards with their scheduling columns. `ord` selects which of the note type's card
    /// templates this card uses; `due` (for new cards) is the new-card position/order.
    func cardRows() throws -> [CardRow] {
        var out: [CardRow] = []
        try forEachRow("SELECT id,nid,did,ord,type,queue,due,ivl,factor,reps,lapses FROM cards") { stmt in
            out.append(CardRow(
                id: Int(sqlite3_column_int64(stmt, 0)),
                nid: Int(sqlite3_column_int64(stmt, 1)),
                did: Int(sqlite3_column_int64(stmt, 2)),
                ord: Int(sqlite3_column_int64(stmt, 3)),
                type: Int(sqlite3_column_int64(stmt, 4)),
                queue: Int(sqlite3_column_int64(stmt, 5)),
                due: Int(sqlite3_column_int64(stmt, 6)),
                ivl: Int(sqlite3_column_int64(stmt, 7)),
                factor: Int(sqlite3_column_int64(stmt, 8)),
                reps: Int(sqlite3_column_int64(stmt, 9)),
                lapses: Int(sqlite3_column_int64(stmt, 10))
            ))
        }
        return out
    }

    // MARK: - Note types (field names + card templates)

    /// Each note type id → its field names in `ord` order (from the `fields` table).
    func noteFieldNames() throws -> [Int: [String]] {
        var map: [Int: [String]] = [:]
        try forEachRow("SELECT ntid, name FROM fields ORDER BY ntid, ord") { stmt in
            let ntid = Int(sqlite3_column_int64(stmt, 0))
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            map[ntid, default: []].append(name)
        }
        return map
    }

    /// Each note type id → its CSS, parsed from the `notetypes.config` protobuf
    /// (`Notetype.Config.css`, field 3). Drives faithful WebView rendering.
    func noteTypeCSS() throws -> [Int: String] {
        var map: [Int: String] = [:]
        try forEachRow("SELECT id, config FROM notetypes") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            if let bytes = blob(stmt, 1) { map[id] = Self.stringField(3, in: bytes) ?? "" }
        }
        return map
    }

    /// Each note type id → (template `ord` → question/answer format strings), parsed from the
    /// `templates.config` protobuf (`CardTemplateConfig.q_format` field 1, `a_format` field 2).
    func cardTemplates() throws -> [Int: [Int: (q: String, a: String)]] {
        var map: [Int: [Int: (String, String)]] = [:]
        try forEachRow("SELECT ntid, ord, config FROM templates") { stmt in
            let ntid = Int(sqlite3_column_int64(stmt, 0))
            let ord = Int(sqlite3_column_int64(stmt, 1))
            let bytes = blob(stmt, 2) ?? []
            let q = Self.stringField(1, in: bytes) ?? ""
            let a = Self.stringField(2, in: bytes) ?? ""
            map[ntid, default: [:]][ord] = (q, a)
        }
        return map
    }

    // MARK: - Deck config (new cards/day)

    /// Maps each deck id → its config id, parsed from the `decks.kind` protobuf blob
    /// (`KindContainer.Normal.config_id`, both field 1). Filtered decks have no config id.
    func deckConfigIDs() throws -> [Int: Int] {
        var map: [Int: Int] = [:]
        try forEachRow("SELECT id, kind FROM decks") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            if let bytes = blob(stmt, 1), let cid = Self.configID(fromKindBlob: bytes) {
                map[id] = cid
            }
        }
        return map
    }

    /// Maps each deck-config id → its `new.perDay`, parsed from the `deck_config.config`
    /// protobuf blob (`DeckConfig.Config.new_per_day`, field 9).
    func deckConfigNewPerDay() throws -> [Int: Int] {
        var map: [Int: Int] = [:]
        try forEachRow("SELECT id, config FROM deck_config") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            if let bytes = blob(stmt, 1), let perDay = Self.varintField(9, in: bytes) {
                map[id] = Int(perDay)
            }
        }
        return map
    }

    // MARK: - Per-deck daily new counter (Anki's source of truth for the New limit)

    /// Each deck id → (lastDayStudied, newStudied) parsed from the `decks.common` protobuf
    /// (`DeckCommon.last_day_studied` field 3, `new_studied` field 4). This is what Anki uses
    /// to decrement the New count — NOT the revlog.
    func deckDailyNewStudied() throws -> [Int: (lastDay: Int, newStudied: Int)] {
        var map: [Int: (Int, Int)] = [:]
        try forEachRow("SELECT id, common FROM decks") { stmt in
            let id = Int(sqlite3_column_int64(stmt, 0))
            if let bytes = blob(stmt, 1) {
                let lastDay = Int(Self.varintField(3, in: bytes) ?? 0)
                let newStudied = Int(Self.varintField(4, in: bytes) ?? 0)
                map[id] = (lastDay, newStudied)
            }
        }
        return map
    }

    /// An integer value from the `config` table (values are stored as JSON, e.g. `4`, `-720`).
    func configInt(_ key: String) -> Int? {
        var value: Int?
        try? forEachRow("SELECT val FROM config WHERE key = '\(key)'", stopAfterFirst: true) { stmt in
            if let text = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) {
                value = Int(text.trimmingCharacters(in: .whitespaces))
            }
        }
        return value
    }

    /// The current Anki day index (`days_elapsed`) — number of rollovers since collection
    /// creation. Uses the collection's own stored UTC offset and rollover hour (NOT the
    /// device timezone, so it matches desktop even if the simulator's zone is different).
    /// Day boundaries fall at `rolloverHour` local time; shifting timestamps so those land on
    /// 86 400-second multiples turns the calc into a simple day-number difference.
    func currentDayIndex(now: Date = .now) -> Int {
        let crt = (try? creationEpoch()) ?? 0
        let rolloverHour = configInt("rollover") ?? 4
        // Minutes WEST of UTC. Prefer the current local offset; fall back to creation offset.
        let offsetMinutesWest = configInt("localOffset") ?? configInt("creationOffset") ?? 0
        let shift = (-offsetMinutesWest * 60) - (rolloverHour * 3600)
        let dayNumber: (Int) -> Int = { secs in Int(floor(Double(secs + shift) / 86_400.0)) }
        return max(0, dayNumber(Int(now.timeIntervalSince1970)) - dayNumber(crt))
    }

    private func blob(_ stmt: OpaquePointer, _ column: Int32) -> [UInt8]? {
        guard let ptr = sqlite3_column_blob(stmt, column) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, column))
        guard count > 0 else { return nil }
        return [UInt8](UnsafeRawBufferPointer(start: ptr, count: count))
    }

    // MARK: - Minimal protobuf scanning (just enough for the two fields above)

    private static func readVarint(_ bytes: [UInt8], _ i: inout Int) -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while i < bytes.count {
            let b = bytes[i]; i += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    /// Advances `i` past a field's value given its wire type (0=varint,1=64-bit,2=len,5=32-bit).
    private static func skip(wire: Int, _ bytes: [UInt8], _ i: inout Int) {
        switch wire {
        case 0: _ = readVarint(bytes, &i)
        case 1: i += 8
        case 5: i += 4
        case 2: let len = Int(readVarint(bytes, &i)); i += len
        default: i = bytes.count
        }
    }

    /// Returns the varint value of a top-level field number, or nil if absent.
    private static func varintField(_ field: Int, in bytes: [UInt8]) -> UInt64? {
        var i = 0
        while i < bytes.count {
            let tag = readVarint(bytes, &i)
            let f = Int(tag >> 3), wire = Int(tag & 7)
            if f == field && wire == 0 { return readVarint(bytes, &i) }
            skip(wire: wire, bytes, &i)
        }
        return nil
    }

    /// Returns a length-delimited (wire type 2) field decoded as a UTF-8 string, or nil.
    private static func stringField(_ field: Int, in bytes: [UInt8]) -> String? {
        var i = 0
        while i < bytes.count {
            let tag = readVarint(bytes, &i)
            let f = Int(tag >> 3), wire = Int(tag & 7)
            if f == field && wire == 2 {
                let len = Int(readVarint(bytes, &i))
                guard i + len <= bytes.count else { return nil }
                let sub = Array(bytes[i..<i + len])
                return String(decoding: sub, as: UTF8.self)
            }
            skip(wire: wire, bytes, &i)
        }
        return nil
    }

    /// Extracts `Normal.config_id` (field 1 varint) from the `KindContainer` blob, where
    /// `Normal` is submessage field 1.
    private static func configID(fromKindBlob bytes: [UInt8]) -> Int? {
        var i = 0
        while i < bytes.count {
            let tag = readVarint(bytes, &i)
            let f = Int(tag >> 3), wire = Int(tag & 7)
            if f == 1 && wire == 2 {                       // Normal submessage
                let len = Int(readVarint(bytes, &i))
                guard i + len <= bytes.count else { return nil }
                let sub = Array(bytes[i..<i + len])
                return varintField(1, in: sub).map(Int.init)   // config_id
            }
            skip(wire: wire, bytes, &i)
        }
        return nil
    }

    /// A single text value, or nil.
    func scalarText(_ sql: String) throws -> String? {
        var value: String?
        try forEachRow(sql, stopAfterFirst: true) { stmt in
            if let c = sqlite3_column_text(stmt, 0) { value = String(cString: c) }
        }
        return value
    }

    // MARK: - Primitives

    private func scalarInt(_ sql: String) throws -> Int {
        var value = 0
        try forEachRow(sql, stopAfterFirst: true) { stmt in
            value = Int(sqlite3_column_int64(stmt, 0))
        }
        return value
    }

    /// Prepares `sql`, steps it, and invokes `body` for each row.
    private func forEachRow(_ sql: String, stopAfterFirst: Bool = false, _ body: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ReaderError.query(sql)
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            body(stmt)
            if stopAfterFirst { break }
        }
    }
}
