import Foundation
import CoreGraphics

extension MappingEngine {
    /// Thread-safe state container used by `MappingEngine` from polling callbacks.
    final class EngineState: @unchecked Sendable {
        let lock = NSLock()
        var isEnabled = true

        // Mirrors of MainActor data
        var activeProfile: Profile?
        var frontmostBundleId: String?
        var joystickSettings: JoystickSettings?

        // Button State
        var heldButtons: [ControllerButton: KeyMapping] = [:]
        var activeChordButtons: Set<ControllerButton> = []
        var lastTapTime: [ControllerButton: Date] = [:]
        var pendingSingleTap: [ControllerButton: DispatchWorkItem] = [:]
        var pendingReleaseActions: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTimers: [ControllerButton: DispatchWorkItem] = [:]
        var longHoldTriggered: Set<ControllerButton> = []
        var repeatTimers: [ControllerButton: DispatchSourceTimer] = [:]
        var onScreenKeyboardButton: ControllerButton? = nil
        var onScreenKeyboardHoldMode: Bool = false
        var commandWheelActive: Bool = false
        var wheelAlternateModifiers: ModifierFlags = ModifierFlags()
        var dpadNavigationTimer: DispatchSourceTimer? = nil
        var dpadNavigationButton: ControllerButton? = nil

        // Layer State
        // Ordered list of active layer IDs; latest item takes priority.
        var activeLayerIds: [UUID] = []
        var layerActivatorMap: [ControllerButton: UUID] = [:]

        // Joystick State
        var smoothedLeftStick: CGPoint = .zero
        var smoothedRightStick: CGPoint = .zero
        var leftStickHeldKeys: Set<CGKeyCode> = []
        var rightStickHeldKeys: Set<CGKeyCode> = []
        var lastJoystickSampleTime: TimeInterval = 0
        var smoothedTouchpadDelta: CGPoint = .zero
        var lastTouchpadSampleTime: TimeInterval = 0
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

        var rightStickWasOutsideDeadzone = false
        var rightStickPeakYAbs: Double = 0
        var rightStickLastDirection: Int = 0
        var lastRightStickTapTime: TimeInterval = 0
        var lastRightStickTapDirection: Int = 0
        var scrollBoostDirection: Int = 0

        // Focus mode state
        var wasFocusActive = false
        var currentMultiplier: Double = 0
        var focusExitTime: TimeInterval = 0

        func reset() {
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

            dpadNavigationTimer?.cancel()
            dpadNavigationTimer = nil
            dpadNavigationButton = nil

            activeLayerIds.removeAll()
            // layerActivatorMap is rebuilt on profile updates.

            smoothedLeftStick = .zero
            smoothedRightStick = .zero
            leftStickHeldKeys.removeAll()
            rightStickHeldKeys.removeAll()
            lastJoystickSampleTime = 0
            smoothedTouchpadDelta = .zero
            lastTouchpadSampleTime = 0
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
            rightStickWasOutsideDeadzone = false
            rightStickPeakYAbs = 0
            rightStickLastDirection = 0
            lastRightStickTapTime = 0
            lastRightStickTapDirection = 0
            scrollBoostDirection = 0
            wasFocusActive = false
            currentMultiplier = 0
            focusExitTime = 0
        }
    }
}
