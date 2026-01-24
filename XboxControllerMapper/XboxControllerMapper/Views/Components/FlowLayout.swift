import SwiftUI

struct FlowLayout<Data: RandomAccessCollection, ItemContent: View>: View where Data.Element: Identifiable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> ItemContent

    @State private var containerWidth: CGFloat = 0
    @State private var sizes: [Int: CGSize] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 0)
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { containerWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in containerWidth = w }
                    }
                )

            let positions = computePositions()
            let totalHeight = computeHeight(positions: positions)

            ZStack(alignment: .topLeading) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .fixedSize()
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: FlowItemSizeKey.self,
                                    value: [index: geo.size]
                                )
                            }
                        )
                        .alignmentGuide(.leading) { _ in
                            -(positions[index]?.x ?? 0)
                        }
                        .alignmentGuide(.top) { _ in
                            -(positions[index]?.y ?? 0)
                        }
                }
            }
            .frame(height: totalHeight > 0 ? totalHeight : nil, alignment: .topLeading)
            .onPreferenceChange(FlowItemSizeKey.self) { newSizes in
                if newSizes != sizes {
                    sizes = newSizes
                }
            }
        }
    }

    private func computePositions() -> [Int: CGPoint] {
        guard containerWidth > 0 else { return [:] }
        var result: [Int: CGPoint] = [:]
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, _) in data.enumerated() {
            let size = sizes[index] ?? CGSize(width: 100, height: 30)
            if x + size.width > containerWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            result[index] = CGPoint(x: x, y: y)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }

    private func computeHeight(positions: [Int: CGPoint]) -> CGFloat {
        guard !positions.isEmpty else { return 0 }
        var maxBottom: CGFloat = 0
        for (index, point) in positions {
            let size = sizes[index] ?? CGSize(width: 100, height: 30)
            maxBottom = max(maxBottom, point.y + size.height)
        }
        return maxBottom
    }
}

private struct FlowItemSizeKey: PreferenceKey {
    static var defaultValue: [Int: CGSize] = [:]
    static func reduce(value: inout [Int: CGSize], nextValue: () -> [Int: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}
