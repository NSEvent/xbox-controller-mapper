import XCTest
import Foundation
import CryptoKit
@testable import ControllerKeys

private enum MockTransportError: Error {
    case noQueuedResponse
}

private final class MockOBSWebSocketTransport: OBSWebSocketTransportProtocol {
    var queuedResponses: [Result<String, Error>]
    private(set) var sentMessages: [String] = []
    private(set) var closeCallCount = 0

    init(queuedResponses: [Result<String, Error>]) {
        self.queuedResponses = queuedResponses
    }

    func send(text: String) async throws {
        sentMessages.append(text)
    }

    func receiveText() async throws -> String {
        guard !queuedResponses.isEmpty else {
            throw MockTransportError.noQueuedResponse
        }
        return try queuedResponses.removeFirst().get()
    }

    func close() {
        closeCallCount += 1
    }
}

private final class MockOBSWebSocketClient: OBSWebSocketClientProtocol {
    struct Call: Equatable {
        let requestType: String
        let requestDataJSON: String?
        let timeout: TimeInterval
    }

    var result: Result<OBSRequestExecutionResult, Error> = .success(.init(code: 100, comment: "OK"))
    private(set) var calls: [Call] = []

    func executeRequest(
        requestType: String,
        requestDataJSON: String?,
        timeout: TimeInterval
    ) async throws -> OBSRequestExecutionResult {
        calls.append(.init(requestType: requestType, requestDataJSON: requestDataJSON, timeout: timeout))
        return try result.get()
    }
}

