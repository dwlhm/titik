# Project: Global Keyboard Shortcuts and Plugin Command Dispatching for Titik

## Architecture
Titik is a native macOS launcher (Raycast/Spotlight-like) organized as a Swift Package with modular targets:
```
TitikCore (Root types, Config schema, Persistence, ConfigWatcher)
  ├── TitikKeymap (Carbon EventHotKey APIs, Multi-Hotkey Manager, KeymapRegistry)
  ├── TitikParser (Command lexical analysis and AST generation)
  ├── TitikPluginKit (Plugin SDK, TitikPlugin, TitikCommandPlugin, Command protocols)
  │     └── TitikPlugins (Builtin plugins: Zen, Launcher, Shortcuts, PluginSystem, Emoji)
  ├── TitikUI (Floating HUD window, Canvas rendering, List views)
  ├── TitikSearch (SearchEngine, Bang query parser & routing, plugin item scoring)
  └── TitikPlatform (UIOrchestrator, WindowController, PluginCommandDispatcher)
```

### Data Flow & Execution Pipeline
1. **Global Carbon Hotkey Trigger**:
   - `HotkeyManager` receives Carbon Event (`kEventClassKeyboard` / `kEventHotKeyPressed`).
   - Looks up `RegisteredHotkey` by Carbon `EventHotKeyID.id`.
   - If `mode == .background`: Calls `PluginCommandDispatcher.shared.dispatch(...)` silently without opening HUD window.
   - If `mode == .palette`: Invokes `WindowController.shared.showWindow()` and pre-populates `UIOrchestrator.shared.query` with target command/query.
2. **Configuration Loading & Live Hot-Reload**:
   - `ConfigLoader` loads `~/.config/titik/config.json` containing `shortcuts: [ShortcutConfig]`.
   - `ConfigWatcher` monitors the configuration file using `DispatchSourceFileSystemObject`.
   - On modification, debounced reload updates `KeymapRegistry` and rebinds `HotkeyManager` hotkeys dynamically.
3. **Search Bar & Bang Command Routing**:
   - User types bang query (e.g. `!zen -new-tab https://apple.com` or `!open /Users/...`).
   - `SearchEngine` identifies bang target via `findActivePlugin(command:)`.
   - Sub-commands are resolved against `TitikCommandPlugin.commands`.
   - Selecting a result or pressing Enter executes through `PluginCommandDispatcher`.
4. **Plugin Command Execution**:
   - Plugins implementing `TitikCommandPlugin` declare `[PluginCommandDefinition]`.
   - `executeCommand(name:arguments:context:)` performs native macOS actions (e.g. `NSWorkspace` launch, CLI arguments, URL schemes, or UI state inspection).

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Multi-Hotkey Carbon Registration | Register and distinguish arbitrary multiple Carbon `EventHotKeyRef` instances by unique IDs | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Hotkey Unregistration & Dynamic Update | Dynamic unregistration, clearing, and rebinding of active hotkeys without restart | M1 | ORIGINAL_REQUEST §R1 |
| 3 | KeymapRegistry Conflict Tracking | Thread-safe detection and resolution of duplicate key combination bindings | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Execution Mode Differentiation | Distinct handling of `background` (silent) vs `palette` (HUD opening) execution modes | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Shortcut Configuration Schema | `ShortcutConfig` and `ShortcutActionConfig` models in `Config.swift` with polymorphic action payloads | M2 | ORIGINAL_REQUEST §R2 |
| 6 | Key Combination String Parsing | Robust parsing of strings like `"cmd+shift+k"`, `"opt+space"`, `"ctrl+alt+t"` into `KeyCombination` | M2 | ORIGINAL_REQUEST §R2 |
| 7 | Resilient Config Deserialization | Fault-tolerant decoding in `Config.swift` allowing malformed shortcut entries to fail gracefully | M2 | ORIGINAL_REQUEST §R2 |
| 8 | Filesystem Config Hot-Reload | `ConfigWatcher` monitoring `~/.config/titik/config.json` for live updates via `DispatchSource` | M2 | ORIGINAL_REQUEST §R2 |
| 9 | Plugin Command Protocol SDK | `PluginCommandDefinition`, `CommandExecutionContext`, `TitikCommandPlugin` in `TitikPluginKit` | M3 | ORIGINAL_REQUEST §R3 |
| 10 | Unified Command Dispatcher | `PluginCommandDispatcher` in `TitikPlatform` unifying hotkey, bang query, and UI command execution | M3 | ORIGINAL_REQUEST §R3 |
| 11 | Bang Query Sub-Command Routing | `SearchEngine` and `CommandParser` resolution for bang queries with arguments (e.g. `!zen`, `!open`) | M3 | ORIGINAL_REQUEST §R3 |
| 12 | Zen Browser Built-in Plugin | `ZenBrowserPlugin` (`titik.builtin.zen`) implementing `!zen` with URL, tab, window, and profile actions | M4 | ORIGINAL_REQUEST §R4 |
| 13 | App & Project Launcher Plugin | `LauncherPlugin` (`titik.builtin.launcher`) implementing `!open` / `!launch` for apps and IDE projects | M4 | ORIGINAL_REQUEST §R4 |
| 14 | Shortcuts Inspector Plugin | `ShortcutsPlugin` (`titik.builtin.shortcuts`) implementing `!shortcut` / `!hotkeys` listing active bindings | M4 | ORIGINAL_REQUEST §R4 |
| 15 | Unit & Integration Test Suite | Comprehensive tests covering multi-hotkey, config parsing, live reloads, bang routing, and plugins | M5 / Test Track | ORIGINAL_REQUEST §R5 |
| 16 | Adversarial & Stress Hardening | White-box stress tests, race condition validation, and error recovery verification | M5 / Test Track | Project Hardening |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Multi-Hotkey Carbon Registration Engine | `TitikKeymap`: `HotkeyManager` multi-key dictionary, Carbon event routing, `KeymapRegistry` execution modes & conflict tracking | none | DONE |
| M2 | Config Schema, Persistence & Live Watcher | `TitikCore`: `ShortcutConfig`, `ShortcutActionConfig`, resilient JSON decoding, `ConfigWatcher` with `DispatchSource` | none | DONE |
| M3 | Plugin Command Architecture & Unified Dispatcher | `TitikPluginKit` + `TitikPlatform` + `TitikSearch`: `PluginCommandDefinition`, `TitikCommandPlugin`, `PluginCommandDispatcher`, bang parser | M1, M2 | DONE |
| M4 | Built-in Reference Plugins | `TitikPlugins`: `ZenBrowserPlugin` (`!zen`), `LauncherPlugin` (`!open`), `ShortcutsPlugin` (`!shortcut`), registration in `BuiltinPluginRegistry` | M3 | DONE |
| M5 | E2E Testing Integration & Coverage Hardening | Pass 100% of E2E test suite (Tiers 1-4) and adversarial coverage hardening (Tier 5) | M1, M2, M3, M4 | DONE |

