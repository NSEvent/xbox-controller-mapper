import Foundation
import CoreGraphics

/// Handles DualSense touchpad input: single-finger movement, two-finger gestures (pan/pinch),
/// tap gestures, long-tap gestures, and momentum scrolling.
///
/// Extracted from MappingEngine to reduce its responsibilities.
extension MappingEngine {

    // MARK: - Touchpad Movement (single-finger mouse control)

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadMovement(_ delta: CGPoint) {
        dispatchPrecondition(condition: .onQueue(pollingQueue))

        // Single lock acquisition for all initial state reads
        guard let snapshot = state.lock.withLock({ () -> (settings: JoystickSettings, isGestureActive: Bool, swipeTypingActive: Bool, swipeTypingSensitivity: Double, smoothedDelta: CGPoint, lastSampleTime: TimeInterval)? in
            guard state.isEnabled, !state.isLocked, let settings = state.joystickSettings else { return nil }
            return (settings, state.isTouchpadGestureActive, state.swipeTypingActive, state.swipeTypingSensitivity, state.smoothedTouchpadDelta, state.lastTouchpadSampleTime)
        }) else { return }

        let settings = snapshot.settings

        // Route to swipe typing engine only while actively swiping (left click held)
        if snapshot.swipeTypingActive && SwipeTypingEngine.shared.threadSafeState == .swiping {
            SwipeTypingEngine.shared.updateCursorFromTouchpadDelta(
                dx: Double(delta.x),
                dy: Double(-delta.y),
                sensitivity: snapshot.swipeTypingSensitivity
            )
            return
        }

        let movementBlocked = controllerService.threadSafeIsTouchpadMovementBlocked
        if snapshot.isGestureActive || movementBlocked {
            state.lock.withLock {
                state.smoothedTouchpadDelta = .zero
                state.lastTouchpadSampleTime = 0
            }
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        // Compute smoothed delta using snapshot (no additional lock needed for reads)
        var smoothedDelta = snapshot.smoothedDelta
        let lastSampleTime = snapshot.lastSampleTime

        let resetSmoothing = lastSampleTime == 0 || (now - lastSampleTime) > Config.touchpadSmoothingResetInterval
        if resetSmoothing || settings.touchpadSmoothing <= 0 {
            smoothedDelta = delta
        } else {
            let alpha = max(Config.touchpadMinSmoothingAlpha, 1.0 - settings.touchpadSmoothing)
            smoothedDelta = CGPoint(
                x: smoothedDelta.x + (delta.x - smoothedDelta.x) * alpha,
                y: smoothedDelta.y + (delta.y - smoothedDelta.y) * alpha
            )
        }

        // Single lock acquisition to write back computed smoothed state
        state.lock.withLock {
            state.smoothedTouchpadDelta = smoothedDelta
            state.lastTouchpadSampleTime = now
        }

        let magnitude = Double(hypot(smoothedDelta.x, smoothedDelta.y))
        guard magnitude > settings.touchpadDeadzone else { return }

        let sensitivity = Config.touchpadNativeScale * settings.touchpadSensitivityMultiplier

        let dx = Double(smoothedDelta.x) * sensitivity
        var dy = -Double(smoothedDelta.y) * sensitivity

        if settings.invertMouseY {
            dy = -dy
        }

        inputSimulator.moveMouse(dx: CGFloat(dx), dy: CGFloat(dy))
        usageStatsService?.recordTouchpadMouseDistance(dx: dx, dy: dy)
    }

    // MARK: - Touchpad Tap Gestures

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadTap() {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        let button = ControllerButton.touchpadTap
        processTapGesture(button)
    }

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadTwoFingerTap() {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        let button = ControllerButton.touchpadTwoFingerTap
        processTapGesture(button)
    }

    nonisolated func processTapGesture(_ button: ControllerButton) {
        guard let profile = state.lock.withLock({
            guard state.isEnabled, !state.isLocked else { return nil as Profile? }
            return state.activeProfile
        }) else { return }

        guard let mapping = effectiveMapping(for: button, in: profile) else {
            inputLogService?.log(buttons: [button], type: .singlePress, action: "(unmapped)")
            return
        }

        if let doubleTapMapping = mapping.doubleTapMapping, !doubleTapMapping.isEmpty {
            let (pendingSingle, lastTap) = getPendingTapInfo(for: button)
            _ = handleDoubleTapIfReady(
                button,
                mapping: mapping,
                pendingSingle: pendingSingle,
                lastTap: lastTap,
                doubleTapMapping: doubleTapMapping,
                profile: profile
            )
            return
        }

        mappingExecutor.executeAction(mapping, for: button, profile: profile)
    }

    // MARK: - Touchpad Long Tap Gestures

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadLongTap() {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        let button = ControllerButton.touchpadTap
        processLongTapGesture(button)
    }

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadTwoFingerLongTap() {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        let button = ControllerButton.touchpadTwoFingerTap
        processLongTapGesture(button)
    }

    nonisolated func processLongTapGesture(_ button: ControllerButton) {
        guard let profile = state.lock.withLock({
            guard state.isEnabled, !state.isLocked else { return nil as Profile? }
            // Cancel any pending single tap for this button
            state.pendingSingleTap[button]?.cancel()
            state.pendingSingleTap.removeValue(forKey: button)
            state.lastTapTime.removeValue(forKey: button)
            return state.activeProfile
        }) else { return }

        guard let mapping = profile.buttonMappings[button],
              let longHoldMapping = mapping.longHoldMapping,
              !longHoldMapping.isEmpty else {
            return
        }

        mappingExecutor.executeAction(longHoldMapping, for: button, profile: profile, logType: .longPress)
    }

    // MARK: - Two-Finger Touchpad Gestures (pan + pinch zoom)

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadGesture(_ gesture: TouchpadGesture) {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        let isActive = gesture.isPrimaryTouching && gesture.isSecondaryTouching
        guard let snapshot = state.lock.withLock({ () -> (settings: JoystickSettings, wasActive: Bool, smoothedCenter: CGPoint, smoothedDistance: Double, lastSampleTime: TimeInterval, smoothedVelocity: CGPoint)? in
            guard state.isEnabled, !state.isLocked, let settings = state.joystickSettings else { return nil }
            let wasActive = state.isTouchpadGestureActive
            state.isTouchpadGestureActive = isActive
            return (settings, wasActive, state.smoothedTouchpadCenterDelta, state.smoothedTouchpadDistanceDelta, state.lastTouchpadGestureSampleTime, state.smoothedTouchpadPanVelocity)
        }) else { return }
        let settings = snapshot.settings
        let wasActive = snapshot.wasActive
        var smoothedCenter = snapshot.smoothedCenter
        var smoothedDistance = snapshot.smoothedDistance
        let lastSampleTime = snapshot.lastSampleTime
        var smoothedVelocity = snapshot.smoothedVelocity

        guard isActive else {
            let wasMagnifyActive = state.lock.withLock {
                let wasMagnify = state.touchpadMagnifyGestureActive
                if wasMagnify {
                    state.touchpadMagnifyGestureActive = false
                    state.touchpadPinchAccumulator = 0
                    state.touchpadMagnifyDirection = 0
                    state.touchpadMagnifyDirectionLockUntil = 0
                }
                state.touchpadPanActive = false
                return wasMagnify
            }
            if wasMagnifyActive {
                postMagnifyGestureEvent(0, 2)
            }

            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: .ended,
                    momentumPhase: nil,
                    isContinuous: true,
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                // Transfer momentum candidate to active momentum velocity on finger lift.
                // This is the only place the candidate becomes the live velocity that
                // processTouchpadMomentumTick reads from.
                state.touchpadMomentumVelocity = state.touchpadMomentumCandidateVelocity
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0

                state.smoothedTouchpadCenterDelta = .zero
                state.smoothedTouchpadDistanceDelta = 0
                state.lastTouchpadGestureSampleTime = 0
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        if lastSampleTime == 0 ||
            (now - lastSampleTime) > Config.touchpadSmoothingResetInterval ||
            settings.touchpadSmoothing <= 0 {
            smoothedCenter = gesture.centerDelta
            smoothedDistance = gesture.distanceDelta
        } else {
            let alpha = max(Config.touchpadMinSmoothingAlpha, 1.0 - settings.touchpadSmoothing)
            smoothedCenter = CGPoint(
                x: smoothedCenter.x + (gesture.centerDelta.x - smoothedCenter.x) * alpha,
                y: smoothedCenter.y + (gesture.centerDelta.y - smoothedCenter.y) * alpha
            )
            smoothedDistance += (gesture.distanceDelta - smoothedDistance) * alpha
        }

        state.lock.withLock {
            state.smoothedTouchpadCenterDelta = smoothedCenter
            state.smoothedTouchpadDistanceDelta = smoothedDistance
            state.lastTouchpadGestureSampleTime = now

            // Reset momentum candidate state when a new gesture begins so stale
            // velocity from a previous gesture cannot leak into the new one.
            if !wasActive {
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
            }
        }

        let phase: CGScrollPhase = wasActive ? .changed : .began

        if phase == .began {
            inputSimulator.scroll(
                dx: 0,
                dy: 0,
                phase: .began,
                momentumPhase: nil,
                isContinuous: true,
                flags: inputSimulator.getHeldModifiers()
            )
        }

        let pinchMagnitude = abs(smoothedDistance)
        let panMagnitude = Double(hypot(smoothedCenter.x, smoothedCenter.y))
        let ratio = pinchMagnitude / max(panMagnitude, 0.001)

        let isPinchGesture = pinchMagnitude > Config.touchpadPinchDeadzone &&
            (panMagnitude < Config.touchpadPanDeadzone ||
             ratio > settings.touchpadZoomToPanRatio)

        if isPinchGesture {
            let pinchResult: (shouldBeginMagnify: Bool, shouldPostMagnify: Bool, magnification: Double, zoomSteps: Int, zoomDirection: Int) = state.lock.withLock {
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
                state.touchpadPanActive = false

                if settings.touchpadUseNativeZoom {
                    var pinchDelta = smoothedDistance
                    if pinchDelta != 0 {
                        let direction = pinchDelta > 0 ? 1.0 : -1.0
                        if !state.touchpadMagnifyGestureActive || state.touchpadMagnifyDirection == 0 {
                            state.touchpadMagnifyDirection = direction
                            state.touchpadMagnifyDirectionLockUntil = now + Config.touchpadPinchDirectionLockInterval
                        } else if direction != state.touchpadMagnifyDirection {
                            if now < state.touchpadMagnifyDirectionLockUntil {
                                pinchDelta = 0
                            } else {
                                state.touchpadMagnifyDirection = direction
                                state.touchpadMagnifyDirectionLockUntil = now + Config.touchpadPinchDirectionLockInterval
                            }
                        }
                    }

                    let magnification = pinchDelta * Config.touchpadPinchSensitivityMultiplier / 1000.0
                    let shouldPostMagnify = pinchDelta != 0
                    let shouldBeginMagnify = !state.touchpadMagnifyGestureActive

                    state.touchpadPinchAccumulator += abs(pinchDelta)
                    state.touchpadMagnifyGestureActive = true
                    return (shouldBeginMagnify, shouldPostMagnify, magnification, 0, 0)
                } else {
                    state.touchpadPinchAccumulator += smoothedDistance
                    let threshold = 0.08
                    if state.touchpadPinchAccumulator > threshold {
                        let steps = min(3, max(1, Int(state.touchpadPinchAccumulator / threshold)))
                        state.touchpadPinchAccumulator = 0
                        return (false, false, 0, steps, 1)
                    } else if state.touchpadPinchAccumulator < -threshold {
                        let steps = min(3, max(1, Int(abs(state.touchpadPinchAccumulator) / threshold)))
                        state.touchpadPinchAccumulator = 0
                        return (false, false, 0, steps, -1)
                    }
                    return (false, false, 0, 0, 0)
                }
            }

            if pinchResult.shouldBeginMagnify {
                postMagnifyGestureEvent(0, 0)
            }
            if pinchResult.shouldPostMagnify {
                postMagnifyGestureEvent(pinchResult.magnification, 1)
            }
            if pinchResult.zoomDirection > 0 {
                for _ in 0..<pinchResult.zoomSteps {
                    inputSimulator.pressKey(KeyCodeMapping.equal, modifiers: [.maskCommand])
                }
            } else if pinchResult.zoomDirection < 0 {
                for _ in 0..<pinchResult.zoomSteps {
                    inputSimulator.pressKey(KeyCodeMapping.minus, modifiers: [.maskCommand])
                }
            }
            return
        }

        let pinchAccumMagnitude = state.lock.withLock { abs(state.touchpadPinchAccumulator) }
        if pinchAccumMagnitude > 0.05 {
            return
        }

        guard panMagnitude > Config.touchpadPanDeadzone else {
            let now = CFAbsoluteTimeGetCurrent()
            state.lock.withLock {
                state.smoothedTouchpadPanVelocity = .zero
                state.touchpadPanActive = false
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
                if state.touchpadMomentumCandidateTime > 0,
                   (now - state.touchpadMomentumCandidateTime) > Config.touchpadMomentumReleaseWindow {
                    state.touchpadMomentumCandidateVelocity = .zero
                    state.touchpadMomentumCandidateTime = 0
                }
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
            return
        }

        let panScale = settings.touchpadPanSensitivity * Config.touchpadPanSensitivityMultiplier
        var dx = Double(smoothedCenter.x) * panScale
        var dy = -Double(smoothedCenter.y) * panScale
        dy = settings.invertScrollY ? -dy : dy

        let sampleInterval = lastSampleTime == 0 ? Config.touchpadMomentumMinDeltaTime : (now - lastSampleTime)
        let dt = max(sampleInterval, Config.touchpadMomentumMinDeltaTime)
        let velocityX = dx / dt
        let velocityY = dy / dt
        let velocityAlpha = Config.touchpadMomentumVelocitySmoothingAlpha
        smoothedVelocity = CGPoint(
            x: smoothedVelocity.x + (velocityX - smoothedVelocity.x) * velocityAlpha,
            y: smoothedVelocity.y + (velocityY - smoothedVelocity.y) * velocityAlpha
        )
        let velocityMagnitude = Double(hypot(smoothedVelocity.x, smoothedVelocity.y))
        state.lock.withLock {
            state.smoothedTouchpadPanVelocity = smoothedVelocity
            state.touchpadPanActive = true
            state.touchpadMomentumLastGestureTime = now
            if velocityMagnitude <= Config.touchpadMomentumStopVelocity {
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
            } else if velocityMagnitude >= Config.touchpadMomentumStartVelocity {
                if state.touchpadMomentumHighVelocityStartTime == 0 {
                    state.touchpadMomentumHighVelocityStartTime = now
                }
                state.touchpadMomentumHighVelocitySampleCount += 1
                if velocityMagnitude > state.touchpadMomentumPeakMagnitude {
                    state.touchpadMomentumPeakMagnitude = velocityMagnitude
                    state.touchpadMomentumPeakVelocity = smoothedVelocity
                }

                let sustainedDuration = now - state.touchpadMomentumHighVelocityStartTime
                if state.touchpadMomentumHighVelocitySampleCount >= 2 &&
                    sustainedDuration >= Config.touchpadMomentumSustainedDuration {
                    let baseMagnitude = velocityMagnitude
                    let baseVelocity = smoothedVelocity
                    let clampedMagnitude = min(baseMagnitude, Config.touchpadMomentumMaxVelocity)
                    let velocityScale = baseMagnitude > 0 ? clampedMagnitude / baseMagnitude : 0
                    let boostRange = Config.touchpadMomentumBoostMax - Config.touchpadMomentumBoostMin
                    let velocityRange = Config.touchpadMomentumBoostMaxVelocity - Config.touchpadMomentumStartVelocity
                    let velocityAboveThreshold = min(baseMagnitude - Config.touchpadMomentumStartVelocity, velocityRange)
                    let boostFactor = velocityRange > 0 ? velocityAboveThreshold / velocityRange : 0
                    let boost = Config.touchpadMomentumBoostMin + boostRange * boostFactor
                    let clampedVelocity = CGPoint(
                        x: baseVelocity.x * velocityScale * boost,
                        y: baseVelocity.y * velocityScale * boost
                    )
                    state.touchpadMomentumCandidateVelocity = clampedVelocity
                    state.touchpadMomentumCandidateTime = now
                }
            } else {
                state.touchpadMomentumCandidateVelocity = .zero
                state.touchpadMomentumCandidateTime = 0
                state.touchpadMomentumHighVelocityStartTime = 0
                state.touchpadMomentumHighVelocitySampleCount = 0
                state.touchpadMomentumPeakVelocity = .zero
                state.touchpadMomentumPeakMagnitude = 0
            }
        }
    }

    // MARK: - Touchpad Momentum Scrolling

    /// - Precondition: Must be called on pollingQueue
    nonisolated func processTouchpadMomentumTick(now: CFAbsoluteTime) {
        dispatchPrecondition(condition: .onQueue(pollingQueue))
        guard let snapshot = state.lock.withLock({ () -> (isGestureActive: Bool, panActive: Bool, panVelocity: CGPoint, lastGestureTime: TimeInterval, velocity: CGPoint, wasActive: Bool, residualX: Double, residualY: Double, lastUpdate: TimeInterval)? in
            guard state.isEnabled, !state.isLocked else { return nil }
            return (state.isTouchpadGestureActive, state.touchpadPanActive, state.smoothedTouchpadPanVelocity, state.touchpadMomentumLastGestureTime, state.touchpadMomentumVelocity, state.touchpadMomentumWasActive, state.touchpadScrollResidualX, state.touchpadScrollResidualY, state.touchpadMomentumLastUpdate)
        }) else { return }
        let isGestureActive = snapshot.isGestureActive
        let panActive = snapshot.panActive
        let panVelocity = snapshot.panVelocity
        let lastGestureTime = snapshot.lastGestureTime
        var velocity = snapshot.velocity
        var wasActive = snapshot.wasActive
        var residualX = snapshot.residualX
        var residualY = snapshot.residualY
        let lastUpdate = snapshot.lastUpdate

        if isGestureActive {
            if lastUpdate == 0 {
                state.lock.withLock { state.touchpadMomentumLastUpdate = now }
                return
            }
            guard panActive else {
                state.lock.withLock { state.touchpadMomentumLastUpdate = now }
                return
            }
            let dt = max(now - lastUpdate, Config.touchpadMomentumMinDeltaTime)
            let dx = Double(panVelocity.x) * dt
            let dy = Double(panVelocity.y) * dt
            let combinedDx = dx + residualX
            let combinedDy = dy + residualY
            let sendDx = combinedDx.rounded()
            let sendDy = combinedDy.rounded()
            residualX = combinedDx - sendDx
            residualY = combinedDy - sendDy
            if sendDx != 0 || sendDy != 0 {
                inputSimulator.scroll(
                    dx: CGFloat(sendDx),
                    dy: CGFloat(sendDy),
                    phase: .changed,
                    momentumPhase: nil,
                    isContinuous: true,
                    flags: inputSimulator.getHeldModifiers()
                )
                usageStatsService?.recordScrollDistance(dx: sendDx, dy: sendDy)
            }
            state.lock.withLock {
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = residualX
                state.touchpadScrollResidualY = residualY
            }
            return
        }

        if lastUpdate == 0 {
            state.lock.withLock { state.touchpadMomentumLastUpdate = now }
            return
        }

        let idleInterval = now - lastGestureTime
        if idleInterval > Config.touchpadMomentumMaxIdleInterval {
            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: nil,
                    momentumPhase: .end,
                    isContinuous: true,
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumWasActive = false
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
            return
        }

        let dt = max(now - lastUpdate, Config.touchpadMomentumMinDeltaTime)
        let decay = exp(-Config.touchpadMomentumDecay * dt)
        velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
        let speed = Double(hypot(velocity.x, velocity.y))
        if speed < Config.touchpadMomentumStopVelocity {
            if wasActive {
                inputSimulator.scroll(
                    dx: 0,
                    dy: 0,
                    phase: nil,
                    momentumPhase: .end,
                    isContinuous: true,
                    flags: inputSimulator.getHeldModifiers()
                )
            }
            state.lock.withLock {
                state.touchpadMomentumVelocity = .zero
                state.touchpadMomentumWasActive = false
                state.touchpadMomentumLastUpdate = now
                state.touchpadScrollResidualX = 0
                state.touchpadScrollResidualY = 0
            }
            return
        }

        let dx = Double(velocity.x) * dt
        let dy = Double(velocity.y) * dt
        let combinedDx = dx + residualX
        let combinedDy = dy + residualY
        let sendDx = combinedDx.rounded()
        let sendDy = combinedDy.rounded()
        residualX = combinedDx - sendDx
        residualY = combinedDy - sendDy

        if sendDx != 0 || sendDy != 0 {
            let momentumPhase: CGMomentumScrollPhase = wasActive ? .continuous : .begin
            inputSimulator.scroll(
                dx: CGFloat(sendDx),
                dy: CGFloat(sendDy),
                phase: nil,
                momentumPhase: momentumPhase,
                isContinuous: true,
                flags: inputSimulator.getHeldModifiers()
            )
            wasActive = true
        }

        state.lock.withLock {
            state.touchpadMomentumVelocity = velocity
            state.touchpadMomentumWasActive = wasActive
            state.touchpadMomentumLastUpdate = now
            state.touchpadScrollResidualX = residualX
            state.touchpadScrollResidualY = residualY
        }
    }
}
