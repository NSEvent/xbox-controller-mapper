import SwiftUI
import CoreGraphics

struct MouseVisualView: View {
    @Binding var selectedKeyCode: CGKeyCode?
    @Binding var modifiers: ModifierFlags

    @State private var hoveredKey: CGKeyCode?

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                mouseBody
                scrollPad
                sideButtons
            }

            modifierRow
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }

    private var mouseBody: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                MouseActionButton(
                    keyCode: KeyCodeMapping.mouseLeftClick,
                    systemImage: "cursorarrow",
                    label: "Left",
                    width: 90,
                    height: 64,
                    selectedKeyCode: $selectedKeyCode,
                    hoveredKey: $hoveredKey
                )
                MouseActionButton(
                    keyCode: KeyCodeMapping.mouseMiddleClick,
                    systemImage: "circle.fill",
                    label: "Middle",
                    width: 72,
                    height: 64,
                    selectedKeyCode: $selectedKeyCode,
                    hoveredKey: $hoveredKey
                )
                MouseActionButton(
                    keyCode: KeyCodeMapping.mouseRightClick,
                    systemImage: "cursorarrow",
                    label: "Right",
                    width: 90,
                    height: 64,
                    selectedKeyCode: $selectedKeyCode,
                    hoveredKey: $hoveredKey
                )
            }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 274, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private var scrollPad: some View {
        VStack(spacing: 6) {
            MouseActionButton(
                keyCode: KeyCodeMapping.scrollUp,
                systemImage: "arrow.up",
                label: "Scroll Up",
                width: 112,
                height: 42,
                selectedKeyCode: $selectedKeyCode,
                hoveredKey: $hoveredKey
            )

            HStack(spacing: 6) {
                MouseActionButton(
                    keyCode: KeyCodeMapping.scrollLeft,
                    systemImage: "arrow.left",
                    label: "Left",
                    width: 72,
                    height: 48,
                    selectedKeyCode: $selectedKeyCode,
                    hoveredKey: $hoveredKey
                )
                MouseActionButton(
                    keyCode: KeyCodeMapping.scrollRight,
                    systemImage: "arrow.right",
                    label: "Right",
                    width: 72,
                    height: 48,
                    selectedKeyCode: $selectedKeyCode,
                    hoveredKey: $hoveredKey
                )
            }

            MouseActionButton(
                keyCode: KeyCodeMapping.scrollDown,
                systemImage: "arrow.down",
                label: "Scroll Down",
                width: 112,
                height: 42,
                selectedKeyCode: $selectedKeyCode,
                hoveredKey: $hoveredKey
            )
        }
    }

    private var sideButtons: some View {
        VStack(spacing: 8) {
            MouseActionButton(
                keyCode: KeyCodeMapping.mouseBackClick,
                systemImage: "arrow.uturn.backward",
                label: "Back",
                width: 104,
                height: 54,
                selectedKeyCode: $selectedKeyCode,
                hoveredKey: $hoveredKey
            )
            MouseActionButton(
                keyCode: KeyCodeMapping.mouseForwardClick,
                systemImage: "arrow.uturn.forward",
                label: "Forward",
                width: 104,
                height: 54,
                selectedKeyCode: $selectedKeyCode,
                hoveredKey: $hoveredKey
            )
        }
    }

    private var modifierRow: some View {
        HStack(spacing: 16) {
            ModifierToggle(label: "⌘ Command", isOn: $modifiers.command, side: $modifiers.commandSide)
            ModifierToggle(label: "⌥ Option", isOn: $modifiers.option, side: $modifiers.optionSide)
            ModifierToggle(label: "⇧ Shift", isOn: $modifiers.shift, side: $modifiers.shiftSide)
            ModifierToggle(label: "⌃ Control", isOn: $modifiers.control, side: $modifiers.controlSide)

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
        .padding(.top, 4)
    }
}

private struct MouseActionButton: View {
    let keyCode: CGKeyCode
    let systemImage: String
    let label: String
    let width: CGFloat
    let height: CGFloat

    @Binding var selectedKeyCode: CGKeyCode?
    @Binding var hoveredKey: CGKeyCode?

    var body: some View {
        Button {
            selectedKeyCode = keyCode
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: label.count > 8 ? 9 : 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: width, height: height)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
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

#Preview {
    MouseVisualView(selectedKeyCode: .constant(nil), modifiers: .constant(ModifierFlags()))
}
