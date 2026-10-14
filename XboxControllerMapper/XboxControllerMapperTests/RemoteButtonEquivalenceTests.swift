import XCTest
@testable import ControllerKeys

final class RemoteButtonEquivalenceTests: XCTestCase {
	func testEveryPhysicalRemoteButtonHasOneRoundTripEquivalent() {
		XCTAssertEqual(Set(RemoteButtonEquivalence.pairs.map(\.xiaomi)).count, 9)
		XCTAssertEqual(Set(RemoteButtonEquivalence.pairs.map(\.apple)).count, 9)
		for pair in RemoteButtonEquivalence.pairs {
			XCTAssertEqual(RemoteButtonEquivalence.counterpart(of: pair.xiaomi), pair.apple)
			XCTAssertEqual(RemoteButtonEquivalence.counterpart(of: pair.apple), pair.xiaomi)
		}
		XCTAssertNil(RemoteButtonEquivalence.counterpart(of: .touchpadTap))
		XCTAssertNil(RemoteButtonEquivalence.counterpart(of: .dpadUp)) // already identical
	}

	func testWholeMappingsIncludingAlternateActionsAreInheritedBothWays() {
		let mapping = KeyMapping(keyCode: 12, longHoldMapping: LongHoldMapping(keyCode: 13),
			doubleTapMapping: DoubleTapMapping(keyCode: 14))
		for pair in RemoteButtonEquivalence.pairs {
			for (input, saved) in [(pair.xiaomi, pair.apple), (pair.apple, pair.xiaomi)] {
				let profile = Profile(name: "Shared", buttonMappings: [saved: mapping])
				XCTAssertEqual(ButtonMappingResolutionPolicy.resolve(button: input, profile: profile,
					activeLayerIds: [], layerActivatorMap: [:], remoteContext: true), mapping)
			}
		}
	}

	func testExplicitBindingsIncludingExplicitClearsTakePriority() {
		let profile = Profile(name: "Overrides", buttonMappings: [.xiaomiBack: .key(10), .view: .key(11)])
		XCTAssertEqual(resolve(.xiaomiBack, profile)?.keyCode, 10)
		XCTAssertEqual(resolve(.view, profile)?.keyCode, 11)
		let cleared = Profile(name: "Clear", buttonMappings: [.xiaomiBack: KeyMapping(), .view: .key(11)])
		XCTAssertNil(resolve(.xiaomiBack, cleared))
		XCTAssertEqual(resolve(.view, cleared)?.keyCode, 11)
	}

	func testLayerEquivalentOverridesBaseWhileLayerNativeOverrideWins() {
		let layer = Layer(name: "Media", buttonMappings: [.appleTVRemoteVolumeUp: .key(20)])
		let profile = Profile(name: "Layers", buttonMappings: [.xiaomiVolumeUp: .key(10)], layers: [layer])
		XCTAssertEqual(resolve(.xiaomiVolumeUp, profile, layers: [layer.id])?.keyCode, 20)
		let native = Layer(name: "Native", buttonMappings: [.xiaomiVolumeUp: .key(30), .appleTVRemoteVolumeUp: .key(20)])
		XCTAssertEqual(resolve(.xiaomiVolumeUp, Profile(name: "Native", layers: [native]), layers: [native.id])?.keyCode, 30)
	}

	func testLayerActivatorsChordsAndSequencesResolveWithoutSingleTapBindings() {
		let layer = Layer(name: "Media", activatorButton: .appleTVRemotePower)
		let profile = Profile(name: "Advanced", chordMappings: [ChordMapping(buttons: [.view, .xbox], keyCode: 9)],
			sequenceMappings: [SequenceMapping(steps: [.menu, .siri], keyCode: 8)], layers: [layer])
		for (input, saved) in [(ControllerButton.xiaomiBack, ControllerButton.view), (.xiaomiTV, .xbox),
			(.xiaomiHome, .menu), (.xiaomiMicrophone, .siri), (.xiaomiPower, .appleTVRemotePower)] {
			XCTAssertEqual(ButtonMappingResolutionPolicy.resolvedButton(button: input, profile: profile,
				activeLayerIds: [], layerActivatorMap: [.appleTVRemotePower: layer.id], remoteContext: true), saved)
		}
		XCTAssertNil(ButtonMappingResolutionPolicy.resolve(button: .xiaomiPower, profile: profile,
			activeLayerIds: [layer.id], layerActivatorMap: [.appleTVRemotePower: layer.id], remoteContext: true))
	}

