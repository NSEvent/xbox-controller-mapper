import SwiftUI

/// Authentic Xbox-style button icon
struct ButtonIconView: View {
    let button: ControllerButton
    let isPressed: Bool
    
    init(button: ControllerButton, isPressed: Bool = false) {
        self.button = button
        self.isPressed = isPressed
    }
    
    var body: some View {
        ZStack {
            if isCircle {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: width, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
                    .frame(width: width, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
            
            Text(button.shortLabel)
                .font(.system(size: fontSize, weight: .black))
                .foregroundColor(foregroundColor)
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
    }
    
    private var isCircle: Bool {
        switch button.category {
        case .face, .special, .thumbstick: return true
        default: return false
        }
    }
    
    private var width: CGFloat {
        switch button.category {
        case .face, .special, .thumbstick: return 24
        case .dpad: return 24
        case .bumper, .trigger: return 36
        }
    }
    
    private var fontSize: CGFloat {
        switch button.category {
        case .face: return 12
        case .special: return 10
        case .dpad: return 12
        default: return 9
        }
    }
    
    private var backgroundColor: Color {
        if isPressed { return Color.accentColor }
        
        switch button {
        case .a: return .green
        case .b: return .red
        case .x: return .blue
        case .y: return .yellow
        case .xbox: return .green.opacity(0.8)
        default: return Color(white: 0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch button {
        case .a, .b, .x, .y: return .white
        case .xbox: return .white
        default: return .white
        }
    }
}
