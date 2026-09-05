import SwiftUI
import AppKit
import TitikCore
import TitikKeymap

public struct ScrollTargetRequest: Equatable, Sendable {
    public let id: String
    public let anchor: UnitPoint
    public let isAnimated: Bool
    public let token: UUID

    public init(id: String, anchor: UnitPoint = .top, isAnimated: Bool = false, token: UUID = UUID()) {
        self.id = id
        self.anchor = anchor
        self.isAnimated = isAnimated
        self.token = token
    }
}

@MainActor
public final class EmojiPlugin: ObservableObject, PluginUIRepresentable {
    public static let shared = EmojiPlugin()

    public static let navigableCategories: [EmojiCategory] = [
        .smileys,
        .people,
        .animals,
        .food,
        .travel,
        .activities,
        .objects,
        .symbols,
        .flags
    ]

    public let pluginId: String = "emoji"

    @Published public var selectedCategory: EmojiCategory = .smileys
    @Published public var searchQuery: String = ""
    @Published public var selectedIndex: Int = 0
    @Published public var items: [EmojiItem] = []
    @Published public var pendingScrollTarget: ScrollTargetRequest? = nil

    public var onSelectEmoji: (@MainActor (EmojiItem) -> Void)?

    public var customView: AnyView {
        AnyView(EmojiGridView(plugin: self))
    }

    public var footerKeycaps: [KeycapAction]? {
        [
            KeycapAction(shortcut: "↵", label: "Paste"),
            KeycapAction(shortcut: "⇥", label: "Category"),
            KeycapAction(shortcut: "←↑↓→", label: "Select"),
            KeycapAction(shortcut: "esc", label: "Close")
        ]
    }

    public init() {
        updateItems()
    }

    public func updateItems() {
        if searchQuery.isEmpty {
            self.items = EmojiCatalog.shared.allEmojis
        } else {
            self.items = EmojiCatalog.shared.search(query: searchQuery)
        }
        if selectedIndex >= items.count {
            self.selectedIndex = max(0, items.count - 1)
        }
        if let emoji = selectedEmoji {
            self.selectedCategory = emoji.category
        }
    }

    public func handleSearchQuery(_ query: String) {
        self.searchQuery = query
        updateItems()
    }

    public func scrollTo(targetId: String, anchor: UnitPoint = .top) {
        self.pendingScrollTarget = ScrollTargetRequest(id: targetId, anchor: anchor, isAnimated: true)
    }

    public func scrollToCategoryHeader(_ category: EmojiCategory) {
        if let idx = items.firstIndex(where: { $0.category == category }) {
            self.selectedIndex = idx
        }
        self.selectedCategory = category
        self.pendingScrollTarget = ScrollTargetRequest(id: "header_\(category.rawValue)", anchor: .top, isAnimated: true)
    }

    public func selectCategory(_ category: EmojiCategory) {
        scrollToCategoryHeader(category)
    }

    public func nextCategory() {
        let nav = Self.navigableCategories
        if let idx = nav.firstIndex(of: selectedCategory) {
            let nextIdx = (idx + 1) % nav.count
            scrollToCategoryHeader(nav[nextIdx])
        } else if let first = nav.first {
            scrollToCategoryHeader(first)
        }
    }

    public func previousCategory() {
        let nav = Self.navigableCategories
        if let idx = nav.firstIndex(of: selectedCategory) {
            let prevIdx = (idx - 1 + nav.count) % nav.count
            scrollToCategoryHeader(nav[prevIdx])
        } else if let last = nav.last {
            scrollToCategoryHeader(last)
        }
    }

    public func moveSelection(deltaX: Int, deltaY: Int, columns: Int = 8) {
        guard !items.isEmpty else { return }
        var nextIndex = selectedIndex + deltaX + (deltaY * columns)
        if nextIndex < 0 {
            nextIndex = 0
        } else if nextIndex >= items.count {
            nextIndex = items.count - 1
        }
        selectedIndex = nextIndex
        if let emoji = selectedEmoji {
            self.selectedCategory = emoji.category
        }
        pendingScrollTarget = ScrollTargetRequest(id: items[selectedIndex].id, anchor: .center, isAnimated: false)
    }

    public var selectedEmoji: EmojiItem? {
        guard !items.isEmpty, selectedIndex >= 0, selectedIndex < items.count else {
            return nil
        }
        return items[selectedIndex]
    }

    public func executeSelected() {
        guard let item = selectedEmoji else { return }
        if let onSelect = onSelectEmoji {
            onSelect(item)
        } else {
            ClipboardManager.shared.copyToPasteboard(item.emoji)
        }
    }

    public func submitQuery() {
        executeSelected()
    }

    public func handleAction(actionId: String, payload: String) -> Bool {
        if actionId == "select", let item = items.first(where: { $0.emoji == payload }) {
            if let onSelect = onSelectEmoji {
                onSelect(item)
            } else {
                ClipboardManager.shared.copyToPasteboard(item.emoji)
            }
            return true
        }
        return false
    }
}

