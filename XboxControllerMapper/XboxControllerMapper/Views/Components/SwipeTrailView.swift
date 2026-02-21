import SwiftUI

/// Renders the swipe path trail and cursor dot over the keyboard area.
/// Coordinates are normalized 0-1 and converted to view coordinates via GeometryReader.
struct SwipeTrailView: View {
    let swipePath: [CGPoint]
    let cursorPosition: CGPoint

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, _ in
                guard swipePath.count >= 2 else { return }

                let total = swipePath.count
                // Draw trail segments with gradient from faded to bright
                for i in 1..<total {
                    let from = viewPoint(swipePath[i - 1], in: size)
                    let to = viewPoint(swipePath[i], in: size)
                    let progress = Double(i) / Double(total - 1)

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)

                    let opacity = 0.15 + 0.85 * progress
                    let lineWidth = 2.0 + 2.0 * progress
                    context.stroke(
                        path,
                        with: .color(.cyan.opacity(opacity)),
                        lineWidth: lineWidth
                    )
                }
            }

            // Cursor dot with glow
            let cursorPt = viewPoint(cursorPosition, in: size)
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: .cyan, radius: 8)
                .shadow(color: .cyan.opacity(0.5), radius: 16)
                .position(cursorPt)
        }
        .allowsHitTesting(false)
    }

    private func viewPoint(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }
}
