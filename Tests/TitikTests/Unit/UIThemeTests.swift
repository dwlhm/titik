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
    }

    @Test("Hex color parsing and conversion")
    func testHexColorConversion() {
        let rgba = RGBAColor.parseHex("#ff0000")
        #expect(rgba != nil)
        let color = Theme.colorFromHex("#ff0000")
        _ = color
    }
}
