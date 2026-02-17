import XCTest
import Foundation
import AppKit
import SwiftUI
@testable import ControllerKeys

@MainActor
final class ModelCodableCoverageTests: XCTestCase {

    // MARK: - QuickText / OnScreenKeyboardSettings

    func testQuickText_ContainsVariablesSupportsNumericVariableNames() {
        XCTAssertTrue(QuickText(text: "Now: {time.12}").containsVariables)
        XCTAssertTrue(QuickText(text: "{date}").containsVariables)
        XCTAssertFalse(QuickText(text: "no vars").containsVariables)
    }

    func testQuickTextDecoding_UsesDefaultsForMissingKeys() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(QuickText.self, from: data)

        XCTAssertEqual(decoded.text, "")
        XCTAssertFalse(decoded.isTerminalCommand)
    }

    func testWebsiteLink_EncodeOmitsFaviconDataAndComputesDomain() throws {
        let link = WebsiteLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: "https://www.example.com/path",
            displayName: "Example",
            faviconData: Data([0x01, 0x02, 0x03])
        )

        let jsonData = try JSONEncoder().encode(link)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])

        XCTAssertNil(json["faviconData"], "faviconData should remain cache-only")
        XCTAssertEqual(link.domain, "example.com")
        XCTAssertEqual(link.urlObject?.host, "www.example.com")
    }

    func testOnScreenKeyboardSettingsDecoding_Defaults() throws {
        let decoded = try JSONDecoder().decode(OnScreenKeyboardSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded.quickTexts, [])
        XCTAssertEqual(decoded.defaultTerminalApp, "Terminal")
        XCTAssertEqual(decoded.typingDelay, 0.03, accuracy: 0.0001)
        XCTAssertEqual(decoded.appBarItems, [])
        XCTAssertEqual(decoded.websiteLinks, [])
        XCTAssertFalse(decoded.showExtendedFunctionKeys)
        XCTAssertNil(decoded.toggleShortcutKeyCode)
        XCTAssertEqual(decoded.toggleShortcutModifiers, ModifierFlags())
        XCTAssertTrue(decoded.activateAllWindows)
        XCTAssertFalse(decoded.wheelShowsWebsites)
        XCTAssertEqual(decoded.wheelAlternateModifiers, ModifierFlags())
    }

    // MARK: - SystemCommand

    func testSystemCommandCategoriesAndDisplayNames() {
        let launch = SystemCommand.launchApp(bundleIdentifier: "com.fake.app", newWindow: true)
        let shell = SystemCommand.shellCommand(command: String(repeating: "x", count: 64), inTerminal: false)
        let link = SystemCommand.openLink(url: "https://example.com/very/long/path/that/should/truncate")
        let webhook = SystemCommand.httpRequest(url: "https://example.com/hook", method: .POST, headers: nil, body: nil)
        let obs = SystemCommand.obsWebSocket(url: "ws://127.0.0.1:4455", password: nil, requestType: "VeryLongRequestTypeNameThatShouldTruncate", requestData: nil)

        XCTAssertEqual(launch.category, .app)
        XCTAssertEqual(shell.category, .shell)
        XCTAssertEqual(link.category, .link)
        XCTAssertEqual(webhook.category, .webhook)
        XCTAssertEqual(obs.category, .obs)

        XCTAssertEqual(launch.displayName, "com.fake.app (New Window)")
        XCTAssertTrue(shell.displayName.hasSuffix("..."))
        XCTAssertTrue(link.displayName.hasSuffix("..."))
        XCTAssertTrue(obs.displayName.hasSuffix("..."))
    }

    func testSystemCommandCodable_DefaultsForMissingFields() throws {
        let launch = try JSONDecoder().decode(SystemCommand.self, from: Data(#"{"type":"launchApp"}"#.utf8))
        let shell = try JSONDecoder().decode(SystemCommand.self, from: Data(#"{"type":"shellCommand"}"#.utf8))
        let link = try JSONDecoder().decode(SystemCommand.self, from: Data(#"{"type":"openLink"}"#.utf8))
        let request = try JSONDecoder().decode(SystemCommand.self, from: Data(#"{"type":"httpRequest"}"#.utf8))
        let obs = try JSONDecoder().decode(SystemCommand.self, from: Data(#"{"type":"obsWebSocket"}"#.utf8))

        XCTAssertEqual(launch, .launchApp(bundleIdentifier: "", newWindow: false))
        XCTAssertEqual(shell, .shellCommand(command: "", inTerminal: false))
        XCTAssertEqual(link, .openLink(url: ""))
        XCTAssertEqual(request, .httpRequest(url: "", method: .POST, headers: nil, body: nil))
        XCTAssertEqual(obs, .obsWebSocket(url: "", password: nil, requestType: "", requestData: nil))
    }

    // MARK: - Macro

    func testMacroStepCodable_RoundTripsAllCases() throws {
        let mapping = KeyMapping.combo(KeyCodeMapping.keyA, modifiers: .command)

        let steps: [MacroStep] = [
            .press(mapping),
            .hold(mapping, duration: 1.25),
            .delay(0.75),
            .typeText("hello", speed: 120, pressEnter: true),
            .openApp(bundleIdentifier: "com.fake.app", newWindow: true),
            .openLink(url: "https://example.com")
        ]

        let data = try JSONEncoder().encode(steps)
        let decoded = try JSONDecoder().decode([MacroStep].self, from: data)
        XCTAssertEqual(decoded, steps)
    }

    func testMacroStepTypeTextDecoding_LegacyStringPayload() throws {
        let json = """
        {
            "type": "typeText",
            "payload": "legacy text"
        }
        """

        let decoded = try JSONDecoder().decode(MacroStep.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .typeText("legacy text", speed: 0, pressEnter: false))
    }

    func testMacroStepDisplayStrings() {
        let mapping = KeyMapping.combo(KeyCodeMapping.keyA, modifiers: .command)

        XCTAssertEqual(MacroStep.press(mapping).displayString, "Press: ⌘ + A")
        XCTAssertTrue(MacroStep.hold(mapping, duration: 1.234).displayString.contains("1.23s"))
        XCTAssertEqual(MacroStep.delay(0.5).displayString, "Wait: 0.50s")
        XCTAssertEqual(MacroStep.typeText("hello", speed: 0, pressEnter: true).displayString, "Type: \"hello\" (Paste) + ⏎")

        let longURL = "https://example.com/this/path/is/long/enough/to/trigger/truncation/in/display"
        let display = MacroStep.openLink(url: longURL).displayString
        XCTAssertTrue(display.hasPrefix("Open: https://example.com/"))
        XCTAssertTrue(display.hasSuffix("..."))
    }

    // MARK: - DualSense LED Models

    func testLightBarAndMuteEnumsExposeExpectedValues() {
        XCTAssertEqual(LightBarBrightness.bright.multiplier, 255)
        XCTAssertEqual(LightBarBrightness.mid.multiplier, 128)
        XCTAssertEqual(LightBarBrightness.dim.multiplier, 64)

        XCTAssertEqual(LightBarBrightness.bright.playerLEDBrightness, 0x00)
        XCTAssertEqual(LightBarBrightness.mid.playerLEDBrightness, 0x01)
        XCTAssertEqual(LightBarBrightness.dim.playerLEDBrightness, 0x02)

        XCTAssertEqual(MuteButtonLEDMode.off.byteValue, 0x00)
        XCTAssertEqual(MuteButtonLEDMode.on.byteValue, 0x01)
        XCTAssertEqual(MuteButtonLEDMode.breathing.byteValue, 0x02)
    }

    func testPlayerLEDsBitmaskAndPresets() {
        XCTAssertEqual(PlayerLEDs.default.bitmask, 0x00)
        XCTAssertEqual(PlayerLEDs.player1.bitmask, 0x04)
        XCTAssertEqual(PlayerLEDs.player2.bitmask, 0x0A)
        XCTAssertEqual(PlayerLEDs.player3.bitmask, 0x15)
        XCTAssertEqual(PlayerLEDs.player4.bitmask, 0x1B)
        XCTAssertEqual(PlayerLEDs.allOn.bitmask, 0x1F)
    }

    func testCodableColor_ByteConversionAndClamping() {
        let color = CodableColor(red: 0.5, green: 1.2, blue: -0.3)
        XCTAssertEqual(color.redByte, 127)
        XCTAssertEqual(color.greenByte, 255)
        XCTAssertEqual(color.blueByte, 0)

        let fromNSColor = CodableColor(nsColor: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0))
        XCTAssertEqual(fromNSColor.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(fromNSColor.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(fromNSColor.blue, 0.6, accuracy: 0.001)
    }

    func testDualSenseLEDSettings_ValidationAndDefaultDecoding() throws {
        let defaults = try JSONDecoder().decode(DualSenseLEDSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults, .default)
        XCTAssertTrue(defaults.isValid())

        let invalid = DualSenseLEDSettings(
            lightBarColor: CodableColor(red: 1.5, green: 0.2, blue: 0.2),
            lightBarBrightness: .bright,
            lightBarEnabled: true,
            muteButtonLED: .off,
            playerLEDs: .default
        )
        XCTAssertFalse(invalid.isValid())
    }
}
