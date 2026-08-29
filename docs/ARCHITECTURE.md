# Titik Architecture

This document provides a comprehensive technical overview of Titik's internal architecture, module separation, data flow, and runtime mechanics.

---

## 1. Modular Overview

Titik is built as a multi-target Swift package designed with clean boundaries, high concurrency safety (Swift 6 strict concurrency), and strict separation of concerns.

```text
┌────────────────────────────────────────────────────────┐
│                        Titik                           │
│                 (Executable Entry)                     │
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

### Module Responsibilities

1. **`TitikCore`**
   - **`ConfigManager`**: Thread-safe configuration loading, saving, environment expansion, and default value fallback.
   - **`PathResolver`**: Path expansion (`~`, `/`, relative paths), splitting, and parent traversal detection.
   - **`FuzzyMatcher`**: High-performance subsequence fuzzy matching algorithm with consecutive match and word-boundary scoring.
   - **`AppLauncher`**: High-speed indexing of `/Applications`, `/System/Applications`, and `~/Applications` with metadata extraction and caching.
   - **`ClipboardManager`**: Background polling of `NSPasteboard` change counts, history tracking, deduplication, and item classification.
   - **`SystemCommands`**: Native macOS management handlers (sleep, restart, shutdown, lock screen, mute, dark/light mode toggle).
   - **`Logger`**: Structured logging subsystem writing to `~/.local/state/titik/titik.log`.

2. **`TitikKeymap`**
   - **`HotkeyManager`**: Carbon Event HotKey API integration for system-wide global hotkey listening (`RegisterEventHotKey`).
   - **`Keycode` & `KeyModifier`**: Type-safe representations of macOS virtual keycodes and modifier masks.
   - **`KeymapRegistry`**: Thread-safe table of registered shortcut combinations and action callbacks.

3. **`TitikParser`**
   - **`CommandParser`**: Lexical analyzer and recursive descent parser.
   - **AST Types**: Distinguishes empty queries, math expressions (`BinaryOp`, `UnaryOp`, `FunctionCall`, `Constant`), bang commands, and raw text queries.

4. **`TitikPlugins`**
   - **`plugin_api.h`**: Stable C99 header declaring C ABI plugin entry points, data structures, and function pointers.
   - **`PluginHost`**: Dynamic loader utilizing `dlopen`, `dlsym`, and `dlclose` to discover, initialize, query, and execute plugins residing in `~/.config/titik/plugins/` and app bundle `PlugIns/`.

5. **`TitikSearch`**
   - **`SearchEngine`**: Central dispatch provider querying applications, file hierarchies, math evaluation (`MathEvaluator`), clipboard history, and dynamic plugins.
   - **`MathEvaluator`**: Floating-point math evaluator supporting trigonometric operations, roots, logarithms, powers, bitwise operators, and constants.

6. **`TitikUI`**
   - **`Theme`**: Visual design tokens (glass background tints, border colors, selection fills, typography, animations).
   - **`SearchBarView`**: Custom search input field with live debounced updates and keyboard event delegates.
   - **`ResultsListView` & `ResultItemRow`**: Virtualized list rendering with match highlighting and category badges.
   - **`PreviewPaneView`**: Multi-format live preview pane for text, code syntax, images, audio, video, PDFs, and directory metadata.
   - **`ActionPaletteView`**: Secondary popover menu (`Cmd + K`) for context-specific actions (copy path, reveal in Finder, copy result).
   - **`ToastManager` & `ToastView`**: Non-intrusive floating feedback notifications.

7. **`TitikPlatform`**
   - **`WindowController`**: Borderless, floating `NSPanel` configuration with `.hudWindow` vibrancy and backdrop blur materials.
   - **`UIOrchestrator`**: Master coordinator connecting search engine events, key monitoring, active plugin states, and window lifecycle.
   - **`AutoPaster`**: Accessibility CGEvent synthesis engine to automatically paste selected clipboard items into active frontmost applications.

8. **`Titik` (Executable)**
   - Entry point configuring `NSApplication`, initializing configuration directories, registering global hotkeys, and running the Cocoa event loop.

---

## 2. Data Flow & Search Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Hotkey as HotkeyManager
    participant Orchestrator as UIOrchestrator
    participant Engine as SearchEngine
    participant Core as TitikCore / Plugins
    participant UI as TitikUI (SwiftUI/AppKit)

    User->>Hotkey: Press Cmd + .
    Hotkey->>Orchestrator: Trigger toggleWindow()
    Orchestrator->>UI: Show floating panel with spring animation
    User->>UI: Type search query (e.g. "2 * pi" or "!math 4^2" or "~/Doc")
    UI->>Orchestrator: Query updated
    Orchestrator->>Engine: search(query)
    alt Bang Command / Dynamic Plugin
        Engine->>Core: PluginHost.queryPlugin(id, subquery)
        Core-->>Engine: Array of TitikPluginItem
    else Path Query
        Engine->>Core: FileBrowser.browseDirectory(path)
        Core-->>Engine: Array of SearchItem (directory contents)
    else Math Expression
        Engine->>Core: CommandParser + MathEvaluator.evaluate(ast)
        Core-->>Engine: Math evaluation result SearchItem
    else Standard Search
        Engine->>Core: AppLauncher, SystemCommands, ClipboardManager
        Core-->>Engine: Ranked SearchItem results
    end
    Engine-->>Orchestrator: [SearchItem] sorted by score
    Orchestrator->>UI: Update list & select top item
    User->>UI: Press Return / Tab
    UI->>Orchestrator: executeSelected()
    Orchestrator->>Core: Run item action (Launch App / Open Dir / Paste)
```

---

## 3. C ABI Dynamic Plugin Architecture

Titik enables dynamic extension without requiring recompilation of the host binary. Plugins are shared libraries (`.dylib`) implementing the C ABI interface defined in `plugin_api.h`.

### Lifecycle Contract

```text
Host (Titik)                                  Plugin (.dylib)
     │                                              │
     │── dlopen("plugin.dylib") ───────────────────>│
     │── dlsym("titik_plugin_entry") ──────────────>│
     │<── Returns TitikPlugin struct pointer ───────│
     │                                              │
     │── plugin->init() ───────────────────────────>│
     │<── Returns 0 (success) ──────────────────────│
     │                                              │
     │── plugin->query(query_str, items_buf, max) ─>│
     │<── Returns item count ───────────────────────│
     │                                              │
     │── plugin->execute(item_id, payload) ────────>│
     │<── Returns 0 (success) ──────────────────────│
     │                                              │
     │── plugin->shutdown() ───────────────────────>│
     │── dlclose(handle) ──────────────────────────>│
```

Memory safety is guaranteed by stack-allocated host buffers (`TitikPluginItem` array passed into `query`) avoiding foreign heap allocation issues between host and dynamic libraries.

---

## 4. UI Architecture & Native Materials

Titik uses standard Apple AppKit vibrancy layers combined with SwiftUI:

- **NSVisualEffectView**: Configured with `hudWindow` material and `behindWindow` blending mode to achieve the true macOS glass look.
- **Spring Physics**: All transitions, selections, and window toggles utilize customizable spring constants (`spring_stiffness`, `spring_damping`, `spring_mass`).
- **Low Latency**: Key monitoring uses `NSEvent.addLocalMonitorForEvents` directly on the main run loop to eliminate input lag.
