import SwiftUI
import AppKit
import TitikCore

public struct ResultItemRow: View {
    public let item: SearchItem
    public let isSelected: Bool

    public init(item: SearchItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    private var defaultIconName: String {
        switch item.category {
        case .application: return "app.badge"
        case .systemCommand: return "gearshape.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .calculator: return "function"
        case .plugin: return "puzzlepiece.extension.fill"
        case .custom: return "star.fill"
        case .directory: return "folder.fill"
        case .emoji: return "face.smiling"
        case .file:
            switch item.previewType {
            case .image: return "photo.fill"
            case .video: return "film.fill"
            case .audio: return "music.note"
            case .pdf: return "doc.richtext.fill"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .fileMetadata: return "doc.fill"
            default: return "doc.fill"
            }
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Icon
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: defaultIconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.colorForCategory(item.category))
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 28, height: 28)

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.fontRowTitle)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Theme.fontRowSubtitle)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Category Badge
            Text(item.category.badgeName)
                .font(Theme.fontBadge)
                .foregroundColor(Theme.colorForCategory(item.category))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Theme.colorForCategory(item.category).opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Theme.colorForCategory(item.category).opacity(0.3), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.selectionBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .opacity(isSelected ? 1.0 : 0.0)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
        .contentShape(Rectangle())
    }
}
