import SwiftUI

/// Interactive wheel preview for the settings tab that mirrors the actual CommandWheelView appearance.
/// Items can be clicked to select for editing and dragged to rearrange order.
struct CommandWheelEditorView: View {
    let items: [CommandWheelAction]
    @Binding var selectedItemId: UUID?
    var onItemTapped: ((CommandWheelAction) -> Void)?
    var onMoveItem: ((IndexSet, Int) -> Void)?

    @State private var draggedItemId: UUID?
    @State private var dragTargetIndex: Int?
    @State private var iconCache: [UUID: NSImage] = [:]

    private let innerRadiusRatio: CGFloat = 0.17
    private let outerRadiusRatio: CGFloat = 0.46
    private let segmentGap: Double = 2.0

    var body: some View {
        GeometryReader { container in
            let size = min(container.size.width, container.size.height)
            let innerRadius = size * innerRadiusRatio
            let outerRadius = size * outerRadiusRatio
            let wheelSize = outerRadius * 2 + size * 0.07

            ZStack {
                // Dark backdrop with material (matches real wheel)
                Color.black.opacity(0.4)
                    .background(.ultraThinMaterial)
                    .mask(Circle())
                    .frame(width: wheelSize, height: wheelSize)
                    .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 5)

                if items.isEmpty {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundColor(.secondary.opacity(0.3))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)

                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: size * 0.07))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Add actions")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                } else {
                    // Segments
                    GeometryReader { geo in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let displayOrder = computeDisplayOrder()

                        ForEach(Array(displayOrder.enumerated()), id: \.element.id) { displayIndex, action in
                            let isSelected = selectedItemId == action.id
                            let isDragging = draggedItemId == action.id
                            let segmentDegrees = 360.0 / Double(items.count)
                            let startAngle = Angle.degrees(270.0 + (segmentDegrees * Double(displayIndex)) + (segmentGap / 2))
                            let endAngle = Angle.degrees(270.0 + (segmentDegrees * Double(displayIndex + 1)) - (segmentGap / 2))
                            let midAngle = Angle.degrees(270.0 + (segmentDegrees * Double(displayIndex)) + (segmentDegrees / 2))

                            let baseFill = isSelected ? Color.accentColor.opacity(0.8) : Color.black.opacity(0.6)

                            ZStack {
                                // Segment fill (matches real wheel style)
                                DonutSegment(
                                    startAngle: startAngle,
                                    endAngle: endAngle,
                                    innerRadius: innerRadius,
                                    outerRadius: outerRadius
                                )
                                .fill(baseFill)
                                .shadow(color: isSelected ? Color.accentColor.opacity(0.5) : .clear, radius: 10)
                                .scaleEffect(isSelected ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                                // Icon
                                GeometryReader { segGeo in
                                    let midRad = midAngle.radians
                                    let iconRadius = (innerRadius + outerRadius) / 2
                                    let x = segGeo.size.width / 2 + cos(midRad) * iconRadius
                                    let y = segGeo.size.height / 2 + sin(midRad) * iconRadius
                                    let baseIconSize = size * (items.count <= 6 ? 0.09 : 0.065)
                                    let iconSize = isSelected ? baseIconSize * 1.2 : baseIconSize

                                    Group {
                                        if let icon = iconCache[action.id] {
                                            Image(nsImage: icon)
                                                .resizable()
                                        } else {
                                            Image(systemName: action.defaultIconName)
                                                .resizable()
                                        }
                                    }
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: iconSize, height: iconSize)
                                    .opacity(isSelected ? 1.0 : 0.7)
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                                    .position(x: x, y: y)
                                }
                            }
                            .opacity(isDragging ? 0.6 : 1.0)
                            .contentShape(
                                DonutSegment(
                                    startAngle: startAngle,
                                    endAngle: endAngle,
                                    innerRadius: innerRadius,
                                    outerRadius: outerRadius
                                )
                            )
                            .onTapGesture {
                                selectedItemId = action.id
                                onItemTapped?(action)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 8, coordinateSpace: .named("wheelEditor"))
                                    .onChanged { value in
                                        if draggedItemId == nil {
                                            draggedItemId = action.id
                                        }
                                        let targetIndex = segmentIndex(for: value.location, in: center)
                                        if targetIndex != dragTargetIndex {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                dragTargetIndex = targetIndex
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        commitDrag()
                                    }
                            )
                        }
                    }
                    .frame(width: wheelSize, height: wheelSize)
                    .coordinateSpace(name: "wheelEditor")

                    // Center hub (matches real wheel)
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: innerRadius * 2 - 10, height: innerRadius * 2 - 10)
                        .shadow(color: .black.opacity(0.3), radius: 5)

                    if let selectedId = selectedItemId,
                       let action = items.first(where: { $0.id == selectedId }) {
                        Text(action.displayName)
                            .font(.system(size: max(10, size * 0.035), weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: innerRadius * 2 - 20)
                            .lineLimit(2)
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: size * 0.06))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: container.size.width / 2, y: container.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { rebuildIconCache() }
        .onChange(of: items) { rebuildIconCache() }
    }

    private func rebuildIconCache() {
        var cache: [UUID: NSImage] = [:]
        for action in items {
            if let icon = action.resolvedIcon() {
                cache[action.id] = icon
            }
        }
        iconCache = cache
    }

    // MARK: - Drag Logic

    private func computeDisplayOrder() -> [CommandWheelAction] {
        guard let dragId = draggedItemId,
              let targetIndex = dragTargetIndex,
              let sourceIndex = items.firstIndex(where: { $0.id == dragId }),
              sourceIndex != targetIndex,
              targetIndex >= 0, targetIndex < items.count else {
            return items
        }

        var reordered = items
        let item = reordered.remove(at: sourceIndex)
        reordered.insert(item, at: targetIndex)
        return reordered
    }

    private func segmentIndex(for point: CGPoint, in center: CGPoint) -> Int {
        guard items.count > 1 else { return 0 }
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx)
        angle -= -.pi / 2
        if angle < 0 { angle += 2 * .pi }
        let segmentSize = (2 * .pi) / Double(items.count)
        let index = Int(angle / segmentSize) % items.count
        return min(index, items.count - 1)
    }

    private func commitDrag() {
        if let dragId = draggedItemId,
           let targetIndex = dragTargetIndex,
           let sourceIndex = items.firstIndex(where: { $0.id == dragId }),
           sourceIndex != targetIndex {
            let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            onMoveItem?(IndexSet(integer: sourceIndex), destination)
        }
        draggedItemId = nil
        dragTargetIndex = nil
    }
}
