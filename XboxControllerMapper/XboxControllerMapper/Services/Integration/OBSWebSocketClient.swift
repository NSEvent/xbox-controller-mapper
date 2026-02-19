import Foundation
import CryptoKit

struct OBSRequestExecutionResult: Equatable {
    let code: Int
    let comment: String?
}

enum OBSWebSocketError: Error, Equatable {
    case invalidRequestType
    case invalidRequestDataJSON
    case requestDataMustBeJSONObject
    case invalidMessage
    case invalidHello
    case authenticationRequired
    case missingIdentified
    case requestFailed(code: Int, comment: String?)
    case timeout
}

protocol OBSWebSocketTransportProtocol: AnyObject {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close()
}

protocol OBSWebSocketClientProtocol {
    func executeRequest(
        requestType: String,
        requestDataJSON: String?,
        timeout: TimeInterval
    ) async throws -> OBSRequestExecutionResult
}

final class URLSessionOBSWebSocketTransport: OBSWebSocketTransportProtocol {
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        self.task = session.webSocketTask(with: url)
        self.task.resume()
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw OBSWebSocketError.invalidMessage
            }
            return text
        @unknown default:
            throw OBSWebSocketError.invalidMessage
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

final class OBSWebSocketClient: OBSWebSocketClientProtocol {
    typealias TransportFactory = (URL) -> OBSWebSocketTransportProtocol
    typealias RequestIDProvider = () -> String

    private let url: URL
    private let password: String?
    private let transportFactory: TransportFactory
    private let requestIdProvider: RequestIDProvider

    init(
        url: URL,
        password: String?,
        transportFactory: @escaping TransportFactory = { URLSessionOBSWebSocketTransport(url: $0) },
        requestIdProvider: @escaping RequestIDProvider = { UUID().uuidString }
    ) {
        self.url = url
        self.password = password
        self.transportFactory = transportFactory
        self.requestIdProvider = requestIdProvider
    }

    func executeRequest(
        requestType: String,
        requestDataJSON: String?,
        timeout: TimeInterval
    ) async throws -> OBSRequestExecutionResult {
        let requestType = requestType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestType.isEmpty else {
            throw OBSWebSocketError.invalidRequestType
        }
        guard timeout > 0 else {
            throw OBSWebSocketError.timeout
        }

        let transport = transportFactory(url)
        defer { transport.close() }

        let hello = try await receiveJSONObject(from: transport)
        guard (hello["op"] as? Int) == 0 else {
            throw OBSWebSocketError.invalidHello
        }

        let helloData = hello["d"] as? [String: Any] ?? [:]
        var identifyData: [String: Any] = ["rpcVersion": 1]

        if let auth = helloData["authentication"] as? [String: Any] {
            guard let salt = auth["salt"] as? String,
                  let challenge = auth["challenge"] as? String else {
                throw OBSWebSocketError.invalidHello
            }

            guard let password = password, !password.isEmpty else {
                throw OBSWebSocketError.authenticationRequired
            }

            identifyData["authentication"] = Self.computeAuth(
                password: password,
                salt: salt,
                challenge: challenge
            )
        }

        try await sendJSONObject(["op": 1, "d": identifyData], via: transport)

        let identified = try await receiveJSONObject(from: transport)
        guard (identified["op"] as? Int) == 2 else {
            throw OBSWebSocketError.missingIdentified
        }

        var requestPayload: [String: Any] = [
            "requestType": requestType,
            "requestId": requestIdProvider()
        ]

        if let requestDataJSON = requestDataJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestDataJSON.isEmpty {
            requestPayload["requestData"] = try parseRequestData(from: requestDataJSON)
        }

        guard let requestID = requestPayload["requestId"] as? String else {
            throw OBSWebSocketError.invalidMessage
        }
        try await sendJSONObject(["op": 6, "d": requestPayload], via: transport)

        for _ in 0..<20 {
            let message = try await receiveJSONObject(from: transport)
            guard let op = message["op"] as? Int else {
                throw OBSWebSocketError.invalidMessage
            }
            guard op == 7 else {
                continue
            }

            guard let responseData = message["d"] as? [String: Any],
                  let responseRequestID = responseData["requestId"] as? String,
                  responseRequestID == requestID,
                  let status = responseData["requestStatus"] as? [String: Any],
                  let result = status["result"] as? Bool,
                  let code = status["code"] as? Int else {
                throw OBSWebSocketError.invalidMessage
            }

            let comment = status["comment"] as? String
            if result {
                return OBSRequestExecutionResult(code: code, comment: comment)
            }
            throw OBSWebSocketError.requestFailed(code: code, comment: comment)
        }

        throw OBSWebSocketError.timeout
    }

    private func parseRequestData(from json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw OBSWebSocketError.invalidRequestDataJSON
        }

        guard let dictionary = object as? [String: Any] else {
            throw OBSWebSocketError.requestDataMustBeJSONObject
        }
        return dictionary
    }

    private func receiveJSONObject(from transport: OBSWebSocketTransportProtocol) async throws -> [String: Any] {
        let text = try await transport.receiveText()
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = object as? [String: Any] else {
            throw OBSWebSocketError.invalidMessage
        }
        return json
    }

    private func sendJSONObject(_ object: [String: Any], via transport: OBSWebSocketTransportProtocol) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw OBSWebSocketError.invalidMessage
        }
        try await transport.send(text: text)
    }

    private static func computeAuth(password: String, salt: String, challenge: String) -> String {
        let secretInput = Data((password + salt).utf8)
        let secretHash = Data(SHA256.hash(data: secretInput))
        let secret = secretHash.base64EncodedString()

        let authInput = Data((secret + challenge).utf8)
        let authHash = Data(SHA256.hash(data: authInput))
        return authHash.base64EncodedString()
    }
}
