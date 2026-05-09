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
            settings: input.settings,
            now: input.now,
            hasMotion: input.hasMotion
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
            engine.updateScrollDoubleTapState(rawStick: input.stick, settings: input.settings, now: input.now)
        }

        let deadzone = input.side == .right ? input.settings.scrollDeadzone : input.settings.mouseDeadzone
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

        engine.processScrolling(smoothed, rawStick: input.stick, settings: input.settings, now: input.now)
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
        // (left stick) vs. scroll (right stick) primary modes.
        if input.side == .left {
            deadzone = input.settings.mouseDeadzone
            invertY = input.settings.invertMouseY
        } else {
            deadzone = input.settings.scrollDeadzone
            invertY = input.settings.invertScrollY
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
