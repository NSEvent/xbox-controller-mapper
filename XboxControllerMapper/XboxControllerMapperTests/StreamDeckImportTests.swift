import XCTest
import CoreGraphics
@testable import ControllerKeys

final class StreamDeckImportTests: XCTestCase {

    // MARK: - Parser: Hotkey Tests

    func testParseHotkey_ConvertsNativeCodeToKeyCode() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "Save",
                "Settings": ["NativeCode": 1, "KeyCmd": true, "KeyShift": false, "KeyOption": false, "KeyCtrl": false],
                "States": [["Title": "Save"]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .hotkey(let keyCode, let modifiers) = manifest.actions[0].settings {
            XCTAssertEqual(keyCode, 1) // CGKeyCode for "s"
            XCTAssertTrue(modifiers.command)
        } else {
            XCTFail("Expected hotkey action")
        }
    }

    func testParseHotkey_ConvertsBooleanModifierFlags() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "Test",
                "Settings": ["NativeCode": 0, "KeyCmd": true, "KeyShift": true, "KeyOption": false, "KeyCtrl": false],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .hotkey(_, let modifiers) = manifest.actions[0].settings {
            XCTAssertTrue(modifiers.command)
            XCTAssertTrue(modifiers.shift)
            XCTAssertFalse(modifiers.option)
            XCTAssertFalse(modifiers.control)
        } else {
            XCTFail("Expected hotkey action")
        }
    }

    func testParseHotkey_FiltersSentinelEntry() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "Sentinel",
                "Settings": ["NativeCode": 146, "KeyCmd": false, "KeyShift": false, "KeyOption": false, "KeyCtrl": false],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 0, "Sentinel entries should be filtered out")
    }

    func testParseModifiers_AllCombinations() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "All Mods",
                "Settings": ["NativeCode": 0, "KeyCmd": true, "KeyShift": true, "KeyOption": true, "KeyCtrl": true],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .hotkey(_, let modifiers) = manifest.actions[0].settings {
            XCTAssertTrue(modifiers.command)
            XCTAssertTrue(modifiers.shift)
            XCTAssertTrue(modifiers.option)
            XCTAssertTrue(modifiers.control)
        } else {
            XCTFail("Expected hotkey action")
        }
    }

    // MARK: - Parser: Other Action Types

    func testParseWebsite_ExtractsURL() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.website",
                "Name": "Google",
                "Settings": ["path": "https://google.com"],
                "States": [["Title": "Google"]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .website(let url) = manifest.actions[0].settings {
            XCTAssertEqual(url, "https://google.com")
        } else {
            XCTFail("Expected website action")
        }
    }

    func testParseOpenApp_ExtractsPath() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.open",
                "Name": "Slack",
                "Settings": ["path": "/Applications/Slack.app"],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .openApp(let path) = manifest.actions[0].settings {
            XCTAssertEqual(path, "/Applications/Slack.app")
        } else {
            XCTFail("Expected openApp action")
        }
    }

    func testParseMultiAction_RecursesSubActions() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.multiactions.routine",
                "Name": "Multi",
                "Settings": [
                    "Routine": [
                        [
                            "UUID": "com.elgato.streamdeck.system.hotkey",
                            "Name": "Copy",
                            "Settings": ["NativeCode": 8, "KeyCmd": true, "KeyShift": false, "KeyOption": false, "KeyCtrl": false],
                            "States": [["Title": ""]]
                        ],
                        [
                            "UUID": "com.elgato.streamdeck.system.website",
                            "Name": "Link",
                            "Settings": ["path": "https://example.com"],
                            "States": [["Title": ""]]
                        ]
                    ]
                ],
                "States": [["Title": "Multi"]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .multiAction(let subs) = manifest.actions[0].settings {
            XCTAssertEqual(subs.count, 2)
            if case .hotkey(let kc, _) = subs[0].settings {
                XCTAssertEqual(kc, 8) // CGKeyCode for "c"
            } else {
                XCTFail("Expected hotkey sub-action")
            }
            if case .website(let url) = subs[1].settings {
                XCTAssertEqual(url, "https://example.com")
            } else {
                XCTFail("Expected website sub-action")
            }
        } else {
            XCTFail("Expected multiAction")
        }
    }

    func testParseUnsupported_MarkedWithPluginUUID() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.someunknownplugin",
                "Name": "Unknown",
                "Settings": [:] as [String: Any],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions.count, 1)
        if case .unsupported(let uuid) = manifest.actions[0].settings {
            XCTAssertEqual(uuid, "com.elgato.streamdeck.system.someunknownplugin")
        } else {
            XCTFail("Expected unsupported action")
        }
    }

    // MARK: - Parser: Title Extraction

    func testParseTitle_PrefersStatesTitle() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "FallbackName",
                "Settings": ["NativeCode": 1, "KeyCmd": true, "KeyShift": false, "KeyOption": false, "KeyCtrl": false],
                "States": [["Title": "Custom Title"]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions[0].title, "Custom Title")
    }

    func testParseTitle_FallsBackToName() throws {
        let json = makeManifest(actions: [
            "0,0": [
                "UUID": "com.elgato.streamdeck.system.hotkey",
                "Name": "FallbackName",
                "Settings": ["NativeCode": 1, "KeyCmd": true, "KeyShift": false, "KeyOption": false, "KeyCtrl": false],
                "States": [["Title": ""]]
            ]
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try StreamDeckProfileParser.parseManifestData(data)

        XCTAssertEqual(manifest.actions[0].title, "FallbackName")
    }

    // MARK: - Mapper: Auto-Assignment

    func testAutoAssign_AssignsInPriorityOrder() {
        let actions = [
            makeStreamDeckAction(position: "0,0", settings: .hotkey(0, ModifierFlags(command: true))),
            makeStreamDeckAction(position: "0,1", settings: .hotkey(1, ModifierFlags())),
            makeStreamDeckAction(position: "0,2", settings: .hotkey(2, ModifierFlags()))
        ]

        let mapped = StreamDeckImportMapper.mapActions(actions)

        XCTAssertEqual(mapped[0].assignedButton, .a)
        XCTAssertEqual(mapped[1].assignedButton, .b)
        XCTAssertEqual(mapped[2].assignedButton, .x)
    }

    func testAutoAssign_ExcessActionsUnassigned() {
        // Create more actions than available buttons
        var actions: [StreamDeckAction] = []
        for i in 0..<20 {
            actions.append(makeStreamDeckAction(
                position: "0,\(i)",
                settings: .hotkey(CGKeyCode(i), ModifierFlags())
            ))
        }

        let mapped = StreamDeckImportMapper.mapActions(actions)
        let assignedCount = mapped.filter { $0.assignedButton != nil }.count
        let buttonCount = StreamDeckImportMapper.assignmentOrder.count

        XCTAssertEqual(assignedCount, buttonCount)
        // Actions beyond button count should be unassigned
        for i in buttonCount..<mapped.count {
            XCTAssertNil(mapped[i].assignedButton)
        }
    }

    func testAutoAssign_UnsupportedActionsNotAssigned() {
        let actions = [
            makeStreamDeckAction(position: "0,0", settings: .unsupported(pluginUUID: "some.plugin")),
            makeStreamDeckAction(position: "0,1", settings: .hotkey(0, ModifierFlags()))
        ]

        let mapped = StreamDeckImportMapper.mapActions(actions)

        XCTAssertNil(mapped[0].assignedButton, "Unsupported actions should not be assigned")
        XCTAssertEqual(mapped[1].assignedButton, .a, "Supported action should get first button")
    }

    // MARK: - Mapper: Conversion

    func testHotkeyMapping_CreatesDirectKeyMapping() {
        let action = makeStreamDeckAction(
            position: "0,0",
            title: "Save",
            settings: .hotkey(1, ModifierFlags(command: true))
        )
        let result = StreamDeckImportMapper.convertAction(action)

        if case .directKey(let mapping) = result {
            XCTAssertEqual(mapping.keyCode, 1)
            XCTAssertTrue(mapping.modifiers.command)
            XCTAssertEqual(mapping.hint, "Save")
        } else {
            XCTFail("Expected directKey result")
        }
    }

    func testOpenAppMapping_CreatesMacroWithOpenAppStep() {
        let action = makeStreamDeckAction(
            position: "0,0",
            title: "Slack",
            settings: .openApp(path: "/Applications/Slack.app")
        )
        let result = StreamDeckImportMapper.convertAction(action)

        if case .macro(let macro) = result {
            XCTAssertEqual(macro.steps.count, 1)
            if case .openApp(let bundleId, let newWindow) = macro.steps[0] {
                // Bundle ID resolution may or may not work depending on whether Slack is installed
                XCTAssertFalse(bundleId.isEmpty)
                XCTAssertFalse(newWindow)
            } else {
                XCTFail("Expected openApp step")
            }
        } else {
            XCTFail("Expected macro result")
        }
    }

    func testWebsiteMapping_CreatesMacroWithOpenLinkStep() {
        let action = makeStreamDeckAction(
            position: "0,0",
            title: "Google",
            settings: .website(url: "https://google.com")
        )
        let result = StreamDeckImportMapper.convertAction(action)

        if case .macro(let macro) = result {
            XCTAssertEqual(macro.steps.count, 1)
            if case .openLink(let url) = macro.steps[0] {
                XCTAssertEqual(url, "https://google.com")
            } else {
                XCTFail("Expected openLink step")
            }
        } else {
            XCTFail("Expected macro result")
        }
    }

    func testTextMapping_CreatesMacroWithTypeTextStep() {
        let action = makeStreamDeckAction(
            position: "0,0",
            title: "Greeting",
            settings: .text("Hello, world!")
        )
        let result = StreamDeckImportMapper.convertAction(action)

        if case .macro(let macro) = result {
            XCTAssertEqual(macro.steps.count, 1)
            if case .typeText(let text, let speed, let pressEnter) = macro.steps[0] {
                XCTAssertEqual(text, "Hello, world!")
                XCTAssertEqual(speed, 0) // Paste mode
                XCTAssertFalse(pressEnter)
            } else {
                XCTFail("Expected typeText step")
            }
        } else {
            XCTFail("Expected macro result")
        }
    }

    // MARK: - Mapper: Profile Building

    func testBuildProfile_LinksMacroIdsToKeyMappings() {
        let actions = [
            makeStreamDeckAction(position: "0,0", title: "Google", settings: .website(url: "https://google.com"))
        ]
        var mapped = StreamDeckImportMapper.mapActions(actions)
        mapped[0].assignedButton = .a

        let profile = StreamDeckImportMapper.buildProfile(name: "Test", mappedActions: mapped)

        XCTAssertEqual(profile.macros.count, 1)
        let macro = profile.macros[0]
        let keyMapping = profile.buttonMappings[.a]
        XCTAssertNotNil(keyMapping)
        XCTAssertEqual(keyMapping?.macroId, macro.id)
    }

    func testBuildProfile_SetsHintFromTitle() {
        let actions = [
            makeStreamDeckAction(position: "0,0", title: "My Shortcut", settings: .hotkey(1, ModifierFlags(command: true)))
        ]
        var mapped = StreamDeckImportMapper.mapActions(actions)
        mapped[0].assignedButton = .a

        let profile = StreamDeckImportMapper.buildProfile(name: "Test", mappedActions: mapped)

        let keyMapping = profile.buttonMappings[.a]
        XCTAssertEqual(keyMapping?.hint, "My Shortcut")
    }

    func testBuildProfile_DirectHotkeyHasNoMacro() {
        let actions = [
            makeStreamDeckAction(position: "0,0", title: "Save", settings: .hotkey(1, ModifierFlags(command: true)))
        ]
        var mapped = StreamDeckImportMapper.mapActions(actions)
        mapped[0].assignedButton = .a

        let profile = StreamDeckImportMapper.buildProfile(name: "Test", mappedActions: mapped)

        XCTAssertTrue(profile.macros.isEmpty, "Direct hotkeys should not create macros")
        let keyMapping = profile.buttonMappings[.a]
        XCTAssertNotNil(keyMapping)
        XCTAssertEqual(keyMapping?.keyCode, 1)
        XCTAssertNil(keyMapping?.macroId)
    }

    func testBuildProfile_UnassignedActionsSkipped() {
        let actions = [
            makeStreamDeckAction(position: "0,0", title: "Save", settings: .hotkey(1, ModifierFlags(command: true)))
        ]
        var mapped = StreamDeckImportMapper.mapActions(actions)
        mapped[0].assignedButton = nil // Explicitly unassign

        let profile = StreamDeckImportMapper.buildProfile(name: "Test", mappedActions: mapped)

        XCTAssertTrue(profile.buttonMappings.isEmpty)
        XCTAssertTrue(profile.macros.isEmpty)
    }

    // MARK: - Helpers

    private func makeManifest(name: String = "Test Profile", actions: [String: Any]) -> [String: Any] {
        return ["Name": name, "Actions": actions]
    }

    private func makeStreamDeckAction(
        position: String,
        name: String = "",
        title: String? = nil,
        settings: StreamDeckActionSettings
    ) -> StreamDeckAction {
        StreamDeckAction(
            position: position,
            name: name,
            title: title,
            settings: settings
        )
    }
}
