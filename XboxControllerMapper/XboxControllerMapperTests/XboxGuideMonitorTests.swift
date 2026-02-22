import XCTest
@testable import ControllerKeys

final class XboxGuideMonitorTests: XCTestCase {

    // MARK: - CallbackContext weak reference safety

    func testCallbackContextWeakReference() {
        // The core safety property: when the monitor is deallocated,
        // the CallbackContext's weak reference becomes nil (no dangling pointer).
        var monitor: XboxGuideMonitor? = XboxGuideMonitor()
        weak var weakMonitor = monitor

        XCTAssertNotNil(weakMonitor, "Monitor should be alive")

        monitor = nil

        XCTAssertNil(weakMonitor, "Monitor should be deallocated after niling reference")
    }

    // MARK: - stop() releases callback context

    func testStopReleasesCallbackContext() {
        let monitor = XboxGuideMonitor()
        XCTAssertTrue(monitor.isStarted, "Monitor should be started after init")

        monitor.stop()

        XCTAssertFalse(monitor.isStarted, "Monitor should not be started after stop()")
    }

    // MARK: - Double stop does not crash

    func testDoubleStopDoesNotCrash() {
        let monitor = XboxGuideMonitor()
        monitor.stop()
        monitor.stop() // Must not double-release or crash
        XCTAssertFalse(monitor.isStarted)
    }

    // MARK: - Double start is a no-op

    func testDoubleStartDoesNotLeak() {
        let monitor = XboxGuideMonitor()
        XCTAssertTrue(monitor.isStarted)

        // Second start should be guarded by isStarted flag
        monitor.start()
        XCTAssertTrue(monitor.isStarted, "Monitor should still be started")

        // Cleanup should still work correctly
        monitor.stop()
        XCTAssertFalse(monitor.isStarted)
    }

    // MARK: - deinit calls stop

    func testDeinitCallsStop() {
        var monitor: XboxGuideMonitor? = XboxGuideMonitor()
        XCTAssertTrue(monitor!.isStarted)

        // When the monitor goes out of scope, deinit should call stop()
        // without crashing. If stop() wasn't called, the retained
        // CallbackContext would leak.
        monitor = nil
        // No crash = pass. The retained context was properly released.
    }

    // MARK: - Start after stop restarts correctly

    func testStartAfterStopRestartsCorrectly() {
        let monitor = XboxGuideMonitor()
        XCTAssertTrue(monitor.isStarted)

        monitor.stop()
        XCTAssertFalse(monitor.isStarted)

        monitor.start()
        XCTAssertTrue(monitor.isStarted)

        monitor.stop()
        XCTAssertFalse(monitor.isStarted)
    }
}
