import XCTest
import TriggerKitCore
@testable import ControllerKeys

final class ConfigurationOverviewSnapshotTests: XCTestCase {
	func testUnavailableOnlyStateAppearsOnlyWithoutCurrentDeviceRowsOrSearch() {
		let unsupported = ConfigurationOverviewRow(
			id: "unsupported",
			category: .wheel,
			trigger: "Slot 1",
			action: "Open App",
			detail: nil,
			source: .profile,
			systemImage: "circle",
			target: .section(MainWindowSection.wheel.rawValue),
			isCurrentDevice: false
		)
		let current = ConfigurationOverviewRow(
			id: "current",
			category: .wheel,
			trigger: "Slot 2",
			action: "Press Space",
			detail: nil,
			source: .profile,
			systemImage: "circle",
			target: .section(MainWindowSection.wheel.rawValue),
			isCurrentDevice: true
		)

		XCTAssertTrue(ConfigurationOverviewEmptyStatePolicy.showsUnavailableOnlyState(
			rows: [unsupported],
			query: ""
		))
		XCTAssertFalse(ConfigurationOverviewEmptyStatePolicy.showsUnavailableOnlyState(
			rows: [unsupported, current],
			query: ""
		))
		XCTAssertFalse(ConfigurationOverviewEmptyStatePolicy.showsUnavailableOnlyState(
			rows: [unsupported],
			query: "slot"
		))
	}

