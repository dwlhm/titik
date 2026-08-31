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

    @Test("Config JSON decoding")
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
}
