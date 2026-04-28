import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Tests for CommandWheelAction model: Codable round-trip, defaults, icon resolution,
/// ExecutableAction conformance, Profile integration, and ButtonPressOrchestrationPolicy.
final class CommandWheelActionTests: XCTestCase {

    // MARK: - Fixtures

    private let testKeyCode: CGKeyCode = 0x00 // 'a'
    private let testMacroId = UUID()
    private let testScriptId = UUID()
    private let testSystemCommand = SystemCommand.shellCommand(command: "echo test", inTerminal: false)

    // MARK: - Codable: Round-Trip

    func testCodableRoundTrip_AllFieldsPopulated() throws {
        let action = CommandWheelAction(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Test Action",
            iconName: "star.fill",
            iconData: Data([0xFF, 0xD8]),
            keyCode: testKeyCode,
            modifiers: ModifierFlags(command: true, option: false, shift: true, control: false),
            hint: "My hint",
            hapticStyle: .lightClick
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.id, action.id)
        XCTAssertEqual(decoded.displayName, "Test Action")
        XCTAssertEqual(decoded.iconName, "star.fill")
        XCTAssertEqual(decoded.iconData, Data([0xFF, 0xD8]))
        XCTAssertEqual(decoded.keyCode, testKeyCode)
        XCTAssertTrue(decoded.modifiers.command)
        XCTAssertTrue(decoded.modifiers.shift)
        XCTAssertFalse(decoded.modifiers.option)
        XCTAssertFalse(decoded.modifiers.control)
        XCTAssertEqual(decoded.hint, "My hint")
        XCTAssertEqual(decoded.hapticStyle, .lightClick)
    }

