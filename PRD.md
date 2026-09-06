# Product Requirements Document (PRD)
## Anki Mobile iOS — Minimal & Aesthetic Spaced Repetition Client

---

### 1. Executive Summary & Vision

**Product Name:** Anki Mobile (iOS Client)  
**Platform:** iOS (iPhone-optimized, mobile-first)  
**Target Audience:** Medical students (USMLE), language learners (JLPT), software engineers, academics, and high-volume spaced repetition practitioners who demand high retention without visual fatigue.  
**Core Problem:** The official desktop Anki client and default mobile clients can feel cluttered, visually dated, or overly complex. High-contrast OLED dark modes frequently induce eye fatigue during intense multi-hour study sessions.  
**Product Vision:** A minimalist, distraction-free iOS companion that honors Anki's battle-tested spaced repetition algorithms (SM-2 / FSRS) while delivering an eye-friendly, calm visual hierarchy ("Nocturne Focus") and seamless two-way synchronization with AnkiWeb.

---

### 2. Design System & Aesthetic Foundation

The app adheres to Apple Human Interface Guidelines (HIG) with a tailored design language:

- **Theme ("Nocturne Focus"):**
  - **Surfaces:** Deep charcoal and graphite tonal layers (`#121316`, `#1a1b1f`, `#23252a`) avoiding high-fatigue pure pitch-black OLED contrast.
  - **Accents & Pacing:**
    - *New Cards:* Soft Cornflower Blue (`#4f8cf6`)
    - *Learning Cards:* Muted Warm Amber (`#e5a93c`)
    - *Review Cards:* Calm Sage Green (`#4ade80`)
    - *Destructive / Reset:* Subdued Terra Cotta (`#f87171`)
  - **Typography:** Clean sans-serif (Manrope / SF Pro Display & Text) with intentional typographic rhythm and high legibility for technical and scientific terms.
  - **Component Styling:** 8px–16px rounded corners, hairline micro-borders (`rgba(255, 255, 255, 0.06)`), and tactile touch targets (minimum 44x44pt).

---

### 3. Key Personas & Use Cases

1. **Alex (Medical Student - USMLE Step 1):**
   - *Behavior:* Reviews 400–800 cards daily across pharmacology and pathology decks.
   - *Need:* Rapid card flipping, low eye strain during night shifts, ability to cram "Reviews Only" before ward rounds, and clear indicator of sync status.
2. **Kenji (Language Learner - JLPT N2):**
   - *Behavior:* Studies Kanji and grammar in transit with spotty cellular reception.
   - *Need:* Reliable offline storage with selective deck caching ("Downloaded" vs "Cloud Only"), clean audio triggers, and fast card flip gestures.

---

### 4. Detailed Feature Breakdown & Screen Flows

#### 4.1 Screen 1: Decks Overview (`Decks - Anki Mobile`)
- **Daily Queue Summary Card:**
  - Aggregated counts across all decks: **New** cards, **Learning** cards, and **To Review** cards.
  - Tri-color proportional progress bar showing current session distribution.
- **Top Navigation Bar:**
  - Global profile avatar & sync status pill (`Synced`, `Syncing...`, `Offline Ready`).
  - Search bar supporting deck filtering, tags, and note attributes.
- **Hierarchical Deck List:**
  - Collapsible deck folders (e.g., `Medical & USMLE Step 1` with subdecks `Pharmacology` and `Pathology`).
  - Distinct count pill indicators per deck row (`New`, `Learn`, `Due`).
  - **Offline Storage Status Badges:**
    - Green pill: `Downloaded (12 MB)` — indicates local SQLite database and media assets are cached.
    - Neutral grey pill: `Cloud Only (38 MB)` — deck metadata is indexed, but media/card bodies remain remote.
- **Persistent Bottom Navigation:**
  - Two primary tabs: `Decks` and `Sync`.

---

#### 4.2 Screen 2: Deck Details & Study Configuration (`Deck Details - Pharmacology`)
- **Deck Header & Pacing:**
  - Back button navigation (`< Decks`), deck taxonomy (`Medical :: Pharmacology`), cadence tags (`High Cadence`), and card count (`420 cards total`).
- **Queue Breakdown:**
  - Granular cards for New (`12`), Learn (`6`), and Review (`45`) with expected session duration (`~25 mins`).
