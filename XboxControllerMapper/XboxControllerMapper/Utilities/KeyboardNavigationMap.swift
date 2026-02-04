import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Manages keyboard navigation for D-pad control of the on-screen keyboard
/// Defines navigable key positions based on OnScreenKeyboardView layout
struct KeyboardNavigationMap {

    /// A position in the keyboard grid
    struct KeyPosition: Equatable {
        let row: Int
        let column: Int
        let keyCode: CGKeyCode
        /// X position hint for vertical navigation (0.0-1.0 within row)
        let xPosition: Double
    }

    /// All navigable rows in the keyboard
    /// Row 0: Function keys (Esc, F1-F12)
    /// Row 1: Media controls (grouped)
    /// Row 2: Extended function keys (F13-F20) - only when enabled
    /// Row 3: Number row (`, 1-0, -, =, Backspace)
    /// Row 4: QWERTY row (Tab, Q-P, [, ], \)
    /// Row 5: ASDF row (Caps, A-L, ;, ', Return)
    /// Row 6: ZXCV row (Shift, Z-M, ,, ., /, Shift)
    /// Row 7: Bottom row (Ctrl, Opt, Cmd, Space, Cmd, Opt, arrows)
    /// Row 8: Navigation column (Del, Home, End, PgUp, PgDn)

