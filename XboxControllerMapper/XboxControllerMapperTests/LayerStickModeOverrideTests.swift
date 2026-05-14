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
        XCTAssertEqual(active.joystickSettings.leftStickMode, .scroll)
        let stored = try XCTUnwrap(active.layers.first(where: { $0.id == layer.id }))
        XCTAssertNil(stored.leftStickModeOverride, "Profile-level write must not touch layer overrides.")
    }

    /// Per-layer write sets the override on that layer only.
    func testSetStickMode_layerScope_setsOverride() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))
        let baseLeftMode = profileManager.activeProfile?.joystickSettings.leftStickMode

        profileManager.setStickMode(.scroll, side: .left, layerId: layer.id)

        let active = try XCTUnwrap(profileManager.activeProfile)
        let stored = try XCTUnwrap(active.layers.first(where: { $0.id == layer.id }))
        XCTAssertEqual(stored.leftStickModeOverride, .scroll)
        XCTAssertEqual(active.joystickSettings.leftStickMode, baseLeftMode,
                       "Layer-scoped write must not mutate profile-level mode.")
    }

    /// Clearing a layer override (nil mode + non-nil layerId) drops it back to inheriting.
    func testSetStickMode_layerScope_clearOverrideWithNilMode() throws {
        let layer = try XCTUnwrap(profileManager.createLayer(name: "L1", activatorButton: .leftBumper))
        profileManager.setStickMode(.scroll, side: .right, layerId: layer.id)
        XCTAssertEqual(profileManager.activeProfile?.layers.first?.rightStickModeOverride, .scroll)

        profileManager.setStickMode(nil, side: .right, layerId: layer.id)

        XCTAssertNil(profileManager.activeProfile?.layers.first?.rightStickModeOverride)
    }

    /// Profile-level write with nil mode is a no-op (the profile must always have a concrete mode).
    func testSetStickMode_profileScope_nilModeIsNoop() throws {
        let initial = profileManager.activeProfile?.joystickSettings.leftStickMode

        profileManager.setStickMode(nil, side: .left, layerId: nil)

        XCTAssertEqual(profileManager.activeProfile?.joystickSettings.leftStickMode, initial)
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
        XCTAssertEqual(a.leftStickModeOverride, .scroll)
        XCTAssertEqual(b.leftStickModeOverride, .mouse)
    }

    /// The override field survives a Codable round-trip (matters for config persistence).
    func testLayer_codableRoundTripPreservesOverrides() throws {
        var layer = Layer(name: "RT", activatorButton: .leftBumper)
        layer.leftStickModeOverride = .scroll
        layer.rightStickModeOverride = .mouse

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(Layer.self, from: data)

        XCTAssertEqual(decoded.leftStickModeOverride, .scroll)
        XCTAssertEqual(decoded.rightStickModeOverride, .mouse)
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

        XCTAssertNil(decoded.leftStickModeOverride)
        XCTAssertNil(decoded.rightStickModeOverride)
    }
}
