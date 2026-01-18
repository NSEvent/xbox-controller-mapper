import SwiftUI
import GameController

/// Interactive visual representation of a controller with a professional Reference Page layout
/// Automatically adapts to show Xbox or DualSense layouts based on connected controller
struct ControllerVisualView: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager

    @Binding var selectedButton: ControllerButton?
    var onButtonTap: (ControllerButton) -> Void

    private var isDualSense: Bool {
        controllerService.threadSafeIsDualSense
    }

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
                    // Controller body - adapts to DualSense or Xbox shape
                    controllerBodyView
                        .frame(width: 320, height: 220)

                    // Compact Controller Overlay (Just icons, no labels)
                    // Uses throttled display values (15Hz) instead of raw values (60Hz) to avoid UI blocking
                    VStack(spacing: 15) {
                        HStack(spacing: 140) {
                            miniTrigger(.leftTrigger, label: "LT", value: controllerService.displayLeftTrigger)
                            miniTrigger(.rightTrigger, label: "RT", value: controllerService.displayRightTrigger)
                        }

                        HStack(spacing: 120) {
                            miniBumper(.leftBumper, label: "LB")
                            miniBumper(.rightBumper, label: "RB")
                        }
                        .offset(y: -5) // Tweak vertical position to sit nicely under triggers

                        HStack(spacing: 40) {
                            miniStick(.leftThumbstick, pos: controllerService.displayLeftStick)
                            
                            VStack(spacing: 6) {
                                miniCircle(.xbox, size: 22)

                                // Battery Status
                                if controllerService.isConnected {
                                    BatteryView(level: controllerService.batteryLevel, state: controllerService.batteryState)
                                }

                                HStack(spacing: 12) {
                                    miniCircle(.view, size: 14)
                                    miniCircle(.menu, size: 14)
                                }
                                // Show mic mute for DualSense, share for Xbox
                                if isDualSense {
                                    miniCircle(.micMute, size: 10)
                                } else {
                                    miniCircle(.share, size: 10)
                                }
                            }
                            
                            miniFaceButtons()
                        }
                        
                        HStack(spacing: 80) {
                            miniDPad()
                            miniStick(.rightThumbstick, pos: controllerService.displayRightStick)
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
                        // Show mic mute for DualSense, share for Xbox
                        if isDualSense {
                            referenceRow(for: .micMute)
                        } else {
                            referenceRow(for: .share)
                        }
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

    // MARK: - Controller Body

    @ViewBuilder
    private var controllerBodyView: some View {
        if isDualSense {
            DualSenseBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.88)], // DualSense white/light grey
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else {
            ControllerBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.9)], // Xbox light theme
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
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
                // Button Indicator (adapts to Xbox or DualSense styling)
                ButtonIconView(button: button, isPressed: isPressed(button), isDualSense: isDualSense)

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

    // MARK: - Mini Controller Helpers (Jewel/Glass Style)

    private func jewelGradient(_ color: Color, pressed: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                pressed ? color.opacity(0.8) : color,
                pressed ? color.opacity(0.6) : color.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.5), location: 0),
                .init(color: .white.opacity(0.1), location: 0.45),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.1), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func miniTrigger(_ button: ControllerButton, label: String, value: Float) -> some View {
        let color = Color(white: 0.2) // Dark grey plastic
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        
        return ZStack(alignment: .bottom) {
            // Background
            shape
                .fill(jewelGradient(color, pressed: false))
                .overlay(glassOverlay.clipShape(shape))
                .frame(width: 34, height: 18)
            
            // Fill based on pressure
            if value > 0 {
                shape
                    .fill(jewelGradient(Color.accentColor, pressed: isPressed(button)))
                    .frame(width: 34, height: 18 * CGFloat(value))
                    .overlay(glassOverlay.clipShape(shape))
            }
            
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1)
        }
        .clipShape(shape)
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
        .onTapGesture { onButtonTap(button) }
    }

    private func miniBumper(_ button: ControllerButton, label: String) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.25)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        
        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: 38, height: 9)
            .overlay(
                Text(label)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            )
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
    }

    private func miniStick(_ button: ControllerButton, pos: CGPoint) -> some View {
        ZStack {
            // Base well
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.1), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 30, height: 30)
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1) // Highlight at bottom lip
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            
            // Stick Cap
            let color = isPressed(button) ? Color.accentColor : Color(white: 0.3)
            Circle()
                .fill(jewelGradient(color, pressed: isPressed(button)))
                .overlay(glassOverlay.clipShape(Circle()))
                .frame(width: 20, height: 20)
                .offset(x: pos.x * 5, y: -pos.y * 5)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
        }
        .onTapGesture { onButtonTap(button) }
    }

    private func miniCircle(_ button: ControllerButton, size: CGFloat) -> some View {
        // Use silver/chrome for Xbox/PS button, grey for others
        let baseColor: Color = {
            if button == .xbox {
                return Color(white: 0.85) // Silver/Chrome for both Xbox and PlayStation
            }
            return Color(white: 0.3)
        }()
        let color = isPressed(button) ? Color.accentColor : baseColor

        return ZStack {
            Circle()
                .fill(jewelGradient(color, pressed: isPressed(button)))
                .overlay(glassOverlay.clipShape(Circle()))

            // Add Xbox or PlayStation logo for the center button
            if button == .xbox {
                Image(systemName: isDualSense ? "playstation.logo" : "xbox.logo")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundColor(isPressed(button) ? .white : Color(white: 0.3))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
        .onTapGesture { onButtonTap(button) }
    }

    private func miniFaceButton(_ button: ControllerButton, color: Color) -> some View {
        // Use the vibrant colors for A/B/X/Y even when not pressed, just like the real controller
        let displayColor = isPressed(button) ? color.opacity(0.8) : color

        return Circle()
            .fill(jewelGradient(displayColor, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(Circle()))
            .frame(width: 12, height: 12)
            .shadow(color: displayColor.opacity(0.4), radius: 2)
            .onTapGesture { onButtonTap(button) }
    }

    /// PlayStation-style face button: dark background with colored symbol
    private func miniPSFaceButton(_ button: ControllerButton, symbolColor: Color) -> some View {
        let bgColor = Color(white: 0.12)
        let symbol: String = {
            switch button {
            case .a: return "✕"
            case .b: return "○"
            case .x: return "□"
            case .y: return "△"
            default: return ""
            }
        }()

        return ZStack {
            Circle()
                .fill(jewelGradient(bgColor, pressed: isPressed(button)))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.15), location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: .black.opacity(0.2), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(Circle())
                )

            Text(symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(isPressed(button) ? symbolColor.opacity(0.7) : symbolColor)
        }
        .frame(width: 12, height: 12)
        .shadow(color: symbolColor.opacity(0.3), radius: 2)
        .onTapGesture { onButtonTap(button) }
    }

    private func miniFaceButtons() -> some View {
        ZStack {
            if isDualSense {
                // PlayStation style: dark background with colored symbols
                miniPSFaceButton(.y, symbolColor: Color(red: 0.45, green: 0.85, blue: 0.75)).offset(y: -12) // Triangle - Teal
                miniPSFaceButton(.a, symbolColor: Color(red: 0.55, green: 0.70, blue: 0.95)).offset(y: 12)  // Cross - Light Blue
                miniPSFaceButton(.x, symbolColor: Color(red: 0.90, green: 0.55, blue: 0.75)).offset(x: -12) // Square - Pink
                miniPSFaceButton(.b, symbolColor: Color(red: 1.0, green: 0.45, blue: 0.50)).offset(x: 12)   // Circle - Red/Pink
            } else {
                // Xbox layout and colors (colored background)
                miniFaceButton(.y, color: Color(red: 1.0, green: 0.7, blue: 0.0)).offset(y: -12) // Yellow
                miniFaceButton(.a, color: Color(red: 0.4, green: 0.8, blue: 0.2)).offset(y: 12)  // Green
                miniFaceButton(.x, color: Color(red: 0.1, green: 0.4, blue: 0.9)).offset(x: -12) // Blue
                miniFaceButton(.b, color: Color(red: 0.9, green: 0.2, blue: 0.2)).offset(x: 12)  // Red
            }
        }
        .frame(width: 40, height: 40)
    }

    private func miniDPad() -> some View {
        let color = Color(white: 0.25)
        
        return ZStack {
            // Background Cross
            Group {
                RoundedRectangle(cornerRadius: 2).frame(width: 8, height: 24)
                RoundedRectangle(cornerRadius: 2).frame(width: 24, height: 8)
            }
            .foregroundStyle(jewelGradient(color, pressed: false))
            .shadow(radius: 1)
            
            // Active states (Lighting up)
            if isPressed(.dpadUp) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 10).offset(y: -7).blur(radius: 2)
            }
            if isPressed(.dpadDown) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 10).offset(y: 7).blur(radius: 2)
            }
            if isPressed(.dpadLeft) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 10, height: 8).offset(x: -7).blur(radius: 2)
            }
            if isPressed(.dpadRight) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 10, height: 8).offset(x: 7).blur(radius: 2)
            }
            
            // Tap zones
            Group {
                // Up
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: -10)
                    .onTapGesture { onButtonTap(.dpadUp) }
                
                // Down
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: 10)
                    .onTapGesture { onButtonTap(.dpadDown) }
                
                // Left
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: -10)
                    .onTapGesture { onButtonTap(.dpadLeft) }
                
                // Right
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: 10)
                    .onTapGesture { onButtonTap(.dpadRight) }
            }
        }
    }

    // MARK: - Helpers

    private func isPressed(_ button: ControllerButton) -> Bool {
        controllerService.activeButtons.contains(button)
    }

    private func mapping(for button: ControllerButton) -> KeyMapping? {
        guard let mapping = profileManager.activeProfile?.buttonMappings[button] else { return nil }
        
        // If the mapping is effectively empty (no primary, no long hold, no double tap), return nil
        // so the UI renders it as "Unmapped"
        if mapping.isEmpty && 
           (mapping.longHoldMapping?.isEmpty ?? true) && 
           (mapping.doubleTapMapping?.isEmpty ?? true) {
            return nil
        }
        
        return mapping
    }
}

