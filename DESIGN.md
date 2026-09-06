---
name: Nocturne Focus
colors:
  surface: '#121316'
  surface-dim: '#121316'
  surface-bright: '#38393c'
  surface-container-lowest: '#0d0e11'
  surface-container-low: '#1a1b1f'
  surface-container: '#1f1f23'
  surface-container-high: '#292a2d'
  surface-container-highest: '#343538'
  on-surface: '#e3e2e6'
  on-surface-variant: '#c2c6d5'
  inverse-surface: '#e3e2e6'
  inverse-on-surface: '#2f3033'
  outline: '#8c909e'
  outline-variant: '#424753'
  surface-tint: '#adc6ff'
  primary: '#adc6ff'
  on-primary: '#002e69'
  primary-container: '#528ff9'
  on-primary-container: '#00285c'
  inverse-primary: '#005bc1'
  secondary: '#75daa8'
  on-secondary: '#003823'
  secondary-container: '#008056'
  on-secondary-container: '#d1ffe3'
  tertiary: '#fdb96f'
  on-tertiary: '#492900'
  tertiary-container: '#c18440'
  on-tertiary-container: '#402300'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc6ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004494'
  secondary-fixed: '#92f7c3'
  secondary-fixed-dim: '#75daa8'
  on-secondary-fixed: '#002113'
  on-secondary-fixed-variant: '#005235'
  tertiary-fixed: '#ffdcbc'
  tertiary-fixed-dim: '#fdb96f'
  on-tertiary-fixed: '#2c1700'
  on-tertiary-fixed-variant: '#683c00'
  background: '#121316'
  on-background: '#e3e2e6'
  surface-variant: '#343538'
typography:
  display:
    fontFamily: manrope
    fontSize: 34px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: manrope
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: manrope
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: -0.005em
  body-lg:
    fontFamily: manrope
    fontSize: 19px
    fontWeight: '400'
    lineHeight: 28px
    letterSpacing: -0.005em
  body-md:
    fontFamily: manrope
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0em
  body-sm:
    fontFamily: manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  label-md:
    fontFamily: manrope
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: manrope
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
  mono-metric:
    fontFamily: jetbrainsMono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: -0.01em
  mono-metric-sm:
    fontFamily: jetbrainsMono
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
    letterSpacing: 0em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  space-2xs: 0.25rem
  space-xs: 0.5rem
  space-sm: 0.75rem
  space-md: 1rem
  space-lg: 1.25rem
  space-xl: 1.5rem
  space-2xl: 2rem
  space-3xl: 2.5rem
  margin-mobile: 1rem
  margin-tablet: 1.5rem
  gutter: 0.75rem
---

## Brand & Style

