import SwiftUI

/// A GTA-style radial command wheel for quick app/website switching
struct CommandWheelView: View {
    @ObservedObject var manager: CommandWheelManager

    private let wheelSize: CGFloat = 800
    private let innerRadius: CGFloat = 140
    private let iconSize: CGFloat = 48
    private let perimeterGap: CGFloat = 5
    private let perimeterWidth: CGFloat = 45

    private var perimeterInnerRadius: CGFloat { wheelSize / 2 + perimeterGap }
    private var perimeterOuterRadius: CGFloat { perimeterInnerRadius + perimeterWidth }
    private var totalSize: CGFloat { perimeterOuterRadius * 2 + 20 }

    var body: some View {
        ZStack {
            // Background circle for main wheel
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 5)

            // Perimeter ring background
            SegmentShape(
                startAngle: .degrees(0),
                endAngle: .degrees(360),
                innerRadius: perimeterInnerRadius,
                outerRadius: perimeterOuterRadius
            )
            .fill(Color.white.opacity(0.05))

            // Segments (main + perimeter)
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
        .frame(width: totalSize, height: totalSize)
    }

    private func segmentView(index: Int, item: CommandWheelItem) -> some View {
        let count = manager.items.count
        let segmentAngle = 360.0 / Double(count)
        // Start from top (270°), go clockwise
        let startAngle = 270.0 + segmentAngle * Double(index)
        let midAngle = startAngle + segmentAngle / 2
        let isSelected = manager.selectedIndex == index

        // Position icon based on item count: centered for few, outer edge for many
        let positionFactor: CGFloat = count <= 8 ? 0.5 : (count <= 12 ? 0.6 : 0.8)
        let iconRadius = innerRadius + (wheelSize / 2 - innerRadius) * positionFactor
        let midAngleRad = midAngle * .pi / 180
        let iconX = cos(midAngleRad) * iconRadius
        let iconY = sin(midAngleRad) * iconRadius

        let forceQuitProgress = isSelected ? manager.forceQuitProgress : 0
        let isAtFullRange = isSelected && manager.isFullRange

        // Main slice: blue when selected normally, gray when full range (selection moves to perimeter)
        let mainSliceFill: Color = {
            if isSelected && !isAtFullRange {
                return Color.accentColor.opacity(0.6)
            }
            return .clear
        }()

        // Perimeter slice state
        let perimeterFill: Color = isAtFullRange ? .green.opacity(0.6) : .clear

        // Radial text for perimeter
        let perimeterText: String? = {
            guard isAtFullRange else { return nil }
            switch item.kind {
            case .app:
                return forceQuitProgress >= 1.0 ? "Force Quit" : "New Window"
            case .website:
                return forceQuitProgress >= 1.0 ? "Incognito" : "New Window"
            }
        }()

        // Text rotation: bottom of text faces center
        let textRotation = midAngle - 270.0

        // Position for perimeter text
        let perimeterMidRadius = perimeterInnerRadius + perimeterWidth / 2
        let perimeterTextX = cos(midAngleRad) * perimeterMidRadius
        let perimeterTextY = sin(midAngleRad) * perimeterMidRadius

        return ZStack {
            // Main slice fill
            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: innerRadius,
                outerRadius: wheelSize / 2
            )
            .fill(mainSliceFill)

            // Main slice border
            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: innerRadius,
                outerRadius: wheelSize / 2
            )
            .stroke(Color.white.opacity(0.2), lineWidth: 1)

            // Perimeter slice - green highlight
            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: perimeterInnerRadius,
                outerRadius: perimeterOuterRadius
            )
            .fill(perimeterFill)

            // Perimeter slice - force quit red fill (grows from inner to outer of perimeter)
            if forceQuitProgress > 0 {
                SegmentShape(
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle + segmentAngle),
                    innerRadius: perimeterInnerRadius,
                    outerRadius: perimeterInnerRadius + perimeterWidth * forceQuitProgress
                )
                .fill(Color.red.opacity(0.7))
            }

            // Perimeter slice border
            SegmentShape(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + segmentAngle),
                innerRadius: perimeterInnerRadius,
                outerRadius: perimeterOuterRadius
            )
            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)

            // Radial text on perimeter
            if let perimeterText = perimeterText {
                Text(perimeterText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(textRotation))
                    .offset(x: perimeterTextX, y: perimeterTextY)
            }

            // Icon and label (always on main slice)
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
        .frame(width: 920, height: 920)
        .background(.black)
}
