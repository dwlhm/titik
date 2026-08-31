import SwiftUI
import AppKit
import TitikUI
import TitikPluginKit

public struct AskAIContainerView: View {
    public let text: String
    public let mediaAssets: [MediaAsset]
    public let citations: [CitationSource]
    public let isStreaming: Bool
    public let rateLimitRetryAfter: TimeInterval?
    @ObservedObject public var focusCoordinator: PluginFocusCoordinator
    @State private var followUpText: String = ""
    public let onFollowUpSubmit: (String) -> Void
    public let onCitationSelect: ((CitationSource) -> Void)?
    public let onMediaSelect: ((Int) -> Void)?
    public let onOpenSetupWizard: (() -> Void)?

    public init(
        text: String,
        mediaAssets: [MediaAsset] = [],
        citations: [CitationSource] = [],
        isStreaming: Bool = false,
        rateLimitRetryAfter: TimeInterval? = nil,
        focusCoordinator: PluginFocusCoordinator,
        onFollowUpSubmit: @escaping (String) -> Void,
        onCitationSelect: ((CitationSource) -> Void)? = nil,
        onMediaSelect: ((Int) -> Void)? = nil,
        onOpenSetupWizard: (() -> Void)? = nil
    ) {
        self.text = text
        self.mediaAssets = mediaAssets
        self.citations = citations
        self.isStreaming = isStreaming
        self.rateLimitRetryAfter = rateLimitRetryAfter
        self.focusCoordinator = focusCoordinator
        self.onFollowUpSubmit = onFollowUpSubmit
        self.onCitationSelect = onCitationSelect
        self.onMediaSelect = onMediaSelect
        self.onOpenSetupWizard = onOpenSetupWizard
    }

    public var body: some View {
        TitikGlassCard(cornerRadius: 14, padding: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header bar with Model Settings button
                    HStack {
                        Spacer()
                        Button(action: {
                            onOpenSetupWizard?()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Model Settings (⌘,)")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white.opacity(0.75))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Connection or Authentication Error setup prompt
                    if text.hasPrefix("Error:") || text.contains("Unauthorized") || text.contains("API key is required") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(text)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                            }

                            Button(action: {
                                if let onOpenSetupWizard = onOpenSetupWizard {
                                    onOpenSetupWizard()
                                } else {
                                    NotificationCenter.default.post(name: .askAISelectPrompt, object: "settings")
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gearshape.fill")
                                    Text("Open Setup Wizard")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    // Rate limit notification if 429
                    if let retry = rateLimitRetryAfter, retry > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.orange)
                            Text("Rate limited. Please retry in \(Int(ceil(retry))) seconds.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                    }

                    // Media Rail (if assets present)
                    if !mediaAssets.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            TitikMediaRail(
                                assets: mediaAssets,
                                selectedIndex: $focusCoordinator.selectedMediaIndex,
                                isFocused: focusCoordinator.currentZone == .mediaRail,
                                onSelect: { idx in
                                    onMediaSelect?(idx)
                                }
                            )
                        }
                    }

                    // Main Markdown Body, Skeleton placeholder, or Ready state
                    if text.isEmpty && isStreaming {
                        VStack(alignment: .leading, spacing: 8) {
                            TitikSkeletonView(height: 16)
                            TitikSkeletonView(height: 16)
                            TitikSkeletonView(height: 16)
                        }
                        .padding(.vertical, 8)
                    } else if text.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 14))
                                Text("Ask AI is ready. Type a prompt or select a quick starter below:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .padding(.top, 4)

                            TitikChipGroup(
                                title: "💡 Quick-Start Example Prompts:",
                                chips: AskAIOnboardingView.starterPrompts,
                                onSelect: { prompt in
                                    NotificationCenter.default.post(name: .askAISelectPrompt, object: prompt)
                                }
                            )
                        }
                        .padding(.vertical, 4)
                    } else {
                        TitikMarkdownView(
                            text: text,
                            onCitationClick: { idx in
                                if idx >= 1 && idx <= citations.count {
                                    let cite = citations[idx - 1]
                                    onCitationSelect?(cite)
                                }
                            },
                            isStreaming: isStreaming
                        )
                        .padding(.vertical, 2)
                    }

                    Spacer(minLength: 0)

                    // Citations Tray (if citations present)
                    if !citations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.vertical, 2)

                            TitikCitationTray(
                                citations: citations,
                                selectedIndex: $focusCoordinator.selectedCitationIndex,
                                isFocused: focusCoordinator.currentZone == .citationTray,
                                onSelect: { cite in
                                    onCitationSelect?(cite)
                                }
                            )
                        }
                    }

                    // Follow-up Bar
                    TitikFollowUpBar(
                        text: $followUpText,
                        isStreaming: isStreaming,
                        isFocused: focusCoordinator.currentZone == .followUpBar,
                        placeholder: "Ask follow-up question...",
                        onSubmit: { query in
                            onFollowUpSubmit(query)
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}
