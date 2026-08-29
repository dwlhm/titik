import SwiftUI
import AppKit
import TitikCore

public struct SearchBarView: View {
    @Binding public var text: String
    public var placeholder: String
    public var onSubmit: () -> Void
    public var onCancel: () -> Void

    private var ghostSuffix: String? {
        BangSuggestionHelper.suggestionSuffix(for: text)
    }

    public init(
        text: Binding<String>,
        placeholder: String = "Type a command or search...",
        onSubmit: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.accent)

            ZStack(alignment: .leading) {
                if let suffix = ghostSuffix {
                    HStack(spacing: 0) {
                        Text(text)
                            .font(Theme.fontSearchInput)
                            .foregroundColor(.clear)
                        Text(suffix)
                            .font(Theme.fontSearchPlaceholder)
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                }

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.fontSearchInput)
                    .foregroundColor(Theme.textPrimary)
                    .onSubmit {
                        onSubmit()
                    }
            }

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
