import SwiftUI

public struct KeycapView: View {
    public let shortcut: String
    public let label: String

    public init(shortcut: String, label: String) {
        self.shortcut = shortcut
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Theme.textMuted)
        }
    }
}
