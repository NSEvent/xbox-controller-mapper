import CoreGraphics

struct TouchpadGesture: Sendable {
    let centerDelta: CGPoint
    let distanceDelta: Double
    let isPrimaryTouching: Bool
    let isSecondaryTouching: Bool
}
