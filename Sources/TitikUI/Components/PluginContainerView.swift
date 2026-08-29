import SwiftUI

@MainActor
public struct PluginContainerView: View {
    public let pluginUI: (any PluginUIRepresentable)?

    public init(pluginUI: (any PluginUIRepresentable)?) {
        self.pluginUI = pluginUI
    }

    public var body: some View {
        if let pluginUI = pluginUI {
            pluginUI.customView
        } else {
            EmptyView()
        }
    }
}

