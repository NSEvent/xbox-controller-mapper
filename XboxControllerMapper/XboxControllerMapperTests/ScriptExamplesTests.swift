import XCTest
@testable import ControllerKeys

/// Verifies that every script example in ScriptExamplesData parses and runs
/// without errors in test mode. This prevents regressions where API renames
/// or removals silently break the examples shown to users.
final class ScriptExamplesTests: XCTestCase {

    private var engine: ScriptEngine!
    private var inputQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        inputQueue = DispatchQueue(label: "test.scriptExamples")
        engine = ScriptEngine(inputSimulator: StubScriptInputSimulator(), inputQueue: inputQueue)
    }

    override func tearDown() {
        engine = nil
        inputQueue = nil
        super.tearDown()
    }

    private func makeTrigger(button: ControllerButton = .a) -> ScriptTrigger {
        ScriptTrigger(button: button)
    }

    // MARK: - All Examples Parse and Execute

    func testAllExamplesExecuteWithoutError() {
        for example in ScriptExamplesData.all {
            let script = Script(name: example.name, source: example.source)
            let (result, _) = engine.executeTest(script: script, trigger: makeTrigger())
            if case .error(let msg) = result {
                XCTFail("Example '\(example.name)' failed with error: \(msg)")
            }
        }
    }

    // MARK: - Individual Example Tests

    func testAppAwareUndo_ProducesCorrectLogs() {
        let example = ScriptExamplesData.all.first { $0.name == "App-Aware Undo" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("App-Aware Undo failed: \(msg)")
        }
        // Should call press() — logged as [press] in test mode
        let pressLogs = logs.filter { $0.contains("[press]") }
        XCTAssertFalse(pressLogs.isEmpty, "App-Aware Undo should call press()")
    }

    func testToggleMuteZoomMeet_ProducesNotify() {
        let example = ScriptExamplesData.all.first { $0.name == "Toggle Mute (Zoom/Meet)" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Toggle Mute failed: \(msg)")
        }
        // Falls through to "Not in a meeting app" since no app is frontmost in test
        let notifyLogs = logs.filter { $0.contains("[notify]") }
        XCTAssertFalse(notifyLogs.isEmpty, "Toggle Mute should call notify()")
    }

    func testScreenshotToClipboard_UsesShellAsync() {
        let example = ScriptExamplesData.all.first { $0.name == "Screenshot to Clipboard" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Screenshot to Clipboard failed: \(msg)")
        }
        let shellLogs = logs.filter { $0.contains("[shellAsync]") }
        XCTAssertFalse(shellLogs.isEmpty, "Screenshot should call shellAsync()")
    }

    func testWindowSnap_UsesTriggerButton() {
        let example = ScriptExamplesData.all.first { $0.name == "Window Snap Left/Right" }!
        let script = Script(name: example.name, source: example.source)

        // Test with dpadLeft
        let (resultL, logsL) = engine.executeTest(script: script, trigger: makeTrigger(button: .dpadLeft))
        if case .error(let msg) = resultL {
            XCTFail("Window Snap (left) failed: \(msg)")
        }
        let pressLogsL = logsL.filter { $0.contains("[press]") }
        XCTAssertFalse(pressLogsL.isEmpty, "dpadLeft should trigger press()")

        // Test with dpadRight
        let (resultR, logsR) = engine.executeTest(script: script, trigger: makeTrigger(button: .dpadRight))
        if case .error(let msg) = resultR {
            XCTFail("Window Snap (right) failed: \(msg)")
        }
        let pressLogsR = logsR.filter { $0.contains("[press]") }
        XCTAssertFalse(pressLogsR.isEmpty, "dpadRight should trigger press()")
    }

    func testSearchSelectedText_UsesClipboardAndOpenURL() {
        let example = ScriptExamplesData.all.first { $0.name == "Search Selected Text" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Search Selected Text failed: \(msg)")
        }
        // Should call press() for Cmd+C
        let pressLogs = logs.filter { $0.contains("[press]") }
        XCTAssertFalse(pressLogs.isEmpty, "Should press Cmd+C to copy")
    }

    func testCycleThroughURLs_UsesStateAndOpenURL() {
        let example = ScriptExamplesData.all.first { $0.name == "Cycle Through URLs" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Cycle Through URLs failed: \(msg)")
        }
        let urlLogs = logs.filter { $0.contains("[openURL]") }
        XCTAssertFalse(urlLogs.isEmpty, "Should call openURL()")
    }

    func testTypeEmailSignature_UsesPasteAndExpand() {
        let example = ScriptExamplesData.all.first { $0.name == "Type Email Signature" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Type Email Signature failed: \(msg)")
        }
        let pasteLogs = logs.filter { $0.contains("[paste]") }
        XCTAssertFalse(pasteLogs.isEmpty, "Should call paste()")
    }

    func testQuickNoteWithTimestamp_UsesOpenAppAndPaste() {
        let example = ScriptExamplesData.all.first { $0.name == "Quick Note with Timestamp" }!
        let script = Script(name: example.name, source: example.source)
        let (result, logs) = engine.executeTest(script: script, trigger: makeTrigger())
        if case .error(let msg) = result {
            XCTFail("Quick Note with Timestamp failed: \(msg)")
        }
        let openAppLogs = logs.filter { $0.contains("[openApp]") }
        XCTAssertFalse(openAppLogs.isEmpty, "Should call openApp()")
        let pasteLogs = logs.filter { $0.contains("[paste]") }
        XCTAssertFalse(pasteLogs.isEmpty, "Should call paste()")
    }

    // MARK: - Featured Examples Subset

    func testFeaturedExamplesAreSubsetOfAll() {
        let featured = ScriptExamplesData.featured
        XCTAssertFalse(featured.isEmpty, "Featured examples should not be empty")
        XCTAssertLessThanOrEqual(featured.count, ScriptExamplesData.all.count)
        for f in featured {
            XCTAssertTrue(
                ScriptExamplesData.all.contains { $0.name == f.name },
                "Featured example '\(f.name)' must exist in all examples"
            )
        }
    }
}

// MARK: - Stub Input Simulator

private class StubScriptInputSimulator: InputSimulatorProtocol {
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {}
    func keyUp(_ keyCode: CGKeyCode) {}
    func holdModifier(_ modifier: CGEventFlags) {}
    func releaseModifier(_ modifier: CGEventFlags) {}
    func releaseAllModifiers() {}
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool { false }
    func getHeldModifiers() -> CGEventFlags { [] }
    func moveMouse(dx: CGFloat, dy: CGFloat) {}
    func moveMouseNative(dx: Int, dy: Int) {}
    func warpMouseTo(point: CGPoint) {}
    var isLeftMouseButtonHeld: Bool { false }
    func scroll(dx: CGFloat, dy: CGFloat, phase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase?, isContinuous: Bool, flags: CGEventFlags) {}
    func executeMapping(_ mapping: KeyMapping) {}
    func startHoldMapping(_ mapping: KeyMapping) {}
    func stopHoldMapping(_ mapping: KeyMapping) {}
    func executeMacro(_ macro: Macro) {}
}