public struct EmojiGridView: View {
    @ObservedObject public var plugin: EmojiPlugin

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    public init(plugin: EmojiPlugin) {
        self.plugin = plugin
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Category Tabs
            ScrollViewReader { tabProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EmojiPlugin.navigableCategories, id: \.self) { category in
                            let isSelected = plugin.selectedCategory == category
                            Button {
                                plugin.selectCategory(category)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 11))
                                    Text(category.rawValue)
                                        .font(Theme.fontFooterLabel)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? Theme.categoryEmoji.opacity(0.25) : Color.white.opacity(0.05)
                                )
                                .foregroundColor(isSelected ? Theme.categoryEmoji : Theme.textSecondary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Theme.categoryEmoji.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(category)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 32)
                .onChange(of: plugin.selectedCategory) { newCat in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tabProxy.scrollTo(newCat, anchor: .center)
                    }
                }
                .onAppear {
                    tabProxy.scrollTo(plugin.selectedCategory, anchor: .center)
                }
            }

            // Grid View / Empty State
            if plugin.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "face.dashed")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.textMuted.opacity(0.5))
                    Text("No emojis found")
                        .font(Theme.fontPreviewTitle)
                        .foregroundColor(Theme.textSecondary)
                    if !plugin.searchQuery.isEmpty {
                        Text("No match for \"\(plugin.searchQuery)\"")
                            .font(Theme.fontPreviewBody)
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if plugin.searchQuery.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(EmojiPlugin.navigableCategories, id: \.self) { category in
                                    let categoryEntries = plugin.items.enumerated().filter { $0.element.category == category }
                                    if !categoryEntries.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Image(systemName: category.iconName)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(Theme.categoryEmoji)
                                                Text(category.rawValue)
                                                    .font(Theme.fontPreviewSubtitle)
                                                    .foregroundColor(Theme.textSecondary)
                                                Text("(\(categoryEntries.count))")
                                                    .font(Theme.fontFooterLabel)
                                                    .foregroundColor(Theme.textMuted)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)
                                            .id("header_\(category.rawValue)")

                                            LazyVGrid(columns: columns, spacing: 8) {
                                                ForEach(categoryEntries, id: \.element.id) { globalIndex, item in
                                                    let isSelected = plugin.selectedIndex == globalIndex
                                                    EmojiCell(
                                                        item: item,
                                                        isSelected: isSelected,
                                                        onTap: {
                                                            plugin.selectedIndex = globalIndex
                                                            plugin.executeSelected()
                                                        }
                                                    )
                                                    .id(item.id)
                                                }
                                            }
                                            .padding(.horizontal, 6)
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.categoryEmoji)
                                    Text("Search Results")
                                        .font(Theme.fontPreviewSubtitle)
                                        .foregroundColor(Theme.textSecondary)
                                    Text("(\(plugin.items.count))")
                                        .font(Theme.fontFooterLabel)
                                        .foregroundColor(Theme.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(Array(plugin.items.enumerated()), id: \.element.id) { index, item in
                                        let isSelected = plugin.selectedIndex == index
                                        EmojiCell(
                                            item: item,
                                            isSelected: isSelected,
                                            onTap: {
                                                plugin.selectedIndex = index
                                                plugin.executeSelected()
                                            }
                                        )
                                        .id(item.id)
                                    }
                                }
                                .padding(.horizontal, 6)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .onChange(of: plugin.pendingScrollTarget) { request in
                        guard let request = request else { return }
                        if request.isAnimated {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(request.id, anchor: request.anchor)
                            }
                        } else {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo(request.id, anchor: request.anchor)
                            }
                        }
                    }
                }
            }

            // Bottom Inspector Bar
            if let emoji = plugin.selectedEmoji {
                HStack(spacing: 12) {
                    // Large glyph
                    Text(emoji.emoji)
                        .font(.system(size: 32))
                        .frame(width: 44, height: 44)
                        .background(Theme.categoryEmoji.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.categoryEmoji.opacity(0.4), lineWidth: 1)
                        )

                    // Meta details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(emoji.name)
                            .font(Theme.fontPreviewTitle)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(emoji.shortcode)
                                .font(Theme.fontCode)
                                .foregroundColor(Theme.categoryEmoji)

                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)

                            Text(emoji.category.rawValue)
                                .font(Theme.fontFooterLabel)
                                .foregroundColor(Theme.textMuted)

                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)

                            Text(emoji.unicodeHex)
                                .font(Theme.fontCode)
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    Spacer()

                    KeycapView(shortcut: "↵", label: "Paste")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.borderGlass, lineWidth: 1)
                )
            }
        }
        .padding(.top, 4)
    }
}

private struct EmojiCell: View {
    let item: EmojiItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onTap()
        } label: {
            Text(item.emoji)
                .font(.system(size: 24))
                .frame(width: 48, height: 48)
                .background(
                    isSelected
                        ? Theme.categoryEmoji.opacity(0.28)
                        : (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.04))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? Theme.categoryEmoji.opacity(0.85)
                                : (isHovered ? Color.white.opacity(0.2) : Color.clear),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .scaleEffect(isSelected ? 1.08 : (isHovered ? 1.03 : 1.0))
                .animation(Theme.springSnappy, value: isSelected)
                .animation(Theme.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
