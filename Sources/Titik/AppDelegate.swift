import Foundation
import AppKit
import SwiftUI
import TitikCore
import TitikKeymap
import TitikUI
import TitikSearch
import TitikPlatform
import TitikPlugins
import TitikPluginKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        // 1. Load configuration
        let config = ConfigLoader.shared.load()
        Logger.shared.info("Titik application launching...", subsystem: "Titik.App")

        // 2. Set window behaviors
        WindowController.shared.autoHideOnBlur = config.behaviors.autoHideOnBlur
        ClipboardManager.shared.maxCapacity = config.behaviors.maxClipboardHistory

        // 3. Scan applications in background
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AppLauncher.shared.scanApplications()
        }

        // 4. Start clipboard monitoring
        ClipboardManager.shared.startMonitoring()

        // 5. Load plugins
        PluginHost.shared.loadAll()

        // 6. Setup main window
        let contentView = AnyView(MainContentView(orchestrator: UIOrchestrator.shared))
        WindowController.shared.setupWindow(
            contentView: contentView,
            width: CGFloat(config.window.width),
            height: CGFloat(config.window.height)
        )

        WindowController.shared.onWindowClosed = {
            Task { @MainActor in
                UIOrchestrator.shared.reset()
            }
        }

        // 7. Register global hotkey
        let mod = config.hotkey.modifier
        let key = config.hotkey.key
        let success = HotkeyManager.shared.updateHotkey(modifier: mod, key: key) {
            Task { @MainActor in
                WindowController.shared.toggleWindow()
            }
        }

        if success {
            Logger.shared.info("Global hotkey \(mod)+\(key) active", subsystem: "Titik.App")
        } else {
            Logger.shared.warn("Failed to bind hotkey \(mod)+\(key)", subsystem: "Titik.App")
        }

        Logger.shared.info("Titik startup complete", subsystem: "Titik.App")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
        ClipboardManager.shared.stopMonitoring()
        PluginHost.shared.shutdownAll()
        Logger.shared.info("Titik terminated cleanly", subsystem: "Titik.App")
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Titik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}
