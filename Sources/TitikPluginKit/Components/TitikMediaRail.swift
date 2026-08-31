import SwiftUI
import AppKit
import TitikUI

public struct TitikMediaRail: View {
    public let assets: [MediaAsset]
    @Binding public var selectedIndex: Int
    public let isFocused: Bool
    public let onSelect: ((Int) -> Void)?

    @State private var zoomedAsset: MediaAsset? = nil

    public init(
        assets: [MediaAsset],
        selectedIndex: Binding<Int>,
        isFocused: Bool = false,
        onSelect: ((Int) -> Void)? = nil
    ) {
        self.assets = Array(assets.prefix(8)) // Flood protection: clamped to max 8 items
        self._selectedIndex = selectedIndex
        self.isFocused = isFocused
        self.onSelect = onSelect
    }

    public var body: some View {
        if assets.isEmpty {
            EmptyView()
        } else if assets.count == 1, let asset = assets.first {
            // Single card mode without scroll indicators
            singleCardView(asset: asset)
                .sheet(item: $zoomedAsset) { item in
                    mediaZoomModal(asset: item)
                }
        } else {
            // Carousel mode
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<assets.count, id: \.self) { idx in
                            let asset = assets[idx]
                            mediaCard(asset: asset, isSelected: idx == selectedIndex)
                                .id(idx)
                                .onTapGesture {
                                    selectedIndex = idx
                                    onSelect?(idx)
                                    zoomedAsset = asset
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .sheet(item: $zoomedAsset) { item in
                mediaZoomModal(asset: item)
            }
        }
    }

    @ViewBuilder
    private func singleCardView(asset: MediaAsset) -> some View {
        mediaCard(asset: asset, isSelected: isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                onSelect?(0)
                zoomedAsset = asset
            }
    }

    @ViewBuilder
    private func mediaCard(asset: MediaAsset, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                switch asset.type {
                case .image:
                    if let urlStr = asset.urlString, let url = URLSanitizer.sanitize(urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .scaleEffect(0.6)
                            case .success(let img):
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                fallbackIcon(systemName: "photo.badge.exclamationmark", label: "Image unavailable")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        fallbackIcon(systemName: "photo.badge.exclamationmark", label: "Invalid URL")
                    }

                case .diagram:
                    fallbackIcon(systemName: "flowchart", label: asset.title)

                case .map:
                    fallbackIcon(systemName: "map", label: asset.title)

                case .codeSnippet:
                    fallbackIcon(systemName: "chevron.left.forwardslash.chevron.right", label: asset.language ?? "Code")
                }
            }
            .frame(width: 140, height: 90)
            .clipped()
            .cornerRadius(8)

            Text(asset.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(isSelected ? 1.0 : 0.7))
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected && isFocused ? Color.blue.opacity(0.2) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected && isFocused ? Color.blue : Color.white.opacity(0.1), lineWidth: isSelected && isFocused ? 2 : 1)
                )
        )
    }

    @ViewBuilder
    private func fallbackIcon(systemName: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundColor(Color.white.opacity(0.5))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(6)
    }

    @ViewBuilder
    private func mediaZoomModal(asset: MediaAsset) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(asset.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Close") {
                    zoomedAsset = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            if asset.type == .image, let urlStr = asset.urlString, let url = URLSanitizer.sanitize(urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if phase.error != nil {
                        Text("Failed to load full-size image")
                            .foregroundColor(.red)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 600, maxHeight: 400)
            } else if let content = asset.content {
                ScrollView {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                }
                .frame(maxWidth: 600, maxHeight: 400)
            }

            if let alt = asset.altText {
                Text(alt)
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}