---

## Interface Contracts

### 1. `TitikKeymap` ↔ `TitikPlatform`
```swift
public typealias ShortcutExecutionMode = TitikCore.ShortcutExecutionMode

public struct RegisteredHotkey: Sendable {
    public let id: UInt32
    public let identifier: String
    public let combination: KeyCombination
    public let mode: ShortcutExecutionMode
    public let handler: @Sendable () -> Void
}

public final class HotkeyManager: @unchecked Sendable {
    public static let shared: HotkeyManager
    public func register(
        identifier: String,
        combination: KeyCombination,
        mode: ShortcutExecutionMode,
        handler: @escaping @Sendable () -> Void
    ) throws -> UInt32
    public func unregister(identifier: String)
    public func unregisterAll()
    public func isRegistered(identifier: String) -> Bool
    public var activeRegistrations: [RegisteredHotkey] { get }
}
```

### 2. `TitikCore` ↔ `TitikPlatform` / `TitikKeymap`
```swift
public enum ShortcutExecutionMode: String, Codable, Sendable {
    case background
    case palette
}

public struct ShortcutConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String?
    public var key: String
    public var modifiers: [String]
    public var mode: ShortcutExecutionMode
    public var action: ShortcutActionConfig
}

public struct ShortcutActionConfig: Codable, Sendable, Equatable {
    public var type: ShortcutActionType
    public var target: String
    public var arguments: [String: String]?
}

public enum ShortcutActionType: String, Codable, Sendable {
    case pluginCommand
    case appLaunch
    case quickLink
    case rawQuery
    case toggleWindow
}

public final class ConfigWatcher: @unchecked Sendable {
    public static let shared: ConfigWatcher
    public func startWatching(path: String, onChange: @escaping @Sendable (Config) -> Void)
    public func stopWatching()
}
```

### 3. `TitikPluginKit` ↔ `TitikPlugins` / `TitikPlatform`
```swift
public struct PluginCommandDefinition: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let triggers: [String]
    public let arguments: [PluginCommandArgument]
    public let defaultMode: ShortcutExecutionMode
}

public struct PluginCommandArgument: Codable, Sendable {
    public let name: String
    public let description: String
    public let isRequired: Bool
    public let defaultValue: String?
}

public struct CommandExecutionContext: Sendable {
    public let trigger: String
    public let mode: ShortcutExecutionMode
    public let rawInput: String
}

public struct CommandExecutionResult: Sendable {
    public let isSuccess: Bool
    public let message: String?
    public let outputPayload: [String: String]?
}

public protocol TitikCommandPlugin: TitikPlugin {
    var commands: [PluginCommandDefinition] { get }
    func executeCommand(
        id: String,
        arguments: [String: String],
        context: CommandExecutionContext
    ) async throws -> CommandExecutionResult
}
```
