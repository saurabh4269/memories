# Memories: brand and design system

> Your family's cinematographer. Everyone shoots into one album; the director cuts the film.

This is the source of truth for every Memories screen in the Flutter app. Code tokens live in
the Flutter app at `lib/memories/design/` (Immich fork, `knowledge-dump/repos/immich-mobile-try/mobile`) (`tokens.dart`, `typography.dart`, `theme.dart`) and must
match this file. If they drift, this file wins.

## 1. What we learned from the references (and what we deliberately did not copy)

We studied two public Dribbble concepts (screenshots kept privately, outside the repo):
a "Yearly Archive" photo album concept and an "AI family album" mobile concept. Principles we took:

| Principle | How Memories applies it |
|---|---|
| The photo is the hero; chrome stays out of the way | Full-bleed real covers from the family's own Immich album, text sits on a soft gradient scrim, never on a coloured box |
| Big editorial numerals / titles on top of imagery | Event names and years in a warm display serif, set large on photos |
| Graceful empty states | No grey boxes: empty states use a real festive photograph with a warm wash |
| Soft, generous radii and airy spacing | 24 dp photo cards, 8-pt rhythm, one idea per section |
| AI shown as a gentle helper, not a robot | The director "talks" in short human steps ("Finding your people…"), with a small spark mark, never a robot icon |
| Pills for filters, frosted chips on photos | Frosted chips for metadata on photos, solid pills for choices |

What we did *not* take: their pink/pastel palettes, their layouts, their iconography or copy.
Memories is festive-Indian, warm and night-lit: marigold, diya flame, plum and indigo night.

## 2. Name and voice

- **Name:** Memories. **Mark:** a small four-point spark (the "director's spark") used only next to AI actions.
- **Voice:** warm, brief, family-first. We speak like a cousin who is good with a camera.
  - Do: "Make a memory", "Your two reels are ready", "Cutting to the beat…"
  - Don't: "Generate content", "AI processing", "Error 500".
- **Bilingual:** every primary string has a Hindi twin. Hindi is never a smaller afterthought;
  it uses the same size and weight as English.
- **Errors:** say what happened and what to do, in one line. "The director is busy. Try again in a minute."

## 3. Colour

Festive but tasteful: one bright accent (marigold) on calm, warm neutrals. Photos bring the rest of the colour.

### Light ("Chandan day")

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#FBF6EE` | App background (warm ivory) |
| `surface` | `#FFFFFF` | Cards, sheets |
| `surfaceMuted` | `#F4ECDF` | Inset fields, unselected chips |
| `line` | `#E8DCCB` | Hairlines, outlines |
| `ink` | `#24161D` | Primary text (plum-black) |
| `inkMuted` | `#6E5B63` | Secondary text (AA on canvas: 6.2:1) |
| `marigold` | `#F2A20C` | Primary action fill, active states (text on it is `ink`, 8.9:1) |
| `diya` | `#D9661A` | Accent, progress, "live" highlights |
| `plum` | `#4B1F4F` | Strong secondary action, headings on light |
| `indigoNight` | `#1D1A38` | Dark hero blocks, video frames |
| `sindoor` | `#B8332B` | Errors, destructive |
| `leaf` | `#2E7A57` | Success, "shared" |

### Dark ("Diwali night")

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#110D19` | App background (indigo night) |
| `surface` | `#1B1626` | Cards |
| `surfaceMuted` | `#251E33` | Inset fields, chips |
| `line` | `#352B45` | Hairlines |
| `ink` | `#F8EFE2` | Primary text |
| `inkMuted` | `#BBAEBD` | Secondary text (AA on canvas: 8.6:1) |
| `marigold` | `#F7B23B` | Primary action (text on it is `#24161D`) |
| `diya` | `#F28A3E` | Accent |
| `plum` | `#D2A3DC` | Secondary accent / headings |
| `indigoNight` | `#0B0912` | Video frames |
| `sindoor` | `#F07468` | Errors |
| `leaf` | `#6CC79C` | Success |

**Scrim:** photos always carry a bottom gradient `transparent -> #000000 @ 72%` (top 35% clear) so white
text passes AA on any photo. Never place text on an un-scrimmed photo.

**Glow:** the only "effect" we allow is a soft marigold glow (`marigold @ 35%`, blur 32) behind the mic and
the primary CTA on hero blocks. No neon, no rainbow gradients.

## 4. Typography

All fonts are open-licensed (SIL OFL 1.1) Google Fonts, bundled as assets (no runtime download):

