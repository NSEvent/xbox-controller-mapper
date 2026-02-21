import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Layout data for letter keys on the on-screen keyboard, used by the swipe typing model.
/// Coordinates are normalized to 0-1 relative to the main keyboard area.
struct SwipeKeyboardLayout {

    /// A key's position and size on the keyboard
    struct KeyRect {
        let keyCode: CGKeyCode
        let character: Character
        let center: CGPoint      // Normalized 0-1
        let size: CGSize         // Normalized 0-1
    }

    // MARK: - Constants (matching OnScreenKeyboardView)

    private static let keyWidth: CGFloat = 68
    private static let keyHeight: CGFloat = 60
    private static let keySpacing: CGFloat = 8
    private static let keyStep: CGFloat = keyWidth + keySpacing  // 76

    // Leading offsets (x position where first letter key starts)
    private static let qwertyLeadingOffset: CGFloat = 95 + keySpacing  // after Tab(95)
    private static let asdfLeadingOffset: CGFloat = 112 + keySpacing   // after CapsLock(112)
    private static let zxcvLeadingOffset: CGFloat = 140 + keySpacing   // after Shift(140)

    // Normalization: use the letter-key bounding box (matching Python training code)
    // This ensures coordinates are consistent with what the model was trained on.
    // Computed from all 26 letter key centers, extended by half key width/height.
    private static let letterBBox: (xMin: CGFloat, xMax: CGFloat, yMin: CGFloat, yMax: CGFloat) = {
        // Compute pixel centers for all letter keys
        var allX: [CGFloat] = []
        var allY: [CGFloat] = []
        let rows: [(offset: CGFloat, count: Int, yIndex: Int)] = [
            (qwertyLeadingOffset, 10, 0),  // QWERTY
            (asdfLeadingOffset, 9, 1),     // ASDF
            (zxcvLeadingOffset, 7, 2),     // ZXCV
        ]
        for row in rows {
            let yCenter = CGFloat(row.yIndex) * (keyHeight + keySpacing) + keyHeight / 2.0
            for i in 0..<row.count {
                let xCenter = row.offset + CGFloat(i) * keyStep + keyWidth / 2.0
                allX.append(xCenter)
                allY.append(yCenter)
            }
        }
        return (
            xMin: allX.min()! - keyWidth / 2.0,
            xMax: allX.max()! + keyWidth / 2.0,
            yMin: allY.min()! - keyHeight / 2.0,
            yMax: allY.max()! + keyHeight / 2.0
        )
    }()

    private static let normWidth: CGFloat = letterBBox.xMax - letterBBox.xMin
    private static let normHeight: CGFloat = letterBBox.yMax - letterBBox.yMin

    // Y centers for each letter row (0=QWERTY, 1=ASDF, 2=ZXCV)
    // Uses y_index 0,1,2 matching Python training code (letter rows only, not full keyboard)
    private static func rowCenterY(_ row: Int) -> CGFloat {
        CGFloat(row) * (keyHeight + keySpacing) + keyHeight / 2.0
    }

    // MARK: - Letter Keys

