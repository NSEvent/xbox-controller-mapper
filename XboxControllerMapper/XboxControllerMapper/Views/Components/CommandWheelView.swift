import SwiftUI

/// A GTA-style radial command wheel for quick app switching
struct CommandWheelView: View {
    @ObservedObject var manager: CommandWheelManager

    private let wheelSize: CGFloat = 280
    private let innerRadius: CGFloat = 50
    private let iconSize: CGFloat = 32

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 5)

            // Segments
            ForEach(Array(manager.appBarItems.enumerated()), id: \.element.id) { index, item in
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
        .frame(width: 300, height: 300)
    }

    private func segmentView(index: Int, item: AppBarItem) -> some View {
        let count = manager.appBarItems.count
        let segmentAngle = 360.0 / Double(count)
        // Start from top (270°), go clockwise
        let startAngle = 270.0 + segmentAngle * Double(index)
        let midAngle = startAngle + segmentAngle / 2
        let isSelected = manager.selectedIndex == index

        // Position icon along the midpoint angle, between inner and outer radius
        let iconRadius = (wheelSize / 2 + innerRadius) / 2
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

            // App icon and label
            VStack(spacing: 2) {
                appIcon(for: item.bundleIdentifier)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .cornerRadius(7)

                Text(item.displayName)
                    .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
            .offset(x: iconX, y: iconY)
        }
    }

    private func appIcon(for bundleIdentifier: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
            return Image(nsImage: icon)
        }
        return Image(systemName: "app.fill")
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
        .frame(width: 300, height: 300)
        .background(.black)
}
