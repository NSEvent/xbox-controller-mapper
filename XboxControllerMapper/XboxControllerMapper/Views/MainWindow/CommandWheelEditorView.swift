import SwiftUI

/// A miniature interactive wheel preview for the settings tab.
/// Shows items as donut segments that can be clicked to select for editing
/// and dragged to rearrange their order.
struct CommandWheelEditorView: View {
    let items: [CommandWheelAction]
    @Binding var selectedItemId: UUID?
    var onItemTapped: ((CommandWheelAction) -> Void)?
    var onMoveItem: ((IndexSet, Int) -> Void)?

    @State private var draggedItemId: UUID?
    @State private var dragTargetIndex: Int?
    @State private var iconCache: [UUID: NSImage] = [:]

    private let innerRadius: CGFloat = 60
    private let outerRadius: CGFloat = 150
    private let segmentGap: Double = 3.0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: outerRadius * 2 + 20, height: outerRadius * 2 + 20)

            if items.isEmpty {
                // Empty state
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)

                VStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
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

                        ZStack {
                            // Segment fill
                            DonutSegment(
                                startAngle: startAngle,
                                endAngle: endAngle,
                                innerRadius: innerRadius,
                                outerRadius: outerRadius
                            )
                            .fill(segmentFill(isSelected: isSelected, isDragging: isDragging))
                            .overlay(
                                DonutSegment(
                                    startAngle: startAngle,
                                    endAngle: endAngle,
                                    innerRadius: innerRadius,
                                    outerRadius: outerRadius
                                )
                                .stroke(segmentStroke(isSelected: isSelected, isDragging: isDragging), lineWidth: isSelected ? 2 : 1)
                            )

                            // Icon and label
                            let midRad = midAngle.radians
                            let iconRadius = (innerRadius + outerRadius) / 2
                            let x = center.x + cos(midRad) * iconRadius
                            let y = center.y + sin(midRad) * iconRadius

                            VStack(spacing: 2) {
                                actionIconView(for: action)
                                    .frame(width: items.count <= 6 ? 22 : 16, height: items.count <= 6 ? 22 : 16)
                                    .foregroundColor(isSelected ? .white : .primary)

                                if items.count <= 8 {
                                    Text(action.displayName)
                                        .font(.system(size: 8))
                                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 50)
                                }
                            }
                            .position(x: x, y: y)
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
                .frame(width: outerRadius * 2 + 20, height: outerRadius * 2 + 20)
                .coordinateSpace(name: "wheelEditor")

                // Center hub
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .frame(width: innerRadius * 2 - 8, height: innerRadius * 2 - 8)
                    .shadow(color: .black.opacity(0.2), radius: 3)

                if let selectedId = selectedItemId,
                   let action = items.first(where: { $0.id == selectedId }) {
                    Text(action.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: innerRadius * 2 - 20)
                        .lineLimit(2)
                } else if draggedItemId != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.5))
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
        }
        .frame(width: outerRadius * 2 + 20, height: outerRadius * 2 + 20)
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

    /// Computes the display order of items, reflecting the in-progress drag reorder
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

    /// Determines which segment index a point falls into based on its angle from center
    private func segmentIndex(for point: CGPoint, in center: CGPoint) -> Int {
        guard items.count > 1 else { return 0 }
        let dx = point.x - center.x
        let dy = point.y - center.y
        // atan2 with SwiftUI coordinates (y-down)
        var angle = atan2(dy, dx)
        // Rotate so "up" (negative y) is index 0, clockwise
        angle -= -.pi / 2 // shift so up = 0
        if angle < 0 { angle += 2 * .pi }
        let segmentSize = (2 * .pi) / Double(items.count)
        let index = Int(angle / segmentSize) % items.count
        return min(index, items.count - 1)
    }

    /// Commits the drag by calling onMoveItem
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

    // MARK: - Appearance

    private func segmentFill(isSelected: Bool, isDragging: Bool) -> Color {
        if isDragging { return Color.accentColor.opacity(0.3) }
        if isSelected { return Color.accentColor.opacity(0.6) }
        return Color.primary.opacity(0.08)
    }

    private func segmentStroke(isSelected: Bool, isDragging: Bool) -> Color {
        if isDragging { return Color.accentColor.opacity(0.6) }
        if isSelected { return Color.accentColor }
        return Color.primary.opacity(0.15)
    }

    @ViewBuilder
    private func actionIconView(for action: CommandWheelAction) -> some View {
        if let icon = iconCache[action.id] {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: action.defaultIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
