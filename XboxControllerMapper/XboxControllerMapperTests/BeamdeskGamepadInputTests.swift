import XCTest
@testable import ControllerKeys

private func gamepadPacket(_ sequence: Int, session: UUID, buttons: [String] = [],
		axes: [Double] = [0, 0, 0, 0, 0, 0], active: Bool = true) -> String {
	let data = try! JSONSerialization.data(withJSONObject: [
		"version": 1, "session": session.uuidString, "sequence": sequence,
		"buttons": buttons, "axes": axes, "active": active,
	])
	return String(decoding: data, as: UTF8.self)
}

final class BeamdeskGamepadInputTests: XCTestCase {
	func testRejectsMalformedUnboundedOrUnknownInputs() {
		let id = UUID()
		XCTAssertNil(BeamdeskGamepadSnapshot.parse("{}"))
		XCTAssertNil(BeamdeskGamepadSnapshot.parse(gamepadPacket(1, session: id, buttons: ["beamdeskLeftThumbTap"])))
		XCTAssertNil(BeamdeskGamepadSnapshot.parse(gamepadPacket(1, session: id, axes: [0, 0])))
		XCTAssertNil(BeamdeskGamepadSnapshot.parse(gamepadPacket(1, session: id, axes: [0, 0, 0, 0, -1, 0])))
		XCTAssertNil(BeamdeskGamepadSnapshot.parse(gamepadPacket(1, session: id, axes: [2, 0, 0, 0, 0, 0])))
		XCTAssertNil(BeamdeskGamepadSnapshot.parse(gamepadPacket(0, session: id)))
	}
	func testLeaseRejectsReorderedFramesAndRetiredSessions() {
		var lease = BeamdeskGamepadLease()
		let first = UUID(), second = UUID()
		func packet(_ seq: Int, _ id: UUID, active: Bool = true) -> BeamdeskGamepadSnapshot {
			BeamdeskGamepadSnapshot.parse(gamepadPacket(seq, session: id, active: active))!
		}
		XCTAssertTrue(lease.accept(packet(1, first), now: 0))
		XCTAssertTrue(lease.accept(packet(3, first), now: 0.5))
		XCTAssertFalse(lease.accept(packet(2, first), now: 0.6))
		XCTAssertTrue(lease.accept(packet(1, second), now: 0.7))
		XCTAssertFalse(lease.accept(packet(4, first), now: 0.8))
		XCTAssertTrue(lease.accept(packet(2, second, active: false), now: 1))
		XCTAssertFalse(lease.accept(packet(3, second), now: 1.1))
	}
	func testLostConnectionRequiresNeutralBeforeResumingSameLease() {
		var lease = BeamdeskGamepadLease()
		let id = UUID()
		let neutral = BeamdeskGamepadSnapshot.parse(gamepadPacket(1, session: id))!
		XCTAssertTrue(lease.accept(neutral, now: 0))
		XCTAssertFalse(lease.expire(now: 1.49))
		XCTAssertTrue(lease.expire(now: 1.5))
		XCTAssertFalse(lease.accept(BeamdeskGamepadSnapshot.parse(gamepadPacket(2, session: id, buttons: ["a"]))!, now: 2))
		XCTAssertTrue(lease.accept(BeamdeskGamepadSnapshot.parse(gamepadPacket(3, session: id))!, now: 2.1))
	}
	@MainActor func testAnalogValuesConnectionAndStopUseNormalControllerState() {
		let controller = ControllerService(enableHardwareMonitoring: false)
		let input = BeamdeskGamepadInput(controller: controller)
		defer { input.stop(); controller.cleanup() }
		let id = UUID()
		input.receive(gamepadPacket(1, session: id))
		input.receive(gamepadPacket(2, session: id, axes: [0.3, 0.7, -0.4, -0.2, 0.6, 0.8]))
		XCTAssertTrue(controller.isConnected)
		XCTAssertEqual(controller.controllerName, "Beamdesk Gamepad")
		XCTAssertEqual(controller.threadSafeLeftStick.x, 0.3, accuracy: 0.001)
		XCTAssertEqual(controller.threadSafeRightStick.y, -0.2, accuracy: 0.001)
		input.stop()
		XCTAssertFalse(controller.isBeamdeskGamepadConnected)
		XCTAssertEqual(controller.threadSafeLeftStick, .zero)
		XCTAssertEqual(controller.threadSafeRightStick, .zero)
		input.receive(gamepadPacket(1, session: UUID()))
		XCTAssertFalse(controller.isBeamdeskGamepadConnected, "A queued notification cannot reactivate a stopped receiver")
	}
}

/// Uses the existing in-memory simulator. No keys, clicks, or pointer motion reach macOS.
final class BeamdeskGamepadMappingTests: MappingEngineTestCase {
	func testUsesCurrentProfileAndReleasesItsHeldModifier() async throws {
		let id = UUID()
		let input = await MainActor.run { () -> BeamdeskGamepadInput in
			profileManager.setActiveProfile(Profile(name: "Quest test", buttonMappings: [
				.a: KeyMapping(keyCode: 1), .leftBumper: .holdModifier(.command),
			]))
			return BeamdeskGamepadInput(controller: controllerService)
		}
		await waitForTasks()
		await MainActor.run {
			input.receive(gamepadPacket(1, session: id))
			input.receive(gamepadPacket(2, session: id, buttons: ["leftBumper"]))
		}
		await waitForTasks(0.3)
		await MainActor.run {
			XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
			input.receive(gamepadPacket(3, session: id, buttons: ["leftBumper", "a"]))
			input.receive(gamepadPacket(4, session: id, buttons: ["leftBumper"]))
		}
		await waitForTasks(0.3)
		await MainActor.run {
			XCTAssertTrue(mockInputSimulator.events.contains { if case .pressKey(1, _) = $0 { return true }; return false })
			input.stop()
		}
		await waitForTasks(0.3)
		await MainActor.run { XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand)) }
	}
}
