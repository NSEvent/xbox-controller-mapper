import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerKeysUXRegressionTests: MappingEngineTestCase {
	func testGuidedPresetStaysActiveInFinderUntilTestEnds() {
		let monitor = AppMonitor()
		monitor.frontmostBundleId = Bundle.main.bundleIdentifier
		let manager = ProfileManager(appMonitor: monitor, configDirectoryOverride: testConfigDirectory.appendingPathComponent("guided-routing"))
		let originalDefault = manager.profiles.first(where: \.isDefault)!
		let preset = GuidedPreset.oneHand.makeProfile(name: "One hand", targetBundleId: nil, linkApp: false)
		let created = manager.createProfile(name: preset.name, basedOn: preset)
		manager.setActiveProfile(created)
		let token = manager.beginGuidedRouting(profileId: created.id)!
		monitor.frontmostBundleId = "com.apple.finder"
		XCTAssertEqual(manager.activeProfileId, created.id)
		manager.endGuidedRouting(token)
		XCTAssertEqual(manager.activeProfileId, originalDefault.id)
	}

	func testDefaultAssignmentMakesOneHandPresetUsableAfterTest() {
		let monitor = AppMonitor()
		monitor.frontmostBundleId = Bundle.main.bundleIdentifier
		let manager = ProfileManager(appMonitor: monitor, configDirectoryOverride: testConfigDirectory.appendingPathComponent("guided-default"))
		let profile = manager.createProfile(name: "One hand", basedOn: GuidedPreset.oneHand.makeProfile(name: "One hand", targetBundleId: nil, linkApp: false))
		manager.setDefaultProfile(profile)
		manager.setActiveProfile(manager.profiles.first { $0.id == profile.id }!)
		monitor.frontmostBundleId = "com.apple.finder"
		XCTAssertEqual(manager.activeProfileId, profile.id)
		XCTAssertEqual(manager.profiles.filter(\.isDefault).count, 1)
	}

	func testGuidedConfirmationRequiresReadyVisitAndInvalidatesOnControllerChange() {
		let session = GuidedPresetTestSession()
		let id = profileManager.activeProfileId!
		controllerService.isConnected = true
		session.start(profileId: id, targetBundleId: "test.target", engine: mappingEngine, accessibility: { true })
		let preview = mappingEngine.beginInputPreview()
		appMonitor.frontmostBundleId = "test.target"
		XCTAssertFalse(session.visitedTarget)
		mappingEngine.endInputPreview(preview)
		appMonitor.frontmostBundleId = "test.before"
		appMonitor.frontmostBundleId = "test.target"
		XCTAssertTrue(session.visitedTarget)
		XCTAssertTrue(session.isReady(profileId: id, engine: mappingEngine, accessibilityGranted: true))
		XCTAssertFalse(session.isReady(profileId: id, engine: mappingEngine, accessibilityGranted: false))
		controllerService.isConnected = true // active controller replacement, not a Boolean transition
		XCTAssertFalse(session.isTesting)
		XCTAssertFalse(session.visitedTarget)
		XCTAssertFalse(session.interruption.isEmpty)
		session.stop()
	}

	func testGuidedSessionDoesNotChangeUserPauseOrLockPreferences() {
		let session = GuidedPresetTestSession()
		mappingEngine.disable()
		mappingEngine.isLocked = true
		controllerService.isConnected = true
		let id = profileManager.activeProfileId!
		session.start(profileId: id, targetBundleId: "test.target", engine: mappingEngine, accessibility: { true })
		appMonitor.frontmostBundleId = "test.target"
		XCTAssertFalse(session.visitedTarget)
		session.stop()
		XCTAssertFalse(mappingEngine.isEnabled)
		XCTAssertTrue(mappingEngine.isLocked)
	}

	func testCalibrationNoOpPreservesDifferentModeDeadzones() {
		var tuning = StickTuning(mode: .mouse)
		tuning.mouseDeadzone = 0.15; tuning.scrollDeadzone = 0.35; tuning.customDeadzone = 0.25
		for mode in [StickMode.mouse, .scroll, .custom] {
			tuning.mode = mode
			let draft = StickCalibrationDraft(tuning: tuning, side: .right)
			XCTAssertFalse(draft.hasChanges)
			XCTAssertEqual(draft.proposed, tuning)
			XCTAssertEqual(draft.inner, StickCalibrationDraft.deadzone(in: tuning, side: .right))
		}
	}

	func testCalibrationChangesOnlySelectedModeUnlessExplicitlyAppliedToAll() {
		var tuning = StickTuning(mode: .mouse); tuning.mode = .scroll
		tuning.mouseDeadzone = 0.15; tuning.scrollDeadzone = 0.35; tuning.customDeadzone = 0.25
		var draft = StickCalibrationDraft(tuning: tuning, side: .right)
		draft.inner = 0.2; draft.outer = 0.8
		XCTAssertEqual(draft.proposed.mouseDeadzone, 0.15)
		XCTAssertEqual(draft.proposed.customDeadzone, 0.25)
		XCTAssertEqual(draft.proposed.scrollDeadzone, 0.25, accuracy: 0.00001)
		XCTAssertEqual(draft.proposed.outerRange, 0.8)
		draft.applyToAllModes = true
		XCTAssertEqual(draft.proposed.mouseDeadzone, 0.25, accuracy: 0.00001)
		XCTAssertEqual(draft.proposed.customDeadzone, 0.25, accuracy: 0.00001)
		draft.inner = 0.9
		XCTAssertFalse(draft.isValid)
	}

	func testCalibrationControllerReplacementDiscardsMeasurementsAndBlocksSave() {
		controllerService.isConnected = true
		let session = StickCalibrationSession()
		session.start(side: .right, controller: controllerService, profiles: profileManager, engine: mappingEngine)
		session.measureRest(now: Date(timeIntervalSince1970: 0))
		session.sample(now: Date(timeIntervalSince1970: 1))
		XCTAssertEqual(session.measurement.restSamples, 1)
		session.draft?.inner = 0.22
		let original = profileManager.activeProfile!.joystickSettings
		controllerService.isConnected = true
		XCTAssertFalse(session.invalidationReason.isEmpty)
		XCTAssertEqual(session.measurement.restSamples, 0)
		XCTAssertFalse(session.canSave)
		XCTAssertFalse(session.save())
		XCTAssertEqual(profileManager.activeProfile!.joystickSettings, original)
		session.start(side: .right, controller: controllerService, profiles: profileManager, engine: mappingEngine)
		XCTAssertTrue(session.invalidationReason.isEmpty)
		XCTAssertEqual(session.draft?.original, original.rightStick)
		session.stop()
	}

	func testCalibrationNoOpSaveAndExternalEditInvalidation() {
		controllerService.isConnected = true
		let session = StickCalibrationSession()
		let original = profileManager.activeProfile!
		session.start(side: .left, controller: controllerService, profiles: profileManager, engine: mappingEngine)
		XCTAssertTrue(session.save())
		XCTAssertEqual(profileManager.activeProfile, original)
		var updated = original.joystickSettings; updated.leftStick.mouseDeadzone = 0.3
		profileManager.updateJoystickSettings(updated, in: original)
		XCTAssertFalse(session.invalidationReason.isEmpty)
		XCTAssertFalse(session.save())
		session.stop()
	}

	func testUnchangedMIDIContinuesThroughAppLayerAndSameProfileEdits() async {
		let config = TriggerMIDIConfiguration(message: MIDIControlChange(channel: 3, controller: 11))
		var settings = JoystickSettings.default
		settings.leftStick.mode = .none; settings.rightStick.mode = .none; settings.rightTriggerMIDI = config
		let layer = Layer(name: "DAW controls", activatorButton: .leftBumper, buttonMappings: [:])
		var profile = Profile(name: "MIDI", buttonMappings: [:], joystickSettings: settings, layers: [layer])
		profile.appLayerBindings["test.daw"] = layer.id
		appMonitor.frontmostBundleId = "test.before"
		profileManager.setActiveProfile(profile)
		controllerService.isConnected = true
		await waitForTasks(0.08)
		controllerService.storage.lock.withLock { controllerService.storage.rightTrigger = 0.7 }
		await waitForTasks(0.08)
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: config.value(for: 0.7))))
		let beforeLayer = mockMIDIService.events.count
		appMonitor.frontmostBundleId = "test.daw"
		await waitForTasks(0.08)
		XCTAssertEqual(mockMIDIService.events.count, beforeLayer)
		profile.name = "Renamed MIDI"
		profileManager.updateProfile(profile)
		controllerService.storage.lock.withLock { controllerService.storage.rightTrigger = 0.8 }
		await waitForTasks(0.08)
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: config.value(for: 0.8))))
		mappingEngine.disable()
		XCTAssertEqual(mockMIDIService.events.last, .press(config.output(value: 0)))
		controllerService.storage.lock.withLock { controllerService.storage.rightTrigger = 0 }
	}

	func testMIDIConfigurationChangeRequiresReleaseButLeavesOtherStreamRunning() async {
		let left = TriggerMIDIConfiguration()
		let right = TriggerMIDIConfiguration(message: MIDIControlChange(controller: 11))
		var settings = JoystickSettings.default
		settings.leftStick.mode = .none; settings.rightStick.mode = .none
		settings.leftTriggerMIDI = left; settings.rightTriggerMIDI = right
		let profile = Profile(name: "Two streams", buttonMappings: [:], joystickSettings: settings)
		profileManager.setActiveProfile(profile); controllerService.isConnected = true
		await waitForTasks(0.08)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0.7; controllerService.storage.rightTrigger = 0.7 }
		await waitForTasks(0.08)
		settings.rightTriggerMIDI?.message.controller = 12
		profileManager.updateJoystickSettings(settings, in: profile)
		await waitForTasks(0.08)
		XCTAssertTrue(mappingEngine.triggerMIDIOutput.snapshot(for: 0)?.armed == true)
		XCTAssertFalse(mappingEngine.triggerMIDIOutput.snapshot(for: 1)?.armed == true)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0.8 }
		await waitForTasks(0.08)
		XCTAssertTrue(mockMIDIService.events.contains(.press(left.output(value: left.value(for: 0.8)))))
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0; controllerService.storage.rightTrigger = 0 }
	}

	func testPreviewSuppressesMIDIAndWaitsForNeutralBeforeResuming() async {
		let config = TriggerMIDIConfiguration()
		var settings = JoystickSettings.default
		settings.leftStick.mode = .none; settings.rightStick.mode = .none; settings.leftTriggerMIDI = config
		profileManager.setActiveProfile(Profile(name: "Preview", buttonMappings: [:], joystickSettings: settings))
		controllerService.isConnected = true
		await waitForTasks(0.08)
		let preview = mappingEngine.beginInputPreview()
		let before = mockMIDIService.events.count
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0.7 }
		await waitForTasks(0.08)
		XCTAssertEqual(mockMIDIService.events.count, before)
		mappingEngine.endInputPreview(preview)
		XCTAssertTrue(mappingEngine.waitingForNeutralInput)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 1)
		controllerService.storage.lock.withLock { controllerService.storage.leftTrigger = 0 }
		await waitForTasks(0.08)
		XCTAssertFalse(mappingEngine.waitingForNeutralInput)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
	}
}

