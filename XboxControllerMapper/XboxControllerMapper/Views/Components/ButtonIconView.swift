import SwiftUI

/// Nostalgic Xbox 360-inspired "Jewel" buttons with a modern macOS glass finish.
/// Automatically shows PlayStation symbols when isDualSense is true.
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    let isDualSense: Bool

    init(button: ControllerButton, isPressed: Bool = false, isDualSense: Bool = false) {
        self.button = button
        self.isPressed = isPressed
        self.isDualSense = isDualSense
    }
    
    var body: some View {
        ZStack {
            // 1. Drop Shadow (Physical Depth)
            baseShape
                .fill(Color.black.opacity(0.25))
                .offset(y: isPressed ? 1 : 2.5)
                .blur(radius: 2)
            
            // 2. Base Jewel Color
            baseShape
                .fill(jewelGradient)
            
            // 3. Darker Rim (Bezel)
            baseShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.0), .black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            
            // 4. Glassy Dome Highlight (The "Aero" look)
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
            
            // 5. Crisp Specular Edge (Top light catch)
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

            // 6. Content (Symbol/Text) - Floating inside the jewel
            contentView
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
        }
        .drawingGroup()
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isPressed)
    }
    
    // MARK: - Shapes & Metrics
    
    private var baseShape: GroupShape {
        GroupShape(isCircle: isCircle, cornerRadius: 5) // Slightly rounder corners for 360 vibe
    }
    
    private var isCircle: Bool {
        // Mic mute is circular like special buttons
        if button == .micMute { return true }
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return true
        default: return false
        }
    }

    private var width: CGFloat {
        // Mic mute uses same width as special buttons (circular)
        if button == .micMute { return 28 }
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        case .touchpad: return 48  // Wider for touchpad
        }
    }

    private var height: CGFloat {
        isCircle ? width : 22
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
            switch button {
            case .a: return Color(red: 0.4, green: 0.8, blue: 0.2) // Vibrant Green
            case .b: return Color(red: 0.9, green: 0.2, blue: 0.2) // Jewel Red
            case .x: return Color(red: 0.1, green: 0.4, blue: 0.9) // Deep Blue
            case .y: return Color(red: 1.0, green: 0.7, blue: 0.0) // Amber/Gold
            case .xbox: return Color(white: 0.85) // Silver/Chrome
            case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return Color(white: 0.25) // Dark Grey Plastic
            case .leftThumbstick, .rightThumbstick: return Color(white: 0.3)
            default: return Color(white: 0.2) // Bumpers/Triggers - Dark Grey/Black
            }
        }
    }

    /// Symbol color for PlayStation face buttons (colored shapes on dark background)
    private var playstationSymbolColor: Color {
        switch button {
        case .a: return Color(red: 0.55, green: 0.70, blue: 0.95) // Cross - Light Blue
        case .b: return Color(red: 1.0, green: 0.45, blue: 0.50)  // Circle - Red/Pink
        case .x: return Color(red: 0.90, green: 0.55, blue: 0.75) // Square - Pink/Magenta
        case .y: return Color(red: 0.45, green: 0.85, blue: 0.75) // Triangle - Teal/Cyan
        default: return .white
        }
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
            // For DualSense face buttons, use colored text symbols on dark background
            if isDualSense && button.category == .face {
                Text(button.shortLabel(forDualSense: true))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(playstationSymbolColor)
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