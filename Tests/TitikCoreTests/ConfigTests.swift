import Foundation
import Testing
import TitikCore

@Suite("Config Tests")
struct ConfigTests {
    @Test("Hex color parsing (3, 4, 6, 8 digit)")
    func testHexColorParsing() {
        // 3-digit hex
        let rgb3 = RGBAColor.parseHex("#f00")
        #expect(rgb3 != nil)
        #expect(abs((rgb3?.red ?? 0) - 1.0) < 0.01)
        #expect(abs((rgb3?.green ?? 0) - 0.0) < 0.01)
        #expect(abs((rgb3?.blue ?? 0) - 0.0) < 0.01)
        #expect(abs((rgb3?.alpha ?? 0) - 1.0) < 0.01)

        // 4-digit hex
        let rgba4 = RGBAColor.parseHex("#0f08")
        #expect(rgba4 != nil)
        #expect(abs((rgba4?.green ?? 0) - 1.0) < 0.01)
        #expect(abs((rgba4?.alpha ?? 0) - 0.533) < 0.02)

        // 6-digit hex
        let rgb6 = RGBAColor.parseHex("#0000ff")
        #expect(rgb6 != nil)
        #expect(abs((rgb6?.blue ?? 0) - 1.0) < 0.01)
        #expect(abs((rgb6?.alpha ?? 0) - 1.0) < 0.01)

        // 8-digit hex
        let rgba8 = RGBAColor.parseHex("#ffffff80")
        #expect(rgba8 != nil)
        #expect(abs((rgba8?.red ?? 0) - 1.0) < 0.01)
        #expect(abs((rgba8?.alpha ?? 0) - 0.5) < 0.01)
    }

