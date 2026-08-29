import SwiftUI
import AppKit
import TitikCore

public enum Theme {
    // Pastel Category Badge Colors
    public static let categoryApp = Color(red: 147/255.0, green: 197/255.0, blue: 253/255.0)       // #93c5fd (pastel blue)
    public static let categoryCommand = Color(red: 252/255.0, green: 211/255.0, blue: 77/255.0)    // #fcd34d (pastel yellow)
    public static let categoryClipboard = Color(red: 134/255.0, green: 239/255.0, blue: 172/255.0) // #86efac (pastel green)
    public static let categoryMath = Color(red: 216/255.0, green: 180/255.0, blue: 254/255.0)      // #d8b4fe (pastel purple)
    public static let categoryPlugin = Color(red: 103/255.0, green: 232/255.0, blue: 249/255.0)    // #67e8f9 (pastel cyan)
    public static let categoryCustom = Color(red: 244/255.0, green: 114/255.0, blue: 182/255.0)    // #f472b6 (pastel pink)
    public static let categoryFile = Color(red: 251/255.0, green: 146/255.0, blue: 60/255.0)       // #fb923c (pastel orange)
    public static let categoryDirectory = Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)  // #2dd4bf (pastel teal)
    public static let categoryEmoji = Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0)       // #fbbf24 (pastel amber/gold)

    // Dark Liquid Glass HUD Colors
    public static let bgGlass = Color(red: 20/255.0, green: 22/255.0, blue: 40/255.0, opacity: 0.85)
    public static let borderGlass = Color.white.opacity(0.12)
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 203/255.0, green: 213/255.0, blue: 225/255.0)   // #cbd5e1
    public static let textMuted = Color(red: 148/255.0, green: 163/255.0, blue: 184/255.0)       // #94a3b8
    public static let accent = Color(red: 165/255.0, green: 180/255.0, blue: 252/255.0)          // #a5b4fc
    public static let selectionBg = Color(red: 165/255.0, green: 180/255.0, blue: 252/255.0, opacity: 0.18)
    public static let cardBg = Color.white.opacity(0.06)

    public static func colorForCategory(_ category: SearchCategory) -> Color {
        switch category {
        case .application: return categoryApp
        case .systemCommand: return categoryCommand
        case .clipboard: return categoryClipboard
        case .calculator: return categoryMath
        case .plugin: return categoryPlugin
        case .custom: return categoryCustom
        case .file: return categoryFile
        case .directory: return categoryDirectory
        case .emoji: return categoryEmoji
        }
    }

    public static func colorFromHex(_ hex: String) -> Color {
        guard let rgba = RGBAColor.parseHex(hex) else {
            return .white
        }
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

public extension View {
    func hudGlassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Theme.bgGlass
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.borderGlass, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
    }
}