    private static let functionRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        // Esc
        keys.append(KeyPosition(row: 0, column: 0, keyCode: CGKeyCode(kVK_Escape), xPosition: 0.0))
        // F1-F12
        let fKeyCodes: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
        ]
        for (i, code) in fKeyCodes.enumerated() {
            keys.append(KeyPosition(row: 0, column: i + 1, keyCode: CGKeyCode(code), xPosition: Double(i + 2) / 14.0))
        }
        return keys
    }()

    private static let mediaRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        // Playback: Previous, Play/Pause, Next
        // F4 (5/14≈0.357) → Play/Pause, so spread Playback around F2-F4 area
        keys.append(KeyPosition(row: 1, column: 0, keyCode: KeyCodeMapping.mediaPrevious, xPosition: 0.18))
        keys.append(KeyPosition(row: 1, column: 1, keyCode: KeyCodeMapping.mediaPlayPause, xPosition: 0.357)) // Exactly F4
        keys.append(KeyPosition(row: 1, column: 2, keyCode: KeyCodeMapping.mediaNext, xPosition: 0.41))
        // Volume: Mute, Down, Up
        // F6 (7/14=0.5) → Vol Down, so spread Volume around F5-F7 area
        keys.append(KeyPosition(row: 1, column: 3, keyCode: KeyCodeMapping.volumeMute, xPosition: 0.44))
        keys.append(KeyPosition(row: 1, column: 4, keyCode: KeyCodeMapping.volumeDown, xPosition: 0.50)) // Exactly F6
        keys.append(KeyPosition(row: 1, column: 5, keyCode: KeyCodeMapping.volumeUp, xPosition: 0.56))
        // Brightness: Down, Up
        // F8 (9/14≈0.643) → Bright Down, so spread Brightness around F8-F10 area
        keys.append(KeyPosition(row: 1, column: 6, keyCode: KeyCodeMapping.brightnessDown, xPosition: 0.643)) // Exactly F8
        keys.append(KeyPosition(row: 1, column: 7, keyCode: KeyCodeMapping.brightnessUp, xPosition: 0.78))
        return keys
    }()

    private static let extendedFunctionRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        let extFKeyCodes: [Int] = [
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        for (i, code) in extFKeyCodes.enumerated() {
            keys.append(KeyPosition(row: 2, column: i, keyCode: CGKeyCode(code), xPosition: Double(i + 1) / 10.0))
        }
        return keys
    }()

    private static let numberRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        let numberCodes: [(Int, String)] = [
            (kVK_ANSI_Grave, "`"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"), (kVK_ANSI_0, "0"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_Delete, "Delete")
        ]
        for (i, (code, _)) in numberCodes.enumerated() {
            keys.append(KeyPosition(row: 3, column: i, keyCode: CGKeyCode(code), xPosition: Double(i) / 14.0))
        }
        return keys
    }()

    private static let qwertyRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        let qwertyCodes: [Int] = [
            kVK_Tab, kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T,
            kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P,
            kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Backslash
        ]
        for (i, code) in qwertyCodes.enumerated() {
            keys.append(KeyPosition(row: 4, column: i, keyCode: CGKeyCode(code), xPosition: Double(i) / 14.0))
        }
        return keys
    }()

    private static let asdfRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        let asdfCodes: [Int] = [
            kVK_CapsLock, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G,
            kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
            kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_Return
        ]
        for (i, code) in asdfCodes.enumerated() {
            keys.append(KeyPosition(row: 5, column: i, keyCode: CGKeyCode(code), xPosition: Double(i) / 13.0))
        }
        return keys
    }()

    private static let zxcvRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        // Note: Both left and right shift use kVK_Shift in the view's modifierKey()
        let zxcvCodes: [Int] = [
            kVK_Shift, kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B,
            kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
            kVK_Shift  // Right shift uses same code as left in view
        ]
        for (i, code) in zxcvCodes.enumerated() {
            keys.append(KeyPosition(row: 6, column: i, keyCode: CGKeyCode(code), xPosition: Double(i) / 12.0))
        }
        return keys
    }()

    private static let bottomRow: [KeyPosition] = {
        var keys: [KeyPosition] = []
        // Control, Option, Command, Space, Command, Option, Arrows
        // Note: The view's modifierKey() uses the same codes for left/right modifiers
        let bottomCodes: [Int] = [
            kVK_Control, kVK_Option, kVK_Command, kVK_Space,
            kVK_Command, kVK_Option  // Right modifiers use same code as left in view
        ]
        let xPositions: [Double] = [0.0, 0.1, 0.2, 0.5, 0.7, 0.8]
        for (i, code) in bottomCodes.enumerated() {
            keys.append(KeyPosition(row: 7, column: i, keyCode: CGKeyCode(code), xPosition: xPositions[i]))
        }
        // Arrow keys at the end
        keys.append(KeyPosition(row: 7, column: 6, keyCode: CGKeyCode(kVK_UpArrow), xPosition: 0.9))
        keys.append(KeyPosition(row: 7, column: 7, keyCode: CGKeyCode(kVK_LeftArrow), xPosition: 0.85))
        keys.append(KeyPosition(row: 7, column: 8, keyCode: CGKeyCode(kVK_DownArrow), xPosition: 0.9))
        keys.append(KeyPosition(row: 7, column: 9, keyCode: CGKeyCode(kVK_RightArrow), xPosition: 0.95))
        return keys
    }()

    /// Navigation column keys (Del, Home, End, PgUp, PgDn) on the right side
    /// These align with rows: number, qwerty, asdf, zxcv, bottom
    static let navigationColumn: [KeyPosition] = {
        var keys: [KeyPosition] = []
        let navCodes: [Int] = [
            kVK_ForwardDelete, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown
        ]
        for (i, code) in navCodes.enumerated() {
            // Navigation column is at the far right, row 3-7
            keys.append(KeyPosition(row: 3 + i, column: 100, keyCode: CGKeyCode(code), xPosition: 1.0))
        }
        return keys
    }()

    /// Returns all rows for the keyboard in visual order (top to bottom)
    /// Visual layout: Media -> Extended F-keys (optional) -> F-keys -> Number -> QWERTY -> ASDF -> ZXCV -> Bottom
    static func allRows(includeExtendedFunctions: Bool = false) -> [[KeyPosition]] {
        var rows: [[KeyPosition]] = [
            mediaRow           // Row 0: Media controls (top)
        ]
        if includeExtendedFunctions {
            rows.append(extendedFunctionRow)  // Row 1: F13-F20
        }
        rows.append(functionRow)  // F1-F12 row
        rows.append(contentsOf: [
            numberRow,
            qwertyRow,
            asdfRow,
            zxcvRow,
            bottomRow
        ])
        return rows
    }

    /// Find the position of a key code in the navigation map
    static func findPosition(for keyCode: CGKeyCode, includeExtendedFunctions: Bool = false) -> (rowIndex: Int, columnIndex: Int)? {
        let rows = allRows(includeExtendedFunctions: includeExtendedFunctions)
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, position) in row.enumerated() {
                if position.keyCode == keyCode {
                    return (rowIndex, columnIndex)
                }
            }
        }
        // Check navigation column separately
        for (i, position) in navigationColumn.enumerated() {
            if position.keyCode == keyCode {
                return (position.row - 3 + (includeExtendedFunctions ? 3 : 2), 100 + i)
            }
        }
        return nil
    }

    /// Navigate from current key in a direction, returns the new key code
    static func navigate(from currentKeyCode: CGKeyCode?, direction: NavigationDirection, includeExtendedFunctions: Bool = false) -> CGKeyCode? {
        let rows = allRows(includeExtendedFunctions: includeExtendedFunctions)

        // If no current key, start at a sensible default
        guard let current = currentKeyCode else {
            // Start at Space bar (center of keyboard)
            return CGKeyCode(kVK_Space)
        }

        // Check if current is in navigation column
        if let navIndex = navigationColumn.firstIndex(where: { $0.keyCode == current }) {
            return navigateInNavigationColumn(from: navIndex, direction: direction, mainRows: rows)
        }

        // Find current position in main rows
        guard let (rowIndex, columnIndex) = findPositionInRows(current, rows: rows) else {
            // Current key not found, start at Space
            return CGKeyCode(kVK_Space)
        }

        let currentRow = rows[rowIndex]
        let currentPosition = currentRow[columnIndex]

        switch direction {
        case .up:
            if rowIndex > 0 {
                return findClosestKeyInRow(rows[rowIndex - 1], xPosition: currentPosition.xPosition)
            }
            return current // Already at top

        case .down:
            if rowIndex < rows.count - 1 {
                return findClosestKeyInRow(rows[rowIndex + 1], xPosition: currentPosition.xPosition)
            }
            return current // Already at bottom

        case .left:
            if columnIndex > 0 {
                return currentRow[columnIndex - 1].keyCode
            }
            return current // Already at left edge

        case .right:
            if columnIndex < currentRow.count - 1 {
                return currentRow[columnIndex + 1].keyCode
            }
            // Check if we can move to navigation column (rows 3-7, adjusted for extended functions)
            let adjustedRow = includeExtendedFunctions ? rowIndex - 3 : rowIndex - 2
            if adjustedRow >= 0 && adjustedRow < navigationColumn.count {
                return navigationColumn[adjustedRow].keyCode
            }
            return current // Already at right edge
        }
    }

    /// Navigate within the navigation column
    private static func navigateInNavigationColumn(from index: Int, direction: NavigationDirection, mainRows: [[KeyPosition]]) -> CGKeyCode {
        switch direction {
        case .up:
            if index > 0 {
                return navigationColumn[index - 1].keyCode
            }
            return navigationColumn[index].keyCode // Already at top

        case .down:
            if index < navigationColumn.count - 1 {
                return navigationColumn[index + 1].keyCode
            }
            return navigationColumn[index].keyCode // Already at bottom

        case .left:
            // Move to the corresponding main row (based on position.row)
            let navPosition = navigationColumn[index]
            let targetRowIndex = navPosition.row - 3 + (mainRows.count > 7 ? 3 : 2) // Adjust for extended functions
            if targetRowIndex >= 0 && targetRowIndex < mainRows.count {
                let row = mainRows[targetRowIndex]
                return row[row.count - 1].keyCode // Last key in that row
            }
            return navigationColumn[index].keyCode

        case .right:
            return navigationColumn[index].keyCode // Already at right edge
        }
    }

    /// Find the position of a key code in the given rows
    private static func findPositionInRows(_ keyCode: CGKeyCode, rows: [[KeyPosition]]) -> (Int, Int)? {
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, position) in row.enumerated() {
                if position.keyCode == keyCode {
                    return (rowIndex, columnIndex)
                }
            }
        }
        return nil
    }

    /// Find the closest key in a row based on x position
    private static func findClosestKeyInRow(_ row: [KeyPosition], xPosition: Double) -> CGKeyCode {
        var closest = row[0]
        var closestDistance = abs(closest.xPosition - xPosition)

        for position in row {
            let distance = abs(position.xPosition - xPosition)
            if distance < closestDistance {
                closest = position
                closestDistance = distance
            }
        }

        return closest.keyCode
    }

    /// Get the default starting key (Space bar)
    static var defaultKey: CGKeyCode {
        CGKeyCode(kVK_Space)
    }

    /// Navigation directions
    enum NavigationDirection {
        case up, down, left, right
    }
}
