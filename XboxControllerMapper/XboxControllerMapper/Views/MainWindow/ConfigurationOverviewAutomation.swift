import Foundation
import TriggerKitCore

extension ConfigurationOverviewBuilder {
	static func automationRows(
		profile: Profile,
		sharedLibraryMacros: [AutomationMacro]
	) -> [ConfigurationOverviewRow] {
		let usageIndex = ProfileAutomationUsageIndex.make(for: profile)
		let macros = profile.macros.map { macro in
			let name = macro.name.trimmingCharacters(in: .whitespacesAndNewlines)
			let stepLabel = macro.steps.count == 1
				? String(localized: "1 step")
				: String(format: String(localized: "%lld steps"), macro.steps.count)
			let usage = usageIndex.report(for: macro.id, kind: .macro)
			return ConfigurationOverviewRow(
				id: "macro-\(macro.id.uuidString)",
				category: .automations,
				trigger: name.isEmpty ? String(localized: "Unnamed Macro") : name,
				action: String(localized: "Macro"),
				detail: "\(stepLabel) · \(usage.summary)",
				source: .profile,
				systemImage: "play.rectangle.on.rectangle",
				target: .section(MainWindowSection.macros.rawValue),
				isCurrentDevice: true
			)
		}

		let scripts = profile.scripts.map { script in
			let name = script.name.trimmingCharacters(in: .whitespacesAndNewlines)
			let description = script.description?.trimmingCharacters(in: .whitespacesAndNewlines)
			let usage = usageIndex.report(for: script.id, kind: .script)
			let detail = description.flatMap { $0.isEmpty ? nil : $0 }
				.map { "\($0) · \(usage.summary)" }
				?? usage.summary
			return ConfigurationOverviewRow(
				id: "script-\(script.id.uuidString)",
				category: .automations,
				trigger: name.isEmpty ? String(localized: "Untitled Script") : name,
				action: String(localized: "Script"),
				detail: detail,
				source: .profile,
				systemImage: "curlybraces",
				target: .section(MainWindowSection.scripts.rawValue),
				isCurrentDevice: true
			)
		}

		let libraryByID = Dictionary(uniqueKeysWithValues: sharedLibraryMacros.map { ($0.id, $0) })
		let sharedSnapshots = profile.sharedMacroSnapshots
			.sorted { lhs, rhs in
				lhs.value.name.localizedCaseInsensitiveCompare(rhs.value.name) == .orderedAscending
			}
			.map { id, program in
				let live = libraryByID[id]
				let effectiveProgram = live?.program ?? program
				let name = (live?.name ?? effectiveProgram.name).trimmingCharacters(in: .whitespacesAndNewlines)
				let stepCount = effectiveProgram.steps.count
				let steps = stepCount == 1
					? String(localized: "1 step")
					: String(format: String(localized: "%lld steps"), stepCount)
				return ConfigurationOverviewRow(
					id: "shared-macro-\(id.uuidString)",
					category: .automations,
					trigger: name.isEmpty ? String(localized: "Unnamed Shared Macro") : name,
					action: live == nil ? String(localized: "Saved Shared Macro Copy") : String(localized: "Shared Macro"),
					detail: "\(steps) · \(usageIndex.report(for: id, kind: .macro).summary)",
					source: live == nil ? .profile : .library,
					systemImage: "shippingbox.fill",
					target: .section(MainWindowSection.macros.rawValue),
					isCurrentDevice: true
				)
			}

		return macros + scripts + sharedSnapshots
	}

