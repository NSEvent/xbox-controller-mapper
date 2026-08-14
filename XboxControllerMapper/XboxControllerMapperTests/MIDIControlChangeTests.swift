import XCTest
@testable import ControllerKeys

final class MIDIControlChangeModelTests: XCTestCase {
	func testInitClampsMIDIDataRanges() {
		let message = MIDIControlChange(
			channel: 99,
			controller: -2,
			pressValue: 300,
			releaseValue: -1
		)

		XCTAssertEqual(message.channel, 16)
		XCTAssertEqual(message.controller, 0)
		XCTAssertEqual(message.pressValue, 127)
		XCTAssertEqual(message.releaseValue, 0)
	}

	func testDecodeDefaultsAndClampsMIDIDataRanges() throws {
		let defaults = try JSONDecoder().decode(
			MIDIControlChange.self,
			from: Data("{}".utf8)
		)
		XCTAssertEqual(defaults, MIDIControlChange())

		let clamped = try JSONDecoder().decode(
			MIDIControlChange.self,
			from: Data(#"{"channel":0,"controller":200,"pressValue":-5,"releaseValue":300}"#.utf8)
		)
		XCTAssertEqual(clamped, MIDIControlChange(channel: 1, controller: 127, pressValue: 0, releaseValue: 127))
	}

	func testMIDIActionClassificationAndConflictClearing() {
		let message = MIDIControlChange(channel: 2, controller: 14)
		let mapping = KeyMapping(keyCode: 12, midiControlChange: message)

		XCTAssertEqual(mapping.activeActionCount, 2)
		XCTAssertEqual(mapping.effectiveActionType, .midiControlChange)

		let cleaned = mapping.clearingConflicts(keeping: .midiControlChange)
		XCTAssertNil(cleaned.keyCode)
		XCTAssertEqual(cleaned.midiControlChange, message)
		XCTAssertFalse(cleaned.hasConflictingActions)
	}

	func testProfileCodablePreservesMIDIOnEveryExecutableSurface() throws {
		let message = MIDIControlChange(channel: 3, controller: 42, pressValue: 110, releaseValue: 4)
		let layerWheelAction = CommandWheelAction(displayName: "Layer MIDI", midiControlChange: message)
		let layer = Layer(
			name: "MIDI Layer",
			buttonMappings: [.a: KeyMapping(midiControlChange: message)],
			commandWheelActions: [layerWheelAction]
		)
		let profile = Profile(
			name: "MIDI",
			buttonMappings: [
				.b: KeyMapping(
					longHoldMapping: LongHoldMapping(midiControlChange: message),
					doubleTapMapping: DoubleTapMapping(midiControlChange: message),
					midiControlChange: message
				)
			],
			chordMappings: [ChordMapping(buttons: [.a, .b], midiControlChange: message)],
			sequenceMappings: [SequenceMapping(steps: [.a, .b], midiControlChange: message)],
			gestureMappings: [GestureMapping(gestureType: .tiltBack, midiControlChange: message)],
			layers: [layer],
			commandWheelActions: [CommandWheelAction(displayName: "Base MIDI", midiControlChange: message)]
		)

		let decoded = try JSONDecoder().decode(
			Profile.self,
			from: JSONEncoder().encode(profile)
		)

		XCTAssertEqual(decoded.buttonMappings[.b]?.midiControlChange, message)
		XCTAssertEqual(decoded.buttonMappings[.b]?.longHoldMapping?.midiControlChange, message)
		XCTAssertEqual(decoded.buttonMappings[.b]?.doubleTapMapping?.midiControlChange, message)
		XCTAssertEqual(decoded.chordMappings.first?.midiControlChange, message)
		XCTAssertEqual(decoded.sequenceMappings.first?.midiControlChange, message)
		XCTAssertEqual(decoded.gestureMappings.first?.midiControlChange, message)
		XCTAssertEqual(decoded.commandWheelActions.first?.midiControlChange, message)
		XCTAssertEqual(decoded.layers.first?.buttonMappings[.a]?.midiControlChange, message)
		XCTAssertEqual(decoded.layers.first?.commandWheelActions?.first?.midiControlChange, message)
	}

	func testReservedControllerWarnings() {
		XCTAssertNotNil(MIDIControlChange(controller: 98).controllerWarning)
		XCTAssertNotNil(MIDIControlChange(controller: 127).controllerWarning)
		XCTAssertNil(MIDIControlChange(controller: 42).controllerWarning)
	}
}

@MainActor
final class MIDIButtonLifecycleTests: MappingEngineTestCase {
	func testButtonMappingSendsPressAndReleaseValues() async {
		let message = MIDIControlChange(channel: 4, controller: 22, pressValue: 127, releaseValue: 0)
		await MainActor.run {
			profileManager.setActiveProfile(
				Profile(name: "MIDI", buttonMappings: [.a: KeyMapping(midiControlChange: message)])
			)
		}
		await waitForTasks(0.05)

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.2)
		XCTAssertEqual(mockMIDIService.events, [.press(message)])

