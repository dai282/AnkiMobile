# Anki Mobile (iOS) — Development Plan

A minimal, local-first iOS flashcard app inspired by [Anki](https://github.com/ankitects/anki),
styled with the **"Nocturne Focus"** dark theme (see `DESIGN.md`).

> This plan supersedes the ambitious cloud/sync sections of `PRD.md`. The agreed scope is
> deliberately minimal (see below). `PRD.md` and `DESIGN.md` remain the source of truth for
> **UI/UX and visual design**; this file is the source of truth for **scope and engineering**.

---

## 1. Agreed Scope (v1)

The app is **local-first**. Everything works offline. The cloud does exactly **two** things,
and both are **mocked** in v1 (realistic UI + fake data, no real network):

1. **Pull decks** from the cloud (download decks + cards into local storage).
2. **Sync progress** (push review results / scheduling state up).

Everything else from the PRD (real AnkiWeb protocol, media dedup, Anki-compatible SQLite,
FSRS) is **out of scope** for v1.

### In scope
- 5 screens, matching the design mockups in `assets/`:
  1. Decks Overview
  2. Deck Details
  3. Study Session — Front (question)
  4. Study Session — Back (answer + grading)
  5. Sync & Account (mocked)
- Local persistence with **SwiftData**.
- A working **SM-2** scheduler that updates card intervals when rated Again/Hard/Good/Easy.
- Bottom tab navigation (`Decks`, `Sync`).
- Seeded sample decks/cards so the app is usable on first launch.

### Out of scope (v1)
- Real AnkiWeb authentication and sync protocol.
- Media (audio/images) download & dedup.
- Anki-compatible `.apkg` / SQLite file format.
- Card editing/creation UI, tags management, note types.
- FSRS scheduler (SM-2 only for now).
- iPad-specific layouts (iPhone portrait first).

---

## 2. Tech Stack & Conventions

| Concern | Choice | Web-dev analogy |
| --- | --- | --- |
| UI | SwiftUI | React (declarative, state-driven) |
| Persistence | SwiftData (`@Model`) | Entity Framework (ORM) |
| Async | Swift `async/await` | C# `async/await` |
| Language mode | Swift 5 | — |
| Min iOS | 17.0 (required by SwiftData) | — |
| Devices | iPhone, portrait | — |
| Fonts | System (SF Pro + monospaced) as stand-ins for Manrope / JetBrains Mono | — |
| Icons | SF Symbols (maps the Material Symbols used in mockups) | — |

**Design tokens** (colors, spacing, radii, type scale) from `DESIGN.md` are centralized in
`Theme/` so every screen pulls from one place.

---

## 3. Project Structure

```
Anki IOS/
  AnkiMobile.xcodeproj/
  AnkiMobile/
    AnkiMobileApp.swift        # app entry, SwiftData container, seeding
    RootView.swift             # bottom tab bar (Decks / Sync)
    Theme/
      Palette.swift            # Nocturne Focus colors
      Typography.swift         # type scale + font helpers
      Metrics.swift            # spacing / corner radii
    Models/
      Deck.swift               # SwiftData @Model
      Card.swift               # SwiftData @Model (+ state, scheduling fields)
    Scheduling/
      Scheduler.swift          # SM-2 logic, interval previews
    Features/
      Decks/DecksView.swift
      DeckDetail/DeckDetailView.swift
      Study/StudyView.swift    # front + back states, grading
      Sync/SyncView.swift      # mocked pull + progress sync
    Services/
      SampleData.swift         # seed decks/cards on first launch
      MockCloudService.swift   # fake "pull decks" + "sync progress"
    Components/                # small reusable views (pills, counts, bars)
    Assets.xcassets/
```

---

## 4. Milestones / Task Tracking

Status: [ ] todo · [~] in progress · [x] done

### M0 — Scaffold ✅
- [x] Initialize git repo + `.gitignore`
- [x] Create Xcode project (`AnkiMobile.xcodeproj`), iOS 17, SwiftUI, SwiftData
- [x] Verify empty app builds

### M1 — Foundation ✅
- [x] Theme layer (Palette, Typography, Metrics) from `DESIGN.md`
- [x] SwiftData models (`Deck`, `Card`) + card state enum + scheduling fields
- [x] SM-2 `Scheduler` with interval-preview for the 4 rating buttons
- [x] Sample data seeding on first launch

### M2 — Screens ✅ (builds & runs)
- [x] Root tab navigation (Decks / Sync)
- [x] Decks Overview (daily queue summary, hierarchical deck list, storage badges)
- [x] Deck Details (queue breakdown, study actions, mock sync card)
- [x] Study Session Front (question, tags, Show Answer)
- [x] Study Session Back (answer, 4-button grading, applies scheduler)
- [x] Sync & Account (mocked pull decks + sync progress, toggles, activity log)

### M3 — Polish ✅ (Dynamic Type deferred)
- [x] Card reveal animation + smooth card-to-card transitions
- [x] Haptics on show-answer, rating (per-rating feel), and session completion
- [x] Empty states (no decks / no search matches; "nothing due" vs "all caught up")
- [x] VoiceOver labels on icon buttons and grading buttons
- [ ] Full Dynamic Type — deferred: design uses fixed px sizes; needs a @ScaledMetric pass
- [x] Verify Deck Detail + Study + Sync screens on device/simulator (Decks screen verified)

> **v1 is functionally complete** (all milestones above done; Dynamic Type deferred).
> Everything works locally; the two cloud actions are mocked. V2 makes them real — see §6.

---

## 5. Open Questions / Notes
- Real Manrope / JetBrains Mono fonts can be bundled later; using system fonts now to avoid
  bundling font files.
- "Pull decks" in v1 adds a couple of extra sample decks to demonstrate the flow.
- **Download model:** downloading is a top-level-deck operation — you cannot partially
  download a subdeck. Subdecks inherit the parent's downloaded state. Only downloaded decks
  are studyable and only they count toward the daily queue. Download & "pull cards" actions
  live on the top-level deck; subdecks show Study only (or a prompt to download the parent).
- Seed data ships two parent decks — one downloaded (Medical), one Cloud Only (Language
  Learning) — to visually compare the two states.

---

## 6. V2 Roadmap — Real AnkiWeb Sync

**Goal:** replace the two *mocked* cloud actions with real ones against AnkiWeb — **(1) pull
decks** and **(2) sync progress** — while keeping the app minimal and local-first. Study
always works offline; sync is an explicit action.

> ⚠️ **Reality check.** AnkiWeb's sync is an **undocumented HTTP + Protobuf protocol**, and the
> reference implementation lives in Anki's **Rust** core (`Projects/anki/rslib/src/sync/`). We
> will *reference* it, not port it. This is the riskiest, highest-effort part of the project;
> the protocol can change and there is no official public API. Phased delivery below de-risks it.

### Guiding decisions to confirm before starting
- [ ] **Approach:** talk to AnkiWeb's real sync endpoints directly (reverse-engineered from
      `rslib/src/sync`) vs. self-host an Anki sync server (`anki sync-server`) for testing first.
      Recommended: build against a **self-hosted sync server** first, then point at AnkiWeb.
