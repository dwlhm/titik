import SwiftUI
import AppKit
import TitikUI

public struct TitikCitationTray: View {
    public let citations: [CitationSource]
    @Binding public var selectedIndex: Int
    public let isFocused: Bool
    public let onSelect: ((CitationSource) -> Void)?

    @State private var hoveredId: String? = nil

    public init(
        citations: [CitationSource],
        selectedIndex: Binding<Int>,
        isFocused: Bool = false,
        onSelect: ((CitationSource) -> Void)? = nil
    ) {
        // Deduplicate citations by urlString
        var unique: [CitationSource] = []
        var seenUrls: Set<String> = []
        for cite in citations {
            if !seenUrls.contains(cite.urlString) {
                seenUrls.insert(cite.urlString)
                unique.append(cite)
            }
        }
        self.citations = unique
        self._selectedIndex = selectedIndex
        self.isFocused = isFocused
        self.onSelect = onSelect
    }

    public var body: some View {
        if citations.isEmpty {
            EmptyView()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<citations.count, id: \.self) { idx in
                            let cite = citations[idx]
                            citationChip(cite: cite, index: idx, isSelected: idx == selectedIndex)
                                .id(idx)
                                .onTapGesture {
                                    selectedIndex = idx
                                    openCitation(cite)
                                }
                                .onHover { hovering in
                                    hoveredId = hovering ? cite.id : nil
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func citationChip(cite: CitationSource, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            // Option+Index badge
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.15)))

            if let favStr = cite.faviconURLString, let favURL = URLSanitizer.sanitize(favStr) {
                AsyncImage(url: favURL) { phase in
                    if let img = phase.image {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(cite.title.isEmpty ? cite.domain : cite.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(isSelected ? 1.0 : 0.85))
                    .lineLimit(1)

                if !cite.domain.isEmpty {
                    Text(cite.domain)
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected && isFocused ? Color.blue.opacity(0.3) : Color.white.opacity(hoveredId == cite.id ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected && isFocused ? Color.blue : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .help(cite.snippet ?? cite.urlString)
    }

    private func openCitation(_ cite: CitationSource) {
        if let onSelect = onSelect {
            onSelect(cite)
        } else if let url = URLSanitizer.sanitize(cite.urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
