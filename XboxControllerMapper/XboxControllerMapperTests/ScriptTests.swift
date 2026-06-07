import XCTest
@testable import ControllerKeys

final class ScriptTests: XCTestCase {

    // MARK: - Script Tests

    func testScriptDefaultInitialization() {
        let script = Script()

        XCTAssertFalse(script.id.uuidString.isEmpty)
        XCTAssertEqual(script.name, "")
        XCTAssertEqual(script.source, "")
        XCTAssertNil(script.description)
        XCTAssertNotNil(script.createdAt)
        XCTAssertNotNil(script.modifiedAt)
    }

    func testScriptExplicitInitialization() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1000)
        let modifiedAt = Date(timeIntervalSince1970: 2000)

        let script = Script(
            id: id,
            name: "Test Script",
            source: "console.log('test');",
            description: "A script for testing",
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )

        XCTAssertEqual(script.id, id)
        XCTAssertEqual(script.name, "Test Script")
        XCTAssertEqual(script.source, "console.log('test');")
        XCTAssertEqual(script.description, "A script for testing")
        XCTAssertEqual(script.createdAt, createdAt)
        XCTAssertEqual(script.modifiedAt, modifiedAt)
    }

    func testScriptCodableRoundTrip() throws {
        let originalScript = Script(
            name: "My Script",
            source: "return true;",
            description: "Docs"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalScript)

        let decoder = JSONDecoder()
        let decodedScript = try decoder.decode(Script.self, from: data)

        XCTAssertEqual(originalScript, decodedScript)
    }

    func testScriptDecodingWithMissingFields() throws {
        // Only id is provided, testing defaults in init(from decoder:)
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decodedScript = try decoder.decode(Script.self, from: json)

        XCTAssertEqual(decodedScript.id.uuidString, "123E4567-E89B-12D3-A456-426614174000")
        XCTAssertEqual(decodedScript.name, "")
        XCTAssertEqual(decodedScript.source, "")
        XCTAssertNil(decodedScript.description)
        XCTAssertNotNil(decodedScript.createdAt)
        XCTAssertNotNil(decodedScript.modifiedAt)
    }

    // MARK: - PressType Tests

    func testPressTypeCodable() throws {
        let types: [PressType] = [.press, .release, .longHold, .doubleTap]

        let encoder = JSONEncoder()
        let data = try encoder.encode(types)

        let decoder = JSONDecoder()
        let decodedTypes = try decoder.decode([PressType].self, from: data)

        XCTAssertEqual(types, decodedTypes)
    }

    func testPressTypeRawValues() {
        XCTAssertEqual(PressType.press.rawValue, "press")
        XCTAssertEqual(PressType.release.rawValue, "release")
        XCTAssertEqual(PressType.longHold.rawValue, "longHold")
        XCTAssertEqual(PressType.doubleTap.rawValue, "doubleTap")
    }

    // MARK: - ScriptTrigger Tests

    func testScriptTriggerDefaultInitialization() {
        let trigger = ScriptTrigger(button: .a)

        XCTAssertEqual(trigger.button, .a)
        XCTAssertEqual(trigger.pressType, .press)
        XCTAssertNil(trigger.holdDuration)
        XCTAssertNotNil(trigger.timestamp)
    }

    func testScriptTriggerExplicitInitialization() {
        let timestamp = Date(timeIntervalSince1970: 5000)
        let trigger = ScriptTrigger(
            button: .leftBumper,
            pressType: .longHold,
            holdDuration: 2.5,
            timestamp: timestamp
        )

        XCTAssertEqual(trigger.button, .leftBumper)
        XCTAssertEqual(trigger.pressType, .longHold)
        XCTAssertEqual(trigger.holdDuration, 2.5)
        XCTAssertEqual(trigger.timestamp, timestamp)
    }

    // MARK: - ScriptResult Tests

    func testScriptResultSuccess() {
        let resultWithoutHint = ScriptResult.success(hintOverride: nil)
        if case let .success(hintOverride) = resultWithoutHint {
            XCTAssertNil(hintOverride)
        } else {
            XCTFail("Expected success")
        }

        let resultWithHint = ScriptResult.success(hintOverride: "Press A to jump")
        if case let .success(hintOverride) = resultWithHint {
            XCTAssertEqual(hintOverride, "Press A to jump")
        } else {
            XCTFail("Expected success")
        }
    }

    func testScriptResultError() {
        let resultError = ScriptResult.error("Syntax Error")
        if case let .error(message) = resultError {
            XCTAssertEqual(message, "Syntax Error")
        } else {
            XCTFail("Expected error")
        }
    }
}
