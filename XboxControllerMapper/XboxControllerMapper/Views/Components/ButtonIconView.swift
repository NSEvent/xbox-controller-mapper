import SwiftUI

/// Modern macOS-inspired button icon
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    
    init(button: ControllerButton, isPressed: Bool = false) {
        self.button = button
        self.isPressed = isPressed
    }
    
    var body: some View {
        ZStack {
            // Background
            if isCircle {
                Circle()
                    .fill(backgroundStyle)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .frame(width: width, height: width)
                    .shadow(color: shadowColor, radius: isPressed ? 2 : 0, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .frame(width: width, height: 24)
                    .shadow(color: shadowColor, radius: isPressed ? 2 : 0, x: 0, y: 1)
            }
            
            // Content (Icon or Text)
            if let systemImage = button.systemImageName {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(contentColor)
            } else {
                Text(button.shortLabel)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(contentColor)
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
    
    // MARK: - Styles
    
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
    
    private var fontSize: CGFloat {
        switch button.category {
        case .face: return 14
        case .special: return 12
        case .dpad: return 12
        case .thumbstick: return 10
        default: return 11
        }
    }
    
    private var identityColor: Color {
        switch button {
        case .a: return .green
        case .b: return .red
        case .x: return .blue
        case .y: return .orange // Yellow is often too light on white, Orange is better/closer or standard Yellow
        case .xbox: return .primary
        default: return .secondary
        }
    }
    
    private var backgroundStyle: AnyShapeStyle {
        if isPressed {
            if button.category == .face {
                return AnyShapeStyle(identityColor.gradient)
            } else {
                return AnyShapeStyle(Color.accentColor.gradient)
            }
        } else {
            // Unpressed: Subtle tint or material
            if button.category == .face {
                return AnyShapeStyle(identityColor.opacity(0.1))
            } else {
                return AnyShapeStyle(Color.primary.opacity(0.05))
            }
        }
    }
    
    private var borderColor: Color {
        if isPressed {
            return .clear
        } else {
            if button.category == .face {
                return identityColor.opacity(0.3)
            } else {
                return Color.primary.opacity(0.1)
            }
        }
    }
    
    private var contentColor: Color {
        if isPressed {
            return .white
        } else {
            if button.category == .face {
                return identityColor
            } else {
                return .primary.opacity(0.8)
            }
        }
    }
    
    private var shadowColor: Color {
        if isPressed {
            return (button.category == .face ? identityColor : Color.accentColor).opacity(0.5)
        } else {
            return Color.clear
        }
    }
}