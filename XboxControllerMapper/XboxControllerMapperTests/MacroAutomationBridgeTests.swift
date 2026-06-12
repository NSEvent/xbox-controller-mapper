import XCTest
import CoreGraphics
import Carbon.HIToolbox
import TriggerKitCore
@testable import ControllerKeys

/// Covers the MacroStep -> AutomationStep conversion table that backs
/// TriggerKit-based macro execution.
final class MacroAutomationBridgeTests: XCTestCase {

    // MARK: - Key presses

    func testRegularPressConvertsToKeyPressWithSides() {
        let mapping = KeyMapping(
            keyCode: 0,
            modifiers: ModifierFlags(command: true, shift: true, commandSide: .right)
        )

        let steps = MacroAutomationBridge.automationSteps(for: .press(mapping))

        XCTAssertEqual(steps.count, 1)
        guard case .keyPress(let stroke) = steps[0] else { return XCTFail("Expected keyPress") }
        XCTAssertEqual(stroke.key.keyCode, 0)
        XCTAssertEqual(stroke.modifiers.command, .right)
        XCTAssertEqual(stroke.modifiers.shift, .any)
        XCTAssertNil(stroke.modifiers.option)
    }

    func testModifierOnlyPressCarriesOneModifierAsKey() {
        let mapping = KeyMapping(modifiers: ModifierFlags(command: true, shift: true))

        let steps = MacroAutomationBridge.automationSteps(for: .press(mapping))

        XCTAssertEqual(steps.count, 1)
        guard case .keyPress(let stroke) = steps[0] else { return XCTFail("Expected keyPress") }
        // Shift is last in ControllerKeys' press order for ⌘⇧, so it rides as
        // the stroke's key with command remaining as a modifier.
        XCTAssertEqual(stroke.key.keyCode, UInt16(kVK_Shift))
        XCTAssertEqual(stroke.modifiers.command, .any)
        XCTAssertNil(stroke.modifiers.shift)
    }

    func testEmptyPressProducesNoSteps() {
        XCTAssertTrue(MacroAutomationBridge.automationSteps(for: .press(KeyMapping())).isEmpty)
    }

    // MARK: - Synthetic markers

