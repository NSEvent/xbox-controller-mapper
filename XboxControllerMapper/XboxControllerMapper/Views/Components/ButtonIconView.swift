import SwiftUI

/// Nostalgic Xbox 360-inspired "Jewel" buttons with a modern macOS glass finish.
/// Automatically shows PlayStation symbols when isDualSense is true.
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    let isDualSense: Bool
    let showDirectionalArrows: Bool

    init(button: ControllerButton, isPressed: Bool = false, isDualSense: Bool = false, showDirectionalArrows: Bool = false) {
        self.button = button
        self.isPressed = isPressed
        self.isDualSense = isDualSense
        self.showDirectionalArrows = showDirectionalArrows
    }
    
    var body: some View {
        ZStack {
            // 1. Base Jewel Color with shadow
            baseShape
                .fill(jewelGradient)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: isPressed ? 1 : 2.5)

            // 2. Darker Rim (Bezel)
            baseShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.0), .black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            // 3. Glassy Dome Highlight (The "Aero" look)
            baseShape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.65), location: 0),
                            .init(color: .white.opacity(0.15), location: 0.45), // Horizon line
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.1), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(1.5) // Slight inset to create the "encased" look

            // 4. Crisp Specular Edge (Top light catch)
            baseShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)

            // 5. Content (Symbol/Text) - Floating inside the jewel
            contentView
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isPressed)
    }
    
    // MARK: - Shapes & Metrics
    
    private var baseShape: GroupShape {
        GroupShape(isCircle: isCircle, cornerRadius: 5) // Slightly rounder corners for 360 vibe
    }
    
    private var isCircle: Bool {
        // Mic mute and touchpad tap gestures are circular like special buttons
        // Touchpad press buttons use rounded square
        if button == .micMute || button == .touchpadTap || button == .touchpadTwoFingerTap { return true }
        if button == .touchpadButton || button == .touchpadTwoFingerButton { return false }
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return true
        default: return false
        }
    }

    private var width: CGFloat {
        // Directional stick icons need more room
        if showDirectionalArrows { return 36 }
        // Mic mute and single touchpad tap use same width as special buttons (circular)
        if button == .micMute || button == .touchpadTap { return 28 }
        // Two-finger tap is slightly wider to fit "2" + icon
        if button == .touchpadTwoFingerTap { return 32 }
        // Touchpad press buttons are rounded squares (same size for 1 and 2 finger)
        if button == .touchpadButton || button == .touchpadTwoFingerButton { return 32 }
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        case .touchpad: return 48  // Wider for touchpad click
        case .paddle: return 36  // Edge paddles and function buttons
        }
    }

    private var height: CGFloat {
        // Directional stick icons are circular
        if showDirectionalArrows { return 36 }
        // Touchpad press buttons are square
        if button == .touchpadButton || button == .touchpadTwoFingerButton { return width }
        return isCircle ? width : 22
    }
    
    // MARK: - Colors & Gradients
    
    private var jewelGradient: LinearGradient {
        let base = baseColor
        // If pressed, the light goes away/darkens
        let topColor = isPressed ? base.opacity(0.8) : base
        let bottomColor = isPressed ? base.opacity(0.6) : base.opacity(0.8)
        
        return LinearGradient(
            colors: [topColor, bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var baseColor: Color {
        // Use PlayStation style for DualSense face buttons (dark background), standard colors for others
        if isDualSense {
            switch button {
            // PlayStation face buttons: dark/black background (symbols are colored)
            case .a, .b, .x, .y: return Color(white: 0.12)
            // Other buttons use standard dark grey like Xbox (not black)
            case .xbox: return Color(white: 0.3)
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return Color(white: 0.25)
            case .leftThumbstick, .rightThumbstick: return Color(white: 0.3)
            default: return Color(white: 0.2) // Bumpers/Triggers
            }
        } else {
            // Vibrant "Jewel" colors inspired by Xbox 360 controller
            if let xboxColor = ButtonColors.xbox(button) {
                return xboxColor
            }
            switch button {
            case .xbox: return Color(white: 0.85) // Silver/Chrome
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return Color(white: 0.25) // Dark Grey Plastic
            case .leftThumbstick, .rightThumbstick: return Color(white: 0.3)
            default: return Color(white: 0.2) // Bumpers/Triggers - Dark Grey/Black
            }
        }
    }

    /// Symbol color for PlayStation face buttons (colored shapes on dark background)
    private var playstationSymbolColor: Color {
        ButtonColors.playStation(button) ?? .white
    }
    
    // MARK: - Content
    
    private var fontSize: CGFloat {
        switch button.category {
        case .face: return 14
        case .special: return 11
        case .dpad: return 11
        case .thumbstick: return 10
        default: return 10
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            if showDirectionalArrows {
                ZStack {
                    // Directional Arrows (Background)
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: fontSize + 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Stick Label (Foreground)
                    Text(stickLabel)
                        .font(.system(size: fontSize + 2, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 1, x: 0, y: 1)
                }
            } else if isDualSense && button.category == .face {
                Text(button.shortLabel(forDualSense: true))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(playstationSymbolColor)
            } else if button == .touchpadTwoFingerButton {
                // Two-finger press: pointing finger icon + "2"
                HStack(spacing: 1) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: fontSize - 2, weight: .medium))
                    Text("2")
                        .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
            } else if button == .touchpadTwoFingerTap {
                // Two-finger tap: tap finger icon + "2"
                HStack(spacing: 1) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: fontSize - 2, weight: .medium))
                    Text("2")
                        .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
            } else if button == .leftFunction {
                // Left function button: "L" + Fn icon
                HStack(spacing: 2) {
                    Text("L")
                        .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                    Image(systemName: "button.horizontal.top.press")
                        .font(.system(size: fontSize - 2, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.95))
            } else if button == .rightFunction {
                // Right function button: Fn icon + "R"
                HStack(spacing: 2) {
                    Image(systemName: "button.horizontal.top.press")
                        .font(.system(size: fontSize - 2, weight: .medium))
                    Text("R")
                        .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
            } else if let systemImage = button.systemImageName(forDualSense: isDualSense) {
                Image(systemName: systemImage)
                    .foregroundColor(.white.opacity(0.95))
            } else {
                Text(button.shortLabel(forDualSense: isDualSense))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .font(.system(size: fontSize, weight: .bold))
    }
    
    private var stickLabel: String {
        switch button {
        case .rightThumbstick: return "R"
        case .leftThumbstick: return "L"
        default: return ""
        }
    }
}

// MARK: - Helper Shape

struct GroupShape: InsettableShape {
    var isCircle: Bool
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0
    
    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        if isCircle {
            return Circle().path(in: insetRect)
        } else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: insetRect)
        }
    }
    
    func inset(by amount: CGFloat) -> GroupShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}