| Role | Family | Weights bundled |
|---|---|---|
| Display / titles | **Fraunces** (soft, warm serif) | 400, 500, 600, 700, italic 400/500 |
| UI / body | **Manrope** (clean geometric sans) | 400, 500, 600, 700, 800 |
| Hindi (fallback for both) | **Noto Sans Devanagari** | 400, 500, 600, 700 |

`fontFamilyFallback: ['NotoSansDevanagari']` is set on every style, so Hindi renders in a matched sans.

| Style | Family | Size / line | Weight | Use |
|---|---|---|---|---|
| `display` | Fraunces | 40 / 44 | 600 | Hero event name |
| `headline` | Fraunces | 30 / 36 | 600 | Screen titles |
| `title` | Fraunces | 22 / 28 | 600 | Card titles, section titles |
| `titleSans` | Manrope | 18 / 24 | 700 | Button labels, list titles |
| `body` | Manrope | 16 / 24 | 500 | Body copy |
| `bodyMuted` | Manrope | 15 / 22 | 500 | Secondary copy |
| `label` | Manrope | 14 / 18 | 700 | Chips, metadata (letter-spacing 0.2) |
| `overline` | Manrope | 12 / 16 | 800 | Section kickers, ALL CAPS, letter-spacing 1.4 |

Italic Fraunces is reserved for one emotive accent per screen (e.g. "*Diwali*, 2026").

## 5. Space, radius, elevation

- **Spacing (8-pt, with 4 for fine tuning):** `xxs 4 · xs 8 · sm 12 · md 16 · lg 20 · xl 24 · xxl 32 · xxxl 48`.
  Screen gutter is 20. Sections are separated by 32.
- **Radius:** `sm 12` (chips inside cards, thumbnails) · `md 16` (inputs, small cards) · `lg 24` (photo cards, reels)
  · `xl 32` (hero, sheets) · `pill 999` (buttons, chips).
- **Elevation:** we use warm, low shadows instead of Material elevation.
  - `e1`: `#24161D @ 6%`, blur 12, y 4 (cards on canvas)
  - `e2`: `#24161D @ 12%`, blur 28, y 12 (hero, floating CTA)
  - Dark mode uses black @ 40% for both, plus a 1 px `line` border on cards.

## 6. Iconography

Material Symbols **Rounded**, 24 dp default (28 in elder mode), 2 px optical weight. Icons are always paired
with a text label on primary actions. Brand glyphs for destinations are drawn as simple rounded tiles in the
platform's own hue (WhatsApp green tile, Instagram gradient tile), never official logos.

## 7. Motion

- **Standard:** 220 ms, `easeOutCubic`. **Emphasised** (hero, page): 360 ms, `easeOutQuart`.
- **Stagger:** list items fade + rise 12 dp, 40 ms apart, max 6 items.
- **Hero photos:** slow Ken Burns (scale 1.0 -> 1.06 over 14 s, reversing). Off when "reduce motion" is on.
- **Progress:** the director's steps advance on real stage timings from the server (see ProgressStory);
  the active step breathes (opacity 0.6 <-> 1.0, 1.4 s). No spinners on hero screens.
- **Never:** bounces, parallax on text, auto-playing sound.
- Respect `MediaQuery.disableAnimations`: all decorative motion stops; state changes cross-fade at 120 ms.

## 8. Elder-friendly accessibility (non-negotiable)

- **Elder mode** (set per member from server flags): body text min **18 sp**, titles scale with it, icons 28 dp.
- **Targets:** every tappable thing is at least **48 x 48 dp**; primary buttons are **60 dp** tall (64 in elder mode).
- **Contrast:** all text meets **WCAG AA** (4.5:1 body, 3:1 large). Text on photos always sits on the scrim.
- **Voice first:** the mic is the largest control on the Make-a-memory screen; typing is the fallback.
- One primary action per screen, bottom-anchored where the thumb is.
- Never rely on colour alone: selected chips also show a check mark.
- Semantic labels on every icon-only control.

## 9. Components (Flutter, `lib/memories/design/components/`)

`PhotoHeroCard`, `MemoryAlbumCard`, `PillButton` (primary / secondary / ghost), `FrostedChip`, `MemoriesChoiceChip`,
`SectionHeader`, `ReelCard` (9:16 frame, title, why, duration), `ShimmerPlaceholder`, `ProgressStory`,
`EmptyState`, `DestinationCard`, `DirectorTimeline` (Under the hood).

## 10. Photography

1. The family's own photos first (Immich album covers and thumbnails, director reel covers).
2. For onboarding / empty states only: bundled openly-licensed festive photos, credited in
   `assets/memories/CREDITS.md`.
3. Warm grade is fine; never add stickers, frames or clip-art to people's photos.
