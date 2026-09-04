import XCTest
@testable import ControllerKeys

final class ProfileAutomationReferencePolicyTests: XCTestCase {
	func testMacroReportAndCleanupCoverEveryBindingSurface() {
		let targetId = UUID()
		let layer = Layer(
			name: "Editing",
			buttonMappings: [.x: KeyMapping(macroId: targetId)],
			commandWheelActions: [CommandWheelAction(displayName: "Layer Wheel", macroId: targetId)]
		)
		let nestedMacro = Macro(
			name: "Caller",
			steps: [.press(KeyMapping(macroId: targetId))]
		)
		let profile = Profile(
			name: "Work",
			buttonMappings: [
				.a: KeyMapping(
					longHoldMapping: LongHoldMapping(macroId: targetId),
					doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.escape),
					macroId: targetId
				),
				.b: KeyMapping(
					keyCode: KeyCodeMapping.return,
					doubleTapMapping: DoubleTapMapping(macroId: targetId)
				)
			],
			chordMappings: [ChordMapping(buttons: [.a, .b], macroId: targetId)],
			sequenceMappings: [SequenceMapping(steps: [.a, .b], macroId: targetId)],
			macros: [Macro(id: targetId, name: "Target"), nestedMacro],
			gestureMappings: [GestureMapping(gestureType: .tiltBack, macroId: targetId)],
			layers: [layer],
			touchpadRegionMappings: [TouchpadRegionMapping(region: .topLeft, macroId: targetId)],
			commandWheelActions: [CommandWheelAction(displayName: "Base Wheel", macroId: targetId)]
		)

		let report = ProfileAutomationReferencePolicy.report(for: targetId, kind: .macro, in: profile)
		XCTAssertEqual(report.count, 10)

		let cleaned = ProfileAutomationReferencePolicy.removingReferences(
			to: targetId,
			kind: .macro,
			from: profile
		)

