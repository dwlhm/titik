# Titik Plugin Development Guide

Titik features an industrial-grade, secure dynamic plugin architecture built around the standard Apple Loadable Bundle (`.bundle` / `.titikplugin`) format. Plugins are authored in Swift using `TitikPluginKit`, isolated in dedicated worker processes (`titik-worker`), and signed with Apple code signatures.

---

## 1. Architecture & Bundle Overview

Dynamic plugins in Titik are standard macOS loadable bundles that provide isolated, out-of-process execution:

- **Isolated Execution**: Dynamic plugins run inside child `titik-worker` processes with address space memory limits (2GB soft/hard `RLIMIT_AS`), file system isolation (`~/.config/titik/sandboxes/<id>`), and async cancellation.
- **Code Signing & Integrity**: Bundles are verified using the macOS Security framework (`SecStaticCodeCreateWithPath`, `SecStaticCodeCheckValidity`). Ad-hoc signatures (`codesign -s - -f`) are supported during development.
- **Rich User Interface**: Plugins stream responsive markdown, search rows, citation trays, chip groups, and custom views into the Titik search interface.
- **Emoji & Visual Icons**: Manifests declare visual icons using native Unicode emoji (e.g. `"icon": "🧘"`) or asset names.

---

## 2. Standard Bundle Directory Layout

Every dynamic plugin conforms to Apple's standard bundle directory structure:

```text
ZenBrowser.bundle/
└── Contents/
    ├── Info.plist               # Apple bundle property list
    ├── MacOS/
    │   └── ZenBrowser           # Compiled Mach-O bundle/dylib executable
    └── Resources/
        └── manifest.json        # Titik plugin manifest & capabilities
```

### `Contents/Info.plist`

The bundle's `Info.plist` defines the bundle identity and principal class:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>titik.plugin.zen</string>
    <key>CFBundleName</key>
    <string>ZenBrowser</string>
    <key>CFBundleExecutable</key>
    <string>ZenBrowser</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>NSPrincipalClass</key>
    <string>ZenBrowserPlugin</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
