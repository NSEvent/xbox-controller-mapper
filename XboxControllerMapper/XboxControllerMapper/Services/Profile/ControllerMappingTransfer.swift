import Foundation

/// Options for copying one controller's button mappings into another profile.
struct ControllerMappingTransferOptions: Equatable {
	enum Mode: String, CaseIterable, Identifiable {
		/// Destination mappings for the controller's buttons become an exact copy
		/// of the source, including clearing buttons the source leaves unmapped.
		case replace
		/// Only buttons that are unmapped in the destination receive a mapping.
		case fillEmpty

		var id: String { rawValue }
	}

	var mode: Mode = .replace
	/// Also copy layer mappings, matching layers by name and creating missing ones.
	var includeLayers = false
}

/// Result of planning a transfer: the updated destination profile plus the
/// counts the confirmation UI shows before anything is written.
struct ControllerMappingTransferPlan {
	let result: Profile
	let copiedCount: Int
	/// Existing destination mappings that the transfer replaces (layerName nil = base layer).
	let overwritten: [ControllerMappingTransferPlan.Change]
	let clearedCount: Int
	let createdLayerNames: [String]
	/// Source layers that could not be created because the destination is at the layer limit.
	let skippedLayerNames: [String]
	let carriedMacroCount: Int
	let carriedScriptCount: Int

	struct Change: Equatable {
		let button: ControllerButton
		let layerName: String?
	}

	var hasChanges: Bool {
		copiedCount > 0 || clearedCount > 0 || !createdLayerNames.isEmpty
	}
}

/// Pure planner for "copy this controller's mappings to another profile".
///
/// Mappings can reference profile-owned macros and scripts by ID, so the plan
/// carries every referenced macro/script along. An identical item already in
/// the destination is reused; a different item with the same ID is copied
/// under a fresh ID and the copied mappings are remapped to it.
enum ControllerMappingTransfer {
	/// The buttons that belong to a controller layout, including the alternate
	/// identities the editor resolves them through (Elite paddles store under
	/// logical paddle buttons; Xiaomi and Apple TV remotes share bindings).
	static func buttonScope(for descriptor: ControllerVisualDescriptor) -> Set<ControllerButton> {
		var scope = descriptor.supportedButtons
		for button in descriptor.supportedButtons {
			if let logical = button.logicalEquivalent { scope.insert(logical) }
			scope.formUnion(button.physicalEquivalentButtons)
			if descriptor.isXiaomiRemote || descriptor.isAppleTVRemote,
			   let counterpart = RemoteButtonEquivalence.counterpart(of: button) {
				scope.insert(counterpart)
			}
		}
		return scope
	}

	static func plan(
		from source: Profile,
		to destination: Profile,
		buttons: Set<ControllerButton>,
		options: ControllerMappingTransferOptions
	) -> ControllerMappingTransferPlan {
		var result = destination
		var stats = Stats()

		let macroRemap = remap(source.macros, into: destination.macros)
		let scriptRemap = remap(source.scripts, into: destination.scripts)
		let prepare: ([ControllerButton: KeyMapping]) -> [ControllerButton: KeyMapping] = { mappings in
			mappings.mapValues { remapped($0, macros: macroRemap, scripts: scriptRemap) }
		}

		transfer(prepare(source.buttonMappings), into: &result.buttonMappings,
				 buttons: buttons, mode: options.mode, layerName: nil, stats: &stats)

		var createdLayerNames: [String] = []
		var skippedLayerNames: [String] = []
		if options.includeLayers {
			for sourceLayer in source.layers {
				let sourceMappings = prepare(sourceLayer.buttonMappings)
				if let index = result.layers.firstIndex(where: {
					$0.name.caseInsensitiveCompare(sourceLayer.name) == .orderedSame
				}) {
					transfer(sourceMappings, into: &result.layers[index].buttonMappings,
							 buttons: buttons, mode: options.mode,
							 layerName: result.layers[index].name, stats: &stats)
					continue
				}

				let scopedMappings = sourceMappings.filter { buttons.contains($0.key) && $0.value.hasConfiguredBehavior }
				let activator = sourceLayer.activatorButton.flatMap { button in
					buttons.contains(button) && !result.layers.contains(where: { $0.activatorButton == button })
						? button : nil
				}
				guard !scopedMappings.isEmpty || activator != nil else { continue }
				guard result.layers.count < ProfileManager.maxLayers else {
					skippedLayerNames.append(sourceLayer.name)
					continue
				}
				result.layers.append(Layer(
					name: sourceLayer.name,
					activatorButton: activator,
					activationStyle: sourceLayer.activationStyle,
					buttonMappings: scopedMappings
				))
				stats.written.append(contentsOf: scopedMappings.values)
				stats.copiedCount += scopedMappings.count
				createdLayerNames.append(sourceLayer.name)
			}
		}

		// Carry only the macros/scripts that a written mapping actually references.
		let referencedMacros = Set(stats.written.flatMap(referencedMacroIds))
		let referencedScripts = Set(stats.written.flatMap(referencedScriptIds))
		var carriedMacroCount = 0
		for macro in source.macros {
			let id = macroRemap[macro.id] ?? macro.id
			guard referencedMacros.contains(id), !result.macros.contains(where: { $0.id == id }) else { continue }
			var copy = macro
			copy.id = id
			result.macros.append(copy)
			carriedMacroCount += 1
		}
		var carriedScriptCount = 0
		for script in source.scripts {
			let id = scriptRemap[script.id] ?? script.id
			guard referencedScripts.contains(id), !result.scripts.contains(where: { $0.id == id }) else { continue }
			var copy = script
			copy.id = id
			result.scripts.append(copy)
			carriedScriptCount += 1
		}

		for button in buttons {
			result.updateOuraMotionOutputModeIfNeeded(afterChanging: button)
		}

		return ControllerMappingTransferPlan(
			result: result,
			copiedCount: stats.copiedCount,
			overwritten: stats.overwritten,
			clearedCount: stats.clearedCount,
			createdLayerNames: createdLayerNames,
			skippedLayerNames: skippedLayerNames,
			carriedMacroCount: carriedMacroCount,
			carriedScriptCount: carriedScriptCount
		)
	}

