# Titik UI Design System & SF Trio Architecture

Welcome to the definitive Design System specification for **Titik**, a keyboard-first, ultra-lightweight launcher engineered for macOS.

---

## 1. Core Design Principles

### 1.1. Liquid Glass over Static Blur
Titik avoids opaque, flat panels and static blurs. The HUD interface employs multi-layered, refractive liquid glass that blurs background window content using system-level visual effect materials (`.popover` behind-window blending) combined with specular sheen gradients, multi-stop luminescence fills, and precision chamfered rim strokes.

### 1.2. Sub-Millisecond Keyboard-First Velocity
Every visual and interactive element prioritizes zero-latency keyboard feedback:
- Instantaneous caret and list selection repositioning via zero-animation transactions (`transaction.disablesAnimations = true`).
- Asynchronous disk and metadata reads that never block the UI thread or cause frame drops during live queries.
- Predictable and standardized keybindings for all operations.

### 1.3. Typography Rigor with the SF Trio
Titik leverages Apple's native San Francisco type family with strict semantic purpose:
- **SF Pro (Default)**: Used for high-legibility system text, search inputs, result row titles, descriptions, and informational labels.
- **SF Pro Rounded**: Used for structural UI badges, keycaps, toast notifications, brand labels, and calculator answers. Soft rounded terminals provide quick visual anchors for interactive cues.
- **SF Mono**: Used for source code snippets, raw file paths, hexadecimal color codes, file permissions, and technical metadata.

### 1.4. Damped Harmonic Momentum
Spatial transitions (e.g. Action Palette presentation, Preview Pane sliding, boundary bounce) employ critically damped harmonic spring physics (`response: 0.20–0.28`, `dampingFraction: 0.82–0.88`). Movement feels tangible, physical, and restrained—never bouncy or sluggish.

### 1.5. Content-to-Chrome Hierarchy
Visual chrome is whisper-quiet. Dim translucent cavity plates recess input fields and preview panels into the glass substrate, directing optical focus entirely to content, typography, and category-accented highlights.

---

## 2. Spatial Hierarchy & Layering

Titik organizes its visual space into four distinct elevation layers:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Window Layer (Z: 0)                                                     │
│ Refractive Liquid Glass Substrate + Specular Bevel + Ambient Dual Bloom │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ Inset Cavity Layer (Z: 1)                                         │  │
│  │ Etched Dark Cavity (Search Bar, Preview Container, Code Box)      │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │ Interactive Selection Layer (Z: 2)                          │  │  │
│  │  │ Active Item Plate (`selectionBg`) + 1px Accent Highlight Rim │  │  │
│  │  │                                                             │  │  │
│  │  │  ┌───────────────────────────────────────────────────────┐  │  │  │
│  │  │  │ Chips, Badges & Overlays Layer (Z: 3 / Z: 100)        │  │  │  │
│  │  │  │ Pastel Badges, Keycaps, Action Palette, Floating Toast│  │  │  │
│  │  │  └───────────────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

1. **Window Layer (Z: 0)**:
   - Root floating HUD container (720 × 460 pt, 16 pt continuous corner radius).
   - Combines native `NSVisualEffectView` behind-window popover material, a downward 3-stop liquid glass dark gradient, an inner specular sheen, dual border strokes (bevel + rim gradient), and dual-layer drop shadows.

2. **Inset Cavity Layer (Z: 1)**:
   - Recessed areas such as Search Bar cavity, Preview Pane card, and Code Preview blocks.
   - Dark translucent fill (`Color.black.opacity(0.15–0.18)`) overlaid with faint white luminescence (`Color.white.opacity(0.04)`) and subtle border stroke (`Color.white.opacity(0.08–0.12)`).

3. **Interactive Selection Layer (Z: 2)**:
   - Selection plate for list items and action rows.
   - Distinctive indigo accent tint (`selectionBg`, `Color(165, 180, 252, opacity: 0.18)`) bordered by a crisp 1 pt stroke (`Theme.accent.opacity(0.40)`).

4. **Chips, Badges & Overlays Layer (Z: 3 / Z: 100)**:
   - Elevated UI tokens including category pills, keycaps, and contextual action menus (Z: 10).
   - High-priority floating feedback such as Toast capsules (Z: 100).

---

## 3. Typography Architecture — San Francisco Trio

All typography tokens in Titik are centralized in `Theme.swift` and follow strict typographic weights, optical sizing, and design system roles:

| Token | Family / Design | Size | Weight | Tracking / Notes | Primary Usage |
|---|---|---|---|---|---|
| `fontSearchInput` | SF Pro (Default) | 18 pt | Medium | Normal | Active query text in search bar |
| `fontSearchPlaceholder` | SF Pro (Default) | 18 pt | Regular | Normal | Unfocused/ghost search placeholder |
| `fontRowTitle` | SF Pro (Default) | 13.5 pt | Medium | Tight (-0.1pt) | Primary item title in result rows |
| `fontRowSubtitle` | SF Pro (Default) | 11 pt | Regular | Normal | Subtitle, detail path in result rows |
| `fontBadge` | SF Pro Rounded | 9.5 pt | Bold | Semi-expanded (+0.2pt) | Category pills (`APP`, `CLIP`, `CALC`) |
| `fontKeycap` | SF Pro Rounded | 10 pt | Semibold | Semi-expanded | Keyboard glyphs (`↵`, `⇥`, `⌘K`) |
| `fontFooterLabel` | SF Pro (Default) | 11 pt | Regular | Normal | Keycap description labels in footer |
| `fontBrand` | SF Pro Rounded | 11 pt | Bold | Semi-expanded | Bottom left "Titik" logo lockup |
| `fontPreviewTitle` | SF Pro (Default) | 15 pt | Semibold | Tight (-0.15pt) | Header title in detail preview pane |
| `fontPreviewSubtitle` | SF Pro (Default) | 11 pt | Medium | Normal | Header category label in preview pane |
| `fontPreviewBody` | SF Pro (Default) | 12 pt | Regular | Normal | Preview descriptive body & details |
| `fontCode` | SF Mono | 12 pt | Regular | Monospaced | File preview text, line numbers, UTI |
| `fontMathResult` | SF Pro Rounded | 22 pt | Semibold | Tight | Calculator evaluate result output |
| `fontToast` | SF Pro Rounded | 13 pt | Medium | Normal | Floating notification toasts |

