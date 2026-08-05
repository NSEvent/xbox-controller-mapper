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
		let latchedLayerId = UUID()
		let manualLayerId = UUID()

		state.appActivatedLayerId = appLayerId
		state.latchedLayerId = latchedLayerId
		state.activeLayerIds = [manualLayerId]

		XCTAssertEqual(
			state.effectiveActiveLayerIds,
			[appLayerId, latchedLayerId, manualLayerId]
		)
	}

	func testEffectiveLayerOrderDeduplicatesSameAppAndManualLayer() {
		let state = MappingEngine.EngineState()
		let layerId = UUID()

		state.appActivatedLayerId = layerId
		state.latchedLayerId = layerId
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
	func testAppLayerChangePreservesUnchangedHeldBaseAction() async {
		let firstBundleId = "com.example.first"
		let secondBundleId = "com.example.second"
		let firstAppLayer = Layer(name: "First App")
		let secondAppLayer = Layer(name: "Second App")
		let shiftMapping = KeyMapping.holdModifier(.shift)
		let profile = Profile(
			name: "Contextual",
			buttonMappings: [.a: shiftMapping],
			appLayerBindings: [
				firstBundleId: firstAppLayer.id,
				secondBundleId: secondAppLayer.id
			],
			layers: [firstAppLayer, secondAppLayer]
		)

		await MainActor.run {
			profileManager.setActiveProfile(profile)
			appMonitor.frontmostBundleId = firstBundleId
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.2)

		await MainActor.run {
			XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskShift))
			mockInputSimulator.clearEvents()
			appMonitor.frontmostBundleId = secondBundleId
		}
		await waitForTasks(0.15)

		await MainActor.run {
			XCTAssertTrue(
				mockInputSimulator.isHoldingModifiers(.maskShift),
				"An unchanged Base action must survive an app-layer change"
			)
			XCTAssertFalse(mockInputSimulator.events.contains(.stopHoldMapping(shiftMapping)))
			controllerService.buttonReleased(.a)
		}
		await waitForTasks(0.15)

		await MainActor.run {
			XCTAssertFalse(mockInputSimulator.isHoldingModifiers(.maskShift))
		}
	}

	func testAppLayerChangePreservesUnchangedHeldManualLayerAction() async {
		let firstBundleId = "com.example.first"
		let secondBundleId = "com.example.second"
		let firstAppLayer = Layer(name: "First App")
		let secondAppLayer = Layer(name: "Second App")
		let shiftMapping = KeyMapping.holdModifier(.shift)
		let manualLayer = Layer(
			name: "Manual",
			activatorButton: .leftBumper,
			buttonMappings: [.a: shiftMapping]
		)
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
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.2)

		await MainActor.run {
			XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskShift))
			mockInputSimulator.clearEvents()
			appMonitor.frontmostBundleId = secondBundleId
		}
		await waitForTasks(0.15)

		await MainActor.run {
			XCTAssertTrue(
				mockInputSimulator.isHoldingModifiers(.maskShift),
				"An unchanged held action from the preserved manual layer must survive an app-layer change"
			)
			XCTAssertEqual(
				mappingEngine.state.lock.withLock { mappingEngine.state.heldButtons[.a] },
				shiftMapping
			)
			XCTAssertFalse(mockInputSimulator.events.contains(.stopHoldMapping(shiftMapping)))
			controllerService.buttonReleased(.a)
			controllerService.buttonReleased(.leftBumper)
		}
		await waitForTasks(0.15)

		await MainActor.run {
			XCTAssertFalse(mockInputSimulator.isHoldingModifiers(.maskShift))
		}
	}

	func testAppLayerChangeReleasesHeldActionWhenEffectiveMappingChanges() async {
		let firstBundleId = "com.example.first"
		let secondBundleId = "com.example.second"
		let shiftMapping = KeyMapping.holdModifier(.shift)
		let commandMapping = KeyMapping.holdModifier(.command)
		let firstAppLayer = Layer(
			name: "First App",
			buttonMappings: [.a: shiftMapping]
		)
		let secondAppLayer = Layer(
			name: "Second App",
			buttonMappings: [.a: commandMapping]
		)
		let profile = Profile(
			name: "Contextual",
			appLayerBindings: [
				firstBundleId: firstAppLayer.id,
				secondBundleId: secondAppLayer.id
			],
			layers: [firstAppLayer, secondAppLayer]
		)

		await MainActor.run {
			profileManager.setActiveProfile(profile)
			appMonitor.frontmostBundleId = firstBundleId
			controllerService.buttonPressed(.a)
		}
		await waitForTasks(0.2)

		await MainActor.run {
			XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskShift))
			appMonitor.frontmostBundleId = secondBundleId
		}
		await waitForTasks(0.15)

		await MainActor.run {
			XCTAssertFalse(mockInputSimulator.isHoldingModifiers(.maskShift))
			XCTAssertFalse(mockInputSimulator.isHoldingModifiers(.maskCommand))
			XCTAssertNil(mappingEngine.state.lock.withLock { mappingEngine.state.heldButtons[.a] })
			XCTAssertTrue(mockInputSimulator.events.contains(.stopHoldMapping(shiftMapping)))
			controllerService.buttonReleased(.a)
		}
		await waitForTasks(0.1)

		await MainActor.run {
			XCTAssertFalse(
				mockInputSimulator.events.contains(.startHoldMapping(commandMapping)),
				"The release of a cancelled physical press must not start the incoming mapping"
			)
		}
	}

	func testManualLayerWithoutLEDOverrideUsesProfileLEDAboveAppLayer() async {
		let targetBundleId = "com.example.editor"
		let profileLED = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 0.8, green: 0.1, blue: 0.1)
		)
		let appLED = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 0.1, green: 0.8, blue: 0.1)
		)
		let appLayer = Layer(name: "App", dualSenseLEDSettings: appLED)
		let manualLayer = Layer(
			name: "Manual",
			activatorButton: .leftBumper,
			dualSenseLEDSettings: nil
		)
		let profile = Profile(
			name: "LED Layers",
			dualSenseLEDSettings: profileLED,
			appLayerBindings: [targetBundleId: appLayer.id],
			layers: [appLayer, manualLayer]
		)

		await MainActor.run {
			profileManager.setActiveProfile(profile)
			appMonitor.frontmostBundleId = targetBundleId
		}
		let appLayerActivated = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeProfile?.id == profile.id
					&& self.mappingEngine.state.appActivatedLayerId == appLayer.id
			}
				&& self.controllerService.threadSafeLEDSettings == appLED
		}
		XCTAssertTrue(appLayerActivated, "App-layer LED did not settle")

		await MainActor.run {
			controllerService.buttonPressed(.leftBumper)
		}
		let manualLayerActivated = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeLayerIds == [manualLayer.id]
			}
				&& self.controllerService.threadSafeLEDSettings == profileLED
		}

		await MainActor.run {
			XCTAssertTrue(
				manualLayerActivated,
				"A top manual layer with no LED override must inherit the profile LED, not the app-layer LED"
			)
			controllerService.buttonReleased(.leftBumper)
		}
		let manualLayerReleased = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeLayerIds.isEmpty
			}
				&& self.controllerService.threadSafeLEDSettings == appLED
		}

		XCTAssertTrue(manualLayerReleased, "App-layer LED did not return after releasing the manual layer")
	}

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
		}
		let initialRouteReady = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeProfile?.id == profile.id
					&& self.mappingEngine.state.appActivatedLayerId == firstAppLayer.id
			}
		}
		XCTAssertTrue(initialRouteReady, "Initial app-layer route did not settle")

		await MainActor.run {
			controllerService.buttonPressed(.leftBumper)
		}
		let manualLayerActivated = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeLayerIds == [manualLayer.id]
			}
		}
		XCTAssertTrue(manualLayerActivated, "Manual layer did not activate")

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
		let transitionCompleted = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.appActivatedLayerId == secondAppLayer.id
					&& self.mappingEngine.state.activeLayerIds == [manualLayer.id]
			}
		}
		XCTAssertTrue(transitionCompleted, "Destination app-layer route did not settle")

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
		let releaseCompleted = await waitForCondition {
			self.mappingEngine.state.lock.withLock {
				self.mappingEngine.state.activeLayerIds.isEmpty
					&& self.mappingEngine.state.effectiveActiveLayerIds == [secondAppLayer.id]
			}
		}
		XCTAssertTrue(releaseCompleted, "Manual-layer release did not settle")

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
