import Foundation
import GameController

// MARK: - Touchpad Handling

@MainActor
extension ControllerService {

    // MARK: - Shared Touchpad Setup (DualSense / DualShock)

    /// Configures touchpad handlers shared by DualSense and DualShock controllers.
    func setupTouchpadHandlers(
        primary: GCControllerDirectionPad,
        secondary: GCControllerDirectionPad,
        button: GCControllerButtonInput
    ) {
        // Avoid system gesture delays on touchpad input
        primary.preferredSystemGestureState = .alwaysReceive
        secondary.preferredSystemGestureState = .alwaysReceive
        button.preferredSystemGestureState = .alwaysReceive

        // Touchpad button (click)
        // Two-finger + click triggers touchpadTwoFingerButton, single finger triggers touchpadButton
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }
            let isTwoFingerClick = self.armTouchpadClick(pressed: pressed)

            if pressed {
                self.storage.lock.lock()
                let willBeTwoFingerClick = self.storage.touchpadTwoFingerClickArmed
                self.storage.lock.unlock()

                if willBeTwoFingerClick {
                    self.controllerQueue.async { self.handleButton(.touchpadTwoFingerButton, pressed: true) }
                } else {
                    self.controllerQueue.async { self.handleButton(.touchpadButton, pressed: true) }
                }
            } else {
                if isTwoFingerClick {
                    self.controllerQueue.async { self.handleButton(.touchpadTwoFingerButton, pressed: false) }
                } else {
                    self.controllerQueue.async { self.handleButton(.touchpadButton, pressed: false) }
                }
            }
        }

        // Touchpad primary finger position (for mouse control)
        primary.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateTouchpad(x: xValue, y: yValue)
        }

        // Touchpad secondary finger position (for gestures)
        secondary.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateTouchpadSecondary(x: xValue, y: yValue)
        }
    }

    /// Computes a two-finger gesture using the shared center point.
    /// Requires storage.lock to be held by the caller.
    nonisolated func computeTwoFingerGestureLocked(secondaryFresh: Bool) -> TouchpadGesture? {
        guard storage.isTouchpadTouching, storage.isTouchpadSecondaryTouching, secondaryFresh else {
            storage.touchpadGestureHasCenter = false
            return nil
        }

        let distance = hypot(
            storage.touchpadPosition.x - storage.touchpadSecondaryPosition.x,
            storage.touchpadPosition.y - storage.touchpadSecondaryPosition.y
        )
        guard Double(distance) > Config.touchpadTwoFingerMinDistance else {
            storage.touchpadGestureHasCenter = false
            return nil
        }

        let currentCenter = CGPoint(
            x: (storage.touchpadPosition.x + storage.touchpadSecondaryPosition.x) * 0.5,
            y: (storage.touchpadPosition.y + storage.touchpadSecondaryPosition.y) * 0.5
        )
        let currentDistance = Double(distance)

        if !storage.touchpadGestureHasCenter {
            storage.touchpadGestureHasCenter = true
            storage.touchpadGesturePreviousCenter = currentCenter
            storage.touchpadGesturePreviousDistance = currentDistance
            return TouchpadGesture(
                centerDelta: .zero,
                distanceDelta: 0,
                isPrimaryTouching: storage.isTouchpadTouching,
                isSecondaryTouching: storage.isTouchpadSecondaryTouching
            )
        }

        let previousCenter = storage.touchpadGesturePreviousCenter
        let previousDistance = storage.touchpadGesturePreviousDistance
        let centerDelta = CGPoint(
            x: currentCenter.x - previousCenter.x,
            y: currentCenter.y - previousCenter.y
        )
        let distanceDelta = currentDistance - previousDistance

        storage.touchpadGesturePreviousCenter = currentCenter
        storage.touchpadGesturePreviousDistance = currentDistance
        storage.touchpadTwoFingerGestureDistance += hypot(Double(centerDelta.x), Double(centerDelta.y))
        storage.touchpadTwoFingerPinchDistance += abs(distanceDelta)

        return TouchpadGesture(
            centerDelta: centerDelta,
            distanceDelta: distanceDelta,
            isPrimaryTouching: storage.isTouchpadTouching,
            isSecondaryTouching: storage.isTouchpadSecondaryTouching
        )
    }

    // MARK: - Primary Touchpad Handler

    /// Handles primary touchpad finger input. This is a state machine with three main states:
    /// 1. Touch Start: Initialize position tracking and start long tap timer
    /// 2. Touch Continue: Calculate deltas, detect gestures, handle tap cooldowns
    /// 3. Touch End: Detect taps, cleanup state, fire callbacks
    nonisolated func updateTouchpad(x: Float, y: Float) {
        defer { logTouchpadDebugIfNeeded(source: "primary") }
        storage.lock.lock()

        // MARK: Initial Setup
        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadTouching
        let wasTwoFinger = storage.isTouchpadTouching && storage.isTouchpadSecondaryTouching
        let gestureCallback = storage.onTouchpadGesture
        let now = CFAbsoluteTimeGetCurrent()
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        // Secondary finger block is handled by secondaryFresh checks below.

        // MARK: Sentinel-based Touch Detection
        // Detect if finger is on touchpad (non-zero position indicates touch)
        // GCControllerDirectionPad returns 0,0 when no finger is present
        var isTouching = abs(x) > 0.001 || abs(y) > 0.001
        if !storage.touchpadHasSeenTouch, isTouching {
            if let sentinel = storage.touchpadIdleSentinel {
                let isNearSentinel = abs(newPosition.x - sentinel.x) <= TouchpadIdleSentinelConfig.activationThreshold &&
                    abs(newPosition.y - sentinel.y) <= TouchpadIdleSentinelConfig.activationThreshold
                if isNearSentinel {
                    isTouching = false
                } else {
                    storage.touchpadHasSeenTouch = true
                    storage.touchpadIdleSentinel = nil
                }
            } else {
                storage.touchpadIdleSentinel = newPosition
                isTouching = false
            }
        }
        if isTouching {
            storage.touchpadHasSeenTouch = true
        }

        if isTouching {
            if wasTouching {
                if storage.touchpadClickArmed {
                    let distance = Double(hypot(
                        newPosition.x - storage.touchpadClickStartPosition.x,
                        newPosition.y - storage.touchpadClickStartPosition.y
                    ))
                    if distance < Config.touchpadClickMovementThreshold {
                        storage.touchpadPosition = newPosition
                        storage.touchpadPreviousPosition = newPosition
                        storage.pendingTouchpadDelta = nil
                        storage.lock.unlock()
                        return
                    }

                    storage.touchpadClickArmed = false
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                if storage.touchpadMovementBlocked || secondaryFresh {
                    storage.pendingTouchpadDelta = nil
                    if secondaryFresh {
                        storage.touchpadPreviousPosition = storage.touchpadPosition
                    } else {
                        storage.touchpadPreviousPosition = newPosition
                    }
                    storage.touchpadPosition = newPosition
                    let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)
                    let gestureCallback = storage.onTouchpadGesture
                    storage.lock.unlock()

                    if let gesture {
                        gestureCallback?(gesture)
                    }
                    return
                }

                // Increment frame counter
                storage.touchpadFramesSinceTouch += 1

                // Skip first 2 frames after touch to let position settle
                // This prevents spurious movement when finger first contacts touchpad
                // Update touchStartPosition so the settle check uses the stable position
                // (the initial touch position from hardware can be noisy/incorrect)
                // NOTE: Do NOT update touchpadTouchStartTime - keep counting from original touch
                if storage.touchpadFramesSinceTouch <= 2 {
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.touchpadTouchStartPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                // Touch settle: suppress movement for short taps/holds where finger is stationary
                // Only allow movement after settle time OR finger has moved significantly from start
                let timeSinceTouchStart = now - storage.touchpadTouchStartTime
                let distanceFromStart = Double(hypot(
                    newPosition.x - storage.touchpadTouchStartPosition.x,
                    newPosition.y - storage.touchpadTouchStartPosition.y
                ))
                let inSettlePeriod = timeSinceTouchStart < Config.touchpadTouchSettleInterval
                let belowMovementThreshold = distanceFromStart < Config.touchpadClickMovementThreshold

                if inSettlePeriod && belowMovementThreshold {
                    // Still settling - update position but don't generate movement
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                // Finger still touching - calculate delta
                let delta = CGPoint(
                    x: newPosition.x - storage.touchpadPosition.x,
                    y: newPosition.y - storage.touchpadPosition.y
                )

                // Detect sudden large jumps which indicate:
                // 1. Finger lift (touchpad sends edge position before resetting)
                // 2. Position wrap/reset during long drags
                // Ignore deltas larger than threshold (normal finger movement is much smaller)
                let jumpThreshold: CGFloat = 0.3
                let isJump = abs(delta.x) > jumpThreshold || abs(delta.y) > jumpThreshold

                if isJump {
                    // Treat as new touch - reset position, don't apply delta
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                storage.touchpadPreviousPosition = storage.touchpadPosition
                storage.touchpadPosition = newPosition

                // Track max distance from start for tap detection
                let currentDistance = Double(hypot(
                    newPosition.x - storage.touchpadTouchStartPosition.x,
                    newPosition.y - storage.touchpadTouchStartPosition.y
                ))
                if currentDistance > storage.touchpadMaxDistanceFromStart {
                    storage.touchpadMaxDistanceFromStart = currentDistance
                    // Cancel long tap timer if finger moved too much (uses tighter threshold)
                    if currentDistance >= Config.touchpadLongTapMaxMovement {
                        storage.touchpadLongTapTimer?.cancel()
                        storage.touchpadLongTapTimer = nil
                    }
                }

                // Apply the PREVIOUS pending delta (if any), then store current as pending
                // This 1-frame delay filters out artifacts right before finger lift
                let previousPending = storage.pendingTouchpadDelta
                let callback = storage.onTouchpadMoved

                // Store current delta as pending for next frame
                if abs(delta.x) > 0.001 || abs(delta.y) > 0.001 {
                    storage.pendingTouchpadDelta = delta
                } else {
                    storage.pendingTouchpadDelta = nil
                }

                let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)

                let isSecondaryTouching = storage.isTouchpadSecondaryTouching
                storage.lock.unlock()

                if let gesture {
                    gestureCallback?(gesture)
                } else if let pending = previousPending, !isSecondaryTouching {
                    callback?(pending)
                }
            } else {
                // Finger just touched - initialize position, no delta yet
                storage.touchpadPosition = newPosition
                storage.touchpadPreviousPosition = newPosition
                storage.isTouchpadTouching = true
                storage.touchpadGestureHasCenter = false
                storage.touchpadGesturePreviousCenter = .zero
                storage.touchpadGesturePreviousDistance = 0
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
                storage.touchpadTouchStartTime = now
                storage.touchpadTouchStartPosition = newPosition
                storage.touchpadMaxDistanceFromStart = 0
                // Check if secondary is already touching (for two-finger tap detection)
                let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
                storage.touchpadWasTwoFingerDuringTouch = secondaryFresh
                storage.touchpadTwoFingerGestureDistance = 0  // Reset for new touch session
                storage.touchpadTwoFingerPinchDistance = 0
                // Block movement if this touch starts within cooldown of a previous tap
                // This prevents double-tap from causing mouse movement between taps
                if (now - storage.touchpadLastTapTime) < Config.touchpadTapCooldown {
                    storage.touchpadMovementBlocked = true
                }
                if storage.touchpadClickArmed {
                    storage.touchpadClickStartPosition = newPosition
                }
                // Cancel any existing long tap timer and reset state
                storage.touchpadLongTapTimer?.cancel()
                storage.touchpadLongTapTimer = nil
                storage.touchpadLongTapFired = false

                // Start long tap timer
                let longTapCallback = secondaryFresh ? storage.onTouchpadTwoFingerLongTap : storage.onTouchpadLongTap
                if longTapCallback != nil {
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.storage.lock.lock()
                        // Only fire if finger hasn't moved too much
                        let distance = self.storage.touchpadMaxDistanceFromStart
                        let stillTouching = self.storage.isTouchpadTouching
                        let isTwoFinger = self.storage.touchpadWasTwoFingerDuringTouch
                        let callback = isTwoFinger ? self.storage.onTouchpadTwoFingerLongTap : self.storage.onTouchpadLongTap
                        if stillTouching && distance < Config.touchpadLongTapMaxMovement {
                            self.storage.touchpadLongTapFired = true
                            self.storage.lock.unlock()
                            self.controllerQueue.async { callback?() }
                        } else {
                            self.storage.lock.unlock()
                        }
                    }
                    storage.touchpadLongTapTimer = workItem
                    controllerQueue.asyncAfter(deadline: .now() + Config.touchpadLongTapThreshold, execute: workItem)
                }
                storage.lock.unlock()
            }
        } else {
            // Finger lifted - discard any pending delta (it was likely lift artifact)
            // Cancel long tap timer
            storage.touchpadLongTapTimer?.cancel()
            storage.touchpadLongTapTimer = nil
            storage.touchpadGestureHasCenter = false
            storage.touchpadGesturePreviousCenter = .zero
            storage.touchpadGesturePreviousDistance = 0
            let longTapFired = storage.touchpadLongTapFired

            // Check for tap: short touch duration with minimal movement
            // Use maxDistanceFromStart instead of final position (which may be corrupted by lift artifacts)
            let touchDuration = now - storage.touchpadTouchStartTime
            let touchDistance = storage.touchpadMaxDistanceFromStart
            let wasTwoFingerDuringTouch = storage.touchpadWasTwoFingerDuringTouch
            let clickFiredDuringTouch = storage.touchpadClickFiredDuringTouch

            // Single-finger tap: short duration, minimal movement, NOT a two-finger gesture,
            // long tap not fired, and no physical click during this touch
            let isSingleTap = wasTouching &&
                !wasTwoFingerDuringTouch &&
                !longTapFired &&
                !clickFiredDuringTouch &&
                touchDuration < Config.touchpadTapMaxDuration &&
                touchDistance < Config.touchpadTapMaxMovement
            let tapCallback = isSingleTap ? storage.onTouchpadTap : nil

            // Two-finger tap: both fingers had short duration and minimal movement, long tap not fired,
            // and no physical click during this touch
            // Secondary finger uses more lenient threshold due to touchpad noise
            // Also check that there wasn't significant gesture (scroll/pinch) movement
            let secondaryTouchDuration = now - storage.touchpadSecondaryTouchStartTime
            let secondaryTouchDistance = storage.touchpadSecondaryMaxDistanceFromStart
            let gestureDistance = storage.touchpadTwoFingerGestureDistance
            let pinchDistance = storage.touchpadTwoFingerPinchDistance
            let isTwoFingerTap = wasTwoFingerDuringTouch &&
                !longTapFired &&
                !clickFiredDuringTouch &&
                touchDuration < Config.touchpadTapMaxDuration &&
                touchDistance < Config.touchpadTapMaxMovement &&
                secondaryTouchDuration < Config.touchpadTapMaxDuration &&
                secondaryTouchDistance < Config.touchpadTwoFingerTapMaxMovement &&
                gestureDistance < Config.touchpadTwoFingerTapMaxGestureDistance &&
                pinchDistance < Config.touchpadTwoFingerTapMaxPinchDistance
            let twoFingerTapCallback = isTwoFingerTap ? storage.onTouchpadTwoFingerTap : nil

            if isSingleTap || isTwoFingerTap {
                storage.touchpadLastTapTime = now
            }

            storage.isTouchpadTouching = false
            storage.touchpadPosition = .zero
            storage.touchpadPreviousPosition = .zero
            storage.touchpadFramesSinceTouch = 0
            storage.pendingTouchpadDelta = nil
            storage.touchpadClickArmed = false
            storage.touchpadClickFiredDuringTouch = false
            storage.touchpadMovementBlocked = false
            storage.touchpadLongTapFired = false
            let isSecondaryTouching = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = storage.isTouchpadTouching && isSecondaryTouching
            storage.lock.unlock()

            // Fire tap callback if it was a tap (not if long tap was fired)
            tapCallback?()
            twoFingerTapCallback?()

            if wasTwoFinger && !isTwoFinger {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: isSecondaryTouching
                ))
            }
        }
    }

    nonisolated func updateTouchpadSecondary(x: Float, y: Float) {
        defer { logTouchpadDebugIfNeeded(source: "secondary") }
        storage.lock.lock()

        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadSecondaryTouching
        let wasTwoFinger = storage.isTouchpadTouching && storage.isTouchpadSecondaryTouching
        let gestureCallback = storage.onTouchpadGesture
        let now = CFAbsoluteTimeGetCurrent()

        // Detect if finger is on touchpad (non-zero position indicates touch)
        var isTouching = abs(x) > 0.001 || abs(y) > 0.001
        if !storage.touchpadSecondaryHasSeenTouch, isTouching {
            if let sentinel = storage.touchpadSecondaryIdleSentinel {
                let isNearSentinel = abs(newPosition.x - sentinel.x) <= TouchpadIdleSentinelConfig.activationThreshold &&
                    abs(newPosition.y - sentinel.y) <= TouchpadIdleSentinelConfig.activationThreshold
                if isNearSentinel {
                    isTouching = false
                } else {
                    storage.touchpadSecondaryHasSeenTouch = true
                    storage.touchpadSecondaryIdleSentinel = nil
                }
            } else {
                storage.touchpadSecondaryIdleSentinel = newPosition
                isTouching = false
            }
        }
        if isTouching {
            storage.touchpadSecondaryHasSeenTouch = true
        }

        if isTouching {
            if wasTouching {
                storage.touchpadSecondaryFramesSinceTouch += 1
                storage.touchpadSecondaryLastUpdate = now
                storage.touchpadSecondaryLastTouchTime = now

                // Skip first 2 frames after touch to let position settle
                if storage.touchpadSecondaryFramesSinceTouch <= 2 {
                    storage.touchpadSecondaryPosition = newPosition
                    storage.touchpadSecondaryPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                let delta = CGPoint(
                    x: newPosition.x - storage.touchpadSecondaryPosition.x,
                    y: newPosition.y - storage.touchpadSecondaryPosition.y
                )

                let jumpThreshold: CGFloat = 0.3
                let isJump = abs(delta.x) > jumpThreshold || abs(delta.y) > jumpThreshold
                if isJump {
                    storage.touchpadSecondaryPosition = newPosition
                    storage.touchpadSecondaryPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                storage.touchpadSecondaryPreviousPosition = storage.touchpadSecondaryPosition
                storage.touchpadSecondaryPosition = newPosition

                // Track max distance from start for two-finger tap detection
                let distanceFromStart = hypot(
                    Double(newPosition.x - storage.touchpadSecondaryTouchStartPosition.x),
                    Double(newPosition.y - storage.touchpadSecondaryTouchStartPosition.y)
                )
                storage.touchpadSecondaryMaxDistanceFromStart = max(storage.touchpadSecondaryMaxDistanceFromStart, distanceFromStart)
            } else {
                // Finger just touched - initialize position and tracking for two-finger tap
                storage.touchpadSecondaryPosition = newPosition
                storage.touchpadSecondaryPreviousPosition = newPosition
                storage.isTouchpadSecondaryTouching = true
                storage.touchpadGestureHasCenter = false
                storage.touchpadGesturePreviousCenter = .zero
                storage.touchpadGesturePreviousDistance = 0
                storage.touchpadSecondaryFramesSinceTouch = 0
                storage.touchpadSecondaryLastUpdate = now
                storage.touchpadSecondaryLastTouchTime = now
                storage.touchpadSecondaryTouchStartTime = now
                storage.touchpadSecondaryTouchStartPosition = newPosition
                storage.touchpadSecondaryMaxDistanceFromStart = 0
                let isPrimaryTouching = storage.isTouchpadTouching
                // Mark that two fingers touched during this primary touch session
                if isPrimaryTouching {
                    storage.touchpadWasTwoFingerDuringTouch = true
                }
                let gestureCallback = storage.onTouchpadGesture
                storage.lock.unlock()

                if isPrimaryTouching {
                    gestureCallback?(TouchpadGesture(
                        centerDelta: .zero,
                        distanceDelta: 0,
                        isPrimaryTouching: true,
                        isSecondaryTouching: true
                    ))
                }
                return
            }

            let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)
            storage.lock.unlock()
            if let gesture {
                gestureCallback?(gesture)
            }
        } else {
            storage.isTouchpadSecondaryTouching = false
            storage.touchpadSecondaryPosition = .zero
            storage.touchpadSecondaryPreviousPosition = .zero
            storage.touchpadSecondaryFramesSinceTouch = 0
            storage.touchpadSecondaryLastUpdate = now
            storage.touchpadGestureHasCenter = false
            storage.touchpadGesturePreviousCenter = .zero
            storage.touchpadGesturePreviousDistance = 0
            let isPrimaryTouching = storage.isTouchpadTouching
            let isTwoFinger = isPrimaryTouching && storage.isTouchpadSecondaryTouching
            storage.lock.unlock()

            if wasTwoFinger && !isTwoFinger {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: isPrimaryTouching,
                    isSecondaryTouching: false
                ))
            } else if isPrimaryTouching {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: false
                ))
            }
        }
    }

    nonisolated func logTouchpadDebugIfNeeded(source: String) {
        let envEnabled = ProcessInfo.processInfo.environment[Config.touchpadDebugEnvKey] == "1"
        let defaultsEnabled = UserDefaults.standard.bool(forKey: Config.touchpadDebugLoggingKey)
        guard envEnabled || defaultsEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        storage.lock.lock()
        if now - storage.touchpadDebugLastLogTime < Config.touchpadDebugLogInterval {
            storage.lock.unlock()
            return
        }
        storage.touchpadDebugLastLogTime = now

        let primary = storage.touchpadPosition
        let secondary = storage.touchpadSecondaryPosition
        let primaryTouching = storage.isTouchpadTouching
        let secondaryTouching = storage.isTouchpadSecondaryTouching
        let blocked = storage.touchpadMovementBlocked
        let distance = hypot(primary.x - secondary.x, primary.y - secondary.y)
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        storage.lock.unlock()

        #if DEBUG
        print(String(
            format: "TP[%@] p=(%.3f,%.3f) s=(%.3f,%.3f) touch=%d/%d blocked=%d dist=%.3f fresh=%d",
            source,
            primary.x, primary.y,
            secondary.x, secondary.y,
            primaryTouching ? 1 : 0,
            secondaryTouching ? 1 : 0,
            blocked ? 1 : 0,
            distance,
            secondaryFresh ? 1 : 0
        ))
        #endif
    }

    /// Arms/disarms touchpad click and detects two-finger clicks.
    /// Returns true if this is a two-finger click (on release), in which case the normal button handling should be suppressed.
    nonisolated func armTouchpadClick(pressed: Bool) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        storage.lock.lock()
        if pressed {
            storage.touchpadClickArmed = true
            storage.touchpadClickStartPosition = storage.touchpadPosition
            storage.touchpadClickFiredDuringTouch = true  // Suppress tap when touch ends
            storage.pendingTouchpadDelta = nil
            storage.touchpadFramesSinceTouch = 0

            // Check if two fingers are on the touchpad
            let isPrimaryTouching = storage.isTouchpadTouching
            let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = isPrimaryTouching && secondaryFresh
            storage.touchpadTwoFingerClickArmed = isTwoFinger
            storage.lock.unlock()
            return false  // On press, don't suppress yet
        } else {
            storage.touchpadClickArmed = false
            let wasTwoFingerClick = storage.touchpadTwoFingerClickArmed
            storage.touchpadTwoFingerClickArmed = false
            storage.lock.unlock()
            return wasTwoFingerClick  // On release, return whether to suppress normal handling
        }
    }
}
