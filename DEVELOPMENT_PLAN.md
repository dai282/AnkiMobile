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

### Future (post-v1)
- [ ] Real AnkiWeb pull + progress sync
- [ ] Media assets
- [ ] FSRS scheduler option
- [ ] Full Dynamic Type support (scalable font metrics)
- [ ] Revisit Offline/Media/Cache controls (currently cosmetic — define real behavior)

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
