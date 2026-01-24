import SwiftUI

/// A GTA-style radial command wheel for quick app/website switching
struct CommandWheelView: View {
    @ObservedObject var manager: CommandWheelManager

    // Layout constants
    private let wheelSize: CGFloat = 700
    private let innerRadius: CGFloat = 120
    private let outerRadius: CGFloat = 350
    private let iconSize: CGFloat = 64
    private let selectedIconScale: CGFloat = 1.2
    private let segmentGap: Double = 2.0 // Degrees of gap between segments

    var body: some View {
        ZStack {
            // Dark Backdrop
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .mask(Circle())
                .frame(width: wheelSize + 50, height: wheelSize + 50)
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)

            // Segments
            ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                WheelSegmentView(
                    index: index,
                    totalCount: manager.items.count,
                    item: item,
                    manager: manager,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    gapDegrees: segmentGap
                )
            }

            // Center Hub Information
            CenterHubView(manager: manager, radius: innerRadius)
        }
        .frame(width: wheelSize + 100, height: wheelSize + 100)
    }
}

/// A single segment slice of the wheel
struct WheelSegmentView: View {
    let index: Int
    let totalCount: Int
    let item: CommandWheelItem
    @ObservedObject var manager: CommandWheelManager
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapDegrees: Double

    var body: some View {
        let isSelected = manager.selectedIndex == index
        
        // Calculate Angles
        let segmentDegrees = 360.0 / Double(totalCount)
        let startAngle = Angle.degrees(270.0 + (segmentDegrees * Double(index)) + (gapDegrees / 2))
        let endAngle = Angle.degrees(270.0 + (segmentDegrees * Double(index + 1)) - (gapDegrees / 2))
        let midAngle = Angle.degrees(270.0 + (segmentDegrees * Double(index)) + (segmentDegrees / 2))

        // Selection State Colors
        let baseFill = isSelected ? Color.accentColor.opacity(0.8) : Color.black.opacity(0.6)

        // Force Quit / Secondary Action Progress
        let progress = isSelected ? manager.forceQuitProgress : 0
        let progressColor: Color = {
            if case .app = item.kind {
                return .red // Red for Force Quit
            } else {
                return .green // Green for Incognito
            }
        }()

        ZStack {
            // 1. Base Segment Shape
            DonutSegment(
                startAngle: startAngle,
                endAngle: endAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
            .fill(baseFill)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.5) : .clear, radius: 10)
            .scaleEffect(isSelected ? 1.05 : 1.0) // Slight pop out
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            // 2. Progress Border (for Force Quit / Secondary)
            if progress > 0 {
                DonutSegment(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: outerRadius - 10, // Inner rim of the outer edge
                    outerRadius: outerRadius
                )
                .trim(from: 0, to: progress)
                .fill(progressColor)
                .shadow(color: progressColor.opacity(0.8), radius: 5)
                .scaleEffect(isSelected ? 1.05 : 1.0)
            }

            // 3. Icon
            // Calculate icon position
            GeometryReader { geo in
                let midRad = midAngle.radians
                let radius = (innerRadius + outerRadius) / 2
                let x = geo.size.width / 2 + cos(midRad) * radius
                let y = geo.size.height / 2 + sin(midRad) * radius
                
                ItemIconView(item: item, isSelected: isSelected)
                    .position(x: x, y: y)
            }
        }
    }
}

/// Icon display logic
struct ItemIconView: View {
    let item: CommandWheelItem
    let isSelected: Bool

    var body: some View {
        Group {
            switch item.kind {
            case .app(let bundleIdentifier):
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
                   let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                }
            case .website(_, let faviconData):
                if let data = faviconData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "globe")
                        .resizable()
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: isSelected ? 80 : 50, height: isSelected ? 80 : 50)
        .opacity(isSelected ? 1.0 : 0.7)
        .saturation(isSelected ? 1.0 : 0.0) // Grayscale for unselected
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

/// The center hub showing details of the selected item
struct CenterHubView: View {
    @ObservedObject var manager: CommandWheelManager
    let radius: CGFloat

    var body: some View {
        ZStack {
            // Hub Background
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: radius * 2 - 10, height: radius * 2 - 10)
                .shadow(color: .black.opacity(0.3), radius: 5)

            if let index = manager.selectedIndex, index < manager.items.count {
                let item = manager.items[index]
                VStack(spacing: 4) {
                    // Item Name
                    Text(item.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)

                    // Secondary Status / Instruction
                    if manager.isFullRange {
                        Group {
                            if manager.forceQuitProgress >= 1.0 {
                                Text(forceQuitText(for: item.kind))
                                    .foregroundColor(.red)
                                    .fontWeight(.heavy)
                            } else {
                                Text(secondaryActionText(for: item.kind))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            } else {
                // Default / Empty State
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.3))
            }
        }
    }

    private func secondaryActionText(for kind: CommandWheelItem.Kind) -> String {
        switch kind {
        case .app: return "New Window"
        case .website: return "New Window"
        }
    }

    private func forceQuitText(for kind: CommandWheelItem.Kind) -> String {
        switch kind {
        case .app: return "FORCE QUIT"
        case .website: return "INCOGNITO"
        }
    }
}

/// Custom Shape for the donut segments
struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        // Outer Arc
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        
        // Inner Arc (drawn in reverse to create the hole)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        
        path.closeSubpath()
        return path
    }
}

#Preview {
    let manager = CommandWheelManager.shared
    CommandWheelView(manager: manager)
        .frame(width: 900, height: 900)
        .background(Color.gray)
}