This design system crafts a calm, tactile sanctuary for disciplined learners. Modern spaced repetition software often defaults to high-contrast, pure-black (#000000) OLED themes that strain the eyes during long nocturnal study sessions, or stark clinical utility that strips away emotional satisfaction. This system replaces harsh polarities with rich, restorative charcoal and warm graphite surfaces, creating a physical, paper-like weight in digital space.

The target audience includes medical students, language learners, polymaths, and researchers who spend hours immersed in dense flashcards and memory consolidation. The emotional response should be one of deep focus, serenity, and quiet momentum—reminiscent of a quiet library desk illuminated by a warm lamp at 2:00 AM. 

The aesthetic is a hybrid of **Quiet Tactile Minimalism** and **Subtle Glassmorphism**:
- Low-contrast surface stacking to establish gentle depth without visual noise.
- Translucent frosted chrome and tactile card physics to give weight to memory actions.
- Soft luminescence rather than sharp specular glare.
- Generous internal padding and calm spacing rhythms that eliminate interface anxiety.

## Colors

The palette is engineered around soft luminescence, ensuring prolonged legibility without retinal fatigue. Pure black and pure white are strictly forbidden.

### Surface Architecture
- **Canvas Base (`#16171a`):** Deep charcoal canvas ground. Absorbs glare while avoiding the dead feeling of pitch-black.
- **Card Base (`#1c1d22`):** Primary structural surface for flashcard decks, review panes, and list containers.
- **Elevated Surface (`#24262d`):** Secondary layer for active flashcards, modals, and sheet views.
- **Floating Surface (`#2f313a`):** Popovers, active pills, segmented control throttles, and toolbars.

### Typography & Grayscale
- **Text Primary (`#e2e4ea`):** Muted pearl white. Holds high contrast against charcoal backgrounds without blooming or burning into the retina.
- **Text Secondary (`#9ba1b0`):** Soft silver slate for card metadata, retention intervals, and subheaders.
- **Text Muted / Tertiary (`#6c7280`):** Muted graphite for timestamps, hints, and structural markers.
- **Hairline Border (`rgba(255, 255, 255, 0.07)`): Subtle interior defining lines that separate stacked surfaces without creating sharp grid lines.

### Functional Study Telemetry
Accent hues are desaturated and softened, deliberately tuned to evoke calm progression rather than urgent alerts:
- **Primary / Learning (`#4f8cf6`):** Muted cornflower blue. Denotes active review, primary navigation, and "Good" intervals.
- **Success / Mature (`#52b788`):** Soft sage green. Denotes "Easy", mastered card telemetry, and consistent retention.
- **Warning / Hard (`#e09f58`):** Gentle warm amber. Denotes "Hard" difficulty, streaks, and warning thresholds.
- **Critical / Again (`#e06c75`):** Muted coral rose. Denotes "Again" lapses and reset buttons, gentle enough to prevent discouragement.

## Typography

The typography couples the refined geometric humanism of **Manrope** for reading and general UI with the technical clarity of **JetBrains Mono** for algorithmic spaced repetition metrics (ease factor, card interval times, queue counters).

### Optical Hierarchy & Legibility
- **Card Content Rendering (`body-lg` / `headline-md`):** Review text requires balanced leading (1.45x - 1.5x) to accommodate dense scientific text, cloze deletions, and foreign script.
- **Cloze Deletion Styling:** Displayed in `fontWeight: 600` with the primary accent color (`#4f8cf6`) or softly bracketed in a translucent accent pill (`rgba(79, 140, 246, 0.15)`).
- **Telemetry & Spaced Repetition Intervals:** All deck counts, intervals (`<10m`, `1d`, `4d`, `1.2mo`), and retention percentages must strictly use `jetbrainsMono` to prevent horizontal layout jiggle during rapid review swipes.

## Layout & Spacing

The layout is built around iOS human interface safe margins, employing an 8-point spatial cadence with 4-point micro-adjustments for compact study telemetry.

### Philosophy: The Centered Focus Pane
- **Mobile Handheld Ergonomics:** In review mode, chrome recedes completely. The interactive rating targets ("Again", "Hard", "Good", "Easy") occupy the bottom thumb-reach zone (height 54px, grouped with 8px gaps). The flashcard body stays suspended in the center optical third of the display.
- **Decks & Navigation Hierarchy:** Decks are presented as floating rounded modules with 12px vertical stacking gaps. Inside each deck row, margins are padded with `1.25rem` (`space-lg`) to prevent accidental taps.
- **Responsive Adaptations:**
  - **Compact (iPhone Portrait):** Side margins fixed at `16px`. Active card width spans `calc(100vw - 32px)`. Maximum content reading width is 640px.
  - **Regular / Tablet (iPad Split-view / Full):** Card stage anchors to a centered column (maximum width 680px), preserving comfortable reading eye spans. Metrics and deck outlines dock into a collapsible side navigation drawer.

## Elevation & Depth

This system avoids dark, heavy, high-contrast drop shadows. Instead, it conveys depth through **tonal layering**, **diffuse tinted ambient occlusion**, and **subtle hairline bounding lines**.

### Surface Hierarchy
1. **Level 0 (Canvas):** `#16171a`. Pure ambient background. No shadow, no border.
2. **Level 1 (Decks & Section Pods):** `#1c1d22` with a 1px border of `rgba(255, 255, 255, 0.06)`. Flat against canvas with zero shadow.
3. **Level 2 (Active Flashcard Stage):** `#24262d` with a 1px border of `rgba(255, 255, 255, 0.08)` and an ambient shadow: `box-shadow: 0 12px 32px -4px rgba(0, 0, 0, 0.35), 0 4px 12px -2px rgba(0, 0, 0, 0.25)`.
4. **Level 3 (Interactive Floating Dock & Action Modals):** `#2f313a` supported by backdrop blur (`backdrop-filter: blur(20px) saturate(180%)`) with a top highlight rim of `rgba(255, 255, 255, 0.12)` and ambient shadow `0 16px 40px rgba(0, 0, 0, 0.45)`.

### Tactile Feedback
When card surfaces are pressed or flipped, the border illumination shifts slightly to `rgba(255, 255, 255, 0.14)` and the surface scales to `0.992`, offering a cushioned, physics-based tactile sensation.

## Shapes

The design uses continuous iOS-style squircle radii (`cornerCurve: continuous`). Roundedness is generous and soft to counter the anxiety often associated with dense test preparation.

- **Primary Flashcards:** 20px continuous corner radius.
- **Floating Modals & Sheets:** 24px continuous corner radius on top corners.
- **Deck List Items & Tiles:** 16px continuous corner radius.
- **Telemetry Pills, Badges & Answer Buttons:** 12px to 14px continuous corner radius.
- **Cloze Deletion Highlights & Micro Badges:** 6px radius.

## Components

### Study Review Card (The Focus Canvas)
- **Background:** `#24262d` wrapped in a 1px `rgba(255, 255, 255, 0.08)` perimeter.
- **Padding:** 24px internal padding on all sides.
- **Card Divider:** A 1px separator using `rgba(255, 255, 255, 0.06)` separating the front prompt from the back answer, revealed with a soft 180ms opacity dissolve.
- **Scroll Behavior:** Contained vertical bounce with fade masking at top and bottom edges.

### Rating Action Bar (Answer Buttons)
A floating bottom dock with four distinct buttons:
1. **Again:** Background `rgba(224, 108, 117, 0.12)`, border `rgba(224, 108, 117, 0.25)`, label text `#e06c75`.
2. **Hard:** Background `rgba(224, 159, 88, 0.12)`, border `rgba(224, 159, 88, 0.25)`, label text `#e09f58`.
3. **Good:** Background `rgba(79, 140, 246, 0.14)`, border `rgba(79, 140, 246, 0.30)`, label text `#4f8cf6`.
4. **Easy:** Background `rgba(82, 183, 136, 0.12)`, border `rgba(82, 183, 136, 0.25)`, label text `#52b788`.
- Each button displays the rating name (`manrope` 13px weight 600) and the calculated interval directly underneath (`jetbrainsMono` 11px weight 400 with 60% opacity).

### Deck List Row
- **Background:** `#1c1d22`.
- **Height:** 64px row height.
- **Elements:** Deck title in `#e2e4ea` on the left. The right trailing cluster contains three monospaced count pills:
  - *New:* `#4f8cf6` text on `rgba(79, 140, 246, 0.12)` pill.
  - *Learn:* `#e09f58` text on `rgba(224, 159, 88, 0.12)` pill.
  - *Due:* `#52b788` text on `rgba(82, 183, 136, 0.12)` pill.

### Form Inputs & Search Fields
- **Container:** Background `#1c1d22`, border 1px `rgba(255, 255, 255, 0.07)`, height 44px, 12px roundedness.
- **Active State:** Border shifts to `#4f8cf6` at 50% opacity, with a subtle ambient glow `0 0 0 3px rgba(79, 140, 246, 0.15)`.
- **Text:** Input text in `#e2e4ea`, placeholder text in `#6c7280`.

### Retention Heatmap & Telemetry Chips
- **Heatmap Blocks:** 10px rounded squares (2px radius) mapped along a 5-tier intensity ramp of `#52b788` (`rgba(82,183,136, 0.1)` through `#52b788` solid).
- **Stat Badges:** Charcoal pills (`#24262d`) with hairline borders framing key metrics like "94.2% Retention" or "42 Day Streak".