	// MARK: - Private

	private struct Stats {
		var copiedCount = 0
		var clearedCount = 0
		var overwritten: [ControllerMappingTransferPlan.Change] = []
		var written: [KeyMapping] = []
	}

	private static func transfer(
		_ source: [ControllerButton: KeyMapping],
		into destination: inout [ControllerButton: KeyMapping],
		buttons: Set<ControllerButton>,
		mode: ControllerMappingTransferOptions.Mode,
		layerName: String?,
		stats: inout Stats
	) {
		for button in buttons.sorted(by: { $0.rawValue < $1.rawValue }) {
			let incoming = source[button].flatMap { $0.hasConfiguredBehavior ? $0 : nil }
			let existing = destination[button].flatMap { $0.hasConfiguredBehavior ? $0 : nil }
			switch mode {
			case .replace:
				guard incoming != existing else { continue }
				if let incoming {
					if existing != nil {
						stats.overwritten.append(.init(button: button, layerName: layerName))
					}
					destination[button] = incoming
					stats.written.append(incoming)
					stats.copiedCount += 1
				} else {
					destination.removeValue(forKey: button)
					stats.clearedCount += 1
				}
			case .fillEmpty:
				guard existing == nil, let incoming else { continue }
				destination[button] = incoming
				stats.written.append(incoming)
				stats.copiedCount += 1
			}
		}
	}

	/// Source IDs that collide with a *different* destination item get a fresh ID.
	private static func remap<Item: Identifiable & Equatable>(
		_ source: [Item],
		into destination: [Item]
	) -> [UUID: UUID] where Item.ID == UUID {
		var remap: [UUID: UUID] = [:]
		for item in source {
			if let existing = destination.first(where: { $0.id == item.id }), existing != item {
				remap[item.id] = UUID()
			}
		}
		return remap
	}

	private static func remapped(_ mapping: KeyMapping, macros: [UUID: UUID], scripts: [UUID: UUID]) -> KeyMapping {
		guard !macros.isEmpty || !scripts.isEmpty else { return mapping }
		var updated = mapping
		updated.macroId = updated.macroId.map { macros[$0] ?? $0 }
		updated.scriptId = updated.scriptId.map { scripts[$0] ?? $0 }
		if var longHold = updated.longHoldMapping {
			longHold.macroId = longHold.macroId.map { macros[$0] ?? $0 }
			longHold.scriptId = longHold.scriptId.map { scripts[$0] ?? $0 }
			updated.longHoldMapping = longHold
		}
		if var doubleTap = updated.doubleTapMapping {
			doubleTap.macroId = doubleTap.macroId.map { macros[$0] ?? $0 }
			doubleTap.scriptId = doubleTap.scriptId.map { scripts[$0] ?? $0 }
			updated.doubleTapMapping = doubleTap
		}
		if var release = updated.releaseMapping {
			release.macroId = release.macroId.map { macros[$0] ?? $0 }
			release.scriptId = release.scriptId.map { scripts[$0] ?? $0 }
			updated.releaseMapping = release
		}
		return updated
	}

	private static func referencedMacroIds(_ mapping: KeyMapping) -> [UUID] {
		[mapping.macroId, mapping.longHoldMapping?.macroId, mapping.doubleTapMapping?.macroId, mapping.releaseMapping?.macroId].compactMap { $0 }
	}

	private static func referencedScriptIds(_ mapping: KeyMapping) -> [UUID] {
		[mapping.scriptId, mapping.longHoldMapping?.scriptId, mapping.doubleTapMapping?.scriptId, mapping.releaseMapping?.scriptId].compactMap { $0 }
	}
}
