import XCTest
@testable import ControllerKeys

@MainActor
final class LayerStickModeOverrideTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-layer-stick-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
    }

    override func tearDown() async throws {
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    /// Profile-level write (nil layerId) updates JoystickSettings, not any layer.
    func testSetStickMode_profileScope_updatesJoystickSettings() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))

        profileManager.setStickMode(.scroll, side: .left, layerId: nil)

        let active = try XCTUnwrap(profileManager.activeProfile)
        XCTAssertEqual(active.joystickSettings.leftStick.mode, .scroll)
        let stored = try XCTUnwrap(active.layers.first(where: { $0.id == layer.id }))
        XCTAssertNil(stored.leftStickTuning, "Profile-level write must not touch layer overrides.")
    }

    /// Per-layer write sets the mode override on that layer only.
    func testSetStickMode_layerScope_setsOverride() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))
        let baseLeftMode = profileManager.activeProfile?.joystickSettings.leftStick.mode

        profileManager.setStickMode(.scroll, side: .left, layerId: layer.id)

        let active = try XCTUnwrap(profileManager.activeProfile)
        let stored = try XCTUnwrap(active.layers.first(where: { $0.id == layer.id }))
        XCTAssertEqual(stored.leftStickTuning?.mode, .scroll)
        XCTAssertEqual(active.joystickSettings.leftStick.mode, baseLeftMode,
                       "Layer-scoped write must not mutate profile-level mode.")
    }

    /// Clearing a layer mode override (nil mode + non-nil layerId) drops it back to inheriting.
    func testSetStickMode_layerScope_clearOverrideWithNilMode() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))
        profileManager.setStickMode(.scroll, side: .right, layerId: layer.id)
        XCTAssertEqual(profileManager.activeProfile?.layers.first?.rightStickTuning?.mode, .scroll)

        profileManager.setStickMode(nil, side: .right, layerId: layer.id)

        XCTAssertNil(profileManager.activeProfile?.layers.first?.rightStickTuning?.mode)
    }

    /// Profile-level write with nil mode is a no-op (the profile must always have a concrete mode).
    func testSetStickMode_profileScope_nilModeIsNoop() throws {
        let initial = profileManager.activeProfile?.joystickSettings.leftStick.mode

        profileManager.setStickMode(nil, side: .left, layerId: nil)

        XCTAssertEqual(profileManager.activeProfile?.joystickSettings.leftStick.mode, initial)
    }

    /// Two layers can independently override the same side.
    func testSetStickMode_layerScope_independentAcrossLayers() throws {
        let layerA = try XCTUnwrap(profileManager.createLayer(name: "A", activatorButton: .leftBumper))
        let layerB = try XCTUnwrap(profileManager.createLayer(name: "B", activatorButton: .rightBumper))

        profileManager.setStickMode(.scroll, side: .left, layerId: layerA.id)
        profileManager.setStickMode(.mouse, side: .left, layerId: layerB.id)

        let stored = try XCTUnwrap(profileManager.activeProfile?.layers)
        let a = try XCTUnwrap(stored.first(where: { $0.id == layerA.id }))
        let b = try XCTUnwrap(stored.first(where: { $0.id == layerB.id }))
        XCTAssertEqual(a.leftStickTuning?.mode, .scroll)
        XCTAssertEqual(b.leftStickTuning?.mode, .mouse)
    }

    /// A single tuning field can be overridden without touching the mode, and clearing
    /// the only overridden field drops the whole override so the layer fully inherits.
    func testSetLayerStickOverride_setsAndClearsSingleField() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))

        profileManager.setLayerStickOverride(\.mouseSensitivity, 0.9, side: .left, layerId: layer.id)
        let stored = try XCTUnwrap(profileManager.activeProfile?.layers.first(where: { $0.id == layer.id }))
        XCTAssertEqual(stored.leftStickTuning?.mouseSensitivity, 0.9)
        XCTAssertNil(stored.leftStickTuning?.mode, "Only one field is overridden; mode still inherits.")

        profileManager.setLayerStickOverride(\.mouseSensitivity, nil, side: .left, layerId: layer.id)
        let cleared = try XCTUnwrap(profileManager.activeProfile?.layers.first(where: { $0.id == layer.id }))
        XCTAssertNil(cleared.leftStickTuning, "Clearing the only overridden field drops the whole override.")
    }

    /// `clearLayerStickOverride` drops the entire side override regardless of how many fields are set.
    func testClearLayerStickOverride_dropsEntireOverride() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))
        profileManager.setStickMode(.scroll, side: .left, layerId: layer.id)
        profileManager.setLayerStickOverride(\.mouseSensitivity, 0.9, side: .left, layerId: layer.id)

        profileManager.clearLayerStickOverride(side: .left, layerId: layer.id)

        let stored = try XCTUnwrap(profileManager.activeProfile?.layers.first(where: { $0.id == layer.id }))
        XCTAssertNil(stored.leftStickTuning)
    }

    /// `applied(to:)` overlays only the fields the override explicitly sets.
    func testStickTuningOverride_appliedOverlaysOnlySetFields() {
        let base = StickTuning(mode: .mouse, mouseSensitivity: 0.5, mouseDeadzone: 0.15)
        var override = StickTuningOverride()
        override.mouseSensitivity = 0.9

        let resolved = override.applied(to: base)
        XCTAssertEqual(resolved.mouseSensitivity, 0.9, "Set field is overridden.")
        XCTAssertEqual(resolved.mode, .mouse, "Unset mode inherits base.")
        XCTAssertEqual(resolved.mouseDeadzone, 0.15, "Unset deadzone inherits base.")
        XCTAssertTrue(StickTuningOverride().isEmpty)
        XCTAssertFalse(override.isEmpty)
    }

    /// A full tuning override survives a Codable round-trip (matters for config persistence).
    func testLayer_codableRoundTripPreservesOverrides() throws {
        var layer = Layer(name: "RT", activatorButton: .leftBumper)
        layer.leftStickTuning = StickTuningOverride(mode: .scroll, mouseSensitivity: 0.9)
        layer.rightStickTuning = StickTuningOverride(mode: .mouse)

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(Layer.self, from: data)

        XCTAssertEqual(decoded.leftStickTuning?.mode, .scroll)
        XCTAssertEqual(decoded.leftStickTuning?.mouseSensitivity, 0.9)
        XCTAssertEqual(decoded.rightStickTuning?.mode, .mouse)
    }

    /// Existing configs without the override fields decode with nil overrides (no migration needed).
    func testLayer_backwardCompatibleDecode_missingFieldsAreNil() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy",
            "buttonMappings": {}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Layer.self, from: json)

        XCTAssertNil(decoded.leftStickTuning)
        XCTAssertNil(decoded.rightStickTuning)
    }

    /// A legacy mode-only override (pre per-stick tuning) migrates into the tuning override.
    func testLayer_legacyModeOverrideMigratesToTuning() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "LegacyOverride",
            "buttonMappings": {},
            "leftStickModeOverride": "scroll"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Layer.self, from: json)

        XCTAssertEqual(decoded.leftStickTuning?.mode, .scroll, "Legacy mode-only override migrates into the tuning override.")
        XCTAssertNil(decoded.rightStickTuning)
    }

    /// An unknown StickMode raw value on a legacy layer override (e.g. a case added by
    /// a newer build) must fall back to nil ("inherit"), NOT throw and unwind the whole
    /// layer/profile decode on a downgrade.
    func testLayer_unknownStickModeOverrideDecodesToNilNotThrow() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "FromFuture",
            "buttonMappings": {},
            "leftStickModeOverride": "teleport",
            "rightStickModeOverride": "scroll"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Layer.self, from: json)

        XCTAssertNil(decoded.leftStickTuning?.mode, "Unknown raw value should degrade to inherit.")
        XCTAssertEqual(decoded.rightStickTuning?.mode, .scroll, "Known sibling value still decodes.")
    }

    /// An unknown StickMode raw value on JoystickSettings must degrade to the
    /// per-side default rather than throwing out the whole settings/profile.
    func testJoystickSettings_unknownStickModeDecodesToDefaultNotThrow() throws {
        let json = #"{"leftStickMode":"teleport","rightStickMode":"dpad"}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(JoystickSettings.self, from: json)

        XCTAssertEqual(decoded.leftStick.mode, .mouse, "Unknown raw value degrades to the default.")
        XCTAssertEqual(decoded.rightStick.mode, .dpad, "Known sibling value (incl. newer cases) still decodes.")
    }
}
