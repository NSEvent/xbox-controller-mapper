import XCTest
@testable import ControllerKeys

final class TriggerMIDIOutputTests: XCTestCase {
	func testQuantizationInversionAndConfiguredRange() {
		let config = TriggerMIDIConfiguration(message: MIDIControlChange(pressValue: 110, releaseValue: 10), deadzone: 0.1)
		XCTAssertEqual(config.value(for: 0), 10)
		XCTAssertEqual(config.value(for: 0.1), 10)
		XCTAssertEqual(config.value(for: 0.55), 60)
		XCTAssertEqual(config.value(for: 1), 110)
		var inverted = config
		inverted.inverted = true
		XCTAssertEqual(inverted.value(for: 0), 110)
		XCTAssertEqual(inverted.value(for: 1), 10)
	}
	func testDuplicateSuppressionRateLimitAndImmediateNeutral() {
		let sender = MockMIDIService()
		let output = TriggerMIDIOutput(sender: sender)
		let config = TriggerMIDIConfiguration()
		func update(_ value: Double, _ now: Double) { output.update(left: value, right: 0, leftConfiguration: config, rightConfiguration: nil, now: now) }
		update(0, 0)
		update(0.5, 1)
		update(0.5, 2)
		update(0.7, 2.001)
		update(0.8, 2.002)
		update(0, 2.003)
		XCTAssertEqual(sender.events, [.press(config.output(value: 0)), .press(config.output(value: config.value(for: 0.5))),
									   .press(config.output(value: config.value(for: 0.7))), .press(config.output(value: 0))])
	}
	func testHeldTriggerMustReturnToNeutralAcrossConfigurationBoundary() {
		let sender = MockMIDIService()
		let output = TriggerMIDIOutput(sender: sender)
		let config = TriggerMIDIConfiguration()
		output.update(left: 1, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 0)
		output.update(left: 1, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 1)
		XCTAssertEqual(sender.events, [.press(config.output(value: 0))])
		output.update(left: 0, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 2)
		output.update(left: 1, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 3)
		output.reset()
		output.update(left: 1, right: 0, leftConfiguration: config, rightConfiguration: nil, now: 4)
		XCTAssertEqual(sender.events.map { event -> Int in if case .press(let message) = event { return message.pressValue }; return -1 }, [0, 127, 0, 0])
	}
	func testOldDestinationResetsBeforeNewDestinationStarts() {
		let sender = MockMIDIService()
		let output = TriggerMIDIOutput(sender: sender)
		let old = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 1, controller: 10))
		let new = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 2, controller: 20))
		output.update(left: 0, right: 0, leftConfiguration: old, rightConfiguration: nil, now: 0)
		output.update(left: 1, right: 0, leftConfiguration: old, rightConfiguration: nil, now: 1)
		output.update(left: 1, right: 0, leftConfiguration: new, rightConfiguration: nil, now: 2)
		XCTAssertEqual(sender.events, [.press(old.output(value: 0)), .press(old.output(value: 127)),
									   .press(old.output(value: 0)), .press(new.output(value: 0))])
	}
	func testProfileRoundTripAndOldDefaults() throws {
		var settings = JoystickSettings.default
		settings.leftTriggerMIDI = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 5, controller: 12))
		let profile = Profile(name: "MIDI", joystickSettings: settings)
		XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)).joystickSettings.leftTriggerMIDI, settings.leftTriggerMIDI)
		let defaults = try JSONDecoder().decode(JoystickSettings.self, from: Data("{}".utf8))
		XCTAssertNil(defaults.leftTriggerMIDI)
		XCTAssertNil(defaults.rightTriggerMIDI)
	}
}

@MainActor
final class TriggerMIDIPollingTests: MappingEngineTestCase {
	func testControllerLockReturnsContinuousCCToNeutral() async {
		var settings = JoystickSettings.default
		let config = TriggerMIDIConfiguration()
		settings.leftTriggerMIDI = config
		profileManager.setActiveProfile(Profile(name: "Lock MIDI", joystickSettings: settings))
		controllerService.isConnected = true
		await waitForTasks(0.05)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 1 }
		await waitForTasks(0.05)
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: 127)))
		_ = mappingEngine.performLockToggle()
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: 0)))
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0 }
	}
	func testProductionPollingSendsValuesAndDisableResets() async {
		var settings = JoystickSettings.default
		let config = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 3, controller: 22))
		settings.leftTriggerMIDI = config
		profileManager.setActiveProfile(Profile(name: "Analog MIDI", joystickSettings: settings))
		controllerService.isConnected = true
		await waitForTasks(0.05)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0.6 }
		await waitForTasks(0.1)
		XCTAssertTrue(mockMIDIService.events.contains(.press(config.output(value: config.value(for: 0.6)))))
		mappingEngine.disable()
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: 0)))
		let count = mockMIDIService.events.count
		await waitForTasks(0.1)
		XCTAssertEqual(mockMIDIService.events.count, count)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0 }
	}
}
