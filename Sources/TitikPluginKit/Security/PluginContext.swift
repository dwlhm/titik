import Foundation
import TitikUI

public struct URLSanitizer: Sendable {
    public static func sanitize(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return nil
        }
        guard let scheme = url.scheme?.lowercased() else {
            return nil
        }
        // Block dangerous schemes
        let forbiddenSchemes: Set<String> = [
            "file", "applescript", "terminal", "javascript", "data", "blob", "vbscript", "about"
        ]
        if forbiddenSchemes.contains(scheme) {
            return nil
        }
        // Only allow safe HTTPS (or HTTP if specifically formatted)
        guard scheme == "https" || scheme == "http" else {
            return nil
        }
        guard let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    public static func isSafeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        let forbiddenSchemes: Set<String> = [
            "file", "applescript", "terminal", "javascript", "data", "blob", "vbscript", "about"
        ]
        if forbiddenSchemes.contains(scheme) {
            return false
        }
        return scheme == "https" || scheme == "http"
    }
}

public final class PluginContext: @unchecked Sendable {
    public let pluginId: String
    public let keychain: PluginKeychainService
    public let storageDirectory: URL
    public let temporaryDirectory: URL
    @MainActor public lazy var keymap: PluginKeymapScope = PluginKeymapScope()

    public init(pluginId: String, keychain: PluginKeychainService? = nil, baseStorageURL: URL? = nil) {
        self.pluginId = pluginId
        self.keychain = keychain ?? HostKeychainService(pluginId: pluginId)

        let base = baseStorageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let pluginDir = base.appendingPathComponent("Titik").appendingPathComponent("Plugins").appendingPathComponent(pluginId)
        self.storageDirectory = pluginDir
        self.temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("titik_plugin_\(pluginId)")

        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    @MainActor public static var hudPresenter: (@MainActor @Sendable (_ query: String?) -> Void)?
    @MainActor public static var hudDismisser: (@MainActor @Sendable () -> Void)?

    @MainActor
    public func summonHUD(query: String? = nil) {
        Self.hudPresenter?(query)
    }

    @MainActor
    public func dismissHUD() {
        Self.hudDismisser?()
    }

    @MainActor
    public func showToast(
        message: String,
        icon: String? = nil,
        type: ToastType = .info,
        duration: TimeInterval = 2.5
    ) {
        ToastManager.shared.show(message: message, icon: icon, type: type, duration: duration)
    }

    @MainActor
    public func dismissToast() {
        ToastManager.shared.dismiss()
    }
}
