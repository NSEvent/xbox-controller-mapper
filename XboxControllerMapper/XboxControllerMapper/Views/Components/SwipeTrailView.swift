import SwiftUI

/// Renders the swipe path trail and cursor dot over the keyboard area.
/// Coordinates are normalized 0-1 relative to the letter-key bounding box
/// (matching SwipeKeyboardLayout) and mapped to the correct pixel region
/// within the full keyboard overlay.
struct SwipeTrailView: View {
    let swipePath: [CGPoint]
    let cursorPosition: CGPoint

    // Keyboard constants (must match OnScreenKeyboardView)
    private let keyWidth: CGFloat = 68
    private let keyHeight: CGFloat = 60
    private let keySpacing: CGFloat = 8
    private let keyStep: CGFloat = 76  // keyWidth + keySpacing

    // Row widths for leading offsets (must match OnScreenKeyboardView)
    private let tabWidth: CGFloat = 95
    private let capsLockWidth: CGFloat = 112
    private let shiftWidth: CGFloat = 140

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let letterArea = letterAreaRect(in: size)

            Canvas { context, _ in
                guard swipePath.count >= 2 else { return }

                let total = swipePath.count
                for i in 1..<total {
                    let from = viewPoint(swipePath[i - 1], letterArea: letterArea)
                    let to = viewPoint(swipePath[i], letterArea: letterArea)
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
            let cursorPt = viewPoint(cursorPosition, letterArea: letterArea)
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: .cyan, radius: 8)
                .shadow(color: .cyan.opacity(0.5), radius: 16)
                .position(cursorPt)
        }
        .allowsHitTesting(false)
    }

    /// Map a normalized (0-1) point to view coordinates within the letter area.
    private func viewPoint(_ normalized: CGPoint, letterArea: CGRect) -> CGPoint {
        CGPoint(
            x: letterArea.origin.x + normalized.x * letterArea.width,
            y: letterArea.origin.y + normalized.y * letterArea.height
        )
    }

    /// Compute the pixel rect of the letter-key area within the overlay.
    /// The overlay covers the full keyboard VStack (5 rows) + navigation column.
    /// The letter area is rows 2-4 (QWERTY, ASDF, ZXCV), X spans from first
    /// letter key to last letter key (matching SwipeKeyboardLayout's bounding box).
    private func letterAreaRect(in size: CGSize) -> CGRect {
        // The overlay's VStack has 5 rows (number, qwerty, asdf, zxcv, bottom)
        // with keySpacing between them.
        let rowStep = keyHeight + keySpacing  // 68
        let totalVStackHeight = 5 * keyHeight + 4 * keySpacing  // 332

        // Letter area Y: starts after number row + spacing
        let letterTopPixel = rowStep  // 68
        let letterHeightPixel = 3 * keyHeight + 2 * keySpacing  // 196

        // Letter area X: use the bounding box of all 26 letter key centers
        // Same computation as SwipeKeyboardLayout.letterBBox
        let qwertyLeading = tabWidth + keySpacing       // 103
        let asdfLeading = capsLockWidth + keySpacing     // 120
        let zxcvLeading = shiftWidth + keySpacing        // 148

        // Min X: leftmost key center - half key width
        // QWERTY row first key center: qwertyLeading + keyWidth/2 = 103 + 34 = 137
        // ASDF row first key center: asdfLeading + keyWidth/2 = 120 + 34 = 154
        // ZXCV row first key center: zxcvLeading + keyWidth/2 = 148 + 34 = 182
        // Min center X = 137 (Q key)
        let minCenterX = qwertyLeading + keyWidth / 2.0

        // Max X: rightmost key center + half key width
        // QWERTY row last key (P, index 9): qwertyLeading + 9 * keyStep + keyWidth/2 = 103 + 684 + 34 = 821
        let maxCenterX = qwertyLeading + 9 * keyStep + keyWidth / 2.0

        let letterLeftPixel = minCenterX - keyWidth / 2.0  // = qwertyLeading
        let letterRightPixel = maxCenterX + keyWidth / 2.0
        let letterWidthPixel = letterRightPixel - letterLeftPixel

        // The overlay HStack also contains the navigation column to the right,
        // plus spacing. The total overlay width includes that extra space.
        // We need to compute the fraction of overlay width that the letter area occupies.
        // Since we don't know the exact overlay width, use size.width and scale by
        // the ratio of letter area to the main keyboard VStack width.
        //
        // Main VStack width (number row is widest):
        // Backtick + 10 numbers + minus + equal + backspace
        // = 68 + 10*68 + 68 + 68 + 107 + 13*8 = 991 (approximate)
        // Actually let's compute from the QWERTY row which is well-defined:
        // Tab(95) + 10 letters(10*68) + [(68) + ](68) + \(95) + 13*8(spacing) = 1030

        // The nav column adds: keyWidth(68) + 2*keySpacing(16) = 84
        // Total HStack width ≈ 1030 + 84 = 1114 (approximate)
        // But the actual overlay size is given by `size`, so we scale.
        let mainKeyboardWidth = tabWidth + 10 * keyStep + keyStep + keyStep + tabWidth + keySpacing  // approximate
        let navColumnWidth = keyWidth + keySpacing * 2
        let totalEstWidth = mainKeyboardWidth + navColumnWidth

        // Scale factors from pixel layout to actual overlay view size
        let scaleX = size.width / totalEstWidth
        let scaleY = size.height / totalVStackHeight

        return CGRect(
            x: letterLeftPixel * scaleX,
            y: letterTopPixel * scaleY,
            width: letterWidthPixel * scaleX,
            height: letterHeightPixel * scaleY
        )
    }
}
