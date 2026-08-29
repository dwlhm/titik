import Testing
import SwiftUI
import TitikUI
import TitikCore

@Suite("UITheme Tests")
struct UIThemeTests {
    @Test("Pastel category badge colors")
    func testPastelCategoryColors() {
        let appColor = Theme.colorForCategory(.application)
        #expect(appColor == Theme.categoryApp)

        let mathColor = Theme.colorForCategory(.calculator)
        #expect(mathColor == Theme.categoryMath)

        let cmdColor = Theme.colorForCategory(.systemCommand)
        #expect(cmdColor == Theme.categoryCommand)

        let clipColor = Theme.colorForCategory(.clipboard)
        #expect(clipColor == Theme.categoryClipboard)

        let fileColor = Theme.colorForCategory(.file)
        #expect(fileColor == Theme.categoryFile)

        let dirColor = Theme.colorForCategory(.directory)
        #expect(dirColor == Theme.categoryDirectory)

        let emojiColor = Theme.colorForCategory(.emoji)
        #expect(emojiColor == Theme.categoryEmoji)
    }

    @Test("Hex color parsing and conversion")
    func testHexColorConversion() {
        let rgba = RGBAColor.parseHex("#ff0000")
        #expect(rgba != nil)
        let color = Theme.colorFromHex("#ff0000")
        _ = color
    }

    @Test("Liquid glass feasibility engine")
    func testLiquidGlassFeasibility() {
        let shouldReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let defaultFeasible = Theme.isLiquidGlassFeasible()
        #expect(defaultFeasible == !shouldReduce)
        let highAlphaFeasible = Theme.isLiquidGlassFeasible(alpha: 0.95)
        #expect(highAlphaFeasible == false)
        let lowAlphaFeasible = Theme.isLiquidGlassFeasible(alpha: 0.48)
        #expect(lowAlphaFeasible == !shouldReduce)
    }

    @Test("SF Trio Typography tokens availability")
    func testTypographyTokens() {
        _ = Theme.fontSearchInput
        _ = Theme.fontSearchPlaceholder
        _ = Theme.fontRowTitle
        _ = Theme.fontRowSubtitle
        _ = Theme.fontBadge
        _ = Theme.fontKeycap
        _ = Theme.fontFooterLabel
        _ = Theme.fontBrand
        _ = Theme.fontPreviewTitle
        _ = Theme.fontPreviewSubtitle
        _ = Theme.fontPreviewBody
        _ = Theme.fontCode
        _ = Theme.fontMathResult
        _ = Theme.fontToast
    }

    @Test("Glass substrate and motion tokens availability")
    func testGlassSubstrateAndMotionTokens() {
        _ = Theme.glassSurfaceGradient
        _ = Theme.glassSpecularGlare
        _ = Theme.borderGlassGradient
        _ = Theme.borderGlassBevel
        _ = Theme.springPresentation
        _ = Theme.springInteractive
        _ = Theme.springSnappy
    }
}
