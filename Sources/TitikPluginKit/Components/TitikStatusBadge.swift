import SwiftUI
import AppKit
import TitikUI

public struct TitikStatusBadge: View {
    public enum StatusStyle: Sendable {
        case connected
        case offline
        case testing
        case idle
        case custom(Color)

        public var color: Color {
            switch self {
            case .connected: return .green
            case .offline: return .red
            case .testing: return .yellow
            case .idle: return .gray
            case .custom(let col): return col
            }
        }

        public var iconName: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .offline: return "exclamationmark.triangle.fill"
            case .testing: return "arrow.triangle.2.circlepath"
            case .idle: return "circle"
            case .custom: return "circle.fill"
            }
        }
    }

    public let text: String
    public let style: StatusStyle
    public let isTesting: Bool

    public init(
        text: String,
        style: StatusStyle = .connected,
        isTesting: Bool = false
    ) {
        self.text = text
        self.style = style
        self.isTesting = isTesting
    }

    public init(statusMessage: String) {
        self.text = statusMessage
        if statusMessage.contains("🟢") || statusMessage.lowercased().contains("connected") || statusMessage.lowercased().contains("ready") {
            self.style = .connected
            self.isTesting = false
        } else if statusMessage.contains("🔴") || statusMessage.lowercased().contains("offline") || statusMessage.lowercased().contains("error") || statusMessage.lowercased().contains("failed") {
            self.style = .offline
            self.isTesting = false
        } else if statusMessage.contains("🟡") || statusMessage.lowercased().contains("testing") || statusMessage.lowercased().contains("connecting") {
            self.style = .testing
            self.isTesting = true
        } else {
            self.style = .idle
            self.isTesting = false
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            if isTesting {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(style.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: style.color.opacity(0.6), radius: 3, x: 0, y: 0)
            }

            Text(cleanText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(style.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(style.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(style.color.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var cleanText: String {
        var str = text
        str = str.replacingOccurrences(of: "🟢", with: "")
        str = str.replacingOccurrences(of: "🔴", with: "")
        str = str.replacingOccurrences(of: "🟡", with: "")
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
