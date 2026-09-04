import Foundation
import TriggerKitCore

enum ProfileAutomationReferenceKind: Equatable {
	case macro
	case script
}

struct ProfileAutomationReferenceReport: Equatable {
	let contexts: [String]

	var count: Int { contexts.count }

	var summary: String {
		switch count {
		case 0:
			return String(localized: "Unused")
		case 1:
			return String(localized: "Used in 1 place")
		default:
			return String(format: String(localized: "Used in %lld places"), count)
		}
	}
}

struct ProfileAutomationUsageIndex {
	private let macroContexts: [UUID: [String]]
	private let scriptContexts: [UUID: [String]]

	static func make(for profile: Profile) -> ProfileAutomationUsageIndex {
		var collector = UsageIndexCollector()
		profile.walkSurface(&collector)
		for region in profile.touchpadRegionMappings {
			if let macroId = region.macroId {
				collector.macroContexts[macroId, default: []].append(
					"Touchpad region \(region.region.rawValue) (\(region.triggerMode.rawValue))"
				)
			}
		}
		return ProfileAutomationUsageIndex(
			macroContexts: collector.macroContexts.mapValues { $0.sorted() },
			scriptContexts: collector.scriptContexts.mapValues { $0.sorted() }
		)
	}

	func report(for id: UUID, kind: ProfileAutomationReferenceKind) -> ProfileAutomationReferenceReport {
		ProfileAutomationReferenceReport(
			contexts: kind == .macro ? macroContexts[id, default: []] : scriptContexts[id, default: []]
		)
	}
}

/// Single source of truth for dependency reporting and cleanup when a
/// profile-owned macro or script is deleted.
enum ProfileAutomationReferencePolicy {
	static func report(
		for id: UUID,
		kind: ProfileAutomationReferenceKind,
		in profile: Profile
	) -> ProfileAutomationReferenceReport {
		ProfileAutomationUsageIndex.make(for: profile).report(for: id, kind: kind)
	}

	static func removingReferences(
		to id: UUID,
		kind: ProfileAutomationReferenceKind,
		from profile: Profile
	) -> Profile {
		var result = profile

		result.buttonMappings = cleanedMappings(result.buttonMappings, id: id, kind: kind)
		for index in result.layers.indices {
			result.layers[index].buttonMappings = cleanedMappings(
				result.layers[index].buttonMappings,
				id: id,
				kind: kind
			)
			result.layers[index].commandWheelActions = result.layers[index].commandWheelActions?.map {
				cleanedAction($0, id: id, kind: kind)
			}
		}

		result.chordMappings = result.chordMappings.map { cleanedAction($0, id: id, kind: kind) }
		result.sequenceMappings = result.sequenceMappings.map { cleanedAction($0, id: id, kind: kind) }
		result.gestureMappings = result.gestureMappings.map { cleanedAction($0, id: id, kind: kind) }
		result.commandWheelActions = result.commandWheelActions.map { cleanedAction($0, id: id, kind: kind) }

		result.macros = result.macros.map { macro in
			var updated = macro
			updated.steps = macro.steps.compactMap { cleanedStep($0, id: id, kind: kind) }
			return updated
		}

		if kind == .macro {
			result.touchpadRegionMappings = result.touchpadRegionMappings.compactMap { region in
				var updated = region
				if updated.macroId == id {
					if updated.systemCommand == nil {
						// Macro outranks the legacy region's key binding. Clear both so
						// deleting the macro cannot make that dormant key executable.
						updated.keyCode = nil
						updated.modifiers = ModifierFlags()
						updated.hint = nil
					}
					// A system command outranks the macro. In that malformed-but-
					// decodable state, preserve the command and its metadata.
					updated.macroId = nil
				}
				return updated.isEmpty ? nil : updated
			}
		}

		return result
	}

