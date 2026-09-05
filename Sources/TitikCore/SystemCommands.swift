import Foundation
import AppKit

public struct SystemCommandItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let keywords: [String]
    public let action: @Sendable () -> Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String],
        action: @escaping @Sendable () -> Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.action = action
    }
}

public final class SystemCommands: Sendable {
    public static let shared = SystemCommands()

    public static var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["SWIFT_TESTING"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: {
            $0.contains("xctest") || $0.contains("testing-helper") || $0.contains("TitikPackageTests")
        })
    }

    public nonisolated(unsafe) static var scriptExecutor: (@Sendable (String) -> Bool)? = nil

    public init() {}

    @discardableResult
    public static func runAppleScript(_ script: String) -> Bool {
        if let customExecutor = scriptExecutor {
            return customExecutor(script)
        }
        if isTestEnvironment {
            Logger.shared.debug("Test environment detected: skipping AppleScript execution: \(script)", subsystem: "Titik.SystemCommands")
            return true
        }

        func execute() -> Bool {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                _ = scriptObject.executeAndReturnError(&error)
                if let error = error {
                    Logger.shared.error("AppleScript error: \(error)", subsystem: "Titik.SystemCommands")
                    return false
                }
                return true
            }
            return false
        }

        if Thread.isMainThread {
            return execute()
        } else {
            return DispatchQueue.main.sync {
                execute()
            }
        }
    }

    public static func lockScreen() -> Bool {
        if isTestEnvironment {
            return true
        }

        // Try SACLockScreenImmediate via login.framework if available
        let bundlePath = "/System/Library/PrivateFrameworks/login.framework"
        if let handle = dlopen(bundlePath, RTLD_LAZY) {
            defer { dlclose(handle) }
            typealias SACLockScreenImmediateFunc = @convention(c) () -> Void
            if let sym = dlsym(handle, "SACLockScreenImmediate") {
                let lockFunc = unsafeBitCast(sym, to: SACLockScreenImmediateFunc.self)
                lockFunc()
                return true
            }
        }

        // Fallback to ScreenSaverEngine
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "ScreenSaverEngine"]
        do {
            try task.run()
            return true
        } catch {
            return runAppleScript("tell application \"System Events\" to start current screen saver")
        }
    }

    public func getAllCommands() -> [SystemCommandItem] {
        return [
            SystemCommandItem(
                id: "system.lock",
                title: "Lock Screen",
                subtitle: "Lock your Mac immediately",
                keywords: ["lock", "screen", "sleep", "protect"],
                action: { SystemCommands.lockScreen() }
            ),
            SystemCommandItem(
                id: "system.sleep",
                title: "Sleep",
                subtitle: "Put your Mac to sleep",
                keywords: ["sleep", "standby", "suspend"],
                action: { SystemCommands.runAppleScript("tell application \"System Events\" to sleep") }
            ),
            SystemCommandItem(
                id: "system.restart",
                title: "Restart...",
                subtitle: "Restart your Mac",
                keywords: ["restart", "reboot"],
                action: { SystemCommands.runAppleScript("tell application \"System Events\" to restart") }
            ),
            SystemCommandItem(
                id: "system.shutdown",
                title: "Shut Down...",
                subtitle: "Shut down your Mac completely",
                keywords: ["shutdown", "shut", "down", "poweroff", "turn off"],
                action: { SystemCommands.runAppleScript("tell application \"System Events\" to shut down") }
            ),
            SystemCommandItem(
                id: "system.logout",
                title: "Log Out...",
                subtitle: "Log out of the current macOS session",
                keywords: ["logout", "log out", "sign out"],
                action: { SystemCommands.runAppleScript("tell application \"System Events\" to log out") }
            ),
            SystemCommandItem(
                id: "system.empty_trash",
                title: "Empty Trash",
                subtitle: "Permanently delete items in Trash",
                keywords: ["empty", "trash", "clean", "bin"],
                action: { SystemCommands.runAppleScript("tell application \"Finder\" to empty trash") }
            ),
            SystemCommandItem(
                id: "system.toggle_dark_mode",
                title: "Toggle Dark Mode",
                subtitle: "Switch between Dark and Light appearance",
                keywords: ["dark", "light", "mode", "theme", "appearance"],
                action: {
                    SystemCommands.runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
                }
            ),
            SystemCommandItem(
                id: "system.screensaver",
                title: "Start Screen Saver",
                subtitle: "Activate the system screen saver",
                keywords: ["screensaver", "saver", "screen"],
                action: {
                    SystemCommands.runAppleScript("tell application \"System Events\" to start current screen saver")
                }
            ),
            SystemCommandItem(
                id: "system.mute",
                title: "Mute / Unmute Volume",
                subtitle: "Toggle system audio mute",
                keywords: ["mute", "unmute", "audio", "volume", "sound"],
                action: {
                    SystemCommands.runAppleScript("set volume with output muted not (output muted of (get volume settings))")
                }
            ),
            SystemCommandItem(
                id: "system.volume_up",
                title: "Volume Up",
                subtitle: "Increase system audio volume",
                keywords: ["volume", "louder", "up", "sound", "increase"],
                action: {
                    SystemCommands.runAppleScript("set volume output volume ((output volume of (get volume settings)) + 6)")
                }
            ),
            SystemCommandItem(
                id: "system.volume_down",
                title: "Volume Down",
                subtitle: "Decrease system audio volume",
                keywords: ["volume", "quieter", "down", "sound", "decrease"],
                action: {
                    SystemCommands.runAppleScript("set volume output volume ((output volume of (get volume settings)) - 6)")
                }
            )
        ]
    }

    public func findCommand(by id: String) -> SystemCommandItem? {
        getAllCommands().first { $0.id == id }
    }

    public func executeCommand(by id: String) -> Bool {
        guard let cmd = findCommand(by: id) else { return false }
        return cmd.action()
    }
}
