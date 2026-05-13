import CoreGraphics
import Foundation

enum JoystickDirectionResolver {
    static func activeButtons(
        stick: CGPoint,
        side: JoystickSide,
        settings: JoystickSettings
    ) -> Set<ControllerButton> {
        let config = customConfig(side: side, settings: settings)
        return activeDirections(
            stick: stick,
            deadzone: config.deadzone,
            horizontalSliceSize: config.horizontalSliceSize,
            verticalSliceSize: config.verticalSliceSize,
            invertY: config.invertY
        ).map { ControllerButton.joystickDirectionButton(side: side, direction: $0) }
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

    private static func customConfig(side: JoystickSide, settings: JoystickSettings) -> (
        deadzone: Double,
        horizontalSliceSize: Double,
        verticalSliceSize: Double,
        invertY: Bool
    ) {
        switch side {
        case .left:
            return (
                deadzone: settings.mouseDeadzone,
                horizontalSliceSize: settings.leftStickCustomHorizontalSliceSize,
                verticalSliceSize: settings.leftStickCustomVerticalSliceSize,
                invertY: settings.invertMouseY
            )
        case .right:
            return (
                deadzone: settings.scrollDeadzone,
                horizontalSliceSize: settings.rightStickCustomHorizontalSliceSize,
                verticalSliceSize: settings.rightStickCustomVerticalSliceSize,
                invertY: settings.invertScrollY
            )
        }
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
