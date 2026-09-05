import Foundation
import Testing
@testable import TitikCore
@testable import TitikKeymap

@Suite("E2E Config Schema, Deserialization & Live Reload Tests")
struct E2EConfigLiveReloadTests {

    // MARK: - Feature 5: Shortcut Configuration Schema

    @Test("F05: ShortcutConfig JSON encoding and decoding round trip")
    func test_f05_shortcutConfigJSONSerialization() throws {
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.builtin.zen",
            arguments: ["command": "open-url", "url": "https://apple.com"]
        )
        let original = ShortcutConfig(
            id: "zen.quick.open",
            name: "Zen Quick Open",
            key: "k",
            modifiers: ["cmd", "shift"],
            mode: .background,
            action: action
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShortcutConfig.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.key == original.key)
        #expect(decoded.modifiers == original.modifiers)
        #expect(decoded.mode == original.mode)
        #expect(decoded.action.type == original.action.type)
        #expect(decoded.action.target == original.action.target)
        #expect(decoded.action.arguments == original.action.arguments)
    }

    @Test("F05: All ShortcutActionType variants decode cleanly")
    func test_f05_shortcutActionTypeEnumeration() throws {
        let decoder = JSONDecoder()

        let types = [
            ("\"pluginCommand\"", ShortcutActionType.pluginCommand),
            ("\"appLaunch\"", ShortcutActionType.appLaunch),
            ("\"quickLink\"", ShortcutActionType.quickLink),
            ("\"rawQuery\"", ShortcutActionType.rawQuery),
            ("\"toggleWindow\"", ShortcutActionType.toggleWindow),
            ("\"systemCommand\"", ShortcutActionType.systemCommand)
        ]

        for (json, expected) in types {
            let data = json.data(using: .utf8)!
            let decoded = try decoder.decode(ShortcutActionType.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("F05: ShortcutActionConfig arguments dictionary preserves arbitrary parameters")
    func test_f05_shortcutActionArgumentsMap() throws {
        let json = """
        {
            "type": "pluginCommand",
            "target": "titik.builtin.launcher",
            "arguments": {
                "ide": "Antigravity",
                "path": "/Users/developer/project",
                "createWindow": "true"
            }
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder().decode(ShortcutActionConfig.self, from: json)
        #expect(action.type == .pluginCommand)
        #expect(action.target == "titik.builtin.launcher")
        #expect(action.arguments?["ide"] == "Antigravity")
        #expect(action.arguments?["path"] == "/Users/developer/project")
        #expect(action.arguments?["createWindow"] == "true")
    }

    @Test("F05: Convenience initializer from shortcut string parses key and modifiers")
    func test_f05_shortcutConfigConvenienceInitializer() {
        let action = ShortcutActionConfig(type: .toggleWindow, target: "hud")
        let config = ShortcutConfig(
            id: "toggle.hud",
            name: "Toggle Window",
            shortcut: "cmd+shift+k",
            mode: .palette,
            action: action
        )

        #expect(config.key == "k")
        #expect(config.modifiers.contains("cmd"))
        #expect(config.modifiers.contains("shift"))
        #expect(config.mode == .palette)
        #expect(config.keyCombinationString.contains("k"))
    }

    @Test("F05: Automatic default identifier derivation from modifiers and key")
    func test_f05_shortcutConfigDefaultIdentifiers() throws {
        let json = """
        {
            "key": "space",
            "modifiers": ["opt"],
            "mode": "palette",
            "action": {
                "type": "rawQuery",
                "target": "!calc"
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(ShortcutConfig.self, from: json)
        #expect(!config.id.isEmpty)
        #expect(config.id == "opt_space")
    }

    // MARK: - Feature 7: Resilient Config Deserialization

    @Test("F07: Empty JSON config defaults gracefully without throwing")
    func test_f07_emptyConfigDefaultsGracefully() throws {
        let emptyJSON = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(Config.self, from: emptyJSON)

        #expect(config.window.width == 720)
        #expect(config.window.height == 460)
        #expect(config.hotkey.modifier == "cmd")
        #expect(config.hotkey.key == ".")
        #expect(config.behaviors.autoHideOnBlur == true)
    }

    @Test("F07: Flexible action type alias decoding (e.g. open_url, launch, plugin_command)")
    func test_f07_flexibleActionTypeAliases() throws {
        let decoder = JSONDecoder()

        let aliases = [
            ("\"plugin_command\"", ShortcutActionType.pluginCommand),
            ("\"open_url\"", ShortcutActionType.quickLink),
            ("\"link\"", ShortcutActionType.quickLink),
            ("\"app\"", ShortcutActionType.appLaunch),
            ("\"launch\"", ShortcutActionType.appLaunch),
            ("\"toggle\"", ShortcutActionType.toggleWindow),
            ("\"query\"", ShortcutActionType.rawQuery),
            ("\"system\"", ShortcutActionType.systemCommand)
        ]

        for (json, expected) in aliases {
            let data = json.data(using: .utf8)!
            let decoded = try decoder.decode(ShortcutActionType.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("F07: Flexible target alias keys (plugin_id, url, app_path, command)")
    func test_f07_flexibleTargetAliases() throws {
        let json1 = """
        { "type": "quickLink", "url": "https://news.ycombinator.com" }
        """.data(using: .utf8)!
        let action1 = try JSONDecoder().decode(ShortcutActionConfig.self, from: json1)
        #expect(action1.target == "https://news.ycombinator.com")

        let json2 = """
        { "type": "pluginCommand", "plugin_id": "titik.builtin.zen" }
        """.data(using: .utf8)!
        let action2 = try JSONDecoder().decode(ShortcutActionConfig.self, from: json2)
        #expect(action2.target == "titik.builtin.zen")

        let json3 = """
        { "type": "appLaunch", "app_path": "/Applications/Safari.app" }
        """.data(using: .utf8)!
        let action3 = try JSONDecoder().decode(ShortcutActionConfig.self, from: json3)
        #expect(action3.target == "/Applications/Safari.app")
    }

    @Test("F07: Flexible arguments decoding supports string array to map conversion")
    func test_f07_flexibleArgumentsArrayOrDict() throws {
        let json = """
        {
            "type": "pluginCommand",
            "target": "titik.builtin.zen",
            "args": ["-new-tab", "https://apple.com"]
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder().decode(ShortcutActionConfig.self, from: json)
        #expect(action.arguments?["0"] == "-new-tab")
        #expect(action.arguments?["1"] == "https://apple.com")
        #expect(action.arguments?["args"] == "-new-tab https://apple.com")
    }

    @Test("F07: Corrupted or non-existent config file returns valid default config")
    func test_f07_corruptedConfigFileFallback() {
        let loader = ConfigLoader.shared
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupted_config_\(UUID().uuidString).json")
        try? "{ invalid json: true, broken ".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let config = loader.load(from: tempURL)
        #expect(config.window.width == 720)
        #expect(config.hotkey.modifier == "cmd")
        #expect(config.hotkey.key == ".")
    }

    @Test("F07: ThemeConfig resilient default decoding")
    func test_f07_themeConfigResilientDefaults() throws {
        let json = """
        {
            "accent_color": "#ff0077"
        }
        """.data(using: .utf8)!

        let theme = try JSONDecoder().decode(ThemeConfig.self, from: json)
        #expect(theme.accentColor == "#ff0077")
        #expect(theme.bgGlassTint == "#0e101a24") // default preserved
        #expect(theme.textPrimary == "#ffffff")  // default preserved
    }
}