    @Test("Config JSON decoding with window and hotkey")
    func testConfigDecoding() throws {
        let json = """
        {
            "window": {
                "width": 800,
                "height": 500,
                "corner_radius": 20.0,
                "border_width": 2.0,
                "blur_material": "popover"
            },
            "hotkey": {
                "modifier": "alt",
                "key": "space"
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.window.width == 800)
        #expect(config.window.height == 500)
        #expect(config.window.cornerRadius == 20.0)
        #expect(config.hotkey.modifier == "alt")
        #expect(config.hotkey.key == "space")
        #expect(config.shortcuts.isEmpty)
    }

    @Test("Default config fallback")
    func testDefaultConfigFallback() {
        let loader = ConfigLoader()
        let nonExistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("non_existent_config_\(UUID().uuidString).json")
        let cfg = loader.load(from: nonExistentURL)
        #expect(cfg.window.width == 720)
        #expect(cfg.hotkey.modifier == "cmd")
        #expect(cfg.hotkey.key == ".")
        #expect(cfg.theme.bgGlassTint == "#14162838" || cfg.theme.bgGlassTint == "#0e101a24")
        #expect(cfg.theme.borderColor == "#ffffff14" || cfg.theme.borderColor == "#ffffff26")
        #expect(cfg.theme.cardBg == "#ffffff0c" || cfg.theme.cardBg == "#ffffff0f")
        #expect(cfg.shortcuts.isEmpty)
    }

    @Test("ThemeConfig default initialization and decoding")
    func testThemeConfigDefaults() throws {
        let theme = ThemeConfig()
        #expect(theme.bgGlassTint == "#0e101a24")
        #expect(theme.borderColor == "#ffffff26")
        #expect(theme.cardBg == "#ffffff0f")

        let emptyJSON = "{}".data(using: .utf8)!
        let decodedTheme = try JSONDecoder().decode(ThemeConfig.self, from: emptyJSON)
        #expect(decodedTheme.bgGlassTint == "#0e101a24")
        #expect(decodedTheme.borderColor == "#ffffff26")
        #expect(decodedTheme.cardBg == "#ffffff0f")
    }

    @Test("ShortcutExecutionMode decoding variants")
    func testShortcutExecutionModeDecoding() throws {
        let decoder = JSONDecoder()

        let bgJSON = "\"background\"".data(using: .utf8)!
        let silentJSON = "\"silent\"".data(using: .utf8)!
        let bgShortJSON = "\"bg\"".data(using: .utf8)!
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: bgJSON) == .background)
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: silentJSON) == .background)
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: bgShortJSON) == .background)

        let paletteJSON = "\"palette\"".data(using: .utf8)!
        let hudJSON = "\"hud\"".data(using: .utf8)!
        let windowJSON = "\"window\"".data(using: .utf8)!
        let interactiveJSON = "\"interactive\"".data(using: .utf8)!
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: paletteJSON) == .palette)
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: hudJSON) == .palette)
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: windowJSON) == .palette)
        #expect(try decoder.decode(ShortcutExecutionMode.self, from: interactiveJSON) == .palette)
    }

    @Test("ShortcutActionType decoding variants")
    func testShortcutActionTypeDecoding() throws {
        let decoder = JSONDecoder()

        // pluginCommand variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"pluginCommand\"".data(using: .utf8)!) == .pluginCommand)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"plugin_command\"".data(using: .utf8)!) == .pluginCommand)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"plugin-command\"".data(using: .utf8)!) == .pluginCommand)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"plugin\"".data(using: .utf8)!) == .pluginCommand)

        // appLaunch variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"appLaunch\"".data(using: .utf8)!) == .appLaunch)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"app_launch\"".data(using: .utf8)!) == .appLaunch)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"app\"".data(using: .utf8)!) == .appLaunch)

        // quickLink variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"quickLink\"".data(using: .utf8)!) == .quickLink)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"quick_link\"".data(using: .utf8)!) == .quickLink)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"url\"".data(using: .utf8)!) == .quickLink)

        // rawQuery variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"rawQuery\"".data(using: .utf8)!) == .rawQuery)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"raw_query\"".data(using: .utf8)!) == .rawQuery)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"query\"".data(using: .utf8)!) == .rawQuery)

        // toggleWindow variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"toggleWindow\"".data(using: .utf8)!) == .toggleWindow)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"toggle_window\"".data(using: .utf8)!) == .toggleWindow)

        // systemCommand variants
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"systemCommand\"".data(using: .utf8)!) == .systemCommand)
        #expect(try decoder.decode(ShortcutActionType.self, from: "\"system_command\"".data(using: .utf8)!) == .systemCommand)
    }

    @Test("ShortcutActionConfig decoding with aliases and args array")
    func testShortcutActionConfigDecoding() throws {
        let decoder = JSONDecoder()

        // Target aliases
        let urlJSON = """
        { "type": "quick_link", "url": "https://apple.com" }
        """.data(using: .utf8)!
        let action1 = try decoder.decode(ShortcutActionConfig.self, from: urlJSON)
        #expect(action1.type == .quickLink)
        #expect(action1.target == "https://apple.com")
        #expect(action1.arguments == nil)

        let pluginJSON = """
        { "type": "plugin_command", "plugin_id": "titik.builtin.zen", "command": "new-tab", "arguments": { "url": "https://google.com" } }
        """.data(using: .utf8)!
        let action2 = try decoder.decode(ShortcutActionConfig.self, from: pluginJSON)
        #expect(action2.type == .pluginCommand)
        #expect(action2.target == "titik.builtin.zen")
        #expect(action2.arguments?["url"] == "https://google.com")

        // Args array decoding
        let argsArrayJSON = """
        { "type": "app_launch", "app_path": "/Applications/Zen.app", "args": ["--profile", "work"] }
        """.data(using: .utf8)!
        let action3 = try decoder.decode(ShortcutActionConfig.self, from: argsArrayJSON)
        #expect(action3.type == .appLaunch)
        #expect(action3.target == "/Applications/Zen.app")
        #expect(action3.arguments?["0"] == "--profile")
        #expect(action3.arguments?["1"] == "work")
        #expect(action3.arguments?["args"] == "--profile work")
    }

    @Test("ShortcutConfig key combination parsing")
    func testKeyCombinationParsing() {
        let (k1, m1) = ShortcutConfig.parseKeyCombinationString("cmd+shift+k")
        #expect(k1 == "k")
        #expect(m1.contains("cmd"))
        #expect(m1.contains("shift"))

        let (k2, m2) = ShortcutConfig.parseKeyCombinationString("opt+space")
        #expect(k2 == "space")
        #expect(m2 == ["opt"])

        let (k3, m3) = ShortcutConfig.parseKeyCombinationString("ctrl+alt+t")
        #expect(k3 == "t")
        #expect(m3.contains("ctrl"))
        #expect(m3.contains("opt"))

        let (k4, m4) = ShortcutConfig.parseKeyCombinationString("  ⌘ + ⇧ + Z  ")
        #expect(k4 == "z")
        #expect(m4.contains("cmd"))
        #expect(m4.contains("shift"))

        let (k5, m5) = ShortcutConfig.parseKeyCombinationString("return")
        #expect(k5 == "return")
        #expect(m5.isEmpty)

        let (kPlus, mPlus) = ShortcutConfig.parseKeyCombinationString("cmd++")
        #expect(kPlus == "+")
        #expect(mPlus == ["cmd"])

        let (kMinus, mMinus) = ShortcutConfig.parseKeyCombinationString("cmd+-")
        #expect(kMinus == "-")
        #expect(mMinus == ["cmd"])

        let (kEqual, mEqual) = ShortcutConfig.parseKeyCombinationString("cmd+=")
        #expect(kEqual == "=")
        #expect(mEqual == ["cmd"])

        let (kGlyph, mGlyph) = ShortcutConfig.parseKeyCombinationString("⌘⇧K")
        #expect(kGlyph == "k")
        #expect(mGlyph.contains("cmd"))
        #expect(mGlyph.contains("shift"))

        let (kOptSpace, mOptSpace) = ShortcutConfig.parseKeyCombinationString("⌥Space")
        #expect(kOptSpace == "space")
        #expect(mOptSpace == ["opt"])

        let (kFn, mFn) = ShortcutConfig.parseKeyCombinationString("fn+f1")
        #expect(kFn == "f1")
        #expect(mFn == ["fn"])
    }

    @Test("ShortcutConfig JSON serialization and deserialization round-trip")
    func testShortcutConfigRoundTrip() throws {
        let action = ShortcutActionConfig(
            type: .pluginCommand,
            target: "titik.builtin.zen",
            arguments: ["command": "open-url", "url": "https://swift.org"]
        )
        let shortcut = ShortcutConfig(
            id: "zen-swift",
            name: "Open Swift.org in Zen",
            key: "z",
            modifiers: ["cmd", "shift"],
            mode: .background,
            action: action
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(shortcut)

        let decoded = try JSONDecoder().decode(ShortcutConfig.self, from: data)
        #expect(decoded.id == "zen-swift")
        #expect(decoded.name == "Open Swift.org in Zen")
        #expect(decoded.key == "z")
        #expect(decoded.modifiers.contains("cmd"))
        #expect(decoded.modifiers.contains("shift"))
        #expect(decoded.mode == .background)
        #expect(decoded.action.type == .pluginCommand)
        #expect(decoded.action.target == "titik.builtin.zen")
        #expect(decoded.action.arguments?["url"] == "https://swift.org")
        #expect(decoded.keyCombinationString == "cmd+shift+z" || decoded.keyCombinationString == "shift+cmd+z")
    }

    @Test("Config decoding with shortcuts array")
    func testConfigWithShortcutsDecoding() throws {
        let json = """
        {
            "window": { "width": 800 },
            "shortcuts": [
                {
                    "id": "open-zen",
                    "name": "Open Zen Browser",
                    "keys": "cmd+shift+z",
                    "mode": "background",
                    "action": {
                        "type": "app_launch",
                        "target": "/Applications/Zen Browser.app"
                    }
                },
                {
                    "id": "search-docs",
                    "name": "Search Docs",
                    "key": "d",
                    "modifiers": ["cmd", "opt"],
                    "mode": "palette",
                    "action": {
                        "type": "raw_query",
                        "target": "!zen https://docs.swift.org"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.shortcuts.count == 2)

        let s1 = config.shortcuts[0]
        #expect(s1.id == "open-zen")
        #expect(s1.key == "z")
        #expect(s1.modifiers.contains("cmd"))
        #expect(s1.modifiers.contains("shift"))
        #expect(s1.mode == .background)
        #expect(s1.action.type == .appLaunch)
        #expect(s1.action.target == "/Applications/Zen Browser.app")

        let s2 = config.shortcuts[1]
        #expect(s2.id == "search-docs")
        #expect(s2.key == "d")
        #expect(s2.modifiers.contains("cmd"))
        #expect(s2.modifiers.contains("opt"))
        #expect(s2.mode == .palette)
        #expect(s2.action.type == .rawQuery)
        #expect(s2.action.target == "!zen https://docs.swift.org")
    }

    @Test("Resilient config decoding: skips malformed shortcut entries without failing overall config")
    func testResilientConfigDecoding() throws {
        let json = """
        {
            "window": { "width": 750, "height": 480 },
            "shortcuts": [
                {
                    "id": "valid-1",
                    "name": "Valid Shortcut 1",
                    "key": "1",
                    "modifiers": ["cmd"],
                    "mode": "palette",
                    "action": { "type": "toggle_window", "target": "main" }
                },
                {
                    "id": "corrupted-1",
                    "missing_key_and_action": true
                },
                {
                    "id": "valid-2",
                    "name": "Valid Shortcut 2",
                    "keys": "cmd+shift+2",
                    "mode": "background",
                    "action": { "type": "quick_link", "target": "https://apple.com" }
                },
                "completely_invalid_string_entry",
                {
                    "id": "corrupted-2",
                    "key": "3",
                    "action": { "invalid_action_type": 999 }
                },
                {
                    "id": "valid-3",
                    "key": "3",
                    "modifiers": ["opt"],
                    "action": { "type": "system_command", "target": "sleep" }
                }
            ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.window.width == 750)
        #expect(config.window.height == 480)

        // Should have safely recovered the 3 valid shortcuts and skipped the 3 malformed ones
        #expect(config.shortcuts.count == 3)
        #expect(config.shortcuts[0].id == "valid-1")
        #expect(config.shortcuts[1].id == "valid-2")
        #expect(config.shortcuts[2].id == "valid-3")
        #expect(config.shortcuts[2].action.type == .systemCommand)
    }

    @Test("Config decoding when shortcuts is a dictionary")
    func testConfigShortcutsDictionaryDecoding() throws {
        let json = """
        {
            "shortcuts": {
                "toggle": {
                    "id": "toggle-shortcut",
                    "keys": "ctrl+space",
                    "action": { "type": "toggle_window", "target": "main" }
                }
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.shortcuts.count == 1)
        #expect(config.shortcuts[0].id == "toggle-shortcut")
        #expect(config.shortcuts[0].key == "space")
        #expect(config.shortcuts[0].modifiers.contains("ctrl"))
    }

    @Test("Shorthand action string decoding (\"action\": \"!zen\")")
    func testShorthandActionStringDecoding() throws {
        let decoder = JSONDecoder()

        // Single value raw query
        let queryJSON = "\"!zen\"".data(using: .utf8)!
        let queryAction = try decoder.decode(ShortcutActionConfig.self, from: queryJSON)
        #expect(queryAction.type == .rawQuery)
        #expect(queryAction.target == "!zen")

        // Single value URL
        let urlJSON = "\"https://apple.com\"".data(using: .utf8)!
        let urlAction = try decoder.decode(ShortcutActionConfig.self, from: urlJSON)
        #expect(urlAction.type == .quickLink)
        #expect(urlAction.target == "https://apple.com")

        // Nested action as string in ShortcutConfig
        let shortcutJSON = """
        {
            "id": "zen-shortcut",
            "keys": "cmd+shift+k",
            "action": "!zen"
        }
        """.data(using: .utf8)!
        let shortcut = try decoder.decode(ShortcutConfig.self, from: shortcutJSON)
        #expect(shortcut.id == "zen-shortcut")
        #expect(shortcut.key == "k")
        #expect(shortcut.modifiers.contains("cmd"))
        #expect(shortcut.modifiers.contains("shift"))
        #expect(shortcut.action.type == .rawQuery)
        #expect(shortcut.action.target == "!zen")

        // Nested action as url string in ShortcutConfig
        let urlShortcutJSON = """
        {
            "id": "apple-shortcut",
            "shortcut": "opt+a",
            "action": "https://apple.com"
        }
        """.data(using: .utf8)!
        let urlShortcut = try decoder.decode(ShortcutConfig.self, from: urlShortcutJSON)
        #expect(urlShortcut.action.type == .quickLink)
        #expect(urlShortcut.action.target == "https://apple.com")
    }

    @Test("Top-level command shortcut decoding ({\"key\": \"k\", \"modifiers\": [\"cmd\"], \"command\": \"!zen\"})")
    func testTopLevelCommandShortcutDecoding() throws {
        let decoder = JSONDecoder()

        // Top-level "command"
        let cmdJSON = """
        {
            "key": "k",
            "modifiers": ["cmd"],
            "command": "!zen"
        }
        """.data(using: .utf8)!
        let scCmd = try decoder.decode(ShortcutConfig.self, from: cmdJSON)
        #expect(scCmd.key == "k")
        #expect(scCmd.modifiers == ["cmd"])
        #expect(scCmd.action.type == .rawQuery)
        #expect(scCmd.action.target == "!zen")

        // Top-level "url"
        let urlJSON = """
        {
            "key": "u",
            "modifiers": ["opt"],
            "url": "https://apple.com"
        }
        """.data(using: .utf8)!
        let scUrl = try decoder.decode(ShortcutConfig.self, from: urlJSON)
        #expect(scUrl.key == "u")
        #expect(scUrl.modifiers == ["opt"])
        #expect(scUrl.action.type == .quickLink)
        #expect(scUrl.action.target == "https://apple.com")

        // Top-level "target"
        let targetJSON = """
        {
            "shortcut": "cmd+shift+d",
            "target": "!file /tmp"
        }
        """.data(using: .utf8)!
        let scTarget = try decoder.decode(ShortcutConfig.self, from: targetJSON)
        #expect(scTarget.key == "d")
        #expect(scTarget.action.type == .rawQuery)
        #expect(scTarget.action.target == "!file /tmp")
    }

    @Test("Dictionary mapping shortcuts ({\"cmd+shift+k\": \"!zen\"})")
    func testDictionaryMappingShortcutsDecoding() throws {
        let json = """
        {
            "shortcuts": {
                "cmd+shift+k": "!zen",
                "opt+space": "!emoji",
                "cmd+g": "https://google.com"
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.shortcuts.count == 3)

        let zen = config.shortcuts.first(where: { $0.key == "k" })
        #expect(zen != nil)
        #expect(zen?.modifiers.contains("cmd") == true)
        #expect(zen?.modifiers.contains("shift") == true)
        #expect(zen?.action.type == .rawQuery)
        #expect(zen?.action.target == "!zen")

        let emoji = config.shortcuts.first(where: { $0.key == "space" })
        #expect(emoji != nil)
        #expect(emoji?.modifiers.contains("opt") == true)
        #expect(emoji?.action.type == .rawQuery)
        #expect(emoji?.action.target == "!emoji")

        let google = config.shortcuts.first(where: { $0.key == "g" })
        #expect(google != nil)
        #expect(google?.modifiers.contains("cmd") == true)
        #expect(google?.action.type == .quickLink)
        #expect(google?.action.target == "https://google.com")
    }

    @Test("ensureConfigFileExists ensures user config path exists on disk")
    func testEnsureConfigFileExists() throws {
        let url = try ConfigLoader.shared.ensureConfigFileExists()
        #expect(url == ConfigLoader.userConfigPath)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
