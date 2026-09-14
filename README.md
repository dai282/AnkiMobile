# AnkiMobile

A minimal, **local-first** iOS flashcard app inspired by [Anki](https://github.com/ankitects/anki),
built with SwiftUI + SwiftData and styled with the **"Nocturne Focus"** dark theme. It works
fully offline and syncs two ways with **real AnkiWeb** (or a self-hosted Anki sync server):
pull your decks down, study, and push your progress back — matching desktop Anki's numbers.

> Built as a learning project, from a fully-mocked v1 into a real Anki-compatible sync client.

---

## Features

- **Local-first study** — decks, cards, and scheduling all live on-device; everything works offline.
- **SM-2 scheduler** — Again / Hard / Good / Easy with new → learning → review states and interval previews.
- **Real two-way AnkiWeb sync** (protocol v11):
  - **Pull decks** — downloads the collection, imports decks/cards, keeps the native `.anki2` as the source of truth.
  - **Sync progress** — mirrors each review into the collection and pushes incrementally; two-way merge with conflict resolution.
  - **Ahead / behind status** so you know when the cloud has changes.
- **Anki-faithful daily counts** — reads and updates Anki's own per-deck new-card counter so the New/Learning/Review numbers match desktop exactly.
- **Media (audio)** — downloads `[sound:…]` media over Anki's `/msync/` protocol with staged progress, and plays it in the study view.
- **Nocturne Focus theme** — calm graphite dark palette designed to reduce eye fatigue during long sessions.
- **17 unit tests** (Swift Testing) covering the scheduler, schema mapping, protobuf codec, media-zip reader, and queue counting.

---

## Tech stack

| Concern | Choice |
| --- | --- |
| UI | SwiftUI (declarative, state-driven) |
| Persistence | SwiftData (`@Model`) |
| Async | Swift `async/await` (no Combine) |
| Sync source of truth | Native Anki `.anki2` SQLite collection |
| Sync protocol | Anki sync v11 (zstd-compressed, schema-18 protobuf blobs) — hand-rolled, no external libs |
| Tests | Swift Testing |

Design tokens (colors, spacing, radii, type scale) from `DESIGN.md` are centralized in `Theme/`.

---

## Project structure

```
Anki IOS/
  AnkiMobile/
    AnkiMobile.xcodeproj/
    AnkiMobile/
      AnkiMobileApp.swift        # app entry, SwiftData container, seeding
      RootView.swift             # bottom tab bar (Decks / Sync)
      Theme/                     # Nocturne Focus palette, type scale, metrics
      Models/                    # Deck, Card, ReviewLog, SyncState (@Model)
      Scheduling/Scheduler.swift # SM-2 logic + interval previews
      Features/                  # DecksView, DeckDetailView, StudyView, SyncView
      Services/                  # AuthController, Keychain, AudioPlayer, SyncEngine protocol
      Sync/                      # AnkiWeb sync engine, .anki2 reader/writer,
                                 #   protobuf + zstd + stored-zip codecs, media store
    AnkiMobileTests/             # Swift Testing unit tests
  PRD.md · DESIGN.md · DEVELOPMENT_PLAN.md · docs/SYNC_MAPPING.md
```

See `DEVELOPMENT_PLAN.md` for the full milestone-by-milestone history and `docs/SYNC_MAPPING.md`
for how our models map onto Anki's schema.

---

## Requirements

- **Xcode 26** (or newer)
- **iOS 26.5+** device or simulator (SwiftData + current deployment target)
- An **AnkiWeb account** (or a self-hosted Anki sync server) to sync real decks — optional; the
  app seeds sample decks so it's usable offline on first launch.

---

## Build & run

```bash
git clone https://github.com/dai282/AnkiMobile.git
cd AnkiMobile/AnkiMobile
open AnkiMobile.xcodeproj
```

Then pick a simulator (or your device) and press **⌘R**. To run the tests: **⌘U**.

Bundle identifier: `com.dainguyen.AnkiMobile`.

---

## Syncing with AnkiWeb

1. Go to the **Sync** tab and sign in with your AnkiWeb email + password.
2. **Pull Decks from Cloud** to download your collection.
3. Study — each rating is mirrored into the local `.anki2`.
4. **Sync** pushes your progress back up; the status card shows when you're ahead of / behind the cloud.

> Media downloading can be toggled on the Sync tab. Pruning media frees space and works offline.

---

## License

Personal learning project. Anki is a trademark of Ankitects Pty Ltd; this app is an independent
client and is not affiliated with or endorsed by Ankitects.
