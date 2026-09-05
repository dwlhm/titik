import Testing
import TitikCore

@Suite("AppLauncher Tests")
struct AppLauncherTests {
    let launcher = AppLauncher()

    @Test("Scan macOS applications")
    func testAppScanning() {
        let apps = launcher.scanApplications()
        #expect(!apps.isEmpty, "Should find at least some system/user applications on macOS")

        for app in apps {
            #expect(!app.name.hasSuffix(".app"), "App name should strip .app extension: \(app.name)")
            #expect(app.path.hasSuffix(".app"), "App path must end with .app: \(app.path)")
        }
    }
}
