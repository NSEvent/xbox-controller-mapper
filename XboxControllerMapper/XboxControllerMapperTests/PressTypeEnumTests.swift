import XCTest
@testable import ControllerKeys

final class PressTypeEnumTests: XCTestCase {

    // MARK: - Enum Cases

    func testPressTypeHasAllExpectedCases() {
        // Verify all four cases exist and are constructible
        let press = PressType.press
        let release = PressType.release
        let longHold = PressType.longHold
        let doubleTap = PressType.doubleTap

        XCTAssertEqual(press, .press)
        XCTAssertEqual(release, .release)
        XCTAssertEqual(longHold, .longHold)
        XCTAssertEqual(doubleTap, .doubleTap)
    }

    func testPressTypeCasesAreDistinct() {
        let allCases: [PressType] = [.press, .release, .longHold, .doubleTap]
        let uniqueCount = Set(allCases).count
        XCTAssertEqual(uniqueCount, 4, "All PressType cases should be distinct")
    }

    // MARK: - Raw Values for Codable Serialization

    func testPressTypeRawValues() {
        XCTAssertEqual(PressType.press.rawValue, "press")
        XCTAssertEqual(PressType.release.rawValue, "release")
        XCTAssertEqual(PressType.longHold.rawValue, "longHold")
        XCTAssertEqual(PressType.doubleTap.rawValue, "doubleTap")
    }

    func testPressTypeInitFromRawValue() {
        XCTAssertEqual(PressType(rawValue: "press"), .press)
        XCTAssertEqual(PressType(rawValue: "release"), .release)
        XCTAssertEqual(PressType(rawValue: "longHold"), .longHold)
        XCTAssertEqual(PressType(rawValue: "doubleTap"), .doubleTap)
    }

    func testPressTypeInvalidRawValueReturnsNil() {
        XCTAssertNil(PressType(rawValue: "invalid"))
        XCTAssertNil(PressType(rawValue: ""))
        XCTAssertNil(PressType(rawValue: "Press"))  // Case-sensitive
        XCTAssertNil(PressType(rawValue: "long_hold"))
    }

    // MARK: - ScriptTrigger Uses Enum Type

    func testScriptTriggerUsesPressTypeEnum() {
        let trigger = ScriptTrigger(button: .a, pressType: .press)
        // This compiles only if pressType is PressType, not String
        let _: PressType = trigger.pressType
        XCTAssertEqual(trigger.pressType, .press)
    }

    func testScriptTriggerDefaultPressType() {
        let trigger = ScriptTrigger(button: .a)
        XCTAssertEqual(trigger.pressType, .press, "Default pressType should be .press")
    }

    func testScriptTriggerWithDifferentPressTypes() {
        let pressTrigger = ScriptTrigger(button: .a, pressType: .press)
        let releaseTrigger = ScriptTrigger(button: .b, pressType: .release)
        let longHoldTrigger = ScriptTrigger(button: .x, pressType: .longHold)
        let doubleTapTrigger = ScriptTrigger(button: .y, pressType: .doubleTap)

        XCTAssertEqual(pressTrigger.pressType, .press)
        XCTAssertEqual(releaseTrigger.pressType, .release)
        XCTAssertEqual(longHoldTrigger.pressType, .longHold)
        XCTAssertEqual(doubleTapTrigger.pressType, .doubleTap)
    }

    // MARK: - Codable Backward Compatibility

    func testPressTypeEncodesCorrectly() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(PressType.longHold)
        let jsonString = String(data: data, encoding: .utf8)!
        XCTAssertEqual(jsonString, "\"longHold\"")
    }

    func testPressTypeDecodesFromStringValue() throws {
        // Simulate old JSON with string values -- backward compatibility
        let decoder = JSONDecoder()

        let pressData = "\"press\"".data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(PressType.self, from: pressData), .press)

        let releaseData = "\"release\"".data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(PressType.self, from: releaseData), .release)

        let longHoldData = "\"longHold\"".data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(PressType.self, from: longHoldData), .longHold)

        let doubleTapData = "\"doubleTap\"".data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(PressType.self, from: doubleTapData), .doubleTap)
    }

    func testPressTypeRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for pressType in [PressType.press, .release, .longHold, .doubleTap] {
            let data = try encoder.encode(pressType)
            let decoded = try decoder.decode(PressType.self, from: data)
            XCTAssertEqual(decoded, pressType, "Round-trip failed for \(pressType)")
        }
    }
}
