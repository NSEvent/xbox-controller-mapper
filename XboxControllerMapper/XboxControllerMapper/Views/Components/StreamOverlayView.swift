import SwiftUI
import Combine

/// Compact controller overlay for OBS/streaming capture
/// Shows real-time button presses on a mini controller silhouette with last action text
struct StreamOverlayView: View {
    @ObservedObject var controllerService: ControllerService
    @ObservedObject var inputLogService: InputLogService

    @State private var lastActionText: String = ""
    @State private var lastActionOpacity: Double = 0
    @State private var hideTimer: Timer?

    private var isPlayStation: Bool {
        controllerService.threadSafeIsPlayStation
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Controller body silhouette
                controllerBody
                    .frame(width: 200, height: 140)

                // Button overlays
                if isPlayStation {
                    dualSenseButtons
                } else {
                    xboxButtons
                }
            }
            .frame(width: 200, height: 140)

            // Last action line — shows held actions while held, otherwise last single action
            Text(displayActionText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .frame(height: 16)
                .opacity(displayActionOpacity)
                .animation(.easeInOut(duration: 0.2), value: displayActionOpacity)
        }
        .padding(10)
        .background(overlayBackground)
        .onChange(of: inputLogService.entries) { _, entries in
            if let latest = entries.first {
                showAction(latest)
            }
        }
        .onDisappear {
            hideTimer?.invalidate()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var overlayBackground: some View {
        let style = StreamOverlayManager.backgroundStyle
        switch style {
        case .semiTransparent:
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.5))
        case .chromaGreen, .chromaMagenta, .solid:
            RoundedRectangle(cornerRadius: 12)
                .fill(style.color)
        }
    }

    // MARK: - Controller Body

    @ViewBuilder
    private var controllerBody: some View {
        if isPlayStation {
            DualSenseBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    DualSenseBodyShape()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        } else {
            ControllerBodyShape()
                .fill(LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    ControllerBodyShape()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    // MARK: - Xbox Button Layout

    private var xboxButtons: some View {
        VStack(spacing: 12) {
            // Triggers
            HStack(spacing: 90) {
                overlayTrigger(.leftTrigger, label: "LT", value: controllerService.displayLeftTrigger)
                overlayTrigger(.rightTrigger, label: "RT", value: controllerService.displayRightTrigger)
            }

            // Bumpers
            HStack(spacing: 76) {
                overlayBumper(.leftBumper, label: "LB")
                overlayBumper(.rightBumper, label: "RB")
            }
            .offset(y: -4)

            // Middle row: sticks + center + face
            HStack(spacing: 20) {
                overlayStick(.leftThumbstick, pos: controllerService.displayLeftStick)

                VStack(spacing: 4) {
                    overlayCircle(.xbox, size: 14)
                    HStack(spacing: 8) {
                        overlayCircle(.view, size: 9)
                        overlayCircle(.menu, size: 9)
                    }
                }

                overlayFaceButtons()
            }

            // Bottom: dpad + right stick
            HStack(spacing: 50) {
                overlayDPad()
                overlayStick(.rightThumbstick, pos: controllerService.displayRightStick)
            }
        }
    }

    // MARK: - DualSense Button Layout

    private var dualSenseButtons: some View {
        VStack(spacing: 3) {
            // Triggers
            HStack(spacing: 96) {
                overlayTrigger(.leftTrigger, label: "L2", value: controllerService.displayLeftTrigger)
                overlayTrigger(.rightTrigger, label: "R2", value: controllerService.displayRightTrigger)
            }

            // Bumpers
            HStack(spacing: 84) {
                overlayBumper(.leftBumper, label: "L1")
                overlayBumper(.rightBumper, label: "R1")
            }

            // Touchpad + Create/Options
            HStack(alignment: .center, spacing: 4) {
                overlayCircle(.view, size: 8)
                overlayTouchpad()
                overlayCircle(.menu, size: 8)
            }

            // D-pad + PS button + face
            HStack(spacing: 14) {
                overlayDPad()

                overlayCircle(.xbox, size: 12)

                overlayFaceButtons()
            }

            // Sticks
            HStack(spacing: 30) {
                overlayStick(.leftThumbstick, pos: controllerService.displayLeftStick)
                overlayStick(.rightThumbstick, pos: controllerService.displayRightStick)
            }
        }
    }

    // MARK: - Mini Button Components

    private func overlayTrigger(_ button: ControllerButton, label: String, value: Float) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)

        return ZStack(alignment: .bottom) {
            shape
                .fill(Color(white: 0.35))
                .frame(width: 24, height: 12)

            if value > 0 {
                shape
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 12 * CGFloat(value))
            }

            Text(label)
                .font(.system(size: 5, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .clipShape(shape)
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.5) : .clear, radius: 3)
    }

    private func overlayBumper(_ button: ControllerButton, label: String) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.4)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)

        return shape
            .fill(color)
            .frame(width: 28, height: 7)
            .overlay(
                Text(label)
                    .font(.system(size: 5, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            )
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.5) : .clear, radius: 3)
    }

    private func overlayStick(_ button: ControllerButton, pos: CGPoint) -> some View {
        ZStack {
            // Well
            Circle()
                .fill(Color(white: 0.2))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color(white: 0.4), lineWidth: 0.5))

            // Cap
            let color = isPressed(button) ? Color.accentColor : Color(white: 0.45)
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .offset(x: pos.x * 3, y: -pos.y * 3)
                .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.5) : .clear, radius: 2)
        }
    }

    private func overlayCircle(_ button: ControllerButton, size: CGFloat) -> some View {
        let baseColor: Color = button == .xbox ? Color(white: 0.75) : Color(white: 0.45)
        let color = isPressed(button) ? Color.accentColor : baseColor

        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.5) : .clear, radius: 2)
    }

    private func overlayFaceButtons() -> some View {
        ZStack {
            if isPlayStation {
                overlayPSFaceButton(.y, symbolColor: ButtonColors.psTriangle).offset(y: -9)
                overlayPSFaceButton(.a, symbolColor: ButtonColors.psCross).offset(y: 9)
                overlayPSFaceButton(.x, symbolColor: ButtonColors.psSquare).offset(x: -9)
                overlayPSFaceButton(.b, symbolColor: ButtonColors.psCircle).offset(x: 9)
            } else {
                overlayXboxFaceButton(.y, color: ButtonColors.xboxY).offset(y: -9)
                overlayXboxFaceButton(.a, color: ButtonColors.xboxA).offset(y: 9)
                overlayXboxFaceButton(.x, color: ButtonColors.xboxX).offset(x: -9)
                overlayXboxFaceButton(.b, color: ButtonColors.xboxB).offset(x: 9)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func overlayXboxFaceButton(_ button: ControllerButton, color: Color) -> some View {
        let displayColor = isPressed(button) ? color.opacity(0.9) : color
        return Circle()
            .fill(displayColor)
            .frame(width: 9, height: 9)
            .shadow(color: isPressed(button) ? displayColor.opacity(0.6) : displayColor.opacity(0.3), radius: 2)
    }

    private func overlayPSFaceButton(_ button: ControllerButton, symbolColor: Color) -> some View {
        let bgColor = Color(white: 0.3)
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
                .fill(isPressed(button) ? bgColor.opacity(0.9) : bgColor)

            Text(symbol)
                .font(.system(size: 5, weight: .bold))
                .foregroundColor(isPressed(button) ? symbolColor.opacity(0.8) : symbolColor)
        }
        .frame(width: 9, height: 9)
        .shadow(color: isPressed(button) ? symbolColor.opacity(0.5) : symbolColor.opacity(0.2), radius: 2)
    }

    private func overlayTouchpad() -> some View {
        let color = isPressed(.touchpadButton) ? Color.accentColor : Color(white: 0.35)
        let touchpadWidth: CGFloat = 60
        let touchpadHeight: CGFloat = 28

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            // Primary touch point
            if controllerService.displayIsTouchpadTouching {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 6, height: 6)
                    .shadow(color: .white.opacity(0.5), radius: 2)
                    .offset(
                        x: controllerService.displayTouchpadPosition.x * (touchpadWidth / 2 - 3),
                        y: -controllerService.displayTouchpadPosition.y * (touchpadHeight / 2 - 3)
                    )
            }

            // Secondary touch point
            if controllerService.displayIsTouchpadSecondaryTouching {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .shadow(color: .white.opacity(0.4), radius: 1.5)
                    .offset(
                        x: controllerService.displayTouchpadSecondaryPosition.x * (touchpadWidth / 2 - 3),
                        y: -controllerService.displayTouchpadSecondaryPosition.y * (touchpadHeight / 2 - 3)
                    )
            }
        }
        .frame(width: touchpadWidth, height: touchpadHeight)
        .shadow(color: isPressed(.touchpadButton) ? Color.accentColor.opacity(0.5) : .clear, radius: 3)
    }

    private func overlayDPad() -> some View {
        let color = Color(white: 0.4)

        return ZStack {
            // Cross shape
            Group {
                RoundedRectangle(cornerRadius: 1.5).frame(width: 6, height: 18)
                RoundedRectangle(cornerRadius: 1.5).frame(width: 18, height: 6)
            }
            .foregroundColor(color)

            // Active highlights
            if isPressed(.dpadUp) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 6, height: 7).offset(y: -5.5).blur(radius: 1.5)
            }
            if isPressed(.dpadDown) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 6, height: 7).offset(y: 5.5).blur(radius: 1.5)
            }
            if isPressed(.dpadLeft) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 7, height: 6).offset(x: -5.5).blur(radius: 1.5)
            }
            if isPressed(.dpadRight) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 7, height: 6).offset(x: 5.5).blur(radius: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Display Logic

    /// Shows held actions when modifiers are held, otherwise shows last single action
    private var displayActionText: String {
        if !inputLogService.heldActions.isEmpty {
            return inputLogService.heldActions.joined(separator: " + ")
        }
        return lastActionText
    }

    private var displayActionOpacity: Double {
        if !inputLogService.heldActions.isEmpty {
            return 1.0
        }
        return lastActionOpacity
    }

    // MARK: - Helpers

    private func isPressed(_ button: ControllerButton) -> Bool {
        controllerService.activeButtons.contains(button)
    }

    private func showAction(_ entry: InputLogEntry) {
        hideTimer?.invalidate()
        lastActionText = entry.actionDescription
        lastActionOpacity = 1.0

        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                self.lastActionOpacity = 0
            }
        }
    }
}
