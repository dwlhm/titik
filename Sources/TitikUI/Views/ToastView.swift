import SwiftUI
import AppKit

public struct ToastView: View {
    public let toast: ToastMessage
    public var onDismiss: (() -> Void)?

    public init(toast: ToastMessage, onDismiss: (() -> Void)? = nil) {
        self.toast = toast
        self.onDismiss = onDismiss
    }

    private var iconName: String {
        if let customIcon = toast.icon {
            return customIcon
        }
        switch toast.type {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.type {
        case .info:
            return Theme.accent
        case .success:
            return Theme.categoryClipboard
        case .warning:
            return Theme.categoryCommand
        case .error:
            return Theme.categoryCustom
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)

            Text(toast.message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Theme.bgGlass
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.borderGlass, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .contentShape(Capsule())
        .onTapGesture {
            if let onDismiss = onDismiss {
                onDismiss()
            } else {
                ToastManager.shared.dismiss()
            }
        }
    }
}
