import SwiftUI

/// Premium, high-fidelity button component with a modern "glassy" aesthetic.
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    
    init(button: ControllerButton, isPressed: Bool = false) {
        self.button = button
        self.isPressed = isPressed
    }
    
    var body: some View {
        ZStack {
            // 1. Drop Shadow (Physical Depth)
            baseShape
                .fill(.black)
                .blur(radius: 2)
                .offset(y: 2)
                .opacity(0.4)
            
            // 2. Main Body (Gradient Surface)
            baseShape
                .fill(surfaceGradient)
                .overlay(
                    // 3. Specular Highlight / Glassy Rim
                    baseShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.05), .black.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: glowColor.opacity(isPressed ? 0.6 : 0.0), radius: 8, x: 0, y: 0) // Active Glow

            // 4. Inner Content (Symbol/Text)
            contentView
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1) // Embossed text look
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
    }
    
    // MARK: - Shapes & Metrics
    
    private var baseShape: some InsettableShape {
        // Using AnyInsettableShape wrapper type erasure pattern or simple conditional view
        // For simplicity in body, we'll return a Shape that conforms to InsettableShape?
        // Actually, SwiftUI's type system handles this better with ViewBuilder but .fill needs a Shape.
        // Let's wrap the shape logic in a helper View since we can't easily return 'some InsettableShape' conditionally.
        // Wait, for standard shapes:
        GroupShape(isCircle: isCircle, cornerRadius: 6)
    }
    
    private var isCircle: Bool {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return true
        default: return false
        }
    }
    
    private var width: CGFloat {
        switch button.category {
        case .face, .special, .thumbstick, .dpad: return 30
        case .bumper, .trigger: return 44
        }
    }
    
    private var height: CGFloat {
        isCircle ? width : 26
    }
    
    // MARK: - Appearance Logic
    
    private var surfaceGradient: LinearGradient {
        let base = baseColor
        if isPressed {
            // "Lit up" state
            return LinearGradient(
                colors: [base.opacity(0.9), base],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // "Glassy" unpressed state
            // Use a dark, sleek look with a hint of color, OR a full colored button.
            // Let's go for "Modern Dark" with colored accents for symbols, OR "Colored Crystal".
            // "Sexier" usually means dark gray/black with vibrant accents for the letters.
            
            if button.category == .face {
                // For face buttons, let's try the "Black Crystal" look with colored glyphs
                return LinearGradient(
                    colors: [
                        Color(white: 0.25),
                        Color(white: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [
                        Color(white: 0.25),
                        Color(white: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private var baseColor: Color {
        switch button {
        case .a: return .green
        case .b: return .red
        case .x: return .blue
        case .y: return .orange
        case .xbox: return .white
        default: return .accentColor
    }
    }
    
    private var glowColor: Color {
        return baseColor
    }
    
    private var contentColor: Color {
        if isPressed {
            return .white
        }
        
        // If unpressed, face buttons show their iconic color
        if button.category == .face {
            return baseColor
        }
        return .white.opacity(0.9)
    }
    
    private var fontSize: CGFloat {
        switch button.category {
        case .face: return 15
        case .special: return 12
        case .dpad: return 13
        case .thumbstick: return 11
        default: return 11
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if let systemImage = button.systemImageName {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(contentColor)
        } else {
            Text(button.shortLabel)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(contentColor)
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
