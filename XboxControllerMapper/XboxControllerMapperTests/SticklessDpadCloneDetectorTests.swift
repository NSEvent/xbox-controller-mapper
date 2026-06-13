import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Behavioral detector for stickless d-pad clones (8BitDo Zero 2 impersonating a
/// Pro Controller in Switch mode / a DualShock 4 in Mac mode). The core rule:
/// a clone's "stick" snaps center→full with no intermediate magnitudes, whereas
/// a real analog stick always sweeps through intermediate values. Latching
/// requires TWO clean center→full snaps so one improbably-fast flick of a real
/// stick can't false-latch.
final class SticklessDpadCloneDetectorTests: XCTestCase {

    /// Drive `count` clean center→full snaps (the clone signature).
    private func snap(_ d: SticklessDpadCloneDetector, _ point: CGPoint, times count: Int) {
        for _ in 0..<count {
            d.noteLeftStick(.zero)        // at rest (arms the next snap)
            d.noteLeftStick(point)        // jump straight to full, no intermediate
        }
    }

    func testDefaultsToNotAClone() {
        let d = SticklessDpadCloneDetector()
        XCTAssertFalse(d.isSticklessClone)
    }

    func testSingleSnapDoesNotLatch() {
        // One center→full snap is not enough — confirmation is required.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))
        XCTAssertFalse(d.isSticklessClone)
    }

    func testTwoCenterFullSnapsLatchClone() {
        let d = SticklessDpadCloneDetector()
        snap(d, CGPoint(x: 0, y: 1.0), times: 2)     // d-pad up, twice
        XCTAssertTrue(d.isSticklessClone)
    }

    func testHeldFullDeflectionCountsAsOneSnap() {
        // Many consecutive full samples from holding a direction must count once
        // (the stick must return to center to arm the next snap), so a single
        // held press does not latch.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        for _ in 0..<10 { d.noteLeftStick(CGPoint(x: 0, y: 1.0)) }
        XCTAssertFalse(d.isSticklessClone)
    }

    func testFullDiagonalSnapsLatch() {
        let d = SticklessDpadCloneDetector()
        snap(d, CGPoint(x: 1.0, y: 1.0), times: 2)   // diagonal d-pad (mag ~1.41)
        XCTAssertTrue(d.isSticklessClone)
    }

    func testIntermediateValueRulesOutClonePermanently() {
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 0.45))      // a real analog stick mid-push
        snap(d, CGPoint(x: 0, y: 1.0), times: 2)     // then full snaps — but analog already proven
        XCTAssertFalse(d.isSticklessClone)
    }

    func testFastFlickThenAnalogReleaseDoesNotLatch() {
        // A genuine analog stick whose first push happens to skip the analog
        // band in one sample (snap #1) but then springs back through an
        // intermediate magnitude on release must be ruled out — its spring-back
        // proves it is analog before a second snap can latch it.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))       // fast flick to full (snap #1)
        d.noteLeftStick(CGPoint(x: 0, y: 0.5))       // spring-back through the band
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))       // pushed full again
        XCTAssertFalse(d.isSticklessClone)
    }

    func testFullWithoutSeenCenterDoesNotLatch() {
        // A real stick held deflected as the controller connects: first sample
        // is full with no prior center — must not be mistaken for a clone.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // already full at first sample
        XCTAssertFalse(d.isSticklessClone)
    }

    func testSnapsLatchAfterHeldStart() {
        // Held-at-connect device: the leading full sample is ignored (no center
        // yet), then two clean center→full snaps latch it.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // full first (ignored — no center yet)
        XCTAssertFalse(d.isSticklessClone)
        snap(d, CGPoint(x: -1.0, y: 0), times: 2)
        XCTAssertTrue(d.isSticklessClone)
    }

    func testRestingDriftIsNotTreatedAsAnalog() {
        // Small resting drift (below the analog band) must not flip the
        // has-analog-stick guard, or a clone would never be detected.
        let d = SticklessDpadCloneDetector()
        d.noteLeftStick(CGPoint(x: 0.03, y: -0.02))  // drift ~ center (arms)
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // snap #1
        d.noteLeftStick(CGPoint(x: -0.02, y: 0.03))  // drift ~ center (re-arms)
        d.noteLeftStick(CGPoint(x: 1.0, y: 0))       // snap #2
        XCTAssertTrue(d.isSticklessClone)
    }

    func testResetClearsLatch() {
        let d = SticklessDpadCloneDetector()
        snap(d, CGPoint(x: 0, y: 1.0), times: 2)
        XCTAssertTrue(d.isSticklessClone)
        d.reset()
        XCTAssertFalse(d.isSticklessClone)
        // And the snap counter is cleared — one post-reset snap must not latch.
        d.noteLeftStick(.zero)
        d.noteLeftStick(CGPoint(x: 0, y: 1.0))
        XCTAssertFalse(d.isSticklessClone)
    }
}