    func testCodableRoundTrip_WithMacroId() throws {
        let action = CommandWheelAction(displayName: "Macro Action", macroId: testMacroId)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.macroId, testMacroId)
        XCTAssertNil(decoded.keyCode)
        XCTAssertNil(decoded.scriptId)
        XCTAssertNil(decoded.systemCommand)
    }

    func testCodableRoundTrip_WithScriptId() throws {
        let action = CommandWheelAction(displayName: "Script Action", scriptId: testScriptId)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.scriptId, testScriptId)
        XCTAssertNil(decoded.macroId)
    }

    func testCodableRoundTrip_WithSystemCommand() throws {
        let action = CommandWheelAction(displayName: "Shell", systemCommand: testSystemCommand)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.systemCommand, testSystemCommand)
        XCTAssertNil(decoded.macroId)
        XCTAssertNil(decoded.keyCode)
    }

    func testCodableRoundTrip_WithLaunchApp() throws {
        let cmd = SystemCommand.launchApp(bundleIdentifier: "com.apple.finder", newWindow: true)
        let action = CommandWheelAction(displayName: "Finder", systemCommand: cmd)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.systemCommand, cmd)
    }

    func testCodableRoundTrip_WithOpenLink() throws {
        let cmd = SystemCommand.openLink(url: "https://example.com")
        let action = CommandWheelAction(displayName: "Example", systemCommand: cmd)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.systemCommand, cmd)
    }

    // MARK: - Codable: Defaults for Missing Keys

    func testDecoding_EmptyJSON_UsesDefaults() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        XCTAssertEqual(decoded.displayName, "")
        XCTAssertNil(decoded.iconName)
        XCTAssertNil(decoded.iconData)
        XCTAssertNil(decoded.keyCode)
        XCTAssertEqual(decoded.modifiers, ModifierFlags())
        XCTAssertNil(decoded.macroId)
        XCTAssertNil(decoded.scriptId)
        XCTAssertNil(decoded.systemCommand)
        XCTAssertNil(decoded.hint)
        XCTAssertNil(decoded.hapticStyle)
    }

    func testDecoding_PartialJSON_FillsDefaults() throws {
        let json = #"{"displayName":"Partial","keyCode":36}"#
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.displayName, "Partial")
        XCTAssertEqual(decoded.keyCode, 36)
        XCTAssertEqual(decoded.modifiers, ModifierFlags())
        XCTAssertNil(decoded.macroId)
    }

    func testDecoding_IdGenerated_WhenMissing() throws {
        let data = Data(#"{"displayName":"No ID"}"#.utf8)
        let decoded = try JSONDecoder().decode(CommandWheelAction.self, from: data)

        // ID should be generated (non-nil)
        XCTAssertFalse(decoded.id.uuidString.isEmpty)
    }

    // MARK: - ExecutableAction Conformance

    func testEffectiveActionType_KeyPress() {
        let action = CommandWheelAction(keyCode: testKeyCode)
        XCTAssertEqual(action.effectiveActionType, .keyPress)
    }

    func testEffectiveActionType_Macro() {
        let action = CommandWheelAction(macroId: testMacroId)
        XCTAssertEqual(action.effectiveActionType, .macro)
    }

    func testEffectiveActionType_Script() {
        let action = CommandWheelAction(scriptId: testScriptId)
        XCTAssertEqual(action.effectiveActionType, .script)
    }

    func testEffectiveActionType_SystemCommand() {
        let action = CommandWheelAction(systemCommand: testSystemCommand)
        XCTAssertEqual(action.effectiveActionType, .systemCommand)
    }

    func testEffectiveActionType_None() {
        let action = CommandWheelAction(displayName: "Empty")
        XCTAssertEqual(action.effectiveActionType, .none)
    }

    func testEffectiveActionType_PriorityChain() {
        // systemCommand > macroId > scriptId > keyCode
        let action = CommandWheelAction(
            keyCode: testKeyCode,
            macroId: testMacroId,
            systemCommand: testSystemCommand
        )
        XCTAssertEqual(action.effectiveActionType, .systemCommand)
    }

    // MARK: - hasAction

    func testHasAction_TrueForKeyCode() {
        XCTAssertTrue(CommandWheelAction(keyCode: testKeyCode).hasAction)
    }

    func testHasAction_TrueForModifiersOnly() {
        XCTAssertTrue(CommandWheelAction(modifiers: .command).hasAction)
    }

    func testHasAction_TrueForMacro() {
        XCTAssertTrue(CommandWheelAction(macroId: testMacroId).hasAction)
    }

    func testHasAction_TrueForScript() {
        XCTAssertTrue(CommandWheelAction(scriptId: testScriptId).hasAction)
    }

    func testHasAction_TrueForSystemCommand() {
        XCTAssertTrue(CommandWheelAction(systemCommand: testSystemCommand).hasAction)
    }

    func testHasAction_FalseWhenEmpty() {
        XCTAssertFalse(CommandWheelAction(displayName: "Empty").hasAction)
    }

    // MARK: - actionDisplayString

    func testActionDisplayString_SystemCommand() {
        let action = CommandWheelAction(displayName: "Test", systemCommand: testSystemCommand)
        XCTAssertEqual(action.actionDisplayString, testSystemCommand.displayName)
    }

    func testActionDisplayString_Macro() {
        let action = CommandWheelAction(displayName: "Test", macroId: testMacroId)
        XCTAssertEqual(action.actionDisplayString, "Macro")
    }

    func testActionDisplayString_Script() {
        let action = CommandWheelAction(displayName: "Test", scriptId: testScriptId)
        XCTAssertEqual(action.actionDisplayString, "Script")
    }

    func testActionDisplayString_KeyPress() {
        let action = CommandWheelAction(
            displayName: "Test",
            keyCode: testKeyCode,
            modifiers: .command
        )
        // Should fall through to displayString (inherited from KeyBindingRepresentable)
        XCTAssertTrue(action.actionDisplayString.contains("⌘"))
    }

    // MARK: - defaultIconName

    func testDefaultIconName_KeyPress() {
        XCTAssertEqual(CommandWheelAction(keyCode: testKeyCode).defaultIconName, "keyboard")
    }

    func testDefaultIconName_Macro() {
        XCTAssertEqual(CommandWheelAction(macroId: testMacroId).defaultIconName, "repeat")
    }

    func testDefaultIconName_Script() {
        XCTAssertEqual(CommandWheelAction(scriptId: testScriptId).defaultIconName, "chevron.left.forwardslash.chevron.right")
    }

    func testDefaultIconName_ShellCommand() {
        let action = CommandWheelAction(systemCommand: .shellCommand(command: "ls", inTerminal: false))
        XCTAssertEqual(action.defaultIconName, "terminal")
    }

    func testDefaultIconName_LaunchApp() {
        let action = CommandWheelAction(systemCommand: .launchApp(bundleIdentifier: "com.test", newWindow: false))
        XCTAssertEqual(action.defaultIconName, "app")
    }

    func testDefaultIconName_OpenLink() {
        let action = CommandWheelAction(systemCommand: .openLink(url: "https://example.com"))
        XCTAssertEqual(action.defaultIconName, "globe")
    }

    func testDefaultIconName_Webhook() {
        let action = CommandWheelAction(systemCommand: .httpRequest(url: "https://hook.com", method: .POST, headers: nil, body: nil))
        XCTAssertEqual(action.defaultIconName, "network")
    }

    func testDefaultIconName_OBS() {
        let action = CommandWheelAction(systemCommand: .obsWebSocket(url: "ws://localhost", password: nil, requestType: "Test", requestData: nil))
        XCTAssertEqual(action.defaultIconName, "video")
    }

    func testDefaultIconName_None() {
        XCTAssertEqual(CommandWheelAction(displayName: "Empty").defaultIconName, "questionmark.circle")
    }

    // MARK: - resolvedIcon

    func testResolvedIcon_PrefersIconName() {
        let action = CommandWheelAction(iconName: "star.fill")
        let icon = action.resolvedIcon()
        XCTAssertNotNil(icon, "Should resolve SF Symbol by name")
    }

    func testResolvedIcon_FallsBackToDefaultSymbol() {
        let action = CommandWheelAction(keyCode: testKeyCode)
        let icon = action.resolvedIcon()
        XCTAssertNotNil(icon, "Should resolve fallback SF Symbol")
    }

    func testResolvedIcon_AppLaunch_ResolvesAppIcon() {
        // Finder is always present on macOS
        let action = CommandWheelAction(systemCommand: .launchApp(bundleIdentifier: "com.apple.finder", newWindow: false))
        let icon = action.resolvedIcon()
        XCTAssertNotNil(icon, "Should resolve Finder app icon")
    }

    func testResolvedIcon_InvalidAppBundle_FallsBackToSymbol() {
        let action = CommandWheelAction(systemCommand: .launchApp(bundleIdentifier: "com.nonexistent.fake.app", newWindow: false))
        let icon = action.resolvedIcon()
        // Should still return a symbol (the "app" fallback)
        XCTAssertNotNil(icon)
    }

    // MARK: - Equatable

    func testEquatable_SameContent() {
        let id = UUID()
        let a = CommandWheelAction(id: id, displayName: "Test", keyCode: testKeyCode)
        let b = CommandWheelAction(id: id, displayName: "Test", keyCode: testKeyCode)
        XCTAssertEqual(a, b)
    }

    func testEquatable_DifferentName() {
        let id = UUID()
        let a = CommandWheelAction(id: id, displayName: "A", keyCode: testKeyCode)
        let b = CommandWheelAction(id: id, displayName: "B", keyCode: testKeyCode)
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_DifferentKeyCode() {
        let id = UUID()
        let a = CommandWheelAction(id: id, displayName: "Test", keyCode: 0x00)
        let b = CommandWheelAction(id: id, displayName: "Test", keyCode: 0x01)
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - Profile Backward Compatibility

final class CommandWheelProfileCompatTests: XCTestCase {

    func testProfile_DecodesWithoutCommandWheelActions() throws {
        // Simulates a config saved before commandWheelActions existed
        let json = """
        {
            "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            "name": "Old Profile",
            "isDefault": true,
            "createdAt": 0,
            "modifiedAt": 0,
            "buttonMappings": {},
            "chordMappings": [],
            "sequenceMappings": [],
            "joystickSettings": {},
            "dualSenseLEDSettings": {},
            "linkedApps": [],
            "macros": [],
            "scripts": [],
            "onScreenKeyboardSettings": {},
            "gestureMappings": [],
            "layers": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let profile = try decoder.decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.commandWheelActions, [])
        XCTAssertEqual(profile.name, "Old Profile")
    }

    func testProfile_EncodesCommandWheelActions() throws {
        let action = CommandWheelAction(displayName: "Test", keyCode: 36)
        var profile = Profile(name: "With Wheel")
        profile.commandWheelActions = [action]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let wheelActions = try XCTUnwrap(json["commandWheelActions"] as? [[String: Any]])
        XCTAssertEqual(wheelActions.count, 1)
        XCTAssertEqual(wheelActions[0]["displayName"] as? String, "Test")
    }

    func testProfile_RoundTrip_PreservesCommandWheelActions() throws {
        let actions = [
            CommandWheelAction(displayName: "Copy", keyCode: 0x08, modifiers: .command),
            CommandWheelAction(displayName: "Terminal", systemCommand: .shellCommand(command: "open -a Terminal", inTerminal: false)),
            CommandWheelAction(displayName: "My Macro", macroId: UUID())
        ]
        var profile = Profile(name: "Full")
        profile.commandWheelActions = actions

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Profile.self, from: data)

        XCTAssertEqual(decoded.commandWheelActions.count, 3)
        XCTAssertEqual(decoded.commandWheelActions[0].displayName, "Copy")
        XCTAssertEqual(decoded.commandWheelActions[0].keyCode, 0x08)
        XCTAssertTrue(decoded.commandWheelActions[0].modifiers.command)
        XCTAssertEqual(decoded.commandWheelActions[1].displayName, "Terminal")
        XCTAssertEqual(decoded.commandWheelActions[1].systemCommand, .shellCommand(command: "open -a Terminal", inTerminal: false))
        XCTAssertEqual(decoded.commandWheelActions[2].displayName, "My Macro")
        XCTAssertEqual(decoded.commandWheelActions[2].macroId, actions[2].macroId)
    }

    func testProfile_Equality_IncludesCommandWheelActions() {
        var a = Profile(name: "Test")
        var b = Profile(name: "Test")
        a.id = b.id

        XCTAssertEqual(a, b)

        a.commandWheelActions = [CommandWheelAction(displayName: "X", keyCode: 36)]
        XCTAssertNotEqual(a, b)

        b.commandWheelActions = a.commandWheelActions
        XCTAssertEqual(a, b)
    }
}

// MARK: - ButtonPressOrchestrationPolicy

final class CommandWheelOrchestrationTests: XCTestCase {

    func testResolve_InterceptsCommandWheel_HoldMode() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .a,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showCommandWheel, isHoldModifier: true),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptCommandWheel(holdMode: true))
    }

    func testResolve_InterceptsCommandWheel_ToggleMode() {
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .x,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showCommandWheel, isHoldModifier: false),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: false,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptCommandWheel(holdMode: false))
    }

    func testResolve_CommandWheel_NotInterceptedByDirectoryNavigator() {
        // Command wheel should not be intercepted when directory navigator is visible
        // (D-pad and confirm buttons are intercepted, but other buttons pass through)
        let outcome = ButtonPressOrchestrationPolicy.resolve(
            button: .leftBumper,
            mapping: KeyMapping(keyCode: KeyCodeMapping.showCommandWheel, isHoldModifier: true),
            keyboardVisible: false,
            navigationModeActive: false,
            directoryNavigatorVisible: true,
            isChordPart: false,
            lastTap: nil
        )

        XCTAssertEqual(outcome, .interceptCommandWheel(holdMode: true))
    }
}

// MARK: - KeyCodeMapping

final class CommandWheelKeyCodeTests: XCTestCase {

    func testKeyCode_Value() {
        XCTAssertEqual(KeyCodeMapping.showCommandWheel, 0xF014)
    }

    func testDisplayName() {
        XCTAssertEqual(KeyCodeMapping.displayName(for: KeyCodeMapping.showCommandWheel), "Command Wheel")
    }

    func testIsSpecialAction() {
        XCTAssertTrue(KeyCodeMapping.isSpecialAction(KeyCodeMapping.showCommandWheel))
    }

    func testIsNotMouseButton() {
        XCTAssertFalse(KeyCodeMapping.isMouseButton(KeyCodeMapping.showCommandWheel))
    }

    func testIsNotMediaKey() {
        XCTAssertFalse(KeyCodeMapping.isMediaKey(KeyCodeMapping.showCommandWheel))
    }
}

// MARK: - CommandWheelItem.Kind

final class CommandWheelItemKindTests: XCTestCase {

    func testIsAction_TrueForActionKind() {
        let kind = CommandWheelItem.Kind.action(CommandWheelAction(displayName: "Test"))
        XCTAssertTrue(kind.isAction)
    }

    func testIsAction_FalseForAppKind() {
        let kind = CommandWheelItem.Kind.app(bundleIdentifier: "com.test")
        XCTAssertFalse(kind.isAction)
    }

    func testIsAction_FalseForWebsiteKind() {
        let kind = CommandWheelItem.Kind.website(url: "https://test.com", faviconData: nil)
        XCTAssertFalse(kind.isAction)
    }
}