	private static func cleanedMappings(
		_ mappings: [ControllerButton: KeyMapping],
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> [ControllerButton: KeyMapping] {
		mappings.compactMapValues { mapping in
			let updated = cleanedMapping(mapping, id: id, kind: kind)
			return updated.hasConfiguredBehavior ? updated : nil
		}
	}

	private static func cleanedMapping(
		_ mapping: KeyMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> KeyMapping {
		var updated = mapping
		clearReference(in: &updated, id: id, kind: kind)

		if var longHold = updated.longHoldMapping {
			clearReference(in: &longHold, id: id, kind: kind)
			updated.longHoldMapping = longHold.isEmpty ? nil : longHold
		}
		if var doubleTap = updated.doubleTapMapping {
			clearReference(in: &doubleTap, id: id, kind: kind)
			updated.doubleTapMapping = doubleTap.isEmpty ? nil : doubleTap
		}
		return updated
	}

	private static func cleanedStep(
		_ step: MacroStep,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> MacroStep? {
		switch step {
		case .press(let mapping):
			let cleaned = cleanedMacroStepMapping(mapping, id: id, kind: kind)
			return macroStepHasExecutableKeystroke(cleaned) ? .press(cleaned) : nil
		case .hold(let mapping, let duration):
			let cleaned = cleanedMacroStepMapping(mapping, id: id, kind: kind)
			return macroStepHasExecutableKeystroke(cleaned) ? .hold(cleaned, duration: duration) : nil
		default:
			return step
		}
	}

	/// Macro press/hold steps execute only the embedded keystroke. Other action
	/// fields can survive old imports, but they never outrank or replace that
	/// keystroke in `MacroAutomationBridge`. Removing an automation dependency
	/// must therefore strip only the stale ID instead of applying normal button
	/// action precedence and accidentally deleting a working key step.
	private static func cleanedMacroStepMapping(
		_ mapping: KeyMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> KeyMapping {
		var updated = mapping
		if matches(updated, id: id, kind: kind) {
			removeReferenceOnly(from: &updated, kind: kind)
		}
		if var longHold = updated.longHoldMapping,
		   matches(longHold, id: id, kind: kind) {
			removeReferenceOnly(from: &longHold, kind: kind)
			updated.longHoldMapping = longHold.isEmpty ? nil : longHold
		}
		if var doubleTap = updated.doubleTapMapping,
		   matches(doubleTap, id: id, kind: kind) {
			removeReferenceOnly(from: &doubleTap, kind: kind)
			updated.doubleTapMapping = doubleTap.isEmpty ? nil : doubleTap
		}
		return updated
	}

	private static func macroStepHasExecutableKeystroke(_ mapping: KeyMapping) -> Bool {
		mapping.keyCode != nil || mapping.modifiers.hasAny
	}

	private static func clearReference(
		in action: inout KeyMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) {
		guard matches(action, id: id, kind: kind) else { return }
		if referenceIsEffective(action, id: id, kind: kind) {
			action = action.clearingConflicts(keeping: .none)
			action.repeatMapping = nil
			action.hint = nil
			action.hapticStyle = nil
		} else {
			removeReferenceOnly(from: &action, kind: kind)
		}
	}

	private static func clearReference(
		in action: inout LongHoldMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) {
		guard matches(action, id: id, kind: kind) else { return }
		if referenceIsEffective(action, id: id, kind: kind) {
			action = action.clearingConflicts(keeping: .none)
			action.hint = nil
			action.hapticStyle = nil
		} else {
			removeReferenceOnly(from: &action, kind: kind)
		}
	}

	private static func clearReference(
		in action: inout DoubleTapMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) {
		guard matches(action, id: id, kind: kind) else { return }
		if referenceIsEffective(action, id: id, kind: kind) {
			action = action.clearingConflicts(keeping: .none)
			action.hint = nil
			action.hapticStyle = nil
		} else {
			removeReferenceOnly(from: &action, kind: kind)
		}
	}

	private static func cleanedAction(
		_ action: ChordMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> ChordMapping {
		guard matches(action, id: id, kind: kind) else { return action }
		guard !referenceIsEffective(action, id: id, kind: kind) else {
			return action.clearingAllActions()
		}
		var updated = action
		removeReferenceOnly(from: &updated, kind: kind)
		return updated
	}

	private static func cleanedAction(
		_ action: SequenceMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> SequenceMapping {
		guard matches(action, id: id, kind: kind) else { return action }
		guard !referenceIsEffective(action, id: id, kind: kind) else {
			return action.clearingAllActions()
		}
		var updated = action
		removeReferenceOnly(from: &updated, kind: kind)
		return updated
	}

	private static func cleanedAction(
		_ action: GestureMapping,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> GestureMapping {
		guard matches(action, id: id, kind: kind) else { return action }
		guard !referenceIsEffective(action, id: id, kind: kind) else {
			return action.clearingAllActions()
		}
		var updated = action
		removeReferenceOnly(from: &updated, kind: kind)
		return updated
	}

	private static func cleanedAction(
		_ action: CommandWheelAction,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> CommandWheelAction {
		var updated = action
		guard matches(action, id: id, kind: kind) else { return action }
		if referenceIsEffective(action, id: id, kind: kind) {
			updated.keyCode = nil
			updated.modifiers = ModifierFlags()
			updated.macroId = nil
			updated.scriptId = nil
			updated.systemCommand = nil
			updated.midiControlChange = nil
			updated.hint = nil
			updated.hapticStyle = nil
		} else {
			removeReferenceOnly(from: &updated, kind: kind)
		}
		return updated
	}

	/// True only when the deleted reference is the action the executor would
	/// currently run. Higher-priority actions make the reference dormant; those
	/// bindings must survive deletion unchanged apart from the stale ID.
	private static func referenceIsEffective(
		_ action: any ExecutableAction,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> Bool {
		guard matches(action, id: id, kind: kind) else { return false }
		switch kind {
		case .macro: return action.effectiveActionType == .macro
		case .script: return action.effectiveActionType == .script
		}
	}

	private static func removeReferenceOnly(from action: inout KeyMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout LongHoldMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout DoubleTapMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout ChordMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout SequenceMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout GestureMapping, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func removeReferenceOnly(from action: inout CommandWheelAction, kind: ProfileAutomationReferenceKind) {
		switch kind {
		case .macro: action.macroId = nil
		case .script: action.scriptId = nil
		}
	}

	private static func matches(
		_ action: any ExecutableAction,
		id: UUID,
		kind: ProfileAutomationReferenceKind
	) -> Bool {
		switch kind {
		case .macro: return action.macroId == id
		case .script: return action.scriptId == id
		}
	}
}

private struct UsageIndexCollector: ProfileSurfaceVisitor {
	var macroContexts: [UUID: [String]] = [:]
	var scriptContexts: [UUID: [String]] = [:]

	mutating func visit(systemCommand: SystemCommand, context: String) {}

	mutating func visit(macroStep: MacroStep, context: String) {
		// Macro press/hold steps execute only their key and modifiers. Old
		// imported automation IDs in the embedded KeyMapping are inert metadata,
		// not real dependencies and therefore not part of deletion warnings.
	}

	mutating func visit(script: Script) {}
	mutating func visit(quickText: QuickText) {}
	mutating func visit(automationStep: AutomationStep, context: String) {}

	mutating func visit(action: any ExecutableAction, context: String) {
		collect(action, context: context)
	}

	private mutating func collect(_ mapping: KeyMapping, context: String) {
		collect(mapping as any ExecutableAction, context: context)
		if let longHold = mapping.longHoldMapping {
			collect(longHold, context: "\(context) (long hold)")
		}
		if let doubleTap = mapping.doubleTapMapping {
			collect(doubleTap, context: "\(context) (double tap)")
		}
	}

	private mutating func collect(_ action: any ExecutableAction, context: String) {
		if let id = action.macroId { macroContexts[id, default: []].append(context) }
		if let id = action.scriptId { scriptContexts[id, default: []].append(context) }
	}
}
