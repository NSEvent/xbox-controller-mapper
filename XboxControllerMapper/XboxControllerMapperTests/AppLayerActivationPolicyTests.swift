import XCTest
@testable import ControllerKeys

final class AppLayerActivationPolicyTests: XCTestCase {
	private let controllerKeysBundleId = "xyz.kevintang.controllerkeys"
	private let targetBundleId = "com.adobe.LightroomClassicCC7"

	func testResolveReturnsBoundLayerForFrontmostApp() {
		let layer = Layer(name: "Lightroom")
		let profile = Profile(
			name: "Editing",
			appLayerBindings: [targetBundleId: layer.id],
			layers: [layer]
		)

		XCTAssertEqual(
			AppLayerActivationPolicy.resolve(
				bundleId: targetBundleId,
				controllerKeysBundleId: controllerKeysBundleId,
				profile: profile
			),
			layer.id
		)
	}

	func testResolveSuppressesLayerWhileControllerKeysIsFrontmost() {
		let layer = Layer(name: "Editor")
		let profile = Profile(
			name: "Editing",
			appLayerBindings: [controllerKeysBundleId: layer.id],
			layers: [layer]
		)

		XCTAssertNil(
			AppLayerActivationPolicy.resolve(
				bundleId: controllerKeysBundleId,
				controllerKeysBundleId: controllerKeysBundleId,
				profile: profile
			)
		)
	}

	func testResolveIgnoresDanglingLayerBinding() {
		let profile = Profile(
			name: "Editing",
			appLayerBindings: [targetBundleId: UUID()]
		)

		XCTAssertNil(
			AppLayerActivationPolicy.resolve(
				bundleId: targetBundleId,
				controllerKeysBundleId: controllerKeysBundleId,
				profile: profile
			)
		)
	}

	func testEffectiveLayerOrderPlacesManualLayerAboveAppLayer() {
		let state = MappingEngine.EngineState()
		let appLayerId = UUID()
		let manualLayerId = UUID()

		state.appActivatedLayerId = appLayerId
		state.activeLayerIds = [manualLayerId]

		XCTAssertEqual(state.effectiveActiveLayerIds, [appLayerId, manualLayerId])
	}

	func testEffectiveLayerOrderDeduplicatesSameAppAndManualLayer() {
		let state = MappingEngine.EngineState()
		let layerId = UUID()

		state.appActivatedLayerId = layerId
		state.activeLayerIds = [layerId]

		XCTAssertEqual(state.effectiveActiveLayerIds, [layerId])
	}

	func testProfileCodablePreservesLayerAppBindings() throws {
		let layer = Layer(name: "Lightroom")
		let profile = Profile(
			name: "Editing",
			appLayerBindings: [targetBundleId: layer.id],
			layers: [layer]
		)

		let decoded = try JSONDecoder().decode(
			Profile.self,
			from: JSONEncoder().encode(profile)
		)

		XCTAssertEqual(decoded.appLayerBindings, [targetBundleId: layer.id])
	}
}