final class OBSWebSocketTests: XCTestCase {
    private var executor: SystemCommandExecutor!
    private var profileManager: ProfileManager!
    private var mockOBSClient: MockOBSWebSocketClient!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            profileManager = ProfileManager()
            mockOBSClient = MockOBSWebSocketClient()
            let injectedClient = mockOBSClient!
            executor = SystemCommandExecutor(
                profileManager: profileManager,
                obsClientFactory: { _, _ in injectedClient }
            )
        }
    }

    override func tearDown() async throws {
        executor = nil
        profileManager = nil
        mockOBSClient = nil
        try await super.tearDown()
    }

    // MARK: - SystemCommand Codable / Display

    func testOBSWebSocketCommand_Encoding() throws {
        let command = SystemCommand.obsWebSocket(
            url: "ws://127.0.0.1:4455",
            password: "secret",
            requestType: "SetCurrentProgramScene",
            requestData: "{\"sceneName\":\"Live\"}"
        )

        let data = try JSONEncoder().encode(command)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "obsWebSocket")
        XCTAssertEqual(json["url"] as? String, "ws://127.0.0.1:4455")
        XCTAssertEqual(json["password"] as? String, "secret")
        XCTAssertEqual(json["requestType"] as? String, "SetCurrentProgramScene")
        XCTAssertEqual(json["requestData"] as? String, "{\"sceneName\":\"Live\"}")
    }

    func testOBSWebSocketCommand_DecodingWithDefaults() throws {
        let json = """
        {
            "type": "obsWebSocket",
            "url": "wss://obs.example.com:4455",
            "requestType": "StartRecord"
        }
        """

        let command = try JSONDecoder().decode(SystemCommand.self, from: Data(json.utf8))

        guard case .obsWebSocket(let url, let password, let requestType, let requestData) = command else {
            XCTFail("Expected obsWebSocket command")
            return
        }

        XCTAssertEqual(url, "wss://obs.example.com:4455")
        XCTAssertNil(password)
        XCTAssertEqual(requestType, "StartRecord")
        XCTAssertNil(requestData)
    }

    func testOBSWebSocketCommand_CategoryAndDisplayName() {
        let command = SystemCommand.obsWebSocket(
            url: "ws://127.0.0.1:4455",
            password: nil,
            requestType: "StartRecord",
            requestData: nil
        )

        XCTAssertEqual(command.category, .obs)
        XCTAssertEqual(command.displayName, "OBS StartRecord")
    }

    // MARK: - OBS WebSocket Client

    func testOBSClient_NoAuthHandshake_SendsIdentifyAndRequest() async throws {
        let requestId = "req-1"
        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON(["op": 0, "d": ["rpcVersion": 1]])),
            .success(Self.makeJSON(["op": 2, "d": ["negotiatedRpcVersion": 1]])),
            .success(Self.makeJSON([
                "op": 7,
                "d": [
                    "requestType": "StartRecord",
                    "requestId": requestId,
                    "requestStatus": [
                        "result": true,
                        "code": 100,
                        "comment": "OK"
                    ]
                ]
            ]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: nil,
            transportFactory: { _ in transport },
            requestIdProvider: { requestId }
        )

        let result = try await client.executeRequest(
            requestType: "StartRecord",
            requestDataJSON: nil,
            timeout: 1
        )

        XCTAssertEqual(result.code, 100)
        XCTAssertEqual(transport.sentMessages.count, 2)
        XCTAssertEqual(transport.closeCallCount, 1)

        let identifyPayload = try Self.decodeJSON(transport.sentMessages[0])
        XCTAssertEqual(identifyPayload["op"] as? Int, 1)
        let identifyData = try XCTUnwrap(identifyPayload["d"] as? [String: Any])
        XCTAssertEqual(identifyData["rpcVersion"] as? Int, 1)
        XCTAssertNil(identifyData["authentication"])

        let requestPayload = try Self.decodeJSON(transport.sentMessages[1])
        XCTAssertEqual(requestPayload["op"] as? Int, 6)
        let requestData = try XCTUnwrap(requestPayload["d"] as? [String: Any])
        XCTAssertEqual(requestData["requestType"] as? String, "StartRecord")
        XCTAssertEqual(requestData["requestId"] as? String, requestId)
        XCTAssertNil(requestData["requestData"])
    }

    func testOBSClient_AuthHandshake_SendsExpectedAuthentication() async throws {
        let requestId = "req-auth"
        let salt = "salt123"
        let challenge = "challenge456"
        let password = "top-secret"
        let expectedAuth = Self.obsAuth(password: password, salt: salt, challenge: challenge)

        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON([
                "op": 0,
                "d": [
                    "rpcVersion": 1,
                    "authentication": [
                        "salt": salt,
                        "challenge": challenge
                    ]
                ]
            ])),
            .success(Self.makeJSON(["op": 2, "d": ["negotiatedRpcVersion": 1]])),
            .success(Self.makeJSON([
                "op": 7,
                "d": [
                    "requestType": "SetCurrentProgramScene",
                    "requestId": requestId,
                    "requestStatus": [
                        "result": true,
                        "code": 100
                    ]
                ]
            ]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: password,
            transportFactory: { _ in transport },
            requestIdProvider: { requestId }
        )

        _ = try await client.executeRequest(
            requestType: "SetCurrentProgramScene",
            requestDataJSON: "{\"sceneName\":\"BRB\"}",
            timeout: 1
        )

        let identifyPayload = try Self.decodeJSON(transport.sentMessages[0])
        let identifyData = try XCTUnwrap(identifyPayload["d"] as? [String: Any])
        XCTAssertEqual(identifyData["authentication"] as? String, expectedAuth)

        let requestPayload = try Self.decodeJSON(transport.sentMessages[1])
        let requestData = try XCTUnwrap(requestPayload["d"] as? [String: Any])
        XCTAssertEqual(requestData["requestType"] as? String, "SetCurrentProgramScene")
        let requestBody = try XCTUnwrap(requestData["requestData"] as? [String: Any])
        XCTAssertEqual(requestBody["sceneName"] as? String, "BRB")
    }

    func testOBSClient_MissingPasswordForAuthenticatedServer_Throws() async {
        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON([
                "op": 0,
                "d": [
                    "rpcVersion": 1,
                    "authentication": [
                        "salt": "abc",
                        "challenge": "def"
                    ]
                ]
            ]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: nil,
            transportFactory: { _ in transport },
            requestIdProvider: { "unused" }
        )

        do {
            _ = try await client.executeRequest(requestType: "StartRecord", requestDataJSON: nil, timeout: 1)
            XCTFail("Expected authenticationRequired error")
        } catch let error as OBSWebSocketError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOBSClient_InvalidRequestDataJSON_Throws() async {
        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON(["op": 0, "d": ["rpcVersion": 1]])),
            .success(Self.makeJSON(["op": 2, "d": ["negotiatedRpcVersion": 1]]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: nil,
            transportFactory: { _ in transport },
            requestIdProvider: { "req-invalid-json" }
        )

        do {
            _ = try await client.executeRequest(
                requestType: "SetCurrentProgramScene",
                requestDataJSON: "not-valid-json",
                timeout: 1
            )
            XCTFail("Expected invalidRequestDataJSON error")
        } catch let error as OBSWebSocketError {
            XCTAssertEqual(error, .invalidRequestDataJSON)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOBSClient_RequestStatusFailure_ThrowsRequestFailed() async {
        let requestId = "req-fail"
        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON(["op": 0, "d": ["rpcVersion": 1]])),
            .success(Self.makeJSON(["op": 2, "d": ["negotiatedRpcVersion": 1]])),
            .success(Self.makeJSON([
                "op": 7,
                "d": [
                    "requestType": "StartRecord",
                    "requestId": requestId,
                    "requestStatus": [
                        "result": false,
                        "code": 702,
                        "comment": "Output running"
                    ]
                ]
            ]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: nil,
            transportFactory: { _ in transport },
            requestIdProvider: { requestId }
        )

        do {
            _ = try await client.executeRequest(requestType: "StartRecord", requestDataJSON: nil, timeout: 1)
            XCTFail("Expected requestFailed error")
        } catch let error as OBSWebSocketError {
            XCTAssertEqual(error, .requestFailed(code: 702, comment: "Output running"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOBSClient_IgnoresEventMessagesUntilResponse() async throws {
        let requestId = "req-with-event"
        let transport = MockOBSWebSocketTransport(queuedResponses: [
            .success(Self.makeJSON(["op": 0, "d": ["rpcVersion": 1]])),
            .success(Self.makeJSON(["op": 2, "d": ["negotiatedRpcVersion": 1]])),
            .success(Self.makeJSON(["op": 5, "d": ["eventType": "CurrentProgramSceneChanged"]])),
            .success(Self.makeJSON([
                "op": 7,
                "d": [
                    "requestType": "GetVersion",
                    "requestId": requestId,
                    "requestStatus": ["result": true, "code": 100]
                ]
            ]))
        ])

        let client = OBSWebSocketClient(
            url: URL(string: "ws://127.0.0.1:4455")!,
            password: nil,
            transportFactory: { _ in transport },
            requestIdProvider: { requestId }
        )

        let result = try await client.executeRequest(requestType: "GetVersion", requestDataJSON: nil, timeout: 1)
        XCTAssertEqual(result.code, 100)
        XCTAssertEqual(transport.closeCallCount, 1)
    }

    // MARK: - Executor OBS Integration

    func testExecuteOBSCommand_Success_FeedbackAndPayloadForwarded() async {
        let command = SystemCommand.obsWebSocket(
            url: "ws://127.0.0.1:4455",
            password: "pw",
            requestType: "StartRecord",
            requestData: "{\"foo\":true}"
        )

        let feedbackExpectation = expectation(description: "Feedback callback")
        executor.webhookFeedbackHandler = { success, message in
            XCTAssertTrue(success)
            XCTAssertEqual(message, "OBS 100")
            feedbackExpectation.fulfill()
        }

        executor.execute(command)
        await fulfillment(of: [feedbackExpectation], timeout: 1.0)

        XCTAssertEqual(mockOBSClient.calls.count, 1)
        XCTAssertEqual(mockOBSClient.calls[0].requestType, "StartRecord")
        XCTAssertEqual(mockOBSClient.calls[0].requestDataJSON, "{\"foo\":true}")
    }

    func testExecuteOBSCommand_Failure_ReportsErrorFeedback() async {
        mockOBSClient.result = .failure(OBSWebSocketError.requestFailed(code: 702, comment: "Output running"))
        let command = SystemCommand.obsWebSocket(
            url: "ws://127.0.0.1:4455",
            password: nil,
            requestType: "StartRecord",
            requestData: nil
        )

        let feedbackExpectation = expectation(description: "Failure feedback callback")
        executor.webhookFeedbackHandler = { success, message in
            XCTAssertFalse(success)
            XCTAssertEqual(message, "OBS Error")
            feedbackExpectation.fulfill()
        }

        executor.execute(command)
        await fulfillment(of: [feedbackExpectation], timeout: 1.0)

        XCTAssertEqual(mockOBSClient.calls.count, 1)
    }

    func testExecuteOBSCommand_InvalidURLScheme_DoesNotInvokeClient() async {
        let command = SystemCommand.obsWebSocket(
            url: "https://example.com",
            password: nil,
            requestType: "StartRecord",
            requestData: nil
        )

        executor.execute(command)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(mockOBSClient.calls.isEmpty)
    }

    func testExecuteOBSCommand_EmptyRequestType_DoesNotInvokeClient() async {
        let command = SystemCommand.obsWebSocket(
            url: "ws://127.0.0.1:4455",
            password: nil,
            requestType: "   ",
            requestData: nil
        )

        executor.execute(command)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(mockOBSClient.calls.isEmpty)
    }

    // MARK: - Helpers

    private static func makeJSON(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [])
        return String(data: data, encoding: .utf8)!
    }

    private static func decodeJSON(_ string: String) throws -> [String: Any] {
        let data = Data(string.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func obsAuth(password: String, salt: String, challenge: String) -> String {
        let secretInput = Data((password + salt).utf8)
        let secretHash = Data(SHA256.hash(data: secretInput))
        let secret = secretHash.base64EncodedString()

        let authInput = Data((secret + challenge).utf8)
        let authHash = Data(SHA256.hash(data: authInput))
        return authHash.base64EncodedString()
    }
}
