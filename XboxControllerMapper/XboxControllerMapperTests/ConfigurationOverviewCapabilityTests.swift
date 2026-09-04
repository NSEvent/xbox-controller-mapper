import XCTest
@testable import ControllerKeys

final class ConfigurationOverviewCapabilityTests: XCTestCase {
	func testSteamMotionGesturesAreCurrent() {
		let profile = Profile(
			name: "Steam",
			gestureMappings: [GestureMapping(gestureType: .tiltBack, keyCode: KeyCodeMapping.space)]
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .steam))
		)

		XCTAssertEqual(snapshot.advancedTriggerCount, 1)
		XCTAssertTrue(snapshot.rows.first { $0.category == .triggers }?.isCurrentDevice == true)
	}

	func testInactiveTouchpadAndStickModesMoveSavedBindingsToOtherDeviceSection() throws {
		var joystickSettings = JoystickSettings()
		joystickSettings.leftStick.mode = .mouse
		let profile = Profile(
			name: "Modes",
			buttonMappings: [
				.touchpadRegionTopLeftClick: .key(KeyCodeMapping.space),
				.touchpadButton: .key(KeyCodeMapping.return),
				.leftStickUp: .key(KeyCodeMapping.escape),
			],
			joystickSettings: joystickSettings,
			touchpadInputMode: .wholePad
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .dualSense))
		)

		XCTAssertTrue(try row(for: .touchpadButton, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .touchpadRegionTopLeftClick, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .leftStickUp, in: snapshot).isCurrentDevice)
	}

	func testUnsupportedLayerStickAndWheelSettingsRemainAuditable() throws {
		let layer = Layer(
			name: "Desktop",
			rightStickTuning: StickTuningOverride(mode: .custom),
			commandWheelActions: [CommandWheelAction(displayName: "Search", keyCode: KeyCodeMapping.space)]
		)
		let profile = Profile(name: "Ring", layers: [layer])
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: presentation(for: ControllerVisualDescriptor(family: .ouraRing))
		)

		let stick = try XCTUnwrap(snapshot.rows.first { $0.id == "layer-stick-right" })
		XCTAssertFalse(stick.isCurrentDevice)
		XCTAssertTrue(stick.detail?.contains("Not available on Oura Ring") == true)
		let wheel = try XCTUnwrap(snapshot.rows.first { $0.category == .wheel })
		XCTAssertFalse(wheel.isCurrentDevice)
		XCTAssertEqual(snapshot.commandWheelCount, 0)
	}

	func testElitePaddleAliasesOnlyCountTheRuntimeReachableIdentity() throws {
		let profile = Profile(
			name: "Elite",
			buttonMappings: [
				.xboxPaddle1: .key(KeyCodeMapping.escape),
				.leftPaddle: .key(KeyCodeMapping.return),
				.share: .key(KeyCodeMapping.space),
			]
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .xboxElite))
		)

		XCTAssertTrue(try row(for: .xboxPaddle1, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .leftPaddle, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .share, in: snapshot).isCurrentDevice)
	}

	func testSelectedLayerStickModesDetermineChordAndSequenceAvailability() throws {
		var settings = JoystickSettings.default
		settings.leftStick.mode = .custom
		settings.rightStick.mode = .mouse
		let layer = Layer(
			name: "Alternate Modes",
			leftStickTuning: StickTuningOverride(mode: .mouse),
			rightStickTuning: StickTuningOverride(mode: .custom)
		)
		let chord = ChordMapping(
			buttons: [.leftStickUp, .a],
			keyCode: KeyCodeMapping.escape
		)
		let sequence = SequenceMapping(
			steps: [.rightStickUp, .b],
			keyCode: KeyCodeMapping.return
		)
		let profile = Profile(
			name: "Layer Modes",
			chordMappings: [chord],
			sequenceMappings: [sequence],
			joystickSettings: settings,
			layers: [layer]
		)
		let presentation = presentation(for: ControllerVisualDescriptor(family: .xbox))

		let base = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation
		)
		let selected = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: presentation
		)

		XCTAssertTrue(try XCTUnwrap(base.rows.first { $0.id == "chord-\(chord.id.uuidString)" }).isCurrentDevice)
		XCTAssertFalse(try XCTUnwrap(base.rows.first { $0.id == "sequence-\(sequence.id.uuidString)" }).isCurrentDevice)
		XCTAssertFalse(try XCTUnwrap(selected.rows.first { $0.id == "chord-\(chord.id.uuidString)" }).isCurrentDevice)
		XCTAssertTrue(try XCTUnwrap(selected.rows.first { $0.id == "sequence-\(sequence.id.uuidString)" }).isCurrentDevice)
	}

	func testDuplicateLayerActivatorsUseRuntimeLastWinsSemanticsWithoutTrapping() throws {
		let first = Layer(name: "First", activatorButton: .leftBumper)
		let second = Layer(name: "Second", activatorButton: .leftBumper)
		let profile = Profile(
			name: "Imported Duplicate",
			buttonMappings: [.xboxPaddle1: .key(KeyCodeMapping.escape)],
			layers: [first, second]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .xboxElite))
		)

		let activator = try XCTUnwrap(snapshot.rows.first { row in
			if case .layer = row.target { return row.trigger == "LB" }
			return false
		})
		XCTAssertEqual(activator.target, .layer(second.id))
		XCTAssertTrue(try row(for: .xboxPaddle1, in: snapshot).isCurrentDevice)

		let shadowed = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: first.id,
			presentation: presentation(for: ControllerVisualDescriptor(family: .xboxElite))
		)
		XCTAssertEqual(
			try XCTUnwrap(shadowed.rows.first { $0.id == "layer-activator-\(first.id.uuidString)" }).action,
			String(format: String(localized: "Overridden by layer %@"), second.name)
		)
		XCTAssertEqual(
			try row(for: .xboxPaddle1, in: shadowed).source,
			.inherited
		)
	}

	func testAppleTVUsesRuntimeWholePadAndTreatsSavedTriggerTuningAsUnavailable() throws {
		var settings = JoystickSettings.default
		settings.analogPrecisionTriggerMode = .left
		let profile = Profile(
			name: "Mixed Apple TV",
			buttonMappings: [
				.touchpadButton: .key(KeyCodeMapping.return),
				.touchpadTap: .key(KeyCodeMapping.space),
				.touchpadRegionTopLeftClick: .key(KeyCodeMapping.escape),
			],
			joystickSettings: settings,
			touchpadInputMode: .quadrants
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .appleTVRemote))
		)

		XCTAssertTrue(try row(for: .touchpadButton, in: snapshot).isCurrentDevice)
		XCTAssertTrue(try row(for: .touchpadTap, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .touchpadRegionTopLeftClick, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try XCTUnwrap(snapshot.rows.first { $0.id == "analog-precision" }).isCurrentDevice)
	}

	func testEightBitDoMicroStarAndStickSettingsAreUnavailable() throws {
		var settings = JoystickSettings.default
		settings.leftStick.mode = .custom
		let profile = Profile(
			name: "Micro",
			buttonMappings: [.share: .key(KeyCodeMapping.escape)],
			joystickSettings: settings
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .eightBitDo(.micro)))
		)

		XCTAssertFalse(try row(for: .share, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try XCTUnwrap(snapshot.rows.first { $0.id == "base-stick-left" }).isCurrentDevice)
	}

	func testLEDDetailDoesNotClaimUnsupportedPlayerOrMuteLEDState() throws {
		var presentation = presentation(for: ControllerVisualDescriptor(family: .dualSense))
		presentation.supportsPlayerAndMuteLEDs = false
		let settings = DualSenseLEDSettings(
			lightBarColor: CodableColor(red: 1, green: 0, blue: 0),
			lightBarBrightness: .dim,
			muteButtonLED: .breathing,
			playerLEDs: .player3
		)
		let profile = Profile(name: "Bluetooth DualSense", dualSenseLEDSettings: settings)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation
		)
		let led = try XCTUnwrap(snapshot.rows.first { $0.id.hasPrefix("led-") })

		XCTAssertFalse(try XCTUnwrap(led.detail).contains("player LEDs"))
		XCTAssertFalse(try XCTUnwrap(led.detail).contains("mute Breathing"))
		XCTAssertTrue(try XCTUnwrap(led.detail).contains(
			String(localized: "Player and mute LEDs unavailable over Bluetooth")
		))
	}

	private func row(
		for button: ControllerButton,
		in snapshot: ConfigurationOverviewSnapshot
	) throws -> ConfigurationOverviewRow {
		try XCTUnwrap(snapshot.rows.first { row in
			guard case .button(let candidate, _) = row.target else { return false }
			return candidate == button
		})
	}

	private func presentation(
		for descriptor: ControllerVisualDescriptor,
		hasMotion: Bool = false
	) -> ConfigurationOverviewPresentation {
		ConfigurationOverviewPresentation(
			isPlayStation: descriptor.isPlayStation,
			isDualSense: descriptor.isDualSense,
			isDualSenseEdge: descriptor.isDualSenseEdge,
			isDualShock: descriptor.isDualShock,
			isXboxElite: descriptor.isXboxElite,
			isSteamController: descriptor.isSteamController,
			isNintendo: descriptor.isNintendo,
			isAppleTVRemote: descriptor.isAppleTVRemote,
			isEightBitDo: descriptor.eightBitDoModel != nil,
			isOuraRing: descriptor.isOuraRing,
			isBeamdeskHands: descriptor.isBeamdeskHands,
			isStickless: descriptor.isStickless,
			hasTriggers: descriptor.hasTriggers,
			hasMotion: hasMotion || descriptor.supportsMotionGestures,
			supportsCommandWheel: descriptor.supportsCommandWheel,
			supportsPlayerAndMuteLEDs: descriptor.isDualSense,
			supportedButtons: descriptor.supportedButtons,
			deviceName: descriptor.displayName
		)
	}
}
