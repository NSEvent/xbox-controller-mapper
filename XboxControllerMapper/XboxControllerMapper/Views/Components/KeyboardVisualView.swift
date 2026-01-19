import SwiftUI
import Carbon.HIToolbox

/// A visual keyboard display for selecting keyboard shortcuts
struct KeyboardVisualView: View {
    @Binding var selectedKeyCode: CGKeyCode?
    @Binding var modifiers: ModifierFlags

    @State private var hoveredKey: CGKeyCode?

    var body: some View {
        VStack(spacing: 12) {
            // Extended function keys (F13-F20) at the very top
            extendedFunctionKeyRow

            // Function key row (Esc + F1-F12)
            functionKeyRow

            // Main keyboard
            VStack(spacing: 4) {
                numberRow
                qwertyRow
                asdfRow
                zxcvRow
                bottomRow
            }

            // Navigation keys
            navigationKeyRow

            // Modifier checkboxes at the bottom
            modifierRow
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Modifier Row

    private var modifierRow: some View {
        HStack(spacing: 16) {
            ModifierToggle(label: "⌘ Command", isOn: $modifiers.command)
            ModifierToggle(label: "⌥ Option", isOn: $modifiers.option)
            ModifierToggle(label: "⇧ Shift", isOn: $modifiers.shift)
            ModifierToggle(label: "⌃ Control", isOn: $modifiers.control)

            Spacer()

            if selectedKeyCode != nil || modifiers.hasAny {
                Button("Clear") {
                    selectedKeyCode = nil
                    modifiers = ModifierFlags()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Function Keys (F1-F12)

    // F-key codes are NOT sequential, so we must use explicit arrays
    private let f1to12Codes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]

    private var functionKeyRow: some View {
        HStack(spacing: 4) {
            KeyButton(keyCode: CGKeyCode(kVK_Escape), label: "Esc", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

            Spacer().frame(width: 20)

            ForEach(0..<4, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 40, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            Spacer().frame(width: 10)

            ForEach(4..<8, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 40, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            Spacer().frame(width: 10)

            ForEach(8..<12, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(f1to12Codes[i]), label: "F\(i + 1)", width: 40, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }
        }
    }

    // MARK: - Number Row

    private var numberRow: some View {
        HStack(spacing: 4) {
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Grave), label: "`", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

            ForEach(0..<10, id: \.self) { i in
                let keyCode = CGKeyCode(i == 0 ? kVK_ANSI_0 : kVK_ANSI_1 + i - 1)
                // Display order: 1,2,3,4,5,6,7,8,9,0
                let displayNum = i == 9 ? "0" : "\(i + 1)"
                KeyButton(keyCode: keyCode, label: displayNum, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Minus), label: "-", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Equal), label: "=", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_Delete), label: "⌫", width: 60, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
        }
    }

    // MARK: - QWERTY Row

    private var qwertyRow: some View {
        HStack(spacing: 4) {
            KeyButton(keyCode: CGKeyCode(kVK_Tab), label: "Tab", width: 50, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

            let qwertyKeys = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
            let qwertyCodes: [Int] = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P]

            ForEach(0..<qwertyKeys.count, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(qwertyCodes[i]), label: qwertyKeys[i], selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            KeyButton(keyCode: CGKeyCode(kVK_ANSI_LeftBracket), label: "[", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_RightBracket), label: "]", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Backslash), label: "\\", width: 50, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
        }
    }

    // MARK: - ASDF Row

    private var asdfRow: some View {
        HStack(spacing: 4) {
            KeyButton(keyCode: CGKeyCode(kVK_CapsLock), label: "Caps", width: 60, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

            let asdfKeys = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
            let asdfCodes: [Int] = [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L]

            ForEach(0..<asdfKeys.count, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(asdfCodes[i]), label: asdfKeys[i], selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Semicolon), label: ";", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Quote), label: "'", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_Return), label: "Return", width: 70, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
        }
    }

    // MARK: - ZXCV Row

    private var zxcvRow: some View {
        HStack(spacing: 4) {
            ModifierKeyButton(label: "⇧ Shift", width: 80, isActive: $modifiers.shift)

            let zxcvKeys = ["Z", "X", "C", "V", "B", "N", "M"]
            let zxcvCodes: [Int] = [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M]

            ForEach(0..<zxcvKeys.count, id: \.self) { i in
                KeyButton(keyCode: CGKeyCode(zxcvCodes[i]), label: zxcvKeys[i], selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }

            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Comma), label: ",", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Period), label: ".", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            KeyButton(keyCode: CGKeyCode(kVK_ANSI_Slash), label: "/", selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            ModifierKeyButton(label: "⇧ Shift", width: 80, isActive: $modifiers.shift)
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 4) {
            KeyButton(keyCode: CGKeyCode(kVK_Function), label: "Fn", width: 40, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            ModifierKeyButton(label: "⌃", width: 40, isActive: $modifiers.control)
            ModifierKeyButton(label: "⌥", width: 40, isActive: $modifiers.option)
            ModifierKeyButton(label: "⌘", width: 50, isActive: $modifiers.command)

            KeyButton(keyCode: CGKeyCode(kVK_Space), label: "Space", width: 200, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

            ModifierKeyButton(label: "⌘", width: 50, isActive: $modifiers.command)
            ModifierKeyButton(label: "⌥", width: 40, isActive: $modifiers.option)

            // Arrow keys cluster
            VStack(spacing: 2) {
                KeyButton(keyCode: CGKeyCode(kVK_UpArrow), label: "↑", width: 30, height: 15, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                HStack(spacing: 2) {
                    KeyButton(keyCode: CGKeyCode(kVK_LeftArrow), label: "←", width: 30, height: 15, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                    KeyButton(keyCode: CGKeyCode(kVK_DownArrow), label: "↓", width: 30, height: 15, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                    KeyButton(keyCode: CGKeyCode(kVK_RightArrow), label: "→", width: 30, height: 15, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                }
            }
        }
    }

    // MARK: - Extended Function Keys (F13-F20)

    private var extendedFunctionKeyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extended Function Keys (F13-F20)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(extendedFunctionKeys, id: \.label) { key in
                    KeyButton(keyCode: key.code, label: key.label, width: 42, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                }
            }
        }
    }

    private var extendedFunctionKeys: [(label: String, code: CGKeyCode)] {
        // macOS officially supports F13-F20 as extended function keys
        // F21-F25 have overlapping codes with other keys, so we omit them
        [
            ("F13", CGKeyCode(kVK_F13)),
            ("F14", CGKeyCode(kVK_F14)),
            ("F15", CGKeyCode(kVK_F15)),
            ("F16", CGKeyCode(kVK_F16)),
            ("F17", CGKeyCode(kVK_F17)),
            ("F18", CGKeyCode(kVK_F18)),
            ("F19", CGKeyCode(kVK_F19)),
            ("F20", CGKeyCode(kVK_F20))
        ]
    }

    // MARK: - Navigation Keys

    private var navigationKeyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Navigation & Special Keys")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                KeyButton(keyCode: CGKeyCode(kVK_Help), label: "Help", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: CGKeyCode(kVK_Home), label: "Home", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: CGKeyCode(kVK_End), label: "End", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: CGKeyCode(kVK_PageUp), label: "PgUp", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: CGKeyCode(kVK_PageDown), label: "PgDn", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: CGKeyCode(kVK_ForwardDelete), label: "Del", width: 45, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

                Spacer().frame(width: 20)

                // Mouse click options
                KeyButton(keyCode: KeyCodeMapping.mouseLeftClick, label: "L Click", width: 55, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: KeyCodeMapping.mouseRightClick, label: "R Click", width: 55, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
                KeyButton(keyCode: KeyCodeMapping.mouseMiddleClick, label: "M Click", width: 55, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)

                Spacer().frame(width: 20)

                // Special actions
                KeyButton(keyCode: KeyCodeMapping.showOnScreenKeyboard, label: "⌨ Keyboard", width: 80, selectedKeyCode: $selectedKeyCode, hoveredKey: $hoveredKey)
            }
        }
    }
}

// MARK: - Modifier Key Button (toggleable)

struct ModifierKeyButton: View {
    let label: String
    var width: CGFloat = 40
    var height: CGFloat = 32
    @Binding var isActive: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: { isActive.toggle() }) {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .frame(width: width, height: height)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: isActive ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var fontSize: CGFloat {
        if label.count > 4 {
            return 9
        } else if label.count > 2 {
            return 10
        }
        return 12
    }

    private var backgroundColor: Color {
        if isActive {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var foregroundColor: Color {
        isActive ? .white : .primary
    }

    private var borderColor: Color {
        if isActive {
            return .accentColor
        } else if isHovered {
            return .accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Key Button

struct KeyButton: View {
    let keyCode: CGKeyCode
    let label: String
    var width: CGFloat = 35
    var height: CGFloat = 32

    @Binding var selectedKeyCode: CGKeyCode?
    @Binding var hoveredKey: CGKeyCode?

    var body: some View {
        Button(action: { selectedKeyCode = keyCode }) {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .frame(width: width, height: height)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? keyCode : nil
        }
    }

    private var isSelected: Bool {
        selectedKeyCode == keyCode
    }

    private var isHovered: Bool {
        hoveredKey == keyCode
    }

    private var fontSize: CGFloat {
        if label.count > 4 {
            return 9
        } else if label.count > 2 {
            return 10
        }
        return 12
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var foregroundColor: Color {
        isSelected ? .white : .primary
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return .accentColor.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Modifier Toggle

struct ModifierToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(isOn ? .accentColor : .secondary)
                Text(label)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    KeyboardVisualView(selectedKeyCode: .constant(nil), modifiers: .constant(ModifierFlags()))
        .frame(width: 700)
}
