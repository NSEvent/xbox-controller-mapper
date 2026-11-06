import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerMappingTransferTests: XCTestCase {
	private var xboxScope: Set<ControllerButton> {
		ControllerMappingTransfer.buttonScope(for: ControllerVisualDescriptor.concrete(for: .xbox)!)
	}

	private func emptyProfile(_ name: String) -> Profile {
		var profile = Profile(name: name)
		profile.buttonMappings = [:]
		profile.layers = []
		profile.macros = []
		profile.scripts = []
		return profile
	}

	// MARK: - Scope

	func testXboxScopeExcludesOtherDeviceButtons() {
		XCTAssertTrue(xboxScope.contains(.a))
		XCTAssertTrue(xboxScope.contains(.leftTrigger))
		XCTAssertFalse(xboxScope.contains(.ouraTap))
		XCTAssertFalse(xboxScope.contains(.xiaomiOK))
	}

	func testEliteScopeIncludesLogicalAndPhysicalPaddles() {
		let scope = ControllerMappingTransfer.buttonScope(for: ControllerVisualDescriptor.concrete(for: .xboxElite)!)
		XCTAssertTrue(scope.contains(.leftPaddle))
		XCTAssertTrue(scope.contains(.xboxPaddle1))
	}

	// MARK: - Modes

	func testReplaceCopiesOverwritesAndClearsOnlyScopedButtons() {
		var source = emptyProfile("Source")
		source.buttonMappings = [.a: KeyMapping(keyCode: 1), .b: KeyMapping(keyCode: 2), .ouraTap: KeyMapping(keyCode: 9)]
		var destination = emptyProfile("Destination")
		destination.buttonMappings = [.b: KeyMapping(keyCode: 20), .x: KeyMapping(keyCode: 30), .ouraTap: KeyMapping(keyCode: 40)]

		let plan = ControllerMappingTransfer.plan(from: source, to: destination, buttons: xboxScope, options: .init())

		XCTAssertEqual(plan.result.buttonMappings[.a], KeyMapping(keyCode: 1))
		XCTAssertEqual(plan.result.buttonMappings[.b], KeyMapping(keyCode: 2))
		XCTAssertNil(plan.result.buttonMappings[.x], "Replace clears buttons the source leaves unmapped")
		XCTAssertEqual(plan.result.buttonMappings[.ouraTap], KeyMapping(keyCode: 40), "Other devices' buttons are untouched")
		XCTAssertEqual(plan.copiedCount, 2)
		XCTAssertEqual(plan.clearedCount, 1)
		XCTAssertEqual(plan.overwritten, [.init(button: .b, layerName: nil)])
		XCTAssertTrue(plan.hasChanges)
	}

	func testFillEmptyKeepsExistingDestinationMappings() {
		var source = emptyProfile("Source")
		source.buttonMappings = [.a: KeyMapping(keyCode: 1), .b: KeyMapping(keyCode: 2)]
		var destination = emptyProfile("Destination")
		destination.buttonMappings = [.b: KeyMapping(keyCode: 20), .x: KeyMapping(keyCode: 30)]

		let plan = ControllerMappingTransfer.plan(
			from: source, to: destination, buttons: xboxScope, options: .init(mode: .fillEmpty)
		)

		XCTAssertEqual(plan.result.buttonMappings[.a], KeyMapping(keyCode: 1))
		XCTAssertEqual(plan.result.buttonMappings[.b], KeyMapping(keyCode: 20))
		XCTAssertEqual(plan.result.buttonMappings[.x], KeyMapping(keyCode: 30))
		XCTAssertEqual(plan.copiedCount, 1)
		XCTAssertEqual(plan.clearedCount, 0)
		XCTAssertTrue(plan.overwritten.isEmpty)
	}

	func testIdenticalProfilesProduceNoChanges() {
		var source = emptyProfile("Source")
		source.buttonMappings = [.a: KeyMapping(keyCode: 1)]
		var destination = emptyProfile("Destination")
		destination.buttonMappings = [.a: KeyMapping(keyCode: 1)]

		let plan = ControllerMappingTransfer.plan(from: source, to: destination, buttons: xboxScope, options: .init())
		XCTAssertFalse(plan.hasChanges)
	}

	// MARK: - Layers

	func testLayersAreIgnoredUnlessIncluded() {
		var source = emptyProfile("Source")
		source.layers = [Layer(name: "Media", activatorButton: .leftBumper, buttonMappings: [.a: KeyMapping(keyCode: 5)])]
		let destination = emptyProfile("Destination")

		let plan = ControllerMappingTransfer.plan(from: source, to: destination, buttons: xboxScope, options: .init())
		XCTAssertTrue(plan.result.layers.isEmpty)
	}

	func testIncludedLayersMatchByNameAndCreateMissingOnes() {
		var source = emptyProfile("Source")
		source.layers = [
			Layer(name: "Media", activatorButton: .leftBumper, buttonMappings: [.a: KeyMapping(keyCode: 5)]),
			Layer(name: "Nav", activatorButton: .rightBumper, activationStyle: .toggle,
				  buttonMappings: [.b: KeyMapping(keyCode: 6), .ouraTap: KeyMapping(keyCode: 7)]),
		]
		var destination = emptyProfile("Destination")
		let existingMedia = Layer(name: "media", activatorButton: .view, buttonMappings: [.a: KeyMapping(keyCode: 50)])
		destination.layers = [existingMedia, Layer(name: "Other", activatorButton: .rightBumper)]

		let plan = ControllerMappingTransfer.plan(
			from: source, to: destination, buttons: xboxScope, options: .init(includeLayers: true)
		)

		let media = plan.result.layers.first { $0.id == existingMedia.id }
		XCTAssertEqual(media?.buttonMappings[.a], KeyMapping(keyCode: 5))
		XCTAssertEqual(media?.activatorButton, .view, "Matched layers keep their own activator")
		XCTAssertTrue(plan.overwritten.contains(.init(button: .a, layerName: "media")))

		let nav = plan.result.layers.first { $0.name == "Nav" }
		XCTAssertNotNil(nav)
		XCTAssertNil(nav?.activatorButton, "An activator already used in the destination is not duplicated")
		XCTAssertEqual(nav?.activationStyle, .toggle)
		XCTAssertEqual(nav?.buttonMappings, [.b: KeyMapping(keyCode: 6)], "Created layers only carry scoped buttons")
		XCTAssertEqual(plan.createdLayerNames, ["Nav"])
	}

	func testLayerCreationStopsAtLayerLimit() {
		var source = emptyProfile("Source")
		source.layers = [Layer(name: "Extra", buttonMappings: [.a: KeyMapping(keyCode: 5)])]
		var destination = emptyProfile("Destination")
		destination.layers = (0..<ProfileManager.maxLayers).map { Layer(name: "L\($0)") }

		let plan = ControllerMappingTransfer.plan(
			from: source, to: destination, buttons: xboxScope, options: .init(includeLayers: true)
		)
		XCTAssertEqual(plan.result.layers.count, ProfileManager.maxLayers)
		XCTAssertEqual(plan.skippedLayerNames, ["Extra"])
	}

	// MARK: - Macro / script dependencies

	func testReferencedMacrosAndScriptsAreCarriedAlong() {
		let macro = Macro(name: "Combo", steps: [.delay(0.1)])
		let unused = Macro(name: "Unused")
		let script = Script(name: "Hold script", source: "1")
		var source = emptyProfile("Source")
		source.macros = [macro, unused]
		source.scripts = [script]
		source.buttonMappings = [
			.a: KeyMapping(macroId: macro.id),
			.b: KeyMapping(keyCode: 2, longHoldMapping: LongHoldMapping(scriptId: script.id)),
		]

		let plan = ControllerMappingTransfer.plan(
			from: source, to: emptyProfile("Destination"), buttons: xboxScope, options: .init()
		)

		XCTAssertEqual(plan.result.macros, [macro])
		XCTAssertEqual(plan.result.scripts, [script])
		XCTAssertEqual(plan.carriedMacroCount, 1)
		XCTAssertEqual(plan.carriedScriptCount, 1)
	}

	func testIdenticalMacroInDestinationIsReused() {
		let macro = Macro(name: "Combo", steps: [.delay(0.1)])
		var source = emptyProfile("Source")
		source.macros = [macro]
		source.buttonMappings = [.a: KeyMapping(macroId: macro.id)]
		var destination = emptyProfile("Destination")
		destination.macros = [macro]

		let plan = ControllerMappingTransfer.plan(from: source, to: destination, buttons: xboxScope, options: .init())

		XCTAssertEqual(plan.result.macros, [macro])
		XCTAssertEqual(plan.result.buttonMappings[.a]?.macroId, macro.id)
		XCTAssertEqual(plan.carriedMacroCount, 0)
	}

	func testConflictingMacroIdIsCopiedUnderFreshId() {
		let id = UUID()
		let sourceMacro = Macro(id: id, name: "Source version", steps: [.delay(0.1)])
		let destinationMacro = Macro(id: id, name: "Destination version", steps: [.delay(0.2)])
		var source = emptyProfile("Source")
		source.macros = [sourceMacro]
		source.buttonMappings = [.a: KeyMapping(doubleTapMapping: DoubleTapMapping(macroId: id))]
		var destination = emptyProfile("Destination")
		destination.macros = [destinationMacro]
		destination.buttonMappings = [.x: KeyMapping(macroId: id)]

		let plan = ControllerMappingTransfer.plan(
			from: source, to: destination, buttons: xboxScope, options: .init(mode: .fillEmpty)
		)

		let newId = plan.result.buttonMappings[.a]?.doubleTapMapping?.macroId
		XCTAssertNotNil(newId)
		XCTAssertNotEqual(newId, id)
		XCTAssertEqual(plan.result.macros.count, 2)
		XCTAssertEqual(plan.result.macros.first { $0.id == id }, destinationMacro, "Destination macro untouched")
		XCTAssertEqual(plan.result.macros.first { $0.id == newId }?.name, "Source version")
		XCTAssertEqual(plan.result.buttonMappings[.x]?.macroId, id, "Existing destination references untouched")
	}

	// MARK: - ProfileManager

	func testProfileManagerAppliesCopyAndSnapshotsFirst() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let manager = ProfileManager(configDirectoryOverride: directory)

		var source = emptyProfile("Source")
		source.buttonMappings = [.a: KeyMapping(keyCode: 1)]
		let destination = emptyProfile("Destination")
		manager.profiles = [source, destination]
		manager.setActiveProfile(source)
		let snapshotsBefore = manager.availableSnapshots().count

		let plan = manager.copyControllerMappings(
			from: source, to: destination.id, buttons: xboxScope, controllerName: "Xbox", options: .init()
		)

		XCTAssertNotNil(plan)
		let stored = try XCTUnwrap(manager.profiles.first { $0.id == destination.id })
		XCTAssertEqual(stored.buttonMappings[.a], KeyMapping(keyCode: 1))
		XCTAssertEqual(manager.availableSnapshots().count, snapshotsBefore + 1)

		XCTAssertNil(
			manager.copyControllerMappings(
				from: source, to: destination.id, buttons: xboxScope, controllerName: "Xbox", options: .init()
			),
			"A copy with nothing to change is a no-op"
		)
		XCTAssertNil(
			manager.copyControllerMappings(
				from: source, to: source.id, buttons: xboxScope, controllerName: "Xbox", options: .init()
			)
		)
	}
}
