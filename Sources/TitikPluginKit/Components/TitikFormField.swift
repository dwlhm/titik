import SwiftUI
import AppKit
import TitikUI

public struct TitikFormField: View {
    public let label: String?
    public let placeholder: String
    @Binding public var text: String
    public let isSecure: Bool
    public let isMonospaced: Bool
    public let helperLinkLabel: String?
    public let helperLinkURL: URL?
    public let onHelperLinkClick: (() -> Void)?

    @State private var isPasswordVisible: Bool = false
    @FocusState private var isFocused: Bool

    public init(
        label: String? = nil,
        placeholder: String = "",
        text: Binding<String>,
        isSecure: Bool = false,
        isMonospaced: Bool = false,
        helperLinkLabel: String? = nil,
        helperLinkURL: URL? = nil,
        onHelperLinkClick: (() -> Void)? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.isMonospaced = isMonospaced
        self.helperLinkLabel = helperLinkLabel
        self.helperLinkURL = helperLinkURL
        self.onHelperLinkClick = onHelperLinkClick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if label != nil || helperLinkLabel != nil {
                HStack {
                    if let label = label {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.8))
                    }

                    Spacer()

                    if let helperLabel = helperLinkLabel {
                        Button(action: {
                            if let onHelperLinkClick = onHelperLinkClick {
                                onHelperLinkClick()
                            } else if let helperLinkURL = helperLinkURL {
                                NSWorkspace.shared.open(helperLinkURL)
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text(helperLabel)
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.blue.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 6) {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                        .foregroundColor(.white)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                        .foregroundColor(.white)
                        .focused($isFocused)
                }

                if isSecure {
                    Button(action: {
                        isPasswordVisible.toggle()
                    }) {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help(isPasswordVisible ? "Hide secret" : "Show secret")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? Color.blue.opacity(0.75) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

public struct TitikSecureField: View {
    public let label: String?
    public let placeholder: String
    @Binding public var text: String
    public let isMonospaced: Bool
    public let helperLinkLabel: String?
    public let helperLinkURL: URL?
    public let onHelperLinkClick: (() -> Void)?

    public init(
        label: String? = nil,
        placeholder: String = "",
        text: Binding<String>,
        isMonospaced: Bool = true,
        helperLinkLabel: String? = nil,
        helperLinkURL: URL? = nil,
        onHelperLinkClick: (() -> Void)? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.isMonospaced = isMonospaced
        self.helperLinkLabel = helperLinkLabel
        self.helperLinkURL = helperLinkURL
        self.onHelperLinkClick = onHelperLinkClick
    }

    public var body: some View {
        TitikFormField(
            label: label,
            placeholder: placeholder,
            text: $text,
            isSecure: true,
            isMonospaced: isMonospaced,
            helperLinkLabel: helperLinkLabel,
            helperLinkURL: helperLinkURL,
            onHelperLinkClick: onHelperLinkClick
        )
    }
}
