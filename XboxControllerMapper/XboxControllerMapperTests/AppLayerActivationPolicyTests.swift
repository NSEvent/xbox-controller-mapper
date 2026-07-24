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
		let manualLayerId = UUID()

		state.appActivatedLayerId = appLayerId
		state.activeLayerIds = [manualLayerId]

		XCTAssertEqual(state.effectiveActiveLayerIds, [appLayerId, manualLayerId])
	}

	func testEffectiveLayerOrderDeduplicatesSameAppAndManualLayer() {
		let state = MappingEngine.EngineState()
		let layerId = UUID()

		state.appActivatedLayerId = layerId
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