- [ ] **Scheduler parity:** how closely must our SM-2 match Anki's so intervals don't "jump"
      after a round-trip? Decide acceptable divergence, or adopt Anki's exact constants / FSRS.
- [ ] **Collection ownership:** we sync a subset (decks + review progress). Confirm we won't
      corrupt a collection also used by desktop (start read-only pull; guard the first push).

### V2.0 — Foundations (no network yet)
- [x] Add a **review log** model (`ReviewLog`: card, rating, interval, ease, timestamp) written
      on every rating — required to push progress. Currently we mutate the card in place only.
- [x] Introduce a `SyncEngine` protocol; keep the mock (`MockSyncEngine`) as one implementation
      so the UI stays testable offline.
- [x] **Keychain** storage for credentials/sync key (never in UserDefaults).
- [x] Map our SwiftData models ↔ Anki's note/card/deck/revlog shape — see `docs/SYNC_MAPPING.md`
      (identifies the notes/notetypes gap and the fields we must add before V2.2).

### V2.1 — Authentication
- [x] Login screen (email + password + server field) and connected-account state in the Sync tab.
- [x] `AuthController` + Keychain-backed credentials; real **Log Out** (clears Keychain).
- [x] End-to-end login flow via `MockSyncEngine` (offline-testable; accepts any creds).
- [x] Real `hostKey` network call — verified against Anki's own sync server (HTTP 200).
      Uses sync v11 wire format: `anki-sync` header + zstd(JSON) body/response. Requires the
      `facebook/zstd` SwiftPM package (`Zstd` wrapper) and an ATS local-networking exception.
