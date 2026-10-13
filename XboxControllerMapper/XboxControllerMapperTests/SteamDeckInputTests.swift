import XCTest
@testable import ControllerKeys

final class SteamDeckInputTests: XCTestCase {
	private func text(_ frame: SteamDeckFrame) -> String {
		String(decoding: try! JSONEncoder().encode(frame), as: UTF8.self)
	}
	@MainActor func testUsesSteamIdentityPadsAndExistingInputPipelineThenReleases() {
		let controller = ControllerService(enableHardwareMonitoring: false)
		let input = SteamDeckInput(controller: controller, observe: false)
		defer { input.stop(); controller.cleanup() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(text(frame))
		XCTAssertTrue(controller.isSteamDeckConnected)
		XCTAssertTrue(controller.threadSafeIsSteamController)
		XCTAssertEqual(controller.controllerName, "Steam Deck (ScreenShell)")
		frame.sequence = 2; frame.axes = [0.4, -0.3, -0.2, 0.6, 0.7, 0.8]
		frame.pads[1] = .init(x: 0.3, y: 0.4, touching: true, pressed: false)
		input.receive(text(frame))
		XCTAssertEqual(controller.threadSafeLeftStick.x, 0.4, accuracy: 0.001)
		XCTAssertEqual(controller.threadSafeRightStick.y, 0.6, accuracy: 0.001)
		XCTAssertTrue(controller.snapshot().isTouchpadTouching)
		input.stop()
		XCTAssertFalse(controller.isSteamDeckConnected)
		XCTAssertFalse(controller.snapshot().isTouchpadTouching)
		XCTAssertEqual(controller.threadSafeLeftStick, .zero)
		input.receive(text(frame))
		XCTAssertFalse(controller.isSteamDeckConnected)
	}
	@MainActor func testTouchedPadCannotStartSessionAndReplayCannotMoveStick() {
		let controller = ControllerService(enableHardwareMonitoring: false)
		let input = SteamDeckInput(controller: controller, observe: false)
		defer { input.stop(); controller.cleanup() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		frame.pads[0].touching = true
		input.receive(text(frame))
		XCTAssertFalse(controller.isSteamDeckConnected)
		frame.pads[0].touching = false; frame.sequence = 2
		input.receive(text(frame))
		frame.sequence = 3; frame.axes[0] = 0.4
		input.receive(text(frame))
		frame.sequence = 2; frame.axes[0] = 0.9
		input.receive(text(frame))
		XCTAssertEqual(controller.threadSafeLeftStick.x, 0.4, accuracy: 0.001)
	}
	@MainActor func testDistributedNotificationReachesInactiveAccessoryReceiver() async throws {
		let controller = ControllerService(enableHardwareMonitoring: false)
		let input = SteamDeckInput(controller: controller)
		defer { input.stop(); controller.cleanup() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		DistributedNotificationCenter.default().postNotificationName(
			Notification.Name(SteamDeckFrame.notification), object: nil,
			userInfo: ["state": text(frame)], deliverImmediately: true)
		try await Task.sleep(for: .milliseconds(200))
		XCTAssertTrue(controller.isSteamDeckConnected)
		frame.active = false; frame.sequence = 2
		DistributedNotificationCenter.default().postNotificationName(
			Notification.Name(SteamDeckFrame.notification), object: nil,
			userInfo: ["state": text(frame)], deliverImmediately: true)
		try await Task.sleep(for: .milliseconds(200))
		XCTAssertFalse(controller.isSteamDeckConnected)
	}
}

@MainActor
final class SteamDeckMappingTests: MappingEngineTestCase {
	func testDestinationSavedProfileOwnsActionsAndReleasesHeldCommand() async throws {
		profileManager.setActiveProfile(Profile(name: "Saved Deck profile", buttonMappings: [
			.a: KeyMapping(keyCode: 1), .rightTrigger: .holdModifier(.command),
		]))
		let input = SteamDeckInput(controller: controllerService, observe: false)
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		await waitForTasks()
		frame.sequence = 2; frame.axes[5] = 0.8
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		await waitForTasks(0.3)
		XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
		frame.sequence = 3; frame.buttons = ["a"]
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		frame.sequence = 4; frame.buttons = []
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		await waitForTasks(0.3)
		XCTAssertTrue(mockInputSimulator.events.contains {
			if case .pressKey(1, _) = $0 { return true }; return false
		}, "The Mac's saved A mapping must run, not a copied factory mapping")
		input.stop()
		await waitForTasks(0.3)
		XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand))
	}
}
