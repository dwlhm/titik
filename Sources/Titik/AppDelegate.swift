import Foundation
import AppKit
import SwiftUI
import TitikCore
import TitikKeymap
import TitikUI
import TitikSearch
import TitikPlatform
import TitikPlugins

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
}
