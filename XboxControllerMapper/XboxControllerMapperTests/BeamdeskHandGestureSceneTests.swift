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

  func testMetaLeftSwipePhysicalMotionMirrorsBetweenHands() {
    let left = BeamdeskGesturePresentation(side: .left, gesture: .swipeLeft)
    let right = BeamdeskGesturePresentation(side: .right, gesture: .swipeLeft)

    XCTAssertLessThan(
      left.thumbSlideOffset.y, 0, "Left-hand left swipe moves away from its index tip")
    XCTAssertGreaterThan(
      right.thumbSlideOffset.y, 0, "Right-hand left swipe moves toward its index tip")
  }

  func testMetaRightSwipePhysicalMotionMirrorsBetweenHands() {
    let left = BeamdeskGesturePresentation(side: .left, gesture: .swipeRight)
    let right = BeamdeskGesturePresentation(side: .right, gesture: .swipeRight)

    XCTAssertGreaterThan(left.thumbSlideOffset.y, 0)
    XCTAssertLessThan(right.thumbSlideOffset.y, 0)
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
  }

  func testGestureTravelIsPronounced() {
    let horizontal = BeamdeskGesturePresentation(side: .left, gesture: .swipeLeft)
    let depth = BeamdeskGesturePresentation(side: .right, gesture: .swipeForward)

    XCTAssertGreaterThanOrEqual(abs(horizontal.thumbSlideOffset.y), 0.65)
    XCTAssertGreaterThanOrEqual(abs(depth.thumbSlideOffset.z), 0.50)
    XCTAssertGreaterThan(BeamdeskThumbArticulation.tap.mcpFlex, 0.70)
    XCTAssertGreaterThan(BeamdeskThumbArticulation.slide.ipFlex, 0.50)
  }
}
