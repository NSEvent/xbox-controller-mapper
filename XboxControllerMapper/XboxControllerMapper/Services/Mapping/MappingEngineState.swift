import Foundation
import CoreGraphics

extension MappingEngine {
    /// Thread-safe state container used by `MappingEngine` from polling callbacks.
    final class EngineState: @unchecked Sendable {
        /// Explicit nonisolated deinit prevents Swift 6 from inferring a
        /// MainActor-isolated deinit from the enclosing `@MainActor`
        /// MappingEngine. Without this, the cross-executor deinit hop double-
        /// freed inside SequenceDetector's deallocation (libmalloc abort), which
        /// silently broke every test that constructed an EngineState.
        nonisolated deinit { }

        let lock = NSLock()
        var isEnabled = true
        var isLocked = false

        // Mirrors of MainActor data
        var activeProfile: Profile?
        var frontmostBundleId: String?
        var joystickSettings: JoystickSettings?

        // Precomputed lookup caches (rebuilt on profile change)
        var chordParticipantButtons: Set<ControllerButton> = []
        var sequenceParticipantButtons: Set<ControllerButton> = []
        var chordLookup: [Set<ControllerButton>: ChordMapping] = [:]
        var layersById: [UUID: Layer] = [:]

        // Button State
        var heldButtons: [ControllerButton: KeyMapping] = [:]
        var activeChordButtons: Set<ControllerButton> = []
        var lastTapTime: [ControllerButton: CFAbsoluteTime] = [:]
        var pendingSingleTap: [ControllerButton: DispatchWorkItem] = [:]
        var pendingReleaseActions: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTimers: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTriggered: Set<ControllerButton> = []
        var repeatTimers: [ControllerButton: DispatchSourceTimer] = [:]
        var holdRepeatTimers: [ControllerButton: DispatchSourceTimer] = [:]
		var smoothScrollMappings: [ControllerButton: KeyMapping] = [:]
		var smoothScrollTimers: [ControllerButton: DispatchSourceTimer] = [:]
		var physicalButtonResolutions: [ControllerButton: ControllerButton] = [:]
        // Sequence detection (passive tracking, zero-latency)
        let sequenceDetector = SequenceDetector()

        var onScreenKeyboardButton: ControllerButton? = nil
        var onScreenKeyboardHoldMode: Bool = false
        var laserPointerButton: ControllerButton? = nil
        var laserPointerHoldMode: Bool = false
        var directoryNavigatorButton: ControllerButton? = nil
        var directoryNavigatorHoldMode: Bool = false
        var commandWheelButton: ControllerButton? = nil
        var commandWheelHoldMode: Bool = false
        var commandWheelActive: Bool = false
        var wheelAlternateModifiers: ModifierFlags = ModifierFlags()
        var dpadNavigationTimer: DispatchSourceTimer? = nil
        var dpadNavigationButton: ControllerButton? = nil

        // Layer State
		// Ordered list of manually activated layer IDs; latest item takes priority.
        var activeLayerIds: [UUID] = []
		// App-activated layer sits below every manually held layer.
		var appActivatedLayerId: UUID?
		var effectiveActiveLayerIds: [UUID] {
			var ids = appActivatedLayerId.map { [$0] } ?? []
			ids.append(contentsOf: activeLayerIds.filter { $0 != appActivatedLayerId })
			return ids
		}
        var layerActivatorMap: [ControllerButton: UUID] = [:]
        // Tracks buttons that actually activated a layer (vs. being remapped within another layer)
        var buttonsActingAsLayerActivators: Set<ControllerButton> = []
        // Buttons whose press was consumed by a special action (e.g., double-tap unlock)
        // — release should be a no-op so the single-tap doesn't fire.
        var pressConsumedByAction: Set<ControllerButton> = []
		// Buttons whose in-flight action was cancelled by a routing boundary.
		// Unlike `pressConsumedByAction`, this is checked only on release so a
		// disconnect that never delivers key-up cannot poison the next press.
		var cancelledPhysicalButtonReleases: Set<ControllerButton> = []

