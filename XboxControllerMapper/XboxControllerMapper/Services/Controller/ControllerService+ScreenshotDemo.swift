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

    private func screenshotDemoTick(_ t: Double) {
        // Left stick sweeps a slow circle; right stick wobbles gently.
        displayLeftStick = CGPoint(x: cos(t * 1.5) * 0.72, y: sin(t * 1.5) * 0.72)
        displayRightStick = CGPoint(x: sin(t * 0.9) * 0.30, y: cos(t * 1.1) * 0.22)

        // Triggers breathe in alternation.
        displayRightTrigger = Float(max(0, sin(t * 1.2))) * 0.9
        displayLeftTrigger = Float(max(0, sin(t * 1.2 + .pi))) * 0.9

        // Face buttons tap in sequence; d-pad taps on a slower, offset cadence.
        var pressed = Set<ControllerButton>()
        let faceSlot = Int(t / 0.8) % 4
        if t.truncatingRemainder(dividingBy: 0.8) < 0.4 {
            pressed.insert([ControllerButton.a, .b, .y, .x][faceSlot])
        }
        let dpadSlot = Int((t + 0.4) / 1.3) % 4
        if (t + 0.4).truncatingRemainder(dividingBy: 1.3) < 0.55 {
            pressed.insert([ControllerButton.dpadUp, .dpadRight, .dpadDown, .dpadLeft][dpadSlot])
        }
        if activeButtons != pressed {
            activeButtons = pressed
        }

        // A finger drifting on the touch surfaces.
        displayIsTouchpadTouching = true
        displayTouchpadPosition = CGPoint(x: sin(t * 0.8) * 0.55, y: cos(t * 0.6) * 0.4)
        displayIsSteamLeftTouchpadTouching = true
        displaySteamLeftTouchpadPosition = CGPoint(x: sin(t * 0.7) * 0.5, y: cos(t * 0.9) * 0.45)
        displayIsSteamRightTouchpadTouching = true
        displaySteamRightTouchpadPosition = CGPoint(x: cos(t * 0.8) * 0.5, y: sin(t * 0.65) * 0.45)
    }
}