		XCTAssertEqual(ProfileAutomationReferencePolicy.report(for: targetId, kind: .macro, in: cleaned).count, 0)
		XCTAssertNotNil(cleaned.buttonMappings[.a]?.doubleTapMapping)
		XCTAssertNotNil(cleaned.buttonMappings[.b])
		XCTAssertTrue(cleaned.touchpadRegionMappings.isEmpty)
	}

	func testScriptReportAndCleanupCoverGestureWheelLayerAndMacroSteps() {
		let targetId = UUID()
		let profile = Profile(
			name: "Work",
			buttonMappings: [.a: KeyMapping(longHoldMapping: LongHoldMapping(scriptId: targetId))],
			macros: [Macro(name: "Caller", steps: [.hold(KeyMapping(scriptId: targetId), duration: 0.2)])],
			gestureMappings: [GestureMapping(gestureType: .steerLeft, scriptId: targetId)],
			layers: [
				Layer(
					name: "Editing",
					buttonMappings: [.b: KeyMapping(doubleTapMapping: DoubleTapMapping(scriptId: targetId))],
					commandWheelActions: [CommandWheelAction(displayName: "Layer Wheel", scriptId: targetId)]
				)
			],
			commandWheelActions: [CommandWheelAction(displayName: "Base Wheel", scriptId: targetId)]
		)

		let report = ProfileAutomationReferencePolicy.report(for: targetId, kind: .script, in: profile)
		XCTAssertEqual(report.count, 5)

		let cleaned = ProfileAutomationReferencePolicy.removingReferences(
			to: targetId,
			kind: .script,
			from: profile
		)
		XCTAssertEqual(ProfileAutomationReferencePolicy.report(for: targetId, kind: .script, in: cleaned).count, 0)
	}

	func testCleanupPreservesHigherActionWithoutAwakeningLowerActions() throws {
		let targetId = UUID()
		let alternate = DoubleTapMapping(keyCode: KeyCodeMapping.space)
		let systemCommand = SystemCommand.openLink(url: "https://example.com")
		let profile = Profile(
			name: "Conflicts",
			buttonMappings: [
				.a: KeyMapping(
					keyCode: KeyCodeMapping.return,
					doubleTapMapping: alternate,
					macroId: targetId,
					systemCommand: systemCommand,
					hint: "Target macro"
				)
			],
			chordMappings: [ChordMapping(
				buttons: [.a, .b],
				keyCode: KeyCodeMapping.escape,
				macroId: targetId,
				hint: "Conflicted chord"
			)],
			commandWheelActions: [CommandWheelAction(
				displayName: "Conflicted wheel",
				keyCode: KeyCodeMapping.escape,
				macroId: targetId,
				hint: "Conflicted wheel"
			)]
		)

		let cleaned = ProfileAutomationReferencePolicy.removingReferences(
			to: targetId,
			kind: .macro,
			from: profile
		)

		let button = try XCTUnwrap(cleaned.buttonMappings[.a])
		XCTAssertNil(button.macroId)
		XCTAssertEqual(button.systemCommand, systemCommand)
		XCTAssertEqual(button.keyCode, KeyCodeMapping.return)
		XCTAssertEqual(button.hint, "Target macro")
		XCTAssertEqual(button.effectiveActionType, .systemCommand)
		XCTAssertEqual(button.doubleTapMapping, alternate)
		XCTAssertFalse(try XCTUnwrap(cleaned.chordMappings.first).hasAction)
		XCTAssertFalse(try XCTUnwrap(cleaned.commandWheelActions.first).hasAction)
	}

	func testDormantReferencesPreserveHigherPriorityActionsAcrossEveryExecutableShape() throws {
		try assertDormantReferenceRemoval(kind: .macro)
		try assertDormantReferenceRemoval(kind: .script)
	}

	func testEffectiveReferencesCannotAwakenLowerPriorityActionsAcrossEveryExecutableShape() throws {
		try assertEffectiveReferenceRemoval(kind: .macro)
		try assertEffectiveReferenceRemoval(kind: .script)
	}

	private func assertDormantReferenceRemoval(
		kind: ProfileAutomationReferenceKind,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws {
		let targetId = UUID()
		let profile = conflictProfile(targetId: targetId, kind: kind, targetIsEffective: false)
		let cleaned = ProfileAutomationReferencePolicy.removingReferences(
			to: targetId,
			kind: kind,
			from: profile
		)

		XCTAssertEqual(
			ProfileAutomationReferencePolicy.report(for: targetId, kind: kind, in: cleaned).count,
			0,
			file: file,
			line: line
		)

		let expectedEffectiveType: ActionType = kind == .macro ? .systemCommand : .macro
		for action in try executableActions(in: cleaned, file: file, line: line) {
			assertReferenceRemoved(action, targetId: targetId, kind: kind, file: file, line: line)
			XCTAssertEqual(action.effectiveActionType, expectedEffectiveType, file: file, line: line)
			XCTAssertEqual(action.keyCode, KeyCodeMapping.return, file: file, line: line)
			XCTAssertTrue(action.modifiers.command, file: file, line: line)
			XCTAssertNotNil(action.midiControlChange, file: file, line: line)
			XCTAssertEqual(action.hint, "Original action", file: file, line: line)
		}

		if kind == .macro {
			let region = try XCTUnwrap(cleaned.touchpadRegionMappings.first, file: file, line: line)
			XCTAssertNil(region.macroId, file: file, line: line)
			XCTAssertNotNil(region.systemCommand, file: file, line: line)
			XCTAssertEqual(region.keyCode, KeyCodeMapping.return, file: file, line: line)
			XCTAssertTrue(region.modifiers.command, file: file, line: line)
			XCTAssertEqual(region.hint, "Original action", file: file, line: line)
		}
	}

	private func assertEffectiveReferenceRemoval(
		kind: ProfileAutomationReferenceKind,
		file: StaticString = #filePath,
		line: UInt = #line
	) throws {
		let targetId = UUID()
		let profile = conflictProfile(targetId: targetId, kind: kind, targetIsEffective: true)
		let cleaned = ProfileAutomationReferencePolicy.removingReferences(
			to: targetId,
			kind: kind,
			from: profile
		)

		XCTAssertEqual(
			ProfileAutomationReferencePolicy.report(for: targetId, kind: kind, in: cleaned).count,
			0,
			file: file,
			line: line
		)
		XCTAssertNil(cleaned.buttonMappings[.a], file: file, line: line)
		XCTAssertNil(cleaned.layers.first?.buttonMappings[.b], file: file, line: line)
		let cleanedStep = try XCTUnwrap(cleaned.macros.first?.steps.first, file: file, line: line)
		switch cleanedStep {
		case .press(let mapping):
			XCTAssertEqual(mapping.keyCode, KeyCodeMapping.return, file: file, line: line)
			XCTAssertTrue(mapping.modifiers.command, file: file, line: line)
			assertReferenceRemoved(mapping, targetId: targetId, kind: kind, file: file, line: line)
		default:
			XCTFail("Expected the working nested key press to survive cleanup", file: file, line: line)
		}

		let persistentActions: [any ExecutableAction] = [
			try XCTUnwrap(cleaned.chordMappings.first, file: file, line: line),
			try XCTUnwrap(cleaned.sequenceMappings.first, file: file, line: line),
			try XCTUnwrap(cleaned.gestureMappings.first, file: file, line: line),
			try XCTUnwrap(cleaned.commandWheelActions.first, file: file, line: line),
			try XCTUnwrap(cleaned.layers.first?.commandWheelActions?.first, file: file, line: line),
		]
		for action in persistentActions {
			assertReferenceRemoved(action, targetId: targetId, kind: kind, file: file, line: line)
			XCTAssertEqual(action.effectiveActionType, .none, file: file, line: line)
			XCTAssertNil(action.keyCode, file: file, line: line)
			XCTAssertFalse(action.modifiers.hasAny, file: file, line: line)
			XCTAssertNil(action.macroId, file: file, line: line)
			XCTAssertNil(action.scriptId, file: file, line: line)
			XCTAssertNil(action.midiControlChange, file: file, line: line)
			XCTAssertNil(action.hint, file: file, line: line)
		}

		if kind == .macro {
			XCTAssertTrue(cleaned.touchpadRegionMappings.isEmpty, file: file, line: line)
		}
	}

	private func conflictProfile(
		targetId: UUID,
		kind: ProfileAutomationReferenceKind,
		targetIsEffective: Bool
	) -> Profile {
		let fields = conflictFields(targetId: targetId, kind: kind, targetIsEffective: targetIsEffective)
		let mapping = conflictKeyMapping(fields: fields, includeAlternates: true)
		let nestedMacro = Macro(
			name: "Caller",
			steps: [.press(conflictKeyMapping(fields: fields, includeAlternates: false))]
		)
		let touchpadRegions: [TouchpadRegionMapping]
		if kind == .macro {
			touchpadRegions = [TouchpadRegionMapping(
				region: .topLeft,
				keyCode: KeyCodeMapping.return,
				modifiers: ModifierFlags(command: true),
				macroId: targetId,
				systemCommand: targetIsEffective ? nil : .openLink(url: "https://example.com"),
				hint: "Original action"
			)]
		} else {
			touchpadRegions = []
		}

		return Profile(
			name: "Conflict Fixture",
			buttonMappings: [.a: mapping],
			chordMappings: [ChordMapping(
				buttons: [.a, .b],
				keyCode: KeyCodeMapping.return,
				modifiers: ModifierFlags(command: true),
				macroId: fields.macroId,
				scriptId: fields.scriptId,
				systemCommand: fields.systemCommand,
				midiControlChange: fields.midiControlChange,
				hint: "Original action"
			)],
			sequenceMappings: [SequenceMapping(
				steps: [.a, .b],
				keyCode: KeyCodeMapping.return,
				modifiers: ModifierFlags(command: true),
				macroId: fields.macroId,
				scriptId: fields.scriptId,
				systemCommand: fields.systemCommand,
				midiControlChange: fields.midiControlChange,
				hint: "Original action"
			)],
			macros: [nestedMacro],
			gestureMappings: [GestureMapping(
				gestureType: .tiltBack,
				keyCode: KeyCodeMapping.return,
				modifiers: ModifierFlags(command: true),
				macroId: fields.macroId,
				scriptId: fields.scriptId,
				systemCommand: fields.systemCommand,
				midiControlChange: fields.midiControlChange,
				hint: "Original action"
			)],
			layers: [Layer(
				name: "Layer",
				buttonMappings: [.b: mapping],
				commandWheelActions: [conflictWheel(fields: fields, name: "Layer Wheel")]
			)],
			touchpadRegionMappings: touchpadRegions,
			commandWheelActions: [conflictWheel(fields: fields, name: "Base Wheel")]
		)
	}

	private func conflictFields(
		targetId: UUID,
		kind: ProfileAutomationReferenceKind,
		targetIsEffective: Bool
	) -> ConflictFields {
		switch (kind, targetIsEffective) {
		case (.macro, true):
			return ConflictFields(macroId: targetId, scriptId: UUID(), systemCommand: nil)
		case (.macro, false):
			return ConflictFields(
				macroId: targetId,
				scriptId: UUID(),
				systemCommand: .openLink(url: "https://example.com")
			)
		case (.script, true):
			return ConflictFields(macroId: nil, scriptId: targetId, systemCommand: nil)
		case (.script, false):
			return ConflictFields(macroId: UUID(), scriptId: targetId, systemCommand: nil)
		}
	}

	private func conflictKeyMapping(fields: ConflictFields, includeAlternates: Bool) -> KeyMapping {
		let longHold = includeAlternates ? LongHoldMapping(
			keyCode: KeyCodeMapping.return,
			modifiers: ModifierFlags(command: true),
			macroId: fields.macroId,
			scriptId: fields.scriptId,
			systemCommand: fields.systemCommand,
			midiControlChange: fields.midiControlChange,
			hint: "Original action"
		) : nil
		let doubleTap = includeAlternates ? DoubleTapMapping(
			keyCode: KeyCodeMapping.return,
			modifiers: ModifierFlags(command: true),
			macroId: fields.macroId,
			scriptId: fields.scriptId,
			systemCommand: fields.systemCommand,
			midiControlChange: fields.midiControlChange,
			hint: "Original action"
		) : nil
		return KeyMapping(
			keyCode: KeyCodeMapping.return,
			modifiers: ModifierFlags(command: true),
			longHoldMapping: longHold,
			doubleTapMapping: doubleTap,
			macroId: fields.macroId,
			scriptId: fields.scriptId,
			systemCommand: fields.systemCommand,
			midiControlChange: fields.midiControlChange,
			hint: "Original action"
		)
	}

	private func conflictWheel(fields: ConflictFields, name: String) -> CommandWheelAction {
		CommandWheelAction(
			displayName: name,
			keyCode: KeyCodeMapping.return,
			modifiers: ModifierFlags(command: true),
			macroId: fields.macroId,
			scriptId: fields.scriptId,
			systemCommand: fields.systemCommand,
			midiControlChange: fields.midiControlChange,
			hint: "Original action"
		)
	}

	private func executableActions(
		in profile: Profile,
		file: StaticString,
		line: UInt
	) throws -> [any ExecutableAction] {
		var actions: [any ExecutableAction] = []
		func append(_ mapping: KeyMapping) {
			actions.append(mapping)
			if let longHold = mapping.longHoldMapping { actions.append(longHold) }
			if let doubleTap = mapping.doubleTapMapping { actions.append(doubleTap) }
		}

		append(try XCTUnwrap(profile.buttonMappings[.a], file: file, line: line))
		actions.append(try XCTUnwrap(profile.chordMappings.first, file: file, line: line))
		actions.append(try XCTUnwrap(profile.sequenceMappings.first, file: file, line: line))
		actions.append(try XCTUnwrap(profile.gestureMappings.first, file: file, line: line))
		actions.append(try XCTUnwrap(profile.commandWheelActions.first, file: file, line: line))
		let layer = try XCTUnwrap(profile.layers.first, file: file, line: line)
		append(try XCTUnwrap(layer.buttonMappings[.b], file: file, line: line))
		actions.append(try XCTUnwrap(layer.commandWheelActions?.first, file: file, line: line))

		let step = try XCTUnwrap(profile.macros.first?.steps.first, file: file, line: line)
		if case .press(let mapping) = step {
			append(mapping)
		} else {
			XCTFail("Expected press macro step", file: file, line: line)
		}
		return actions
	}

	private func assertReferenceRemoved(
		_ action: any ExecutableAction,
		targetId: UUID,
		kind: ProfileAutomationReferenceKind,
		file: StaticString,
		line: UInt
	) {
		switch kind {
		case .macro:
			XCTAssertNotEqual(action.macroId, targetId, file: file, line: line)
		case .script:
			XCTAssertNotEqual(action.scriptId, targetId, file: file, line: line)
		}
	}
}

private struct ConflictFields {
	let macroId: UUID?
	let scriptId: UUID?
	let systemCommand: SystemCommand?
	let midiControlChange = MIDIControlChange(channel: 2, controller: 11)
}