@MainActor
final class WorkflowUXModelTests: XCTestCase {
	func testProgressSurvivesRelaunchAndCompletionRemovesResumeEntry() {
		let suite = "controllerkeys-guided-tests-\(UUID())"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		let profile = Profile(name: "Saved workflow")
		let store = GuidedPresetProgressStore(defaults: defaults)
		store.save(.init(preset: .oneHand, hand: .right, targetBundleId: "com.apple.finder"), for: profile.id)
		let restored = GuidedPresetProgressStore(defaults: defaults)
		XCTAssertEqual(restored.pending(in: [profile]).map(\.id), [profile.id])
		XCTAssertEqual(restored.entries[profile.id.uuidString]?.hand, .right)
		restored.complete(profile.id)
		XCTAssertTrue(restored.pending(in: [profile]).isEmpty)
		XCTAssertTrue(restored.pending(in: []).isEmpty)
	}
	func testOneHandPresetsStayOnChosenSide() {
		let left = GuidedPreset.oneHand.makeProfile(name: "Left", targetBundleId: nil, linkApp: false, hand: .left)
		let right = GuidedPreset.oneHand.makeProfile(name: "Right", targetBundleId: nil, linkApp: false, hand: .right)
		XCTAssertEqual(left.joystickSettings.rightStick.mode, .none)
		XCTAssertNil(left.buttonMappings[.rightBumper]); XCTAssertNil(left.buttonMappings[.a])
		XCTAssertEqual(left.buttonMappings[.leftBumper]?.keyCode, 0xF000)
		XCTAssertEqual(right.joystickSettings.leftStick.mode, .none)
		XCTAssertEqual(right.joystickSettings.rightStick.mode, .mouse)
		XCTAssertNil(right.buttonMappings[.leftBumper])
		XCTAssertEqual(right.buttonMappings[.rightBumper]?.keyCode, 0xF000)
	}
	func testWorkflowLabelsFollowDisconnectedPreview() {
		let controller = ControllerService(enableHardwareMonitoring: false)
		defer { controller.cleanup() }
		var profile = Profile(name: "Preview")
		profile.controllerPreviewLayout = .dualSense
		let descriptor = ControllerVisualDescriptor.inputWorkflow(profile: profile, using: controller)
		XCTAssertTrue(descriptor.isPlayStation)
		XCTAssertEqual(descriptor.buttonLabel(.a), ControllerButton.a.displayName(forDualSense: true))
		profile.controllerPreviewLayout = .nintendo
		XCTAssertTrue(ControllerVisualDescriptor.inputWorkflow(profile: profile, using: controller).isNintendo)
	}

