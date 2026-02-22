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

        state.lock.withLock {
            state.reset()
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

        let leftStick = controllerService.threadSafeLeftStick

        // Swipe typing: left trigger toggles swipe mode, touchpad touch drives word boundaries
        let keyboardVisible = OnScreenKeyboardManager.shared.threadSafeIsVisible
        let leftTrigger = controllerService.threadSafeLeftTrigger
        if keyboardVisible && state.swipeTypingEnabled {
            let wasSwipeActive = state.swipeTypingActive
            if !wasSwipeActive && leftTrigger > Config.swipeTriggerThreshold {
                state.swipeTypingActive = true
                state.wasTouchpadTouching = inputSimulator.isLeftMouseButtonHeld
                SwipeTypingEngine.shared.activateMode()
            } else if wasSwipeActive && leftTrigger < Config.swipeTriggerReleaseThreshold {
                state.swipeTypingActive = false
                state.wasTouchpadTouching = false
                SwipeTypingEngine.shared.deactivateMode()
            }

            if state.swipeTypingActive {
                let isClicking = inputSimulator.isLeftMouseButtonHeld
                let wasClicking = state.wasTouchpadTouching
                if isClicking && !wasClicking {
                    state.swipeClickReleaseFrames = 0
                    let letterArea = OnScreenKeyboardManager.shared.threadSafeLetterAreaScreenRect
                    if letterArea.width > 0 && letterArea.height > 0,
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
                    }
                    SwipeTypingEngine.shared.beginSwipe()
                    controllerService.playHaptic(
                        intensity: Config.swipeBeginHapticIntensity,
                        sharpness: Config.swipeBeginHapticSharpness,
                        duration: Config.swipeBeginHapticDuration,
                        transient: true
                    )
                } else if !isClicking && wasClicking {
                    state.swipeClickReleaseFrames += 1
                    if state.swipeClickReleaseFrames >= 3 {
                        let swipeCursorPos = SwipeTypingEngine.shared.threadSafeCursorPosition
                        SwipeTypingEngine.shared.endSwipe()
                        controllerService.playHaptic(
                            intensity: Config.swipeEndHapticIntensity,
                            sharpness: Config.swipeEndHapticSharpness,
                            duration: Config.swipeEndHapticDuration,
                            transient: true
                        )
                        state.swipeClickReleaseFrames = 0
                        let letterArea = OnScreenKeyboardManager.shared.threadSafeLetterAreaScreenRect
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

                if SwipeTypingEngine.shared.threadSafeState == .swiping {
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
            SwipeTypingEngine.shared.deactivateMode()
        }

        let swipeBlocksLeftStick = state.swipeTypingActive && SwipeTypingEngine.shared.threadSafeState == .swiping
        guard !swipeBlocksLeftStick else {
            let rightStick = controllerService.threadSafeRightStick
            if state.commandWheelActive {
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
                DispatchQueue.main.async {
                    CommandWheelManager.shared.setShowingAlternate(alternateHeld)
                    CommandWheelManager.shared.updateSelection(stickX: rightStick.x, stickY: rightStick.y)
                }
            }
            return
        }

        switch settings.leftStickMode {
        case .none:
            break
        case .mouse:
            processMouseMovement(leftStick, settings: settings, now: now)
        case .scroll:
            let leftMagnitudeSquared = leftStick.x * leftStick.x + leftStick.y * leftStick.y
            let leftDeadzoneSquared = settings.mouseDeadzone * settings.mouseDeadzone
            if leftMagnitudeSquared <= leftDeadzoneSquared {
                state.smoothedLeftStick = .zero
            } else {
                state.smoothedLeftStick = smoothStick(leftStick, previous: state.smoothedLeftStick, dt: dt)
            }
            processScrolling(state.smoothedLeftStick, rawStick: leftStick, settings: settings, now: now)
        case .wasdKeys, .arrowKeys:
            processDirectionKeys(
                stick: leftStick,
                deadzone: settings.mouseDeadzone,
                mode: settings.leftStickMode,
                heldKeys: &state.leftStickHeldKeys,
                invertY: settings.invertMouseY
            )
        }

        let rightStick = controllerService.threadSafeRightStick

        if state.commandWheelActive {
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
            DispatchQueue.main.async {
                CommandWheelManager.shared.setShowingAlternate(alternateHeld)
                CommandWheelManager.shared.updateSelection(stickX: rightStick.x, stickY: rightStick.y)
            }
        } else {
            switch settings.rightStickMode {
            case .none:
                break
            case .mouse:
                processMouseMovement(rightStick, settings: settings, now: now)
            case .scroll:
                updateScrollDoubleTapState(rawStick: rightStick, settings: settings, now: now)
                let rightMagnitudeSquared = rightStick.x * rightStick.x + rightStick.y * rightStick.y
                let rightDeadzoneSquared = settings.scrollDeadzone * settings.scrollDeadzone

                if rightMagnitudeSquared <= rightDeadzoneSquared {
                    state.smoothedRightStick = .zero
                } else {
                    state.smoothedRightStick = smoothStick(rightStick, previous: state.smoothedRightStick, dt: dt)
                }
                processScrolling(state.smoothedRightStick, rawStick: rightStick, settings: settings, now: now)
            case .wasdKeys, .arrowKeys:
                processDirectionKeys(
                    stick: rightStick,
                    deadzone: settings.scrollDeadzone,
                    mode: settings.rightStickMode,
                    heldKeys: &state.rightStickHeldKeys,
                    invertY: settings.invertScrollY
                )
            }
        }
    }

    // MARK: - Stick Smoothing

    nonisolated func smoothStick(_ raw: CGPoint, previous: CGPoint, dt: TimeInterval) -> CGPoint {
        let magnitude = sqrt(Double(raw.x * raw.x + raw.y * raw.y))
        let t = min(1.0, magnitude * 1.2)
        let cutoff = Config.joystickMinCutoffFrequency + (Config.joystickMaxCutoffFrequency - Config.joystickMinCutoffFrequency) * t
        let alpha = 1.0 - exp(-2.0 * Double.pi * cutoff * max(0.0, dt))
        let newX = Double(previous.x) + alpha * (Double(raw.x) - Double(previous.x))
        let newY = Double(previous.y) + alpha * (Double(raw.y) - Double(previous.y))
        return CGPoint(x: newX, y: newY)
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

    // MARK: - Mouse Movement (incl. Focus Mode + Gyro Aiming)

    nonisolated func processMouseMovement(_ stick: CGPoint, settings: JoystickSettings, now: CFAbsoluteTime) {
        let focusFlags = settings.focusModeModifier.cgEventFlags
        let isFocusActive = focusFlags.rawValue != 0 && inputSimulator.isHoldingModifiers(focusFlags)

        let wasFocusActive = state.wasFocusActive

        if isFocusActive != wasFocusActive {
            state.wasFocusActive = isFocusActive
            performFocusModeHaptic(entering: isFocusActive)

            Task { @MainActor in
                if isFocusActive {
                    FocusModeIndicator.shared.show()
                } else {
                    FocusModeIndicator.shared.hide()
                }
            }

            if !isFocusActive {
                state.focusExitTime = now
                state.currentMultiplier = settings.focusMultiplier
            }
        }

        if state.focusExitTime > 0 && (now - state.focusExitTime) < Config.focusExitPauseDuration {
            return
        }

        if settings.gyroAimingEnabled && isFocusActive && controllerService.threadSafeIsDualSense {
            let pitchRate = controllerService.threadSafeMotionPitchRate
            let rollRate = controllerService.threadSafeMotionRollRate

            let absPitch = abs(pitchRate)
            let absRoll = abs(rollRate)
            let gyroDeadzone = Config.gyroAimingDeadzone
            let mult = settings.gyroAimingMultiplier

            var gyroDx: Double = 0
            var gyroDy: Double = 0

            if absRoll > gyroDeadzone {
                let adjusted = (absRoll - gyroDeadzone) * (rollRate < 0 ? -1.0 : 1.0)
                gyroDx = -adjusted * mult * Config.gyroAimingRollBoost
            }
            if absPitch > gyroDeadzone {
                let adjusted = (absPitch - gyroDeadzone) * (pitchRate < 0 ? -1.0 : 1.0)
                gyroDy = -adjusted * mult
            }

            if gyroDx != 0 || gyroDy != 0 {
                inputSimulator.moveMouse(dx: CGFloat(gyroDx), dy: CGFloat(gyroDy))
            }
        }

        let deadzone = settings.mouseDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        let magnitude = sqrt(magnitudeSquared)
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)
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
        let deadzone = settings.scrollDeadzone
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        let deadzoneSquared = deadzone * deadzone
        guard magnitudeSquared > deadzoneSquared else { return }

        let magnitude = sqrt(magnitudeSquared)
        let normalizedMagnitude = (magnitude - deadzone) / (1.0 - deadzone)
        let acceleratedMagnitude = pow(normalizedMagnitude, settings.scrollAccelerationExponent)
        let scale = acceleratedMagnitude * settings.scrollMultiplier / magnitude

        let absX = abs(stick.x)
        let absY = abs(stick.y)
        let effectiveX: CGFloat
        if absY > absX && absX < absY * Config.scrollHorizontalThresholdRatio {
            effectiveX = 0
        } else {
            effectiveX = stick.x
        }

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

    // MARK: - Focus Mode Haptics

    nonisolated func performFocusModeHaptic(entering: Bool) {
        let intensity: Float = entering ? Config.focusEntryHapticIntensity : Config.focusExitHapticIntensity
        let sharpness: Float = entering ? Config.focusEntryHapticSharpness : Config.focusExitHapticSharpness
        let duration: TimeInterval = entering ? Config.focusEntryHapticDuration : Config.focusExitHapticDuration
        controllerService.playHaptic(intensity: intensity, sharpness: sharpness, duration: duration)
    }

    /// Releases all direction keys for both sticks (called on disable)
    nonisolated func releaseAllDirectionKeys() {
        let (leftKeys, rightKeys) = state.lock.withLock {
            let left = state.leftStickHeldKeys
            let right = state.rightStickHeldKeys
            state.leftStickHeldKeys.removeAll()
            state.rightStickHeldKeys.removeAll()
            return (left, right)
        }

        for key in leftKeys {
            inputSimulator.keyUp(key)
        }
        for key in rightKeys {
            inputSimulator.keyUp(key)
        }
    }
}
