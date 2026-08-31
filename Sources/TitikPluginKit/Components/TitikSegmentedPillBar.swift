import SwiftUI
import AppKit
import TitikUI

public struct TitikSegmentedPillBar<Item: Hashable & Sendable>: View {
    public let items: [Item]
    @Binding public var selection: Item
    public let title: (Item) -> String
    public let iconName: ((Item) -> String?)?
    public let onSelect: ((Item) -> Void)?

    @Namespace private var animationNamespace
    @State private var hoveredItem: Item? = nil

    public init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        iconName: ((Item) -> String?)? = nil,
        onSelect: ((Item) -> Void)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.iconName = iconName
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                let isHovered = item == hoveredItem

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selection = item
                    }
                    onSelect?(item)
                }) {
                    HStack(spacing: 6) {
                        if let icon = iconName?(item) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : Color.white.opacity(0.7))
                        }
                        Text(title(item))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.85),
                                        Color.blue.opacity(0.65)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .matchedGeometryEffect(id: "activePill", in: animationNamespace)
                            .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 2)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                }
                .onHover { hovering in
                    hoveredItem = hovering ? item : nil
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
