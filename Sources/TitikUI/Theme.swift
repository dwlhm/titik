import SwiftUI
import AppKit
import TitikCore

public enum Theme {
    // MARK: - SF Trio Typography Tokens
    public static let fontSearchInput = Font.system(size: 18, weight: .medium, design: .default)
    public static let fontSearchPlaceholder = Font.system(size: 18, weight: .regular, design: .default)
    public static let fontRowTitle = Font.system(size: 13.5, weight: .medium, design: .default)
    public static let fontRowSubtitle = Font.system(size: 11, weight: .regular, design: .default)
    public static let fontBadge = Font.system(size: 9.5, weight: .bold, design: .rounded)
    public static let fontKeycap = Font.system(size: 10, weight: .semibold, design: .rounded)
    public static let fontFooterLabel = Font.system(size: 11, weight: .regular, design: .default)
    public static let fontBrand = Font.system(size: 11, weight: .bold, design: .rounded)
    public static let fontPreviewTitle = Font.system(size: 15, weight: .semibold, design: .default)
    public static let fontPreviewSubtitle = Font.system(size: 11, weight: .medium, design: .default)
    public static let fontPreviewBody = Font.system(size: 12, weight: .regular, design: .default)
    public static let fontCode = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let fontMathResult = Font.system(size: 22, weight: .semibold, design: .rounded)
    public static let fontToast = Font.system(size: 13, weight: .medium, design: .rounded)

    // MARK: - Pastel Category Badge Colors
    public static let categoryApp = Color(red: 147/255.0, green: 197/255.0, blue: 253/255.0)       // #93c5fd (pastel blue)
    public static let categoryCommand = Color(red: 252/255.0, green: 211/255.0, blue: 77/255.0)    // #fcd34d (pastel yellow)
    public static let categoryClipboard = Color(red: 134/255.0, green: 239/255.0, blue: 172/255.0) // #86efac (pastel green)
    public static let categoryMath = Color(red: 216/255.0, green: 180/255.0, blue: 254/255.0)      // #d8b4fe (pastel purple)
    public static let categoryPlugin = Color(red: 103/255.0, green: 232/255.0, blue: 249/255.0)    // #67e8f9 (pastel cyan)
    public static let categoryCustom = Color(red: 244/255.0, green: 114/255.0, blue: 182/255.0)    // #f472b6 (pastel pink)
    public static let categoryFile = Color(red: 251/255.0, green: 146/255.0, blue: 60/255.0)       // #fb923c (pastel orange)
    public static let categoryDirectory = Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)  // #2dd4bf (pastel teal)
    public static let categoryEmoji = Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0)       // #fbbf24 (pastel amber/gold)

    // MARK: - Liquid Glass Substrate & Specular Tokens
    public static let glassSurfaceGradient = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.06), location: 0),
            .init(color: Color(red: 16/255.0, green: 18/255.0, blue: 32/255.0, opacity: 0.16), location: 0.35),
            .init(color: Color(red: 10/255.0, green: 12/255.0, blue: 22/255.0, opacity: 0.22), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    public static let glassSpecularGlare = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.14), location: 0),
            .init(color: Color.white.opacity(0.02), location: 0.25),
            .init(color: Color.clear, location: 0.55)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    public static let borderGlassGradient = LinearGradient(
        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let borderGlassBevel = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03), Color.black.opacity(0.15)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Legacy/convenience materials
    public static let bgGlass = Color(red: 14/255.0, green: 16/255.0, blue: 26/255.0, opacity: 0.14)
    public static let borderGlass = Color.white.opacity(0.15)
    public static let bgSolidFallback = Color(red: 20/255.0, green: 22/255.0, blue: 38/255.0)
    public static let innerSheenGradient = LinearGradient(
        colors: [Color.white.opacity(0.06), Color.white.opacity(0.01), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Text & Interaction Tokens
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 203/255.0, green: 213/255.0, blue: 225/255.0)   // #cbd5e1
    public static let textMuted = Color(red: 148/255.0, green: 163/255.0, blue: 184/255.0)       // #94a3b8
    public static let accent = Color(red: 165/255.0, green: 180/255.0, blue: 252/255.0)          // #a5b4fc
    public static let selectionBg = Color(red: 165/255.0, green: 180/255.0, blue: 252/255.0, opacity: 0.18)
    public static let cardBg = Color.white.opacity(0.06)

    // MARK: - Motion & Physics Tokens
    public static let springPresentation = Animation.spring(response: 0.28, dampingFraction: 0.82)
    public static let springInteractive = Animation.spring(response: 0.25, dampingFraction: 0.85)
    public static let springSnappy = Animation.spring(response: 0.20, dampingFraction: 0.88)

    // MARK: - Feasibility
    public static func isLiquidGlassFeasible(alpha: Double = 0.14) -> Bool {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return !reduceTransparency && alpha < 0.80
    }

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
            Group {
                if Theme.isLiquidGlassFeasible() {
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    ZStack {
                        VisualEffectView(material: .popover, blendingMode: .behindWindow)
                        Theme.glassSurfaceGradient
                        Theme.glassSpecularGlare
                    }
                    .clipShape(shape)
                    .overlay(
                        shape
                            .stroke(Theme.borderGlassBevel, lineWidth: 0.5)
                    )
                    .overlay(
                        shape
                            .stroke(Theme.borderGlassGradient, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 16)
                } else {
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    Theme.bgSolidFallback
                        .clipShape(shape)
                        .overlay(
                            shape
                                .stroke(Theme.borderGlass, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                }
            }
        )
    }
}
