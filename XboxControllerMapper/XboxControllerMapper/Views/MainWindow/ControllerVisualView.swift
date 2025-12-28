import SwiftUI

/// Interactive visual representation of an Xbox controller
struct ControllerVisualView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedButton: ControllerButton?
    var onButtonTap: (ControllerButton) -> Void

    var body: some View {
        ZStack {
            // Controller body
            ControllerBodyShape()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    ControllerBodyShape()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                )

            // Buttons and controls
            VStack(spacing: 0) {
                // Top section: Bumpers and Triggers
                HStack(spacing: 100) {
                    // Left bumper/trigger
                    VStack(spacing: 8) {
                        TriggerButton(button: .leftTrigger, label: "LT", selectedButton: $selectedButton, onTap: onButtonTap)
                        BumperButton(button: .leftBumper, label: "LB", selectedButton: $selectedButton, onTap: onButtonTap)
                    }

                    // Right bumper/trigger
                    VStack(spacing: 8) {
                        TriggerButton(button: .rightTrigger, label: "RT", selectedButton: $selectedButton, onTap: onButtonTap)
                        BumperButton(button: .rightBumper, label: "RB", selectedButton: $selectedButton, onTap: onButtonTap)
                    }
                }
                .padding(.top, 20)

                // Middle section: Sticks, D-pad, Face buttons
                HStack(spacing: 20) {
                    // Left side: Left stick + D-pad
                    VStack(spacing: 30) {
                        // Left stick
                        JoystickView(
                            position: controllerService.leftStick,
                            button: .leftThumbstick,
                            label: "L",
                            selectedButton: $selectedButton,
                            onTap: onButtonTap
                        )

                        // D-pad
                        DPadView(selectedButton: $selectedButton, onTap: onButtonTap)
                    }

                    // Center: Special buttons in diamond layout
                    VStack(spacing: 8) {
                        Spacer()

                        // Top: Share button
                        SpecialButton(button: .share, label: "⬆", selectedButton: $selectedButton, onTap: onButtonTap)

                        // Middle row: View, Xbox, Menu
                        HStack(spacing: 20) {
                            SpecialButton(button: .view, label: "⧉", selectedButton: $selectedButton, onTap: onButtonTap)
                            SpecialButton(button: .xbox, label: "ⓧ", isXboxButton: true, selectedButton: $selectedButton, onTap: onButtonTap)
                            SpecialButton(button: .menu, label: "≡", selectedButton: $selectedButton, onTap: onButtonTap)
                        }

                        Spacer()
                    }
                    .frame(width: 140)

                    // Right side: Face buttons + Right stick
                    VStack(spacing: 30) {
                        // Face buttons (ABXY)
                        FaceButtonsView(selectedButton: $selectedButton, onTap: onButtonTap)

                        // Right stick
                        JoystickView(
                            position: controllerService.rightStick,
                            button: .rightThumbstick,
                            label: "R",
                            selectedButton: $selectedButton,
                            onTap: onButtonTap
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 480, height: 340)
    }

    private func hasMapping(for button: ControllerButton) -> Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }
}

// MARK: - Controller Body Shape

struct ControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height

        // Main body with rounded corners and grip extensions
        path.move(to: CGPoint(x: width * 0.15, y: height * 0.2))

        // Top edge
        path.addLine(to: CGPoint(x: width * 0.85, y: height * 0.2))

        // Right grip
        path.addQuadCurve(
            to: CGPoint(x: width * 0.95, y: height * 0.5),
            control: CGPoint(x: width * 0.95, y: height * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: width * 0.8, y: height * 0.85),
            control: CGPoint(x: width * 0.95, y: height * 0.8)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: width * 0.2, y: height * 0.85))

        // Left grip
        path.addQuadCurve(
            to: CGPoint(x: width * 0.05, y: height * 0.5),
            control: CGPoint(x: width * 0.05, y: height * 0.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: width * 0.15, y: height * 0.2),
            control: CGPoint(x: width * 0.05, y: height * 0.2)
        )

        path.closeSubpath()

        return path
    }
}

// MARK: - Joystick View

struct JoystickView: View {
    let position: CGPoint
    let button: ControllerButton
    let label: String
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    // Movement range for visual feedback
    private let movementRange: CGFloat = 12

    var body: some View {
        ZStack {
            // Outer ring (movement boundary)
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                .frame(width: 74, height: 74)

            // Inner track ring
            Circle()
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                .frame(width: 70, height: 70)

            // Movement trail/glow when stick is moved
            if isStickMoved {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .offset(x: position.x * movementRange * 0.5, y: -position.y * movementRange * 0.5)
            }

            // Joystick thumb
            Button(action: { onTap(button) }) {
                ZStack {
                    // Shadow/depth effect
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 42, height: 42)
                        .offset(x: 1, y: 2)

                    // Main thumb
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 40, height: 40)

                    // Highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isPressed ? 0.1 : 0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    // Label
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .offset(x: position.x * movementRange, y: -position.y * movementRange)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: position)
        }
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var isStickMoved: Bool {
        abs(position.x) > 0.1 || abs(position.y) > 0.1
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed {
            // Darker/more saturated when pressed
            return hasMapping ? Color.blue : Color(white: 0.3)
        } else if hasMapping {
            return .blue.opacity(0.7)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

// MARK: - D-Pad View

struct DPadView: View {
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DPadButton(button: .dpadUp, label: "↑", selectedButton: $selectedButton, onTap: onTap)

            HStack(spacing: 0) {
                DPadButton(button: .dpadLeft, label: "←", selectedButton: $selectedButton, onTap: onTap)

                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 30, height: 30)

                DPadButton(button: .dpadRight, label: "→", selectedButton: $selectedButton, onTap: onTap)
            }

            DPadButton(button: .dpadDown, label: "↓", selectedButton: $selectedButton, onTap: onTap)
        }
    }
}

