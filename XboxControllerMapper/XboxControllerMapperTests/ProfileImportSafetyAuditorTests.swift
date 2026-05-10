import XCTest
@testable import ControllerKeys

final class ProfileImportSafetyAuditorTests: XCTestCase {

    // MARK: - No-warning paths

    func testEmptyProfile_doesNotRequireConfirmation() {
        let report = ProfileImportSafetyAuditor.audit(Profile(name: "empty"))
        XCTAssertFalse(report.requiresUserConfirmation)
        XCTAssertTrue(report.shellCommands.isEmpty)
        XCTAssertTrue(report.scripts.isEmpty)
    }

    func testProfileWithOnlyKeyPresses_doesNotRequireConfirmation() {
        var profile = Profile(name: "p")
        profile.buttonMappings[.a] = KeyMapping(keyCode: 0)
        profile.chordMappings = [ChordMapping(buttons: [.a, .b], keyCode: 0)]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertFalse(report.requiresUserConfirmation)
    }

    func testProfileWithLaunchAppOrOpenLink_doesNotRequireConfirmation() {
        // Other SystemCommand cases are out of scope for the warning sheet —
        // they're risks but get separate treatment.
        var profile = Profile(name: "p")
        profile.buttonMappings[.a] = KeyMapping(systemCommand: .launchApp(bundleIdentifier: "com.apple.calculator"))
        profile.buttonMappings[.b] = KeyMapping(systemCommand: .openLink(url: "https://example.com"))
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertFalse(report.requiresUserConfirmation)
    }

    // MARK: - Shell command discovery

    func testShellCommandOnButton_isReported() {
        var profile = Profile(name: "p")
        profile.buttonMappings[.a] = KeyMapping(systemCommand: .shellCommand(command: "echo hi", inTerminal: false))
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertEqual(report.shellCommands.first?.command, "echo hi")
        XCTAssertFalse(report.shellCommands.first?.inTerminal == true)
        XCTAssertTrue(report.shellCommands.first?.context.contains("Button") == true)
    }

