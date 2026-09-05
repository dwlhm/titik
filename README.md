# Titik

[![CI](https://github.com/dwlhm/titik/actions/workflows/ci.yml/badge.svg)](https://github.com/dwlhm/titik/actions/workflows/ci.yml)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/dwlhm/titik?color=6366f1)](https://github.com/dwlhm/titik/releases)

A lightning-fast, extensible macOS command palette and spotlight launcher built with Swift 6 and modern Native Liquid Glass UI.

---

## Key Features

- ⚡️ **Ultra-fast App & Binary Launcher** — Instantly index and launch native macOS applications, preference panes, and command-line utilities.
- 🔍 **Fuzzy File Search & Live In-Memory Directory Navigation** — Fast hierarchical file system traversal starting with `/` or `~`, full keyboard autocomplete with `Tab` and `Right Arrow`, and quick step-back with `Left Arrow`.
- 🧩 **macOS Loadable Bundle Plugin Architecture** — Extensible `.bundle` / `.titikplugin` loadable bundle architecture with out-of-process execution (`titik-worker`), code signature validation, and `!bang` triggers (e.g. `!zen`, `!calc`).
- 📋 **Clipboard History Manager & Automated Accessibility Pasting** — Background clipboard monitoring with real-time fuzzy recall, previewing, and automated synthetic keyboard pasting via macOS Accessibility APIs.
- 🧮 **Embedded Math Evaluator & Unit Converter** — High-performance recursive descent math parser supporting arithmetic, trigonometry, bitwise operations, powers, constants (`pi`, `e`), and unit conversions.
- ⚙️ **Native System Commands** — Built-in system management tasks including dark/light mode toggle, lock screen, sleep, restart, shutdown, volume mute, and screensaver activation.
- 🎨 **Liquid Glass & Spring Physics Customization** — Sleek floating palette styled with native HUD vibrancy materials, backdrop blurs, customizable border tints, and fluid spring physics animations configured via `~/.config/titik/config.json`.

---

## Quick Start & Installation

### Prerequisites

- macOS 13.0 (Ventura) or later
- Swift 6.0+ toolchain (Xcode 16+ or Command Line Tools)

### Building from Source

Clone the repository and build using the provided `Makefile`:

```bash
git clone https://github.com/dwlhm/titik.git
cd titik
make all

# Build the macOS app bundle and install to ~/Applications
make install
```

### Running Titik

You can launch Titik directly from your terminal or open the installed app:

```bash
# Run release binary from terminal
make run

# Or launch the application bundle
open ~/Applications/Titik.app
```

Default Global Hotkey: **`Cmd + .`** (`⌘ + .`).  
You can customize the shortcut anytime in `~/.config/titik/config.json`.

---

## Keybindings Reference

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| `Cmd + .` | Global | Toggle Titik window visibility |
| `Down Arrow` / `Ctrl + N` | List | Select next item |
| `Up Arrow` / `Ctrl + P` | List | Select previous item |
| `Return` | List | Execute selected item / open directory |
| `Tab` / `Right Arrow` | List / Path | Autocomplete query with selected item path |
| `Left Arrow` | Path browsing | Navigate to parent directory |
| `Cmd + K` | Results | Open Action Palette for selected item |
| `Cmd + C` | Results | Copy item action payload / result to clipboard |
| `Cmd + O` / `Cmd + R` | File results | Reveal selected file in Finder |
| `Escape` | Window | Hide Titik window / close Action Palette |

---

## Architecture Overview

Titik is designed as a modular suite of Swift packages and libraries:

```text
┌────────────────────────────────────────────────────────┐
│                        Titik                           │
│                 (Executable Target)                    │
└──────────────────────────┬─────────────────────────────┘
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐    ┌──────────────┐
│ TitikPlatform│   │   TitikUI    │    │ TitikSearch  │
└──────┬───────┘   └──────┬───────┘    └──────┬───────┘
       │                  │                   │
       ├──────────────────┴─────────┬─────────┤
       ▼                            ▼         ▼
┌──────────────┐             ┌──────────────┐ ┌──────────────┐
│ TitikKeymap  │             │ TitikPlugins │ │ TitikParser  │
└──────┬───────┘             └──────┬───────┘ └──────────────┘
       │                            │
       └──────────────┬─────────────┘
                      ▼
               ┌──────────────┐
               │  TitikCore   │
               └──────────────┘
```

- **`TitikCore`**: Core primitives, Configuration Manager (`ConfigManager`), Path Resolver (`PathResolver`), Fuzzy Matcher (`FuzzyMatcher`), App Indexer (`AppLauncher`), Clipboard Manager (`ClipboardManager`), and System Commands (`SystemCommands`).
- **`TitikKeymap`**: Global hotkey registration via Carbon APIs (`HotkeyManager`), keycode mappings, and key combination registry (`KeymapRegistry`).
- **`TitikParser`**: Fast recursive descent tokenizer and parser for expressions, commands, and math AST generation.
- **`TitikPlugins`**: Dynamic bundle loader and registry (`PluginHost`, `PluginManager`) supporting Apple `.bundle` plugins and out-of-process isolation with `titik-worker`.
- **`TitikSearch`**: Unified search orchestration engine (`SearchEngine`) ranking and multiplexing applications, file paths, math evaluation, system commands, and plugin results.
- **`TitikUI`**: SwiftUI & AppKit hybrid user interface with liquid glass HUD materials, spring physics, split-view previews, and toast notifications.
- **`TitikPlatform`**: Orchestration layer (`UIOrchestrator`, `WindowController`, `AutoPaster`) handling window lifecycle, event taps, and accessibility pasting.

For deep architectural details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Configuration

Titik loads its user preferences from `~/.config/titik/config.json`. The configuration file is automatically initialized on the first run.

Example configuration snippet:

```json
{
  "window": {
    "width": 720,
    "height": 460,
    "corner_radius": 16.0,
    "blur_material": "hud"
  },
  "animation": {
    "spring_stiffness": 320.0,
    "spring_damping": 28.0
  },
  "hotkey": {
    "modifier": "cmd",
    "key": "."
  },
  "behaviors": {
    "auto_hide_on_blur": true,
    "max_clipboard_history": 100,
    "show_preview_pane": true
  }
}
```

For complete field specifications, styling tokens, and hotkey configurations, refer to the [Configuration Guide](docs/CONFIGURATION.md).

---

## Dynamic Plugins

Titik supports dynamic plugins packaged as macOS loadable bundles (`.bundle` or `.titikplugin`). Dynamic plugins conform to `TitikPlugin` / `TitikStreamingPlugin` protocols via `TitikPluginKit`, running out-of-process under `titik-worker` with code signature verification:

```swift
import Foundation
import TitikCore
import TitikPluginKit

public final class CustomPlugin: TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.plugin.custom"
    public static let name = "Custom Tool"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext
    public required init(context: PluginContext) {
        self.context = context
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let items = [
            PluginItem(
                id: "tool-item",
                title: "Custom Tool Result",
                subtitle: "Query: \(query)",
                icon: "🧘",
                actionPayload: query,
                pluginId: Self.id
            )
        ]
        return .list(items)
    }

    public func cancelActiveStream() async {}
}
```

Drop compiled `.bundle` directories into `~/.config/titik/plugins/` to load them automatically. See the [Plugin Development Guide](docs/PLUGINS.md) for full instructions and packaging scripts.

---

## Contributing

Contributions are welcome! Please check out [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines on setting up your local environment, running the test suite, and submitting pull requests.

---

## License

Titik is open-source software licensed under the [MIT License](LICENSE).
