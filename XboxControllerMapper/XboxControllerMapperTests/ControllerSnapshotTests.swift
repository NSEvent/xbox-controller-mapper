import XCTest
import CoreGraphics
@testable import ControllerKeys

@MainActor
final class ControllerSnapshotTests: XCTestCase {
    private var controllerService: ControllerService!

    override func setUp() {
        super.setUp()
        controllerService = ControllerService(enableHardwareMonitoring: false)
    }

    override func tearDown() {
        controllerService.cleanup()
        controllerService = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultSnapshotHasZeroValues() {
        let snap = ControllerService.ControllerSnapshot()
        XCTAssertEqual(snap.leftStick, .zero)
        XCTAssertEqual(snap.rightStick, .zero)
        XCTAssertEqual(snap.leftTrigger, 0)
        XCTAssertEqual(snap.rightTrigger, 0)
        XCTAssertFalse(snap.isDualSense)
    }

    // MARK: - Value Correctness

    func testSnapshotCapturesStorageValues() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.5, y: -0.3)
        controllerService.storage.rightStick = CGPoint(x: -0.7, y: 0.9)
        controllerService.storage.leftTrigger = 0.6
        controllerService.storage.rightTrigger = 0.85
        controllerService.storage.isDualSense = true
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        XCTAssertEqual(snap.leftStick.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(snap.leftStick.y, -0.3, accuracy: 0.001)
        XCTAssertEqual(snap.rightStick.x, -0.7, accuracy: 0.001)
        XCTAssertEqual(snap.rightStick.y, 0.9, accuracy: 0.001)
        XCTAssertEqual(snap.leftTrigger, 0.6, accuracy: 0.001)
        XCTAssertEqual(snap.rightTrigger, 0.85, accuracy: 0.001)
        XCTAssertTrue(snap.isDualSense)
    }

    func testSnapshotCapturesDualSenseFalse() {
        controllerService.storage.lock.lock()
        controllerService.storage.isDualSense = false
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()
        XCTAssertFalse(snap.isDualSense)
    }

    // MARK: - Atomicity (Conceptual)

    func testSnapshotValuesAreConsistent() {
        // Set both sticks together, verify snapshot captures both from the same lock acquisition
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 1.0, y: 1.0)
        controllerService.storage.rightStick = CGPoint(x: -1.0, y: -1.0)
        controllerService.storage.leftTrigger = 1.0
        controllerService.storage.rightTrigger = 1.0
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        // All values should be from the same state — either all set or all zero
        XCTAssertEqual(snap.leftStick, CGPoint(x: 1.0, y: 1.0))
        XCTAssertEqual(snap.rightStick, CGPoint(x: -1.0, y: -1.0))
        XCTAssertEqual(snap.leftTrigger, 1.0)
        XCTAssertEqual(snap.rightTrigger, 1.0)
    }

    // MARK: - Value Type Semantics

    func testSnapshotIsValueType() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.5, y: 0.5)
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()
        var copy = snap

        // Mutating the copy should not affect the original
        copy.leftStick = CGPoint(x: 0.9, y: 0.9)

        XCTAssertEqual(snap.leftStick.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(copy.leftStick.x, 0.9, accuracy: 0.001)
    }

    // MARK: - Backward Compatibility (Individual Accessors Still Work)

    func testIndividualAccessorsStillWork() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.3, y: -0.4)
        controllerService.storage.rightStick = CGPoint(x: -0.6, y: 0.7)
        controllerService.storage.leftTrigger = 0.45
        controllerService.storage.rightTrigger = 0.55
        controllerService.storage.isDualSense = true
        controllerService.storage.lock.unlock()

        // Verify individual threadSafe accessors still return correct values
        XCTAssertEqual(controllerService.threadSafeLeftStick.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeLeftStick.y, -0.4, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightStick.x, -0.6, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightStick.y, 0.7, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeLeftTrigger, 0.45, accuracy: 0.001)
        XCTAssertEqual(controllerService.threadSafeRightTrigger, 0.55, accuracy: 0.001)
        XCTAssertTrue(controllerService.threadSafeIsDualSense)
    }

    func testSnapshotAndIndividualAccessorsAgree() {
        controllerService.storage.lock.lock()
        controllerService.storage.leftStick = CGPoint(x: 0.12, y: 0.34)
        controllerService.storage.rightStick = CGPoint(x: 0.56, y: 0.78)
        controllerService.storage.leftTrigger = 0.9
        controllerService.storage.rightTrigger = 0.1
        controllerService.storage.isDualSense = false
        controllerService.storage.lock.unlock()

        let snap = controllerService.snapshot()

        XCTAssertEqual(snap.leftStick, controllerService.threadSafeLeftStick)
        XCTAssertEqual(snap.rightStick, controllerService.threadSafeRightStick)
        XCTAssertEqual(snap.leftTrigger, controllerService.threadSafeLeftTrigger)
        XCTAssertEqual(snap.rightTrigger, controllerService.threadSafeRightTrigger)
        XCTAssertEqual(snap.isDualSense, controllerService.threadSafeIsDualSense)
    }
}