// MARK: - Controller Body Shapes

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

/// DualSense controller body shape - more symmetric and rounded than Xbox
struct DualSenseBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // DualSense has a more symmetric, rounded shape with wider grips
        // Top edge - flatter than Xbox
        path.move(to: CGPoint(x: width * 0.18, y: height * 0.12))
        path.addCurve(
            to: CGPoint(x: width * 0.82, y: height * 0.12),
            control1: CGPoint(x: width * 0.35, y: height * 0.02),
            control2: CGPoint(x: width * 0.65, y: height * 0.02)
        )

        // Right side - more vertical drop for DualSense grips
        path.addQuadCurve(
            to: CGPoint(x: width * 0.92, y: height * 0.35),
            control: CGPoint(x: width * 0.95, y: height * 0.18)
        )

        // Right grip - straighter, more ergonomic curve
        path.addCurve(
            to: CGPoint(x: width * 0.72, y: height * 0.92),
            control1: CGPoint(x: width * 0.95, y: height * 0.55),
            control2: CGPoint(x: width * 0.85, y: height * 0.88)
        )

        // Bottom center - DualSense has a flatter bottom with touchpad indent
        path.addQuadCurve(
            to: CGPoint(x: width * 0.28, y: height * 0.92),
            control: CGPoint(x: width * 0.5, y: height * 0.82)
        )

        // Left grip - mirror of right
        path.addCurve(
            to: CGPoint(x: width * 0.08, y: height * 0.35),
            control1: CGPoint(x: width * 0.15, y: height * 0.88),
            control2: CGPoint(x: width * 0.05, y: height * 0.55)
        )

        // Back to top left
        path.addQuadCurve(
            to: CGPoint(x: width * 0.18, y: height * 0.12),
            control: CGPoint(x: width * 0.05, y: height * 0.18)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Shared Components

struct BatteryView: View {
    let level: Float
    let state: GCDeviceBattery.State
    
    // Xbox controllers on macOS often report 0.0 with unknown state when data is unavailable
    private var isUnknown: Bool {
        level < 0 || (level == 0 && state == .unknown)
    }
    
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
                    .frame(width: 30, height: 14)
                
                // Empty track background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 28, height: 12)
                    .padding(.leading, 1)

                // Fill
                if !isUnknown {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(batteryColor)
                            .frame(width: max(2, 28 * CGFloat(level)), height: 12)
                        
                        Text("\(Int(level * 100))%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                            .frame(width: 28, alignment: .center)
                    }
                    .padding(.leading, 1)
                } else {
                    // Unknown level
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 14, alignment: .center)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.4))
                .frame(width: 2, height: 4)
        }
        .help(isUnknown ? "Battery level unavailable (common macOS limitation for Xbox controllers)" : "Battery: \(Int(level * 100))%")
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