import XCTest
@preconcurrency import GameController
@testable import ControllerKeys

/// Replay the Micro's physical-profile Direction Pad through its real binding
/// and mapping engine. OS output is mocked; no real keyboard/mouse events.
final class SticklessPhysicalDpadTests: MappingEngineTestCase {
	@MainActor
	private func install(mode: StickMode) -> GCController {
		var profile = Profile(name: "Micro D-pad", buttonMappings: [
			.dpadUp: .key(13), .dpadRight: .key(2),
			.dpadDown: .key(1), .dpadLeft: .key(0)
		])
		profile.selectDPadPreset(.wasd)
		profile.joystickSettings.leftStick.mode = mode
		profileManager.installTestProfile(profile)
		let controller = GCController.withExtendedGamepad()
		controllerService.connectedController = controller
		controllerService.storage.lock.withLock { controllerService.storage.eightBitDoModel = .micro }
		controllerService.bindPhysicalDirectionPad(controller.extendedGamepad!.dpad, from: controller, isStickless: true)
		controllerService.isConnected = true
		return controller
	}

	@MainActor
	private func direction(_ controller: GCController, _ x: Float, _ y: Float) {
		let dpad = controller.extendedGamepad!.dpad
		dpad.valueChangedHandler?(dpad, x, y)
	}

	@MainActor
	func testMicroMouseModeMovesAndReleaseStopsInput() async {
		let controller = install(mode: .mouse)
		direction(controller, 1, 0)
		let moved = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .moveMouse(let x, _) = $0 { return x > 0 }; return false }
		}
		XCTAssertTrue(moved)
		XCTAssertNil(controller.extendedGamepad!.dpad.right.pressedChangedHandler)
		XCTAssertFalse(mockInputSimulator.events.contains { if case .startHoldMapping = $0 { return true }; return false })
		direction(controller, 0, 0)
		let released = await waitForCondition { self.controllerService.readStorage(\.leftStick) == .zero }
		XCTAssertTrue(released)
	}

	@MainActor
	func testMicroWASDPresetProducesOnePressAndRelease() async {
		let controller = install(mode: .dpad)
		direction(controller, 0, 1)
		let pressed = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .startHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }
		}
		XCTAssertTrue(pressed)
		direction(controller, 0, 0)
		let released = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .stopHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }
		}
		XCTAssertTrue(released)
		XCTAssertEqual(mockInputSimulator.events.filter { if case .startHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }.count, 1)
	}

	@MainActor
	func testMicroOffModeDoesNotEmitDirectionKeysOrMouse() async {
		let controller = install(mode: .none)
		direction(controller, -1, 1)
		let received = await waitForCondition { self.controllerService.readStorage(\.leftStick) == CGPoint(x: -1, y: 1) }
		XCTAssertTrue(received)
		await waitForTasks(0.1)
		XCTAssertFalse(mockInputSimulator.events.contains {
			switch $0 {
			case .moveMouse, .startHoldMapping, .executeMapping, .keyDown: return true
			default: return false
			}
		})
		direction(controller, 0, 0)
	}

	@MainActor
	func testOrdinaryGamepadRetainsIndependentDpadButtons() async {
		let controller = install(mode: .none)
		let dpad = controller.extendedGamepad!.dpad
		dpad.valueChangedHandler = nil
		controllerService.bindPhysicalDirectionPad(dpad, from: controller, isStickless: false)
		dpad.up.pressedChangedHandler?(dpad.up, 1, true)
		let pressed = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .startHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }
		}
		XCTAssertTrue(pressed)
		XCTAssertEqual(controllerService.readStorage(\.leftStick), .zero)
		dpad.up.pressedChangedHandler?(dpad.up, 0, false)
	}

	// MARK: - Raw-HID hat (GameController never fires the Micro's Direction Pad)

	/// Feeds a Micro D-input report (id 0x03, 11 bytes) with the given hat.
	/// Bytes mirror a 2026-10-29 Bluetooth capture: `03 HH 7F 7F 7F 7F 00 00 00 00 51`.
	private func sendMicroReport(hat: UInt8) {
		var bytes: [UInt8] = [0x03, hat, 0x7F, 0x7F, 0x7F, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x51]
		bytes.withUnsafeMutableBufferPointer { buffer in
			controllerService.handleEightBitDoHIDReport(
				productID: EightBitDoDInputHIDDriverDescriptor.microProductID,
				reportID: 0x03,
				report: buffer.baseAddress!,
				length: buffer.count
			)
		}
	}

	func testMicroHatVectorsFollowHIDClockwiseOrder() {
		let expected: [(UInt8, Float, Float)] = [
			(0, 0, 1), (1, 1, 1), (2, 1, 0), (3, 1, -1),
			(4, 0, -1), (5, -1, -1), (6, -1, 0), (7, -1, 1), (8, 0, 0), (15, 0, 0)
		]
		for (hat, x, y) in expected {
			let vector = ControllerService.eightBitDoHatVector(hat)
			XCTAssertEqual(vector.x, x, "hat \(hat)")
			XCTAssertEqual(vector.y, y, "hat \(hat)")
		}
	}

	@MainActor
	func testMicroRawHatDrivesLeftStickAndCenters() async {
		_ = install(mode: .none)
		for (hat, point) in [(UInt8(0x00), CGPoint(x: 0, y: 1)), (0x04, CGPoint(x: 0, y: -1)),
		                     (0x06, CGPoint(x: -1, y: 0)), (0x02, CGPoint(x: 1, y: 0))] {
			sendMicroReport(hat: hat)
			XCTAssertEqual(controllerService.readStorage(\.leftStick), point)
			sendMicroReport(hat: 0x08)
			XCTAssertEqual(controllerService.readStorage(\.leftStick), .zero)
		}
	}

	@MainActor
	func testMicroRawHatInWASDModePressesAndReleasesW() async {
		_ = install(mode: .dpad)
		sendMicroReport(hat: 0x00)
		let pressed = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .startHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }
		}
		XCTAssertTrue(pressed)
		sendMicroReport(hat: 0x08)
		let released = await waitForCondition {
			self.mockInputSimulator.events.contains { if case .stopHoldMapping(let mapping) = $0 { return mapping.keyCode == 13 }; return false }
		}
		XCTAssertTrue(released)
	}

	@MainActor
	func testMicroRawHatRepeatedReportsDoNotRewriteStick() async {
		_ = install(mode: .none)
		sendMicroReport(hat: 0x02)
		controllerService.updateLeftStick(x: 0, y: 0)
		// Same hat again (e.g. a battery-byte change): edge-triggered, no rewrite.
		sendMicroReport(hat: 0x02)
		XCTAssertEqual(controllerService.readStorage(\.leftStick), .zero)
		sendMicroReport(hat: 0x08)
	}
}
