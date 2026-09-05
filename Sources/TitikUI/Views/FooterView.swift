import SwiftUI

public struct FooterView: View {
    public var isPluginActive: Bool
    public var isActionPaletteActive: Bool
    public var isCategoryDirectory: Bool
    public var canGoBack: Bool
    public var pluginKeycaps: [KeycapAction]?

    public init(
        isPluginActive: Bool = false,
        isActionPaletteActive: Bool = false,
        isCategoryDirectory: Bool = false,
        canGoBack: Bool = false,
        pluginKeycaps: [KeycapAction]? = nil
    ) {
        self.isPluginActive = isPluginActive
        self.isActionPaletteActive = isActionPaletteActive
        self.isCategoryDirectory = isCategoryDirectory
        self.canGoBack = canGoBack
        self.pluginKeycaps = pluginKeycaps
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Brand Label
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                Text("Titik")
                    .font(Theme.fontBrand)
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            // Dynamic Keycap Actions
            HStack(spacing: 12) {
                if isActionPaletteActive {
                    KeycapView(shortcut: "↵", label: "Execute")
                    KeycapView(shortcut: "↑↓", label: "Navigate")
                    KeycapView(shortcut: "esc", label: "Dismiss")
                } else if let keycaps = pluginKeycaps {
                    ForEach(keycaps, id: \.self) { action in
                        KeycapView(shortcut: action.shortcut, label: action.label)
                    }
                } else if isPluginActive {
                    KeycapView(shortcut: "esc", label: "Close")
                } else {
                    if canGoBack {
                        KeycapView(shortcut: "←", label: "Back")
                    }
                    KeycapView(shortcut: "↵", label: "Open")
                    KeycapView(shortcut: "⇥", label: isCategoryDirectory ? "Drill-in" : "Complete")
                    KeycapView(shortcut: "⌘K", label: "Actions")
                    KeycapView(shortcut: "!", label: "Modes")
                    KeycapView(shortcut: "⌘O", label: "Finder")
                    KeycapView(shortcut: "⌘C", label: "Copy")
                    KeycapView(shortcut: "esc", label: "Close")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
    }
}
