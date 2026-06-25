import Foundation
import CoreGraphics

// MARK: - NoOp

struct NoOpStickStrategy: JoystickStickStrategy {
    static let shared = NoOpStickStrategy()

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        // Stick is unmapped — nothing to do.
    }
}

// MARK: - Mouse

struct MouseStickStrategy: JoystickStickStrategy {
    static let shared = MouseStickStrategy()

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        engine.processMouseMovement(
            input.stick,
            tuning: input.tuning,
            settings: input.settings,
            now: input.now
        )
    }
}

// MARK: - Scroll

struct ScrollStickStrategy: JoystickStickStrategy {
    static let shared = ScrollStickStrategy()

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        let state = engine.state
        let smoothed: CGPoint

        // Right-stick scroll has a double-tap-to-boost feature; left-stick
        // does not. Match existing behavior exactly.
        if input.side == .right {
            engine.updateScrollDoubleTapState(rawStick: input.stick, tuning: input.tuning, now: input.now)
        }

        let deadzone = input.side == .right ? input.tuning.scrollDeadzone : input.tuning.mouseDeadzone
        let magnitudeSquared = input.stick.x * input.stick.x + input.stick.y * input.stick.y
        let deadzoneSquared = deadzone * deadzone

        if magnitudeSquared <= deadzoneSquared {
            smoothed = .zero
        } else {
            let previous = input.side == .left ? state.smoothedLeftStick : state.smoothedRightStick
            smoothed = engine.smoothStick(input.stick, previous: previous, dt: input.dt)
        }

        if input.side == .left {
            state.smoothedLeftStick = smoothed
        } else {
            state.smoothedRightStick = smoothed
        }

        engine.processScrolling(smoothed, rawStick: input.stick, tuning: input.tuning, settings: input.settings, now: input.now)
    }
}

// MARK: - Direction Keys (WASD / Arrows)

struct DirectionKeyStickStrategy: JoystickStickStrategy {
    static let wasd = DirectionKeyStickStrategy(mode: .wasdKeys)
    static let arrows = DirectionKeyStickStrategy(mode: .arrowKeys)

    let mode: StickMode

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        let state = engine.state
        let deadzone: Double
        let invertY: Bool

        // Left and right sticks read different deadzone/invert fields, matching
        // the long-standing convention that those settings cluster with mouse
        // (left stick) vs. scroll (right stick) primary modes — now sourced from
        // each stick's own tuning.
        if input.side == .left {
            deadzone = input.tuning.mouseDeadzone
            invertY = input.tuning.invertMouseY
        } else {
            deadzone = input.tuning.scrollDeadzone
            invertY = input.tuning.invertScrollY
        }

        if input.side == .left {
            engine.processDirectionKeys(
                stick: input.stick,
                deadzone: deadzone,
                mode: mode,
                heldKeys: &state.leftStickHeldKeys,
                invertY: invertY
            )
        } else {
            engine.processDirectionKeys(
                stick: input.stick,
                deadzone: deadzone,
                mode: mode,
                heldKeys: &state.rightStickHeldKeys,
                invertY: invertY
            )
        }
    }
}

// MARK: - Custom Direction Buttons

struct CustomDirectionStickStrategy: JoystickStickStrategy {
    static let shared = CustomDirectionStickStrategy()

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        let state = engine.state
        if input.side == .left {
            engine.processCustomDirectionButtons(
                stick: input.stick,
                side: input.side,
                tuning: input.tuning,
                heldButtons: &state.leftStickHeldDirectionButtons
            )
        } else {
            engine.processCustomDirectionButtons(
                stick: input.stick,
                side: input.side,
                tuning: input.tuning,
                heldButtons: &state.rightStickHeldDirectionButtons
            )
        }
    }
}

// MARK: - D-Pad Buttons

/// Drives the controller's D-pad buttons (.dpadUp/.dpadDown/.dpadLeft/
/// .dpadRight) from stick deflection. Lets a stickless pad's d-pad (which
/// arrives as the left stick) act as a real d-pad. Reuses the held-direction
/// set so release-on-disable is already handled.
struct DPadStickStrategy: JoystickStickStrategy {
    static let shared = DPadStickStrategy()

    func process(_ input: JoystickStickInput, on engine: MappingEngine) {
        let state = engine.state
        if input.side == .left {
            engine.processDPadDirectionButtons(
                stick: input.stick,
                side: input.side,
                tuning: input.tuning,
                heldButtons: &state.leftStickHeldDirectionButtons
            )
        } else {
            engine.processDPadDirectionButtons(
                stick: input.stick,
                side: input.side,
                tuning: input.tuning,
                heldButtons: &state.rightStickHeldDirectionButtons
            )
        }
    }
}
