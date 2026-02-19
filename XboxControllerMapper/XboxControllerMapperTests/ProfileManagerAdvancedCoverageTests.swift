import XCTest
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

        profileManager.deleteLayer(updatedLayer)
        XCTAssertFalse(profileManager.activeProfile?.layers.contains(where: { $0.id == layer.id }) ?? true)
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
