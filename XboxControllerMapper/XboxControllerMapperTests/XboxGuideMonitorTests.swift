import XCTest
import IOKit.hid
@testable import ControllerKeys

final class XboxGuideMonitorTests: XCTestCase {

	// MARK: - Elite 2 guide routing

	func testClassicBluetoothEliteRoutesGuideFromConsumerACHomeOnly() {
		let buttonPage = UInt32(kHIDPage_Button)
		let consumerPage = UInt32(kHIDPage_Consumer)

		XCTAssertTrue(
			XboxGuideMonitor.isGuideEvent(
				usagePage: consumerPage,
				usage: 0x0223,
				hasExtendedButtons: true,
				hasACHome: true
			),
			"Classic Bluetooth Elite 2 sends the Xbox button as Consumer AC Home."
		)
		XCTAssertFalse(
			XboxGuideMonitor.isGuideEvent(
				usagePage: buttonPage,
				usage: 17,
				hasExtendedButtons: true,
				hasACHome: true
			),
			"Classic Bluetooth Elite 2 mirrors B as Button usage 17; it must not trigger Xbox."
		)
		XCTAssertFalse(
			XboxGuideMonitor.isGuideEvent(
				usagePage: buttonPage,
				usage: 13,
				hasExtendedButtons: true,
				hasACHome: true
			),
			"Extended Elite descriptors use Button usage 13 for a paddle, not Guide."
		)
	}

	func testBLEEliteRoutesGuideFromButton13() {
		XCTAssertTrue(
			XboxGuideMonitor.isGuideEvent(
				usagePage: UInt32(kHIDPage_Button),
				usage: 13,
				hasExtendedButtons: false,
				hasACHome: false
			)
		)
	}

	func testUSBStyleControllersRouteGuideFromButton17() {
		let buttonPage = UInt32(kHIDPage_Button)

		XCTAssertTrue(
			XboxGuideMonitor.isGuideEvent(
				usagePage: buttonPage,
				usage: 17,
				hasExtendedButtons: true,
				hasACHome: false
			)
		)
		XCTAssertFalse(
			XboxGuideMonitor.isGuideEvent(
				usagePage: buttonPage,
				usage: 13,
				hasExtendedButtons: true,
				hasACHome: false
			)
		)
	}

	func testPaddleConsumerUsageIsNotGuide() {
		XCTAssertFalse(
			XboxGuideMonitor.isGuideEvent(
				usagePage: UInt32(kHIDPage_Consumer),
				usage: 0x81,
				hasExtendedButtons: true,
				hasACHome: true
			)
		)
	}

    // MARK: - CallbackContext weak reference safety

    func testCallbackContextWeakReference() {
        // The core safety property: when the monitor is deallocated,
        // the CallbackContext's weak reference becomes nil (no dangling pointer).
		var monitor: XboxGuideMonitor? = XboxGuideMonitor(enableHardwareMonitoring: false)
		monitor?.prepareCallbackContextForTesting()
        weak var weakMonitor = monitor

        XCTAssertNotNil(weakMonitor, "Monitor should be alive")
		XCTAssertEqual(monitor?.hasCallbackContextForTesting, true)

        monitor = nil

        XCTAssertNil(weakMonitor, "Monitor should be deallocated after niling reference")
    }

    // MARK: - stop() releases callback context

    func testStopReleasesCallbackContext() {
		let monitor = XboxGuideMonitor(enableHardwareMonitoring: false)
		monitor.prepareCallbackContextForTesting()
        XCTAssertTrue(monitor.isStarted, "Monitor should be started after init")
		XCTAssertTrue(monitor.hasCallbackContextForTesting, "Monitor should have an owned callback context")

        monitor.stop()

        XCTAssertFalse(monitor.isStarted, "Monitor should not be started after stop()")
		XCTAssertFalse(monitor.hasCallbackContextForTesting, "stop() should release the callback context")
    }

    // MARK: - Double stop does not crash

    func testDoubleStopDoesNotCrash() {
		let monitor = XboxGuideMonitor(enableHardwareMonitoring: false)
		monitor.prepareCallbackContextForTesting()
        monitor.stop()
        monitor.stop() // Must not double-release or crash
        XCTAssertFalse(monitor.isStarted)
    }

    // MARK: - Double start is a no-op

    func testDoubleStartDoesNotLeak() {
		let monitor = XboxGuideMonitor(enableHardwareMonitoring: false)
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
		var monitor: XboxGuideMonitor? = XboxGuideMonitor(enableHardwareMonitoring: false)
		monitor?.prepareCallbackContextForTesting()
        XCTAssertTrue(monitor!.isStarted)
		XCTAssertTrue(monitor!.hasCallbackContextForTesting)

        // When the monitor goes out of scope, deinit should call stop()
        // without crashing. If stop() wasn't called, the retained
        // CallbackContext would leak.
        monitor = nil
        // No crash = pass. The retained context was properly released.
    }

    // MARK: - Start after stop restarts correctly

    func testStartAfterStopRestartsCorrectly() {
		let monitor = XboxGuideMonitor(enableHardwareMonitoring: false)
        XCTAssertTrue(monitor.isStarted)

        monitor.stop()
        XCTAssertFalse(monitor.isStarted)

        monitor.start()
        XCTAssertTrue(monitor.isStarted)

        monitor.stop()
        XCTAssertFalse(monitor.isStarted)
    }
}

@MainActor
final class EliteControllerInputPolicyTests: XCTestCase {

	func testPaddleEventSourceIsNoneWhenGameControllerExposesPaddles() {
		XCTAssertEqual(
			EliteControllerInputPolicy.paddleEventSource(gameControllerHasPaddles: true),
			.none
		)
	}

	func testPaddleEventSourceIsRawHIDWhenGameControllerDoesNotExposePaddles() {
		XCTAssertEqual(
			EliteControllerInputPolicy.paddleEventSource(gameControllerHasPaddles: false),
			.rawHID
		)
	}

	func testHelperPaddleOwnershipComesFromRawHIDSource() {
		XCTAssertFalse(EliteControllerInputPolicy.helperHandlesPaddles(paddleEventSource: .none))
		XCTAssertTrue(EliteControllerInputPolicy.helperHandlesPaddles(paddleEventSource: .rawHID))
	}

	func testHelperArgumentsUseGuideOnlyWhenHelperDoesNotOwnPaddles() {
		XCTAssertEqual(
			EliteControllerInputPolicy.helperArguments(paddleEventSource: .none),
			["--guide-only"]
		)
		XCTAssertEqual(
			EliteControllerInputPolicy.helperArguments(paddleEventSource: .rawHID),
			[]
		)
	}

	func testHelperRestartsOnlyWhenRequestedPaddleModeChanges() {
		XCTAssertFalse(
			EliteControllerInputPolicy.helperNeedsRestart(
				currentHandlePaddles: true,
				requestedHandlePaddles: true
			)
		)
		XCTAssertTrue(
			EliteControllerInputPolicy.helperNeedsRestart(
				currentHandlePaddles: true,
				requestedHandlePaddles: false
			)
		)
		XCTAssertTrue(
			EliteControllerInputPolicy.helperNeedsRestart(
				currentHandlePaddles: nil,
				requestedHandlePaddles: true
			)
		)
	}
}