- **Targeted Study Actions:**
  - **Primary Action:** `Study All Due Cards (63)` button.
  - **Filtered Study Modes:**
    - `New Only (12)`: Focuses exclusively on unseen cards.
    - `Reviews Only (45)`: Focuses strictly on cards past learning intervals to clear backlog.
- **Differential Cloud Sync & Cache Card:**
  - **State Detection:** Detects remote changes committed from desktop or web (`+8 Cards Remote Changes Detected`).
  - **Action:** `Pull 8 Cards & Updates · 1.4 MB` to perform incremental note updates without full re-download.
  - Local device footprint metrics (`14.2 MB on device`) and manual `Re-download Media` diff checker.

---

#### 4.3 Screen 3: Flashcard Study — Front State (`Study Session - Front`)
- **Header:**
  - Navigation back to Deck Details, deck path, and session card queue pill (`12 New`, `5 Learn`, `38 Due`, `Card 55/120`).
  - Card utilities: Tag chips (`#Endocrinology`, `#Renal`), Audio readout, Star/Flag, and Edit.
- **Card Body (Question Area):**
  - Distraction-free question prompt (e.g., *"Mechanism of Action of SGLT-2 Inhibitors"*).
  - Strict absence of answer leaks or grading buttons to enforce genuine active recall.
- **Action Control:**
  - Full-width tactile **"Show Answer"** button.
  - Supports keyboard shortcuts (Spacebar) and swipe-up gesture to reveal.

---

#### 4.4 Screen 4: Flashcard Study — Back State (`Study Session - Pharmacology`)
- **Answer Presentation:**
  - Preserves question prompt with an subtle `Answer Revealed` divider.
  - High-readability formatting: bold semantic highlights for key mechanisms, clinical outcome badges, and anatomical diagrams/site breakdowns.
- **Spaced Repetition Grading Bar (4-Button SM-2/FSRS Layout):**
  - **Again (`<1m`):** Red hue, resets card step.
  - **Hard (`12m`):** Amber hue, minor interval progression.
  - **Good (`1d`):** Sage green hue, standard progression.
  - **Easy (`4d`):** Cornflower blue hue, accelerated ease multiplier.

---

#### 4.5 Screen 5: AnkiWeb Sync & Account (`Account & Sync`)
- **Connected Profile:**
  - Authenticated AnkiWeb email account, connection status badge, and manual `Sync Progress` trigger.
- **Offline & Storage Controls:**
  - `Full Offline Mode` toggle: Automatically keeps all decks and media cached locally for zero-latency airplane/hospital use.
  - `Media Syncing` toggle: Restricts large audio/image downloads to Wi-Fi.
  - Cache allocation bar (DB size vs Media size) with a one-tap `Prune Cache` utility.
- **Recent Activity Log (Constrained to 2 Strict Activity Types):**
  1. **`Progress Synced`**:
     - Logs review submissions and interval updates (e.g., *"42 reviews synced, scheduling intervals updated across 3 decks · 0.8s"*).
  2. **`Deck Updated`**:
     - Logs card/note additions, deck downloads, or remote pulls (e.g., *"Medical :: Pharmacology · 8 new cards and note templates pulled from AnkiWeb · +8 Cards Added · 1.4 MB"*).
- **Session Actions:**
  - Secure `Log Out` button with local data clearing confirmation.

---

### 5. Technical & Sync Architecture

1. **Local Storage:** SQLite relational database mirroring the Anki 2.1 schema (notes, cards, revlog, col).
2. **Media Storage:** Sandboxed filesystem storage with hash-based deduplication (`collection.media`).
3. **AnkiWeb Sync Engine:**
   - Incremental 2-way sync using chunked changesets (avoiding full database downloads where possible).
   - Fast review log sync (<1s on typical cellular connections).
   - Fallback conflict resolution (Force Upload / Force Download modal).
4. **Scheduling Compatibility:** Native support for standard Anki SM-2 and next-gen FSRS (Free Spaced Repetition Scheduler) retention curves.

---

### 6. Non-Functional Requirements & Success Metrics

- **Performance:**
  - Card flip animation latency < 16ms (60–120 fps ProMotion support).
  - App cold launch to daily queue in under 1.2 seconds.
- **Reliability:**
  - Zero review loss; atomic SQLite commits per card rating before sync dispatch.
- **Accessibility:**
  - Full Dynamic Type support, VoiceOver labels on flashcard state changes, and high contrast WCAG AA compliance even in low-fatigue dark mode.
