import SwiftUI

struct FlowLayout<Data: RandomAccessCollection, ItemContent: View>: View where Data.Element: Identifiable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> ItemContent

    @State private var containerWidth: CGFloat = 0
    @State private var sizes: [Data.Element.ID: CGSize] = [:]

    var body: some View {
        GeometryReader { geo in
            let _ = updateContainerWidth(geo.size.width)
            let layout = computeLayout()

            ZStack(alignment: .topLeading) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .fixedSize()
                        .background(
                            GeometryReader { itemGeo in
                                Color.clear.preference(
                                    key: FlowItemSizeKey<Data.Element.ID>.self,
                                    value: [item.id: itemGeo.size]
                                )
                            }
                        )
                        .offset(x: layout.positions[index].x, y: layout.positions[index].y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onPreferenceChange(FlowItemSizeKey<Data.Element.ID>.self) { newSizes in
                if newSizes != sizes {
                    sizes = newSizes
                }
            }
        }
        .frame(height: computeLayout().totalHeight)
    }

    private func updateContainerWidth(_ width: CGFloat) {
        if containerWidth != width {
            DispatchQueue.main.async {
                containerWidth = width
            }
        }
    }

    private func computeLayout() -> (positions: [CGPoint], totalHeight: CGFloat) {
        guard containerWidth > 0 else {
            return (Array(repeating: .zero, count: data.count), 0)
        }

        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for item in data {
            let size = sizes[item.id] ?? CGSize(width: 100, height: 30)

            // Wrap to next line if this item doesn't fit
            if x + size.width > containerWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        // Total height is the bottom of the last row
        let totalHeight = y + rowHeight

        return (positions, totalHeight > 0 ? totalHeight : 30)
    }
}

private struct FlowItemSizeKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGSize] { [:] }
    static func reduce(value: inout [ID: CGSize], nextValue: () -> [ID: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}
