import SwiftUI

/// A GTA-style radial command wheel for quick app/website switching
struct CommandWheelView: View {
    @ObservedObject var manager: CommandWheelManager

    private let wheelSize: CGFloat = 800
    private let innerRadius: CGFloat = 140
    private let iconSize: CGFloat = 48

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 5)

            // Segments
            ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                segmentView(index: index, item: item)
            }

            // Center indicator
            Circle()
                .fill(manager.selectedIndex == nil ? Color.white.opacity(0.15) : Color.clear)
                .frame(width: innerRadius * 2, height: innerRadius * 2)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .frame(width: 820, height: 820)
    }

    private func segmentView(index: Int, item: CommandWheelItem) -> some View {
        let count = manager.items.count
        let segmentAngle = 360.0 / Double(count)
        // Start from top (270°), go clockwise
        let startAngle = 270.0 + segmentAngle * Double(index)
        let midAngle = startAngle + segmentAngle / 2
        let isSelected = manager.selectedIndex == index

        // Position icon based on item count: centered for few, outer edge for many
        let positionFactor: CGFloat = count <= 8 ? 0.5 : (count <= 12 ? 0.65 : 0.8)
        let iconRadius = innerRadius + (wheelSize / 2 - innerRadius) * positionFactor
        let midAngleRad = midAngle * .pi / 180
        let iconX = cos(midAngleRad) * iconRadius
        let iconY = sin(midAngleRad) * iconRadius

        return ZStack {
            // Segment shape
            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: innerRadius,
                outerRadius: wheelSize / 2
            )
            .fill(isSelected ? Color.accentColor.opacity(0.6) : Color.clear)

            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: innerRadius,
                outerRadius: wheelSize / 2
            )
            .stroke(Color.white.opacity(0.2), lineWidth: 1)

            // Icon and label
            VStack(spacing: 2) {
                itemIcon(for: item)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .cornerRadius(10)

                Text(item.displayName)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 100)
            }
            .offset(x: iconX, y: iconY)
        }
    }

    private func itemIcon(for item: CommandWheelItem) -> Image {
        switch item.kind {
        case .app(let bundleIdentifier):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
               let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                return Image(nsImage: icon)
            }
            return Image(systemName: "app.fill")
        case .website(_, let faviconData):
            if let data = faviconData, let nsImage = NSImage(data: data) {
                return Image(nsImage: nsImage)
            }
            return Image(systemName: "globe")
        }
    }
}

/// A donut segment shape
struct SegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        // Outer arc
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        // Line to inner arc
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()

        return path
    }
}

#Preview {
    let manager = CommandWheelManager.shared
    CommandWheelView(manager: manager)
        .frame(width: 820, height: 820)
        .background(.black)
}
