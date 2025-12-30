import SwiftUI
import GameController

/// Interactive visual representation of an Xbox controller with a professional Reference Page layout
struct ControllerVisualView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedButton: ControllerButton?
    var onButtonTap: (ControllerButton) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Column: Shoulder and Left-side inputs
            VStack(alignment: .trailing, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: [.leftTrigger, .leftBumper])
                referenceGroup(title: "Movement", buttons: [.leftThumbstick])
                referenceGroup(title: "D-Pad", buttons: [.dpadUp, .dpadLeft, .dpadRight, .dpadDown])
            }
            .frame(width: 220)
            .padding(.trailing, 20)

            // Center Column: Controller Graphic and System Buttons
            VStack(spacing: 30) {
                ZStack {
                    ControllerBodyShape()
                        .fill(LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .frame(width: 320, height: 220)

                    // Compact Controller Overlay (Just icons, no labels)
                    VStack(spacing: 15) {
                        HStack(spacing: 140) {
                            miniTrigger(.leftTrigger, label: "LT", value: controllerService.leftTriggerValue)
                            miniTrigger(.rightTrigger, label: "RT", value: controllerService.rightTriggerValue)
                        }
                        
                        HStack(spacing: 120) {
                            miniBumper(.leftBumper, label: "LB")
                            miniBumper(.rightBumper, label: "RB")
                        }
                        .offset(y: -5) // Tweak vertical position to sit nicely under triggers
                        
                        HStack(spacing: 40) {
                            miniStick(.leftThumbstick, pos: controllerService.leftStick)
                            
                            VStack(spacing: 6) {
                                miniCircle(.xbox, size: 22)
                                
                                // Battery Status
                                if controllerService.isConnected {
                                    BatteryView(level: controllerService.batteryLevel, state: controllerService.batteryState)
                                        .frame(height: 10)
                                }

                                HStack(spacing: 12) {
                                    miniCircle(.view, size: 14)
                                    miniCircle(.menu, size: 14)
                                }
                                miniCircle(.share, size: 10)
                            }
                            
                            miniFaceButtons()
                        }
                        
                        HStack(spacing: 80) {
                            miniDPad()
                            miniStick(.rightThumbstick, pos: controllerService.rightStick)
                        }
                    }
                }
                
                // System Buttons Reference
                HStack(spacing: 20) {
                    VStack(alignment: .trailing) {
                        referenceRow(for: .view)
                        referenceRow(for: .xbox)
                    }
                    VStack(alignment: .leading) {
                        referenceRow(for: .menu)
                        referenceRow(for: .share)
                    }
                }
            }
            .frame(width: 350)

            // Right Column: Face buttons and Right-side inputs
            VStack(alignment: .leading, spacing: 16) {
                referenceGroup(title: "Shoulder", buttons: [.rightTrigger, .rightBumper])
                referenceGroup(title: "Actions", buttons: [.y, .b, .a, .x])
                referenceGroup(title: "Camera", buttons: [.rightThumbstick])
            }
            .frame(width: 220)
            .padding(.leading, 20)
        }
        .padding(20)
    }

    // MARK: - Reference UI Components

    @ViewBuilder
    private func referenceGroup(title: String, buttons: [ControllerButton]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(buttons) { button in
                    referenceRow(for: button)
                }
            }
        }
    }

    @ViewBuilder
    private func referenceRow(for button: ControllerButton) -> some View {
        Button(action: { onButtonTap(button) }) {
            HStack(spacing: 12) {
                // Button Indicator (Authentic Xbox Styling)
                ButtonIconView(button: button, isPressed: isPressed(button))

                // Shortcut Labels Container
                HStack {
                    if let mapping = mapping(for: button) {
                        MappingLabelView(
                            mapping: mapping,
                            font: .system(size: 15, weight: .semibold, design: .rounded)
                        )
                    } else {
                        Text("Unmapped")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))
                            .italic()
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedButton == button ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: selectedButton == button ? 2 : 1)
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini Controller Helpers

    private func miniTrigger(_ button: ControllerButton, label: String, value: Float) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 34, height: 14)
            
            // Fill based on pressure
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor)
                .frame(width: 34, height: 14 * CGFloat(value))
                .opacity(isPressed(button) ? 1.0 : 0.6)
            
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.1), radius: 1)
    }

    private func miniBumper(_ button: ControllerButton, label: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isPressed(button) ? Color.accentColor : Color.gray.opacity(0.3))
            .frame(width: 34, height: 10)
            .overlay(
                Text(label)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func miniStick(_ button: ControllerButton, pos: CGPoint) -> some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.2)).frame(width: 30, height: 30)
            Circle()
                .fill(isPressed(button) ? Color.accentColor : Color.gray)
                .frame(width: 20, height: 20)
                .offset(x: pos.x * 5, y: -pos.y * 5)
        }
    }

    private func miniCircle(_ button: ControllerButton, size: CGFloat) -> some View {
        Circle()
            .fill(isPressed(button) ? Color.accentColor : Color.gray.opacity(0.5))
            .frame(width: size, height: size)
    }

    private func miniFaceButtons() -> some View {
        ZStack {
            miniCircle(.y, size: 12).offset(y: -12)
            miniCircle(.a, size: 12).offset(y: 12)
            miniCircle(.x, size: 12).offset(x: -12)
            miniCircle(.b, size: 12).offset(x: 12)
        }
        .frame(width: 40, height: 40)
    }

    private func miniDPad() -> some View {
        ZStack {
            // Vertical bar background
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 8, height: 24)
            // Horizontal bar background
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 24, height: 8)
            
            // Active states overlay
            if isPressed(.dpadUp) {
                Rectangle().fill(Color.accentColor).frame(width: 8, height: 10).offset(y: -7)
            }
            if isPressed(.dpadDown) {
                Rectangle().fill(Color.accentColor).frame(width: 8, height: 10).offset(y: 7)
            }
            if isPressed(.dpadLeft) {
                Rectangle().fill(Color.accentColor).frame(width: 10, height: 8).offset(x: -7)
            }
            if isPressed(.dpadRight) {
                Rectangle().fill(Color.accentColor).frame(width: 10, height: 8).offset(x: 7)
            }
        }
    }

    // MARK: - Helpers

    private func isPressed(_ button: ControllerButton) -> Bool {
        controllerService.activeButtons.contains(button)
    }

    private func mapping(for button: ControllerButton) -> KeyMapping? {
        profileManager.activeProfile?.buttonMappings[button]
    }
}

