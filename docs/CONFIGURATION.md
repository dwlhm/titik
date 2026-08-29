# Titik Configuration Guide

Titik is fully customizable through a single JSON configuration file located at:

```bash
~/.config/titik/config.json
```

If the file does not exist, Titik creates it with default settings upon first launch. You can regenerate the default configuration at any time by running:

```bash
bash scripts/setup_config.sh --force
```

---

## Configuration Schema & Options

### 1. `window`

Controls the dimensions, shape, and blur material of the command palette window.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `width` | Number | `720` | Window width in points. |
| `height` | Number | `460` | Window height in points. |
| `corner_radius` | Number | `16.0` | Window corner radius in points. |
| `border_width` | Number | `1.0` | Outer border line width in points. |
| `blur_material` | String | `"hud"` | macOS vibrancy material (`"hud"`, `"popover"`, `"sidebar"`, `"fullScreenUI"`, `"menu"`). |

---

### 2. `animation`

Configures the physics of spring animations and window transitions.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `spring_stiffness` | Number | `320.0` | Stiffness coefficient for interactive spring transitions. |
| `spring_damping` | Number | `28.0` | Damping ratio for spring smoothing. |
| `spring_mass` | Number | `1.0` | Mass coefficient of animated elements. |
| `window_open_duration` | Number | `0.18` | Window open/close animation duration in seconds. |

---

### 3. `hotkey`

Specifies the global system-wide shortcut to summon and dismiss Titik.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `modifier` | String | `"cmd"` | Key modifier: `"cmd"`, `"alt"`, `"ctrl"`, `"shift"`, or combos (`"cmd+shift"`). |
| `key` | String | `"."` | Target character or key identifier (`"."`, `"space"`, `"k"`, etc.). |

---

### 4. `theme`

Customizes colors and alpha transparencies formatted as hex strings (`#RRGGBB` or `#RRGGBBAA`).

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `bg_glass_tint` | String | `"#14162838"` | Translucent tint overlaid on top of blur material. |
| `border_color` | String | `"#ffffff14"` | Subtle border stroke surrounding the window. |
| `text_primary` | String | `"#ffffff"` | Primary title and search input font color. |
| `text_secondary` | String | `"#cbd5e1"` | Subtitle and detail text color. |
| `text_muted` | String | `"#94a3b8"` | Keyboard hints and badge labels color. |
| `accent_color` | String | `"#a5b4fc"` | Primary highlight and action color. |
| `selection_bg` | String | `"#a5b4fc2d"` | Background color for currently selected list row. |
| `badge_bg` | String | `"#93c5fd33"` | Category pill and tag background color. |
| `card_bg` | String | `"#ffffff0c"` | Background container color for preview metadata cards. |

---

### 5. `layout`

Defines dimensions, split ratios, and typography font sizes.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `split_ratio` | Number | `0.60` | Fraction of horizontal width allocated to the results list (remaining is preview pane). |
| `item_height` | Number | `44.0` | Height in points for each list row item. |
| `search_bar_height` | Number | `56.0` | Height in points for the top search input bar. |
| `footer_height` | Number | `36.0` | Height in points for the bottom status bar and key hint footer. |
| `font_size_search` | Number | `18` | Font size for query search input. |
| `font_size_title` | Number | `15` | Font size for item result titles. |
| `font_size_subtitle` | Number | `12` | Font size for item result subtitles and paths. |
| `font_size_badge` | Number | `10` | Font size for category badge pills. |
| `font_size_preview` | Number | `13` | Font size for preview pane text and code content. |

---

### 6. `behaviors`

Configures interaction behaviors and integration settings.

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `auto_hide_on_blur` | Boolean | `true` | Dismiss the palette automatically when clicking outside or losing focus. |
| `max_clipboard_history` | Number | `100` | Maximum number of recent clipboard copies stored in memory. |
| `show_preview_pane` | Boolean | `true` | Toggle the split preview pane for files, images, and plugins. |
| `excluded_apps` | Array | `[]` | Bundle identifiers or application names excluded from index results. |

---

## Full Default Configuration File

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "comment": "Titik macOS Command Center Configuration - Native Liquid Glass and Spring Physics",
  "window": {
    "width": 720,
    "height": 460,
    "corner_radius": 16.0,
    "border_width": 1.0,
    "blur_material": "hud"
  },
  "animation": {
    "spring_stiffness": 320.0,
    "spring_damping": 28.0,
    "spring_mass": 1.0,
    "window_open_duration": 0.18
  },
  "hotkey": {
    "modifier": "cmd",
    "key": "."
  },
  "theme": {
    "bg_glass_tint": "#14162838",
    "border_color": "#ffffff14",
    "text_primary": "#ffffff",
    "text_secondary": "#cbd5e1",
    "text_muted": "#94a3b8",
    "accent_color": "#a5b4fc",
    "selection_bg": "#a5b4fc2d",
    "badge_bg": "#93c5fd33",
    "card_bg": "#ffffff0c"
  },
  "layout": {
    "split_ratio": 0.60,
    "item_height": 44.0,
    "search_bar_height": 56.0,
    "footer_height": 36.0,
    "font_size_search": 18,
    "font_size_title": 15,
    "font_size_subtitle": 12,
    "font_size_badge": 10,
    "font_size_preview": 13
  },
  "behaviors": {
    "auto_hide_on_blur": true,
    "max_clipboard_history": 100,
    "show_preview_pane": true,
    "excluded_apps": []
  }
}
```