@MainActor
final class AppLayerRuntimeTransitionTests: MappingEngineTestCase {
	func testAppLayerChangePreservesHeldManualLayerAndOpenWheelState() async {
		let firstBundleId = "com.example.first"
		let secondBundleId = "com.example.second"
		let firstAppLayer = Layer(name: "First App")
		let remappedActivatorMessage = MIDIControlChange(channel: 1, controller: 44)
		let secondAppLayer = Layer(
			name: "Second App",
			buttonMappings: [
				.leftBumper: KeyMapping(midiControlChange: remappedActivatorMessage)
			]
		)
		let manualLayer = Layer(name: "Manual", activatorButton: .leftBumper)
		let profile = Profile(
			name: "Contextual",
			appLayerBindings: [
				firstBundleId: firstAppLayer.id,
				secondBundleId: secondAppLayer.id
			],
			layers: [firstAppLayer, secondAppLayer, manualLayer]
		)

		await MainActor.run {
			profileManager.setActiveProfile(profile)
			appMonitor.frontmostBundleId = firstBundleId
			controllerService.buttonPressed(.leftBumper)
		}
		await waitForTasks(0.15)

		await MainActor.run {
			mappingEngine.state.lock.withLock {
				XCTAssertEqual(mappingEngine.state.activeLayerIds, [manualLayer.id])
				mappingEngine.state.commandWheelButton = .menu
				mappingEngine.state.commandWheelHoldMode = true
				mappingEngine.state.commandWheelActive = true
			}
			mockInputSimulator.holdModifier(.maskCommand)
		}

		await MainActor.run {
			appMonitor.frontmostBundleId = secondBundleId
		}

		await MainActor.run {
			mappingEngine.state.lock.withLock {
				XCTAssertEqual(mappingEngine.state.appActivatedLayerId, secondAppLayer.id)
				XCTAssertEqual(mappingEngine.state.activeLayerIds, [manualLayer.id])
				XCTAssertTrue(
					mappingEngine.state.buttonsActingAsLayerActivators.contains(.leftBumper)
				)
				XCTAssertEqual(mappingEngine.state.commandWheelButton, .menu)
				XCTAssertTrue(mappingEngine.state.commandWheelHoldMode)
				XCTAssertTrue(mappingEngine.state.commandWheelActive)
			}
			XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskCommand))
		}

		await MainActor.run {
			controllerService.buttonReleased(.leftBumper)
		}
		await waitForTasks(0.15)

		await MainActor.run {
			mappingEngine.state.lock.withLock {
				XCTAssertTrue(mappingEngine.state.activeLayerIds.isEmpty)
				XCTAssertEqual(mappingEngine.state.effectiveActiveLayerIds, [secondAppLayer.id])
			}
		}
		XCTAssertTrue(
			mockMIDIService.events.isEmpty,
			"Releasing the preserved activator must not execute its incoming-layer mapping"
		)
	}

	func testProfileSwitchReleasesHeldOutputAndAppliesDestinationAppLayerLED() async {
		let targetBundleId = "com.example.destination"
		let outgoingMessage = MIDIControlChange(channel: 2, controller: 45)
		let incomingMessage = MIDIControlChange(channel: 2, controller: 46)
		let appLayerLED = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 0.1, green: 0.8, blue: 0.3)
		)
		let destinationLayer = Layer(
			name: "Destination",
			buttonMappings: [.a: KeyMapping(midiControlChange: incomingMessage)],
			dualSenseLEDSettings: appLayerLED
		)
		let sourceProfile = Profile(
			name: "Source",
			buttonMappings: [.a: KeyMapping(midiControlChange: outgoingMessage)]
		)
		let destinationProfile = Profile(
			name: "Destination",
			appLayerBindings: [targetBundleId: destinationLayer.id],
			layers: [destinationLayer]
		)

		await MainActor.run {
			profileManager.setActiveProfile(sourceProfile)
			appMonitor.frontmostBundleId = targetBundleId
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.2)
		XCTAssertEqual(mockMIDIService.events, [.press(outgoingMessage)])

		await MainActor.run {
			profileManager.setActiveProfile(destinationProfile)
		}
		await waitForTasks(0.1)

		XCTAssertEqual(
			mockMIDIService.events,
			[.press(outgoingMessage), .release(outgoingMessage)]
		)
		await MainActor.run {
			XCTAssertEqual(
				mappingEngine.state.lock.withLock { mappingEngine.state.appActivatedLayerId },
				destinationLayer.id
			)
			XCTAssertEqual(controllerService.threadSafeLEDSettings, appLayerLED)
		}

		await MainActor.run {
			controllerService.buttonReleased(.a)
		}
		await waitForTasks(0.15)

		XCTAssertEqual(
			mockMIDIService.events,
			[.press(outgoingMessage), .release(outgoingMessage)],
			"The old physical release must not execute the destination mapping"
		)
	}

	func testCancelledReleaseTracksPhysicalButtonAcrossLogicalAliases() async {
		let outgoingMessage = MIDIControlChange(channel: 4, controller: 47)
		let incomingMessage = MIDIControlChange(channel: 4, controller: 48)
		let sourceProfile = Profile(
			name: "Source",
			buttonMappings: [.leftPaddle: KeyMapping(midiControlChange: outgoingMessage)]
		)
		let destinationProfile = Profile(
			name: "Destination",
			buttonMappings: [.leftPaddle: KeyMapping(midiControlChange: incomingMessage)]
		)

		profileManager.setActiveProfile(sourceProfile)
		controllerService.buttonPressed(.xboxPaddle1)
		await waitForTasks(0.2)

		profileManager.setActiveProfile(destinationProfile)
		await waitForTasks(0.1)
		XCTAssertEqual(
			mockMIDIService.events,
			[.press(outgoingMessage), .release(outgoingMessage)]
		)

		controllerService.buttonPressed(.leftPaddle)
		await waitForTasks(0.2)
		controllerService.buttonReleased(.xboxPaddle1)
		await waitForTasks(0.1)

		XCTAssertEqual(
			mockMIDIService.events,
			[.press(outgoingMessage), .release(outgoingMessage), .press(incomingMessage)],
			"Releasing the old physical alias must not release the new logical-button action"
		)

		controllerService.buttonReleased(.leftPaddle)
		await waitForTasks(0.1)
		XCTAssertEqual(
			mockMIDIService.events,
			[
				.press(outgoingMessage),
				.release(outgoingMessage),
				.press(incomingMessage),
				.release(incomingMessage)
			]
		)
	}
}
