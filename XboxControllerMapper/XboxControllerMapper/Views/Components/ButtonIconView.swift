import SwiftUI

/// Modern Xbox Series X/S style button component.
/// Features a clean, satin-matte finish with bold typography and vibrant, accurate colors.
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    
    init(button: ControllerButton, isPressed: Bool = false) {
        self.button = button
        self.isPressed = isPressed
    }
    
    var body: some View {
        ZStack {
            // 1. Shadow (Soft, diffuse, modern)
            baseShape
                .fill(Color.black)
                .offset(y: isPressed ? 1 : 2)
                .blur(radius: isPressed ? 1 : 3)
                .opacity(0.3)
            
            // 2. Base Material (Satin finish)
            baseShape
                .fill(buttonGradient)
                .overlay(
                    // Subtle rim light/bevel
                    baseShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.1), .black.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )

            // 3. Content
            contentView
                .shadow(color: .black.opacity(0.1), radius: 0, x: 0, y: 1) // Very subtle text inset
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
    
    // MARK: - Shapes & Metrics
    
    private var baseShape: GroupShape {
        // Series X buttons are quite round, bumpers are rounded rects
        GroupShape(isCircle: isCircle, cornerRadius: 4)
    }
    
    private var isCircle: Bool {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return true
        default: return false
        }
    }
    
    private var width: CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 28
        case .bumper, .trigger: return 42
        }
    }
    
    private var height: CGFloat {
        isCircle ? width : 22
    }
    
    // MARK: - Colors & Gradients
    
    private var buttonGradient: LinearGradient {
        let base = baseColor
        // Series X UI is often flat, but hardware has a satin sheen.
        // We'll use a very subtle gradient to imply the physical button curve.
        return LinearGradient(
            colors: [
                base.opacity(isPressed ? 0.8 : 1.0),
                base.opacity(isPressed ? 0.6 : 0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var baseColor: Color {
        // Authentic Xbox Series X Colors (Approximated from UI/Marketing)
        switch button {
        case .a: return Color(red: 0.06, green: 0.49, blue: 0.06) // Deep Xbox Green
        case .b: return Color(red: 0.82, green: 0.18, blue: 0.18) // Red
        case .x: return Color(red: 0.00, green: 0.35, blue: 0.73) // Blue
        case .y: return Color(red: 0.96, green: 0.70, blue: 0.00) // Yellow
        case .view, .menu, .share: return Color(white: 0.2) // Dark Grey (Matte Black controller)
        case .xbox: return Color(white: 0.9) // White/Silver Lit
        default: return Color(white: 0.15) // Bumpers/Triggers - Almost Black
        }
    }
    
    private var contentColor: Color {
        switch button {
        case .xbox: return .black.opacity(0.8)
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
            if let systemImage = button.systemImageName {
                Image(systemName: systemImage)
            } else {
                Text(button.shortLabel)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
            }
        }
        .foregroundColor(contentColor)
        .font(.system(size: fontSize, weight: .semibold))
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
