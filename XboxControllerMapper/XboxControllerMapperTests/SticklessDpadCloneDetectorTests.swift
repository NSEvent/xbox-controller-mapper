import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Behavioral detector for stickless d-pad clones (8BitDo Zero 2 impersonating a
/// Pro Controller in Switch mode / a DualShock 4 in Mac mode). The core rule:
/// a clone's "stick" snaps center→full with no intermediate magnitudes, whereas
/// a real analog stick always sweeps through intermediate values.
final class SticklessDpadCloneDetectorTests: XCTestCase {

    func testDefaultsToNotAClone() {
        let d = SticklessDpadCloneDetector()
        XCTAssertFalse(d.isSticklessClone)
    }

    func testCenterThenFullDeflectionLatchesClone() {
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)                       // at rest
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))       // d-pad up: snapped to full
        XCTAssertTrue(d.isSticklessClone)
    }

    func testFullDiagonalAlsoLatches() {
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 1.0, y: 1.0))     // diagonal d-pad (mag ~1.41)
        XCTAssertTrue(d.isSticklessClone)
    }

    func testIntermediateValueRulesOutClonePermanently() {
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 0.45))      // a real analog stick mid-push
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))       // then full — but analog already proven
        XCTAssertFalse(d.isSticklessClone)
    }

    func testFullWithoutSeenCenterDoesNotLatch() {
        // A real stick held deflected as the controller connects: first sample
        // is full with no prior center — must not be mistaken for a clone.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // already full at first sample
        XCTAssertFalse(d.isSticklessClone)
    }

    func testCenterThenFullStillLatchesAfterHeldStart() {
        // Same held-at-connect device, but once it returns to center and snaps
        // out again with no intermediate, it's a clone after all.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // full first (ignored — no center yet)
        XCTAssertFalse(d.isSticklessClone)
        d.noteLeftStick(.zero)                       // returns to center
        d.noteLeftStick(CGPoint(x: -1.0, y: 0))      // snaps to full again
        XCTAssertTrue(d.isSticklessClone)
    }

    func testRestingDriftIsNotTreatedAsAnalog() {
        // Small resting drift (below the analog band) must not flip the
        // has-analog-stick guard, or a clone would never be detected.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 0.03, y: -0.02))  // drift ~ center
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))
        XCTAssertTrue(d.isSticklessClone)
    }

    func testResetClearsLatch() {
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))
        XCTAssertTrue(d.isSticklessClone)
        d.reset()
        XCTAssertFalse(d.isSticklessClone)
    }
}