- [x] Auth errors: empty fields, 403 → invalid credentials, 429 → rate limited, network failure.
- [x] Manual 308 host-redirect handling (follows AnkiWeb's shard move; remembers resolved host).

### V2.2 — Pull decks
- [x] `meta` handshake (server usn/schema/empty) — verified against the real server.
- [x] Full `download`: fetch the collection as a zstd `.anki2` SQLite file (POST `/sync/download`,
      body `{}`). Verified against the real server.
- [x] Parse the downloaded SQLite with the built-in SQLite3 C API (opened read-write to satisfy
      WAL). Modern schema 18: separate `decks`/`notetypes`/`notes`/`cards` tables.
- [x] Materialize into SwiftData: deck hierarchy from `\x1f`-separated names (skip empty Default);
      notes+cards → `Card` (first field = front, rest = back; strip HTML/`[sound:]`); scheduling.
      Idempotent re-pull (replaces prior pulled decks/cards; keeps local seeded decks).
- [x] Surface real pull results in the activity log. **Verified with a real 101-card deck.**

### V2.3 — Sync progress (push) ✅ core done
> **Architecture note:** real push is harder than pull. Our full `download` is *not* a normal-sync
> anchor. To push incrementally we keep a **persisted native `.anki2` collection as the sync source
> of truth**, mirror our study reviews into it (update `cards` + insert `revlog`, mark `usn=-1`,
> bump `col.mod`), then run the normal incremental protocol
> (`start`→`applyChanges`→`chunk`/`applyChunk`→`sanityCheck2`→`finish`). `CardEntry`/`RevlogEntry`
> serialize as JSON **arrays** (serde tuples). Because we only ever *review* cards (never edit
> decks/notes/notetypes), the unchunked-changes payload is empty — the flow reduces to pushing
> changed **cards + revlog**.

- **V2.3a — Persist + anchor** ✅
  - [x] Persist the downloaded `.anki2` at a stable Application Support path (`CollectionStore`)
        instead of a temp file.
  - [x] Record the server sync anchor after a pull (`SyncState`: usn/mod/scm/crt, `hasCollection`).
- **V2.3b — Mirror reviews** ✅
  - [x] On every rating, mirror into the native collection (`AnkiCollectionWriter`): update the
        `cards` row (type/queue/due/ivl/factor/reps/lapses, `mod`, `usn=-1`), append a `revlog`
        entry (`usn=-1`), bump `col.mod` (leave `col.scm` untouched). No-op for locally-seeded
        cards; failures are logged, never fatal.
- **V2.3c — Incremental push protocol** ✅
  - [x] Stateful normal sync (v11) driven off the dirty rows (`AnkiCollectionSyncStore`): one
        stable session key across the whole sync; stamp pushed cards/revlog with the server USN
        before `sanityCheck2`; finalize `col.usn = serverUsn+1`, `col.mod` from `finish`.
  - [x] Register Anki's custom `unicase` collation on every native-collection connection so
        index-backed queries (e.g. `count(*) FROM decks`) work (`AnkiSQLite`).
  - [x] Short-circuit to "Already up to date" when nothing is pending locally.
  - [x] Wire the Sync tab's **Sync Progress** action to the real engine; real activity entries.
        **Verified against a self-hosted Anki sync server** (`[sync] pushed cards/revlog`).
  - [ ] Guarded, not merged: if the server returns structural changes (decks/notetypes/tags) or
        chunked note/card data, we currently bail and ask the user to re-Pull. Full two-way merge
        is future work.
- **V2.3d — Two-way Sync Progress** ✅
  - [x] **Sync Progress** is now two-way: pushes local reviews *and* pulls the server's
        review/scheduling changes (and new cards in existing decks, via `chunk`). Runs the
        handshake when either side has changed; skips only when both are even.
  - [x] After `finish`, re-project the merged `.anki2` into SwiftData so pulled changes show
        in the UI. Activity reports "N pushed · M pulled".
  - [x] Clear separation of concerns: **Download Decks** is now bootstrap / full re-download
        only (and the path for brand-new decks/note types Sync can't merge — Sync tells the
        user to use it). **Sync Progress** owns ongoing two-way progress.
- **V2.3e — Conflict resolution** ✅
  - [x] When a normal sync can't reconcile (schema mismatch, new decks/note types, or a failed
        sanity check) `syncProgress` throws `fullSyncRequired`; the Sync tab shows a **Force
        Upload / Force Download** dialog. The common case still auto-merges by mtime.
  - [x] **Force Download** = full re-download (reuses Download Decks). **Force Upload** = Anki's
        full upload (`before_upload` prep → POST `/sync/upload`), making this device the cloud copy.
