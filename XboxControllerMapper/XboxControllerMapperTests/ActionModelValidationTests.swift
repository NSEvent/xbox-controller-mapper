import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Tests for action conflict validation on mapping models.
///
/// The execution layer picks one action via priority:
///   systemCommand > macroId > scriptId > keyCode/modifiers
/// These tests verify that the validation API correctly detects when
/// multiple action fields are set simultaneously.
final class ActionModelValidationTests: XCTestCase {

    // MARK: - Shared Fixtures

    private let testKeyCode: CGKeyCode = 0x00  // 'a'
    private let testMacroId = UUID()
    private let testScriptId = UUID()
    private let testSystemCommand = SystemCommand.shellCommand(command: "echo test", inTerminal: false)

    // MARK: - KeyMapping: Single Action (Valid)

    func testKeyMapping_onlyKeyCode_isNotConflicting() {
        let mapping = KeyMapping(keyCode: testKeyCode)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
    }

    func testKeyMapping_onlyModifiers_isNotConflicting() {
        let mapping = KeyMapping(modifiers: .command)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
    }

    func testKeyMapping_onlyMacroId_isNotConflicting() {
        let mapping = KeyMapping(macroId: testMacroId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testKeyMapping_onlyScriptId_isNotConflicting() {
        let mapping = KeyMapping(scriptId: testScriptId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    func testKeyMapping_onlySystemCommand_isNotConflicting() {
        let mapping = KeyMapping(systemCommand: testSystemCommand)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    func testKeyMapping_empty_hasNoConflicts() {
        let mapping = KeyMapping()
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 0)
        XCTAssertEqual(mapping.effectiveActionType, .none)
    }

    // MARK: - KeyMapping: Conflicting Actions

    func testKeyMapping_keyCodeAndMacroId_isConflicting() {
        let mapping = KeyMapping(keyCode: testKeyCode, macroId: testMacroId)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        // macroId has higher priority than keyCode
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testKeyMapping_keyCodeAndScriptId_isConflicting() {
        let mapping = KeyMapping(keyCode: testKeyCode, scriptId: testScriptId)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    func testKeyMapping_keyCodeAndSystemCommand_isConflicting() {
        let mapping = KeyMapping(keyCode: testKeyCode, systemCommand: testSystemCommand)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    func testKeyMapping_macroIdAndScriptId_isConflicting() {
        let mapping = KeyMapping(macroId: testMacroId, scriptId: testScriptId)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        // macroId has higher priority than scriptId
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testKeyMapping_allActionsSet_isConflicting() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            modifiers: .shift,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 4)
        // systemCommand wins
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    // MARK: - KeyMapping: effectiveAction Priority Order

    func testKeyMapping_effectiveActionPriority_systemCommandWinsOverAll() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    func testKeyMapping_effectiveActionPriority_macroWinsOverScriptAndKey() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId
        )
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testKeyMapping_effectiveActionPriority_scriptWinsOverKey() {
        let mapping = KeyMapping(keyCode: testKeyCode, scriptId: testScriptId)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    // MARK: - KeyMapping: activeActionTypes

    func testKeyMapping_activeActionTypes_reportsAllSetTypes() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let expected: Set<ActionType> = [.keyPress, .macro, .script, .systemCommand]
        XCTAssertEqual(mapping.activeActionTypes, expected)
    }

    func testKeyMapping_activeActionTypes_emptyMappingReturnsEmptySet() {
        let mapping = KeyMapping()
        XCTAssertTrue(mapping.activeActionTypes.isEmpty)
    }

    // MARK: - KeyMapping: clearingConflicts

    func testKeyMapping_clearingConflicts_keepingKeyPress() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            modifiers: .shift,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .keyPress)
        XCTAssertEqual(cleaned.keyCode, testKeyCode)
        XCTAssertEqual(cleaned.modifiers, ModifierFlags.shift)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
        XCTAssertEqual(cleaned.effectiveActionType, .keyPress)
    }

    func testKeyMapping_clearingConflicts_keepingMacro() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .macro)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertEqual(cleaned.modifiers, ModifierFlags())
        XCTAssertEqual(cleaned.macroId, testMacroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    func testKeyMapping_clearingConflicts_keepingScript() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .script)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertNil(cleaned.macroId)
        XCTAssertEqual(cleaned.scriptId, testScriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    func testKeyMapping_clearingConflicts_keepingSystemCommand() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .systemCommand)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertEqual(cleaned.systemCommand, testSystemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    func testKeyMapping_clearingConflicts_keepingNone_clearsEverything() {
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .none)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertEqual(cleaned.modifiers, ModifierFlags())
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testKeyMapping_clearingConflicts_preservesNonActionFields() {
        let longHold = LongHoldMapping(keyCode: 0x01)
        let doubleTap = DoubleTapMapping(keyCode: 0x02)
        let mapping = KeyMapping(
            keyCode: testKeyCode,
            longHoldMapping: longHold,
            doubleTapMapping: doubleTap,
            isHoldModifier: true,
            macroId: testMacroId,
            hint: "test hint"
        )
        let cleaned = mapping.clearingConflicts(keeping: .macro)
        // Non-action fields should be preserved
        XCTAssertEqual(cleaned.longHoldMapping, longHold)
        XCTAssertEqual(cleaned.doubleTapMapping, doubleTap)
        XCTAssertTrue(cleaned.isHoldModifier)
        XCTAssertEqual(cleaned.hint, "test hint")
    }

    // MARK: - ChordMapping: Single Action (Valid)

    func testChordMapping_onlyKeyCode_isNotConflicting() {
        let mapping = ChordMapping(buttons: [.a, .b], keyCode: testKeyCode)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
    }

    func testChordMapping_onlyMacroId_isNotConflicting() {
        let mapping = ChordMapping(buttons: [.a, .b], macroId: testMacroId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testChordMapping_onlyScriptId_isNotConflicting() {
        let mapping = ChordMapping(buttons: [.a, .b], scriptId: testScriptId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    func testChordMapping_onlySystemCommand_isNotConflicting() {
        let mapping = ChordMapping(buttons: [.a, .b], systemCommand: testSystemCommand)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    // MARK: - ChordMapping: Conflicting Actions

    func testChordMapping_keyCodeAndMacroId_isConflicting() {
        let mapping = ChordMapping(buttons: [.a, .b], keyCode: testKeyCode, macroId: testMacroId)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testChordMapping_allActionsSet_isConflicting() {
        let mapping = ChordMapping(
            buttons: [.a, .b],
            keyCode: testKeyCode,
            modifiers: .command,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 4)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    // MARK: - ChordMapping: clearingConflicts

    func testChordMapping_clearingConflicts_keepingMacro() {
        let mapping = ChordMapping(
            buttons: [.a, .b],
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand,
            hint: "chord hint"
        )
        let cleaned = mapping.clearingConflicts(keeping: .macro)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertEqual(cleaned.macroId, testMacroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
        // Preserved fields
        XCTAssertEqual(cleaned.buttons, [.a, .b])
        XCTAssertEqual(cleaned.hint, "chord hint")
        XCTAssertEqual(cleaned.id, mapping.id)
    }

    func testChordMapping_clearingConflicts_keepingSystemCommand() {
        let mapping = ChordMapping(
            buttons: [.x, .y],
            keyCode: testKeyCode,
            macroId: testMacroId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .systemCommand)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertEqual(cleaned.systemCommand, testSystemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    // MARK: - SequenceMapping: Single Action (Valid)

    func testSequenceMapping_onlyKeyCode_isNotConflicting() {
        let mapping = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], keyCode: testKeyCode)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
    }

    func testSequenceMapping_onlyMacroId_isNotConflicting() {
        let mapping = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], macroId: testMacroId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testSequenceMapping_onlyScriptId_isNotConflicting() {
        let mapping = SequenceMapping(steps: [.dpadDown, .a], scriptId: testScriptId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    func testSequenceMapping_onlySystemCommand_isNotConflicting() {
        let mapping = SequenceMapping(steps: [.dpadDown, .a], systemCommand: testSystemCommand)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    // MARK: - SequenceMapping: Conflicting Actions

    func testSequenceMapping_keyCodeAndMacroId_isConflicting() {
        let mapping = SequenceMapping(
            steps: [.dpadDown, .a],
            keyCode: testKeyCode,
            macroId: testMacroId
        )
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testSequenceMapping_allActionsSet_isConflicting() {
        let mapping = SequenceMapping(
            steps: [.dpadDown, .a],
            keyCode: testKeyCode,
            modifiers: .option,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 4)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    // MARK: - SequenceMapping: clearingConflicts

    func testSequenceMapping_clearingConflicts_keepingScript() {
        let mapping = SequenceMapping(
            steps: [.dpadDown, .a],
            keyCode: testKeyCode,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand,
            hint: "seq hint"
        )
        let cleaned = mapping.clearingConflicts(keeping: .script)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertNil(cleaned.macroId)
        XCTAssertEqual(cleaned.scriptId, testScriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
        // Preserved fields
        XCTAssertEqual(cleaned.steps, [.dpadDown, .a])
        XCTAssertEqual(cleaned.hint, "seq hint")
        XCTAssertEqual(cleaned.id, mapping.id)
    }

    func testSequenceMapping_clearingConflicts_keepingKeyPress() {
        let mapping = SequenceMapping(
            steps: [.a, .b],
            keyCode: testKeyCode,
            modifiers: .command,
            macroId: testMacroId,
            scriptId: testScriptId
        )
        let cleaned = mapping.clearingConflicts(keeping: .keyPress)
        XCTAssertEqual(cleaned.keyCode, testKeyCode)
        XCTAssertEqual(cleaned.modifiers, ModifierFlags.command)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    // MARK: - LongHoldMapping & DoubleTapMapping: Validation

    func testLongHoldMapping_singleAction_isNotConflicting() {
        let mapping = LongHoldMapping(keyCode: testKeyCode)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
    }

    func testLongHoldMapping_conflicting_isDetected() {
        let mapping = LongHoldMapping(keyCode: testKeyCode, macroId: testMacroId)
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 2)
        XCTAssertEqual(mapping.effectiveActionType, .macro)
    }

    func testLongHoldMapping_clearingConflicts_keepingKeyPress() {
        let mapping = LongHoldMapping(
            keyCode: testKeyCode,
            modifiers: .shift,
            macroId: testMacroId,
            scriptId: testScriptId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .keyPress)
        XCTAssertEqual(cleaned.keyCode, testKeyCode)
        XCTAssertEqual(cleaned.modifiers, ModifierFlags.shift)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    func testDoubleTapMapping_singleAction_isNotConflicting() {
        let mapping = DoubleTapMapping(scriptId: testScriptId)
        XCTAssertFalse(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.effectiveActionType, .script)
    }

    func testDoubleTapMapping_conflicting_isDetected() {
        let mapping = DoubleTapMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            systemCommand: testSystemCommand
        )
        XCTAssertTrue(mapping.hasConflictingActions)
        XCTAssertEqual(mapping.activeActionCount, 3)
        XCTAssertEqual(mapping.effectiveActionType, .systemCommand)
    }

    func testDoubleTapMapping_clearingConflicts_keepingMacro() {
        let mapping = DoubleTapMapping(
            keyCode: testKeyCode,
            macroId: testMacroId,
            systemCommand: testSystemCommand
        )
        let cleaned = mapping.clearingConflicts(keeping: .macro)
        XCTAssertNil(cleaned.keyCode)
        XCTAssertEqual(cleaned.macroId, testMacroId)
        XCTAssertNil(cleaned.systemCommand)
        XCTAssertFalse(cleaned.hasConflictingActions)
    }

    // MARK: - ActionType Enum

    func testActionType_allCases() {
        let cases = ActionType.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.keyPress))
        XCTAssertTrue(cases.contains(.macro))
        XCTAssertTrue(cases.contains(.script))
        XCTAssertTrue(cases.contains(.systemCommand))
        XCTAssertTrue(cases.contains(.none))
    }

    func testActionType_rawValues() {
        XCTAssertEqual(ActionType.keyPress.rawValue, "keyPress")
        XCTAssertEqual(ActionType.macro.rawValue, "macro")
        XCTAssertEqual(ActionType.script.rawValue, "script")
        XCTAssertEqual(ActionType.systemCommand.rawValue, "systemCommand")
        XCTAssertEqual(ActionType.none.rawValue, "none")
    }

    // MARK: - Edge Cases

    func testKeyMapping_keyCodeWithModifiers_countsAsOneAction() {
        // keyCode + modifiers together form a single "key press" action
        let mapping = KeyMapping(keyCode: testKeyCode, modifiers: .command)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertFalse(mapping.hasConflictingActions)
    }

    func testChordMapping_modifiersOnly_countsAsOneAction() {
        // Modifiers without keyCode is still a key-press action (modifier tap)
        let mapping = ChordMapping(buttons: [.a, .b], modifiers: .shift)
        XCTAssertEqual(mapping.activeActionCount, 1)
        XCTAssertEqual(mapping.effectiveActionType, .keyPress)
        XCTAssertFalse(mapping.hasConflictingActions)
    }

    func testClearingConflicts_onAlreadyCleanMapping_isNoOp() {
        let mapping = KeyMapping(keyCode: testKeyCode, modifiers: .command)
        let cleaned = mapping.clearingConflicts(keeping: .keyPress)
        XCTAssertEqual(cleaned.keyCode, mapping.keyCode)
        XCTAssertEqual(cleaned.modifiers, mapping.modifiers)
        XCTAssertNil(cleaned.macroId)
        XCTAssertNil(cleaned.scriptId)
        XCTAssertNil(cleaned.systemCommand)
    }
}
