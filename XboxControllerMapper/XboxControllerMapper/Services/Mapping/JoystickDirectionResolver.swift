import CoreGraphics
import Foundation

enum JoystickDirectionResolver {
    static func activeButtons(
        stick: CGPoint,
        side: JoystickSide,
		tuning: StickTuning,
		previousDirection: JoystickDirection? = nil
    ) -> Set<ControllerButton> {
        let config = customConfig(side: side, tuning: tuning)
		let directions: [JoystickDirection]
		switch tuning.customDirectionLayout {
		case .fourWay:
			directions = activeDirections(
				stick: stick,
				deadzone: config.deadzone,
				horizontalSliceSize: config.horizontalSliceSize,
				verticalSliceSize: config.verticalSliceSize,
				invertY: config.invertY
			)
		case .eightWay:
			directions = activeEightWayDirections(
				stick: stick,
				deadzone: config.deadzone,
				invertY: config.invertY,
				previousDirection: previousDirection
			)
		}
		return directions.map { ControllerButton.joystickDirectionButton(side: side, direction: $0) }
            .asSet()
    }

    static func activeDirections(
        stick: CGPoint,
        deadzone: Double,
        horizontalSliceSize: Double,
        verticalSliceSize: Double,
        invertY: Bool
    ) -> [JoystickDirection] {
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        guard magnitudeSquared > deadzone * deadzone else { return [] }

        let x = Double(stick.x)
        let y = Double(stick.y) * (invertY ? -1.0 : 1.0)

        guard let direction = activeCardinalDirection(
            x: x,
            y: y,
            horizontalSliceSize: horizontalSliceSize,
            verticalSliceSize: verticalSliceSize
        ) else {
            return []
        }
        return [direction]
    }

	/// Resolves one of eight equal 45° sectors. Once a sector is active it retains
	/// the stick for 5° past the ordinary boundary, preventing noisy samples around
	/// a boundary from rapidly firing adjacent actions.
	static func activeEightWayDirections(
		stick: CGPoint,
		deadzone: Double,
		invertY: Bool,
		previousDirection: JoystickDirection? = nil
	) -> [JoystickDirection] {
		let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
		guard magnitudeSquared > deadzone * deadzone else { return [] }

		let x = Double(stick.x)
		let y = Double(stick.y) * (invertY ? -1.0 : 1.0)
		let angle = normalizedDegrees(atan2(y, x) * 180.0 / .pi)

		if let previousDirection,
		   angularDistance(angle, centerDegrees(for: previousDirection)) <= 27.5 {
			return [previousDirection]
		}

		let direction = StickDirectionLayout.eightWay.directions.min {
			angularDistance(angle, centerDegrees(for: $0)) <
				angularDistance(angle, centerDegrees(for: $1))
		}
		return direction.map { [$0] } ?? []
	}

    static func activeAxisButtons(
        stick: CGPoint,
        side: JoystickSide,
        deadzone: Double,
        invertY: Bool,
        threshold: Double = 0.4
    ) -> Set<ControllerButton> {
        activeAxisDirections(
            stick: stick,
            deadzone: deadzone,
            invertY: invertY,
            threshold: threshold
        ).map { ControllerButton.joystickDirectionButton(side: side, direction: $0) }
            .asSet()
    }

	static func activeAxisButtons(
		stick: CGPoint,
		side: JoystickSide,
		tuning: StickTuning,
		threshold: Double = 0.4
	) -> Set<ControllerButton> {
		let config = customConfig(side: side, tuning: tuning)
		return activeAxisButtons(
			stick: stick,
			side: side,
			deadzone: config.deadzone,
			invertY: config.invertY,
			threshold: threshold
		)
	}

    static func activeAxisDirections(
        stick: CGPoint,
        deadzone: Double,
        invertY: Bool,
        threshold: Double = 0.4
    ) -> [JoystickDirection] {
        let magnitudeSquared = stick.x * stick.x + stick.y * stick.y
        guard magnitudeSquared > deadzone * deadzone else { return [] }

        let stickX = Double(stick.x)
        let stickY = Double(stick.y) * (invertY ? -1.0 : 1.0)
        var directions: [JoystickDirection] = []

        if stickY > threshold {
            directions.append(.up)
        } else if stickY < -threshold {
            directions.append(.down)
        }

        if stickX > threshold {
            directions.append(.right)
        } else if stickX < -threshold {
            directions.append(.left)
        }

        return directions
    }

    private static func customConfig(side: JoystickSide, tuning: StickTuning) -> (
        deadzone: Double,
        horizontalSliceSize: Double,
        verticalSliceSize: Double,
        invertY: Bool
    ) {
        // Custom-direction invert still tracks the stick's mouse (left) vs. scroll
        // (right) invert toggle, matching the custom-direction panel's binding.
        return (
            deadzone: tuning.customDeadzone,
            horizontalSliceSize: tuning.customHorizontalSliceSize,
            verticalSliceSize: tuning.customVerticalSliceSize,
            invertY: side == .left ? tuning.invertMouseY : tuning.invertScrollY
        )
    }

    private static func activeCardinalDirection(
        x: Double,
        y: Double,
        horizontalSliceSize: Double,
        verticalSliceSize: Double
    ) -> JoystickDirection? {
        let angle = normalizedDegrees(atan2(y, x) * 180.0 / .pi)
        let candidates: [(direction: JoystickDirection, degrees: Double)] = [
            (.right, 0),
            (.up, 90),
            (.left, 180),
            (.down, 270)
        ]

        return candidates
            .filter { candidate in
                angularDistance(angle, candidate.degrees) <= halfWidthDegrees(
                    for: candidate.direction,
                    horizontalSliceSize: horizontalSliceSize,
                    verticalSliceSize: verticalSliceSize
                )
            }
            .min {
                angularDistance(angle, $0.degrees) < angularDistance(angle, $1.degrees)
            }?
            .direction
    }

	private static func centerDegrees(for direction: JoystickDirection) -> Double {
		switch direction {
		case .right: return 0
		case .upRight: return 45
		case .up: return 90
		case .upLeft: return 135
		case .left: return 180
		case .downLeft: return 225
		case .down: return 270
		case .downRight: return 315
		}
	}

    private static func halfWidthDegrees(
        for direction: JoystickDirection,
        horizontalSliceSize: Double,
        verticalSliceSize: Double
    ) -> Double {
        let size: Double
        switch direction {
        case .left, .right:
            size = horizontalSliceSize
        case .up, .down:
            size = verticalSliceSize
        case .upLeft, .upRight, .downLeft, .downRight:
            size = 0
        }
        return max(0, min(1, size)) * 45.0
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private static func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }
}

private extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        Set(self)
    }
}