    func testMouseMarkerPressConvertsToMouseClick() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, modifiers: .command)

        let steps = MacroAutomationBridge.automationSteps(for: .press(mapping))

        guard case .mouseClick(let click) = steps.first else { return XCTFail("Expected mouseClick") }
        XCTAssertEqual(click.button, .right)
        XCTAssertEqual(click.clickCount, 1)
        XCTAssertEqual(click.modifiers.command, .any)
    }

    func testUnmodifiedScrollMarkerConvertsToMouseScroll() {
        let steps = MacroAutomationBridge.automationSteps(for: .press(KeyMapping(keyCode: KeyCodeMapping.scrollDown)))

        guard case .mouseScroll(let scroll) = steps.first else { return XCTFail("Expected mouseScroll") }
        XCTAssertLessThan(scroll.deltaY, 0)
        XCTAssertEqual(MacroAutomationBridge.scrollMarkerKeyCode(for: scroll), KeyCodeMapping.scrollDown)
    }

    func testModifiedScrollMarkerPassesThroughAsKeyPress() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.scrollUp, modifiers: .control)

        let steps = MacroAutomationBridge.automationSteps(for: .press(mapping))

        // MouseScroll cannot carry modifiers (Ctrl+scroll = zoom), so the
        // marker key code passes through and the adapter routes it back into
        // InputSimulator's scroll handling.
        guard case .keyPress(let stroke) = steps.first else { return XCTFail("Expected keyPress passthrough") }
        XCTAssertEqual(CGKeyCode(stroke.key.keyCode), KeyCodeMapping.scrollUp)
        XCTAssertEqual(stroke.modifiers.control, .any)
    }

    func testMediaKeyPressMapsToTriggerKitCatalogKey() {
        let steps = MacroAutomationBridge.automationSteps(for: .press(KeyMapping(keyCode: KeyCodeMapping.mediaPlayPause)))

        guard case .keyPress(let stroke) = steps.first else { return XCTFail("Expected keyPress") }
        XCTAssertEqual(stroke.key, TriggerKey.mediaPlayPause, "ControllerKeys and TriggerKit share media key codes")
    }

    func testSpecialActionMarkerPassesThroughWithRawCode() {
        let steps = MacroAutomationBridge.automationSteps(for: .press(KeyMapping(keyCode: KeyCodeMapping.showOnScreenKeyboard)))

        guard case .keyPress(let stroke) = steps.first else { return XCTFail("Expected keyPress") }
        XCTAssertEqual(CGKeyCode(stroke.key.keyCode), KeyCodeMapping.showOnScreenKeyboard)
    }

    // MARK: - Holds

    func testHoldConvertsToKeyDownDelayKeyUp() {
        let mapping = KeyMapping(keyCode: 4, modifiers: .command)

        let steps = MacroAutomationBridge.automationSteps(for: .hold(mapping, duration: 1.5))

        XCTAssertEqual(steps.count, 3)
        guard case .keyDown(let down) = steps[0],
              case .delay(let delay) = steps[1],
              case .keyUp(let up) = steps[2] else {
            return XCTFail("Expected keyDown/delay/keyUp")
        }
        XCTAssertEqual(down.key.keyCode, 4)
        XCTAssertEqual(down.modifiers.command, .any)
        XCTAssertEqual(delay.seconds, 1.5)
        XCTAssertEqual(up, down)
    }

    func testMouseMarkerHoldConvertsToMouseDownUp() {
        let steps = MacroAutomationBridge.automationSteps(
            for: .hold(KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick), duration: 0.5)
        )

        XCTAssertEqual(steps.count, 3)
        guard case .mouseDown(let down) = steps[0],
              case .delay = steps[1],
              case .mouseUp(let up) = steps[2] else {
            return XCTFail("Expected mouseDown/delay/mouseUp")
        }
        XCTAssertEqual(down.button, .left)
        XCTAssertEqual(up, down)
    }

    func testNegativeHoldDurationClampsToZero() {
        let steps = MacroAutomationBridge.automationSteps(for: .hold(KeyMapping(keyCode: 0), duration: -3))

        guard case .delay(let delay) = steps[1] else { return XCTFail("Expected delay") }
        XCTAssertEqual(delay.seconds, 0)
    }

    // MARK: - Delay / type text

    func testDelayClampsNegativeValues() {
        guard case .delay(let delay) = MacroAutomationBridge.automationSteps(for: .delay(-2))[0] else {
            return XCTFail("Expected delay")
        }
        XCTAssertEqual(delay.seconds, 0)
    }

    func testTypeTextSpeedZeroMapsToPaste() {
        guard case .typeText(let step) = MacroAutomationBridge.automationSteps(
            for: .typeText("hi", speed: 0, pressEnter: true)
        )[0] else { return XCTFail("Expected typeText") }

        XCTAssertEqual(step.mode, .paste)
        XCTAssertNil(step.charactersPerMinute)
        XCTAssertTrue(step.pressReturn)
    }

    func testTypeTextPositiveSpeedMapsToPacedTyping() {
        guard case .typeText(let step) = MacroAutomationBridge.automationSteps(
            for: .typeText("hi", speed: 240, pressEnter: false)
        )[0] else { return XCTFail("Expected typeText") }

        XCTAssertEqual(step.mode, .type)
        XCTAssertEqual(step.charactersPerMinute, 240)
        XCTAssertFalse(step.pressReturn)
    }

    // MARK: - System steps

    func testOpenAppOpenLinkAndShellConvert() {
        guard case .openApp(let app) = MacroAutomationBridge.automationSteps(
            for: .openApp(bundleIdentifier: "com.apple.TextEdit", newWindow: true)
        )[0] else { return XCTFail("Expected openApp") }
        XCTAssertEqual(app.bundleIdentifier, "com.apple.TextEdit")
        XCTAssertTrue(app.openNewWindow)

        guard case .openURL(let url) = MacroAutomationBridge.automationSteps(
            for: .openLink(url: "https://example.com")
        )[0] else { return XCTFail("Expected openURL") }
        XCTAssertEqual(url.url, "https://example.com")

        guard case .shellCommand(let shell) = MacroAutomationBridge.automationSteps(
            for: .shellCommand(command: "top", inTerminal: true)
        )[0] else { return XCTFail("Expected shellCommand") }
        XCTAssertEqual(shell.command, "top")
        XCTAssertTrue(shell.runsInTerminal)
    }

    func testWebhookConvertsMethodHeadersAndBody() {
        guard case .webhook(let webhook) = MacroAutomationBridge.automationSteps(
            for: .webhook(url: "https://example.com/h", method: .PATCH, headers: ["A": "1"], body: "{}")
        )[0] else { return XCTFail("Expected webhook") }

        XCTAssertEqual(webhook.url, "https://example.com/h")
        XCTAssertEqual(webhook.method, .patch)
        XCTAssertEqual(webhook.headers, ["A": "1"])
        XCTAssertEqual(webhook.body, "{}")
    }

    func testWebhookNilHeadersBecomeEmptyDictionary() {
        guard case .webhook(let webhook) = MacroAutomationBridge.automationSteps(
            for: .webhook(url: "https://example.com", method: .GET, headers: nil, body: nil)
        )[0] else { return XCTFail("Expected webhook") }

        XCTAssertTrue(webhook.headers.isEmpty)
        XCTAssertEqual(webhook.method, .get)
    }

    func testOBSConvertsToCustomStepAndBackToSystemCommand() {
        guard case .custom(let custom) = MacroAutomationBridge.automationSteps(
            for: .obsWebSocket(url: "ws://localhost:4455", password: "pw", requestType: "ToggleRecord", requestData: #"{"a":1}"#)
        )[0] else { return XCTFail("Expected custom step") }

        XCTAssertEqual(custom.namespace, MacroAutomationBridge.obsNamespace)
        XCTAssertEqual(custom.displayName, "OBS: ToggleRecord")

        let command = MacroAutomationBridge.obsCommand(fromPayload: custom.payload)
        XCTAssertEqual(command, .obsWebSocket(
            url: "ws://localhost:4455",
            password: "pw",
            requestType: "ToggleRecord",
            requestData: #"{"a":1}"#
        ))
    }

    func testMalformedOBSPayloadReturnsNil() {
        XCTAssertNil(MacroAutomationBridge.obsCommand(fromPayload: "not json"))
    }

    // MARK: - Whole macro

    func testProgramPreservesIdentityAndFlattensSteps() {
        let macro = Macro(name: "Combo", steps: [
            .press(KeyMapping(keyCode: 0)),
            .hold(KeyMapping(keyCode: 1), duration: 0.2),
            .delay(0.1)
        ])

        let program = MacroAutomationBridge.automationProgram(for: macro)

        XCTAssertEqual(program.id, macro.id)
        XCTAssertEqual(program.name, "Combo")
        XCTAssertEqual(program.steps.count, 5, "press(1) + hold(3) + delay(1)")
    }

    // MARK: - Modifier conversion round trip

    func testModifierFlagsRoundTripThroughModifierSet() {
        let flags = ModifierFlags(
            command: true,
            option: true,
            shift: false,
            control: true,
            commandSide: .right,
            optionSide: nil,
            shiftSide: nil,
            controlSide: .left
        )

        let roundTripped = MacroAutomationBridge.modifierFlags(
            for: MacroAutomationBridge.modifierSet(for: flags)
        )

        XCTAssertEqual(roundTripped, flags)
    }
}