// MARK: - Controller Body Shape

struct ControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: width * 0.2, y: height * 0.15))
        path.addCurve(to: CGPoint(x: width * 0.8, y: height * 0.15), control1: CGPoint(x: width * 0.35, y: height * 0.05), control2: CGPoint(x: width * 0.65, y: height * 0.05))
        path.addQuadCurve(to: CGPoint(x: width * 0.95, y: height * 0.35), control: CGPoint(x: width * 0.98, y: height * 0.2))
        path.addCurve(to: CGPoint(x: width * 0.75, y: height * 0.9), control1: CGPoint(x: width * 1.0, y: height * 0.6), control2: CGPoint(x: width * 0.9, y: height * 0.85))
        path.addQuadCurve(to: CGPoint(x: width * 0.25, y: height * 0.9), control: CGPoint(x: width * 0.5, y: height * 0.75))
        path.addCurve(to: CGPoint(x: width * 0.05, y: height * 0.35), control1: CGPoint(x: width * 0.1, y: height * 0.85), control2: CGPoint(x: width * 0.0, y: height * 0.6))
        path.addQuadCurve(to: CGPoint(x: width * 0.2, y: height * 0.15), control: CGPoint(x: width * 0.02, y: height * 0.2))
        path.closeSubpath()
        return path
    }
}

// MARK: - Shared Components

struct BatteryView: View {
    let level: Float
    let state: GCDeviceBattery.State
    
    var body: some View {
        HStack(spacing: 2) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
            
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 1)
                    .frame(width: 22, height: 10)
                
                // Empty track background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 20, height: 8)
                    .padding(.leading, 1)

                // Fill
                if level >= 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(batteryColor)
                        .frame(width: max(2, 20 * CGFloat(level)), height: 8) // Min width 2 so even 0% is visible
                        .padding(.leading, 1)
                } else {
                    // Unknown level
                    Text("?")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 10, alignment: .center)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 2, height: 4)
        }
    }
    
    private var batteryColor: Color {
        if level > 0.6 { return .green }
        if level > 0.2 { return .orange }
        return .red
    }
}

struct MappingTag: View {
    let mapping: KeyMapping
    
    var body: some View {
        MappingLabelView(
            mapping: mapping,
            font: .system(size: 13, weight: .semibold),
            foregroundColor: .primary
        )
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }
}



#Preview {
    ControllerVisualView(selectedButton: .constant(nil)) { _ in }
        .environmentObject(ControllerService())
        .environmentObject(ProfileManager())
        .frame(width: 800, height: 600)
}