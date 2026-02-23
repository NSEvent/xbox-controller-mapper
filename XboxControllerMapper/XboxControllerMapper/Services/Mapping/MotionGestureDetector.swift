import Foundation

/// Detects motion gestures (tilt/steer) from gyroscope rotation rates.
/// Extracted from ControllerService+Motion.swift processAxis() state machine.
///
/// Processes pitch (tilt back/forward) and roll (steer left/right) axes independently.
/// Uses a peak-detection state machine per axis: idle -> tracking -> settling -> idle.
///
/// Thread safety: This class is NOT thread-safe. Callers must synchronize access externally
/// (e.g., via the ControllerStorage lock).
final class MotionGestureDetector: GestureDetecting {
    typealias Input = (pitchRate: Double, rollRate: Double)
    typealias Result = MotionGestureType

    /// Per-axis gesture detection state.
    struct AxisGestureState {
        enum Phase {
            case idle
            case tracking
            case settling
        }

        var phase: Phase = .idle
        var peakVelocity: Double = 0
        var peakSign: Double = 0
        var startTime: TimeInterval = 0
        var lastGestureTime: TimeInterval = 0
        var lastGestureSign: Double = 0
    }

    private(set) var pitchState = AxisGestureState()
    private(set) var rollState = AxisGestureState()

    // Configurable thresholds (default to Config values for backward compatibility)
    var pitchActivationThreshold: Double = Config.gestureActivationThreshold
    var pitchMinPeakVelocity: Double = Config.gestureMinPeakVelocity
    var rollActivationThreshold: Double = Config.gestureRollActivationThreshold
    var rollMinPeakVelocity: Double = Config.gestureRollMinPeakVelocity
    var cooldown: TimeInterval = Config.gestureCooldown
    var oppositeDirectionCooldown: TimeInterval = Config.gestureOppositeDirectionCooldown

    /// Process gyroscope rotation rates and detect completed gestures.
    ///
    /// Since two axes are processed independently, this may return a pitch gesture.
    /// Use `processAll(_:at:)` to get all completed gestures in one call.
    ///
    /// - Parameters:
    ///   - input: Tuple of (pitchRate, rollRate) rotation velocities.
    ///   - time: Current timestamp (any monotonic time source).
    /// - Returns: The first completed gesture, or nil.
    func process(_ input: Input, at time: TimeInterval) -> MotionGestureType? {
        let results = processAll(input, at: time)
        return results.first
    }

    /// Process gyroscope rotation rates and return all completed gestures.
    ///
    /// - Parameters:
    ///   - input: Tuple of (pitchRate, rollRate) rotation velocities.
    ///   - time: Current timestamp (any monotonic time source).
    /// - Returns: Array of completed gestures (0, 1, or 2 elements).
    func processAll(_ input: Input, at time: TimeInterval) -> [MotionGestureType] {
        var results: [MotionGestureType] = []

        if let (peakVelocity, peakSign) = processAxis(
            state: &pitchState,
            velocity: input.pitchRate,
            activationThreshold: pitchActivationThreshold,
            now: time
        ), peakVelocity >= pitchMinPeakVelocity {
            results.append(peakSign > 0 ? .tiltBack : .tiltForward)
        }

        if let (peakVelocity, peakSign) = processAxis(
            state: &rollState,
            velocity: input.rollRate,
            activationThreshold: rollActivationThreshold,
            now: time
        ), peakVelocity >= rollMinPeakVelocity {
            results.append(peakSign > 0 ? .steerLeft : .steerRight)
        }

        return results
    }

    /// Reset all tracking state for both axes.
    func reset() {
        pitchState = AxisGestureState()
        rollState = AxisGestureState()
    }

    // MARK: - Private

    /// Runs the peak-detection state machine for a single axis.
    /// Returns (peakVelocity, peakSign) if a gesture completed, nil otherwise.
    private func processAxis(
        state: inout AxisGestureState,
        velocity: Double,
        activationThreshold: Double,
        now: TimeInterval
    ) -> (Double, Double)? {
        let absVelocity = abs(velocity)

        switch state.phase {
        case .idle:
            let currentSign: Double = velocity > 0 ? 1.0 : -1.0
            let isOppositeDirection = state.lastGestureSign != 0 && currentSign != state.lastGestureSign
            let requiredCooldown = isOppositeDirection
                ? oppositeDirectionCooldown
                : cooldown
            let cooldownElapsed = (now - state.lastGestureTime) >= requiredCooldown

            if absVelocity >= activationThreshold && cooldownElapsed {
                state.phase = .tracking
                state.peakVelocity = absVelocity
                state.peakSign = currentSign
                state.startTime = now
            }
            return nil

        case .tracking:
            let duration = now - state.startTime

            if duration > Config.gestureMaxDuration {
                state.phase = .idle
                return nil
            }

            if absVelocity > state.peakVelocity {
                state.peakVelocity = absVelocity
                state.peakSign = velocity > 0 ? 1.0 : -1.0
            }

            let completionThreshold = state.peakVelocity * Config.gestureCompletionRatio
            if absVelocity < completionThreshold {
                let result = (state.peakVelocity, state.peakSign)

                state.phase = .settling
                state.lastGestureTime = now
                state.lastGestureSign = state.peakSign

                return result
            }

            return nil

        case .settling:
            if absVelocity < Config.gestureSettlingThreshold {
                let cooldownElapsed = (now - state.lastGestureTime) >= cooldown
                if cooldownElapsed {
                    state.phase = .idle
                }
            }
            return nil
        }
    }
}
