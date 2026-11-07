import XCTest
@testable import ControllerKeys

/// Stopping mic level monitoring must cancel an engine start that is still
/// waiting out its device-switch delay, or the mic tap keeps running with
/// nothing left to stop it.
@MainActor
final class MicLevelMonitorStopTests: XCTestCase {
	private var controllerService: ControllerService!

	override func setUp() async throws {
		try await super.setUp()
		controllerService = ControllerService(enableHardwareMonitoring: false)
	}

	override func tearDown() async throws {
		controllerService?.micLevelEngineStarterForTesting = nil
		controllerService?.cleanup()
		controllerService = nil
		try await super.tearDown()
	}

	func testStopDuringStartDelayCancelsEngineStart() async throws {
		var engineStarts = 0
		controllerService.micLevelEngineStarterForTesting = { engineStarts += 1 }

		controllerService.startAudioEngine()
		controllerService.stopMicLevelMonitoring()
		try await Task.sleep(nanoseconds: 400_000_000)

		XCTAssertEqual(engineStarts, 0, "a stopped monitor must not start the mic engine later")
	}

	func testUnstoppedStartStillRuns() async throws {
		var engineStarts = 0
		controllerService.micLevelEngineStarterForTesting = { engineStarts += 1 }

		controllerService.startAudioEngine()
		try await Task.sleep(nanoseconds: 400_000_000)

		XCTAssertEqual(engineStarts, 1)
	}
}