	func testSecondTriggerDefaultsToDifferentCC() {
		let left = TriggerMIDIConfiguration.suggested(for: .left, avoiding: nil)
		let right = TriggerMIDIConfiguration.suggested(for: .right, avoiding: left)
		XCTAssertNotEqual(left.message.controller, right.message.controller)
		let collision = TriggerMIDIConfiguration(message: MIDIControlChange(controller: 11))
		XCTAssertEqual(TriggerMIDIConfiguration.suggested(for: .right, avoiding: collision).message.controller, 12)
	}
	func testConflictInventoryIncludesMappingsLayersChordsSequencesAndPrecision() {
		var settings = JoystickSettings.default; settings.analogPrecisionTriggerMode = .right
		let layer = Layer(name: "Layer", activatorButton: .rightTrigger, buttonMappings: [.rightTrigger: KeyMapping(keyCode: 49)])
		let profile = Profile(name: "Conflicts", buttonMappings: [.rightTrigger: KeyMapping(keyCode: 36)],
							  chordMappings: [ChordMapping(buttons: [.rightTrigger, .a], keyCode: 49)],
							  sequenceMappings: [SequenceMapping(steps: [.rightTrigger, .a], keyCode: 49)], joystickSettings: settings, layers: [layer])
		XCTAssertEqual(TriggerMIDIConflict.find(in: profile, side: .right).count, 6)
		XCTAssertTrue(TriggerMIDIConflict.find(in: profile, side: .left).isEmpty)
	}
}
