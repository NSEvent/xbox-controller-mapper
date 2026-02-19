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