    /// All 26 letter keys with normalized positions (matching Python training layout)
    static let letterKeys: [KeyRect] = {
        var keys: [KeyRect] = []

        let qwertyChars: [(Character, Int)] = [
            ("Q", kVK_ANSI_Q), ("W", kVK_ANSI_W), ("E", kVK_ANSI_E), ("R", kVK_ANSI_R),
            ("T", kVK_ANSI_T), ("Y", kVK_ANSI_Y), ("U", kVK_ANSI_U), ("I", kVK_ANSI_I),
            ("O", kVK_ANSI_O), ("P", kVK_ANSI_P)
        ]
        let qwertyY = rowCenterY(0)  // y_index=0 matching Python
        for (i, (char, code)) in qwertyChars.enumerated() {
            let cx = qwertyLeadingOffset + CGFloat(i) * keyStep + keyWidth / 2.0
            keys.append(KeyRect(
                keyCode: CGKeyCode(code),
                character: char,
                center: CGPoint(
                    x: (cx - letterBBox.xMin) / normWidth,
                    y: (qwertyY - letterBBox.yMin) / normHeight
                ),
                size: CGSize(width: keyWidth / normWidth, height: keyHeight / normHeight)
            ))
        }

        let asdfChars: [(Character, Int)] = [
            ("A", kVK_ANSI_A), ("S", kVK_ANSI_S), ("D", kVK_ANSI_D), ("F", kVK_ANSI_F),
            ("G", kVK_ANSI_G), ("H", kVK_ANSI_H), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K),
            ("L", kVK_ANSI_L)
        ]
        let asdfY = rowCenterY(1)  // y_index=1 matching Python
        for (i, (char, code)) in asdfChars.enumerated() {
            let cx = asdfLeadingOffset + CGFloat(i) * keyStep + keyWidth / 2.0
            keys.append(KeyRect(
                keyCode: CGKeyCode(code),
                character: char,
                center: CGPoint(
                    x: (cx - letterBBox.xMin) / normWidth,
                    y: (asdfY - letterBBox.yMin) / normHeight
                ),
                size: CGSize(width: keyWidth / normWidth, height: keyHeight / normHeight)
            ))
        }

        let zxcvChars: [(Character, Int)] = [
            ("Z", kVK_ANSI_Z), ("X", kVK_ANSI_X), ("C", kVK_ANSI_C), ("V", kVK_ANSI_V),
            ("B", kVK_ANSI_B), ("N", kVK_ANSI_N), ("M", kVK_ANSI_M)
        ]
        let zxcvY = rowCenterY(2)  // y_index=2 matching Python
        for (i, (char, code)) in zxcvChars.enumerated() {
            let cx = zxcvLeadingOffset + CGFloat(i) * keyStep + keyWidth / 2.0
            keys.append(KeyRect(
                keyCode: CGKeyCode(code),
                character: char,
                center: CGPoint(
                    x: (cx - letterBBox.xMin) / normWidth,
                    y: (zxcvY - letterBBox.yMin) / normHeight
                ),
                size: CGSize(width: keyWidth / normWidth, height: keyHeight / normHeight)
            ))
        }

        return keys
    }()

    /// Lookup from character to KeyRect (uppercase letters)
    private static let charToKey: [Character: KeyRect] = {
        var map: [Character: KeyRect] = [:]
        for key in letterKeys {
            map[key.character] = key
        }
        return map
    }()

    /// Find the KeyRect for a given character (case-insensitive)
    static func key(for character: Character) -> KeyRect? {
        charToKey[Character(character.uppercased())]
    }

    // MARK: - Proximity

    /// Find the nearest letter key to a normalized point
    static func nearestKey(to point: CGPoint) -> KeyRect? {
        var best: KeyRect?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for key in letterKeys {
            let dx = key.center.x - point.x
            let dy = key.center.y - point.y
            let dist = dx * dx + dy * dy
            if dist < bestDist {
                bestDist = dist
                best = key
            }
        }
        return best
    }

    /// Find the N nearest letter keys to a normalized point
    static func nearestKeys(to point: CGPoint, count: Int) -> [KeyRect] {
        let sorted = letterKeys.sorted { a, b in
            let da = (a.center.x - point.x) * (a.center.x - point.x) + (a.center.y - point.y) * (a.center.y - point.y)
            let db = (b.center.x - point.x) * (b.center.x - point.x) + (b.center.y - point.y) * (b.center.y - point.y)
            return da < db
        }
        return Array(sorted.prefix(count))
    }

    /// 26-dimensional inverse-distance vector for model input, ordered A-Z.
    /// Each element is 1/(1 + distance*10) from the given point to that letter's center.
    /// The *10 scale factor matches the Python training code for useful gradient.
    static func keyProximityVector(for point: CGPoint) -> [Double] {
        // Build in A-Z order
        let orderedKeys = letterKeys.sorted { $0.character < $1.character }
        return orderedKeys.map { key in
            let dx = Double(key.center.x - point.x)
            let dy = Double(key.center.y - point.y)
            let dist = (dx * dx + dy * dy).squareRoot()
            return 1.0 / (1.0 + dist * 10.0)
        }
    }
}