```

### `Contents/Resources/manifest.json`

The manifest declares plugin identification, search triggers, permissions, and metadata:

```json
{
  "id": "titik.plugin.zen",
  "name": "Zen Browser",
  "icon": "🧘",
  "version": "1.0.0",
  "sdkVersion": 2,
  "description": "Control Zen Browser tabs, windows, and profiles",
  "entrypoint": "ZenBrowserPlugin",
  "triggers": [
    "!zen",
    "zen"
  ],
  "permissions": [
    "workspace:launch"
  ]
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | String | Unique reverse-DNS identifier (e.g., `titik.plugin.zen`) |
| `name` | String | Display name shown in search suggestions and UI |
| `icon` | String? | Optional Unicode emoji (e.g. `"🧘"`) or asset name |
| `version` | String | Semantic version string |
| `sdkVersion` | Int | Target Titik SDK version (current: `2`) |
| `description`| String | Short summary of plugin capabilities |
| `entrypoint` | String | Swift class name implementing `TitikPlugin` |
| `triggers` | [String] | Bang triggers and search keywords (e.g. `["!zen", "zen"]`) |
| `permissions`| [String] | Required capabilities (e.g. `workspace:launch`, `network:fetch`) |

---

## 3. Reference Implementation: Zen Browser Plugin

The reference implementation is located at `Sources/TitikPlugins/Reference/ZenBrowser/ZenBrowserPlugin.swift` and packaged as `bin/plugins/ZenBrowser.bundle`.

```swift
import Foundation
import AppKit
import TitikCore
import TitikPluginKit

public final class ZenBrowserPlugin: TitikCommandPlugin, TitikStreamingPlugin, @unchecked Sendable {
    public static let id = "titik.plugin.zen"
    public static let name = "Zen Browser"
    public static let version = "1.0.0"
    public static let sdkVersion = titikSDKVersion

    public let context: PluginContext

    public required init(context: PluginContext) {
        self.context = context
    }

    public var commands: [PluginCommandDefinition] {
        [
            PluginCommandDefinition(
                id: "open-url",
                name: "Open URL",
                description: "Opens a URL in Zen Browser",
                triggers: ["!zen", "!z", "open-url", "open", "url", "zen"],
                arguments: [
                    PluginCommandArgument(name: "url", description: "Target URL to open", isRequired: true)
                ],
                defaultMode: .background
            )
        ]
    }

    public func onQuery(_ query: String) async throws -> PluginCanvas {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let items = commands.map { cmd in
                PluginItem(
                    id: cmd.id,
                    title: cmd.name,
                    subtitle: cmd.description,
                    icon: "🧘",
                    actionPayload: cmd.id,
                    pluginId: Self.id
                )
            }
            return .list(items)
        }

        let items = [
            PluginItem(
                id: "search-zen",
                title: "Search in Zen: \(trimmed)",
                subtitle: "Search web using Zen Browser",
                icon: "🧘",
                actionPayload: "https://duckduckgo.com/?q=\(trimmed)",
                pluginId: Self.id
            )
        ]
        return .list(items)
    }

    public func cancelActiveStream() async {}
    public func onShutdown() {}
}
```

---

## 4. Building and Packaging Plugin Bundles

### Building the Reference Zen Browser Bundle

To build and sign the reference `ZenBrowser.bundle`:

```bash
make plugins
```

This runs `scripts/build_zen_plugin.sh`, outputting the signed bundle to `bin/plugins/ZenBrowser.bundle`.

### Packaging Custom Plugin Bundles

Use the general-purpose packaging script `scripts/build_plugin_bundle.sh`:

```bash
bash scripts/build_plugin_bundle.sh <Name> <SourceOrBinary> <ManifestPath> <OutputDir>
```

Example:

```bash
bash scripts/build_plugin_bundle.sh \
  ZenBrowser \
  Sources/TitikPlugins/Reference/ZenBrowser/ZenBrowserPlugin.swift \
  config/zen_manifest.json \
  ~/.config/titik/plugins
```

The script:
1. Compiles the Swift source against Titik modules with dynamic symbol resolution (`-Xlinker -undefined -Xlinker dynamic_lookup`).
2. Creates the `Contents/MacOS`, `Contents/Resources`, and `Contents/Info.plist` hierarchy.
3. Copies `manifest.json` into `Contents/Resources/manifest.json`.
4. Signs the bundle with `codesign -s - -f`.

---

## 5. Security & Verification

Titik verifies all dynamic plugins before execution:

1. **Existence & Hierarchy**: Verifies the `.bundle` directory contains `manifest.json` under `Contents/Resources/` (or root fallback) and an executable under `Contents/MacOS/`.
2. **Code Signature**: Uses `SecStaticCodeCreateWithPath` and `SecStaticCodeCheckValidity` to inspect signature validity. Ad-hoc development signatures are permitted, while corrupted signatures trigger warnings.
3. **Class Resolution**: Resolves the principal class via:
   - `bundle.classNamed(manifest.entrypoint)`
   - `bundle.principalClass` (from `NSPrincipalClass` in `Info.plist`)
   - Namespaced `<bundleId>.<entrypoint>`
   - Namespaced `<bundleName>.<entrypoint>`
   - `NSClassFromString(entrypoint)`
4. **Protocol Conformance**: Ensures the resolved class conforms to `TitikPlugin.Type`.

---

## 6. Built-in Core Plugins

Built-in plugins remain statically linked into Titik for maximum performance:

| Plugin Identifier | Name | Bang Trigger | Roles & Protocols |
| :--- | :--- | :--- | :--- |
| `titik.system.plugin` | Plugin System | `!plugin` | `TitikCommandPlugin` |
| `titik.builtin.app` | Applications | `!app` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `TitikGlobalSearchProvider` |
| `titik.builtin.file` | Files & Folders | `!file` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `TitikGlobalSearchProvider` |
| `titik.builtin.clipboard` | Clipboard History | `!clip` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `TitikGlobalSearchProvider` |
| `titik.builtin.system` | System Commands | `!cmd` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `TitikGlobalSearchProvider` |
| `titik.builtin.calculator` | Calculator | `!calc` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `TitikGlobalSearchProvider` |
| `titik.builtin.emoji` | Emoji Catalog | `!emoji` | `TitikStreamingPlugin`, `PluginUIRepresentable` |
| `titik.builtin.launcher` | App & Project Launcher | `!open` | `TitikCommandPlugin`, `TitikStreamingPlugin` |
| `titik.builtin.shortcuts` | Shortcuts Inspector | `!keys` | `TitikCommandPlugin`, `TitikStreamingPlugin`, `PluginUIRepresentable` |

---

## 7. Deployment & Hot-Reload

1. **Install Bundle**: Copy the `.bundle` or `.titikplugin` directory to:
   ```bash
   cp -R bin/plugins/ZenBrowser.bundle ~/.config/titik/plugins/
   ```
2. **Reload**: In Titik's search bar, run:
   ```text
   !plugin reload
   ```
   Or restart the application. Titik will automatically discover the bundle, validate its manifest and signature, and activate the triggers.
