import Foundation
import CoreGraphics

/// Handles joystick polling, mouse movement, scroll wheel, direction keys, focus mode, and gyro aiming.
///
/// Extracted from MappingEngine to reduce its responsibilities. Operates on the shared
/// `EngineState` and reads controller data via `ControllerService` thread-safe properties.
extension MappingEngine {

    // MARK: - Joystick Polling Lifecycle

    func startJoystickPollingIfNeeded() {
        stopJoystickPollingInternal()

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now(), repeating: Config.joystickPollInterval, leeway: .microseconds(100))
        timer.setEventHandler { [weak self] in
            let now = CFAbsoluteTimeGetCurrent()
            self?.processJoysticks(now: now)
            self?.processTouchpadMomentumTick(now: now)
        }
        timer.resume()
        joystickTimer = timer
    }

    func stopJoystickPollingInternal() {
        joystickTimer?.cancel()
        joystickTimer = nil

        releaseAllDirectionKeys()
        state.lock.withLock {
            state.resetTransientInputState()
        }
    }

    // MARK: - Joystick Processing (called at 120Hz from pollingQueue)

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processJoysticks(now: CFAbsoluteTime) {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        state.lock.lock()
        defer { state.lock.unlock() }

        guard state.isEnabled, !state.isLocked, let settings = state.joystickSettings else { return }

        let dt = state.lastJoystickSampleTime > 0 ? now - state.lastJoystickSampleTime : Config.joystickPollInterval
        state.lastJoystickSampleTime = now

        // Single lock acquisition for all controller input state (cache-friendly snapshot)
        let controllerSnapshot = controllerService.snapshot()
        let leftStick = controllerSnapshot.leftStick

        // Batch UI singleton reads: one lock per singleton instead of multiple per-property reads.
        // Previously 6 separate lock/unlock cycles across 3 singletons; now 3 total.
        let keyboardSnapshot = OnScreenKeyboardManager.shared.keyboardUISnapshot()
        let swipeSnapshot = SwipeTypingEngine.shared.swipeSnapshot()
        let remoteOverlayState = UniversalControlMouseRelay.shared.remoteOverlayState()
        let navigatorVisible = DirectoryNavigatorManager.shared.threadSafeIsVisible
            || remoteOverlayState.directoryNavigatorVisible

        // Swipe typing: left trigger toggles swipe mode, touchpad touch drives word boundaries
        let remoteKeyboardVisible = remoteOverlayState.keyboardVisible
        let keyboardVisible = keyboardSnapshot.visible || remoteKeyboardVisible
        let letterArea = keyboardSnapshot.letterArea
        let leftTrigger = controllerSnapshot.leftTrigger
        if keyboardVisible && state.swipeTypingEnabled {
            let isSwipeClickHeld = remoteKeyboardVisible
                ? UniversalControlMouseRelay.shared.isOutgoingRemoteLeftMouseButtonHeld
                : inputSimulator.isLeftMouseButtonHeld
            let wasSwipeActive = state.swipeTypingActive
            if !wasSwipeActive && leftTrigger > Config.swipeTriggerThreshold {
                state.swipeTypingActive = true
                state.wasTouchpadTouching = isSwipeClickHeld
                if !remoteKeyboardVisible || !UniversalControlMouseRelay.shared.sendSwipeMode(active: true) {
                    SwipeTypingEngine.shared.activateMode()
                }
            } else if wasSwipeActive && leftTrigger < Config.swipeTriggerReleaseThreshold {
                state.swipeTypingActive = false
                state.wasTouchpadTouching = false
                if !remoteKeyboardVisible || !UniversalControlMouseRelay.shared.sendSwipeMode(active: false) {
                    SwipeTypingEngine.shared.deactivateMode()
                }
            }

            if state.swipeTypingActive {
                let isClicking = isSwipeClickHeld
                let wasClicking = state.wasTouchpadTouching
                if isClicking && !wasClicking {
                    state.swipeClickReleaseFrames = 0
                    let beganRemotely = remoteKeyboardVisible
                        && UniversalControlMouseRelay.shared.sendSwipeBegin()
                    if !beganRemotely, letterArea.width > 0 && letterArea.height > 0,
                       let mouseEvent = CGEvent(source: nil) {
                        let quartz = mouseEvent.location
                        let screenHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
                        let cocoaX = quartz.x
                        let cocoaY = screenHeight - quartz.y
                        let normalized = CGPoint(
                            x: (cocoaX - letterArea.origin.x) / letterArea.width,
                            y: 1.0 - (cocoaY - letterArea.origin.y) / letterArea.height
                        )
                        SwipeTypingEngine.shared.setCursorPosition(normalized)
                        SwipeTypingEngine.shared.beginSwipe()
                    } else if !beganRemotely {
                        SwipeTypingEngine.shared.beginSwipe()
                    }
                    controllerService.playHaptic(
                        intensity: Config.swipeBeginHapticIntensity,
                        sharpness: Config.swipeBeginHapticSharpness,
                        duration: Config.swipeBeginHapticDuration,
                        transient: true
                    )
                } else if !isClicking && wasClicking {
                    state.swipeClickReleaseFrames += 1
                    if state.swipeClickReleaseFrames >= 3 {
                        let swipeCursorPos = swipeSnapshot.cursorPosition
                        let endedRemotely = remoteKeyboardVisible
                            && UniversalControlMouseRelay.shared.sendSwipeEnd()
                        if !endedRemotely {
                            SwipeTypingEngine.shared.endSwipe()
                        }
                        controllerService.playHaptic(
                            intensity: Config.swipeEndHapticIntensity,
                            sharpness: Config.swipeEndHapticSharpness,
                            duration: Config.swipeEndHapticDuration,
                            transient: true
                        )
                        state.swipeClickReleaseFrames = 0
                        if letterArea.width > 0 && letterArea.height > 0 {
                            let screenHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
                            let cocoaX = swipeCursorPos.x * letterArea.width + letterArea.origin.x
                            let cocoaY = (1.0 - swipeCursorPos.y) * letterArea.height + letterArea.origin.y
                            let quartzY = screenHeight - cocoaY
                            inputSimulator.warpMouseTo(point: CGPoint(x: cocoaX, y: quartzY))
                        }
                    }
                } else if isClicking {
                    state.swipeClickReleaseFrames = 0
                }
                if isClicking || state.swipeClickReleaseFrames == 0 {
                    state.wasTouchpadTouching = isClicking
                }

                if remoteKeyboardVisible, isClicking {
                    _ = UniversalControlMouseRelay.shared.sendSwipeJoystick(
                        x: Double(leftStick.x),
                        y: Double(-leftStick.y),
                        sensitivity: state.swipeTypingSensitivity
                    )
                } else if swipeSnapshot.state == .swiping {
                    SwipeTypingEngine.shared.updateCursorFromJoystick(
                        x: Double(leftStick.x),
                        y: Double(-leftStick.y),
                        sensitivity: state.swipeTypingSensitivity
                    )
                }
            }
        } else if state.swipeTypingActive {
            state.swipeTypingActive = false
            state.wasTouchpadTouching = false
            if !UniversalControlMouseRelay.shared.sendSwipeMode(active: false) {
                SwipeTypingEngine.shared.deactivateMode()
            }
        }

        let swipeBlocksLeftStick = state.swipeTypingActive
            && (swipeSnapshot.state == .swiping || (remoteKeyboardVisible && inputSimulator.isLeftMouseButtonHeld))
        guard !swipeBlocksLeftStick else {
            if state.commandWheelActive {
                updateCommandWheel(rightStick: controllerSnapshot.rightStick)
            }
            return
        }

        // Resolve effective per-side modes: active layer override (if any) wins over profile default.
        // Lock is held for the whole function, so reading state.activeLayerIds + state.activeProfile here is safe.
        let activeLayer: Layer? = {
            guard let layerId = state.activeLayerIds.last else { return nil }
            return state.activeProfile?.layers.first(where: { $0.id == layerId })
        }()
        let effectiveLeftMode = activeLayer?.leftStickModeOverride ?? settings.leftStickMode
        let effectiveRightMode = activeLayer?.rightStickModeOverride ?? settings.rightStickMode

        let leftInput = JoystickStickInput(
            stick: leftStick,
            side: .left,
            settings: settings,
            dt: dt,
            now: now,
            hasMotion: controllerSnapshot.hasMotion
        )
        effectiveLeftMode.strategy.process(leftInput, on: self)

        let rightStick = controllerSnapshot.rightStick

        // Right stick navigates directory navigator when visible
        if navigatorVisible {
            processDirectoryNavigatorStick(rightStick, now: now)
        } else if state.commandWheelActive {
            updateCommandWheel(rightStick: rightStick)
        } else {
            let rightInput = JoystickStickInput(
                stick: rightStick,
                side: .right,
                settings: settings,
                dt: dt,
                now: now,
                hasMotion: controllerSnapshot.hasMotion
            )
            effectiveRightMode.strategy.process(rightInput, on: self)
        }
    }

    // MARK: - Directory Navigator Stick Navigation

    /// Converts right stick input into directory navigator navigation commands.
    /// Uses a deadzone + throttle approach: the first deflection triggers immediately,
    /// then repeats at the D-pad repeat interval while held.
    nonisolated func processDirectoryNavigatorStick(_ stick: CGPoint, now: CFAbsoluteTime) {
        let deadzone: Double = state.joystickSettings?.mouseDeadzone ?? 0.4
        let magnitude = sqrt(Double(stick.x * stick.x + stick.y * stick.y))

        guard magnitude > deadzone else {
            state.directoryNavStickWasInDeadzone = true
            return
        }

        // Determine dominant axis direction
        let button: ControllerButton
        if abs(stick.x) > abs(stick.y) {
            button = stick.x > 0 ? .dpadRight : .dpadLeft
        } else {
            button = stick.y > 0 ? .dpadUp : .dpadDown
        }

        let justEntered = state.directoryNavStickWasInDeadzone
        state.directoryNavStickWasInDeadzone = false

        if justEntered {
            // First deflection — move immediately
            state.directoryNavLastMoveTime = now
            if UniversalControlMouseRelay.shared.sendDirectoryNavigation(button) {
                return
            }
            Task { @MainActor in
                DirectoryNavigatorManager.shared.handleDPadNavigation(button)
            }
        } else if now - state.directoryNavLastMoveTime >= Config.dpadRepeatInterval {
            // Repeat at dpad interval
            state.directoryNavLastMoveTime = now
            if UniversalControlMouseRelay.shared.sendDirectoryNavigation(button) {
                return
            }
            Task { @MainActor in
                DirectoryNavigatorManager.shared.handleDPadNavigation(button)
            }
        }
    }

    // MARK: - Command Wheel Update

    /// Updates the command wheel selection from the right stick input.
    /// Called from processJoysticks() when the command wheel is active.
    nonisolated func updateCommandWheel(rightStick: CGPoint) {
        let altMods = state.wheelAlternateModifiers
        let alternateHeld: Bool = {
            guard altMods.command || altMods.option || altMods.shift || altMods.control else { return false }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if altMods.command && !flags.contains(.maskCommand) { return false }
            if altMods.option && !flags.contains(.maskAlternate) { return false }
            if altMods.shift && !flags.contains(.maskShift) { return false }
            if altMods.control && !flags.contains(.maskControl) { return false }
            return true
        }()
        if UniversalControlMouseRelay.shared.sendCommandWheelUpdate(stick: rightStick, alternateHeld: alternateHeld) {
            return
        }
        DispatchQueue.main.async {
            CommandWheelManager.shared.setShowingAlternate(alternateHeld)
            CommandWheelManager.shared.updateSelection(stickX: rightStick.x, stickY: rightStick.y)
        }
    }

    // MARK: - Stick Smoothing

    nonisolated func smoothStick(_ raw: CGPoint, previous: CGPoint, dt: TimeInterval) -> CGPoint {
        JoystickMath.smoothStick(raw, previous: previous, dt: dt,
                                 minCutoff: Config.joystickMinCutoffFrequency,
                                 maxCutoff: Config.joystickMaxCutoffFrequency)
    }

    // MARK: - Scroll Double-Tap Boost

    nonisolated func updateScrollDoubleTapState(rawStick: CGPoint, settings: JoystickSettings, now: TimeInterval) {
        let deadzone = settings.scrollDeadzone
        let magnitudeSquared = rawStick.x * rawStick.x + rawStick.y * rawStick.y
        let deadzoneSquared = deadzone * deadzone
        let isOutside = magnitudeSquared > deadzoneSquared

        if state.scrollBoostDirection != 0, isOutside {
            let currentDirection = rawStick.y >= 0 ? 1 : -1
            if abs(rawStick.y) >= abs(rawStick.x) * Config.scrollTapDirectionRatio,
               currentDirection != state.scrollBoostDirection {
                state.scrollBoostDirection = 0
            }
        }

        if isOutside {
            state.rightStickWasOutsideDeadzone = true
            state.rightStickPeakYAbs = max(state.rightStickPeakYAbs, abs(Double(rawStick.y)))
            if abs(rawStick.y) >= abs(rawStick.x) * Config.scrollTapDirectionRatio {
                state.rightStickLastDirection = rawStick.y >= 0 ? 1 : -1
            }
            return
        }

        guard state.rightStickWasOutsideDeadzone else { return }
        state.rightStickWasOutsideDeadzone = false

        if state.rightStickPeakYAbs >= Config.scrollTapThreshold, state.rightStickLastDirection != 0 {
            if now - state.lastRightStickTapTime <= Config.scrollDoubleTapWindow,
               state.rightStickLastDirection == state.lastRightStickTapDirection {
                state.scrollBoostDirection = state.rightStickLastDirection
            }
            state.lastRightStickTapTime = now
            state.lastRightStickTapDirection = state.rightStickLastDirection
        }

        state.rightStickPeakYAbs = 0
        state.rightStickLastDirection = 0
    }

    // MARK: - Gyro Aiming Helpers

    /// Smooth deadzone ramp: returns 0 below deadzone, quadratic ease-in through
    /// a transition zone of width `deadzone`, then linear above `2 * deadzone`.
    /// Eliminates the hard cutoff discontinuity that causes stutter at the boundary.
    nonisolated func smoothDeadzone(_ value: Double, deadzone: Double) -> Double {
        JoystickMath.smoothDeadzone(value, deadzone: deadzone)
    }

    // MARK: - Mouse Movement (incl. Focus Mode + Gyro Aiming)

    nonisolated func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings, now: CFAbsoluteTime, hasMotion: Bool? = nil) {
        let focusFlags = settings.focusModeModifier.cgEventFlags
        let isFocusActive = focusFlags.rawValue != 0 && inputSimulator.isHoldingModifiers(focusFlags)

        let wasFocusActive = state.wasFocusActive

        if isFocusActive != wasFocusActive {
            state.wasFocusActive = isFocusActive
            performFocusModeHaptic(entering: isFocusActive)

            if !UniversalControlMouseRelay.shared.sendFocusMode(active: isFocusActive) {
                Task { @MainActor in
                    if isFocusActive {
                        FocusModeIndicator.shared.show()
                    } else {
                        FocusModeIndicator.shared.hide()
                    }
                }
            }

            if !isFocusActive {
                state.focusExitTime = now
                state.currentMultiplier = settings.focusMultiplier
            }
        } else if isFocusActive {
            if UniversalControlMouseRelay.shared.sendFocusMode(active: true) {
                Task { @MainActor in
                    FocusModeIndicator.shared.hide()
                }
            } else {
                Task { @MainActor in
                    FocusModeIndicator.shared.show()
                }
            }
        }

        if state.focusExitTime > 0 && (now - state.focusExitTime) < Config.focusExitPauseDuration {
            return
        }

        if settings.gyroAimingEnabled && isFocusActive && (hasMotion ?? controllerService.threadSafeHasMotion) {
            let (pitchRate, rollRate) = controllerService.consumeAverageMotionRates()

            // Skip filter update if no new gyro samples arrived this tick
            // (poll at 120Hz can outpace gyro at ~100Hz); avoids feeding false zeros
            if pitchRate != 0 || rollRate != 0 {
                let gyroDeadzone = settings.gyroAimingDeadzone
                let mult = settings.gyroAimingMultiplier

                // Smooth deadzone ramp: quadratic ease-in over a transition zone
                // avoids the hard cutoff discontinuity that causes stutter at the boundary
                let gyroDx = -smoothDeadzone(abs(rollRate), deadzone: gyroDeadzone)
                    * (rollRate < 0 ? -1.0 : 1.0) * mult * Config.gyroAimingRollBoost
                let gyroDy = -smoothDeadzone(abs(pitchRate), deadzone: gyroDeadzone)
                    * (pitchRate < 0 ? -1.0 : 1.0) * mult

                // 1-Euro filter: adaptive smoothing (heavy at low speed, minimal at high speed)
                let dt: Double
                if state.lastGyroTime > 0 {
                    dt = max(now - state.lastGyroTime, 1.0 / 240.0)
                } else {
                    dt = Config.joystickPollInterval
                }
                state.lastGyroTime = now

                let filteredDx = state.gyroFilterX.filter(gyroDx, dt: dt)
                let filteredDy = state.gyroFilterY.filter(gyroDy, dt: dt)

                if abs(filteredDx) > 0.01 || abs(filteredDy) > 0.01 {
                    inputSimulator.moveMouse(dx: CGFloat(filteredDx), dy: CGFloat(filteredDy))
                }
            }
        } else {
            // Reset filter state when gyro is inactive so there's no stale residual on re-entry
            if state.lastGyroTime > 0 {
                state.gyroFilterX.reset()
                state.gyroFilterY.reset()
                state.lastGyroTime = 0
            }
        }

        guard let magnitude = JoystickMath.circularDeadzone(
            x: Double(stick.x), y: Double(stick.y), deadzone: settings.mouseDeadzone
        ) else { return }

        let normalizedMagnitude = JoystickMath.normalizedMagnitude(magnitude, deadzone: settings.mouseDeadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.mouseAccelerationExponent)

        let targetMultiplier = isFocusActive ? settings.focusMultiplier : settings.mouseMultiplier

        if state.currentMultiplier == 0 {
            state.currentMultiplier = targetMultiplier
        }

        state.currentMultiplier += Config.focusMultiplierSmoothingAlpha * (targetMultiplier - state.currentMultiplier)

        let scale = acceleratedMagnitude * state.currentMultiplier / magnitude
        let dx = stick.x * scale
        var dy = stick.y * scale

        dy = settings.invertMouseY ? dy : -dy

        inputSimulator.moveMouse(dx: dx, dy: dy)
        usageStatsService?.recordJoystickMouseDistance(dx: Double(dx), dy: Double(dy))
    }

    // MARK: - Scrolling

    nonisolated func processScrolling(_ stick: CGPoint, rawStick: CGPoint, settings: JoystickSettings, now: TimeInterval) {
        guard let magnitude = JoystickMath.circularDeadzone(
            x: Double(stick.x), y: Double(stick.y), deadzone: settings.scrollDeadzone
        ) else { return }

        let normalizedMag = JoystickMath.normalizedMagnitude(magnitude, deadzone: settings.scrollDeadzone)
        let acceleratedMagnitude = pow(normalizedMag, settings.scrollAccelerationExponent)
        let scale = acceleratedMagnitude * settings.scrollMultiplier / magnitude

        let effectiveX = JoystickMath.scrollEffectiveX(
            stickX: Double(stick.x), stickY: Double(stick.y),
            thresholdRatio: Config.scrollHorizontalThresholdRatio
        )

        let dx = -effectiveX * scale
        var dy = stick.y * scale

        dy = settings.invertScrollY ? -dy : dy

        if state.scrollBoostDirection != 0,
           (rawStick.y >= 0 ? 1 : -1) == state.scrollBoostDirection {
            dy *= settings.scrollBoostMultiplier
        }

        inputSimulator.scroll(
            dx: dx,
            dy: dy,
            phase: nil,
            momentumPhase: nil,
            isContinuous: false,
            flags: inputSimulator.getHeldModifiers()
        )
        usageStatsService?.recordScrollDistance(dx: Double(dx), dy: Double(dy))
    }

    // MARK: - Direction Keys (WASD / Arrow)

    nonisolated func processDirectionKeys(
        stick: CGPoint,
        deadzone: Double,
        mode: StickMode,
        heldKeys: inout Set<CGKeyCode>,
        invertY: Bool
    ) {
        let upKey: CGKeyCode = mode == .wasdKeys ? 13 : 126
        let downKey: CGKeyCode = mode == .wasdKeys ? 1 : 125
        let leftKey: CGKeyCode = mode == .wasdKeys ? 0 : 123
        let rightKey: CGKeyCode = mode == .wasdKeys ? 2 : 124

        var targetKeys: Set<CGKeyCode> = []

        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone

        if magnitudeSquared > deadzoneSquared {
            let stickX = Double(stick.x)
            let stickY = Double(stick.y) * (invertY ? -1.0 : 1.0)
            let threshold = 0.4

            if stickY > threshold {
                targetKeys.insert(upKey)
            } else if stickY < -threshold {
                targetKeys.insert(downKey)
            }

            if stickX > threshold {
                targetKeys.insert(rightKey)
            } else if stickX < -threshold {
                targetKeys.insert(leftKey)
            }
        }

        for key in heldKeys {
            if !targetKeys.contains(key) {
                inputSimulator.keyUp(key)
            }
        }

        for key in targetKeys {
            if !heldKeys.contains(key) {
                inputSimulator.keyDown(key, modifiers: [])
            }
        }

        heldKeys = targetKeys
    }

    // MARK: - Axis Direction Buttons (WASD / Arrow)

    nonisolated func processAxisDirectionButtons(
        stick: CGPoint,
        side: JoystickSide,
        deadzone: Double,
        heldButtons: inout Set<ControllerButton>,
        invertY: Bool
    ) {
        let targetButtons = JoystickDirectionResolver.activeAxisButtons(
            stick: stick,
            side: side,
            deadzone: deadzone,
            invertY: invertY
        )
        updateHeldDirectionButtons(targetButtons, heldButtons: &heldButtons)
    }

    // MARK: - Custom Direction Buttons

    nonisolated func processCustomDirectionButtons(
        stick: CGPoint,
        side: JoystickSide,
        settings: JoystickSettings,
        heldButtons: inout Set<ControllerButton>
    ) {
		let targetButtons = customDirectionMappingsUseAxisMovement(side: side)
			? JoystickDirectionResolver.activeAxisButtons(
				stick: stick,
				side: side,
				settings: settings
			)
			: JoystickDirectionResolver.activeButtons(
				stick: stick,
				side: side,
				settings: settings
			)
        updateHeldDirectionButtons(targetButtons, heldButtons: &heldButtons)
    }

	nonisolated private func customDirectionMappingsUseAxisMovement(side: JoystickSide) -> Bool {
		guard let profile = state.activeProfile else { return false }

		return ControllerButton.joystickDirectionButtons(side: side).allSatisfy { button in
			guard let mapping = ButtonMappingResolutionPolicy.resolve(
				button: button,
				profile: profile,
				activeLayerIds: state.activeLayerIds,
				layerActivatorMap: state.layerActivatorMap
			) else {
				return false
			}

			return mapping.isJoystickAxisMovementMapping
		}
	}

    nonisolated private func updateHeldDirectionButtons(
        _ targetButtons: Set<ControllerButton>,
        heldButtons: inout Set<ControllerButton>
    ) {
        let releasedButtons = heldButtons.subtracting(targetButtons)
        let pressedButtons = targetButtons.subtracting(heldButtons)

        heldButtons = targetButtons

        // Release first so moving between directions never leaves a stale held mapping.
        for button in releasedButtons {
            controllerService.handleButton(button, pressed: false)
        }
        for button in pressedButtons {
            controllerService.handleButton(button, pressed: true)
        }
    }

    // MARK: - Focus Mode Haptics

    nonisolated func performFocusModeHaptic(entering: Bool) {
        let intensity: Float = entering ? Config.focusEntryHapticIntensity : Config.focusExitHapticIntensity
        let sharpness: Float = entering ? Config.focusEntryHapticSharpness : Config.focusExitHapticSharpness
        let duration: TimeInterval = entering ? Config.focusEntryHapticDuration : Config.focusExitHapticDuration
        controllerService.playHaptic(intensity: intensity, sharpness: sharpness, duration: duration)
    }

    /// Releases all direction keys for both sticks (called on disable)
    nonisolated func releaseAllDirectionKeys() {
        let (leftKeys, rightKeys, directionButtons) = state.lock.withLock {
            let left = state.leftStickHeldKeys
            let right = state.rightStickHeldKeys
            let directions = state.leftStickHeldDirectionButtons.union(state.rightStickHeldDirectionButtons)
            state.leftStickHeldKeys.removeAll()
            state.rightStickHeldKeys.removeAll()
            state.leftStickHeldDirectionButtons.removeAll()
            state.rightStickHeldDirectionButtons.removeAll()
            return (left, right, directions)
        }

        for key in leftKeys {
            inputSimulator.keyUp(key)
        }
        for key in rightKeys {
            inputSimulator.keyUp(key)
        }
        for button in directionButtons {
            controllerService.handleButton(button, pressed: false)
        }
    }
}

private extension KeyMapping {
	var isJoystickAxisMovementMapping: Bool {
		keyCode != nil
			&& modifiers == ModifierFlags()
			&& macroId == nil
			&& scriptId == nil
			&& systemCommand == nil
			&& isHoldModifier
	}
}
