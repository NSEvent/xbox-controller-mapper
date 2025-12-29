import SwiftUI

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
                Spacer()
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
                        HStack(spacing: 120) {
                            miniButton(.leftTrigger, label: "LT")
                            miniButton(.rightTrigger, label: "RT")
                        }
                        
                        HStack(spacing: 40) {
                            miniStick(.leftThumbstick, pos: controllerService.leftStick)
                            
                            VStack(spacing: 8) {
                                miniCircle(.xbox, size: 24)
                                HStack(spacing: 15) {
                                    miniCircle(.view, size: 18)
                                    miniCircle(.menu, size: 18)
                                }
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
                
                Spacer()
            }
            .frame(width: 350)

            // Right Column: Face buttons and Right-side inputs
            VStack(alignment: .leading, spacing: 16) {
                referenceGroup(title: "Actions", buttons: [.y, .b, .a, .x])
                referenceGroup(title: "Camera", buttons: [.rightThumbstick])
                referenceGroup(title: "Shoulder", buttons: [.rightTrigger, .rightBumper])
                Spacer()
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

            VStack(spacing: 2) {
                ForEach(buttons) { button in
                    referenceRow(for: button)
                }
            }
        }
    }

    @ViewBuilder
    private func referenceRow(for button: ControllerButton) -> some View {
        Button(action: { onButtonTap(button) }) {
            HStack(spacing: 10) {
                // Button Indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPressed(button) ? Color.accentColor : Color(white: 0.2))
                        .frame(width: 32, height: 24)
                    
                    Text(button.shortLabel)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                }

                // Shortcut Labels
                if let mapping = mapping(for: button) {
                    MappingLabelView(mapping: mapping)
                } else {
                    Text("Unmapped")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                        .italic()
                }
                
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedButton == button ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selectedButton == button ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini Controller Helpers

    private func miniButton(_ button: ControllerButton, label: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isPressed(button) ? Color.accentColor : Color.gray.opacity(0.3))
            .frame(width: 30, height: 10)
            .overlay(Text(label).font(.system(size: 6)).foregroundColor(.white))
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
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 8, height: 24)
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 24, height: 8)
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

// MARK: - Controller Body Shape (Reused)

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

#Preview {
    ControllerVisualView(selectedButton: .constant(nil)) { _ in }
        .environmentObject(ControllerService())
        .environmentObject(ProfileManager())
        .frame(width: 800, height: 600)
}