import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Virtual key code constants and utilities
enum KeyCodeMapping {
    // MARK: - Special Keys

    static let `return`: CGKeyCode = CGKeyCode(kVK_Return)
    static let tab: CGKeyCode = CGKeyCode(kVK_Tab)
    static let space: CGKeyCode = CGKeyCode(kVK_Space)
    static let delete: CGKeyCode = CGKeyCode(kVK_Delete)
    static let escape: CGKeyCode = CGKeyCode(kVK_Escape)
    static let forwardDelete: CGKeyCode = CGKeyCode(kVK_ForwardDelete)

    // MARK: - Arrow Keys

    static let leftArrow: CGKeyCode = CGKeyCode(kVK_LeftArrow)
    static let rightArrow: CGKeyCode = CGKeyCode(kVK_RightArrow)
    static let upArrow: CGKeyCode = CGKeyCode(kVK_UpArrow)
    static let downArrow: CGKeyCode = CGKeyCode(kVK_DownArrow)

    // MARK: - Function Keys

    static let f1: CGKeyCode = CGKeyCode(kVK_F1)
    static let f2: CGKeyCode = CGKeyCode(kVK_F2)
    static let f3: CGKeyCode = CGKeyCode(kVK_F3)
    static let f4: CGKeyCode = CGKeyCode(kVK_F4)
    static let f5: CGKeyCode = CGKeyCode(kVK_F5)
    static let f6: CGKeyCode = CGKeyCode(kVK_F6)
    static let f7: CGKeyCode = CGKeyCode(kVK_F7)
    static let f8: CGKeyCode = CGKeyCode(kVK_F8)
    static let f9: CGKeyCode = CGKeyCode(kVK_F9)
    static let f10: CGKeyCode = CGKeyCode(kVK_F10)
    static let f11: CGKeyCode = CGKeyCode(kVK_F11)
    static let f12: CGKeyCode = CGKeyCode(kVK_F12)

    // MARK: - Modifier Keys

    static let command: CGKeyCode = CGKeyCode(kVK_Command)
    static let shift: CGKeyCode = CGKeyCode(kVK_Shift)
    static let option: CGKeyCode = CGKeyCode(kVK_Option)
    static let control: CGKeyCode = CGKeyCode(kVK_Control)

    // MARK: - Number Keys

    static let key0: CGKeyCode = CGKeyCode(kVK_ANSI_0)
    static let key1: CGKeyCode = CGKeyCode(kVK_ANSI_1)
    static let key2: CGKeyCode = CGKeyCode(kVK_ANSI_2)
    static let key3: CGKeyCode = CGKeyCode(kVK_ANSI_3)
    static let key4: CGKeyCode = CGKeyCode(kVK_ANSI_4)
    static let key5: CGKeyCode = CGKeyCode(kVK_ANSI_5)
    static let key6: CGKeyCode = CGKeyCode(kVK_ANSI_6)
    static let key7: CGKeyCode = CGKeyCode(kVK_ANSI_7)
    static let key8: CGKeyCode = CGKeyCode(kVK_ANSI_8)
    static let key9: CGKeyCode = CGKeyCode(kVK_ANSI_9)

    // MARK: - Letter Keys

