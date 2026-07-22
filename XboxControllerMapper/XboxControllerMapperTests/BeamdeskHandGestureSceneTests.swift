import SceneKit
import XCTest

@testable import ControllerKeys

@MainActor
final class BeamdeskHandGestureSceneTests: XCTestCase {
  func testDirectXCTestProcessIsRecognizedAsTestRuntime() {
    XCTAssertTrue(AppRuntime.isRunningTests)
  }

  func testEveryBeamdeskButtonResolvesToAVisualization() {
    for button in ControllerButton.beamdeskHandButtons {
      XCTAssertNotNil(
        BeamdeskGesturePresentation(button: button), "Missing visualization for \(button)")
    }
  }

  func testPOVHandsMirrorPalmFacingCoordinates() {
    XCTAssertEqual(BeamdeskHandSide.left.inwardSign, 1)
    XCTAssertEqual(BeamdeskHandSide.right.inwardSign, -1)
    XCTAssertEqual(BeamdeskHandSide.left.profileSign, -1)
    XCTAssertEqual(BeamdeskHandSide.right.profileSign, 1)
  }

  func testSwipeLeftMovesLeftInScreenSpaceForBothHands() {
    let left = BeamdeskGesturePresentation(side: .left, gesture: .swipeLeft)
    let right = BeamdeskGesturePresentation(side: .right, gesture: .swipeLeft)

    XCTAssertLessThan(left.thumbSlideOffset.x, 0)
    XCTAssertLessThan(right.thumbSlideOffset.x, 0)
    XCTAssertEqual(left.thumbSlideOffset.y, 0)
    XCTAssertEqual(right.thumbSlideOffset.y, 0)
  }

  func testSwipeRightMovesRightInScreenSpaceForBothHands() {
    let left = BeamdeskGesturePresentation(side: .left, gesture: .swipeRight)
    let right = BeamdeskGesturePresentation(side: .right, gesture: .swipeRight)

    XCTAssertGreaterThan(left.thumbSlideOffset.x, 0)
    XCTAssertGreaterThan(right.thumbSlideOffset.x, 0)
    XCTAssertEqual(left.thumbSlideOffset.y, 0)
    XCTAssertEqual(right.thumbSlideOffset.y, 0)
  }

  func testThumbTapDoesNotSlideAfterContact() {
    for side in [BeamdeskHandSide.left, .right] {
      let offset = BeamdeskGesturePresentation(side: side, gesture: .thumbTap).thumbSlideOffset
      XCTAssertEqual(offset.x, SCNVector3Zero.x)
      XCTAssertEqual(offset.y, SCNVector3Zero.y)
      XCTAssertEqual(offset.z, SCNVector3Zero.z)
    }
  }

  func testThumbUsesAllThreeAnatomicalJoints() {
    XCTAssertNotEqual(BeamdeskThumbArticulation.rest.cmcFlex, BeamdeskThumbArticulation.tap.cmcFlex)
    XCTAssertNotEqual(BeamdeskThumbArticulation.rest.mcpFlex, BeamdeskThumbArticulation.tap.mcpFlex)
    XCTAssertNotEqual(BeamdeskThumbArticulation.rest.ipFlex, BeamdeskThumbArticulation.tap.ipFlex)
  }

  func testTapFlexesFurtherThanSwipe() {
    XCTAssertGreaterThan(
      BeamdeskThumbArticulation.tap.cmcFlex, BeamdeskThumbArticulation.slide.cmcFlex)
    XCTAssertGreaterThan(
      BeamdeskThumbArticulation.tap.mcpFlex, BeamdeskThumbArticulation.slide.mcpFlex)
    XCTAssertGreaterThan(
      BeamdeskThumbArticulation.tap.ipFlex, BeamdeskThumbArticulation.slide.ipFlex)
  }

  func testPresentationSelectsGestureSpecificArticulation() {
    for side in [BeamdeskHandSide.left, .right] {
      XCTAssertEqual(
        BeamdeskGesturePresentation(side: side, gesture: .thumbTap).finalArticulation,
        .tap
      )
      XCTAssertEqual(
        BeamdeskGesturePresentation(side: side, gesture: .swipeForward).finalArticulation,
        .slide
      )
    }

    XCTAssertEqual(
	BeamdeskGesturePresentation(side: .left, gesture: .swipeLeft).finalArticulation,
	.outwardLeft
    )
    XCTAssertEqual(
	BeamdeskGesturePresentation(side: .right, gesture: .swipeLeft).finalArticulation,
	.slideLeft
    )
    XCTAssertEqual(
	BeamdeskGesturePresentation(side: .left, gesture: .swipeRight).finalArticulation,
	.slideRight
    )
    XCTAssertEqual(
	BeamdeskGesturePresentation(side: .right, gesture: .swipeRight).finalArticulation,
	.outwardRight
    )
  }

  func testOutwardSwipesUseShorterTravelAndGentlerSweepThanInwardSwipes() {
    let leftOutward = BeamdeskGesturePresentation(side: .left, gesture: .swipeLeft)
    let leftInward = BeamdeskGesturePresentation(side: .left, gesture: .swipeRight)
    let rightOutward = BeamdeskGesturePresentation(side: .right, gesture: .swipeRight)
    let rightInward = BeamdeskGesturePresentation(side: .right, gesture: .swipeLeft)

    XCTAssertLessThan(abs(leftOutward.thumbSlideOffset.x), abs(leftInward.thumbSlideOffset.x))
    XCTAssertLessThan(
      abs(leftOutward.finalArticulation.lateralSweep),
      abs(leftInward.finalArticulation.lateralSweep)
    )
    XCTAssertEqual(abs(leftOutward.thumbSlideOffset.x), abs(rightOutward.thumbSlideOffset.x))
    XCTAssertEqual(
      abs(leftOutward.finalArticulation.lateralSweep),
      abs(rightOutward.finalArticulation.lateralSweep)
    )
    XCTAssertLessThanOrEqual(abs(leftOutward.finalArticulation.lateralSweep), 0.35)
    XCTAssertEqual(abs(leftInward.thumbSlideOffset.x), abs(rightInward.thumbSlideOffset.x))
  }

  func testGestureTravelIsPronounced() {
    let horizontal = BeamdeskGesturePresentation(side: .left, gesture: .swipeRight)
    let depth = BeamdeskGesturePresentation(side: .right, gesture: .swipeForward)

    XCTAssertGreaterThanOrEqual(abs(horizontal.thumbSlideOffset.x), 0.55)
    XCTAssertGreaterThanOrEqual(abs(depth.thumbSlideOffset.z), 0.50)
    XCTAssertGreaterThanOrEqual(abs(horizontal.finalArticulation.lateralSweep), 0.70)
    XCTAssertGreaterThan(BeamdeskThumbArticulation.tap.mcpFlex, 0.70)
    XCTAssertGreaterThan(BeamdeskThumbArticulation.slide.ipFlex, 0.50)
  }
}
