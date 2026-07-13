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
    /// Non-nil when previewing one of the small 8BitDo pads; selects the
    /// dedicated silhouette + layout instead of the boolean style families.
    var eightBitDoModel: EightBitDoMinimapModel? = nil
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
        if let eightBitDoModel { return eightBitDoModel.minimapStyle }
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
        overlayContent
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


    // MARK: - 8BitDo Overlays

    private func eightBitDoOverlay(_ model: EightBitDoMinimapModel) -> some View {
        let size = frameSize

        return ZStack {
            switch model {
            case .zero2: eightBitDoZero2Controls(size: size, w: size.width)
            case .micro: eightBitDoMicroControls(size: size, w: size.width)
            case .lite2: eightBitDoLite2Controls(size: size, w: size.width)
            case .liteSE: eightBitDoLiteSEControls(size: size, w: size.width)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func eightBitDoZero2Controls(size: CGSize, w: CGFloat) -> some View {
        let layout = EightBitDoZero2MinimapLayout.self

		miniZero2Bumper(.leftBumper, label: "L", width: w * layout.bumperWidth, tilt: -5)
            .minimapPosition(layout.leftBumper, in: size)
		miniZero2Bumper(.rightBumper, label: "R", width: w * layout.bumperWidth, tilt: 5)
            .minimapPosition(layout.rightBumper, in: size)

        miniLightGlyphButton(.view, systemImage: "minus", size: w * layout.selectStartSize)
            .minimapPosition(layout.select, in: size)
        miniLightGlyphButton(.menu, systemImage: "plus", size: w * layout.selectStartSize)
            .minimapPosition(layout.start, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        miniDPad(span: w * layout.dpadSize, style: .lightCross)
            .minimapPosition(layout.dpad, in: size)

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    @ViewBuilder
    private func eightBitDoMicroControls(size: CGSize, w: CGFloat) -> some View {
        let layout = EightBitDoMicroMinimapLayout.self

        miniTrigger(.leftTrigger, label: "L2", value: leftTrigger, width: w * 0.10)
            .minimapPosition(layout.leftTrigger, in: size)
        miniTrigger(.rightTrigger, label: "R2", value: rightTrigger, width: w * 0.10)
            .minimapPosition(layout.rightTrigger, in: size)
        miniBumper(.leftBumper, label: "L", width: w * 0.12)
            .minimapPosition(layout.leftBumper, in: size)
        miniBumper(.rightBumper, label: "R", width: w * 0.12)
            .minimapPosition(layout.rightBumper, in: size)

        miniLightGlyphButton(.view, systemImage: "minus", size: w * layout.minusPlusSize)
            .minimapPosition(layout.minus, in: size)
        miniLightGlyphButton(.menu, systemImage: "plus", size: w * layout.minusPlusSize)
            .minimapPosition(layout.plus, in: size)
        miniCircle(.share, size: w * layout.starHomeSize, interactive: false)
            .minimapPosition(layout.star, in: size)
        miniCircle(.xbox, size: w * layout.starHomeSize)
            .minimapPosition(layout.home, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        miniDPad(span: w * layout.dpadSize, style: .lightCross)
            .minimapPosition(layout.dpad, in: size)

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    @ViewBuilder
    private func eightBitDoLite2Controls(size: CGSize, w: CGFloat) -> some View {
        let layout = EightBitDoLite2MinimapLayout.self

        miniTrigger(.leftTrigger, label: "L2", value: leftTrigger, width: w * 0.09)
            .minimapPosition(layout.leftTrigger, in: size)
        miniTrigger(.rightTrigger, label: "R2", value: rightTrigger, width: w * 0.09)
            .minimapPosition(layout.rightTrigger, in: size)
        miniBumper(.leftBumper, label: "L", width: w * 0.12)
            .minimapPosition(layout.leftBumper, in: size)
        miniBumper(.rightBumper, label: "R", width: w * 0.12)
            .minimapPosition(layout.rightBumper, in: size)

        miniLightGlyphButton(.view, systemImage: "minus", size: w * layout.minusPlusSize)
            .minimapPosition(layout.minus, in: size)
        miniLightGlyphButton(.menu, systemImage: "plus", size: w * layout.minusPlusSize)
            .minimapPosition(layout.plus, in: size)
        miniCircle(.share, size: w * layout.starHomeSize, interactive: false)
            .minimapPosition(layout.star, in: size)
        miniCircle(.xbox, size: w * layout.starHomeSize)
            .minimapPosition(layout.home, in: size)

        miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize, lightCap: true)
            .minimapPosition(layout.leftStick, in: size)
        miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize, lightCap: true)
            .minimapPosition(layout.rightStick, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        miniDPad(span: w * layout.dpadSize, style: .lightCross)
            .minimapPosition(layout.dpad, in: size)

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    @ViewBuilder
    private func eightBitDoLiteSEControls(size: CGSize, w: CGFloat) -> some View {
        let layout = EightBitDoLiteSEMinimapLayout.self

        // The accessibility layout puts the whole shoulder set on the face
        // as round labeled buttons.
        miniLightFaceButton(.leftTrigger, letter: "L2", size: w * layout.faceRowSize)
            .minimapPosition(layout.l2, in: size)
        miniLightFaceButton(.rightTrigger, letter: "R2", size: w * layout.faceRowSize)
            .minimapPosition(layout.r2, in: size)
        miniLightFaceButton(.leftBumper, letter: "L", size: w * layout.faceRowSize)
            .minimapPosition(layout.l1, in: size)
        miniLightFaceButton(.rightBumper, letter: "R", size: w * layout.faceRowSize)
            .minimapPosition(layout.r1, in: size)

        miniLightGlyphButton(.view, systemImage: "minus", size: w * layout.faceRowSize)
            .minimapPosition(layout.minus, in: size)
        miniLightGlyphButton(.menu, systemImage: "plus", size: w * layout.faceRowSize)
            .minimapPosition(layout.plus, in: size)
        miniCircle(.share, size: w * layout.starHomeSize, interactive: false)
            .minimapPosition(layout.star, in: size)
        miniCircle(.xbox, size: w * layout.starHomeSize)
            .minimapPosition(layout.home, in: size)

        // D-pad: four separate round arrow buttons.
        miniLightGlyphButton(.dpadUp, systemImage: "arrowtriangle.up.fill", size: w * layout.faceRowSize)
            .minimapPosition(layout.dpadUp, in: size)
        miniLightGlyphButton(.dpadDown, systemImage: "arrowtriangle.down.fill", size: w * layout.faceRowSize)
            .minimapPosition(layout.dpadDown, in: size)
        miniLightGlyphButton(.dpadLeft, systemImage: "arrowtriangle.left.fill", size: w * layout.faceRowSize)
            .minimapPosition(layout.dpadLeft, in: size)
        miniLightGlyphButton(.dpadRight, systemImage: "arrowtriangle.right.fill", size: w * layout.faceRowSize)
            .minimapPosition(layout.dpadRight, in: size)

        // L3/R3 face buttons click the sticks; the stick wells below own the
        // mappable anchors, so these render as decoration.
        ForEach([("L3", layout.l3), ("R3", layout.r3)], id: \.0) { label, point in
            ZStack {
                Circle()
                    .fill(Color(white: 0.93))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))
                Text(label)
                    .font(.system(size: w * layout.stickClickSize * 0.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.45))
            }
            .frame(width: w * layout.stickClickSize, height: w * layout.stickClickSize)
            .minimapPosition(point, in: size)
            .allowsHitTesting(false)
        }

        miniStick(.leftThumbstick, pos: leftStick, wellSize: w * layout.stickWellSize, lightCap: true)
            .minimapPosition(layout.leftStick, in: size)
        miniStick(.rightThumbstick, pos: rightStick, wellSize: w * layout.stickWellSize, lightCap: true)
            .minimapPosition(layout.rightStick, in: size)

        miniFaceButtons(
            buttonSize: w * layout.faceButtonSize,
            offset: w * layout.faceButtonOffset
        )
        .minimapPosition(layout.faceCluster, in: size)

        if isConnected {
            BatteryView(level: batteryLevel, state: batteryState)
                .minimapPosition(layout.battery, in: size)
        }
    }

    /// Controller dispatch, type-erased: six statically-typed branches push
    /// `body`'s generic signature past what SILGen handles in Release builds
    /// (the Swift frontend crashes lowering the conditional). One AnyView at
    /// the root keeps the per-controller subtrees' identity stable while the
    /// 15Hz analog state updates re-evaluate the same branch.
    private var overlayContent: AnyView {
        if let model = eightBitDoModel { return AnyView(eightBitDoOverlay(model)) }
        if isSteamController { return AnyView(steamOverlay) }
        if isDualShock { return AnyView(dualShockOverlay) }
        if isPlayStation { return AnyView(dualSenseOverlay) }
        if isNintendo { return AnyView(nintendoOverlay) }
        return AnyView(xboxOverlay)
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
            miniTrigger(.leftTrigger, label: "LT", value: leftTrigger, width: w * 0.065, tilt: -18)
                .minimapPosition(layout.leftTrigger, in: size)
            miniTrigger(.rightTrigger, label: "RT", value: rightTrigger, width: w * 0.065, tilt: 18)
                .minimapPosition(layout.rightTrigger, in: size)
            miniBumper(.leftBumper, label: "LB", width: w * 0.105, tilt: -8)
                .minimapPosition(layout.leftBumper, in: size)
            miniBumper(.rightBumper, label: "RB", width: w * 0.105, tilt: 8)
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

            // Create / Options: near-vertical pills beside the touchpad's
            // top corners, tops leaning slightly outward like the hardware
            miniPill(.view, size: w * layout.createOptionsSize, tilt: 80)
                .minimapPosition(layout.create, in: size)
            miniPill(.menu, size: w * layout.createOptionsSize, tilt: 100)
                .minimapPosition(layout.options, in: size)

            miniTouchpad(
                width: w * layout.touchpadSize.width,
                height: size.height * layout.touchpadSize.height,
                lightStyle: !isDualSenseEdge,
                bottomTaper: w * layout.touchpadBottomTaper
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

            // Share / Options: vertical pills in the dips beside the touchpad
            miniPill(.view, size: w * layout.shareOptionsSize, tilt: 90)
                .minimapPosition(layout.share, in: size)
            miniPill(.menu, size: w * layout.shareOptionsSize, tilt: 90)
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
        showLightBar: Bool = false,
        bottomTaper: CGFloat = 0
    ) -> some View {
        let pressed = isPressed(.touchpadButton)
        let baseColor: Color = lightStyle ? Color(white: 0.93) : Color(white: 0.16)
        let color = pressed ? Color.accentColor : baseColor
        let inQuadrantsMode = touchpadInputMode == .quadrants
        let padShape = RoundedTrapezoidShape(bottomInset: bottomTaper, cornerRadius: 10)

        return ZStack {
            // Base touchpad shape
            padShape
                .fill(jewelGradient(color, pressed: pressed))
                .overlay(
                    padShape
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
                    .frame(width: touchpadWidth * 0.85, height: 3.5)
                    .offset(y: -touchpadHeight / 2 + 3)
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
                    padShape
                        .fill(Color.accentColor.opacity(isPressed(.touchpadButton) ? 0.32 : 0.16))
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.08), value: isPressed(.touchpadButton))
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
		if activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains(where: { activeButtons.contains($0) }) {
			return true
		}
		// Stickless 8BitDo pads route their physical d-pad through the left
		// stick, so in Mouse mode no .dpad* button is "pressed". Reflect the
		// stick deflection onto the d-pad so the minimap shows the press
		// regardless of the stick mode.
		if eightBitDoModel?.isStickless == true, dpadActiveFromLeftStick(button) {
			return true
		}
		return false
    }

	/// True when the left stick is deflected toward `button`'s d-pad direction.
	/// +y is up (GameController convention); threshold matches the D-Pad mode.
	private func dpadActiveFromLeftStick(_ button: ControllerButton) -> Bool {
		let threshold: CGFloat = 0.4
		switch button {
		case .dpadUp:    return leftStick.y > threshold
		case .dpadDown:  return leftStick.y < -threshold
		case .dpadLeft:  return leftStick.x < -threshold
		case .dpadRight: return leftStick.x > threshold
		default:         return false
		}
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

    /// Zero 2 shoulder tab: the product photo shows shallow white caps
    /// peeking above the teal face rather than dark bumper strips.
    private func miniZero2Bumper(_ button: ControllerButton, label: String, width: CGFloat, tilt: Double) -> some View {
		let pressed = isPressed(button)
		let height = width * 0.22
		let shape = Capsule(style: .continuous)
		let base = pressed ? Color.accentColor : Color(white: 0.92)

		return shape
			.fill(jewelGradient(base, pressed: pressed))
			.overlay(glassOverlay.clipShape(shape))
			.overlay(
				shape.strokeBorder(
					pressed ? Color.white.opacity(0.35) : Color.black.opacity(0.16),
					lineWidth: 0.8
				)
			)
			.frame(width: width, height: height)
			.overlay(
				Text(label)
					.font(.system(size: height * 0.62, weight: .bold, design: .rounded))
					.foregroundColor(pressed ? .white : Color(white: 0.42))
			)
			.overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
			.rotationEffect(.degrees(tilt))
			.shadow(color: pressed ? Color.accentColor.opacity(0.42) : .black.opacity(0.18), radius: 2, x: 0, y: 1)
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
    private func miniStick(_ button: ControllerButton, pos: CGPoint, wellSize: CGFloat = 30, eliteRing: Bool = false, lightCap: Bool = false) -> some View {
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
                        jewelGradient(isStickActive ? Color.accentColor : Color(white: lightCap ? 0.88 : 0.20), pressed: isStickActive)
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(lightCap ? 0.12 : 0.38), .clear],
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
        let usesNintendoGlyphs = isNintendo || eightBitDoModel != nil
        switch button {
        case .view:
            return usesNintendoGlyphs ? "minus" : "rectangle.on.rectangle"
        case .menu:
            return usesNintendoGlyphs ? "plus" : "line.3.horizontal"
        case .share:
            return eightBitDoModel != nil ? "star.fill" : "square.and.arrow.up"
        default:
            return nil
        }
    }

    private func miniCircle(_ button: ControllerButton, size: CGFloat, interactive: Bool = true) -> some View {
        // The guide button is silver/chrome on Xbox; everything else is
        // dark plastic with a white glyph.
        let baseColor: Color = {
            if button == .xbox && !isNintendo && !isSteamController && eightBitDoModel == nil {
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
                } else if eightBitDoModel != nil {
                    Image("EightBitDoLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.6, height: size * 0.48)
                        .foregroundColor(isPressed(button) ? .white : Color(white: 0.85))
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
        // Non-interactive buttons (e.g. the 8BitDo star/profile button, which
        // the firmware consumes) render as decoration: no tap, hover, or swap.
        .allowsHitTesting(interactive)
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


    /// White-capped lettered button (8BitDo style: white caps, grey glyphs).
    private func miniLightFaceButton(_ button: ControllerButton, letter: String, size: CGFloat) -> some View {
        let pressed = isPressed(button)
        let base = pressed ? Color.accentColor : Color(white: 0.93)

        return ZStack {
            Circle()
                .fill(jewelGradient(base, pressed: pressed))
                .overlay(glassOverlay.clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))

            Text(letter)
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundColor(pressed ? .white : Color(white: 0.45))
        }
        .frame(width: size, height: size)
        .overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: pressed ? Color.accentColor.opacity(0.5) : .black.opacity(0.25), radius: 1.5)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// White-capped button with an SF Symbol glyph (8BitDo Lite SE d-pad arrows).
    private func miniLightGlyphButton(_ button: ControllerButton, systemImage: String, size: CGFloat) -> some View {
        let pressed = isPressed(button)
        let base = pressed ? Color.accentColor : Color(white: 0.93)

        return ZStack {
            Circle()
                .fill(jewelGradient(base, pressed: pressed))
                .overlay(glassOverlay.clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))

            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(pressed ? .white : Color(white: 0.45))
        }
        .frame(width: size, height: size)
        .overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: pressed ? Color.accentColor.opacity(0.5) : .black.opacity(0.25), radius: 1.5)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    /// PlayStation-style face button. The DualSense uses light buttons with
    /// muted grey symbols (like the real hardware); the DualShock 4 uses
    /// dark buttons with the classic colored symbols. SF Symbols rather
    /// than Unicode glyphs — the text glyphs (△ ○ □ ✕) have inconsistent
    /// optical sizes in the system font (the triangle renders smaller).
    private func miniPSFaceButton(_ button: ControllerButton, symbolColor: Color, size: CGFloat, lightStyle: Bool) -> some View {
        let pressed = isPressed(button)
        let bgColor = pressed ? Color.accentColor : (lightStyle ? Color(white: 0.92) : Color(white: 0.12))
        let symbolName: String = {
            switch button {
            case .a: return "xmark"    // Cross
            case .b: return "circle"   // Circle
            case .x: return "square"   // Square
            case .y: return "triangle" // Triangle
            default: return "questionmark"
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

            Image(systemName: symbolName)
                .font(.system(size: size * 0.42, weight: .bold))
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
            case .xboxElite, .steam:
                // Xbox-layout face buttons (Y north, A south, X west, B east).
                let letterColor = Color(white: 0.85)
                miniFaceButton(.y, letter: "Y", letterColor: letterColor, size: buttonSize).offset(y: -offset)
                miniFaceButton(.a, letter: "A", letterColor: letterColor, size: buttonSize).offset(y: offset)
                miniFaceButton(.x, letter: "X", letterColor: letterColor, size: buttonSize).offset(x: -offset)
                miniFaceButton(.b, letter: "B", letterColor: letterColor, size: buttonSize).offset(x: offset)
            case .nintendo:
                // Nintendo physical diamond: X north, A east, B south, Y west.
                // macOS maps these pads by LABEL (.a is the printed-A button,
                // etc.), so each button keeps its own letter and we place it
                // at its physical slot. Pressing a button then lights the
                // matching position with the matching letter.
                let letterColor = Color(white: 0.85)
                miniFaceButton(.x, letter: "X", letterColor: letterColor, size: buttonSize).offset(y: -offset)  // north
                miniFaceButton(.b, letter: "B", letterColor: letterColor, size: buttonSize).offset(y: offset)   // south
                miniFaceButton(.y, letter: "Y", letterColor: letterColor, size: buttonSize).offset(x: -offset)  // west
                miniFaceButton(.a, letter: "A", letterColor: letterColor, size: buttonSize).offset(x: offset)   // east
            case .eightBitDoZero2, .eightBitDoMicro, .eightBitDoLite2, .eightBitDoLiteSE:
                // 8BitDo pads use the Nintendo physical diamond (X north,
                // A east, B south, Y west). White caps, engraved grey letters.
                // Same label-mapped positioning as .nintendo.
                miniLightFaceButton(.x, letter: "X", size: buttonSize).offset(y: -offset)  // north
                miniLightFaceButton(.b, letter: "B", size: buttonSize).offset(y: offset)   // south
                miniLightFaceButton(.y, letter: "Y", size: buttonSize).offset(x: -offset)  // west
                miniLightFaceButton(.a, letter: "A", size: buttonSize).offset(x: offset)   // east
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
        /// White glossy cross on a colored body (8BitDo pads).
        case lightCross
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
                // (Nintendo/Steam) so it stands out against the dark body;
                // white for the 8BitDo pads' silver crosses on colored shells.
                let crossColor: Color = {
                    switch style {
                    case .eliteDisc: return Color(white: 0.58)
                    case .lightCross: return Color(white: 0.90)
                    default: return Color(white: 0.08)
                    }
                }()
                DPadCrossShape(armRatio: 0.30)
                    .fill(jewelGradient(crossColor, pressed: false))
                    .frame(width: span, height: span)
                    .shadow(radius: 1)

                if style == .cross || style == .lightCross {
                    DPadCrossShape(armRatio: 0.30)
                        .stroke(style == .lightCross ? Color.black.opacity(0.25) : Color.white.opacity(0.22), lineWidth: 0.8)
                        .frame(width: span, height: span)
                        .allowsHitTesting(false)
                }

				if style == .lightCross {
					Group {
						dpadEmbossedArrow("arrowtriangle.up.fill", size: arm).offset(y: -span * 0.30)
						dpadEmbossedArrow("arrowtriangle.down.fill", size: arm).offset(y: span * 0.30)
						dpadEmbossedArrow("arrowtriangle.left.fill", size: arm).offset(x: -span * 0.30)
						dpadEmbossedArrow("arrowtriangle.right.fill", size: arm).offset(x: span * 0.30)
					}
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

    /// Subtle embossed arrow glyphs for the 8BitDo white cross d-pad.
    private func dpadEmbossedArrow(_ glyph: String, size: CGFloat) -> some View {
		Image(systemName: glyph)
			.font(.system(size: size * 0.58, weight: .bold))
			.foregroundStyle(Color.black.opacity(0.13))
			.shadow(color: .white.opacity(0.24), radius: 0.5, x: 0, y: -0.5)
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

/// Rounded rectangle whose bottom edge is slightly narrower than the top
/// (the DualSense touchpad's subtle trapezoid). `bottomInset` is how far
/// each bottom corner moves inward; 0 yields a plain rounded rect.
struct RoundedTrapezoidShape: InsettableShape {
    var bottomInset: CGFloat
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> RoundedTrapezoidShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, cornerRadius - insetAmount)
        let topLeft = CGPoint(x: r.minX, y: r.minY)
        let topRight = CGPoint(x: r.maxX, y: r.minY)
        let bottomRight = CGPoint(x: r.maxX - bottomInset, y: r.maxY)
        let bottomLeft = CGPoint(x: r.minX + bottomInset, y: r.maxY)

        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
        p.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
        p.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
        p.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
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
