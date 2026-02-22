import CoreGraphics

struct TouchpadGesture: Sendable, Equatable {
    let centerDelta: CGPoint
    let distanceDelta: Double
    let isPrimaryTouching: Bool
    let isSecondaryTouching: Bool
}