---

## 4. Color & Materials

### 4.1. Pastel Category Palette
Distinct, low-saturation pastel hues classify search result types instantly without optical noise:

| Category | Hex | Color Token | Visual Tint |
|---|---|---|---|
| Applications | `#93c5fd` | `categoryApp` | Pastel Sky Blue |
| System Commands | `#fcd34d` | `categoryCommand` | Pastel Amber Yellow |
| Clipboard History | `#86efac` | `categoryClipboard` | Pastel Mint Green |
| Calculator / Math | `#d8b4fe` | `categoryMath` | Pastel Lavender Purple |
| Plugins | `#67e8f9` | `categoryPlugin` | Pastel Electric Cyan |
| Custom Bangs | `#f472b6` | `categoryCustom` | Pastel Rose Pink |
| Files | `#fb923c` | `categoryFile` | Pastel Coral Orange |
| Directories | `#2dd4bf` | `categoryDirectory` | Pastel Seafoam Teal |
| Emoji | `#fbbf24` | `categoryEmoji` | Pastel Warm Gold |

### 4.2. Glass Substrate & Specular Tokens
- `glassSurfaceGradient`:
  - Stop 0.00: `Color.white.opacity(0.06)`
  - Stop 0.35: `rgba(16, 18, 32, 0.16)`
  - Stop 1.00: `rgba(10, 12, 22, 0.22)`
- `glassSpecularGlare`:
  - Stop 0.00: `Color.white.opacity(0.14)`
  - Stop 0.25: `Color.white.opacity(0.02)`
  - Stop 0.55: `Color.clear`
- `borderGlassGradient`: Linear gradient from top-leading `rgba(255, 255, 255, 0.35)` to bottom-trailing `rgba(255, 255, 255, 0.08)`.
- `borderGlassBevel`: Top-to-bottom inner bevel from `rgba(255, 255, 255, 0.12)` through `rgba(255, 255, 255, 0.03)` to `rgba(0, 0, 0, 0.15)`.

### 4.3. Text & Interactive State Tokens
- `textPrimary`: `Color.white` (100% luminance)
- `textSecondary`: `#cbd5e1` (`rgba(203, 213, 225, 1.0)`)
- `textMuted`: `#94a3b8` (`rgba(148, 163, 184, 1.0)`)
- `accent`: `#a5b4fc` (`rgba(165, 180, 252, 1.0)`)
- `selectionBg`: `rgba(165, 180, 252, 0.18)`
- `bgSolidFallback`: `rgba(20, 22, 38, 1.0)` (used when transparency reduction is enabled)

---

## 5. Elevation & Dual-Layer Shadows

Floating HUD windows on macOS require dual-depth shadowing to ground the window against complex wallpapers while conveying elevation:

1. **Contact Shadow**:
   - `color: Color.black.opacity(0.25)`
   - `radius: 8`
   - `x: 0, y: 4`
   - Gives crisp definition along the bottom perimeter.

2. **Ambient Bloom Shadow**:
   - `color: Color.black.opacity(0.35)`
   - `radius: 32`
   - `x: 0, y: 16`
   - Creates a soft, atmospheric dispersion field.

---

## 6. Motion & Physics Tokens

Interactive responsiveness is governed by strict physics tokens:

| Token | Parameters | Purpose |
|---|---|---|
| `springPresentation` | `response: 0.28, dampingFraction: 0.82` | Action palette sheet presentation, window scale-in |
| `springInteractive` | `response: 0.25, dampingFraction: 0.85` | Preview pane reveal/collapse, mode transitions |
| `springSnappy` | `response: 0.20, dampingFraction: 0.88` | Emoji grid tabs, boundary bounce reset |

### Zero-Latency Transaction Rules
- Keyboard selection changes (`↑`, `↓`, `Tab`, `Shift+Tab`) MUST use `transaction.disablesAnimations = true` or `transaction.animation = nil`.
- Result list item selection changes must snap immediately within the display refresh cycle.

---

## 7. Communication & Voice Guidelines

Titik communicates with a calm, concise, developer-first voice.

### 7.1. Toast Notification Grammar
- Use imperative or past-tense action phrases:
  - *Good*: "Copied to clipboard", "Pinned item", "Moved to Trash"
  - *Avoid*: "The item was successfully copied to your system clipboard!"
- Keep toast duration between 2.0 and 3.0 seconds.
- Limit toast messages to a single line whenever possible.

### 7.2. Empty States
- Always state the outcome simply and offer actionable guidance.
- E.g. "No results found for 'foo'" / "Type a command or search..."

### 7.3. Standardized Keycap Grammar
Footers and palettes adhere to standard keyboard symbols with single-word verbs:
- `↵ Open` / `↵ Execute` / `↵ Paste`
- `⇥ Complete` / `⇥ Drill-in`
- `⌘K Actions`
- `⌘O Finder`
- `⌘C Copy`
- `esc Close` / `esc Dismiss` / `esc Back`
