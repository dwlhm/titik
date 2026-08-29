import SwiftUI
import TitikCore

public struct ResultsListView: View {
    public let items: [SearchItem]
    @Binding public var selectedIndex: Int
    public var boundaryBounceOffset: CGFloat = 0
    public var onSelect: (SearchItem) -> Void

    public init(
        items: [SearchItem],
        selectedIndex: Binding<Int>,
        boundaryBounceOffset: CGFloat = 0,
        onSelect: @escaping (SearchItem) -> Void = { _ in }
    ) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.boundaryBounceOffset = boundaryBounceOffset
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ResultItemRow(item: item, isSelected: index == selectedIndex)
                            .id(item.id)
                            .transaction { $0.animation = nil }
                            .onTapGesture {
                                selectedIndex = index
                                onSelect(item)
                            }
                    }
                }
                .padding(.vertical, 4)
                .offset(y: boundaryBounceOffset)
            }
            .onChange(of: selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < items.count {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(items[newIndex].id, anchor: nil)
                    }
                }
            }
            .onChange(of: items.map(\.id)) { _ in
                if selectedIndex == 0, let first = items.first {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }
}
