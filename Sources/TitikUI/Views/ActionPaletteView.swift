import SwiftUI
import AppKit
import TitikCore

public struct ActionPaletteView: View {
    public let actions: [ContextualAction]
    @Binding public var selectedIndex: Int
    public let onSelect: (ContextualAction) -> Void
    public let onDismiss: () -> Void

    public init(
        actions: [ContextualAction],
        selectedIndex: Binding<Int>,
        onSelect: @escaping (ContextualAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.actions = actions
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Backdrop dismissal
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Floating Palette Card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "command")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.accent)
                    Text("Actions")
                        .font(Theme.fontBrand)
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    KeycapView(shortcut: "esc", label: "Back")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04))

                Divider()
                    .background(Theme.borderGlass)

                // Action Items List
                if actions.isEmpty {
                    VStack(spacing: 6) {
                        Text("No actions available")
                            .font(Theme.fontRowSubtitle)
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                    let isSelected = selectedIndex == index
                                    ActionPaletteRow(
                                        action: action,
                                        isSelected: isSelected,
                                        onTap: {
                                            selectedIndex = index
                                            onSelect(action)
                                        }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: selectedIndex) { newIndex in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .frame(width: 380)
            .hudGlassBackground(cornerRadius: 12)
            .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct ActionPaletteRow: View {
    let action: ContextualAction
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 20)

                Text(action.title)
                    .font(Theme.fontRowTitle)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)

                Spacer()

                if let shortcut = action.shortcut {
                    KeycapView(shortcut: shortcut, label: "")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Theme.selectionBg
                    : (isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