- **V2.3f — Real AnkiWeb + polish** ✅
  - [x] **Verified end-to-end against real AnkiWeb** (login, Download Decks, two-way Sync Progress).
        Follow **303** redirects, and keep the whole sync on the account's resolved shard
        (`fetchMeta` returns the host; pull/sync/upload reuse it). Default bare hosts to **https**
        (only `localhost`/`127.0.0.1` stay http).
  - [x] Learn-count consistency: `studyQueue` includes all learning cards (regardless of intraday
        due), matching `queueCounts`, so the in-session pill agrees with the deck views.
- **Known gap (→ V2.5):** the study session caps New at 20/day while the deck views show all new
  cards, so those two disagree above 20. Fixed properly by the daily-limits work in V2.5.

> **V2.3 complete** — real, two-way, Anki-compatible sync verified against AnkiWeb. Merged to `main`.

> **Ordering note:** tests and non-urgent hardening were moved to the end (V2.8) so the feature
> set stabilizes first; the one data-safety item (Pull guard) was pulled forward to V2.4.

### V2.4 — Pull safety
> Pull / Force-Download is a full download-and-replace: it overwrites the persisted `.anki2` and
> would silently discard un-synced local reviews (`usn=-1`). Guard against data loss.
- [ ] Detect unpushed local changes (pending `usn=-1` cards/revlog) before a Pull / Force-Download.
- [ ] Confirm with the user (or auto-Sync-first) before replacing the local collection.

### V2.5 — New-card daily limits (scheduler parity) ✅
> Desktop caps the deck's **New** count at `deck_config.new.perDay` (default 20) and decrements
> it as new cards are introduced each day. We used to show *every* `.new` card, diverging from
> desktop and from our own study session (which caps at 20).
- [x] **Real per-deck limit:** parse each deck's `new.perDay` from the collection — `decks.kind`
      protobuf (`KindContainer.Normal.config_id`) → `deck_config.config` protobuf (`new_per_day`,
      field 9), via a minimal varint scanner in `AnkiCollectionReader`. Stored on `Deck.newPerDay`
      at import (lightweight SwiftData migration, defaults to 20). So a 99/day preset shows 99.
