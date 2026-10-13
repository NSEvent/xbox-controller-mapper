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
	func testDeckSystemAndRearButtonsUseTheirExactSavedEdgeMappings() async throws {
		let buttons: [ControllerButton] = [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle, .xbox, .micMute]
		profileManager.setActiveProfile(Profile(name: "Deck buttons", buttonMappings:
			Dictionary(uniqueKeysWithValues: buttons.enumerated().map { ($0.element, KeyMapping(keyCode: UInt16($0.offset))) })))
		let input = SteamDeckInput(controller: controllerService, observe: false)
		defer { input.stop() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		await waitForTasks()
		for (index, button) in buttons.enumerated() {
			mockInputSimulator.clearEvents()
			frame.sequence! += 1; frame.buttons = [button.rawValue]
			input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
			frame.sequence! += 1; frame.buttons = []
			input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
			await waitForTasks(0.2)
			let pressed = mockInputSimulator.events.compactMap { event -> UInt16? in
				if case .pressKey(let code, _) = event { return code }; return nil
			}
			XCTAssertEqual(pressed, [UInt16(index)], "Unexpected mapping for \(button)")
		}
	}
	func testFilteredDeckFineMouseMotionUsesProfileDeadzoneButPhysicalSteamKeepsNoiseFloor() async throws {
		var settings = JoystickSettings()
		settings.touchpadDeadzone = 0.0013
		settings.touchpadSmoothing = 0.403
		profileManager.setActiveProfile(Profile(name: "Deck precision", joystickSettings: settings))
		let input = SteamDeckInput(controller: controllerService, observe: false)
		defer { input.stop() }
		var frame = SteamDeckFrame.released
		frame.active = true; frame.session = UUID(); frame.sequence = 1
		input.receive(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
		await waitForTasks(0.2)
		XCTAssertTrue(controllerService.snapshot().hasFilteredSteamDeckPads)
		let engine = mappingEngine!
		mockInputSimulator.clearEvents()
		engine.pollingQueue.sync { engine.processTouchpadMovement(.init(x: 0.0025, y: 0)) }
		XCTAssertTrue(mockInputSimulator.events.contains {
			if case .moveMouse(let x, _) = $0 { return x > 0 }; return false
		}, "Filtered Deck micro-movement must reach the mouse")
		input.stop()
		controllerService.withStorageLock { $0.applyControllerTypeLocked(.steam) }
		XCTAssertFalse(controllerService.snapshot().hasFilteredSteamDeckPads)
		mockInputSimulator.clearEvents()
		engine.pollingQueue.sync { engine.processTouchpadMovement(.init(x: 0.0025, y: 0)) }
		XCTAssertFalse(mockInputSimulator.events.contains {
			if case .moveMouse = $0 { return true }; return false
		}, "Unfiltered physical Steam pads retain their noise floor")
	}

	func testFilteredPadSourceFlagClearsOnHardwareTypeTakeover() {
		controllerService.setSteamDeckConnected(true)
		XCTAssertTrue(controllerService.snapshot().hasFilteredSteamDeckPads)
		controllerService.withStorageLock { $0.applyControllerTypeLocked(.steam) }
		XCTAssertFalse(controllerService.snapshot().hasFilteredSteamDeckPads)
		controllerService.setSteamDeckConnected(false)
		XCTAssertFalse(controllerService.snapshot().hasFilteredSteamDeckPads)
	}

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

/// Opt-in measurements use mock output only. No real controller, pointer or key events.
@MainActor
final class SteamDeckPerformanceExperiments: MappingEngineTestCase {
	func testOptInExtraJoystickTicksAgainstFixedRateProfile() async throws {
		guard ProcessInfo.processInfo.environment["CONTROLLERKEYS_DECK_PERF"] == "1" else {
			throw XCTSkip("Opt-in mock cadence experiment")
		}
		var settings = JoystickSettings()
		settings.leftStick.mode = .mouse
		settings.rightStick.mode = .scroll
		profileManager.setActiveProfile(Profile(name: "Owned cadence experiment", joystickSettings: settings))
		await waitForTasks(0.2)
		controllerService.updateLeftStick(x: 0.8, y: 0)
		controllerService.updateRightStick(x: 0, y: 0.8)
		let engine = mappingEngine!
		var rows: [[String: Double]] = []
		for frequency in [120, 360, 120, 360] {
			let row: [String: Double] = engine.pollingQueue.sync {
				engine.state.lock.lock()
				defer { engine.state.lock.unlock() }
				engine.state.currentMultiplier = 0
				engine.state.lastJoystickSampleTime = 0
				mockInputSimulator.clearEvents()
				// Exercise the actual output paths. The synthetic clock spans the
				// same second; only the number of scheduling opportunities changes.
				let base = CFAbsoluteTimeGetCurrent()
				for index in 0..<frequency {
					let now = base + Double(index) / Double(frequency)
					engine.processMouseMovement(CGPoint(x: 0.8, y: 0), tuning: settings.leftStick,
						settings: settings, analogPrecisionMultiplier: 1, now: now)
					engine.processScrolling(CGPoint(x: 0, y: 0.8), rawStick: CGPoint(x: 0, y: 0.8),
						tuning: settings.rightStick, settings: settings, now: now)
				}
				var mouse: Double = 0
				var scroll: Double = 0
				for event in mockInputSimulator.events {
					switch event {
					case .moveMouse(let x, _): mouse += Double(x)
					case .scroll(_, let y): scroll += Double(y)
					default: break
					}
				}
				engine.state.lastJoystickSampleTime = 0
				return ["ticks": Double(frequency), "mouseX": mouse, "scrollY": scroll]
			}
			rows.append(row)
		}
		let output = String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self)
		NSLog("[DeckCadenceExperiment] %@", output)
	}
}
