# AnkiMobile ↔ Anki Schema Mapping (V2 reference)

How our SwiftData models line up with Anki's collection schema and sync payloads, plus the
concrete changes we must make before real sync works. Sourced from the cloned Anki repo
(`Projects/anki/rslib`); file references included so we can re-verify.

> Scope reminder: v1 stores a **Card** with `front`/`back` directly. Anki has no such thing —
> it separates **notetypes** (templates) → **notes** (field values) → **cards** (one per template).
> Bridging that gap is the main structural work for sync.

---

## 1. Object model: ours vs Anki

| Ours (SwiftData) | Anki | Where Anki stores it |
| --- | --- | --- |
| `Deck` (+ `subdecks`) | Deck | JSON dict in `col.decks` (synced via `ApplyChanges`), `schema11.rs` |
| `Card` (`front`/`back` inline) | **Note** (fields) + **Card** (schedule) + **Notetype** (template) | `notes` + `cards` tables; notetype JSON in `col.models` |
| `ReviewLog` | Revlog entry | `revlog` table; `revlog/mod.rs` |
| — (none yet) | Notetype | JSON in `col.models` |
| — (none yet) | Graves (deletions) | `graves` table |
| — (app-level) | Collection meta (`crt`, `scm`, `usn`, `ls`) | `col` table |

**Key consequence:** each of our `Card`s must, for sync, be represented as **one Anki note + one
Anki card** under a single fixed **"Basic" notetype** (two fields: `Front`, `Back`; one template).
We synthesize the note/notetype; the user never sees them.

---

## 2. Field mapping

### Deck → Anki deck (`col.decks` JSON)
| Ours | Anki | Notes |
| --- | --- | --- |
| `name` (+ parent chain) | `name` | Anki encodes hierarchy in the name with `::` (e.g. `Medical::Pharmacology`). We model it as a parent relationship → flatten to `::` names on sync. |
| `id: UUID` | `id: i64` | Anki deck ids are millisecond integers. **We must add an `ankiDeckId: Int64?`.** |
| — | `usn`, `mod` | **Add** (see §4). |
| `isDownloaded`, `sizeMB`, `iconSystemName`, `subtitle`, `isHighCadence` | — | App-only; not synced. |

### Card → Anki `cards` row (`cards.rs`, `chunks.rs::CardEntry`)
| Ours | Anki col | Conversion |
| --- | --- | --- |
| `state` (`new/learning/review`) | `type` (0 New,1 Learn,2 Review,3 Relearn) + `queue` | `new→(0,0)`, `learning→(1,1)`, `review→(2,2)`. We currently fold Relearn into `learning`; on lapse it is really Relearn(3) — decide whether to distinguish. |
| `due: Date` | `due: i32` | **Context-dependent!** Review → *days since `col.crt`*; Learn → *unix timestamp (secs)*; New → *position*. Needs `col.crt` and per-queue conversion. |
| `interval: Int` (days) | `ivl: u32` (days) | Direct for review; `0` while learning. |
| `ease: Double` (2.5) | `factor: u16` (2500) | `factor = round(ease * 1000)`. |
| `reps`, `lapses` | `reps`, `lapses` | Direct. |
| `learningStep: Int` | `left: u32` | Anki encodes `left = (stepsLeftToday << 16) | stepsLeftTotal`. Approximate from our step index. |
| `id: UUID` | `id: i64`, `nid: i64`, `did: i64` | **Add `ankiCardId`, `ankiNoteId`; derive `did` from the deck.** |
| `isStarred`/`isFlagged` | `flags` (partial) | Anki `flags` is colored flags (1–7); star has no direct equivalent (Anki uses the `marked` tag). Map flag→`flags`, star→a `marked` tag. |
| — | `usn`, `mod`, `odue`, `odid`, `data` | `odue/odid` only for filtered decks (unused). `data` holds FSRS state (unused for SM-2). **Add `usn`,`mod`.** |