	func testSelectedLayerMakesOverridesAndInheritanceExplicit() throws {
		let layer = Layer(
			name: "Editing",
			activatorButton: .leftBumper,
			activationStyle: .hold,
			buttonMappings: [.a: .key(KeyCodeMapping.escape)]
		)
		let profile = Profile(
			name: "Work",
			buttonMappings: [
				.a: .key(KeyCodeMapping.return),
				.b: .key(KeyCodeMapping.space)
			],
			layers: [layer]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(snapshot.scopeName, "Editing")
		XCTAssertEqual(snapshot.layer?.overrideCount, 1)
		XCTAssertEqual(try row(for: .a, in: snapshot).source, .override)
		XCTAssertEqual(try row(for: .a, in: snapshot).target, .button(.a, layerId: layer.id))
		XCTAssertEqual(try row(for: .b, in: snapshot).source, .inherited)
		XCTAssertEqual(try row(for: .b, in: snapshot).target, .button(.b, layerId: layer.id))
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.target == .layer(layer.id) }).source,
			.profile
		)
		XCTAssertEqual(snapshot.mappedControlCount, 2)
		XCTAssertEqual(snapshot.configuredControlCount, 3)
	}

	func testSnapshotIncludesConfiguredTriggersAndAutomationLibrary() {
		let chord = ChordMapping(
			buttons: [.a, .b],
			keyCode: KeyCodeMapping.escape,
			hint: "Close Window"
		)
		let emptySequence = SequenceMapping(steps: [.a, .b])
		let profile = Profile(
			name: "Work",
			chordMappings: [chord],
			sequenceMappings: [emptySequence],
			macros: [Macro(name: "Morning Setup", steps: [.delay(0.1)])],
			scripts: [Script(name: "Arrange Windows", source: "")]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(snapshot.advancedTriggerCount, 1)
		XCTAssertEqual(snapshot.automationCount, 2)
		XCTAssertTrue(snapshot.rows.contains { $0.action == "Close Window" })
		XCTAssertTrue(snapshot.rows.contains { $0.trigger == "Morning Setup" })
		XCTAssertTrue(snapshot.rows.contains { $0.trigger == "Arrange Windows" })
		XCTAssertTrue(snapshot.rows.filter { $0.category == .automations }.allSatisfy { $0.source == .profile })
		XCTAssertTrue(snapshot.rows.first { $0.action == "Close Window" }?.detail?.contains(KeyMapping.key(KeyCodeMapping.escape).displayString) == true)
	}

	func testAutomationRowsGiveBlankNamesReadableFallbacks() {
		let profile = Profile(
			name: "Work",
			macros: [Macro(name: "   ")],
			scripts: [Script(name: "\n", source: "")]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertTrue(snapshot.rows.contains { $0.trigger == "Unnamed Macro" })
		XCTAssertTrue(snapshot.rows.contains { $0.trigger == "Untitled Script" })
	}

	func testAlternateOnlyMappingsRemainVisibleAndOverrideBase() throws {
		let layer = Layer(
			name: "Alternate",
			buttonMappings: [
				.a: KeyMapping(doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.escape))
			]
		)
		let profile = Profile(
			name: "Work",
			buttonMappings: [
				.a: .key(KeyCodeMapping.return),
				.b: KeyMapping(longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.space))
			],
			layers: [layer]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(try row(for: .a, in: snapshot).source, .override)
		XCTAssertEqual(
			try row(for: .a, in: snapshot).action,
			String(format: String(localized: "Double tap only: %@"), KeyMapping.key(KeyCodeMapping.escape).displayString)
		)
		XCTAssertNotEqual(try row(for: .a, in: snapshot).action, "None")
		XCTAssertTrue(try row(for: .a, in: snapshot).detail?.contains("Double tap") == true)
		XCTAssertEqual(try row(for: .b, in: snapshot).source, .inherited)
		XCTAssertEqual(
			try row(for: .b, in: snapshot).action,
			String(format: String(localized: "Hold only: %@"), KeyMapping.key(KeyCodeMapping.space).displayString)
		)
		XCTAssertTrue(try row(for: .b, in: snapshot).detail?.contains("Hold") == true)
	}

	func testCurrentDeviceMappingsAreSeparatedFromOtherHardware() {
		let profile = Profile(
			name: "Mixed",
			buttonMappings: [
				.a: .key(KeyCodeMapping.return),
				.touchpadButton: .key(KeyCodeMapping.space),
				.ouraTap: .key(KeyCodeMapping.escape)
			]
		)

		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(snapshot.mappedControlCount, 1)
		XCTAssertEqual(snapshot.configuredControlCount, 1)
		XCTAssertEqual(
			snapshot.rows.filter { $0.category == .controls && !$0.isCurrentDevice }.count,
			2
		)
	}

	func testCanonicalControllerCapabilitiesHideControlsAbsentFromEightBitDoZero2() throws {
		let descriptor = ControllerVisualDescriptor(family: .eightBitDo(.zero2))
		let profile = Profile(
			name: "Tiny",
			buttonMappings: [
				.a: .key(KeyCodeMapping.return),
				.share: .key(KeyCodeMapping.space),
				.xbox: .key(KeyCodeMapping.escape),
				.leftTrigger: .key(KeyCodeMapping.tab)
			]
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: descriptor)
		)

		XCTAssertTrue(try row(for: .a, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .share, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .xbox, in: snapshot).isCurrentDevice)
		XCTAssertFalse(try row(for: .leftTrigger, in: snapshot).isCurrentDevice)
		XCTAssertEqual(snapshot.mappedControlCount, 1)
		XCTAssertEqual(
			snapshot.rows.filter { $0.category == .controls && !$0.isCurrentDevice }.count,
			3
		)
	}

	func testUnsupportedAdvancedTriggersAreSeparatedFromCurrentDeviceCounts() {
		let profile = Profile(
			name: "Mixed",
			chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: KeyCodeMapping.escape)],
			sequenceMappings: [SequenceMapping(steps: [.a, .b], keyCode: KeyCodeMapping.return)],
			gestureMappings: [GestureMapping(gestureType: .tiltBack, keyCode: KeyCodeMapping.space)]
		)
		let descriptor = ControllerVisualDescriptor(family: .ouraRing)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: descriptor)
		)

		XCTAssertEqual(snapshot.advancedTriggerCount, 0)
		XCTAssertEqual(snapshot.rows.filter { $0.category == .triggers && !$0.isCurrentDevice }.count, 3)
		XCTAssertTrue(snapshot.rows.filter { $0.category == .triggers }.allSatisfy {
			$0.detail?.contains("Not available on Oura Ring") == true
		})
	}

	func testActionSummaryUsesExecutorPrecedence() throws {
		let macroId = UUID()
		let command = SystemCommand.openLink(url: "https://example.com")
		let profile = Profile(
			name: "Conflicts",
			buttonMappings: [.a: KeyMapping(
				keyCode: KeyCodeMapping.return,
				macroId: macroId,
				systemCommand: command
			)],
			macros: [Macro(id: macroId, name: "Dormant Macro")]
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(try row(for: .a, in: snapshot).action, command.displayName)
		XCTAssertNotEqual(try row(for: .a, in: snapshot).action, "Dormant Macro")
	}

	func testCommandWheelAndNonButtonLayerConfigurationAreVisible() {
		let layer = Layer(name: "Apps", commandWheelActions: [])
		let profile = Profile(
			name: "Work",
			appLayerBindings: ["com.example.editor": layer.id],
			layers: [layer],
			commandWheelActions: [CommandWheelAction(displayName: "Search", keyCode: KeyCodeMapping.space)]
		)

		let base = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation()
		)
		let selected = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: ConfigurationOverviewPresentation()
		)

		XCTAssertEqual(base.commandWheelCount, 1)
		XCTAssertEqual(selected.commandWheelCount, 0)
		XCTAssertEqual(selected.layer?.overrideCount, 2)
		XCTAssertTrue(selected.layer?.overrideDetails.contains("wheel disabled") == true)
		XCTAssertTrue(selected.layer?.overrideDetails.contains("1 linked apps") == true)
		XCTAssertEqual(selected.rows.first { $0.category == .wheel }?.target, .wheel(layerId: layer.id))
		XCTAssertEqual(
			selected.rows.first { $0.id == "layer-apps-\(layer.id.uuidString)" }?.target,
			.layerLinkedApps(profileId: profile.id, layerId: layer.id)
		)
	}

	func testSelectedLayerSettingsRouteBackToThatLayerScope() throws {
		let layer = Layer(
			name: "Precision",
			dualSenseLEDSettings: .default,
			leftStickTuning: StickTuningOverride(mouseSensitivity: 0.2),
			commandWheelActions: [CommandWheelAction(displayName: "Search", keyCode: KeyCodeMapping.space)]
		)
		let profile = Profile(name: "Work", layers: [layer])
		let descriptor = ControllerVisualDescriptor(family: .dualSense)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: layer.id,
			presentation: presentation(for: descriptor, hasMotion: true)
		)

		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id == "layer-stick-left" }).target,
			.joysticks(layerId: layer.id, side: .left)
		)
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.category == .wheel }).target,
			.wheel(layerId: layer.id)
		)
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id.hasPrefix("led-") }).target,
			.layerLED(layer.id)
		)
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id == "layer-apps-\(layer.id.uuidString)" }).target,
			.layerLinkedApps(profileId: profile.id, layerId: layer.id)
		)
	}

	func testAutomationInventoryOnlyIncludesProfileOwnedAndReferencedSharedMacros() throws {
		let liveId = UUID()
		let orphanId = UUID()
		let profile = Profile(
			name: "Work",
			buttonMappings: [.a: KeyMapping(macroId: liveId)],
			sharedMacroSnapshots: [
				liveId: AutomationProgram(name: "Saved Live"),
				orphanId: AutomationProgram(name: "Portable Fallback")
			]
		)
		let live = AutomationMacro(
			id: liveId,
			name: "Current Library Name",
			program: AutomationProgram(name: "Current Library Name")
		)
		let unrelated = AutomationMacro(
			name: "Unrelated",
			program: AutomationProgram(name: "Unrelated")
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: ConfigurationOverviewPresentation(),
			sharedLibraryMacros: [live, unrelated]
		)

		let automationRows = snapshot.rows.filter { $0.category == .automations }
		XCTAssertEqual(automationRows.count, 2)
		XCTAssertEqual(snapshot.automationCount, ConfigurationOverviewBuilder.counts(for: profile).automationCount)
		XCTAssertEqual(try XCTUnwrap(automationRows.first { $0.trigger == "Current Library Name" }).source, .library)
		XCTAssertEqual(try XCTUnwrap(automationRows.first { $0.trigger == "Portable Fallback" }).source, .profile)
		XCTAssertFalse(automationRows.contains { $0.trigger == "Unrelated" })
		XCTAssertEqual(try row(for: .a, in: snapshot).action, "Current Library Name")
	}

	func testBaseInventorySurfacesEveryProfileSettingsFamily() throws {
		var keyboard = OnScreenKeyboardSettings()
		keyboard.quickTexts = [QuickText(text: "hello")]
		var joystickSettings = JoystickSettings.default
		joystickSettings.ouraMotion.enabled = true
		joystickSettings.appleTVRemoteCircularScrollEnabled = false
		let identity = ControllerIdentity(
			stableId: "controller-1",
			fallbackId: "fallback",
			vendorId: 1,
			productId: 2,
			productName: "Desk Pad",
			transport: "Bluetooth",
			serialNumber: nil,
			deviceAddress: nil
		)
		let profile = Profile(
			name: "Complete",
			controllerPreviewLayout: .dualSense,
			joystickSettings: joystickSettings,
			linkedApps: ["com.example.editor"],
			linkedControllers: [ControllerProfileBinding(displayName: "Desk Pad", identity: identity)],
			inputLatencyMode: .realtime,
			onScreenKeyboardSettings: keyboard,
			touchpadRegionTriggerModes: [.touchpadRegionTopLeftClick: .touch],
			touchpadInputMode: .quadrants
		)
		let snapshot = ConfigurationOverviewBuilder.make(
			profile: profile,
			selectedLayerId: nil,
			presentation: presentation(for: ControllerVisualDescriptor(family: .dualSense), hasMotion: true)
		)
		let ids = Set(snapshot.rows.filter { $0.category == .settings }.map(\.id))

		XCTAssertTrue([
			"dpad-preset", "preview-layout", "input-latency", "keyboard-settings",
			"profile-app-links", "profile-controller-links", "touchpad-mode",
			"legacy-touchpad-trigger-modes", "base-stick-left", "base-stick-right",
			"focus-mode", "analog-precision", "pointer-lock", "scroll-boost",
			"touchpad-cursor", "motion-gesture-tuning", "gyro-aiming",
			"oura-motion", "apple-tv-edge-input", "led-Base"
		].allSatisfy(ids.contains))
		XCTAssertEqual(try XCTUnwrap(snapshot.rows.first { $0.id == "keyboard-settings" }).detail, "1 quick texts · 0 apps · 0 websites")
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id == "profile-app-links" }).target,
			.linkedApps(profileId: profile.id)
		)
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id == "profile-controller-links" }).target,
			.linkedControllers(profileId: profile.id)
		)
		XCTAssertEqual(
			try XCTUnwrap(snapshot.rows.first { $0.id == "touchpad-mode" }).target,
			.section(MainWindowSection.buttons.rawValue)
		)
	}

	func testProfileCountsExcludeEmptyActionsAndIncludeEveryConfigurationFamily() {
		let layer = Layer(
			name: "Editing",
			buttonMappings: [
				.a: .key(KeyCodeMapping.escape),
				.b: KeyMapping()
			]
		)
		let profile = Profile(
			name: "Work",
			buttonMappings: [
				.a: .key(KeyCodeMapping.return),
				.b: KeyMapping()
			],
			chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: KeyCodeMapping.escape)],
			sequenceMappings: [SequenceMapping(steps: [.a, .b])],
			macros: [Macro(name: "One")],
			scripts: [Script(name: "Two")],
			layers: [layer]
		)

		let counts = ConfigurationOverviewBuilder.counts(for: profile)

		XCTAssertEqual(counts.baseControlCount, 1)
		XCTAssertEqual(counts.layerOverrideCount, 1)
		XCTAssertEqual(counts.advancedTriggerCount, 1)
		XCTAssertEqual(counts.automationCount, 2)
		XCTAssertEqual(counts.layerCount, 1)
	}

	func testFilteringSearchesSourceAndAction() {
		let rows = [
			ConfigurationOverviewRow(
				id: "one",
				category: .controls,
				trigger: "A",
				action: "Open Search",
				detail: nil,
				source: .override,
				systemImage: "button.programmable",
				target: .button(.a, layerId: nil),
				isCurrentDevice: true
			)
		]

		XCTAssertEqual(ConfigurationOverviewBuilder.filteredRows(rows, category: nil, query: "search").count, 1)
		XCTAssertEqual(ConfigurationOverviewBuilder.filteredRows(rows, category: nil, query: "override").count, 1)
		XCTAssertTrue(ConfigurationOverviewBuilder.filteredRows(rows, category: .triggers, query: "").isEmpty)
		XCTAssertTrue(rows[0].accessibilitySummary.contains("Open Search"))
		XCTAssertTrue(rows[0].accessibilitySummary.contains("Override"))
	}

	func testEmptyCategoryActionsOpenTheRelevantEditor() {
		XCTAssertEqual(
			ConfigurationOverviewFilter.controls.emptyConfiguration.target,
			.section(MainWindowSection.buttons.rawValue)
		)
		XCTAssertEqual(
			ConfigurationOverviewFilter.triggers.emptyConfiguration.target,
			.section(MainWindowSection.chords.rawValue)
		)
		XCTAssertEqual(
			ConfigurationOverviewFilter.wheel.emptyConfiguration.target,
			.section(MainWindowSection.wheel.rawValue)
		)
		XCTAssertEqual(
			ConfigurationOverviewFilter.automations.emptyConfiguration.target,
			.section(MainWindowSection.macros.rawValue)
		)
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
			supportedButtons: descriptor.supportedButtons,
			deviceName: descriptor.displayName
		)
	}
}
