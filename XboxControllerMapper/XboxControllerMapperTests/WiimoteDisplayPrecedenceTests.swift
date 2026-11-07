import XCTest
@testable import ControllerKeys

/// A Wii Remote shown as the active controller is hardware: auxiliary inputs
/// (rings, Beamdesk, Steam Deck) must neither take over its display slot nor
/// blank it when they disconnect.
@MainActor
final class WiimoteDisplayPrecedenceTests: XCTestCase {
	private var controllerService: ControllerService!

	override func setUp() async throws {
		try await super.setUp()
		controllerService = ControllerService(enableHardwareMonitoring: false)
		controllerService.wiimoteHIDActiveForTesting = true
		controllerService.controllerName = "Wii Remote"
		controllerService.isConnected = true
	}

	override func tearDown() async throws {
		controllerService?.cleanup()
		controllerService = nil
		try await super.tearDown()
	}

	private func assertWiimoteStillShown(_ message: String, line: UInt = #line) {
		XCTAssertEqual(controllerService.controllerName, "Wii Remote", message, line: line)
		XCTAssertTrue(controllerService.isConnected, message, line: line)
	}

	func testRingConnectDoesNotTakeOver() {
		controllerService.setOuraRingConnected(true)
		assertWiimoteStillShown("Oura connect")
		controllerService.setS29RingConnected(true)
		assertWiimoteStillShown("S29 connect")
	}

	func testAuxiliaryDisconnectsDoNotBlankWiimote() {
		controllerService.setS29RingConnected(true)
		controllerService.setS29RingConnected(false)
		assertWiimoteStillShown("S29 disconnect")
		controllerService.setBeamdeskHandsConnected(true)
		controllerService.setBeamdeskHandsConnected(false)
		assertWiimoteStillShown("Beamdesk hands disconnect")
		controllerService.setBeamdeskGamepadConnected(true)
		controllerService.setBeamdeskGamepadConnected(false)
		assertWiimoteStillShown("Beamdesk gamepad disconnect")
		controllerService.setOuraRingConnected(true)
		controllerService.setOuraRingConnected(false)
		assertWiimoteStillShown("Oura disconnect")
	}
}