	func testSharedGamepadIdentitiesDoNotInheritRemoteMappingsOutsideRemoteContext() {
		for pair in RemoteButtonEquivalence.pairs {
			let profile = Profile(name: "Xiaomi", buttonMappings: [pair.xiaomi: .key(12)])
			XCTAssertNil(ButtonMappingResolutionPolicy.resolve(button: pair.apple, profile: profile,
				activeLayerIds: [], layerActivatorMap: [:]))
		}
		XCTAssertEqual(ButtonMappingResolutionPolicy.resolvedButton(button: .xiaomiOK,
			profile: Profile(name: "Empty"), activeLayerIds: [], layerActivatorMap: [:]), .xiaomiOK)
	}

	private func resolve(_ button: ControllerButton, _ profile: Profile, layers: [UUID] = []) -> KeyMapping? {
		ButtonMappingResolutionPolicy.resolve(button: button, profile: profile,
			activeLayerIds: layers, layerActivatorMap: [:], remoteContext: true)
	}
}

@MainActor
final class RemoteButtonEquivalenceMappingTests: MappingEngineTestCase {
	func testExistingRemoteProfilesExecuteEveryEquivalentExactlyOnceInBothDirections() async {
		for appleInput in [false, true] {
			controllerService.storage.isAppleTVRemote = appleInput
			let pairs = RemoteButtonEquivalence.pairs
			profileManager.setActiveProfile(Profile(name: "Existing", buttonMappings: Dictionary(
				uniqueKeysWithValues: pairs.enumerated().map { index, pair in
					(appleInput ? pair.xiaomi : pair.apple, KeyMapping.key(UInt16(index)))
				})))
			await waitForTasks()
			for (index, pair) in pairs.enumerated() {
				mockInputSimulator.clearEvents()
				let input = appleInput ? pair.apple : pair.xiaomi
				controllerService.handleButton(input, pressed: true)
				controllerService.handleButton(input, pressed: false)
				await waitForTasks(0.2)
				XCTAssertEqual(keys(), [UInt16(index)], "\(input) must inherit its saved counterpart once")
			}
		}
	}

	func testAppleLayerActivatorAndLayerMappingWorkOnXiaomiAndReleaseNormally() async {
		let layer = Layer(name: "Media", activatorButton: .appleTVRemotePower,
			buttonMappings: [.appleTVRemoteVolumeUp: .key(20)])
		profileManager.setActiveProfile(Profile(name: "Apple", layers: [layer]))
		await waitForTasks()
		controllerService.handleButton(.xiaomiPower, pressed: true)
		await waitForTasks(0.1)
		XCTAssertEqual(mappingEngine.activeManualLayerId, layer.id)
		controllerService.handleButton(.xiaomiVolumeUp, pressed: true)
		controllerService.handleButton(.xiaomiVolumeUp, pressed: false)
		await waitForTasks(0.2)
		XCTAssertEqual(keys(), [20])
		controllerService.handleButton(.xiaomiPower, pressed: false)
		await waitForTasks(0.1)
		XCTAssertNil(mappingEngine.activeManualLayerId)
	}

	func testSavedAppleSequenceWorksWithXiaomiKeys() async {
		profileManager.setActiveProfile(Profile(name: "Apple sequence", sequenceMappings: [
			SequenceMapping(steps: [.view, .siri], stepTimeout: 0.5, keyCode: 22)]))
		await waitForTasks()
		for input in [ControllerButton.xiaomiBack, .xiaomiMicrophone] {
			controllerService.handleButton(input, pressed: true)
			controllerService.handleButton(input, pressed: false)
			await waitForTasks(0.1)
		}
		await waitForTasks(0.2)
		XCTAssertEqual(keys(), [22])
	}

	private func keys() -> [UInt16] {
		mockInputSimulator.events.compactMap { event in
			if case .pressKey(let key, _) = event { return key }
			return nil
		}
	}
}