- [x] **Anki-correct summation:** Learning/Review sum over the whole subtree, but **New does not
      add up** — a parent's New is capped by the *parent's* own daily limit (children keep their
      own), matching desktop Anki.
- [x] **New-studied-today = Anki's own per-deck counter, not the revlog.** Anki stores
      `Deck.Common.new_studied` (+ `last_day_studied`) in the deck protobuf and syncs it; it's
      NOT recomputed from the revlog. We read the same counter so the numbers match desktop
      exactly. Three parts:
  - **(1) Read** — parse `new_studied`/`last_day_studied` from each deck's `common` blob; resolve
    against the current Anki day index (`AnkiCollectionReader.currentDayIndex`, computed from
    `crt` + `config.rollover` + `config.localOffset`, independent of the device timezone). A
    deck's OWN counter already includes its subtree (Anki propagates studies to ancestors), so we
    read it directly rather than summing (summing double-counted the parent).
  - **(2) Increment** — answering a new card in-app bumps `new_studied` (+ sets `last_day_studied`)
    in the `.anki2` for the card's deck **and all ancestors**, marking them `usn=-1`. New
    decrements live as you study on the phone.
  - **(3) Push** — the sync's `applyChanges` now serializes changed decks as Anki schema-11 JSON
    (`newToday:[day,count]`, etc.) and sends them, then stamps their usn — so desktop's counter
    matches ours. (Minimal protobuf read/write lives in `AnkiSQLite.Protobuf`.)

### V2.6 — Enhancements & Sync UX ✅ (core)
> Make the push/pull asymmetry legible instead of guesswork.
- [x] **Ahead/behind indicator** on the Sync tab: a status card driven by `SyncEngine.checkStatus`
      (a `meta` check vs our `SyncState` anchor). Shows "N reviews to push" (ahead), "Cloud has new
      changes" (behind, `meta.usn > anchor`), "Up to date", or "Can't reach the server" — with a
      manual refresh, and auto-refresh on appear and after each sync/pull/upload.
- [x] **"Sync before Pull" prompt** — delivered in V2.4 (guards Download against unpushed reviews).
- [x] Honest messaging when the server is ahead (the indicator says "Cloud has new changes — tap
      Sync Progress") instead of a flat "Already up to date".
- [x] Two-way reconcile on Sync — delivered in V2.3d (Sync pulls server changes, no full download).
- [ ] (Deferred) Split the single indicator into *progress* vs *deck-structure* signals, and mirror
      it on the Decks tab. The current combined indicator covers the common case.

### V2.7 — Media (audio/images)
- **V2.7a — Local media plumbing** ✅
  - [x] Preserve `[sound:…]` references on import into `Card.audio` (filenames), while still
        stripping them from the displayed text.
  - [x] `MediaStore` — a flat media directory in Application Support; look up a file by name.
  - [x] Wire the study speaker button: plays the first present media file via `AudioPlayer`
        (AVFoundation); lights up only when the card has audio, no-ops if the file isn't
        downloaded yet.
- **V2.7b — Media download (`/msync/`)** ⬜ (the big part)
  - [ ] Media sync protocol: `begin` → `mediaChanges` → `downloadFiles` (zip) → store into
        `MediaStore`; record media usn. Then the speaker button actually plays.

### V2.8 — Hardening & tests (last)
> Done once the feature set has stabilized.
- [ ] Background/last-sync bookkeeping; retry + offline queueing of pending reviews.
- [ ] Wire the currently-cosmetic **Offline Mode / Media Syncing / Prune Cache** controls, or
      remove them if we decide media is out of scope.
- [ ] Tests: scheduler round-trip, sync reconciliation, auth failure paths.

### Deferred / stretch (not blocking V2)
- [ ] Media hash-based dedup.
- [ ] **FSRS** scheduler option (reference `rslib/src/scheduler/fsrs`).
- [ ] Full **Dynamic Type** support (scalable font metrics via `@ScaledMetric`).
- [ ] iPad layout (only if desired later).
