import Testing
import TitikCore

@Suite("SystemCommands Tests")
struct SystemCommandsTests {
    let commands = SystemCommands()

    @Test("Commands catalog integrity")
    func testCommandsCatalogIntegrity() {
        let allCmds = commands.getAllCommands()
        #expect(allCmds.count >= 10)

        let requiredIds = [
            "system.lock",
            "system.sleep",
            "system.restart",
            "system.shutdown",
            "system.logout",
            "system.empty_trash",
            "system.toggle_dark_mode",
            "system.screensaver",
            "system.mute",
            "system.volume_up",
            "system.volume_down"
        ]

        for reqId in requiredIds {
            #expect(commands.findCommand(by: reqId) != nil, "Missing system command: \(reqId)")
        }
    }

    @Test("Find command by ID")
    func testFindCommand() {
        let lockCmd = commands.findCommand(by: "system.lock")
        #expect(lockCmd != nil)
        #expect(lockCmd?.title == "Lock Screen")
        #expect(lockCmd?.keywords.contains("lock") == true)
    }
}
