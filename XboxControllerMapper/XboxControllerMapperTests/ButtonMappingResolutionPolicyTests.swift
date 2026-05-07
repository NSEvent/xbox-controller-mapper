import XCTest
@testable import ControllerKeys

final class ButtonMappingResolutionPolicyTests: XCTestCase {
    func testResolveReturnsNilForLayerActivatorButton() {
        let layer = Layer(name: "Layer A", activatorButton: .leftBumper, buttonMappings: [.a: .key(12)])
        let profile = Profile(name: "Test", buttonMappings: [.leftBumper: .key(30)], layers: [layer])

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .leftBumper,
            profile: profile,
            activeLayerIds: [layer.id],
            layerActivatorMap: [.leftBumper: layer.id]
        )

        XCTAssertNil(result)
    }

    func testResolveUsesMostRecentlyActivatedLayerMapping() {
        let olderLayer = Layer(name: "Older", activatorButton: .leftBumper, buttonMappings: [.a: .key(11)])
        let newerLayer = Layer(name: "Newer", activatorButton: .rightBumper, buttonMappings: [.a: .key(12)])
        let profile = Profile(
            name: "Test",
            buttonMappings: [.a: .key(10)],
            layers: [olderLayer, newerLayer]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .a,
            profile: profile,
            activeLayerIds: [olderLayer.id, newerLayer.id],
            layerActivatorMap: [
                .leftBumper: olderLayer.id,
                .rightBumper: newerLayer.id
            ]
        )

        XCTAssertEqual(result?.keyCode, 12)
    }

    func testResolveFallsBackToBaseMappingWhenLayerMappingMissingOrEmpty() {
        let emptyLayer = Layer(name: "Empty", activatorButton: .leftBumper, buttonMappings: [.a: KeyMapping()])
        let profile = Profile(
            name: "Test",
            buttonMappings: [.a: .key(10)],
            layers: [emptyLayer]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .a,
            profile: profile,
            activeLayerIds: [emptyLayer.id],
            layerActivatorMap: [.leftBumper: emptyLayer.id]
        )

        XCTAssertEqual(result?.keyCode, 10)
    }

    func testResolveProvidesDefaultTouchpadMappings() {
        let profile = Profile(name: "Test")

        let tap = ButtonMappingResolutionPolicy.resolve(
            button: .touchpadTap,
            profile: profile,
            activeLayerIds: [],
            layerActivatorMap: [:]
        )
        let twoFingerTap = ButtonMappingResolutionPolicy.resolve(
            button: .touchpadTwoFingerTap,
            profile: profile,
            activeLayerIds: [],
            layerActivatorMap: [:]
        )

        XCTAssertEqual(tap, KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true))
        XCTAssertEqual(twoFingerTap, KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true))
    }

    // MARK: - Flexible Layer Modifier Tests

    func testResolveAllowsActivatorRemappingInDifferentActiveLayer() {
        // R1 activates Layer 1, R2 activates Layer 2.
        // Layer 1 maps R2 to key 42.
        // When Layer 1 is active, R2 should resolve to key 42 (not nil).
        let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.rightBumper: .key(42)])
        let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.a: .key(99)])
        let profile = Profile(
            name: "Test",
            buttonMappings: [:],
            layers: [layer1, layer2]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .rightBumper,
            profile: profile,
            activeLayerIds: [layer1.id],
            layerActivatorMap: [.leftBumper: layer1.id, .rightBumper: layer2.id]
        )

        XCTAssertEqual(result?.keyCode, 42)
    }

    func testResolveFreesActivatorWhenDifferentLayerActive() {
        // R1 activates Layer 1, R2 activates Layer 2.
        // Layer 1 does NOT map R2, and base layer has no mapping for R2.
        // When Layer 1 is active, R2 is freed (not consumed as activator) but resolves to nil
        // because neither the active layer nor the base has a mapping for it.
        let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.a: .key(10)])
        let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.a: .key(20)])
        let profile = Profile(
            name: "Test",
            buttonMappings: [:],
            layers: [layer1, layer2]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .rightBumper,
            profile: profile,
            activeLayerIds: [layer1.id],
            layerActivatorMap: [.leftBumper: layer1.id, .rightBumper: layer2.id]
        )

        XCTAssertNil(result)
    }

    func testResolveFreedActivatorUsesBaseMappingWhenActiveLayerHasNone() {
        // R1 activates Layer 1, R2 activates Layer 2.
        // Layer 1 does NOT map R2, but base layer maps R2 to key 50.
        // When Layer 1 is active, R2 should resolve to its base mapping (key 50).
        let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.a: .key(10)])
        let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.a: .key(20)])
        let profile = Profile(
            name: "Test",
            buttonMappings: [.rightBumper: .key(50)],
            layers: [layer1, layer2]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .rightBumper,
            profile: profile,
            activeLayerIds: [layer1.id],
            layerActivatorMap: [.leftBumper: layer1.id, .rightBumper: layer2.id]
        )

        XCTAssertEqual(result?.keyCode, 50)
    }

    func testResolveConsumesActivatorWhenNoLayerIsActive() {
        // No layer is active. R2 (a layer activator) should return nil.
        let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.a: .key(20)])
        let profile = Profile(
            name: "Test",
            buttonMappings: [.rightBumper: .key(50)],
            layers: [layer2]
        )

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .rightBumper,
            profile: profile,
            activeLayerIds: [],
            layerActivatorMap: [.rightBumper: layer2.id]
        )

        XCTAssertNil(result)
    }

    func testResolveReturnsNilWhenNoLayerBaseOrDefaultMappingExists() {
        let profile = Profile(name: "Test")

        let result = ButtonMappingResolutionPolicy.resolve(
            button: .x,
            profile: profile,
            activeLayerIds: [],
            layerActivatorMap: [:]
        )

        XCTAssertNil(result)
    }
}