		await MainActor.run { controllerService.buttonReleased(.a) }
		await waitForTasks(0.2)
		XCTAssertEqual(mockMIDIService.events, [.press(message), .release(message)])
	}

	func testDiscreteMIDIActionPulses() async {
		let message = MIDIControlChange(channel: 1, controller: 9)

		await MainActor.run {
			_ = mappingEngine.mappingExecutor.executeAction(
				CommandWheelAction(displayName: "MIDI", midiControlChange: message),
				profile: profileManager.activeProfile
			)
		}

		XCTAssertEqual(mockMIDIService.events, [.pulse(message)])
	}

	func testDisablingEngineReleasesHeldMIDIControl() async {
		let message = MIDIControlChange(channel: 2, controller: 31)
		await MainActor.run {
			profileManager.setActiveProfile(
				Profile(name: "MIDI", buttonMappings: [.a: KeyMapping(midiControlChange: message)])
			)
		}
		await waitForTasks(0.05)

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.2)
		await MainActor.run { mappingEngine.disable() }
		await waitForTasks(0.1)

		XCTAssertEqual(mockMIDIService.events, [.press(message), .release(message)])
	}

	func testShutdownReleasesHeldMIDIAndFlushesPendingOutput() async {
		let message = MIDIControlChange(channel: 2, controller: 34)
		await MainActor.run {
			profileManager.setActiveProfile(
				Profile(name: "MIDI", buttonMappings: [.a: KeyMapping(midiControlChange: message)])
			)
		}
		await waitForTasks(0.05)

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.2)
		await MainActor.run { mappingEngine.shutdown() }

		XCTAssertEqual(mockMIDIService.events, [.press(message), .release(message)])
		XCTAssertEqual(mockMIDIService.flushCount, 1)
		XCTAssertNil(controllerService.onInputEvent)
	}

	func testControllerDisconnectedEventReleasesHeldMIDIControlAndDoesNotPoisonReconnect() async {
		let message = MIDIControlChange(channel: 3, controller: 32)
		await MainActor.run {
			profileManager.setActiveProfile(
				Profile(name: "MIDI", buttonMappings: [.a: KeyMapping(midiControlChange: message)])
			)
			controllerService.isConnected = true
		}
		await waitForTasks(0.1)

		await MainActor.run { controllerService.buttonPressed(.a) }
		await waitForTasks(0.2)
		await MainActor.run { controllerService.emitInputEvent(.controllerDisconnected) }
		await waitForTasks(0.1)

		XCTAssertEqual(mockMIDIService.events, [.press(message), .release(message)])

		await MainActor.run {
			controllerService.isConnected = true
			mappingEngine.handleRemoteControllerButtonPressed(.a)
		}
		await waitForTasks(0.2)
		await MainActor.run { mappingEngine.handleRemoteControllerButtonReleased(.a, holdDuration: 0.2) }
		await waitForTasks(0.1)

		XCTAssertEqual(
			mockMIDIService.events,
			[.press(message), .release(message), .press(message), .release(message)]
		)
	}
}
