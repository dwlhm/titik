import SwiftUI
import AppKit
import TitikUI

public struct TitikGlassCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let padding: CGFloat
    public let content: () -> Content

    public init(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            )
    }
}

public struct TitikSkeletonView: View {
    @State private var phase: CGFloat = 0
    public let height: CGFloat
    public let cornerRadius: CGFloat

    public init(height: CGFloat = 16, cornerRadius: CGFloat = 6) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.05), location: max(0, phase - 0.3)),
                        .init(color: Color.white.opacity(0.15), location: phase),
                        .init(color: Color.white.opacity(0.05), location: min(1, phase + 0.3))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}
