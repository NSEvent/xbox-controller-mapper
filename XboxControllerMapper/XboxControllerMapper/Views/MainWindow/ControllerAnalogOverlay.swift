import SwiftUI
import GameController
import Combine

// MARK: - Controller Analog Overlay

/// Extracted overlay view that isolates high-frequency analog display updates (15Hz)
/// from the rest of the ControllerVisualView hierarchy. By snapshotting display values
/// into local @State via .onReceive, only this sub-view redraws when joystick/trigger
/// values change, preventing cascading redraws of the mapping reference rows.
struct ControllerAnalogOverlay: View {
    let controllerService: ControllerService
    let isPlayStation: Bool
    let isNintendo: Bool
    let isXboxElite: Bool
    let isSteamController: Bool
    var isDualShock: Bool = false
    var isDualSenseEdge: Bool = false
    /// Buttons the Elite/Steam back paddles currently resolve to (paddles
    /// can be hardware-assigned to act as another button; connector lines
    /// must anchor whatever the reference rows resolve to). Order:
    /// upper-left, upper-right, lower-left, lower-right.
    var elitePaddleButtons: [ControllerButton] = [.xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4]
    /// Whole-pad shows one big click target with a single anchor. Quadrants
    /// shows the dashed divider cross plus four per-quadrant tap zones, each
    /// anchoring its `.touchpadRegion*Click` and `.touchpadRegion*Touch`
    /// buttons so connectors land at the correct quarter of the pad.
    var touchpadInputMode: TouchpadInputMode = .wholePad
    var onButtonTap: (ControllerButton) -> Void
    var onButtonHover: ((ControllerButton, Bool) -> Void)? = nil
    var onSwapRequest: ((ControllerButton, ControllerButton) -> Void)? = nil
    var overrideColorForButton: (ControllerButton) -> Color? = { _ in nil }

    // Snapshotted analog display values (updated via .onReceive at 15Hz)
    @State private var leftStick: CGPoint = .zero
    @State private var rightStick: CGPoint = .zero
    @State private var leftTrigger: Float = 0
    @State private var rightTrigger: Float = 0
    @State private var isTouchpadTouching: Bool = false
    @State private var touchpadPosition: CGPoint = .zero
    @State private var isTouchpadSecondaryTouching: Bool = false
    @State private var touchpadSecondaryPosition: CGPoint = .zero
    @State private var isSteamLeftTouchpadTouching: Bool = false
    @State private var steamLeftTouchpadPosition: CGPoint = .zero
    @State private var isSteamRightTouchpadTouching: Bool = false
    @State private var steamRightTouchpadPosition: CGPoint = .zero
    @State private var activeButtons: Set<ControllerButton> = []
    /// Local hover tracking — used by the touchpad quadrant zones to highlight
    /// the targeted region. The parent owns the canonical hover state for
    /// connector drawing; this is just for the per-zone tint.
    @State private var hoveredQuadrant: ControllerButton?
    @State private var isConnected: Bool = false
    @State private var batteryLevel: Float = -1
    @State private var batteryState: GCDeviceBattery.State = .unknown

    /// Resolved visual style for layout lookups.
    var minimapStyle: ControllerMinimapStyle {
        if isSteamController { return .steam }
        if isDualShock { return .dualShock }
        if isDualSenseEdge { return .dualSenseEdge }
        if isPlayStation { return .dualSense }
        if isNintendo { return .nintendo }
        if isXboxElite { return .xboxElite }
        return .xbox
    }

    /// Preview frame the overlay is laid out in (matches the body silhouette).
    private var frameSize: CGSize { minimapStyle.previewSize }

    var body: some View {
        Group {
            if isSteamController {
                steamOverlay
            } else if isDualShock {
                dualShockOverlay
            } else if isPlayStation {
                dualSenseOverlay
            } else if isNintendo {
                nintendoOverlay
            } else {
                xboxOverlay
            }
        }
        .onReceive(controllerService.displayLeftStickSubject) { leftStick = $0 }
        .onReceive(controllerService.displayRightStickSubject) { rightStick = $0 }
        .onReceive(controllerService.displayLeftTriggerSubject) { leftTrigger = $0 }
        .onReceive(controllerService.displayRightTriggerSubject) { rightTrigger = $0 }
        .onReceive(controllerService.displayIsTouchpadTouchingSubject) { isTouchpadTouching = $0 }
        .onReceive(controllerService.displayTouchpadPositionSubject) { touchpadPosition = $0 }
        .onReceive(controllerService.displayIsTouchpadSecondaryTouchingSubject) { isTouchpadSecondaryTouching = $0 }
        .onReceive(controllerService.displayTouchpadSecondaryPositionSubject) { touchpadSecondaryPosition = $0 }
        .onReceive(controllerService.displayIsSteamLeftTouchpadTouchingSubject) { isSteamLeftTouchpadTouching = $0 }
        .onReceive(controllerService.displaySteamLeftTouchpadPositionSubject) { steamLeftTouchpadPosition = $0 }
        .onReceive(controllerService.displayIsSteamRightTouchpadTouchingSubject) { isSteamRightTouchpadTouching = $0 }
        .onReceive(controllerService.displaySteamRightTouchpadPositionSubject) { steamRightTouchpadPosition = $0 }
        .onReceive(controllerService.$activeButtons) { activeButtons = $0 }
        .onReceive(controllerService.$isConnected) { isConnected = $0 }
        .onReceive(controllerService.$batteryLevel) { batteryLevel = $0 }
        .onReceive(controllerService.$batteryState) { batteryState = $0 }
    }

    // MARK: - Xbox Controller Overlay

