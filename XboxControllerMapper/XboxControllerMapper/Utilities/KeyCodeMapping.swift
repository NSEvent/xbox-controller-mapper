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

    // MARK: - Symbol Keys

    static let leftBracket: CGKeyCode = CGKeyCode(kVK_ANSI_LeftBracket)
    static let rightBracket: CGKeyCode = CGKeyCode(kVK_ANSI_RightBracket)
    static let semicolon: CGKeyCode = CGKeyCode(kVK_ANSI_Semicolon)
    static let quote: CGKeyCode = CGKeyCode(kVK_ANSI_Quote)
    static let comma: CGKeyCode = CGKeyCode(kVK_ANSI_Comma)
    static let period: CGKeyCode = CGKeyCode(kVK_ANSI_Period)
    static let slash: CGKeyCode = CGKeyCode(kVK_ANSI_Slash)
    static let backslash: CGKeyCode = CGKeyCode(kVK_ANSI_Backslash)
    static let minus: CGKeyCode = CGKeyCode(kVK_ANSI_Minus)
    static let equal: CGKeyCode = CGKeyCode(kVK_ANSI_Equal)
    static let grave: CGKeyCode = CGKeyCode(kVK_ANSI_Grave)

    // MARK: - Other Keys

    static let home: CGKeyCode = CGKeyCode(kVK_Home)
    static let end: CGKeyCode = CGKeyCode(kVK_End)
    static let pageUp: CGKeyCode = CGKeyCode(kVK_PageUp)
    static let pageDown: CGKeyCode = CGKeyCode(kVK_PageDown)

    // MARK: - Special Markers for Mouse Buttons (not real key codes)

    static let mouseLeftClick: CGKeyCode = 0xF000
    static let mouseRightClick: CGKeyCode = 0xF001
    static let mouseMiddleClick: CGKeyCode = 0xF002

    // MARK: - Special Action Markers

    /// Shows on-screen keyboard while button is held
    static let showOnScreenKeyboard: CGKeyCode = 0xF010

    /// Shows a laser pointer dot on the cursor
    static let showLaserPointer: CGKeyCode = 0xF011

    // MARK: - Media Key Markers

    // Playback controls
    static let mediaPlayPause: CGKeyCode = 0xF020
    static let mediaNext: CGKeyCode = 0xF021
    static let mediaPrevious: CGKeyCode = 0xF022
    static let mediaFastForward: CGKeyCode = 0xF023
    static let mediaRewind: CGKeyCode = 0xF024

    // Volume controls
    static let volumeUp: CGKeyCode = 0xF030
    static let volumeDown: CGKeyCode = 0xF031
    static let volumeMute: CGKeyCode = 0xF032

    // Brightness controls
    static let brightnessUp: CGKeyCode = 0xF040
    static let brightnessDown: CGKeyCode = 0xF041

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

        // Function keys F1-F12
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

        // Extended function keys F13-F20
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

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

        // Symbols
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Grave: return "`"

        // Modifiers
        case kVK_Command: return "Command"
        case kVK_Shift: return "Shift"
        case kVK_Option: return "Option"
        case kVK_Control: return "Control"
        case kVK_CapsLock: return "Caps Lock"
        case kVK_Function: return "Fn"

        // Navigation
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"

        // Mouse buttons
        case 0xF000: return "Left Click"
        case 0xF001: return "Right Click"
        case 0xF002: return "Middle Click"

        // Special actions
        case 0xF010: return "On-Screen Keyboard"
        case 0xF011: return "Laser Pointer"

        // Media keys - Playback
        case 0xF020: return "Play/Pause"
        case 0xF021: return "Next Track"
        case 0xF022: return "Previous Track"
        case 0xF023: return "Fast Forward"
        case 0xF024: return "Rewind"

        // Media keys - Volume
        case 0xF030: return "Volume Up"
        case 0xF031: return "Volume Down"
        case 0xF032: return "Mute"

        // Media keys - Brightness
        case 0xF040: return "Brightness Up"
        case 0xF041: return "Brightness Down"

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

        // Function keys F1-F12 (key codes are NOT sequential)
        let fKeyCodes: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
        ]
        for i in 0..<12 {
            options.append(("F\(i + 1)", CGKeyCode(fKeyCodes[i])))
        }

        // Extended function keys F13-F20
        let extFKeyCodes: [Int] = [
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        for i in 0..<8 {
            options.append(("F\(i + 13)", CGKeyCode(extFKeyCodes[i])))
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

        // Numbers (key codes are NOT sequential)
        let numberCodes: [CGKeyCode] = [
            key0, key1, key2, key3, key4, key5, key6, key7, key8, key9
        ]
        for i in 0...9 {
            options.append(("\(i)", numberCodes[i]))
        }

        // Symbols
        options.append(("[", leftBracket))
        options.append(("]", rightBracket))
        options.append((";", semicolon))
        options.append(("'", quote))
        options.append((",", comma))
        options.append((".", period))
        options.append(("/", slash))
        options.append(("\\", backslash))
        options.append(("-", minus))
        options.append(("=", equal))
        options.append(("`", grave))

        // Mouse buttons
        options.append(("Left Click", mouseLeftClick))
        options.append(("Right Click", mouseRightClick))
        options.append(("Middle Click", mouseMiddleClick))

        // Special actions
        options.append(("On-Screen Keyboard", showOnScreenKeyboard))
        options.append(("Laser Pointer", showLaserPointer))

        // Media keys - Playback
        options.append(("Play/Pause", mediaPlayPause))
        options.append(("Next Track", mediaNext))
        options.append(("Previous Track", mediaPrevious))
        options.append(("Fast Forward", mediaFastForward))
        options.append(("Rewind", mediaRewind))

        // Media keys - Volume
        options.append(("Volume Up", volumeUp))
        options.append(("Volume Down", volumeDown))
        options.append(("Mute", volumeMute))

        // Media keys - Brightness
        options.append(("Brightness Up", brightnessUp))
        options.append(("Brightness Down", brightnessDown))

        return options
    }

    /// Checks if a key code represents a mouse button
    static func isMouseButton(_ keyCode: CGKeyCode) -> Bool {
        keyCode == mouseLeftClick || keyCode == mouseRightClick || keyCode == mouseMiddleClick
    }

    /// Checks if a key code represents a special action (on-screen keyboard, etc.)
    static func isSpecialAction(_ keyCode: CGKeyCode) -> Bool {
        keyCode == showOnScreenKeyboard || keyCode == showLaserPointer
    }

    /// Checks if a key code represents a media key
    static func isMediaKey(_ keyCode: CGKeyCode) -> Bool {
        (keyCode >= 0xF020 && keyCode <= 0xF024) ||  // Playback
        (keyCode >= 0xF030 && keyCode <= 0xF032) ||  // Volume
        (keyCode >= 0xF040 && keyCode <= 0xF041)     // Brightness
    }

    /// Checks if a key code is a special marker that shouldn't be sent as a key event
    static func isSpecialMarker(_ keyCode: CGKeyCode) -> Bool {
        isMouseButton(keyCode) || isSpecialAction(keyCode) || isMediaKey(keyCode)
    }

    // MARK: - Character to Key Code Mapping

    /// Returns the key code and whether shift is required for a given character
    /// Returns nil for characters that cannot be typed with a standard US keyboard
    static func keyInfo(for character: Character) -> (keyCode: CGKeyCode, needsShift: Bool)? {
        let char = character.lowercased().first ?? character

        // Letters (a-z)
        if let scalar = char.unicodeScalars.first, scalar.value >= 97 && scalar.value <= 122 {
            let letterCodes: [CGKeyCode] = [
                keyA, keyB, keyC, keyD, keyE, keyF, keyG, keyH, keyI, keyJ, keyK, keyL, keyM,
                keyN, keyO, keyP, keyQ, keyR, keyS, keyT, keyU, keyV, keyW, keyX, keyY, keyZ
            ]
            let index = Int(scalar.value - 97)
            return (letterCodes[index], character.isUppercase)
        }

        // Numbers and their shifted symbols
        switch character {
        case "0": return (key0, false)
        case "1": return (key1, false)
        case "2": return (key2, false)
        case "3": return (key3, false)
        case "4": return (key4, false)
        case "5": return (key5, false)
        case "6": return (key6, false)
        case "7": return (key7, false)
        case "8": return (key8, false)
        case "9": return (key9, false)
        case ")": return (key0, true)
        case "!": return (key1, true)
        case "@": return (key2, true)
        case "#": return (key3, true)
        case "$": return (key4, true)
        case "%": return (key5, true)
        case "^": return (key6, true)
        case "&": return (key7, true)
        case "*": return (key8, true)
        case "(": return (key9, true)
        default: break
        }

        // Punctuation and symbols
        switch character {
        case " ": return (space, false)
        case "\n", "\r": return (`return`, false)
        case "\t": return (tab, false)
        case "-": return (minus, false)
        case "_": return (minus, true)
        case "=": return (equal, false)
        case "+": return (equal, true)
        case "[": return (leftBracket, false)
        case "{": return (leftBracket, true)
        case "]": return (rightBracket, false)
        case "}": return (rightBracket, true)
        case "\\": return (backslash, false)
        case "|": return (backslash, true)
        case ";": return (semicolon, false)
        case ":": return (semicolon, true)
        case "'": return (quote, false)
        case "\"": return (quote, true)
        case ",": return (comma, false)
        case "<": return (comma, true)
        case ".": return (period, false)
        case ">": return (period, true)
        case "/": return (slash, false)
        case "?": return (slash, true)
        case "`": return (grave, false)
        case "~": return (grave, true)
        default: return nil
        }
    }

    // MARK: - Key Code to Character Mapping

    /// Returns the character that would be typed for a given key code and shift state.
    /// Returns nil for non-typable keys (modifiers, function keys, arrows, media, mouse, etc.)
    static func typedCharacter(for keyCode: CGKeyCode, shift: Bool) -> String? {
        let code = Int(keyCode)

        if let letter = letterMap[code] {
            return shift ? letter.uppercased() : letter
        }
        if let num = numberMap[code] {
            return shift ? num.shifted : num.normal
        }
        if let sym = symbolMap[code] {
            return shift ? sym.shifted : sym.normal
        }
        if code == kVK_Space { return " " }

        // Everything else (Return, Tab, Escape, Delete, arrows, F-keys, modifiers, media, mouse) → nil
        return nil
    }

    // Static lookup tables for typedCharacter (avoid allocation on every call)

    private static let letterMap: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
        kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
        kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
        kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z"
    ]

    private static let numberMap: [Int: (normal: String, shifted: String)] = [
        kVK_ANSI_1: ("1", "!"), kVK_ANSI_2: ("2", "@"), kVK_ANSI_3: ("3", "#"),
        kVK_ANSI_4: ("4", "$"), kVK_ANSI_5: ("5", "%"), kVK_ANSI_6: ("6", "^"),
        kVK_ANSI_7: ("7", "&"), kVK_ANSI_8: ("8", "*"), kVK_ANSI_9: ("9", "("),
        kVK_ANSI_0: ("0", ")")
    ]

    private static let symbolMap: [Int: (normal: String, shifted: String)] = [
        kVK_ANSI_Grave: ("`", "~"), kVK_ANSI_Minus: ("-", "_"), kVK_ANSI_Equal: ("=", "+"),
        kVK_ANSI_LeftBracket: ("[", "{"), kVK_ANSI_RightBracket: ("]", "}"),
        kVK_ANSI_Backslash: ("\\", "|"), kVK_ANSI_Semicolon: (";", ":"),
        kVK_ANSI_Quote: ("'", "\""), kVK_ANSI_Comma: (",", "<"),
        kVK_ANSI_Period: (".", ">"), kVK_ANSI_Slash: ("/", "?")
    ]

    // MARK: - Special Key Flags

    /// Keys that require NumPad flag to be recognized properly by apps
    private static let numPadKeys: Set<CGKeyCode> = [
        CGKeyCode(kVK_LeftArrow), CGKeyCode(kVK_RightArrow),
        CGKeyCode(kVK_DownArrow), CGKeyCode(kVK_UpArrow),
        CGKeyCode(kVK_Home), CGKeyCode(kVK_End),
        CGKeyCode(kVK_PageUp), CGKeyCode(kVK_PageDown),
        CGKeyCode(kVK_ForwardDelete)
    ]

    /// Keys that require the Fn (SecondaryFn) flag to be recognized properly by apps
    /// This includes F1-F20 and navigation keys. Without this flag, terminals using
    /// CSI u / Kitty keyboard protocol will output escape sequences instead of triggering hotkeys.
    private static let fnKeys: Set<CGKeyCode> = [
        // F1-F12
        CGKeyCode(kVK_F1), CGKeyCode(kVK_F2), CGKeyCode(kVK_F3), CGKeyCode(kVK_F4),
        CGKeyCode(kVK_F5), CGKeyCode(kVK_F6), CGKeyCode(kVK_F7), CGKeyCode(kVK_F8),
        CGKeyCode(kVK_F9), CGKeyCode(kVK_F10), CGKeyCode(kVK_F11), CGKeyCode(kVK_F12),
        // F13-F20 (extended function keys)
        CGKeyCode(kVK_F13), CGKeyCode(kVK_F14), CGKeyCode(kVK_F15), CGKeyCode(kVK_F16),
        CGKeyCode(kVK_F17), CGKeyCode(kVK_F18), CGKeyCode(kVK_F19), CGKeyCode(kVK_F20),
        // Navigation keys
        CGKeyCode(kVK_Home), CGKeyCode(kVK_End),
        CGKeyCode(kVK_PageUp), CGKeyCode(kVK_PageDown),
        CGKeyCode(kVK_ForwardDelete),
        CGKeyCode(kVK_LeftArrow), CGKeyCode(kVK_RightArrow),
        CGKeyCode(kVK_DownArrow), CGKeyCode(kVK_UpArrow)
    ]

    /// Returns additional CGEventFlags needed for special keys (function keys, arrow keys, etc.)
    /// These flags are required for apps like Rectangle to recognize shortcuts and for
    /// terminals to properly interpret function keys.
    static func specialKeyFlags(for keyCode: CGKeyCode) -> CGEventFlags {
        var flags: CGEventFlags = []

        if numPadKeys.contains(keyCode) {
            flags.insert(.maskNumericPad)
        }
        if fnKeys.contains(keyCode) {
            flags.insert(.maskSecondaryFn)
        }

        return flags
    }

    /// Checks if a key code requires the Fn flag
    static func requiresFnFlag(_ keyCode: CGKeyCode) -> Bool {
        fnKeys.contains(keyCode)
    }

    /// Checks if a key code requires the NumPad flag
    static func requiresNumPadFlag(_ keyCode: CGKeyCode) -> Bool {
        numPadKeys.contains(keyCode)
    }
}
