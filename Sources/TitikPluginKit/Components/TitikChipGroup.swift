import SwiftUI
import AppKit
import TitikUI

public struct TitikChipGroup: View {
    public let title: String?
    public let chips: [String]
    public let onSelect: (String) -> Void

    @State private var hoveredChip: String? = nil

    public init(
        title: String? = nil,
        chips: [String],
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.chips = chips
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.75))
            }

            TitikFlowLayout(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    let isHovered = chip == hoveredChip

                    Button(action: {
                        onSelect(chip)
                    }) {
                        HStack(spacing: 5) {
                            Text("\"\(chip)\"")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(isHovered ? 1.0 : 0.85))
                                .lineLimit(1)

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color.blue.opacity(isHovered ? 1.0 : 0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(isHovered ? 0.12 : 0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isHovered ? Color.blue.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredChip = hovering ? chip : nil
                    }
                }
            }
        }
    }
}

public struct TitikFlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: currentY + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