    static let keyA: CGKeyCode = CGKeyCode(kVK_ANSI_A)
    static let keyB: CGKeyCode = CGKeyCode(kVK_ANSI_B)
    static let keyC: CGKeyCode = CGKeyCode(kVK_ANSI_C)
    static let keyD: CGKeyCode = CGKeyCode(kVK_ANSI_D)
    static let keyE: CGKeyCode = CGKeyCode(kVK_ANSI_E)
    static let keyF: CGKeyCode = CGKeyCode(kVK_ANSI_F)
    static let keyG: CGKeyCode = CGKeyCode(kVK_ANSI_G)
    static let keyH: CGKeyCode = CGKeyCode(kVK_ANSI_H)
    static let keyI: CGKeyCode = CGKeyCode(kVK_ANSI_I)
    static let keyJ: CGKeyCode = CGKeyCode(kVK_ANSI_J)
    static let keyK: CGKeyCode = CGKeyCode(kVK_ANSI_K)
    static let keyL: CGKeyCode = CGKeyCode(kVK_ANSI_L)
    static let keyM: CGKeyCode = CGKeyCode(kVK_ANSI_M)
    static let keyN: CGKeyCode = CGKeyCode(kVK_ANSI_N)
    static let keyO: CGKeyCode = CGKeyCode(kVK_ANSI_O)
    static let keyP: CGKeyCode = CGKeyCode(kVK_ANSI_P)
    static let keyQ: CGKeyCode = CGKeyCode(kVK_ANSI_Q)
    static let keyR: CGKeyCode = CGKeyCode(kVK_ANSI_R)
    static let keyS: CGKeyCode = CGKeyCode(kVK_ANSI_S)
    static let keyT: CGKeyCode = CGKeyCode(kVK_ANSI_T)
    static let keyU: CGKeyCode = CGKeyCode(kVK_ANSI_U)
    static let keyV: CGKeyCode = CGKeyCode(kVK_ANSI_V)
    static let keyW: CGKeyCode = CGKeyCode(kVK_ANSI_W)
    static let keyX: CGKeyCode = CGKeyCode(kVK_ANSI_X)
    static let keyY: CGKeyCode = CGKeyCode(kVK_ANSI_Y)
    static let keyZ: CGKeyCode = CGKeyCode(kVK_ANSI_Z)

    // MARK: - Other Keys

    static let home: CGKeyCode = CGKeyCode(kVK_Home)
    static let end: CGKeyCode = CGKeyCode(kVK_End)
    static let pageUp: CGKeyCode = CGKeyCode(kVK_PageUp)
    static let pageDown: CGKeyCode = CGKeyCode(kVK_PageDown)

    // MARK: - Special Markers for Mouse Buttons (not real key codes)

    static let mouseLeftClick: CGKeyCode = 0xF000
    static let mouseRightClick: CGKeyCode = 0xF001
    static let mouseMiddleClick: CGKeyCode = 0xF002

    // MARK: - Display Names

    /// Returns a human-readable name for a key code
    static func displayName(for keyCode: CGKeyCode) -> String {
        switch Int(keyCode) {
        // Special keys
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_ForwardDelete: return "⌦"

        // Arrow keys
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"

        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // Navigation
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"

        // Mouse buttons
        case 0xF000: return "Left Click"
        case 0xF001: return "Right Click"
        case 0xF002: return "Middle Click"

        default: return "Key \(keyCode)"
        }
    }

    /// Returns all available key codes for picker UI
    static var allKeyOptions: [(name: String, code: CGKeyCode)] {
        var options: [(String, CGKeyCode)] = []

        // Common keys first
        options.append(("Return", `return`))
        options.append(("Tab", tab))
        options.append(("Space", space))
        options.append(("Escape", escape))
        options.append(("Delete", delete))

        // Arrow keys
        options.append(("←", leftArrow))
        options.append(("→", rightArrow))
        options.append(("↑", upArrow))
        options.append(("↓", downArrow))

        // Function keys
        for i in 1...12 {
            let code = CGKeyCode(kVK_F1 + i - 1)
            options.append(("F\(i)", code))
        }

        // Letters
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let letterCodes: [CGKeyCode] = [
            keyA, keyB, keyC, keyD, keyE, keyF, keyG, keyH, keyI, keyJ, keyK, keyL, keyM,
            keyN, keyO, keyP, keyQ, keyR, keyS, keyT, keyU, keyV, keyW, keyX, keyY, keyZ
        ]
        for (letter, code) in zip(letters, letterCodes) {
            options.append((String(letter), code))
        }

        // Numbers
        for i in 0...9 {
            let code = CGKeyCode(kVK_ANSI_0 + i)
            options.append(("\(i)", code))
        }

        // Mouse buttons
        options.append(("Left Click", mouseLeftClick))
        options.append(("Right Click", mouseRightClick))
        options.append(("Middle Click", mouseMiddleClick))

        return options
    }

    /// Checks if a key code represents a mouse button
    static func isMouseButton(_ keyCode: CGKeyCode) -> Bool {
        keyCode == mouseLeftClick || keyCode == mouseRightClick || keyCode == mouseMiddleClick
    }
}
