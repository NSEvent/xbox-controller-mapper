import XCTest
import CoreGraphics
@testable import ControllerKeys

final class CodexMicroBridgeTests: XCTestCase {
	func testWireFramesRoundTripLongUTF8Message() throws {
		let source = try XCTUnwrap(
			CodexMicroWireProtocol.notification(
				method: "v.oai.hid",
				parameters: ["k": "ACT12", "act": 1, "label": String(repeating: "é", count: 50)]
			)
		)
		let frames = CodexMicroWireProtocol.frames(for: source)
		XCTAssertGreaterThan(frames.count, 1)
		XCTAssertTrue(frames.allSatisfy { $0.count == CodexMicroWireProtocol.reportSize })

		let reconstructed = frames.compactMap(CodexMicroWireProtocol.payload(from:)).reduce(into: Data()) {
			$0.append($1.bytes)
		}
		XCTAssertEqual(reconstructed, source)
	}

	func testExtractJSONObjectsHandlesEscapedBracesAndPartialTail() throws {
		var buffer = Data(#"{"method":"one","params":{"text":"} \" still quoted"}}{"method":"two""#.utf8)
		let firstPass = CodexMicroWireProtocol.extractJSONObjects(from: &buffer)
		XCTAssertEqual(firstPass.count, 1)
		let firstObject = try XCTUnwrap(
			JSONSerialization.jsonObject(with: firstPass[0]) as? [String: Any]
		)
		XCTAssertEqual(firstObject["method"] as? String, "one")
		let parameters = try XCTUnwrap(firstObject["params"] as? [String: String])
		XCTAssertEqual(parameters["text"], "} \" still quoted")

		buffer.append(Data(#"}"#.utf8))
		let secondPass = CodexMicroWireProtocol.extractJSONObjects(from: &buffer)
		XCTAssertEqual(secondPass.count, 1)
		XCTAssertEqual(
			try JSONSerialization.jsonObject(with: secondPass[0]) as? [String: String],
			["method": "two"]
		)
	}

	func testDeviceStatusRequestGetsRequiredFirmwareShape() throws {
		let request = Data(#"{"method":"device.status","id":77}"#.utf8)
		let responseData = try XCTUnwrap(CodexMicroWireProtocol.response(to: request))
		let response = try XCTUnwrap(
			JSONSerialization.jsonObject(with: responseData) as? [String: Any]
		)
		XCTAssertEqual(response["id"] as? Int, 77)
		let result = try XCTUnwrap(response["result"] as? [String: Any])
		XCTAssertEqual(result["version"] as? String, "1.0.0")
		XCTAssertEqual(result["battery"] as? Int, 100)
		XCTAssertEqual(result["is_charging"] as? Bool, false)
	}

	func testCodexMicroControlMatchesChatGPTDirectionAndHIDContract() {
		XCTAssertEqual(CodexMicroControl.stickRight.joystickAngle, 0)
		XCTAssertEqual(CodexMicroControl.stickDown.joystickAngle, 0.25)
		XCTAssertEqual(CodexMicroControl.stickLeft.joystickAngle, 0.5)
		XCTAssertEqual(CodexMicroControl.stickUp.joystickAngle, 0.75)
		XCTAssertEqual(CodexMicroControl.agent6.hidKey, "AG05")
		XCTAssertEqual(CodexMicroControl.submit.hidKey, "ACT12")
		XCTAssertEqual(CodexMicroControl.dialClockwise.hidKey, "ENC_CW")
	}

	func testInputSimulatorRoutesCodexMarkersWithoutCGEvents() {
		let output = MockCodexMicroOutput()
		let simulator = InputSimulator(codexMicroOutput: output)

		simulator.pressKey(CodexMicroControl.fast.keyCode, modifiers: CGEventFlags())
		simulator.keyDown(CodexMicroControl.pushToTalk.keyCode, modifiers: CGEventFlags())
		simulator.keyUp(CodexMicroControl.pushToTalk.keyCode)

		XCTAssertEqual(output.events, [
			.tap(.fast),
			.press(.pushToTalk),
			.release(.pushToTalk)
		])
	}

	func testCircularDialPolicyAccumulatesAndRespectsInversion() {
		var clockwiseAccumulator = 0.0
		XCTAssertEqual(
			AppleTVRemoteCircularInputPolicy.codexMicroDialTicks(
				angleDelta: 0.12,
				sensitivity: 0.5,
				isInverted: false,
				accumulator: &clockwiseAccumulator
			),
			0
		)
		XCTAssertEqual(
			AppleTVRemoteCircularInputPolicy.codexMicroDialTicks(
				angleDelta: 0.15,
				sensitivity: 0.5,
				isInverted: false,
				accumulator: &clockwiseAccumulator
			),
			1
		)

		var invertedAccumulator = 0.0
		XCTAssertEqual(
			AppleTVRemoteCircularInputPolicy.codexMicroDialTicks(
				angleDelta: 0.3,
				sensitivity: 0.5,
				isInverted: true,
				accumulator: &invertedAccumulator
			),
			-1
		)
	}

	func testCircularInputModeDefaultsAndRoundTrips() throws {
		let defaultSettings = try JSONDecoder().decode(JoystickSettings.self, from: Data("{}".utf8))
		XCTAssertEqual(defaultSettings.appleTVRemoteCircularInputMode, .scroll)

		var settings = JoystickSettings.default
		settings.appleTVRemoteCircularInputMode = .codexMicroDial
		let decoded = try JSONDecoder().decode(
			JoystickSettings.self,
			from: JSONEncoder().encode(settings)
		)
		XCTAssertEqual(decoded.appleTVRemoteCircularInputMode, .codexMicroDial)
	}

	func testAppleTVRemoteCommunityProfileDecodesWithCodexMappings() throws {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let profileURL = repositoryRoot
			.appendingPathComponent("community-profiles")
			.appendingPathComponent("Codex Micro - Apple TV Remote.json")
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let profile = try decoder.decode(Profile.self, from: Data(contentsOf: profileURL))

		XCTAssertEqual(profile.linkedApps, ["com.openai.chat"])
		XCTAssertEqual(profile.joystickSettings.appleTVRemoteCircularInputMode, .codexMicroDial)
		XCTAssertEqual(profile.buttonMappings[.siri]?.keyCode, CodexMicroControl.pushToTalk.keyCode)
		XCTAssertTrue(profile.buttonMappings[.siri]?.isHoldModifier == true)
		let agentLayer = try XCTUnwrap(profile.layers.first)
		XCTAssertEqual(agentLayer.activatorButton, .appleTVRemotePower)
		XCTAssertEqual(agentLayer.buttonMappings[.xbox]?.keyCode, CodexMicroControl.agent1.keyCode)
		XCTAssertEqual(agentLayer.buttonMappings[.menu]?.keyCode, CodexMicroControl.agent6.keyCode)
	}
}
