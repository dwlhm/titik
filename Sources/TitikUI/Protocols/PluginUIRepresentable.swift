import SwiftUI
import AppKit

@MainActor
public protocol PluginUIRepresentable: AnyObject {
    var pluginId: String { get }
    var customView: AnyView { get }
    func handleSearchQuery(_ query: String)
    func submitQuery()
    func handleAction(actionId: String, payload: String) -> Bool
    func handleKeyDown(event: NSEvent) -> Bool
    func scrollTo(targetId: String, anchor: UnitPoint)
}

public extension PluginUIRepresentable {
    func handleSearchQuery(_ query: String) {}
    func submitQuery() {}
    func handleAction(actionId: String, payload: String) -> Bool { false }
    func handleKeyDown(event: NSEvent) -> Bool { false }
    func scrollTo(targetId: String, anchor: UnitPoint) {}
}

