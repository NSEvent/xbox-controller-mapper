import SwiftUI
import Carbon.HIToolbox

/// A clickable on-screen keyboard that sends key presses to the system
struct OnScreenKeyboardView: View {
    /// Callback to send a key press with modifiers
    var onKeyPress: (CGKeyCode, ModifierFlags) -> Void

    @State private var activeModifiers = ModifierFlags()
    @State private var hoveredKey: CGKeyCode?
    @State private var pressedKey: CGKeyCode?

    // Key size constants - increase for larger keyboard
    private let keyWidth: CGFloat = 44
    private let keyHeight: CGFloat = 40
    private let keySpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 10) {
            // Function key row (Esc + F1-F12)
            functionKeyRow

            // Main keyboard
            VStack(spacing: keySpacing) {
                numberRow
                qwertyRow
                asdfRow
                zxcvRow
                bottomRow
            }

            // Navigation keys
            navigationKeyRow
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    // MARK: - Function Keys (F1-F12)

    private let f1to12Codes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]

    private var functionKeyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Escape), label: "Esc", width: 56)

            Spacer().frame(width: 20)

            ForEach(0..<4, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 50)
            }

            Spacer().frame(width: 12)

            ForEach(4..<8, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 50)
            }

            Spacer().frame(width: 12)

            ForEach(8..<12, id: \.self) { i in
                clickableKey(CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 50)
            }
        }
    }

    // MARK: - Number Row

    private var numberRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_ANSI_Grave), label: "`")

            ForEach(0..<10, id: \.self) { i in
                let keyCode = CGKeyCode(i == 9 ? kVK_ANSI_0 : kVK_ANSI_1 + i)
                let displayNum = i == 9 ? "0" : "\(i + 1)"
                clickableKey(keyCode, label: displayNum)
            }

            clickableKey(CGKeyCode(kVK_ANSI_Minus), label: "-")
            clickableKey(CGKeyCode(kVK_ANSI_Equal), label: "=")
            clickableKey(CGKeyCode(kVK_Delete), label: "⌫", width: 70)
        }
    }

    // MARK: - QWERTY Row

    private var qwertyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Tab), label: "Tab", width: 62)

            let qwertyKeys = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
            let qwertyCodes: [Int] = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P]

            ForEach(0..<qwertyKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(qwertyCodes[i]), label: qwertyKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_LeftBracket), label: "[")
            clickableKey(CGKeyCode(kVK_ANSI_RightBracket), label: "]")
            clickableKey(CGKeyCode(kVK_ANSI_Backslash), label: "\\", width: 62)
        }
    }

    // MARK: - ASDF Row

    private var asdfRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_CapsLock), label: "Caps", width: 74)

            let asdfKeys = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
            let asdfCodes: [Int] = [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L]

            ForEach(0..<asdfKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(asdfCodes[i]), label: asdfKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_Semicolon), label: ";")
            clickableKey(CGKeyCode(kVK_ANSI_Quote), label: "'")
            clickableKey(CGKeyCode(kVK_Return), label: "Return", width: 82)
        }
    }

    // MARK: - ZXCV Row

    private var zxcvRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⇧ Shift", width: 92, modifier: \.shift)

            let zxcvKeys = ["Z", "X", "C", "V", "B", "N", "M"]
            let zxcvCodes: [Int] = [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M]

            ForEach(0..<zxcvKeys.count, id: \.self) { i in
                clickableKey(CGKeyCode(zxcvCodes[i]), label: zxcvKeys[i])
            }

            clickableKey(CGKeyCode(kVK_ANSI_Comma), label: ",")
            clickableKey(CGKeyCode(kVK_ANSI_Period), label: ".")
            clickableKey(CGKeyCode(kVK_ANSI_Slash), label: "/")
            modifierKey(label: "⇧ Shift", width: 92, modifier: \.shift)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: keySpacing) {
            modifierKey(label: "⌃", width: 50, modifier: \.control)
            modifierKey(label: "⌥", width: 50, modifier: \.option)
            modifierKey(label: "⌘", width: 60, modifier: \.command)

            clickableKey(CGKeyCode(kVK_Space), label: "Space", width: 240)

            modifierKey(label: "⌘", width: 60, modifier: \.command)
            modifierKey(label: "⌥", width: 50, modifier: \.option)

            // Arrow keys cluster
            VStack(spacing: 2) {
                clickableKey(CGKeyCode(kVK_UpArrow), label: "↑", width: 40, height: 18)
                HStack(spacing: 2) {
                    clickableKey(CGKeyCode(kVK_LeftArrow), label: "←", width: 40, height: 18)
                    clickableKey(CGKeyCode(kVK_DownArrow), label: "↓", width: 40, height: 18)
                    clickableKey(CGKeyCode(kVK_RightArrow), label: "→", width: 40, height: 18)
                }
            }
        }
    }

    // MARK: - Navigation Keys

    private var navigationKeyRow: some View {
        HStack(spacing: keySpacing) {
            clickableKey(CGKeyCode(kVK_Home), label: "Home", width: 54)
            clickableKey(CGKeyCode(kVK_End), label: "End", width: 54)
            clickableKey(CGKeyCode(kVK_PageUp), label: "PgUp", width: 54)
            clickableKey(CGKeyCode(kVK_PageDown), label: "PgDn", width: 54)
            clickableKey(CGKeyCode(kVK_ForwardDelete), label: "Del", width: 54)
        }
    }

    // MARK: - Key Button

    @ViewBuilder
    private func clickableKey(_ keyCode: CGKeyCode, label: String, width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        let actualWidth = width ?? keyWidth
        let actualHeight = height ?? keyHeight
        let isHovered = hoveredKey == keyCode
        let isPressed = pressedKey == keyCode

        Button {
            pressedKey = keyCode
            onKeyPress(keyCode, activeModifiers)
            // Brief visual feedback then clear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if pressedKey == keyCode {
                    pressedKey = nil
                }
            }
        } label: {
            Text(label)
                .font(.system(size: fontSize(for: label), weight: .medium))
                .frame(width: actualWidth, height: actualHeight)
                .background(keyBackground(isHovered: isHovered, isPressed: isPressed))
                .foregroundColor(isPressed ? .white : .primary)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(keyBorderColor(isHovered: isHovered, isPressed: isPressed), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
        }
    }

    // MARK: - Modifier Key

    @ViewBuilder
    private func modifierKey(label: String, width: CGFloat, modifier: WritableKeyPath<ModifierFlags, Bool>) -> some View {
        let isActive = activeModifiers[keyPath: modifier]
        let isHovered = hoveredKey == modifierKeyCode(for: modifier)

        Button {
            activeModifiers[keyPath: modifier].toggle()
        } label: {
            Text(label)
                .font(.system(size: fontSize(for: label), weight: .medium))
                .frame(width: width, height: keyHeight)
                .background(isActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor)))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: isActive ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? modifierKeyCode(for: modifier) : nil
        }
    }

    private func modifierKeyCode(for modifier: WritableKeyPath<ModifierFlags, Bool>) -> CGKeyCode {
        switch modifier {
        case \.command: return CGKeyCode(kVK_Command)
        case \.option: return CGKeyCode(kVK_Option)
        case \.shift: return CGKeyCode(kVK_Shift)
        case \.control: return CGKeyCode(kVK_Control)
        default: return 0
        }
    }

    // MARK: - Helpers

    private func fontSize(for label: String) -> CGFloat {
        if label.count > 4 { return 11 }
        if label.count > 2 { return 12 }
        return 14
    }

    private func keyBackground(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func keyBorderColor(isHovered: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return .accentColor
        } else if isHovered {
            return .accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }
}

#Preview {
    OnScreenKeyboardView { keyCode, modifiers in
        print("Key pressed: \(keyCode), modifiers: \(modifiers)")
    }
    .frame(width: 650)
}