    private var xboxOverlay: some View {
        let size = frameSize
        let w = size.width
        let isElite = isXboxElite

        return ZStack {
            if isElite {
                eliteXboxControls(size: size, w: w)
            } else {
                standardXboxControls(size: size, w: w)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func standardXboxControls(size: CGSize, w: CGFloat) -> some View {
        let layout = XboxMinimapLayout.self

        miniTrigger(.leftTrigger, label: "LT", value: leftTrigger, width: w * 0.085)
            .minimapPosition(layout.leftTrigger, in: size)
        miniTrigger(.rightTrigger, label: "RT", value: rightTrigger, width: w * 0.085)
            .minimapPosition(layout.rightTrigger, in: size)
        miniBumper(.leftBumper, label: "LB", width: w * 0.15, tilt: -7)
            .minimapPosition(layout.leftBumper, in: size)
        miniBumper(.rightBumper, label: "RB", width: w * 0.15, tilt: 7)
            .minimapPosition(layout.rightBumper, in: size)

        miniCircle(.xbox, size: w * layout.guideSize)
            .minimapPosition(layout.guide, in: size)
        miniCircle(.view, size: w * layout.viewMenuSize)
            .minimapPosition(layout.view, in: size)
        miniCircle(.menu, size: w * layout.viewMenuSize)
            .minimapPosition(layout.menu, in: size)
        miniCircle(.share, size: w * layout.shareSize)
            .minimapPosition(layout.share, in: size)

        miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize)
            .minimapPosition(layout.leftStick, in: size)
        miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize)
            .minimapPosition(layout.rightStick, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        miniDPad(span: w * layout.dpadSize, style: .xboxDisc)
            .minimapPosition(layout.dpad, in: size)

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    @ViewBuilder
    private func eliteXboxControls(size: CGSize, w: CGFloat) -> some View {
        let layout = XboxEliteMinimapLayout.self

        miniTrigger(.leftTrigger, label: "LT", value: leftTrigger, width: w * 0.085)
            .minimapPosition(layout.leftTrigger, in: size)
        miniTrigger(.rightTrigger, label: "RT", value: rightTrigger, width: w * 0.085)
            .minimapPosition(layout.rightTrigger, in: size)
        miniBumper(.leftBumper, label: "LB", width: w * 0.15, tilt: -7)
            .minimapPosition(layout.leftBumper, in: size)
        miniBumper(.rightBumper, label: "RB", width: w * 0.15, tilt: 7)
            .minimapPosition(layout.rightBumper, in: size)

        miniCircle(.xbox, size: w * layout.guideSize)
            .minimapPosition(layout.guide, in: size)
        miniCircle(.view, size: w * layout.viewMenuSize)
            .minimapPosition(layout.view, in: size)
        miniCircle(.menu, size: w * layout.viewMenuSize)
            .minimapPosition(layout.menu, in: size)

        // Decorative profile-switch slot (not a mappable button)
        Capsule()
            .fill(Color(white: 0.07))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
            .frame(width: w * 0.045, height: w * 0.018)
            .minimapPosition(layout.profileSlot, in: size)
            .allowsHitTesting(false)

        miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize, eliteRing: true)
            .minimapPosition(layout.leftStick, in: size)
        miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize, eliteRing: true)
            .minimapPosition(layout.rightStick, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        miniDPad(span: w * layout.dpadSize, style: .eliteDisc)
            .minimapPosition(layout.dpad, in: size)

        // Back paddles peeking into the valley between the grips
        if elitePaddleButtons.count == 4 {
            miniPaddle(elitePaddleButtons[0], width: w * 0.022, height: w * 0.055, tilt: -10, metallic: true)
                .minimapPosition(layout.paddleUpperLeft, in: size)
            miniPaddle(elitePaddleButtons[1], width: w * 0.022, height: w * 0.055, tilt: 10, metallic: true)
                .minimapPosition(layout.paddleUpperRight, in: size)
            miniPaddle(elitePaddleButtons[2], width: w * 0.019, height: w * 0.043, tilt: -6, metallic: true)
                .minimapPosition(layout.paddleLowerLeft, in: size)
            miniPaddle(elitePaddleButtons[3], width: w * 0.019, height: w * 0.043, tilt: 6, metallic: true)
                .minimapPosition(layout.paddleLowerRight, in: size)
        }

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    // MARK: - Steam Controller Overlay

    private var steamOverlay: some View {
        let size = frameSize
        let w = size.width
        let layout = SteamMinimapLayout.self

        return ZStack {
            miniTrigger(.leftTrigger, label: "LT", value: leftTrigger, width: w * 0.07, tilt: -30)
                .minimapPosition(layout.leftTrigger, in: size)
            miniTrigger(.rightTrigger, label: "RT", value: rightTrigger, width: w * 0.07, tilt: 30)
                .minimapPosition(layout.rightTrigger, in: size)
            miniBumper(.leftBumper, label: "LB", width: w * 0.10, tilt: -26)
                .minimapPosition(layout.leftBumper, in: size)
            miniBumper(.rightBumper, label: "RB", width: w * 0.10, tilt: 26)
                .minimapPosition(layout.rightBumper, in: size)

            miniDPad(span: w * layout.dpadSize, style: .cross)
                .minimapPosition(layout.dpad, in: size)

            miniCircle(.view, size: w * layout.viewMenuSize)
                .minimapPosition(layout.view, in: size)
            miniCircle(.xbox, size: w * layout.guideSize)
                .minimapPosition(layout.guide, in: size)
            miniCircle(.menu, size: w * layout.viewMenuSize)
                .minimapPosition(layout.menu, in: size)

            miniFaceButtons(
                buttonSize: w * layout.faceButtonSize,
                offset: w * layout.faceButtonOffset
            )
            .minimapPosition(layout.faceCluster, in: size)

            miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.leftStick, in: size)
            miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.rightStick, in: size)

            miniSteamTouchpad(side: .left, padSize: w * layout.touchpadSize, tilt: 4)
                .minimapPosition(layout.leftTouchpad, in: size)
            miniSteamTouchpad(side: .right, padSize: w * layout.touchpadSize, tilt: -4)
                .minimapPosition(layout.rightTouchpad, in: size)

            miniCircle(.share, size: w * layout.shareSize)
                .minimapPosition(layout.share, in: size)

            // Rear grip buttons peeking under the bottom arches
            if elitePaddleButtons.count == 4 {
                miniPaddle(elitePaddleButtons[0], width: w * 0.020, height: w * 0.046, tilt: -14)
                    .minimapPosition(layout.gripUpperLeft, in: size)
                miniPaddle(elitePaddleButtons[1], width: w * 0.020, height: w * 0.046, tilt: 14)
                    .minimapPosition(layout.gripUpperRight, in: size)
                miniPaddle(elitePaddleButtons[2], width: w * 0.018, height: w * 0.038, tilt: -8)
                    .minimapPosition(layout.gripLowerLeft, in: size)
                miniPaddle(elitePaddleButtons[3], width: w * 0.018, height: w * 0.038, tilt: 8)
                    .minimapPosition(layout.gripLowerRight, in: size)
            }

            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .minimapPosition(layout.battery, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Nintendo Pro Controller Overlay

    private var nintendoOverlay: some View {
        let size = frameSize
        let w = size.width
        let layout = NintendoProMinimapLayout.self

        return ZStack {
            miniTrigger(.leftTrigger, label: "ZL", value: leftTrigger, width: w * 0.085)
                .minimapPosition(layout.leftTrigger, in: size)
            miniTrigger(.rightTrigger, label: "ZR", value: rightTrigger, width: w * 0.085)
                .minimapPosition(layout.rightTrigger, in: size)
            miniBumper(.leftBumper, label: "L", width: w * 0.15, tilt: -6)
                .minimapPosition(layout.leftBumper, in: size)
            miniBumper(.rightBumper, label: "R", width: w * 0.15, tilt: 6)
                .minimapPosition(layout.rightBumper, in: size)

            miniCircle(.view, size: w * layout.minusPlusSize)   // − button
                .minimapPosition(layout.minus, in: size)
            miniCircle(.menu, size: w * layout.minusPlusSize)   // + button
                .minimapPosition(layout.plus, in: size)
            miniSquare(.share, size: w * layout.captureHomeSize)  // Capture
                .minimapPosition(layout.capture, in: size)
            miniCircle(.xbox, size: w * layout.captureHomeSize)   // Home
                .minimapPosition(layout.home, in: size)

            miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.leftStick, in: size)
            miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.rightStick, in: size)

            miniFaceButtons(
                buttonSize: w * layout.faceButtonSize,
                offset: w * layout.faceButtonOffset
            )
            .minimapPosition(layout.faceCluster, in: size)

            miniDPad(span: w * layout.dpadSize, style: .cross)
                .minimapPosition(layout.dpad, in: size)

            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .minimapPosition(layout.battery, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - DualSense Controller Overlay

    private var dualSenseOverlay: some View {
        let size = frameSize
        let w = size.width
        let layout = DualSenseMinimapLayout.self

        return ZStack {
            miniTrigger(.leftTrigger, label: "L2", value: leftTrigger, width: w * 0.075)
                .minimapPosition(layout.leftTrigger, in: size)
            miniTrigger(.rightTrigger, label: "R2", value: rightTrigger, width: w * 0.075)
                .minimapPosition(layout.rightTrigger, in: size)
            miniBumper(.leftBumper, label: "L1", width: w * 0.12, tilt: -6)
                .minimapPosition(layout.leftBumper, in: size)
            miniBumper(.rightBumper, label: "R1", width: w * 0.12, tilt: 6)
                .minimapPosition(layout.rightBumper, in: size)

            // Create / Options: small angled pills beside the touchpad
            miniPill(.view, size: w * layout.createOptionsSize, tilt: 28)
                .minimapPosition(layout.create, in: size)
            miniPill(.menu, size: w * layout.createOptionsSize, tilt: -28)
                .minimapPosition(layout.options, in: size)

            miniTouchpad(
                width: w * layout.touchpadSize.width,
                height: size.height * layout.touchpadSize.height,
                lightStyle: !isDualSenseEdge
            )
            .minimapPosition(layout.touchpad, in: size)

            miniDPad(span: w * layout.dpadSize, style: .chiclets)
                .minimapPosition(layout.dpad, in: size)

            miniFaceButtons(
                buttonSize: w * layout.faceButtonSize,
                offset: w * layout.faceButtonOffset
            )
            .minimapPosition(layout.faceCluster, in: size)

            miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.leftStick, in: size)
            miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.rightStick, in: size)

            miniPSButton(size: w * layout.psButtonSize)
                .minimapPosition(layout.psButton, in: size)
            miniBumperWithIcon(.micMute, icon: "mic.slash", width: w * 0.05)
                .minimapPosition(layout.micMute, in: size)

            // Edge-only Fn pills below the sticks + back paddles under the V notch
            if isDualSenseEdge {
                miniPill(.leftFunction, size: w * 0.026, tilt: 0)
                    .minimapPosition(layout.leftFunction, in: size)
                miniPill(.rightFunction, size: w * 0.026, tilt: 0)
                    .minimapPosition(layout.rightFunction, in: size)
                miniPaddle(.leftPaddle, width: w * 0.022, height: w * 0.05, tilt: -12)
                    .minimapPosition(layout.leftPaddle, in: size)
                miniPaddle(.rightPaddle, width: w * 0.022, height: w * 0.05, tilt: 12)
                    .minimapPosition(layout.rightPaddle, in: size)
            }

            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .minimapPosition(layout.battery, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - DualShock 4 Controller Overlay

    private var dualShockOverlay: some View {
        let size = frameSize
        let w = size.width
        let layout = DualShockMinimapLayout.self

        return ZStack {
            miniTrigger(.leftTrigger, label: "L2", value: leftTrigger, width: w * 0.075)
                .minimapPosition(layout.leftTrigger, in: size)
            miniTrigger(.rightTrigger, label: "R2", value: rightTrigger, width: w * 0.075)
                .minimapPosition(layout.rightTrigger, in: size)
            miniBumper(.leftBumper, label: "L1", width: w * 0.12, tilt: -6)
                .minimapPosition(layout.leftBumper, in: size)
            miniBumper(.rightBumper, label: "R1", width: w * 0.12, tilt: 6)
                .minimapPosition(layout.rightBumper, in: size)

            // Share / Options: small pills flanking the touchpad
            miniPill(.view, size: w * layout.shareOptionsSize, tilt: 0)
                .minimapPosition(layout.share, in: size)
            miniPill(.menu, size: w * layout.shareOptionsSize, tilt: 0)
                .minimapPosition(layout.options, in: size)

            miniTouchpad(
                width: w * layout.touchpadSize.width,
                height: size.height * layout.touchpadSize.height,
                lightStyle: false,
                showLightBar: true
            )
            .minimapPosition(layout.touchpad, in: size)

            miniDPad(span: w * layout.dpadSize, style: .chiclets)
                .minimapPosition(layout.dpad, in: size)

            miniFaceButtons(
                buttonSize: w * layout.faceButtonSize,
                offset: w * layout.faceButtonOffset
            )
            .minimapPosition(layout.faceCluster, in: size)

            miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.leftStick, in: size)
            miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize)
                .minimapPosition(layout.rightStick, in: size)

            miniPSButton(size: w * layout.psButtonSize)
                .minimapPosition(layout.psButton, in: size)

            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .minimapPosition(layout.battery, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Mini Touchpad

    /// PlayStation touchpad. `lightStyle` renders the DualSense's white pad;
    /// dark style is used by the DualShock 4 and DualSense Edge. The DS4
    /// additionally shows its light bar as a glowing strip at the pad's top
    /// edge (`showLightBar`).
    private func miniTouchpad(
        width touchpadWidth: CGFloat,
        height touchpadHeight: CGFloat,
        lightStyle: Bool,
        showLightBar: Bool = false
    ) -> some View {
        let pressed = isPressed(.touchpadButton)
        let baseColor: Color = lightStyle ? Color(white: 0.93) : Color(white: 0.16)
        let color = pressed ? Color.accentColor : baseColor
        let inQuadrantsMode = touchpadInputMode == .quadrants

        return ZStack {
            // Base touchpad shape
            RoundedRectangle(cornerRadius: 10)
                .fill(jewelGradient(color, pressed: pressed))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            lightStyle ? Color.black.opacity(0.18) : Color.white.opacity(0.12),
                            lineWidth: 0.8
                        )
                )

            // DualShock 4 light bar peeking over the pad's top edge
            if showLightBar {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.55, blue: 1.0),
                                     Color(red: 0.15, green: 0.35, blue: 0.95)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: touchpadWidth * 0.55, height: 3)
                    .offset(y: -touchpadHeight / 2 + 2.5)
                    .shadow(color: Color(red: 0.2, green: 0.45, blue: 1.0).opacity(0.7), radius: 3)
                    .allowsHitTesting(false)
            }

            // Quadrant divider cross is only meaningful in quadrants mode.
            // In whole-pad mode the entire pad is one binding target and the
            // dashed cross would mislead users.
            if inQuadrantsMode {
                quadrantDividers(width: touchpadWidth, height: touchpadHeight)
            }

            // Live activation overlay: which quadrant is currently being
            // touched, and is it being clicked? Drawn under the touch dot so
            // the dot stays visible. Touch = soft accent wash; click = brighter
            // accent fill — the click distinction makes a physical press
            // visually distinct from a finger that's just resting on the pad.
            if isTouchpadTouching {
                if inQuadrantsMode {
                    quadrantHighlight(
                        region: TouchpadRegion.from(position: touchpadPosition),
                        width: touchpadWidth,
                        height: touchpadHeight,
                        isClicked: isPressed(.touchpadButton)
                    )
                } else {
                    touchpadWholePadHighlight(
                        width: touchpadWidth,
                        height: touchpadHeight,
                        cornerRadius: 10,
                        isClicked: isPressed(.touchpadButton)
                    )
                }
            }

            // Primary touch point (dark dot on the white DualSense pad,
            // white dot on dark pads)
            let dotColor: Color = lightStyle ? Color(white: 0.2) : .white
            if isTouchpadTouching {
                Circle()
                    .fill(dotColor.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.5), radius: 3)
                    .offset(
                        x: touchpadPosition.x * (touchpadWidth / 2 - 5),
                        y: -touchpadPosition.y * (touchpadHeight / 2 - 5)
                    )
            }

            // Secondary touch point (two-finger)
            if isTouchpadSecondaryTouching {
                Circle()
                    .fill(dotColor.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.4), radius: 2)
                    .offset(
                        x: touchpadSecondaryPosition.x * (touchpadWidth / 2 - 4),
                        y: -touchpadSecondaryPosition.y * (touchpadHeight / 2 - 4)
                    )
            }

			touchpadOverrideOverlay(width: touchpadWidth, height: touchpadHeight, inQuadrantsMode: inQuadrantsMode)

            if inQuadrantsMode {
                quadrantTapZones(width: touchpadWidth, height: touchpadHeight)
            }
        }
        .frame(width: touchpadWidth, height: touchpadHeight)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .onTapGesture { onButtonTap(.touchpadButton) }
        // All touchpad connector anchors. Whole-pad and quadrant variants
        // both currently resolve to the entire pad rect; ConnectorLayer can
        // refine quadrant endpoints visually if needed. Stacking these as
        // sibling modifiers on the working chain (rather than nested child
        // views) is the only placement that reliably propagates region
        // anchors through SwiftUI's preference machinery here.
        .controllerAnchor(
            [.touchpadButton, .touchpadTap, .touchpadTwoFingerButton, .touchpadTwoFingerTap,
             .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick,
             .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch],
            role: .controller
        )
        .onHover { hovering in onButtonHover?(.touchpadButton, hovering) }
        .swappable(.touchpadButton, onSwap: onSwapRequest)
    }

    private func miniSteamTouchpad(side: SteamTouchpadSide, padSize: CGFloat, tilt: Double = 0) -> some View {
        let clickButton = side.wholeClickButton
        let tapButton = side.wholeTapButton
        let position = side == .left ? steamLeftTouchpadPosition : steamRightTouchpadPosition
        let isTouching = side == .left ? isSteamLeftTouchpadTouching : isSteamRightTouchpadTouching
        let inQuadrantsMode = touchpadInputMode == .quadrants
        let region = TouchpadRegion.from(position: position)
        let activeRegionClick = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click)
        let isClicked = isPressed(clickButton) || activeRegionClick.map(isPressed) == true
        let allButtons = [clickButton, tapButton] + ControllerButton.steamTouchpadRegionButtons(side: side)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(jewelGradient(isClicked ? Color.accentColor : Color(white: 0.18), pressed: isClicked))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.7)
                )
                .overlay(glassOverlay.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))

            if inQuadrantsMode {
                quadrantDividers(width: padSize, height: padSize)
            }

            if isTouching {
                if inQuadrantsMode {
                    quadrantHighlight(
                        region: region,
                        width: padSize,
                        height: padSize,
                        isClicked: isClicked
                    )
                } else {
                    touchpadWholePadHighlight(
                        width: padSize,
                        height: padSize,
                        cornerRadius: 8,
                        isClicked: isClicked
                    )
                }
            }

            if isTouching {
                Circle()
                    .fill(Color.white.opacity(0.82))
                    .frame(width: 9, height: 9)
                    .shadow(color: .white.opacity(0.45), radius: 3)
                    .offset(
                        x: position.x * (padSize / 2 - 5),
                        y: -position.y * (padSize / 2 - 5)
                    )
            }

            steamTouchpadOverrideOverlay(side: side, width: padSize, height: padSize, inQuadrantsMode: inQuadrantsMode)

            if inQuadrantsMode {
                steamTouchpadTapZones(side: side, width: padSize, height: padSize)
            }
        }
        .frame(width: padSize, height: padSize)
        .rotationEffect(.degrees(tilt))
        .shadow(color: isClicked ? Color.accentColor.opacity(0.35) : .black.opacity(0.25), radius: 2, x: 0, y: 1)
        .onTapGesture { onButtonTap(clickButton) }
        .controllerAnchor(allButtons, role: .controller)
        .onHover { hovering in onButtonHover?(clickButton, hovering) }
        .swappable(clickButton, onSwap: onSwapRequest)
    }

    /// Live highlight on the active quadrant. `isClicked` distinguishes a
    /// physical click (brighter, accent-saturated fill) from a passive touch
    /// (soft, low-opacity wash) so the same overlay communicates two
    /// different input states. Clipped to a rounded rectangle slightly inset
    /// from the touchpad's corner radius so it doesn't bleed past the bezel.
    private func quadrantHighlight(
        region: TouchpadRegion,
        width: CGFloat,
        height: CGFloat,
        isClicked: Bool
    ) -> some View {
        let halfW = width / 2
        let halfH = height / 2
        let originX: CGFloat = (region == .topLeft || region == .bottomLeft) ? 0 : halfW
        // SwiftUI Y grows downward inside this view; touchpad "top" maps to y=0.
        let originY: CGFloat = (region == .topLeft || region == .topRight) ? 0 : halfH
        let touchOpacity: Double = 0.18
        let clickOpacity: Double = 0.42
        return Rectangle()
            .fill(Color.accentColor.opacity(isClicked ? clickOpacity : touchOpacity))
            .frame(width: halfW, height: halfH)
            .position(x: originX + halfW / 2, y: originY + halfH / 2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: isClicked)
    }

    private func touchpadWholePadHighlight(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        isClicked: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(isClicked ? 0.32 : 0.16))
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: isClicked)
    }

    /// Subtle dashed cross dividing the touchpad into four quadrants. Visual
    /// only — no hit testing.
    private func quadrantDividers(width: CGFloat, height: CGFloat) -> some View {
        return ZStack {
            // Vertical divider at horizontal center
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: 4))
                path.addLine(to: CGPoint(x: width / 2, y: height - 4))
            }
            .stroke(Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [2, 2]))
            // Horizontal divider at vertical center
            Path { path in
                path.move(to: CGPoint(x: 4, y: height / 2))
                path.addLine(to: CGPoint(x: width - 4, y: height / 2))
            }
            .stroke(Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [2, 2]))
        }
        .allowsHitTesting(false)
    }

    /// 2×2 grid of transparent tap zones for hover/tap/drag handling.
    /// Connector anchors live in `quadrantAnchorOverlay`, separately attached
    /// to miniTouchpad's outer ZStack so they propagate to the connector
    /// preference reliably.
    private func quadrantTapZones(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                quadrantTapTarget(region: .topLeft, width: width / 2, height: height / 2)
                quadrantTapTarget(region: .topRight, width: width / 2, height: height / 2)
            }
            HStack(spacing: 0) {
                quadrantTapTarget(region: .bottomLeft, width: width / 2, height: height / 2)
                quadrantTapTarget(region: .bottomRight, width: width / 2, height: height / 2)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func touchpadOverrideOverlay(width: CGFloat, height: CGFloat, inQuadrantsMode: Bool) -> some View {
		let wholePadButtons: [ControllerButton] = [
			.touchpadButton,
			.touchpadTap,
			.touchpadTwoFingerButton,
			.touchpadTwoFingerTap
		]

		if let color = firstOverrideColor(for: wholePadButtons) {
			RoundedRectangle(cornerRadius: 10)
				.stroke(color.opacity(0.95), lineWidth: 2)
				.shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
				.frame(width: width, height: height)
		}

		if inQuadrantsMode {
			ForEach(TouchpadRegion.allCases) { region in
				touchpadRegionOverrideOutline(region: region, width: width, height: height)
			}
		}
	}

	@ViewBuilder
	private func touchpadRegionOverrideOutline(region: TouchpadRegion, width: CGFloat, height: CGFloat) -> some View {
		let buttons = [
			ControllerButton.from(region: region, trigger: .click),
			ControllerButton.from(region: region, trigger: .touch)
		].compactMap { $0 }

		if let color = firstOverrideColor(for: buttons) {
			let halfW = width / 2
			let halfH = height / 2
			let originX: CGFloat = (region == .topLeft || region == .bottomLeft) ? 0 : halfW
			let originY: CGFloat = (region == .topLeft || region == .topRight) ? 0 : halfH

			RoundedRectangle(cornerRadius: 6)
				.stroke(color.opacity(0.95), lineWidth: 1.5)
				.shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
				.frame(width: halfW - 5, height: halfH - 5)
				.position(x: originX + halfW / 2, y: originY + halfH / 2)
				.frame(width: width, height: height)
				.allowsHitTesting(false)
		}
    }

    @ViewBuilder
    private func quadrantTapTarget(region: TouchpadRegion, width: CGFloat, height: CGFloat) -> some View {
        let clickButton = ControllerButton.from(region: region, trigger: .click) ?? .touchpadButton
        let touchButton = ControllerButton.from(region: region, trigger: .touch) ?? .touchpadTap
        let isHovered = hoveredQuadrant == clickButton || hoveredQuadrant == touchButton
        Rectangle()
            .fill(Color.white.opacity(isHovered ? 0.12 : 0.001))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { onButtonTap(clickButton) }
            .onHover { hovering in
                if hovering {
                    hoveredQuadrant = clickButton
                } else if hoveredQuadrant == clickButton || hoveredQuadrant == touchButton {
                    hoveredQuadrant = nil
                }
                onButtonHover?(clickButton, hovering)
                _ = touchButton  // kept in scope so Swift doesn't elide the binding
            }
            .swappable(clickButton, onSwap: onSwapRequest)
    }

    private func steamTouchpadTapZones(side: SteamTouchpadSide, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                steamTouchpadTapTarget(side: side, region: .topLeft, width: width / 2, height: height / 2)
                steamTouchpadTapTarget(side: side, region: .topRight, width: width / 2, height: height / 2)
            }
            HStack(spacing: 0) {
                steamTouchpadTapTarget(side: side, region: .bottomLeft, width: width / 2, height: height / 2)
                steamTouchpadTapTarget(side: side, region: .bottomRight, width: width / 2, height: height / 2)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func steamTouchpadTapTarget(
        side: SteamTouchpadSide,
        region: TouchpadRegion,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let clickButton = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click) ?? side.wholeClickButton
        let touchButton = ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch) ?? side.wholeTapButton
        let isHovered = hoveredQuadrant == clickButton || hoveredQuadrant == touchButton

        Rectangle()
            .fill(Color.white.opacity(isHovered ? 0.12 : 0.001))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { onButtonTap(clickButton) }
            .onHover { hovering in
                if hovering {
                    hoveredQuadrant = clickButton
                } else if hoveredQuadrant == clickButton || hoveredQuadrant == touchButton {
                    hoveredQuadrant = nil
                }
                onButtonHover?(clickButton, hovering)
                _ = touchButton
            }
            .swappable(clickButton, onSwap: onSwapRequest)
    }

    @ViewBuilder
    private func steamTouchpadOverrideOverlay(
        side: SteamTouchpadSide,
        width: CGFloat,
        height: CGFloat,
        inQuadrantsMode: Bool
    ) -> some View {
        let wholePadButtons = [side.wholeClickButton, side.wholeTapButton]

        if let color = firstOverrideColor(for: wholePadButtons) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.95), lineWidth: 2)
                .shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
                .frame(width: width, height: height)
        }

        if inQuadrantsMode {
            ForEach(TouchpadRegion.allCases) { region in
                steamTouchpadRegionOverrideOutline(side: side, region: region, width: width, height: height)
            }
        }
    }

    @ViewBuilder
    private func steamTouchpadRegionOverrideOutline(
        side: SteamTouchpadSide,
        region: TouchpadRegion,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let buttons = [
            ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .click),
            ControllerButton.from(steamTouchpadSide: side, region: region, trigger: .touch),
        ].compactMap { $0 }

        if let color = firstOverrideColor(for: buttons) {
            let halfW = width / 2
            let halfH = height / 2
            let originX: CGFloat = (region == .topLeft || region == .bottomLeft) ? 0 : halfW
            let originY: CGFloat = (region == .topLeft || region == .topRight) ? 0 : halfH

            RoundedRectangle(cornerRadius: 5)
                .stroke(color.opacity(0.95), lineWidth: 1.4)
                .shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
                .frame(width: halfW - 5, height: halfH - 5)
                .position(x: originX + halfW / 2, y: originY + halfH / 2)
                .frame(width: width, height: height)
                .allowsHitTesting(false)
        }
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

    private func isPressed(_ button: ControllerButton) -> Bool {
		activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { activeButtons.contains($0) }
    }

    private func firstOverrideColor(for buttons: [ControllerButton]) -> Color? {
		for button in buttons {
			if let color = overrideColorForButton(button) {
				return color
			}
		}
		return nil
	}

	@ViewBuilder
	private func miniOverrideOutline<S: InsettableShape>(
		for button: ControllerButton,
		shape: S,
		lineWidth: CGFloat = 2
	) -> some View {
		miniOverrideOutline(for: [button], shape: shape, lineWidth: lineWidth)
	}

	@ViewBuilder
	private func miniOverrideOutline<S: InsettableShape>(
		for buttons: [ControllerButton],
		shape: S,
		lineWidth: CGFloat = 2
	) -> some View {
		if let color = firstOverrideColor(for: buttons) {
			shape
				.strokeBorder(color.opacity(0.95), lineWidth: lineWidth)
				.shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
				.allowsHitTesting(false)
		}
    }

    /// Analog trigger drawn as a rounded tab peeking over the body's top
    /// edge, with an accent fill that rises with pull pressure. `tilt`
    /// follows the local slope of the body's shoulder.
    private func miniTrigger(_ button: ControllerButton, label: String, value: Float, width: CGFloat = 34, tilt: Double = 0) -> some View {
        let height = width * 0.66
        let shape = TriggerTabShape()

        return ZStack(alignment: .bottom) {
            shape
                .fill(jewelGradient(Color(white: 0.2), pressed: false))
                .overlay(glassOverlay.clipShape(shape))
                .frame(width: width, height: height)

            // Fill based on pull pressure
            if value > 0 {
                Rectangle()
                    .fill(jewelGradient(Color.accentColor, pressed: isPressed(button)))
                    .frame(width: width, height: height * CGFloat(value))
            }

            Text(label)
                .font(.system(size: height * 0.40, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1)
                .frame(height: height)
        }
        .clipShape(shape)
        .overlay(miniOverrideOutline(for: button, shape: RoundedRectangle(cornerRadius: 5, style: .continuous), lineWidth: 2))
        .rotationEffect(.degrees(tilt))
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// Shoulder bumper: a slightly tilted strip hugging the body's top edge.
    private func miniBumper(_ button: ControllerButton, label: String, width: CGFloat = 38, tilt: Double = 0) -> some View {
        let height = width * 0.24
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.22)
        let shape = Capsule(style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: width, height: height)
            .overlay(
                Text(label)
                    .font(.system(size: height * 0.70, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
                    .shadow(radius: 1)
            )
            .overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .rotationEffect(.degrees(tilt))
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Bumper-shaped button with an icon inside (used for mic mute on DualSense)
    private func miniBumperWithIcon(_ button: ControllerButton, icon: String, width: CGFloat = 38) -> some View {
        let height = max(8, width * 0.48)
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.25)
        let shape = RoundedRectangle(cornerRadius: height * 0.4, style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: height * 0.62, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 1)
            )
            .overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Small pill button (DualSense Create/Options, DS4 Share/Options,
    /// Edge Fn). `size` is the pill height; width is derived.
    private func miniPill(_ button: ControllerButton, size: CGFloat, tilt: Double = 0) -> some View {
        let pressed = isPressed(button)
        let lightBody = isPlayStation && !isDualShock
        let baseColor: Color = lightBody ? Color(white: 0.90) : Color(white: 0.24)
        let color = pressed ? Color.accentColor : baseColor
        let shape = Capsule(style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: pressed))
            .overlay(
                shape.strokeBorder(
                    lightBody && !pressed ? Color.black.opacity(0.22) : Color.white.opacity(0.18),
                    lineWidth: 0.8
                )
            )
            .frame(width: size * 2.3, height: size)
            .overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .rotationEffect(.degrees(tilt))
            .shadow(color: pressed ? Color.accentColor.opacity(0.4) : .black.opacity(0.25), radius: 1.5)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// PlayStation logo button: borderless logo sitting directly on the
    /// black center deck, like the real hardware.
    private func miniPSButton(size: CGFloat) -> some View {
        let pressed = isPressed(.xbox)

        return Image(systemName: "playstation.logo")
            .font(.system(size: size, weight: .medium))
            .foregroundColor(pressed ? Color.accentColor : Color(white: 0.62))
            .shadow(color: pressed ? Color.accentColor.opacity(0.7) : .clear, radius: 4)
            .frame(width: size * 1.5, height: size * 1.5)
            .contentShape(Circle())
            .overlay(miniOverrideOutline(for: .xbox, shape: Circle(), lineWidth: 1.5))
            .onTapGesture { onButtonTap(.xbox) }
            .controllerAnchor(.xbox, role: .controller)
            .onHover { hovering in onButtonHover?(.xbox, hovering) }
            .swappable(.xbox, onSwap: onSwapRequest)
    }

    /// Back paddle / rear grip button peeking from behind the body into the
    /// valley between the grips. `metallic` renders the Elite's stainless
    /// blades; plain dark plastic otherwise (Edge, Steam grips).
    private func miniPaddle(
        _ button: ControllerButton,
        width: CGFloat,
        height: CGFloat,
        tilt: Double,
        metallic: Bool = false
    ) -> some View {
        let pressed = isPressed(button)
        let shape = Capsule(style: .continuous)
        let colors: [Color] = pressed
            ? [Color.accentColor, Color.accentColor.opacity(0.7)]
            : (metallic ? [Color(white: 0.74), Color(white: 0.36)] : [Color(white: 0.30), Color(white: 0.14)])

        return shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.strokeBorder(
                    metallic && !pressed ? Color.black.opacity(0.4) : Color.white.opacity(0.16),
                    lineWidth: 0.8
                )
            )
            .frame(width: width, height: height)
            .overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .rotationEffect(.degrees(tilt))
            .shadow(color: pressed ? Color.accentColor.opacity(0.4) : .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Thumbstick: recessed well + domed cap with a concave dish, following
    /// the live analog position.
    private func miniStick(_ button: ControllerButton, pos: CGPoint, wellSize: CGFloat = 30, eliteRing: Bool = false) -> some View {
        let directionButtons = button == .leftThumbstick
            ? ControllerButton.joystickDirectionButtons(side: .left)
            : ControllerButton.joystickDirectionButtons(side: .right)
        let isStickActive = isPressed(button) || directionButtons.contains(where: isPressed)
        let capSize = wellSize * 0.72

        return ZStack {
            // Recessed well
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.03), Color(white: 0.16)],
                        center: .center,
                        startRadius: wellSize * 0.18,
                        endRadius: wellSize * 0.52
                    )
                )
                .frame(width: wellSize, height: wellSize)
                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))

            // Elite's metallic accent ring around the well
            if eliteRing {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(white: 0.78), Color(white: 0.38)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: wellSize * 0.05
                    )
                    .frame(width: wellSize, height: wellSize)
            }

            // Cap: domed black rubber with a concave dish on top
            ZStack {
                Circle()
                    .fill(
                        jewelGradient(isStickActive ? Color.accentColor : Color(white: 0.20), pressed: isStickActive)
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.38), .clear],
                            center: UnitPoint(x: 0.5, y: 0.44),
                            startRadius: 0,
                            endRadius: capSize * 0.40
                        )
                    )
            }
            .frame(width: capSize, height: capSize)
            .offset(x: pos.x * wellSize * 0.16, y: -pos.y * wellSize * 0.16)
            .shadow(color: .black.opacity(0.45), radius: 2.5, x: 0, y: 2)
        }
        .overlay(miniOverrideOutline(for: [button] + directionButtons, shape: Circle(), lineWidth: 2))
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor([button] + directionButtons, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// Glyph shown inside a system button circle, adapted per controller.
    private func miniCircleGlyph(for button: ControllerButton) -> String? {
        switch button {
        case .view:
            return isNintendo ? "minus" : "rectangle.on.rectangle"
        case .menu:
            return isNintendo ? "plus" : "line.3.horizontal"
        case .share:
            return "square.and.arrow.up"
        default:
            return nil
        }
    }

    private func miniCircle(_ button: ControllerButton, size: CGFloat) -> some View {
        // The guide button is silver/chrome on Xbox; everything else is
        // dark plastic with a white glyph.
        let baseColor: Color = {
            if button == .xbox && !isNintendo && !isSteamController {
                return Color(white: 0.85)
            }
            return Color(white: 0.24)
        }()
        let color = isPressed(button) ? Color.accentColor : baseColor

        return ZStack {
            Circle()
                .fill(jewelGradient(color, pressed: isPressed(button)))
                .overlay(glassOverlay.clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

            if button == .xbox {
                if isSteamController {
                    SteamLogoMark(foregroundColor: isPressed(button) ? .white : Color(white: 0.78))
                        .frame(width: size * 0.62, height: size * 0.62)
                } else {
                    Image(systemName: isPlayStation ? "playstation.logo" : (isNintendo ? "house" : "xbox.logo"))
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundColor(isPressed(button) ? .white : (isNintendo ? Color(white: 0.85) : Color(white: 0.3)))
                }
            } else if isSteamController && button == .share {
                Image(systemName: "ellipsis")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundColor(.white.opacity(0.95))
            } else if let glyph = miniCircleGlyph(for: button) {
                Image(systemName: glyph)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniSquare(_ button: ControllerButton, size: CGFloat) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.24)
        let shape = RoundedRectangle(cornerRadius: size * 0.2)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .overlay(
                // Capture-button circle engraving
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    .frame(width: size * 0.45, height: size * 0.45)
            )
            .frame(width: size, height: size)
            .overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Lettered face button (Xbox/Elite/Nintendo/Steam style).
    private func miniFaceButton(_ button: ControllerButton, letter: String, letterColor: Color, size: CGFloat) -> some View {
        let pressed = isPressed(button)
        let base = pressed ? Color.accentColor : Color(white: 0.13)

        return ZStack {
            Circle()
                .fill(jewelGradient(base, pressed: pressed))
                .overlay(glassOverlay.clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))

            Text(letter)
                .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                .foregroundColor(pressed ? .white : letterColor)
                .shadow(color: pressed ? .clear : letterColor.opacity(0.5), radius: 1.5)
        }
        .frame(width: size, height: size)
        .overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: pressed ? Color.accentColor.opacity(0.5) : .black.opacity(0.3), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// PlayStation-style face button. The DualSense uses light buttons with
    /// muted grey symbols (like the real hardware); the DualShock 4 uses
    /// dark buttons with the classic colored symbols.
    private func miniPSFaceButton(_ button: ControllerButton, symbolColor: Color, size: CGFloat, lightStyle: Bool) -> some View {
        let pressed = isPressed(button)
        let bgColor = pressed ? Color.accentColor : (lightStyle ? Color(white: 0.92) : Color(white: 0.12))
        let symbol: String = {
            switch button {
            case .a: return "\u{2715}" // Cross
            case .b: return "\u{25CB}" // Circle
            case .x: return "\u{25A1}" // Square
            case .y: return "\u{25B3}" // Triangle
            default: return ""
            }
        }()

        return ZStack {
            Circle()
                .fill(jewelGradient(bgColor, pressed: pressed))
                .overlay(
                    Circle().strokeBorder(
                        lightStyle && !pressed ? Color.black.opacity(0.18) : Color.white.opacity(0.12),
                        lineWidth: 0.8
                    )
                )

            Text(symbol)
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundColor(pressed ? .white : symbolColor)
        }
        .frame(width: size, height: size)
        .overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: pressed ? Color.accentColor.opacity(0.5) : .black.opacity(0.25), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// Diamond of four face buttons, styled per controller family.
    /// `offset` is the center-to-button distance.
    private func miniFaceButtons(buttonSize: CGFloat = 12, offset: CGFloat = 12) -> some View {
        let cluster = (offset + buttonSize / 2) * 2 + 4

        return ZStack {
            switch minimapStyle {
            case .dualSense, .dualSenseEdge:
                let symbolColor = Color(white: 0.45)
                miniPSFaceButton(.y, symbolColor: symbolColor, size: buttonSize, lightStyle: true).offset(y: -offset)
                miniPSFaceButton(.a, symbolColor: symbolColor, size: buttonSize, lightStyle: true).offset(y: offset)
                miniPSFaceButton(.x, symbolColor: symbolColor, size: buttonSize, lightStyle: true).offset(x: -offset)
                miniPSFaceButton(.b, symbolColor: symbolColor, size: buttonSize, lightStyle: true).offset(x: offset)
            case .dualShock:
                miniPSFaceButton(.y, symbolColor: ButtonColors.psTriangle, size: buttonSize, lightStyle: false).offset(y: -offset)
                miniPSFaceButton(.a, symbolColor: ButtonColors.psCross, size: buttonSize, lightStyle: false).offset(y: offset)
                miniPSFaceButton(.x, symbolColor: ButtonColors.psSquare, size: buttonSize, lightStyle: false).offset(x: -offset)
                miniPSFaceButton(.b, symbolColor: ButtonColors.psCircle, size: buttonSize, lightStyle: false).offset(x: offset)
            case .xbox:
                miniFaceButton(.y, letter: "Y", letterColor: ButtonColors.xboxY, size: buttonSize).offset(y: -offset)
                miniFaceButton(.a, letter: "A", letterColor: ButtonColors.xboxA, size: buttonSize).offset(y: offset)
                miniFaceButton(.x, letter: "X", letterColor: ButtonColors.xboxX, size: buttonSize).offset(x: -offset)
                miniFaceButton(.b, letter: "B", letterColor: ButtonColors.xboxB, size: buttonSize).offset(x: offset)
            case .xboxElite, .nintendo, .steam:
                let letterColor = Color(white: 0.85)
                miniFaceButton(.y, letter: "Y", letterColor: letterColor, size: buttonSize).offset(y: -offset)
                miniFaceButton(.a, letter: "A", letterColor: letterColor, size: buttonSize).offset(y: offset)
                miniFaceButton(.x, letter: "X", letterColor: letterColor, size: buttonSize).offset(x: -offset)
                miniFaceButton(.b, letter: "B", letterColor: letterColor, size: buttonSize).offset(x: offset)
            }
        }
        .frame(width: cluster, height: cluster)
    }

    // MARK: - Mini D-Pad

    enum MiniDPadStyle {
        /// Cross sitting on a recessed dark disc (Xbox Series).
        case xboxDisc
        /// Faceted metallic disc (Xbox Elite Series 2).
        case eliteDisc
        /// Plain glossy cross (Nintendo Pro, Steam Controller).
        case cross
        /// Four separate chiclet buttons (DualSense, DualShock).
        case chiclets
    }

    private func miniDPad(span: CGFloat = 24, style: MiniDPadStyle = .cross) -> some View {
        let arm = span * 0.30

        return ZStack {
            // Disc base behind the cross
            if style == .xboxDisc {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.05), Color(white: 0.14)],
                            center: .center,
                            startRadius: span * 0.1,
                            endRadius: span * 0.62
                        )
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                    .frame(width: span * 1.22, height: span * 1.22)
            } else if style == .eliteDisc {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.80), Color(white: 0.40)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: span * 1.22, height: span * 1.22)

                // Facet seams
                ZStack {
                    Rectangle().frame(width: 0.8, height: span * 1.22)
                    Rectangle().frame(width: span * 1.22, height: 0.8)
                    Rectangle().frame(width: 0.8, height: span * 1.22).rotationEffect(.degrees(45))
                    Rectangle().frame(width: 0.8, height: span * 1.22).rotationEffect(.degrees(-45))
                }
                .foregroundColor(Color.black.opacity(0.22))
                .mask(Circle().frame(width: span * 1.22, height: span * 1.22))
            }

            if style == .chiclets {
                dpadChiclet(.dpadUp, glyph: "arrowtriangle.up.fill", size: arm).offset(y: -span * 0.34)
                dpadChiclet(.dpadDown, glyph: "arrowtriangle.down.fill", size: arm).offset(y: span * 0.34)
                dpadChiclet(.dpadLeft, glyph: "arrowtriangle.left.fill", size: arm).offset(x: -span * 0.34)
                dpadChiclet(.dpadRight, glyph: "arrowtriangle.right.fill", size: arm).offset(x: span * 0.34)
            } else {
                // Joined cross. Glossy near-black for the standalone cross
                // (Nintendo/Steam) so it stands out against the dark body.
                let crossColor: Color = style == .eliteDisc ? Color(white: 0.58) : Color(white: 0.08)
                DPadCrossShape(armRatio: 0.30)
                    .fill(jewelGradient(crossColor, pressed: false))
                    .frame(width: span, height: span)
                    .shadow(radius: 1)

                if style == .cross {
                    DPadCrossShape(armRatio: 0.30)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                        .frame(width: span, height: span)
                        .allowsHitTesting(false)
                }

                // Active states (lighting up)
                if isPressed(.dpadUp) {
                    RoundedRectangle(cornerRadius: arm * 0.25).fill(Color.accentColor)
                        .frame(width: arm, height: span * 0.42).offset(y: -span * 0.29).blur(radius: 2)
                }
                if isPressed(.dpadDown) {
                    RoundedRectangle(cornerRadius: arm * 0.25).fill(Color.accentColor)
                        .frame(width: arm, height: span * 0.42).offset(y: span * 0.29).blur(radius: 2)
                }
                if isPressed(.dpadLeft) {
                    RoundedRectangle(cornerRadius: arm * 0.25).fill(Color.accentColor)
                        .frame(width: span * 0.42, height: arm).offset(x: -span * 0.29).blur(radius: 2)
                }
                if isPressed(.dpadRight) {
                    RoundedRectangle(cornerRadius: arm * 0.25).fill(Color.accentColor)
                        .frame(width: span * 0.42, height: arm).offset(x: span * 0.29).blur(radius: 2)
                }
            }

            dpadOverrideOverlay(span: span)

            // Tap zones — `.offset` is render-only and works fine for hit-testing.
            // Anchors are reported separately by the markers below, since `.offset`
            // does NOT propagate into anchor preference reads from ancestor proxies.
            Group {
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: span * 0.6, height: span * 0.55)
                    .offset(y: -span * 0.28)
                    .onTapGesture { onButtonTap(.dpadUp) }
                    .onHover { hovering in onButtonHover?(.dpadUp, hovering) }
                    .swappable(.dpadUp, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: span * 0.6, height: span * 0.55)
                    .offset(y: span * 0.28)
                    .onTapGesture { onButtonTap(.dpadDown) }
                    .onHover { hovering in onButtonHover?(.dpadDown, hovering) }
                    .swappable(.dpadDown, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: span * 0.55, height: span * 0.6)
                    .offset(x: -span * 0.28)
                    .onTapGesture { onButtonTap(.dpadLeft) }
                    .onHover { hovering in onButtonHover?(.dpadLeft, hovering) }
                    .swappable(.dpadLeft, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: span * 0.55, height: span * 0.6)
                    .offset(x: span * 0.28)
                    .onTapGesture { onButtonTap(.dpadRight) }
                    .onHover { hovering in onButtonHover?(.dpadRight, hovering) }
                    .swappable(.dpadRight, onSwap: onSwapRequest)
            }

            // Connector anchor markers. VStack/HStack layout guarantees each
            // marker's reported anchor sits at the corresponding edge of the
            // d-pad cross, so per-direction connector lines emerge correctly.
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadUp, role: .controller)
                Spacer(minLength: 0)
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadDown, role: .controller)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadLeft, role: .controller)
                Spacer(minLength: 0)
                Color.clear.frame(width: 1, height: 1)
                    .controllerAnchor(.dpadRight, role: .controller)
            }
        }
        .frame(width: span, height: span)
    }

    /// One separated d-pad button for the PlayStation chiclet style.
    private func dpadChiclet(_ button: ControllerButton, glyph: String, size: CGFloat) -> some View {
        let pressed = isPressed(button)
        let lightBody = isPlayStation && !isDualShock
        let base: Color = lightBody ? Color(white: 0.90) : Color(white: 0.18)
        let glyphColor: Color = lightBody ? Color(white: 0.45) : Color(white: 0.65)
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)

        return shape
            .fill(jewelGradient(pressed ? Color.accentColor : base, pressed: pressed))
            .overlay(
                shape.strokeBorder(
                    lightBody && !pressed ? Color.black.opacity(0.16) : Color.white.opacity(0.10),
                    lineWidth: 0.8
                )
            )
            .frame(width: size * 1.15, height: size * 1.15)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(pressed ? .white : glyphColor)
            )
            .shadow(color: pressed ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1.5)
            .allowsHitTesting(false)
    }

    private func dpadOverrideOverlay(span: CGFloat) -> some View {
        ZStack {
            dpadOverrideSegment(.dpadUp, width: span * 0.42, height: span * 0.5)
                .offset(y: -span * 0.25)
            dpadOverrideSegment(.dpadDown, width: span * 0.42, height: span * 0.5)
                .offset(y: span * 0.25)
            dpadOverrideSegment(.dpadLeft, width: span * 0.5, height: span * 0.42)
                .offset(x: -span * 0.25)
            dpadOverrideSegment(.dpadRight, width: span * 0.5, height: span * 0.42)
                .offset(x: span * 0.25)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dpadOverrideSegment(_ button: ControllerButton, width: CGFloat, height: CGFloat) -> some View {
        if let color = overrideColorForButton(button) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(color.opacity(0.95), lineWidth: 1.3)
                .shadow(color: color.opacity(0.45), radius: 3, x: 0, y: 0)
                .frame(width: width, height: height)
        }
    }
}

