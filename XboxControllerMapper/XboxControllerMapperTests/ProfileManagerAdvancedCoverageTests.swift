import XCTest
import CoreGraphics
@testable import ControllerKeys

@MainActor
final class ProfileManagerAdvancedCoverageTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
    }

    override func tearDown() async throws {
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    func testSetMappingAndMoveChordsMutateActiveProfile() {
        let mapping = KeyMapping(keyCode: 12)
        profileManager.setMapping(mapping, for: .a)
        XCTAssertEqual(profileManager.getMapping(for: .a), mapping)

        let baselineCount = profileManager.activeProfile?.chordMappings.count ?? 0
        let chordA = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let chordB = ChordMapping(buttons: [.x, .y], keyCode: 1)
        let chordC = ChordMapping(buttons: [.dpadUp, .dpadDown], keyCode: 2)

        profileManager.addChord(chordA)
        profileManager.addChord(chordB)
        profileManager.addChord(chordC)
        profileManager.moveChords(from: IndexSet(integer: baselineCount), to: baselineCount + 3)

        let trailingIds = Array((profileManager.activeProfile?.chordMappings.map(\.id) ?? []).suffix(3))
        XCTAssertEqual(trailingIds, [chordB.id, chordC.id, chordA.id])
    }

	func testEditingFourthDPadArrowMappingKeepsPresetCustom() {
		let profile = Profile(name: "Manual D-pad")
		profileManager.profiles = [profile]
		profileManager.setActiveProfile(profile)

		let arrowMappings: [(ControllerButton, CGKeyCode)] = [
			(.dpadUp, KeyCodeMapping.upArrow),
			(.dpadLeft, KeyCodeMapping.leftArrow),
			(.dpadRight, KeyCodeMapping.rightArrow),
			(.dpadDown, KeyCodeMapping.downArrow)
		]
		for (button, keyCode) in arrowMappings {
			profileManager.setMapping(
				KeyMapping(
					keyCode: keyCode,
					repeatMapping: RepeatMapping(enabled: true, interval: 0.1)
				),
				for: button
			)
		}

		XCTAssertEqual(profileManager.activeProfile?.dpadPreset, .custom)
		XCTAssertFalse(profileManager.activeProfile?.dpadPresetWasExplicitlySelected ?? true)
		XCTAssertTrue(
			arrowMappings.allSatisfy { button, _ in
				profileManager.getMapping(for: button)?.repeatMapping?.enabled == true
			}
		)
	}

	func testDPadPresetPickerRetainsExplicitPreset() {
		let profile = Profile(name: "Preset D-pad")
		profileManager.profiles = [profile]
		profileManager.setActiveProfile(profile)

		profileManager.setDPadPreset(.arrows)

		XCTAssertEqual(profileManager.activeProfile?.dpadPreset, .arrows)
		XCTAssertTrue(profileManager.activeProfile?.dpadPresetWasExplicitlySelected ?? false)
		XCTAssertEqual(
			profileManager.getMapping(for: .dpadDown)?.keyCode,
			KeyCodeMapping.downArrow
		)
	}

	func testControllerPreviewLayoutPersistsPerProfile() {
		let first = Profile(name: "DS4", controllerPreviewLayout: .dualShock)
		let second = Profile(name: "Micro", controllerPreviewLayout: .eightBitDoMicro)
		profileManager.profiles = [first, second]

		profileManager.setActiveProfile(first)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .dualShock)

		profileManager.setControllerPreviewLayout(.dualSense)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .dualSense)

		profileManager.setActiveProfile(second)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .eightBitDoMicro)

		let updatedFirst = profileManager.profiles.first(where: { $0.id == first.id })
		XCTAssertEqual(updatedFirst?.controllerPreviewLayout, .dualSense)
	}

	func testMoveProfilesReordersAndPersistsWithoutChangingActiveProfile() {
		let first = Profile(name: "First")
		let second = Profile(name: "Second", isDefault: true)
		let third = Profile(name: "Third")
		profileManager.profiles = [first, second, third]
		profileManager.setActiveProfile(second)

		profileManager.moveProfiles(from: IndexSet(integer: 0), to: 3)

		XCTAssertEqual(profileManager.profiles.map(\.id), [second.id, third.id, first.id])
		XCTAssertEqual(profileManager.activeProfileId, second.id)
		XCTAssertEqual(profileManager.activeProfile?.id, second.id)
		XCTAssertEqual(profileManager.profiles.first(where: { $0.isDefault })?.id, second.id)

		profileManager.flushPendingSaves()
		let reloadedManager = ProfileManager(configDirectoryOverride: testConfigDirectory)

		XCTAssertEqual(reloadedManager.profiles.map(\.id), [second.id, third.id, first.id])
		XCTAssertEqual(reloadedManager.activeProfileId, second.id)
	}

    func testLayerCreationActivatorRulesAndQueries() {
        let first = profileManager.createLayer(name: "Layer 1", activatorButton: .leftBumper)
        XCTAssertNotNil(first)

        let duplicateActivator = profileManager.createLayer(name: "Duplicate", activatorButton: .leftBumper)
        XCTAssertNil(duplicateActivator)

        guard let second = profileManager.createLayer(name: "Layer 2") else {
            return XCTFail("Expected second layer")
        }

        XCTAssertEqual(profileManager.layerForActivator(.leftBumper)?.id, first?.id)
        XCTAssertEqual(profileManager.unassignedLayers().map(\.id), [second.id])

        profileManager.renameLayer(second, to: "Layer 2 Renamed")
        let renamed = profileManager.activeProfile?.layers.first(where: { $0.id == second.id })
        XCTAssertEqual(renamed?.name, "Layer 2 Renamed")

        guard let currentSecond = renamed else {
            return XCTFail("Expected renamed layer")
        }
        XCTAssertTrue(profileManager.setLayerActivator(currentSecond, button: .rightBumper))

        guard let currentFirst = first else {
            return XCTFail("Expected first layer")
        }
        XCTAssertFalse(profileManager.setLayerActivator(currentFirst, button: .rightBumper))
        XCTAssertTrue(profileManager.setLayerActivator(currentSecond, button: nil))
        XCTAssertEqual(Set(profileManager.unassignedLayers().map(\.id)), Set([currentSecond.id]))
    }

    func testLayerMappingUpdateAndDelete() {
        guard let layer = profileManager.createLayer(name: "Mappings") else {
            return XCTFail("Expected layer")
        }
        let mapping = KeyMapping(keyCode: 6)

        profileManager.setLayerMapping(mapping, for: .x, in: layer)
        let stored = profileManager.activeProfile?.layers
            .first(where: { $0.id == layer.id })?
            .buttonMappings[.x]
        XCTAssertEqual(stored, mapping)

        profileManager.removeLayerMapping(for: .x, from: layer)
        let removed = profileManager.activeProfile?.layers
            .first(where: { $0.id == layer.id })?
            .buttonMappings[.x]
        XCTAssertNil(removed)

        var updatedLayer = layer
        updatedLayer.name = "Updated Layer"
        profileManager.updateLayer(updatedLayer)
        XCTAssertEqual(
            profileManager.activeProfile?.layers.first(where: { $0.id == layer.id })?.name,
            "Updated Layer"
        )

		guard let activeProfile = profileManager.activeProfile else {
			return XCTFail("Expected active profile")
		}
		XCTAssertEqual(
			profileManager.linkApp("com.example.layer", toLayer: layer.id, in: activeProfile),
			.linked
		)

        profileManager.deleteLayer(updatedLayer)
        XCTAssertFalse(profileManager.activeProfile?.layers.contains(where: { $0.id == layer.id }) ?? true)
		XCTAssertNil(profileManager.activeProfile?.appLayerBindings["com.example.layer"])
    }

	func testLayerAppLinkRejectsAppOwnedByAnotherProfile() {
		let layer = Layer(name: "Editing")
		let layerProfile = Profile(name: "Layer Profile", layers: [layer])
		let linkedProfile = Profile(
			name: "Full Profile",
			linkedApps: ["com.example.editor"]
		)
		profileManager.profiles = [layerProfile, linkedProfile]
		profileManager.setActiveProfile(layerProfile)

		let result = profileManager.linkApp(
			"com.example.editor",
			toLayer: layer.id,
			in: layerProfile
		)

		XCTAssertEqual(result, .profileConflict(profileName: "Full Profile"))
		XCTAssertNil(
			profileManager.profiles
				.first(where: { $0.id == layerProfile.id })?
				.appLayerBindings["com.example.editor"]
		)
	}

	func testLayerAppLinkAllowsSameProfileToOwnProfileAndLayerLinks() {
		let layer = Layer(name: "Editing")
		let profile = Profile(
			name: "Combined",
			linkedApps: ["com.example.editor"],
			layers: [layer]
		)
		profileManager.profiles = [profile]
		profileManager.setActiveProfile(profile)

		XCTAssertEqual(
			profileManager.linkApp(
				"com.example.editor",
				toLayer: layer.id,
				in: profile
			),
			.linked
		)
		XCTAssertEqual(
			profileManager.activeProfile?.appLayerBindings["com.example.editor"],
			layer.id
		)
	}

	func testFullProfileLinkRemovesOtherProfileLayerBindingAndPreservesDestinationBinding() {
		let bundleId = "com.example.editor"
		let destinationLayer = Layer(name: "Destination Layer")
		let otherLayer = Layer(name: "Other Layer")
		let destination = Profile(
			name: "Destination",
			appLayerBindings: [bundleId: destinationLayer.id],
			layers: [destinationLayer]
		)
		let other = Profile(
			name: "Other",
			appLayerBindings: [bundleId: otherLayer.id],
			layers: [otherLayer]
		)
		profileManager.profiles = [destination, other]
		profileManager.setActiveProfile(destination)

		profileManager.addLinkedApp(bundleId, to: destination)

		let storedDestination = profileManager.profiles.first { $0.id == destination.id }
		let storedOther = profileManager.profiles.first { $0.id == other.id }
		XCTAssertTrue(storedDestination?.linkedApps.contains(bundleId) == true)
		XCTAssertEqual(storedDestination?.appLayerBindings[bundleId], destinationLayer.id)
		XCTAssertNil(storedOther?.appLayerBindings[bundleId])
	}

	func testLayerCommandWheelMutationPreservesInheritCustomAndDisabledStates() {
		let baseAction = CommandWheelAction(displayName: "Base", keyCode: 1)
		let layer = Layer(name: "Editing")
		let profile = Profile(
			name: "Wheel",
			layers: [layer],
			commandWheelActions: [baseAction]
		)
		profileManager.profiles = [profile]
		profileManager.setActiveProfile(profile)

		XCTAssertTrue(profileManager.layerCommandWheelInheritsBase(layerId: layer.id))
		XCTAssertEqual(profileManager.commandWheelActions(layerId: layer.id), [baseAction])

		profileManager.setLayerCommandWheelInheritsBase(false, layerId: layer.id)
		XCTAssertFalse(profileManager.layerCommandWheelInheritsBase(layerId: layer.id))
		XCTAssertEqual(profileManager.commandWheelActions(layerId: layer.id), [baseAction])

		profileManager.removeCommandWheelAction(baseAction, layerId: layer.id)
		XCTAssertEqual(profileManager.commandWheelActions(layerId: layer.id), [])
		XCTAssertEqual(
			profileManager.activeProfile?.layers.first(where: { $0.id == layer.id })?.commandWheelActions,
			[]
		)

		profileManager.setLayerCommandWheelInheritsBase(true, layerId: layer.id)
		XCTAssertTrue(profileManager.layerCommandWheelInheritsBase(layerId: layer.id))
		XCTAssertEqual(profileManager.commandWheelActions(layerId: layer.id), [baseAction])
	}

    func testCreateLayerRespectsMaximumLimit() {
        for index in 0..<ProfileManager.maxLayers {
            let created = profileManager.createLayer(name: "L\(index)")
            XCTAssertNotNil(created)
        }

        let overflow = profileManager.createLayer(name: "Too Many")
        XCTAssertNil(overflow)
    }

    func testSetDefaultProfileMarksOnlySelectedProfileAsDefault() {
        let first = Profile(name: "First", isDefault: true)
        let second = Profile(name: "Second", isDefault: false)
        profileManager.profiles = [first, second]
        profileManager.setActiveProfile(second)

        profileManager.setDefaultProfile(second)

        let updatedFirst = profileManager.profiles.first(where: { $0.id == first.id })
        let updatedSecond = profileManager.profiles.first(where: { $0.id == second.id })
        XCTAssertEqual(updatedFirst?.isDefault, false)
        XCTAssertEqual(updatedSecond?.isDefault, true)
        XCTAssertEqual(profileManager.activeProfileId, second.id)
        XCTAssertEqual(profileManager.activeProfile?.isDefault, true)
    }

    func testUpdateDualSenseAndOnScreenKeyboardQuickTextCRUD() {
        let dualSense = DualSenseLEDSettings(
            lightBarColor: CodableColor(red: 1.0, green: 0.0, blue: 0.0),
            lightBarBrightness: .dim,
            lightBarEnabled: false,
            muteButtonLED: .breathing,
            playerLEDs: .player3
        )
        profileManager.updateDualSenseLEDSettings(dualSense)
        XCTAssertEqual(profileManager.activeProfile?.dualSenseLEDSettings, dualSense)

        let keyboardSettings = OnScreenKeyboardSettings(
            quickTexts: [],
            defaultTerminalApp: "Warp",
            typingDelay: 0.09,
            appBarItems: [],
            websiteLinks: [],
            showExtendedFunctionKeys: true,
            toggleShortcutKeyCode: 40,
            toggleShortcutModifiers: ModifierFlags(command: true),
            activateAllWindows: false,
            wheelShowsWebsites: true,
            wheelAlternateModifiers: ModifierFlags(option: true)
        )
        profileManager.updateOnScreenKeyboardSettings(keyboardSettings)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings, keyboardSettings)

        var first = QuickText(text: "one")
        let second = QuickText(text: "two")
        profileManager.addQuickText(first)
        profileManager.addQuickText(second)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts.map(\.text), ["one", "two"])

        profileManager.moveQuickTexts(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts.map(\.text), ["two", "one"])

        first.text = "ONE"
        first.isTerminalCommand = true
        profileManager.updateQuickText(first)
        let updatedFirst = profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts.first(where: { $0.id == first.id })
        XCTAssertEqual(updatedFirst?.text, "ONE")
        XCTAssertEqual(updatedFirst?.isTerminalCommand, true)

        profileManager.removeQuickText(second)
        XCTAssertEqual(profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts.map(\.id), [first.id])
    }
}