        // Joystick State
        var smoothedLeftStick: CGPoint = .zero
        var smoothedRightStick: CGPoint = .zero
        var leftStickHeldKeys: Set<CGKeyCode> = []
        var rightStickHeldKeys: Set<CGKeyCode> = []
        var leftStickHeldDirectionButtons: Set<ControllerButton> = []
        var rightStickHeldDirectionButtons: Set<ControllerButton> = []
        var lastJoystickSampleTime: TimeInterval = 0
        var smoothedTouchpadDelta: CGPoint = .zero
        var lastTouchpadSampleTime: TimeInterval = 0
        // Touchpad movement coalescing: a burst of high-rate touchpad samples is
        // summed into one net delta and applied once per scheduled flush, so a
        // bursty transport (BT→USB bridge dongle, or a wired DualSense at its
        // native high report rate) can't backlog the serial pollingQueue and
        // replay the swipe path. See MappingEngine.enqueueCoalescedTouchpadMovement.
        var coalescedTouchpadDelta: CGPoint = .zero
        var touchpadFlushScheduled: Bool = false
        var smoothedTouchpadCenterDelta: CGPoint = .zero
        var smoothedTouchpadDistanceDelta: Double = 0
        var lastTouchpadGestureSampleTime: TimeInterval = 0
        var isTouchpadGestureActive = false
        var touchpadScrollResidualX: Double = 0
        var touchpadScrollResidualY: Double = 0
        var touchpadMomentumVelocity: CGPoint = .zero
        var touchpadMomentumLastUpdate: TimeInterval = 0
        var touchpadMomentumLastGestureTime: TimeInterval = 0
        var touchpadMomentumWasActive = false
        var touchpadMomentumCandidateVelocity: CGPoint = .zero
        var touchpadMomentumCandidateTime: TimeInterval = 0
        var touchpadMomentumHighVelocityStartTime: TimeInterval = 0
        var touchpadMomentumHighVelocitySampleCount: Int = 0
        var touchpadMomentumPeakVelocity: CGPoint = .zero
        var touchpadMomentumPeakMagnitude: Double = 0
        var smoothedTouchpadPanVelocity: CGPoint = .zero
        var touchpadPanActive = false
        var touchpadPinchAccumulator: Double = 0
        var touchpadMagnifyGestureActive: Bool = false
        var touchpadMagnifyDirection: Double = 0
        var touchpadMagnifyDirectionLockUntil: TimeInterval = 0
		var appleTVRemoteCodexMicroDialAccumulator: Double = 0

        var rightStickWasOutsideDeadzone = false
        var rightStickPeakYAbs: Double = 0
        var rightStickLastDirection: Int = 0
        var lastRightStickTapTime: TimeInterval = 0
        var lastRightStickTapDirection: Int = 0
        var scrollBoostDirection: Int = 0

        // Swipe typing state
        var swipeTypingEnabled: Bool = false
        var swipeTypingSensitivity: Double = 0.5
        var swipeTypingActive: Bool = false
        var swipeTypingCursorX: Double = 0.5
        var swipeTypingCursorY: Double = 0.5
        var wasTouchpadTouching: Bool = false
        var swipeClickReleaseFrames: Int = 0  // debounce: consecutive frames with click released

        // Directory navigator stick navigation
        var directoryNavLastMoveTime: TimeInterval = 0
        var directoryNavStickWasInDeadzone = true

        // Focus mode state
        var wasFocusActive = false
        var currentMultiplier: Double = 0
        var focusExitTime: TimeInterval = 0

        // Gyro aiming filter state
        var gyroFilterX = OneEuroFilter(fcmin: 1.0, beta: 0.007, dcutoff: 1.0)
        var gyroFilterY = OneEuroFilter(fcmin: 1.0, beta: 0.007, dcutoff: 1.0)
        var lastGyroTime: TimeInterval = 0

        /// Thread-safe reset: acquires the lock, resets all transient state, and releases the lock.
        /// Use this when you are NOT already holding the lock.
        func lockedReset() {
            lock.lock()
            defer { lock.unlock() }
            reset()
        }

