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

    var body: some View {
        Group {
            if isSteamController {
                steamOverlay
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
        VStack(spacing: 15) {
            HStack(spacing: 140) {
                miniTrigger(.leftTrigger, label: "LT", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "RT", value: rightTrigger)
            }

            HStack(spacing: 120) {
                miniBumper(.leftBumper, label: "LB")
                miniBumper(.rightBumper, label: "RB")
            }
            .offset(y: -5)

            HStack(spacing: 40) {
                miniStick(.leftThumbstick, pos: leftStick)

                VStack(spacing: 6) {
                    miniCircle(.xbox, size: 22)

                    if isConnected {
                        BatteryView(level: batteryLevel, state: batteryState)
                    }

                    HStack(spacing: 12) {
                        miniCircle(.view, size: 14)
                        miniCircle(.menu, size: 14)
                    }
                    if !isXboxElite || isSteamController {
                        miniCircle(.share, size: 10)
                    }
                }

                miniFaceButtons()
            }

            HStack(spacing: 80) {
                miniDPad()
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - Steam Controller Overlay

    private var steamOverlay: some View {
        ZStack {
            miniTrigger(.leftTrigger, label: "LT", value: leftTrigger)
                .position(x: 72, y: 22)
            miniTrigger(.rightTrigger, label: "RT", value: rightTrigger)
                .position(x: 248, y: 22)

            miniBumper(.leftBumper, label: "LB")
                .position(x: 82, y: 45)
            miniBumper(.rightBumper, label: "RB")
                .position(x: 238, y: 45)

            VStack(spacing: 4) {
                miniCircle(.xbox, size: 21)

                if isConnected {
                    BatteryView(level: batteryLevel, state: batteryState)
                        .frame(width: 40)
                }

                HStack(spacing: 10) {
                    miniCircle(.view, size: 13)
                    miniCircle(.menu, size: 13)
                }
                miniCircle(.share, size: 11)
            }
            .frame(width: 58)
            .position(x: 160, y: 82)

            miniDPad()
                .position(x: 74, y: 90)
            miniFaceButtons()
                .position(x: 246, y: 90)

            miniStick(.leftThumbstick, pos: leftStick)
                .position(x: 100, y: 126)
            miniStick(.rightThumbstick, pos: rightStick)
                .position(x: 220, y: 126)

            miniSteamTouchpad(side: .left)
                .position(x: 100, y: 180)
            miniSteamTouchpad(side: .right)
                .position(x: 220, y: 180)
        }
        .frame(width: 320, height: 228)
    }

    // MARK: - Nintendo Pro Controller Overlay

    private var nintendoOverlay: some View {
        VStack(spacing: 15) {
            HStack(spacing: 140) {
                miniTrigger(.leftTrigger, label: "ZL", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "ZR", value: rightTrigger)
            }

            HStack(spacing: 120) {
                miniBumper(.leftBumper, label: "L")
                miniBumper(.rightBumper, label: "R")
            }
            .offset(y: -5)

            HStack(spacing: 40) {
                miniStick(.leftThumbstick, pos: leftStick)

                VStack(spacing: 6) {
                    if isConnected {
                        BatteryView(level: batteryLevel, state: batteryState)
                    }

                    // − and + buttons (slightly wider)
                    HStack(spacing: 20) {
                        miniCircle(.view, size: 16)   // − button
                        miniCircle(.menu, size: 16)   // + button
                    }

                    // Capture and Home — side by side, mirrored (slightly narrower)
                    HStack(spacing: 20) {
                        miniSquare(.share, size: 10)   // Capture (left)
                        miniCircle(.xbox, size: 10)    // Home (right)
                    }
                }

                miniFaceButtons()
            }

            HStack(spacing: 80) {
                miniDPad()
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - DualSense Controller Overlay

    private var dualSenseOverlay: some View {
        VStack(spacing: 4) {
            // Row 1: Triggers (top)
            HStack(spacing: 150) {
                miniTrigger(.leftTrigger, label: "L2", value: leftTrigger)
                miniTrigger(.rightTrigger, label: "R2", value: rightTrigger)
            }

            // Row 2: Bumpers
            HStack(spacing: 130) {
                miniBumper(.leftBumper, label: "L1")
                miniBumper(.rightBumper, label: "R1")
            }

            // Row 3: Battery indicator (above touchpad)
            if isConnected {
                BatteryView(level: batteryLevel, state: batteryState)
                    .frame(width: 40)
            }

            // Row 4: D-pad + Touchpad section + Face buttons (straddling touchpad)
            HStack(spacing: 8) {
                miniDPad()
                    .frame(width: 40)
                    .offset(y: 15)

                // Center: Create + Touchpad + Options
                HStack(alignment: .top, spacing: 6) {
                    miniCircle(.view, size: 12)  // Create button
                    miniTouchpad()
                    miniCircle(.menu, size: 12)  // Options button
                }

                miniFaceButtons()
                    .frame(width: 40)
                    .offset(y: 15)
            }

            // Row 5: Sticks with PS/Mic in center (bottom)
            HStack(spacing: 20) {
                miniStick(.leftThumbstick, pos: leftStick)
                VStack(spacing: 3) {
                    miniCircle(.xbox, size: 16)  // PS button
                    miniBumperWithIcon(.micMute, icon: "mic.slash", width: 16)  // Mic mute
                }
                miniStick(.rightThumbstick, pos: rightStick)
            }
        }
    }

    // MARK: - Mini Touchpad

    private func miniTouchpad() -> some View {
        let color = isPressed(.touchpadButton) ? Color.accentColor : Color(white: 0.25)
        let touchpadWidth: CGFloat = 100
        let touchpadHeight: CGFloat = 50
        let inQuadrantsMode = touchpadInputMode == .quadrants

        return ZStack {
            // Base touchpad shape
            RoundedRectangle(cornerRadius: 10)
                .fill(jewelGradient(color, pressed: isPressed(.touchpadButton)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
                )

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

            // Primary touch point
            if isTouchpadTouching {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.5), radius: 3)
                    .offset(
                        x: touchpadPosition.x * (touchpadWidth / 2 - 5),
                        y: -touchpadPosition.y * (touchpadHeight / 2 - 5)
                    )
            }

            // Secondary touch point (two-finger)
            if isTouchpadSecondaryTouching {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.4), radius: 2)
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

    private func miniSteamTouchpad(side: SteamTouchpadSide) -> some View {
        let clickButton = side.wholeClickButton
        let tapButton = side.wholeTapButton
        let position = side == .left ? steamLeftTouchpadPosition : steamRightTouchpadPosition
        let isTouching = side == .left ? isSteamLeftTouchpadTouching : isSteamRightTouchpadTouching
        let padSize: CGFloat = 48
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
		.overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 2))
        .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
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
			.overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// Bumper-shaped button with an icon inside (used for mic mute on DualSense)
    private func miniBumperWithIcon(_ button: ControllerButton, icon: String, width: CGFloat = 38) -> some View {
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.25)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)

        return shape
            .fill(jewelGradient(color, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(shape))
            .frame(width: width, height: 9)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 6, weight: .bold))
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

    private func miniStick(_ button: ControllerButton, pos: CGPoint) -> some View {
        let directionButtons = button == .leftThumbstick
            ? ControllerButton.joystickDirectionButtons(side: .left)
            : ControllerButton.joystickDirectionButtons(side: .right)
        let isStickActive = isPressed(button) || directionButtons.contains(where: isPressed)

        return ZStack {
            // Base well
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.1), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 30, height: 30)
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1) // Highlight at bottom lip
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))

            // Stick Cap
            let color = isStickActive ? Color.accentColor : Color(white: 0.3)
            Circle()
                .fill(jewelGradient(color, pressed: isStickActive))
                .overlay(glassOverlay.clipShape(Circle()))
                .frame(width: 20, height: 20)
                .offset(x: pos.x * 5, y: -pos.y * 5)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
        }
		.overlay(miniOverrideOutline(for: [button] + directionButtons, shape: Circle(), lineWidth: 2))
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor([button] + directionButtons, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
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

            if button == .xbox {
                if isSteamController {
                    SteamLogoMark(foregroundColor: isPressed(button) ? .white : Color(white: 0.25))
                        .frame(width: size * 0.62, height: size * 0.62)
                } else {
                    Image(systemName: isPlayStation ? "playstation.logo" : (isNintendo ? "house" : "xbox.logo"))
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundColor(isPressed(button) ? .white : Color(white: 0.3))
                }
            } else if isSteamController && button == .share {
                Image(systemName: "ellipsis")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundColor(.white.opacity(0.95))
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
        let color = isPressed(button) ? Color.accentColor : Color(white: 0.3)
		let shape = RoundedRectangle(cornerRadius: size * 0.2)

		return shape
			.fill(jewelGradient(color, pressed: isPressed(button)))
			.overlay(glassOverlay.clipShape(shape))
			.frame(width: size, height: size)
			.overlay(miniOverrideOutline(for: button, shape: shape, lineWidth: 1.5))
            .shadow(color: isPressed(button) ? Color.accentColor.opacity(0.4) : .black.opacity(0.2), radius: 1)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    private func miniFaceButton(_ button: ControllerButton, color: Color) -> some View {
        // Use the vibrant colors for A/B/X/Y even when not pressed, just like the real controller
        let displayColor = isPressed(button) ? color.opacity(0.8) : color

        return Circle()
            .fill(jewelGradient(displayColor, pressed: isPressed(button)))
            .overlay(glassOverlay.clipShape(Circle()))
            .frame(width: 12, height: 12)
			.overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
            .shadow(color: displayColor.opacity(0.4), radius: 2)
            .onTapGesture { onButtonTap(button) }
            .controllerAnchor(button, role: .controller)
            .onHover { hovering in onButtonHover?(button, hovering) }
            .swappable(button, onSwap: onSwapRequest)
    }

    /// PlayStation-style face button: dark background with colored symbol
    private func miniPSFaceButton(_ button: ControllerButton, symbolColor: Color) -> some View {
        let bgColor = Color(white: 0.12)
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
		.overlay(miniOverrideOutline(for: button, shape: Circle(), lineWidth: 1.5))
        .shadow(color: symbolColor.opacity(0.3), radius: 2)
        .onTapGesture { onButtonTap(button) }
        .controllerAnchor(button, role: .controller)
        .onHover { hovering in onButtonHover?(button, hovering) }
        .swappable(button, onSwap: onSwapRequest)
    }

    private func miniFaceButtons() -> some View {
        ZStack {
            if isPlayStation {
                // PlayStation style: dark background with colored symbols
                miniPSFaceButton(.y, symbolColor: ButtonColors.psTriangle).offset(y: -12)
                miniPSFaceButton(.a, symbolColor: ButtonColors.psCross).offset(y: 12)
                miniPSFaceButton(.x, symbolColor: ButtonColors.psSquare).offset(x: -12)
                miniPSFaceButton(.b, symbolColor: ButtonColors.psCircle).offset(x: 12)
            } else {
                // Xbox layout and colors (colored background)
                miniFaceButton(.y, color: ButtonColors.xboxY).offset(y: -12)
                miniFaceButton(.a, color: ButtonColors.xboxA).offset(y: 12)
                miniFaceButton(.x, color: ButtonColors.xboxX).offset(x: -12)
                miniFaceButton(.b, color: ButtonColors.xboxB).offset(x: 12)
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

			dpadOverrideOverlay

            // Tap zones — `.offset` is render-only and works fine for hit-testing.
            // Anchors are reported separately by the markers below, since `.offset`
            // does NOT propagate into anchor preference reads from ancestor proxies.
            Group {
                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: -10)
                    .onTapGesture { onButtonTap(.dpadUp) }
                    .onHover { hovering in onButtonHover?(.dpadUp, hovering) }
                    .swappable(.dpadUp, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(y: 10)
                    .onTapGesture { onButtonTap(.dpadDown) }
                    .onHover { hovering in onButtonHover?(.dpadDown, hovering) }
                    .swappable(.dpadDown, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: -10)
                    .onTapGesture { onButtonTap(.dpadLeft) }
                    .onHover { hovering in onButtonHover?(.dpadLeft, hovering) }
                    .swappable(.dpadLeft, onSwap: onSwapRequest)

                Rectangle().fill(Color.black.opacity(0.001))
                    .frame(width: 20, height: 20)
                    .offset(x: 10)
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
        .frame(width: 24, height: 24)
    }

    private var dpadOverrideOverlay: some View {
		ZStack {
			dpadOverrideSegment(.dpadUp, width: 10, height: 12)
				.offset(y: -6)
			dpadOverrideSegment(.dpadDown, width: 10, height: 12)
				.offset(y: 6)
			dpadOverrideSegment(.dpadLeft, width: 12, height: 10)
				.offset(x: -6)
			dpadOverrideSegment(.dpadRight, width: 12, height: 10)
				.offset(x: 6)
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