struct DPadButton: View {
    let button: ControllerButton
    let label: String
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Button(action: { onTap(button) }) {
            Rectangle()
                .fill(buttonColor)
                .frame(width: 30, height: 30)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.0 : 0.2),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? buttonColor : .clear, radius: isPressed ? 4 : 0)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(.plain)
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed {
            return hasMapping ? Color.blue.opacity(0.9) : Color(white: 0.3)
        } else if hasMapping {
            return .blue.opacity(0.7)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

// MARK: - Face Buttons View

struct FaceButtonsView: View {
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    var body: some View {
        VStack(spacing: 5) {
            FaceButton(button: .y, label: "Y", color: .yellow, selectedButton: $selectedButton, onTap: onTap)

            HStack(spacing: 30) {
                FaceButton(button: .x, label: "X", color: .blue, selectedButton: $selectedButton, onTap: onTap)
                FaceButton(button: .b, label: "B", color: .red, selectedButton: $selectedButton, onTap: onTap)
            }

            FaceButton(button: .a, label: "A", color: .green, selectedButton: $selectedButton, onTap: onTap)
        }
    }
}

struct FaceButton: View {
    let button: ControllerButton
    let label: String
    let color: Color
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Button(action: { onTap(button) }) {
            ZStack {
                // Pressed state: show darker inset
                if isPressed {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 38, height: 38)
                }

                Circle()
                    .fill(buttonColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isPressed ? 0.0 : 0.3),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Text(label)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: isPressed ? color : .clear, radius: isPressed ? 8 : 0)
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
        }
        .buttonStyle(.plain)
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed {
            // Darker when pressed
            return color.opacity(0.9)
        } else if hasMapping {
            return color.opacity(0.75)
        } else {
            return color.opacity(0.5)
        }
    }
}

// MARK: - Bumper and Trigger Buttons

struct BumperButton: View {
    let button: ControllerButton
    let label: String
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Button(action: { onTap(button) }) {
            RoundedRectangle(cornerRadius: 8)
                .fill(buttonColor)
                .frame(width: 60, height: 25)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.0 : 0.2),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: isPressed ? buttonColor : .clear, radius: isPressed ? 5 : 0)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed {
            return hasMapping ? Color.blue.opacity(0.9) : Color(white: 0.35)
        } else if hasMapping {
            return .blue.opacity(0.7)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

struct TriggerButton: View {
    let button: ControllerButton
    let label: String
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        Button(action: { onTap(button) }) {
            RoundedRectangle(cornerRadius: 4)
                .fill(buttonColor)
                .frame(width: 50, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(triggerValue > 0.1 ? 0.0 : 0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    VStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)

                        // Pressure indicator
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .overlay(
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(triggerValue > 0.5 ? Color.orange : Color.white)
                                        .frame(width: geo.size.width * CGFloat(triggerValue))
                                        .animation(.easeOut(duration: 0.1), value: triggerValue)
                                }
                            )
                    }
                )
                .shadow(color: isPressed ? buttonColor.opacity(0.6) : .clear, radius: isPressed ? 5 : 0)
                .scaleEffect(y: isPressed ? 0.9 : 1.0, anchor: .top)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
    }

    private var triggerValue: Float {
        switch button {
        case .leftTrigger:
            return controllerService.leftTriggerValue
        case .rightTrigger:
            return controllerService.rightTriggerValue
        default:
            return 0
        }
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed || triggerValue > 0.1 {
            // Darken based on trigger pressure
            let pressAmount = max(triggerValue, isPressed ? 0.5 : 0)
            return hasMapping
                ? Color.blue.opacity(0.6 + Double(pressAmount) * 0.4)
                : Color(white: 0.4 - Double(pressAmount) * 0.15)
        } else if hasMapping {
            return .blue.opacity(0.7)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

// MARK: - Special Buttons

struct SpecialButton: View {
    let button: ControllerButton
    let label: String
    var isXboxButton: Bool = false
    @Binding var selectedButton: ControllerButton?
    var onTap: (ControllerButton) -> Void

    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    private var size: CGFloat { isXboxButton ? 30 : 24 }

    var body: some View {
        Button(action: { onTap(button) }) {
            ZStack {
                // Glow effect when pressed
                if isPressed {
                    Circle()
                        .fill(buttonColor.opacity(0.4))
                        .frame(width: size + 8, height: size + 8)
                        .blur(radius: 4)
                }

                Circle()
                    .fill(buttonColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isPressed ? 0.0 : 0.25),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Text(label)
                            .font(.system(size: isXboxButton ? 14 : 10, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(isPressed ? 0.88 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
        }
        .buttonStyle(.plain)
    }

    private var isPressed: Bool {
        controllerService.activeButtons.contains(button)
    }

    private var hasMapping: Bool {
        profileManager.activeProfile?.buttonMappings[button] != nil
    }

    private var buttonColor: Color {
        if selectedButton == button {
            return .accentColor
        } else if isPressed {
            return isXboxButton ? .green.opacity(0.9) : (hasMapping ? Color.blue.opacity(0.9) : Color(white: 0.3))
        } else if hasMapping {
            return .blue.opacity(0.7)
        } else if isXboxButton {
            return .green.opacity(0.6)
        } else {
            return .gray.opacity(0.6)
        }
    }
}

#Preview {
    ControllerVisualView(selectedButton: .constant(nil)) { _ in }
        .environmentObject(ControllerService())
        .environmentObject(ProfileManager())
}