/// Plus-shaped d-pad cross as a single path (no internal seams when stroked).
private struct DPadCrossShape: Shape {
    /// Arm thickness as a fraction of the span.
    let armRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let span = min(rect.width, rect.height)
        let arm = span * armRatio
        let r = arm * 0.25
        let cx = rect.midX
        let cy = rect.midY
        let h = arm / 2
        let s = span / 2

        var p = Path()
        // Clockwise outline: 4 arm tips with rounded outer corners,
        // square inner corners where the arms meet.
        p.move(to: CGPoint(x: cx - h, y: cy - s + r))
        p.addQuadCurve(to: CGPoint(x: cx - h + r, y: cy - s), control: CGPoint(x: cx - h, y: cy - s))
        p.addLine(to: CGPoint(x: cx + h - r, y: cy - s))
        p.addQuadCurve(to: CGPoint(x: cx + h, y: cy - s + r), control: CGPoint(x: cx + h, y: cy - s))
        p.addLine(to: CGPoint(x: cx + h, y: cy - h))
        p.addLine(to: CGPoint(x: cx + s - r, y: cy - h))
        p.addQuadCurve(to: CGPoint(x: cx + s, y: cy - h + r), control: CGPoint(x: cx + s, y: cy - h))
        p.addLine(to: CGPoint(x: cx + s, y: cy + h - r))
        p.addQuadCurve(to: CGPoint(x: cx + s - r, y: cy + h), control: CGPoint(x: cx + s, y: cy + h))
        p.addLine(to: CGPoint(x: cx + h, y: cy + h))
        p.addLine(to: CGPoint(x: cx + h, y: cy + s - r))
        p.addQuadCurve(to: CGPoint(x: cx + h - r, y: cy + s), control: CGPoint(x: cx + h, y: cy + s))
        p.addLine(to: CGPoint(x: cx - h + r, y: cy + s))
        p.addQuadCurve(to: CGPoint(x: cx - h, y: cy + s - r), control: CGPoint(x: cx - h, y: cy + s))
        p.addLine(to: CGPoint(x: cx - h, y: cy + h))
        p.addLine(to: CGPoint(x: cx - s + r, y: cy + h))
        p.addQuadCurve(to: CGPoint(x: cx - s, y: cy + h - r), control: CGPoint(x: cx - s, y: cy + h))
        p.addLine(to: CGPoint(x: cx - s, y: cy - h + r))
        p.addQuadCurve(to: CGPoint(x: cx - s + r, y: cy - h), control: CGPoint(x: cx - s, y: cy - h))
        p.addLine(to: CGPoint(x: cx - h, y: cy - h))
        p.closeSubpath()
        return p
    }
}

/// Rounded-top tab used for the analog triggers.
private struct TriggerTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width * 0.30, rect.height * 0.45)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