        /// Resets input/session state that should not survive a routing boundary.
		///
		/// App-layer changes preserve manually held layers and open overlays: those
		/// are user-owned context, not outputs from the outgoing app layer. Profile
		/// changes preserve overlays but clear manual layers because their IDs belong
		/// to the old profile. In both cases, physical releases for cancelled actions
		/// are consumed so they cannot fire a mapping from the incoming context.
		///
        /// Caller MUST already hold `lock`.
		func resetTransientInputState(
			preservingManualLayers: Bool = false,
			preservingUIOverlays: Bool = false,
			consumingPendingButtonReleases: Bool = false
		) {
			let preservedActiveLayerIds = preservingManualLayers ? activeLayerIds : []
			let preservedLayerActivatorButtons = preservingManualLayers
				? buttonsActingAsLayerActivators
				: []

			let preservedOnScreenKeyboardButton = preservingUIOverlays ? onScreenKeyboardButton : nil
			let preservedOnScreenKeyboardHoldMode = preservingUIOverlays && onScreenKeyboardHoldMode
			let preservedLaserPointerButton = preservingUIOverlays ? laserPointerButton : nil
			let preservedLaserPointerHoldMode = preservingUIOverlays && laserPointerHoldMode
			let preservedDirectoryNavigatorButton = preservingUIOverlays ? directoryNavigatorButton : nil
			let preservedDirectoryNavigatorHoldMode = preservingUIOverlays && directoryNavigatorHoldMode
			let preservedCommandWheelButton = preservingUIOverlays ? commandWheelButton : nil
			let preservedCommandWheelHoldMode = preservingUIOverlays && commandWheelHoldMode
			let preservedCommandWheelActive = preservingUIOverlays && commandWheelActive
			let preservedWheelAlternateModifiers = preservingUIOverlays
				? wheelAlternateModifiers
				: ModifierFlags()

			let preservedPhysicalButtonResolutions = consumingPendingButtonReleases
				? physicalButtonResolutions
				: [:]
			let previouslyCancelledPhysicalButtonReleases = consumingPendingButtonReleases
				? cancelledPhysicalButtonReleases
				: []
			var cancelledButtons: Set<ControllerButton> = []
			if consumingPendingButtonReleases {
				cancelledButtons.formUnion(pressConsumedByAction)
				cancelledButtons.formUnion(heldButtons.keys)
				cancelledButtons.formUnion(activeChordButtons)
				cancelledButtons.formUnion(pendingSingleTap.keys)
				cancelledButtons.formUnion(pendingReleaseActions.keys)
				cancelledButtons.formUnion(longHoldTimers.keys)
				cancelledButtons.formUnion(repeatTimers.keys)
				cancelledButtons.formUnion(holdRepeatTimers.keys)
				cancelledButtons.formUnion(smoothScrollMappings.keys)
				cancelledButtons.formUnion(smoothScrollTimers.keys)
				cancelledButtons.formUnion(physicalButtonResolutions.values)

				if preservingManualLayers {
					cancelledButtons.subtract(buttonsActingAsLayerActivators)
				} else {
					cancelledButtons.formUnion(buttonsActingAsLayerActivators)
				}

				if preservingUIOverlays {
					[
						onScreenKeyboardButton,
						laserPointerButton,
						directoryNavigatorButton,
						commandWheelButton
					]
					.compactMap { $0 }
					.forEach { cancelledButtons.remove($0) }
				}
			}
			let resolvedButtonsWithPhysicalInputs = Set(physicalButtonResolutions.values)
			var cancelledPhysicalButtons = Set(
				physicalButtonResolutions.compactMap { physicalButton, resolvedButton in
					cancelledButtons.contains(resolvedButton) ? physicalButton : nil
				}
			)
			cancelledPhysicalButtons.formUnion(
				cancelledButtons.subtracting(resolvedButtonsWithPhysicalInputs)
			)

            heldButtons.removeAll()
            activeChordButtons.removeAll()
            lastTapTime.removeAll()

            pendingSingleTap.values.forEach { $0.cancel() }
            pendingSingleTap.removeAll()

            pendingReleaseActions.values.forEach { $0.cancel() }
            pendingReleaseActions.removeAll()

            longHoldTimers.values.forEach { $0.cancel() }
            longHoldTimers.removeAll()
            longHoldTriggered.removeAll()

            repeatTimers.values.forEach { $0.cancel() }
            repeatTimers.removeAll()

            holdRepeatTimers.values.forEach { $0.cancel() }
            holdRepeatTimers.removeAll()

			smoothScrollTimers.values.forEach { $0.cancel() }
			smoothScrollTimers.removeAll()
			smoothScrollMappings.removeAll()
			physicalButtonResolutions.removeAll()

            sequenceDetector.reset()

            onScreenKeyboardButton = nil
            onScreenKeyboardHoldMode = false
            laserPointerButton = nil
            laserPointerHoldMode = false
            directoryNavigatorButton = nil
            directoryNavigatorHoldMode = false
            commandWheelButton = nil
            commandWheelHoldMode = false
            commandWheelActive = false
            wheelAlternateModifiers = ModifierFlags()

            dpadNavigationTimer?.cancel()
            dpadNavigationTimer = nil
            dpadNavigationButton = nil

            activeLayerIds.removeAll()
            buttonsActingAsLayerActivators.removeAll()
            pressConsumedByAction.removeAll()
			cancelledPhysicalButtonReleases.removeAll()
            // layerActivatorMap is rebuilt on profile updates.

            smoothedLeftStick = .zero
            smoothedRightStick = .zero
            leftStickHeldKeys.removeAll()
            rightStickHeldKeys.removeAll()
            leftStickHeldDirectionButtons.removeAll()
            rightStickHeldDirectionButtons.removeAll()
            lastJoystickSampleTime = 0
            smoothedTouchpadDelta = .zero
            lastTouchpadSampleTime = 0
            coalescedTouchpadDelta = .zero
            touchpadFlushScheduled = false
            smoothedTouchpadCenterDelta = .zero
            smoothedTouchpadDistanceDelta = 0
            lastTouchpadGestureSampleTime = 0
            isTouchpadGestureActive = false
            touchpadScrollResidualX = 0
            touchpadScrollResidualY = 0
            touchpadMomentumVelocity = .zero
            touchpadMomentumLastUpdate = 0
            touchpadMomentumLastGestureTime = 0
            touchpadMomentumWasActive = false
            touchpadMomentumCandidateVelocity = .zero
            touchpadMomentumCandidateTime = 0
            touchpadMomentumHighVelocityStartTime = 0
            touchpadMomentumHighVelocitySampleCount = 0
            touchpadMomentumPeakVelocity = .zero
            touchpadMomentumPeakMagnitude = 0
            smoothedTouchpadPanVelocity = .zero
            touchpadPanActive = false
            touchpadPinchAccumulator = 0
            touchpadMagnifyGestureActive = false
            touchpadMagnifyDirection = 0
            touchpadMagnifyDirectionLockUntil = 0
			appleTVRemoteCodexMicroDialAccumulator = 0
            rightStickWasOutsideDeadzone = false
            rightStickPeakYAbs = 0
            rightStickLastDirection = 0
            lastRightStickTapTime = 0
            lastRightStickTapDirection = 0
            scrollBoostDirection = 0
            // Note: swipeTypingEnabled and swipeTypingSensitivity are config-derived,
            // not transient state — they are set by the profile binding, not reset here.
            swipeTypingActive = false
            swipeTypingCursorX = 0.5
            swipeTypingCursorY = 0.5
            wasTouchpadTouching = false
            swipeClickReleaseFrames = 0
            directoryNavLastMoveTime = 0
            directoryNavStickWasInDeadzone = true
            wasFocusActive = false
            currentMultiplier = 0
            focusExitTime = 0
            gyroFilterX.reset()
            gyroFilterY.reset()
            lastGyroTime = 0

			if preservingManualLayers {
				activeLayerIds = preservedActiveLayerIds
				buttonsActingAsLayerActivators = preservedLayerActivatorButtons
			}

			if preservingUIOverlays {
				onScreenKeyboardButton = preservedOnScreenKeyboardButton
				onScreenKeyboardHoldMode = preservedOnScreenKeyboardHoldMode
				laserPointerButton = preservedLaserPointerButton
				laserPointerHoldMode = preservedLaserPointerHoldMode
				directoryNavigatorButton = preservedDirectoryNavigatorButton
				directoryNavigatorHoldMode = preservedDirectoryNavigatorHoldMode
				commandWheelButton = preservedCommandWheelButton
				commandWheelHoldMode = preservedCommandWheelHoldMode
				commandWheelActive = preservedCommandWheelActive
				wheelAlternateModifiers = preservedWheelAlternateModifiers
			}

			if consumingPendingButtonReleases {
				physicalButtonResolutions = preservedPhysicalButtonResolutions
				cancelledPhysicalButtonReleases =
					previouslyCancelledPhysicalButtonReleases.union(cancelledPhysicalButtons)
			}
        }

        /// Resets all transient state. Caller MUST already hold `lock`.
		func reset(consumingPendingButtonReleases: Bool = false) {
            chordParticipantButtons.removeAll()
            sequenceParticipantButtons.removeAll()
            chordLookup.removeAll()
            layersById.removeAll()
			resetTransientInputState(
				consumingPendingButtonReleases: consumingPendingButtonReleases
			)
        }
    }
}
