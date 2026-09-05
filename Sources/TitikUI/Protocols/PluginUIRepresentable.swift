import SwiftUI
import AppKit

public struct KeycapAction: Sendable, Equatable, Hashable {
    public let shortcut: String
    public let label: String
    public init(shortcut: String, label: String) {
        self.shortcut = shortcut
        self.label = label
    }
}

@MainActor
public protocol PluginUIRepresentable: AnyObject {
    var pluginId: String { get }
    var customView: AnyView { get }
    var keymapScope: PluginKeymapScope { get }
    var footerKeycaps: [KeycapAction]? { get }
    var onDismiss: (@MainActor () -> Void)? { get set }
    func onActivated()
    func handleSearchQuery(_ query: String)
    func submitQuery()
    func handleAction(actionId: String, payload: String) -> Bool
    func scrollTo(targetId: String, anchor: UnitPoint)
}

public extension PluginUIRepresentable {
    var keymapScope: PluginKeymapScope { PluginKeymapScope() }
    var footerKeycaps: [KeycapAction]? {
        let caps = keymapScope.keycaps
        return caps.isEmpty ? nil : caps
    }
    var onDismiss: (@MainActor () -> Void)? {
        get { nil }
        set {}
    }
    func onActivated() {}
    func handleSearchQuery(_ query: String) {}
    func submitQuery() {}
    func handleAction(actionId: String, payload: String) -> Bool { false }
    func scrollTo(targetId: String, anchor: UnitPoint) {}
}