	static func actionName(_ action: any ExecutableAction, profile: Profile) -> String {
		if let hint = action.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
			return hint
		}
		return underlyingActionName(action, profile: profile)
	}

	static func underlyingActionName(_ action: any ExecutableAction, profile: Profile) -> String {
		switch action.effectiveActionType {
		case .systemCommand:
			return action.systemCommand?.displayName ?? String(localized: "None")
		case .macro:
			guard let macroId = action.macroId else { return String(localized: "Missing macro") }
			return profile.macroDisplayName(for: macroId) ?? String(localized: "Missing macro")
		case .script:
			guard let scriptId = action.scriptId else { return String(localized: "Missing script") }
			return profile.scripts.first(where: { $0.id == scriptId })?.name ?? String(localized: "Missing script")
		case .midiControlChange:
			return action.midiControlChange?.displayString ?? String(localized: "None")
		case .keyPress:
			return action.displayString
		case .none:
			return String(localized: "None")
		}
	}

	static func buttonActionName(_ mapping: KeyMapping, profile: Profile) -> String {
		if !mapping.isEmpty { return actionName(mapping, profile: profile) }
		let hold = mapping.longHoldMapping.flatMap { $0.isEmpty ? nil : actionName($0, profile: profile) }
		let doubleTap = mapping.doubleTapMapping.flatMap { $0.isEmpty ? nil : actionName($0, profile: profile) }
		switch (hold, doubleTap) {
		case let (.some(action), .none):
			return String(format: String(localized: "Hold only: %@"), action)
		case let (.none, .some(action)):
			return String(format: String(localized: "Double tap only: %@"), action)
		case (.some, .some):
			return String(localized: "Hold and double tap only")
		case (.none, .none):
			return String(localized: "None")
		}
	}

	static func actionDetail(
		_ action: any ExecutableAction,
		prefix: String,
		profile: Profile
	) -> String {
		let hint = action.hint?.trimmingCharacters(in: .whitespacesAndNewlines)
		let underlying = underlyingActionName(action, profile: profile)
		guard let hint, !hint.isEmpty, hint != underlying else { return prefix }
		return "\(prefix) · \(underlying)"
	}

	static func buttonDetail(_ mapping: KeyMapping, profile: Profile) -> String? {
		var details: [String] = []
		if let hint = mapping.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
			let underlying = underlyingActionName(mapping, profile: profile)
			if underlying != hint { details.append(underlying) }
		}
		if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
			let action = actionName(longHold, profile: profile)
			let underlying = underlyingActionName(longHold, profile: profile)
			let value = action == underlying ? action : "\(action) (\(underlying))"
			details.append(String(format: String(localized: "Hold: %@"), value))
		}
		if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
			let action = actionName(doubleTap, profile: profile)
			let underlying = underlyingActionName(doubleTap, profile: profile)
			let value = action == underlying ? action : "\(action) (\(underlying))"
			details.append(String(format: String(localized: "Double tap: %@"), value))
		}
		if let repeatMapping = mapping.repeatMapping, repeatMapping.enabled {
			details.append(String(format: String(localized: "Repeat: %lld/s"), Int(repeatMapping.ratePerSecond)))
		}
		return details.isEmpty ? nil : details.joined(separator: " · ")
	}

	static func legacyTouchpadActionName(
		_ mapping: TouchpadRegionMapping,
		profile: Profile,
		preferHint: Bool
	) -> String {
		if preferHint,
		   let hint = mapping.hint?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !hint.isEmpty {
			return hint
		}
		if let macroId = mapping.macroId {
			return profile.macroDisplayName(for: macroId) ?? String(localized: "Missing macro")
		}
		if let command = mapping.systemCommand { return command.displayName }
		return KeyMapping(keyCode: mapping.keyCode, modifiers: mapping.modifiers).displayString
	}

	static func layerConfigurationCount(_ layer: Layer, profile: Profile) -> Int {
		layer.buttonMappings.values.filter(\.hasConfiguredBehavior).count
			+ (layer.commandWheelActions == nil
				? 0
				: max(layer.commandWheelActions?.filter(\.hasAction).count ?? 0, 1))
			+ (layer.leftStickTuning?.isEmpty == false ? 1 : 0)
			+ (layer.rightStickTuning?.isEmpty == false ? 1 : 0)
			+ (layer.dualSenseLEDSettings == nil ? 0 : 1)
			+ profile.appLayerBindings.values.filter { $0 == layer.id }.count
	}

	static func layerOverrideDetails(_ layer: Layer, profile: Profile) -> [String] {
		var details: [String] = []
		let buttons = layer.buttonMappings.values.filter(\.hasConfiguredBehavior).count
		if buttons > 0 {
			details.append(String(format: String(localized: "%lld button mappings"), buttons))
		}
		if let wheel = layer.commandWheelActions {
			details.append(wheel.isEmpty
				? String(localized: "wheel disabled")
				: String(format: String(localized: "%lld wheel actions"), wheel.filter(\.hasAction).count))
		}
		let sticks = [layer.leftStickTuning, layer.rightStickTuning]
			.compactMap { $0 }
			.filter { !$0.isEmpty }
			.count
		if sticks > 0 {
			details.append(String(format: String(localized: "%lld stick overrides"), sticks))
		}
		if layer.dualSenseLEDSettings != nil { details.append(String(localized: "LED override")) }
		let apps = profile.appLayerBindings.values.filter { $0 == layer.id }.count
		if apps > 0 { details.append(String(format: String(localized: "%lld linked apps"), apps)) }
		return details
	}
}
