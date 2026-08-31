import SwiftUI
import AppKit
import TitikUI

public struct TitikFollowUpBar: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let isFocused: Bool
    public let placeholder: String
    public let onSubmit: (String) -> Void

    public init(
        text: Binding<String>,
        isStreaming: Bool = false,
        isFocused: Bool = false,
        placeholder: String = "Ask follow-up question...",
        onSubmit: @escaping (String) -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.isFocused = isFocused
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.right")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.5))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .onSubmit {
                    submit()
                }

            if isStreaming {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.25) : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? Color.blue.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty && !isStreaming else { return }
        onSubmit(query)
        text = ""
    }
}