### Card → Anki `notes` row (`chunks.rs::NoteEntry`)
| Ours | Anki | Conversion |
| --- | --- | --- |
| `front`, `back` | `flds` | Join as `front \x1f back` (0x1f separator). |
| `tags: [String]` | `tags` | Space-separated string; add `marked` when `isStarred`. |
| — | `guid` | Generate a stable base91 guid per note. |
| — | `mid` | The fixed Basic notetype id. |
| `id` | `id: i64` (`ankiNoteId`) | One note per card (1 template). |
| — | `usn`, `mod`, `sfld`, `csum` | `sfld`/`csum` sent empty during sync; **add `usn`,`mod`.** |

### ReviewLog → Anki `revlog` row (`revlog/mod.rs`)
| Ours | Anki col | Conversion |
| --- | --- | --- |
| `reviewedAt: Date` | `id` (ms) | Milliseconds since epoch; **must be unique** per row (bump by 1ms on collision). |
| `card.ankiCardId` | `cid` | Requires the card's Anki id. |
| `rating` (0…3) | `ease` (1…4) | `ease = rating.rawValue + 1`. |
| `interval` | `ivl` | Days if ≥1; Anki uses **negative = seconds** for sub-day steps. |
| `lastInterval` | `lastIvl` | Same sign convention. |
| `ease: Double` | `factor: u32` | `round(ease * 1000)`. |
| `stateBefore/After` | `type` (0 Learn,1 Review,2 Relearn,…) | Map from the transition. |
| — | `time` (ms answering) | We don't record answer time yet → `0` (or start tracking). |
| `synced` | `usn` | `usn = -1` until pushed, then server usn. |

---

## 3. Sync protocol shape (what we'll implement in V2.2/V2.3)

Ordered calls (`sync/collection/protocol.rs`), JSON bodies, **ZSTD-compressed**, `hkey` in the
`X-AnkiSyncServer` header:

1. `hostKey` — login `{u,p}` → `{key}` (V2.1).
2. `meta` — compare `mod`/`scm`/`usn`; decide no-op / incremental / full sync.
3. `start` — send our `minUsn`; receive remote **graves**.
4. `applyGraves` — send our deletions.
5. `applyChanges` — exchange notetypes, decks, deck configs, tags, collection conf.
6. `chunk` / `applyChunk` — stream `notes` + `cards` + `revlog` in batches of **250** (`CHUNK_SIZE`).
7. `sanityCheck2` → `finish`.

**USN rule:** local rows carry `usn = -1` when changed; only those are sent; server rewrites them
to its current usn on `finish`. We must persist the collection's last-synced usn.

---

## 4. Changes we must make to our models (before V2.2)

Additive, nullable so existing data migrates cleanly:

- **Collection/SyncState** (new, single row or Keychain/UserDefaults): `crt` (creation secs),
  `scm`, `usn` (last synced), `lastSyncMod`. Needed to convert `due` and drive `meta`.
- **Deck**: `ankiDeckId: Int64?`, `usn: Int`, `mod: Int`.
- **Card**: `ankiCardId: Int64?`, `ankiNoteId: Int64?`, `usn: Int`, `mod: Int`.
- **ReviewLog**: `ankiRevlogId: Int64?`, `usn: Int`, `timeTakenMs: Int` (start recording answer time).
- A fixed **Basic notetype** definition (constant id + 2 fields + 1 template) to attach notes to.
- Set `usn = -1` and bump `mod` whenever we mutate any of the above (study rating, edit, pull).

---

## 5. Decisions / open questions

1. **ID allocation:** assign Anki-native integer ids **on first pull/sync** (nullable until then),
   vs. at creation. → Lean: nullable, assign lazily; keep UUID as our primary key.
2. **Scheduler parity:** our SM-2 diverges from Anki's exact steps, so intervals may "jump" after a
   round-trip. Accept minor divergence for v2, or adopt Anki's constants / FSRS later.
3. **Relearn state:** distinguish Relearn(3) from Learn(1) on lapse, or keep folding into `learning`?
   Sync fidelity prefers distinguishing.
4. **Answer-time tracking:** start timing each card so `revlog.time` is meaningful (currently 0).
5. **Full-sync fallback:** implement `upload`/`download` for the schema-changed / first-sync case.

---

_Source: `Projects/anki/rslib/src/{card,revlog,sync/collection,sync/login,storage}` and
`proto/anki/{sync,cards,decks,notetypes}.proto`._
