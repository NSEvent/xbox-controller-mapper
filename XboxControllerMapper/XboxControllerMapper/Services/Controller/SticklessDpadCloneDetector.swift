import Foundation
import CoreGraphics

/// Behavioral, manufacturer-independent detector for a "stickless d-pad clone":
/// a pad (e.g. 8BitDo Zero 2) that impersonates a first-party controller —
/// a Nintendo Pro Controller in Switch mode, a Sony DualShock 4 in Mac mode —
/// but has no analog stick. Its physical d-pad is funneled through the left
/// thumbstick, so the d-pad ends up driving both the stick (→ mouse) and, in
/// some modes, the d-pad buttons. We detect that so the d-pad can be routed to
/// the stick only (mouse by default, or the user's chosen D-Pad mode).
///
/// Why behavioral instead of the HID manufacturer string: a clone leaves the
/// manufacturer empty — but so can a *genuine* first-party pad over Bluetooth,
/// so that signal misclassifies real controllers. Instead we use a property
/// that holds by construction: a real analog stick is sampled continuously, so
/// pushing it from center to full ALWAYS sweeps through intermediate
/// magnitudes. A clone's "stick" is a digital d-pad — it jumps center→full with
/// nothing in between.
///
/// Latch rule: count a "snap" each time the stick jumps from rest (center) to
/// full with no intermediate magnitude in between, and latch only after TWO
/// such snaps. A snap is counted at most once per center→full cycle — the stick
/// must return to center to arm the next one. Two snaps are required because a
/// single fast flick of a *real* analog stick could, in principle, skip the
/// intermediate band in one sample interval; but its spring-back to center
/// always sweeps through intermediate magnitudes, which permanently disqualifies
/// it before a second snap can occur. Only a genuinely digital d-pad produces
/// two clean center→full jumps. The center-first requirement also avoids a false
/// positive when a real stick is held deflected as the controller connects (its
/// first sample is full with no prior center). Any intermediate value permanently
/// rules out the clone. Default is "not a clone", so genuine controllers are
/// never altered; the latch is sticky for the connection and cleared on disconnect.
///
/// Thread-safe: HID callbacks and GameController handlers run on different
/// queues, so all state is guarded by an internal lock. Explicitly
/// `nonisolated` — the project defaults types to `@MainActor`, but this is fed
/// entirely from background queues, and a MainActor-isolated deinit would hop
/// to the main executor (wrong, and it crashes the duplicate-linked test host).
nonisolated final class SticklessDpadCloneDetector: @unchecked Sendable {
    private let lock = NSLock()
    private var hasAnalogStick = false
    /// Armed once the stick has been seen at center since the last counted snap.
    private var armed = false
    private var fullSnaps = 0
    private var latched = false

    /// A magnitude strictly between these bounds can only come from a real,
    /// continuously-sampled analog stick — a digital d-pad jumps center→full.
    private static let analogLow = 0.18
    private static let analogHigh = 0.82
    /// At/above this magnitude is a "full" deflection (d-pad-like). Cardinals
    /// read ~1.0, diagonals ~1.41.
    private static let fullThreshold = 0.82
    /// Below this magnitude counts as the stick resting at center.
    private static let centerThreshold = 0.10
    /// Distinct center→full snaps (with no intermediate ever) required to latch.
    /// Two, so one improbably-fast flick of a real stick can't false-latch — its
    /// spring-back disqualifies it before a second snap.
    private static let requiredFullSnaps = 2

    /// True once the device has been identified as a stickless d-pad clone.
    var isSticklessClone: Bool {
        lock.lock(); defer { lock.unlock() }
        return latched
    }

    /// Clear all state. Call on disconnect / controller change.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        hasAnalogStick = false
        armed = false
        fullSnaps = 0
        latched = false
    }

    /// Feed a left-stick sample. Use the cleanest source available — raw HID for
    /// the Nintendo path (exact digital values), the GameController stick for
    /// DualShock.
    func noteLeftStick(_ point: CGPoint) {
        let mag = (point.x * point.x + point.y * point.y).squareRoot()
        lock.lock(); defer { lock.unlock() }
        guard !latched, !hasAnalogStick else { return }

        if mag < Self.centerThreshold {
            // At rest: arm the next snap.
            armed = true
        } else if mag > Self.analogLow && mag < Self.analogHigh {
            // Intermediate magnitude ⇒ a real analog stick exists. Never a clone.
            hasAnalogStick = true
        } else if mag >= Self.fullThreshold && armed {
            // Snapped center→full with nothing in between: a digital-d-pad snap.
            // Disarm until the stick returns to center so a held deflection
            // (many consecutive full samples) only counts once.
            fullSnaps += 1
            armed = false
            if fullSnaps >= Self.requiredFullSnaps {
                latched = true
                NSLog("[ControllerKeys] stickless d-pad clone detected (behavioral: \(fullSnaps) clean center→full snaps, no intermediate)")
            }
        }
    }
}
