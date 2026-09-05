import Foundation
import AppKit
import SwiftUI
import TitikCore

public final class FloatingPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                return super.performKeyEquivalent(with: event)
            }
            switch chars {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }
            case "c":
                if let textView = firstResponder as? NSTextView, textView.selectedRange().length > 0 {
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                        return true
                    }
                }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                    return true
                }
            case "z":
                let action = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
                if NSApp.sendAction(action, to: nil, from: self) {
                    return true
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
public final class WindowController: NSObject, NSWindowDelegate {
    public static let shared = WindowController()

    public private(set) var panel: FloatingPanel?
    public var autoHideOnBlur: Bool = true
    public var onWindowClosed: (@Sendable () -> Void)?

    public override init() {
        super.init()
        AutoPaster.shared.windowCloser = { [weak self] in
            self?.hideWindow()
        }
    }

    public func setupWindow(contentView: AnyView, width: CGFloat = 720, height: CGFloat = 460) {
        let hostingView = NSHostingView(rootView: contentView)

        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.contentView = hostingView
        p.delegate = self

        self.panel = p

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: p
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc public func applicationDidBecomeActive(_ notification: Notification) {
        if let panel = panel, panel.isVisible, !panel.isKeyWindow {
            panel.makeKey()
        }
    }

    @objc public func windowDidResignKey(_ notification: Notification) {
        guard autoHideOnBlur else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.autoHideOnBlur else { return }
            guard let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }

            if let frontmost = NSWorkspace.shared.frontmostApplication {
                let bundleId = frontmost.bundleIdentifier ?? ""
                if bundleId.hasPrefix("com.apple.coreservices") ||
                   bundleId == "com.apple.SecurityAgent" ||
                   bundleId == "com.apple.UserNotificationCenter" ||
                   frontmost.processIdentifier == NSRunningApplication.current.processIdentifier {
                    return
                }
            }

            self.hideWindow()
        }
    }

    public func centerOnActiveScreen() {
        guard let panel = panel else { return }

        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = activeScreen else { return }

        let screenFrame = screen.frame
        let windowWidth = panel.frame.width
        let windowHeight = panel.frame.height

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2.0
        // Golden ratio ~58% from bottom (Spotlight position)
        let y = screenFrame.origin.y + (screenFrame.height * 0.58) - (windowHeight / 2.0)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    public func showWindow() {
        guard let panel = panel else { return }

        // Capture previous frontmost application if it is not Titik
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            AutoPaster.shared.lastActiveApplication = frontmost
        }

        centerOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Logger.shared.debug("Window shown", subsystem: "Titik.Platform")
    }

    public func hideWindow() {
        guard let panel = panel, panel.isVisible else { return }

        panel.orderOut(nil)
        onWindowClosed?()
        Logger.shared.debug("Window hidden", subsystem: "Titik.Platform")
    }

    public func toggleWindow() {
        guard let panel = panel else { return }
        if panel.isVisible && panel.isKeyWindow {
            hideWindow()
        } else {
            showWindow()
        }
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
