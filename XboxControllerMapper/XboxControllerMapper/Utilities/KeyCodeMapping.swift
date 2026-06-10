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

    // MARK: - Modifier Keys (Left)

    static let command: CGKeyCode = CGKeyCode(kVK_Command)
    static let shift: CGKeyCode = CGKeyCode(kVK_Shift)
    static let option: CGKeyCode = CGKeyCode(kVK_Option)
    static let control: CGKeyCode = CGKeyCode(kVK_Control)

    // MARK: - Modifier Keys (Right)

    static let rightCommand: CGKeyCode = CGKeyCode(kVK_RightCommand)
    static let rightShift: CGKeyCode = CGKeyCode(kVK_RightShift)
    static let rightOption: CGKeyCode = CGKeyCode(kVK_RightOption)
    static let rightControl: CGKeyCode = CGKeyCode(kVK_RightControl)

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
    static let scrollUp: CGKeyCode = 0xF003
    static let scrollDown: CGKeyCode = 0xF004
    static let scrollLeft: CGKeyCode = 0xF005
    static let scrollRight: CGKeyCode = 0xF006
    static let mouseBackClick: CGKeyCode = 0xF007
    static let mouseForwardClick: CGKeyCode = 0xF008

    // MARK: - Special Action Markers

    /// Shows on-screen keyboard while button is held
    static let showOnScreenKeyboard: CGKeyCode = 0xF010

    /// Shows a laser pointer dot on the cursor
    static let showLaserPointer: CGKeyCode = 0xF011

    /// Locks/unlocks all controller input
    static let controllerLock: CGKeyCode = 0xF012

    /// Shows directory navigator overlay
    static let showDirectoryNavigator: CGKeyCode = 0xF013

    /// Shows standalone command wheel while button is held
    static let showCommandWheel: CGKeyCode = 0xF014

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

    private static let displayNames: [Int: String] = [
        // Special keys
	kVK_Return: "Return",
	kVK_Tab: "Tab",
	kVK_Space: "Space",
	kVK_Delete: "Delete",
	kVK_Escape: "Esc",
	kVK_ForwardDelete: "⌦",

	// Arrow keys
	kVK_LeftArrow: "←",
	kVK_RightArrow: "→",
	kVK_UpArrow: "↑",
	kVK_DownArrow: "↓",

	// Function keys F1-F12
	kVK_F1: "F1",
	kVK_F2: "F2",
	kVK_F3: "F3",
	kVK_F4: "F4",
	kVK_F5: "F5",
	kVK_F6: "F6",
	kVK_F7: "F7",
	kVK_F8: "F8",
	kVK_F9: "F9",
	kVK_F10: "F10",
	kVK_F11: "F11",
	kVK_F12: "F12",

	// Extended function keys F13-F20
	kVK_F13: "F13",
	kVK_F14: "F14",
	kVK_F15: "F15",
	kVK_F16: "F16",
	kVK_F17: "F17",
	kVK_F18: "F18",
	kVK_F19: "F19",
	kVK_F20: "F20",

	// Numbers
	kVK_ANSI_0: "0",
	kVK_ANSI_1: "1",
	kVK_ANSI_2: "2",
	kVK_ANSI_3: "3",
	kVK_ANSI_4: "4",
	kVK_ANSI_5: "5",
	kVK_ANSI_6: "6",
	kVK_ANSI_7: "7",
	kVK_ANSI_8: "8",
	kVK_ANSI_9: "9",

	// Letters
	kVK_ANSI_A: "A",
	kVK_ANSI_B: "B",
	kVK_ANSI_C: "C",
	kVK_ANSI_D: "D",
	kVK_ANSI_E: "E",
	kVK_ANSI_F: "F",
	kVK_ANSI_G: "G",
	kVK_ANSI_H: "H",
	kVK_ANSI_I: "I",
	kVK_ANSI_J: "J",
	kVK_ANSI_K: "K",
	kVK_ANSI_L: "L",
	kVK_ANSI_M: "M",
	kVK_ANSI_N: "N",
	kVK_ANSI_O: "O",
	kVK_ANSI_P: "P",
	kVK_ANSI_Q: "Q",
	kVK_ANSI_R: "R",
	kVK_ANSI_S: "S",
	kVK_ANSI_T: "T",
	kVK_ANSI_U: "U",
	kVK_ANSI_V: "V",
	kVK_ANSI_W: "W",
	kVK_ANSI_X: "X",
	kVK_ANSI_Y: "Y",
	kVK_ANSI_Z: "Z",

	// Symbols
	kVK_ANSI_LeftBracket: "[",
	kVK_ANSI_RightBracket: "]",
	kVK_ANSI_Semicolon: ";",
	kVK_ANSI_Quote: "'",
	kVK_ANSI_Comma: ",",
	kVK_ANSI_Period: ".",
	kVK_ANSI_Slash: "/",
	kVK_ANSI_Backslash: "\\",
	kVK_ANSI_Minus: "-",
	kVK_ANSI_Equal: "=",
	kVK_ANSI_Grave: "`",

	// Modifiers
	kVK_Command: "Left ⌘",
	kVK_Shift: "Left ⇧",
	kVK_Option: "Left ⌥",
	kVK_Control: "Left ⌃",
	kVK_RightCommand: "Right ⌘",
	kVK_RightShift: "Right ⇧",
	kVK_RightOption: "Right ⌥",
	kVK_RightControl: "Right ⌃",
	kVK_CapsLock: "Caps Lock",
	kVK_Function: "Fn",

	// Navigation
	kVK_Home: "Home",
	kVK_End: "End",
	kVK_PageUp: "Page Up",
	kVK_PageDown: "Page Down",

	// Mouse buttons and scroll actions
	Int(mouseLeftClick): "Left Click",
	Int(mouseRightClick): "Right Click",
	Int(mouseMiddleClick): "Middle Click",
	Int(scrollUp): "Scroll Up",
	Int(scrollDown): "Scroll Down",
	Int(scrollLeft): "Scroll Left",
	Int(scrollRight): "Scroll Right",
	Int(mouseBackClick): "Back Button",
	Int(mouseForwardClick): "Forward Button",

	// Special actions
	Int(showOnScreenKeyboard): "On-Screen Keyboard",
	Int(showLaserPointer): "Laser Pointer",
	Int(controllerLock): "Controller Lock",
	Int(showDirectoryNavigator): "Directory Navigator",
	Int(showCommandWheel): "Command Wheel",

	// Media keys
	Int(mediaPlayPause): "Play/Pause",
	Int(mediaNext): "Next Track",
	Int(mediaPrevious): "Previous Track",
	Int(mediaFastForward): "Fast Forward",
	Int(mediaRewind): "Rewind",
	Int(volumeUp): "Volume Up",
	Int(volumeDown): "Volume Down",
	Int(volumeMute): "Mute",
	Int(brightnessUp): "Brightness Up",
	Int(brightnessDown): "Brightness Down"
    ]

    /// Returns a human-readable name for a key code
    static func displayName(for keyCode: CGKeyCode) -> String {
	displayNames[Int(keyCode)] ?? "Key \(keyCode)"
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

        // Modifier keys (Left / Right distinction)
        options.append(("Left ⌘", command))
        options.append(("Right ⌘", rightCommand))
        options.append(("Left ⌥", option))
        options.append(("Right ⌥", rightOption))
        options.append(("Left ⇧", shift))
        options.append(("Right ⇧", rightShift))
        options.append(("Left ⌃", control))
        options.append(("Right ⌃", rightControl))

        // Mouse buttons
        options.append(("Left Click", mouseLeftClick))
        options.append(("Right Click", mouseRightClick))
        options.append(("Middle Click", mouseMiddleClick))
        options.append(("Scroll Up", scrollUp))
        options.append(("Scroll Down", scrollDown))
        options.append(("Scroll Left", scrollLeft))
        options.append(("Scroll Right", scrollRight))
        options.append(("Back Button", mouseBackClick))
        options.append(("Forward Button", mouseForwardClick))

        // Special actions
        options.append(("On-Screen Keyboard", showOnScreenKeyboard))
        options.append(("Laser Pointer", showLaserPointer))
        options.append(("Controller Lock", controllerLock))
        options.append(("Directory Navigator", showDirectoryNavigator))

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
        keyCode == mouseLeftClick ||
        keyCode == mouseRightClick ||
        keyCode == mouseMiddleClick ||
        keyCode == mouseBackClick ||
        keyCode == mouseForwardClick
    }

    /// Maps a mouse-button marker key code to the CGEvent type and button for
    /// a down or up event. Unknown codes fall back to the left button.
    static func mouseEventType(for keyCode: CGKeyCode, down: Bool) -> (CGEventType, CGMouseButton) {
        switch keyCode {
        case mouseLeftClick:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        case mouseRightClick:
            return (down ? .rightMouseDown : .rightMouseUp, .right)
        case mouseMiddleClick:
            return (down ? .otherMouseDown : .otherMouseUp, .center)
        case mouseBackClick:
            return (down ? .otherMouseDown : .otherMouseUp, CGMouseButton(rawValue: 3) ?? .center)
        case mouseForwardClick:
            return (down ? .otherMouseDown : .otherMouseUp, CGMouseButton(rawValue: 4) ?? .center)
        default:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        }
    }

    /// Checks if a key code represents a scroll action
    static func isScrollAction(_ keyCode: CGKeyCode) -> Bool {
        keyCode == scrollUp ||
        keyCode == scrollDown ||
        keyCode == scrollLeft ||
        keyCode == scrollRight
    }

    static func scrollDelta(for keyCode: CGKeyCode, amount: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        switch keyCode {
        case scrollUp:
            return (0, amount)
        case scrollDown:
            return (0, -amount)
        case scrollLeft:
            return (amount, 0)
        case scrollRight:
            return (-amount, 0)
        default:
            return (0, 0)
        }
    }

    /// Checks if a key code represents a special action (on-screen keyboard, etc.)
    static func isSpecialAction(_ keyCode: CGKeyCode) -> Bool {
        keyCode == showOnScreenKeyboard || keyCode == showLaserPointer || keyCode == controllerLock || keyCode == showDirectoryNavigator || keyCode == showCommandWheel
    }

    /// Checks if a key code represents a media key
    static func isMediaKey(_ keyCode: CGKeyCode) -> Bool {
        (keyCode >= 0xF020 && keyCode <= 0xF024) ||  // Playback
        (keyCode >= 0xF030 && keyCode <= 0xF032) ||  // Volume
        (keyCode >= 0xF040 && keyCode <= 0xF041)     // Brightness
    }

    /// Checks if a key code is a special marker that shouldn't be sent as a key event
    static func isSpecialMarker(_ keyCode: CGKeyCode) -> Bool {
        isMouseButton(keyCode) || isScrollAction(keyCode) || isSpecialAction(keyCode) || isMediaKey(keyCode)
    }

    /// Checks if a key code represents a modifier key (left or right variant)
    static func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl:
            return true
        default:
            return false
        }
    }

    /// Returns the CGEventFlags mask for a modifier key code, or empty if not a modifier.
    /// Left and right variants share the same mask (e.g. both Commands → .maskCommand).
    static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .maskCommand
        case kVK_Shift, kVK_RightShift: return .maskShift
        case kVK_Option, kVK_RightOption: return .maskAlternate
        case kVK_Control, kVK_RightControl: return .maskControl
        default: return []
        }
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
