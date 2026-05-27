import CoreGraphics

struct TouchpadGesture: Sendable, Equatable {
    let centerDelta: CGPoint
    let distanceDelta: Double
    let isPrimaryTouching: Bool
    let isSecondaryTouching: Bool
    let primaryDelta: CGPoint
    let secondaryDelta: CGPoint

    init(
        centerDelta: CGPoint,
        distanceDelta: Double,
        isPrimaryTouching: Bool,
        isSecondaryTouching: Bool,
        primaryDelta: CGPoint = .zero,
        secondaryDelta: CGPoint = .zero
    ) {
        self.centerDelta = centerDelta
        self.distanceDelta = distanceDelta
        self.isPrimaryTouching = isPrimaryTouching
        self.isSecondaryTouching = isSecondaryTouching
        self.primaryDelta = primaryDelta
        self.secondaryDelta = secondaryDelta
    }
}