    func testShellCommandOnLongHold_isReported() {
        let longHold = LongHoldMapping(systemCommand: .shellCommand(command: "rm -rf ~/Documents", inTerminal: true))
        let mapping = KeyMapping(longHoldMapping: longHold)
        var profile = Profile(name: "p")
        profile.buttonMappings[.x] = mapping
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("long hold") == true,
                      "Context should distinguish long-hold from primary mapping")
        XCTAssertTrue(report.shellCommands.first?.inTerminal == true)
    }

    func testShellCommandOnDoubleTap_isReported() {
        let doubleTap = DoubleTapMapping(systemCommand: .shellCommand(command: "say hi", inTerminal: false))
        var profile = Profile(name: "p")
        profile.buttonMappings[.y] = KeyMapping(doubleTapMapping: doubleTap)
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("double tap") == true)
    }

    func testShellCommandOnChord_isReported() {
        var profile = Profile(name: "p")
        profile.chordMappings = [
            ChordMapping(buttons: [.a, .b], systemCommand: .shellCommand(command: "ls", inTerminal: false))
        ]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.starts(with: "Chord") == true)
    }

    func testShellCommandOnSequence_isReported() {
        var profile = Profile(name: "p")
        profile.sequenceMappings = [
            SequenceMapping(steps: [.a, .b, .x], systemCommand: .shellCommand(command: "ls", inTerminal: false))
        ]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.starts(with: "Sequence") == true)
    }

    func testShellCommandOnGesture_isReported() {
        var profile = Profile(name: "p")
        profile.gestureMappings = [
            GestureMapping(gestureType: .tiltBack, systemCommand: .shellCommand(command: "ls", inTerminal: false))
        ]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.starts(with: "Gesture") == true)
    }

    func testShellCommandInLayer_isReported() {
        var profile = Profile(name: "p")
        var layer = Layer(name: "Layer1", activatorButton: .leftBumper)
        layer.buttonMappings[.a] = KeyMapping(systemCommand: .shellCommand(command: "uptime", inTerminal: false))
        profile.layers = [layer]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("Layer 'Layer1'") == true)
    }

    func testShellStepInMacro_isReported() {
        var profile = Profile(name: "p")
        let macro = Macro(name: "MyMacro", steps: [
            .delay(0.1),
            .shellCommand(command: "open .", inTerminal: false),
            .delay(0.1),
        ])
        profile.macros = [macro]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("Macro 'MyMacro' step 2") == true,
                      "Step number should be 1-indexed and reflect actual position in steps array")
    }

    func testMultipleShellCommands_areAllReported() {
        var profile = Profile(name: "p")
        profile.buttonMappings[.a] = KeyMapping(systemCommand: .shellCommand(command: "cmd1", inTerminal: false))
        profile.buttonMappings[.b] = KeyMapping(systemCommand: .shellCommand(command: "cmd2", inTerminal: false))
        profile.chordMappings = [ChordMapping(buttons: [.x, .y], systemCommand: .shellCommand(command: "cmd3", inTerminal: false))]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 3)
    }

    // MARK: - Scripts

    func testProfileWithScript_isReported() {
        var profile = Profile(name: "p")
        profile.scripts = [Script(name: "MyScript", source: "console.log('hi');\nshell('whoami');")]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.scripts.count, 1)
        XCTAssertEqual(report.scripts.first?.name, "MyScript")
        XCTAssertEqual(report.scripts.first?.lineCount, 2)
    }

    func testEmptyScriptName_getsPlaceholder() {
        var profile = Profile(name: "p")
        profile.scripts = [Script(name: "", source: "x")]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.scripts.first?.name, "(unnamed script)")
    }

    func testProfileWithScript_requiresConfirmation() {
        var profile = Profile(name: "p")
        profile.scripts = [Script(name: "ok", source: "/* harmless */")]
        XCTAssertTrue(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation,
                      "Any script — regardless of content — must trigger the import warning")
    }

    // MARK: - On-screen-keyboard quick texts

    func testTerminalQuickText_isReportedAsShellCommand() {
        var profile = Profile(name: "p")
        profile.onScreenKeyboardSettings.quickTexts = [
            QuickText(text: "cat /etc/hosts", isTerminalCommand: true)
        ]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "OSK terminal commands run shell payloads — must surface in the warning")
        XCTAssertEqual(report.shellCommands.first?.command, "cat /etc/hosts")
        XCTAssertTrue(report.shellCommands.first?.inTerminal == true,
                      "OSK terminal commands always execute in Terminal — flag accordingly")
        XCTAssertTrue(report.shellCommands.first?.context.lowercased().contains("on-screen keyboard") == true)
    }

    func testNonTerminalQuickText_isNotReported() {
        var profile = Profile(name: "p")
        profile.onScreenKeyboardSettings.quickTexts = [
            QuickText(text: "Hello world", isTerminalCommand: false)
        ]
        XCTAssertFalse(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation,
                       "Plain text snippets are not code execution — must not trigger the warning")
    }

    func testMixOfTerminalAndPlainQuickTexts_onlyTerminalReported() {
        var profile = Profile(name: "p")
        profile.onScreenKeyboardSettings.quickTexts = [
            QuickText(text: "Hello", isTerminalCommand: false),
            QuickText(text: "whoami", isTerminalCommand: true),
            QuickText(text: "Other plain text", isTerminalCommand: false),
            QuickText(text: "uptime", isTerminalCommand: true),
        ]
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 2)
        XCTAssertEqual(Set(report.shellCommands.map(\.command)), ["whoami", "uptime"])
    }

    // MARK: - Webhook responseHandling shell follow-ups

    func testWebhookOnSuccessCommand_isReportedAsShellCommand() {
        var profile = Profile(name: "p")
        let webhook = SystemCommand.httpRequest(
            url: "https://example.com/track",
            method: .POST,
            headers: nil,
            body: nil,
            responseHandling: HTTPResponseHandling(onSuccessCommand: "rm -rf /tmp/cache")
        )
        profile.buttonMappings[.a] = KeyMapping(systemCommand: webhook)
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "Webhook onSuccess shell follow-up must surface — SystemCommandExecutor runs it silently after the request resolves")
        XCTAssertEqual(report.shellCommands.first?.command, "rm -rf /tmp/cache")
        XCTAssertTrue(report.shellCommands.first?.context.contains("on-success") == true)
    }

    func testWebhookOnErrorCommand_isReportedAsShellCommand() {
        var profile = Profile(name: "p")
        let webhook = SystemCommand.httpRequest(
            url: "https://example.com",
            method: .GET,
            headers: nil,
            body: nil,
            responseHandling: HTTPResponseHandling(onErrorCommand: "say failed")
        )
        profile.buttonMappings[.b] = KeyMapping(systemCommand: webhook)
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertEqual(report.shellCommands.first?.command, "say failed")
        XCTAssertTrue(report.shellCommands.first?.context.contains("on-error") == true)
    }

    func testWebhookWithBothOnSuccessAndOnError_reportsBoth() {
        var profile = Profile(name: "p")
        let webhook = SystemCommand.httpRequest(
            url: "https://example.com",
            method: .POST,
            headers: nil,
            body: "data",
            responseHandling: HTTPResponseHandling(
                onSuccessCommand: "echo ok",
                onErrorCommand: "echo bad"
            )
        )
        profile.buttonMappings[.x] = KeyMapping(systemCommand: webhook)
        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 2)
        XCTAssertEqual(Set(report.shellCommands.map(\.command)), ["echo ok", "echo bad"])
    }

    func testWebhookWithoutShellFollowUps_doesNotRequireConfirmation() {
        // A plain webhook (no onSuccess/onError) is not a shell-command
        // surface — it's just a network call. Auditor should pass it through.
        var profile = Profile(name: "p")
        profile.buttonMappings[.y] = KeyMapping(systemCommand: .httpRequest(
            url: "https://example.com",
            method: .POST,
            headers: nil,
            body: nil,
            responseHandling: nil
        ))
        XCTAssertFalse(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation)
    }

    func testEmptyOnSuccessCommand_isNotReported() {
        // Defensive: an empty string in responseHandling shouldn't trigger a
        // false positive on the warning sheet.
        var profile = Profile(name: "p")
        profile.buttonMappings[.a] = KeyMapping(systemCommand: .httpRequest(
            url: "https://example.com",
            method: .GET,
            headers: nil,
            body: nil,
            responseHandling: HTTPResponseHandling(onSuccessCommand: "")
        ))
        XCTAssertFalse(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation)
    }

    // MARK: - Layer long-hold and double-tap variants

    func testShellCommandOnLayerLongHold_isReported() {
        var profile = Profile(name: "p")
        var layer = Layer(name: "Gaming", activatorButton: .leftBumper)
        let longHold = LongHoldMapping(systemCommand: .shellCommand(command: "rm -rf ~/games", inTerminal: false))
        layer.buttonMappings[.a] = KeyMapping(longHoldMapping: longHold)
        profile.layers = [layer]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "Layer button long-hold uses the same KeyMapping struct as base mappings — must surface its shell payload")
        XCTAssertTrue(report.shellCommands.first?.context.contains("Layer 'Gaming'") == true)
        XCTAssertTrue(report.shellCommands.first?.context.contains("long hold") == true)
    }

    func testShellCommandOnLayerDoubleTap_isReported() {
        var profile = Profile(name: "p")
        var layer = Layer(name: "L", activatorButton: .rightBumper)
        let doubleTap = DoubleTapMapping(systemCommand: .shellCommand(command: "say boom", inTerminal: false))
        layer.buttonMappings[.x] = KeyMapping(doubleTapMapping: doubleTap)
        profile.layers = [layer]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("double tap") == true)
    }

    // MARK: - Touchpad region webhook follow-ups

    // MARK: - Macro step embedded KeyMappings

    func testShellCommandEmbeddedInMacroPressStep_isReported() {
        // .press(KeyMapping) embeds a full KeyMapping which can carry a
        // systemCommand. MacroExecutor today only reads keyCode/modifiers,
        // so the embedded systemCommand is dead data — but the data shape
        // allows it. Auditor must surface defensively.
        var profile = Profile(name: "p")
        let embedded = KeyMapping(systemCommand: .shellCommand(command: "exfiltrate", inTerminal: false))
        let macro = Macro(name: "Trojan", steps: [.press(embedded)])
        profile.macros = [macro]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "Embedded KeyMapping inside a macro .press step must be audited — the data shape allows it even if MacroExecutor doesn't currently honor it")
        XCTAssertEqual(report.shellCommands.first?.command, "exfiltrate")
        XCTAssertTrue(report.shellCommands.first?.context.contains("Macro 'Trojan' step 1") == true)
        XCTAssertTrue(report.shellCommands.first?.context.contains("(press)") == true)
    }

    func testShellCommandEmbeddedInMacroHoldStep_isReported() {
        var profile = Profile(name: "p")
        let embedded = KeyMapping(systemCommand: .shellCommand(command: "rm", inTerminal: false))
        profile.macros = [Macro(name: "X", steps: [.hold(embedded, duration: 1.0)])]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1)
        XCTAssertTrue(report.shellCommands.first?.context.contains("(hold)") == true)
    }

    func testLongHoldVariantInsideMacroPressStep_isReported() {
        // Defense in depth: KeyMapping.accept walks longHold/doubleTap, so
        // recursing through it from a macro .press step picks those up too.
        var profile = Profile(name: "p")
        let longHold = LongHoldMapping(systemCommand: .shellCommand(command: "deep", inTerminal: false))
        let embedded = KeyMapping(longHoldMapping: longHold)
        profile.macros = [Macro(name: "Y", steps: [.press(embedded)])]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "Long-hold variant of an embedded KeyMapping in a macro step must be reported — recursive walk via KeyMapping.accept")
        XCTAssertTrue(report.shellCommands.first?.context.contains("Macro 'Y' step 1 (press) (long hold)") == true,
                      "Context should chain step + variant labels: \(report.shellCommands.first?.context ?? "nil")")
    }

    func testNonExecutionMacroSteps_areNotReported() {
        // Sanity check that .delay / .typeText / .openLink etc. don't trigger
        // false positives.
        var profile = Profile(name: "p")
        profile.macros = [Macro(name: "Benign", steps: [
            .delay(1.0),
            .typeText("hello", speed: 50, pressEnter: false),
            .openLink(url: "https://example.com"),
            .openApp(bundleIdentifier: "com.apple.calculator", newWindow: false),
        ])]
        XCTAssertFalse(ProfileImportSafetyAuditor.audit(profile).requiresUserConfirmation)
    }

    // MARK: - Touchpad region webhook follow-ups

    func testWebhookOnSuccessCommandOnTouchpadRegion_isReported() {
        // Pre-fix: touchpad region used a manual `if case` that skipped
        // collectShell, missing webhook follow-ups entirely. Now routes
        // through collectShell.
        var profile = Profile(name: "p")
        let webhook = SystemCommand.httpRequest(
            url: "https://example.com",
            method: .POST,
            headers: nil,
            body: nil,
            responseHandling: HTTPResponseHandling(onSuccessCommand: "exfiltrate")
        )
        profile.touchpadRegionMappings = [
            TouchpadRegionMapping(
                region: .topLeft,
                triggerMode: .click,
                systemCommand: webhook
            )
        ]

        let report = ProfileImportSafetyAuditor.audit(profile)
        XCTAssertEqual(report.shellCommands.count, 1,
                       "Touchpad regions must use the same audit path as other bindings — webhook follow-ups should not bypass the warning")
        XCTAssertEqual(report.shellCommands.first?.command, "exfiltrate")
        XCTAssertTrue(report.shellCommands.first?.context.contains("Touchpad region") == true)
        XCTAssertTrue(report.shellCommands.first?.context.contains("on-success") == true)
    }
}
