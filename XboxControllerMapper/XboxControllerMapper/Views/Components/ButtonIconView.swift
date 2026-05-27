import SwiftUI

/// Nostalgic Xbox 360-inspired "Jewel" buttons with a modern macOS glass finish.
/// Automatically shows PlayStation symbols when isDualSense is true.
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    let isDualSense: Bool
    let isNintendo: Bool
    let isSteamController: Bool
    let showDirectionalArrows: Bool

    init(
        button: ControllerButton,
        isPressed: Bool = false,
        isDualSense: Bool = false,
        isNintendo: Bool = false,
        isSteamController: Bool = false,
        showDirectionalArrows: Bool = false
    ) {
        self.button = button
        self.isPressed = isPressed
        self.isDualSense = isDualSense
        self.isNintendo = isNintendo
        self.isSteamController = isSteamController
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
        .accessibilityHidden(true)
    }
    
    // MARK: - Shapes & Metrics

    /// Maximum icon width across all button types (excluding directional arrows mode).
    /// Used by stats view to create a fixed-width column so bars align.
    static var maxIconWidth: CGFloat {
        ControllerButton.allCases
            .map { ButtonIconView(button: $0).width }
            .max() ?? 48
    }

    private var baseShape: GroupShape {
        GroupShape(isCircle: isCircle, cornerRadius: 5) // Slightly rounder corners for 360 vibe
    }
    
    private var isCircle: Bool {
        // Mic mute and touchpad tap gestures are circular like special buttons
        // Touchpad press buttons use rounded square
        if button == .micMute || button == .touchpadTap || button == .touchpadTwoFingerTap ||
            button == .leftTouchpadTap || button == .rightTouchpadTap { return true }
        if button == .touchpadButton || button == .touchpadTwoFingerButton ||
            button == .leftTouchpadButton || button == .rightTouchpadButton { return false }
        // Touchpad region buttons follow the same convention: Touch = circle,
        // Click = rounded square. Distinguishes them at a glance.
        if let trigger = button.touchpadQuadrantTrigger {
            return trigger == .touch
        }
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return true
        default: return false
        }
    }

    var width: CGFloat {
        // Directional stick icons need more room
        if showDirectionalArrows { return 36 }
        // Mic mute and single touchpad tap use same width as special buttons (circular)
        if button == .micMute || button == .touchpadTap { return 28 }
        // Two-finger tap is slightly wider to fit "2" + icon
        if button == .touchpadTwoFingerTap { return 32 }
        // Touchpad press buttons are rounded squares (same size for 1 and 2 finger)
        if button == .touchpadButton || button == .touchpadTwoFingerButton { return 32 }
        if button == .leftTouchpadButton || button == .rightTouchpadButton { return 34 }
        if button == .leftTouchpadTap || button == .rightTouchpadTap { return 34 }
        // Touchpad region buttons match the touchpadButton/touchpadTap sizing.
        if let trigger = button.touchpadQuadrantTrigger {
            return trigger == .click ? 32 : 28
        }
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
        if button == .touchpadButton || button == .touchpadTwoFingerButton ||
            button == .leftTouchpadButton || button == .rightTouchpadButton { return width }
        // Touchpad region click buttons are square (height == width).
        if button.touchpadQuadrantTrigger == .click { return width }
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
        } else if isSteamController {
            switch button {
            case .xbox: return Color(white: 0.82)
            case .share: return Color(white: 0.26)
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return Color(white: 0.2)
            case .leftThumbstick, .rightThumbstick: return Color(white: 0.24)
            default: return Color(white: 0.16)
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
                Text(button.shortLabel(forDualSense: true, forNintendo: false))
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
            } else if button == .leftTouchpadButton || button == .rightTouchpadButton {
                touchpadSideGlyph(icon: "hand.point.up.left")
            } else if button == .leftTouchpadTap || button == .rightTouchpadTap {
                touchpadSideGlyph(icon: "hand.tap")
            } else if isSteamController && button == .xbox {
                SteamLogoMark(foregroundColor: isPressed ? .white : Color(white: 0.25))
                    .frame(width: 15, height: 15)
            } else if isSteamController && button == .share {
                Image(systemName: "ellipsis")
                    .font(.system(size: fontSize + 1, weight: .heavy))
                    .foregroundColor(.white.opacity(0.95))
            } else if let side = button.steamTouchpadSide, let region = button.touchpadRegion {
                steamQuadrantGlyph(side: side, region: region)
                    .foregroundColor(.white.opacity(0.95))
            } else if let region = button.touchpadRegion {
                // Touchpad region indicator: a small 2×2 grid with the active
                // quadrant filled. Much more legible at button-tile size than
                // diagonal arrows, and instantly readable as "this is one of
                // four quarters."
                quadrantGlyph(for: region)
                    .foregroundColor(.white.opacity(0.95))
            } else if button == .leftFunction || button == .rightFunction {
                // Function buttons: show "LFn" or "RFn" text (similar to L1/R1)
                Text(button.shortLabel(forDualSense: isDualSense, forNintendo: isNintendo))
                    .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            } else if let systemImage = isNintendo ? button.systemImageName(forNintendo: true) : button.systemImageName(forDualSense: isDualSense) {
                Image(systemName: systemImage)
                    .foregroundColor(.white.opacity(0.95))
            } else {
                Text(button.shortLabel(forDualSense: isDualSense, forNintendo: isNintendo))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .font(.system(size: fontSize, weight: .bold))
    }

    @ViewBuilder
    private func steamQuadrantGlyph(side: SteamTouchpadSide, region: TouchpadRegion) -> some View {
        HStack(spacing: 2) {
            Text(side.shortLabel)
                .font(.system(size: 7, weight: .black, design: .rounded))
            quadrantGlyph(for: region)
        }
    }

    @ViewBuilder
    private func touchpadSideGlyph(icon: String) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: fontSize - 3, weight: .medium))
            Text(button == .leftTouchpadButton || button == .leftTouchpadTap ? "L" : "R")
                .font(.system(size: fontSize - 2, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.95))
    }

    private var stickLabel: String {
        switch button {
        case .rightThumbstick: return "R"
        case .leftThumbstick: return "L"
        default: return ""
        }
    }

    /// 2×2 grid where the active quadrant is filled; the other three are
    /// drawn as faint outlines. Sized to fit naturally inside the existing
    /// 28-32pt button shape.
    @ViewBuilder
    private func quadrantGlyph(for region: TouchpadRegion) -> some View {
        let cellSize: CGFloat = 6
        let spacing: CGFloat = 1.5
        let cornerRadius: CGFloat = 1.2

        let isTopLeftFilled = region == .topLeft
        let isTopRightFilled = region == .topRight
        let isBottomLeftFilled = region == .bottomLeft
        let isBottomRightFilled = region == .bottomRight

        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                quadrantCell(filled: isTopLeftFilled, size: cellSize, cornerRadius: cornerRadius)
                quadrantCell(filled: isTopRightFilled, size: cellSize, cornerRadius: cornerRadius)
            }
            HStack(spacing: spacing) {
                quadrantCell(filled: isBottomLeftFilled, size: cellSize, cornerRadius: cornerRadius)
                quadrantCell(filled: isBottomRightFilled, size: cellSize, cornerRadius: cornerRadius)
            }
        }
    }

    @ViewBuilder
    private func quadrantCell(filled: Bool, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if filled {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                .frame(width: size, height: size)
        }
    }
}

struct SteamLogoMark: View {
    var foregroundColor: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let main = size * 0.62
            let small = size * 0.25
            let lineWidth = max(1.4, size * 0.11)

            ZStack {
                Circle()
                    .stroke(foregroundColor, lineWidth: lineWidth)
                    .frame(width: main, height: main)
                    .offset(x: -size * 0.11, y: size * 0.10)

                Path { path in
                    path.move(to: CGPoint(x: size * 0.48, y: size * 0.39))
                    path.addLine(to: CGPoint(x: size * 0.68, y: size * 0.24))
                }
                .stroke(foregroundColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Circle()
                    .stroke(foregroundColor, lineWidth: lineWidth)
                    .frame(width: small, height: small)
                    .offset(x: size * 0.22, y: -size * 0.22)
            }
            .frame(width: size, height: size)
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
