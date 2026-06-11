import Foundation
import CoreGraphics

// MARK: - Screenshot demo input
//
// Synthetic input for screenshot/recording mode so marketing captures show
// the minimap reacting to a controller "in use" instead of an idle pad.
// A static pose is applied for tab-walk screenshots (deterministic); the
// `--screenshot-animate` flag additionally runs a scripted input loop for
// GIF/video capture. Everything here touches only display state — the
// mapping engine receives its input from hardware events, which are
// disabled in screenshot mode.

extension ControllerService {
    /// Frozen "in use" pose: one face button held, the right trigger
    /// half-pulled, the left stick deflected, a finger resting on the
    /// touch surfaces.
    func applyScreenshotDemoPose() {
        activeButtons = [.a]
        displayLeftStick = CGPoint(x: 0.55, y: 0.35)
        displayRightTrigger = 0.65

        displayIsTouchpadTouching = true
        displayTouchpadPosition = CGPoint(x: -0.3, y: 0.25)
        displayIsSteamLeftTouchpadTouching = true
        displaySteamLeftTouchpadPosition = CGPoint(x: 0.2, y: 0.3)
    }

    /// Scripted input loop for recordings: sticks sweep, triggers breathe,
    /// face/d-pad buttons tap in sequence, a finger drifts on the pads.
    func startScreenshotDemoAnimation() {
        var t: Double = 0
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            t += 1.0 / 30.0
            self.screenshotDemoTick(t)
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The Konami code, tapped with natural press/release timing, then a
    /// beat of rest before looping: ↑ ↑ ↓ ↓ ← → ← → B A.
    private static let konamiCode: [ControllerButton] = [
        .dpadUp, .dpadUp, .dpadDown, .dpadDown,
        .dpadLeft, .dpadRight, .dpadLeft, .dpadRight,
        .b, .a
    ]

    private func screenshotDemoTick(_ t: Double) {
        // Left stick sweeps a slow circle; right stick wobbles gently.
        displayLeftStick = CGPoint(x: cos(t * 1.5) * 0.72, y: sin(t * 1.5) * 0.72)
        displayRightStick = CGPoint(x: sin(t * 0.9) * 0.30, y: cos(t * 1.1) * 0.22)

        // Triggers breathe in alternation.
        displayRightTrigger = Float(max(0, sin(t * 1.2))) * 0.9
        displayLeftTrigger = Float(max(0, sin(t * 1.2 + .pi))) * 0.9

        // Buttons enter the Konami code: quick taps, short gaps, then a
        // pause before the sequence repeats.
        let tapSlot = 0.38      // seconds per input
        let tapHold = 0.20      // press duration within a slot
        let restAfter = 1.2     // pause before looping
        let cycle = Double(Self.konamiCode.count) * tapSlot + restAfter
        let tc = t.truncatingRemainder(dividingBy: cycle)
        let slot = Int(tc / tapSlot)
        var pressed = Set<ControllerButton>()
        if slot < Self.konamiCode.count, tc.truncatingRemainder(dividingBy: tapSlot) < tapHold {
            pressed.insert(Self.konamiCode[slot])
        }
        if activeButtons != pressed {
            activeButtons = pressed
        }

        // Touch surfaces: discrete swipe gestures — finger lands, sweeps
        // across with easing, lifts, then lands somewhere else.
        let (touching, position) = Self.swipeState(at: t)
        displayIsTouchpadTouching = touching
        if touching { displayTouchpadPosition = position }

        let (lTouching, lPosition) = Self.swipeState(at: t + 0.55)
        displayIsSteamLeftTouchpadTouching = lTouching
        if lTouching { displaySteamLeftTouchpadPosition = lPosition }

        let (rTouching, rPosition) = Self.swipeState(at: t + 1.15)
        displayIsSteamRightTouchpadTouching = rTouching
        if rTouching { displaySteamRightTouchpadPosition = rPosition }
    }

    /// Cycle of four swipes. Each segment: 0.55 s of eased contact travel,
    /// then 0.35 s lifted before the next swipe begins.
    private static func swipeState(at t: Double) -> (touching: Bool, position: CGPoint) {
        let swipes: [(from: CGPoint, to: CGPoint)] = [
            (CGPoint(x: -0.65, y: -0.20), CGPoint(x: 0.60, y: 0.15)),
            (CGPoint(x: 0.55, y: 0.35), CGPoint(x: -0.50, y: -0.30)),
            (CGPoint(x: -0.25, y: 0.50), CGPoint(x: 0.30, y: -0.45)),
            (CGPoint(x: 0.60, y: -0.10), CGPoint(x: -0.60, y: 0.25)),
        ]
        let segment = 0.9
        let contact = 0.55
        let cycle = segment * Double(swipes.count)
        let tc = t.truncatingRemainder(dividingBy: cycle)
        let index = Int(tc / segment)
        let local = tc - Double(index) * segment

        guard local < contact else { return (false, .zero) }

        let progress = local / contact
        let eased = progress * progress * (3 - 2 * progress) // smoothstep
        let swipe = swipes[index]
        return (true, CGPoint(
            x: swipe.from.x + (swipe.to.x - swipe.from.x) * eased,
            y: swipe.from.y + (swipe.to.y - swipe.from.y) * eased
        ))
    }
}
