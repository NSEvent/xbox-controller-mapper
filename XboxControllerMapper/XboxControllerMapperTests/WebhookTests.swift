import XCTest
@testable import ControllerKeys

// MARK: - Captured Request (preserves body data)

/// Wraps a URLRequest with its body data preserved
/// (URLRequest.httpBody is often nil after URLProtocol intercepts it)
struct CapturedRequest {
    let request: URLRequest
    let bodyData: Data?

    var url: URL? { request.url }
    var httpMethod: String? { request.httpMethod }
    var httpBody: Data? { bodyData }

    func value(forHTTPHeaderField field: String) -> String? {
        request.value(forHTTPHeaderField: field)
    }
}

// MARK: - Mock URL Protocol

/// Intercepts URLSession requests for testing without a real server
final class MockURLProtocol: URLProtocol {
    /// Handler that receives requests and returns mock responses
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Captured requests for verification (with body data preserved)
    static var capturedRequests: [CapturedRequest] = []

    /// Lock for thread-safe access to captured requests
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests = []
        requestHandler = nil
    }

    static func addCapturedRequest(_ request: URLRequest, bodyData: Data?) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests.append(CapturedRequest(request: request, bodyData: bodyData))
    }

    static func getCapturedRequests() -> [CapturedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Capture body data from httpBody or httpBodyStream
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    data.append(buffer, count: bytesRead)
                } else {
                    break
                }
            }
            if !data.isEmpty {
                bodyData = data
            }
        }

        MockURLProtocol.addCapturedRequest(request, bodyData: bodyData)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: 0, userInfo: [NSLocalizedDescriptionKey: "No request handler set"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Webhook Tests

/// Tests for HTTP request/webhook functionality
@MainActor
final class WebhookTests: XCTestCase {

    // MARK: - Properties

    private var executor: SystemCommandExecutor!
    private var mockSession: URLSession!
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        MockURLProtocol.reset()

        // Create a URLSession configured to use our mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Create profile manager and executor with mock session
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
        executor = SystemCommandExecutor(profileManager: profileManager, urlSession: mockSession)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        executor = nil
        mockSession = nil
        profileManager = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Sets up a mock response for all requests
    private func setupMockResponse(statusCode: Int = 200, data: Data? = nil) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
    }

    /// Waits for async execution to complete by polling for captured requests
    private func waitForExecution(timeout: TimeInterval = 2.0, expectedRequestCount: Int = 1) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if MockURLProtocol.getCapturedRequests().count >= expectedRequestCount {
                // Give a tiny bit more time for the request to fully process
                Thread.sleep(forTimeInterval: 0.05)
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    // MARK: - SystemCommand.httpRequest Codable Tests

    func testHTTPRequestCommand_Encoding() throws {
        // Given
        let command = SystemCommand.httpRequest(
            url: "https://example.com/webhook",
            method: .POST,
            headers: ["Authorization": "Bearer token123"],
            body: "{\"action\": \"test\"}"
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(command)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        XCTAssertEqual(json?["type"] as? String, "httpRequest")
        XCTAssertEqual(json?["url"] as? String, "https://example.com/webhook")
        XCTAssertEqual(json?["method"] as? String, "POST")
        XCTAssertEqual(json?["body"] as? String, "{\"action\": \"test\"}")

        let headers = json?["headers"] as? [String: String]
        XCTAssertEqual(headers?["Authorization"], "Bearer token123")
    }

    func testHTTPRequestCommand_Decoding() throws {
        // Given
        let json = """
        {
            "type": "httpRequest",
            "url": "https://example.com/api",
            "method": "PUT",
            "headers": {"X-API-Key": "secret"},
            "body": "{\\"data\\": 123}"
        }
        """

        // When
        let data = json.data(using: .utf8)!
        let command = try JSONDecoder().decode(SystemCommand.self, from: data)

        // Then
        if case .httpRequest(let url, let method, let headers, let body) = command {
            XCTAssertEqual(url, "https://example.com/api")
            XCTAssertEqual(method, .PUT)
            XCTAssertEqual(headers?["X-API-Key"], "secret")
            XCTAssertEqual(body, "{\"data\": 123}")
        } else {
            XCTFail("Expected httpRequest command")
        }
    }

    func testHTTPRequestCommand_DecodingWithDefaults() throws {
        // Given - minimal JSON with only required fields
        let json = """
        {
            "type": "httpRequest",
            "url": "https://example.com/webhook"
        }
        """

        // When
        let data = json.data(using: .utf8)!
        let command = try JSONDecoder().decode(SystemCommand.self, from: data)

        // Then - should use defaults
        if case .httpRequest(let url, let method, let headers, let body) = command {
            XCTAssertEqual(url, "https://example.com/webhook")
            XCTAssertEqual(method, .POST) // default
            XCTAssertNil(headers)
            XCTAssertNil(body)
        } else {
            XCTFail("Expected httpRequest command")
        }
    }

    func testHTTPRequestCommand_DisplayName() {
        // Given
        let shortURL = SystemCommand.httpRequest(url: "https://api.ex.com/h", method: .POST, headers: nil, body: nil)
        let longURL = SystemCommand.httpRequest(url: "https://very-long-domain-name.example.com/very/long/path/to/webhook", method: .POST, headers: nil, body: nil)

        // Then - "POST https://api.ex.com/h" is 22 chars, under 30 limit
        XCTAssertEqual(shortURL.displayName, "POST https://api.ex.com/h")
        XCTAssertTrue(longURL.displayName.count <= 33, "Display name should be truncated: \(longURL.displayName)")
        XCTAssertTrue(longURL.displayName.hasSuffix("..."), "Long display name should end with ...: \(longURL.displayName)")
    }

    func testHTTPRequestCommand_Category() {
        // Given
        let command = SystemCommand.httpRequest(url: "https://example.com", method: .POST, headers: nil, body: nil)

        // Then
        XCTAssertEqual(command.category, .webhook)
    }

    // MARK: - HTTPMethod Enum Tests

    func testHTTPMethod_AllCases() {
        let allMethods: [HTTPMethod] = [.GET, .POST, .PUT, .DELETE, .PATCH]
        XCTAssertEqual(HTTPMethod.allCases.count, 5)

        for method in allMethods {
            XCTAssertTrue(HTTPMethod.allCases.contains(method))
        }
    }

    func testHTTPMethod_RawValues() {
        XCTAssertEqual(HTTPMethod.GET.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.POST.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.PUT.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.DELETE.rawValue, "DELETE")
        XCTAssertEqual(HTTPMethod.PATCH.rawValue, "PATCH")
    }

    // MARK: - HTTP Request Execution Tests

    func testExecuteHTTPRequest_POST() throws {
        // Given
        setupMockResponse(statusCode: 201)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/webhook",
            method: .POST,
            headers: nil,
            body: "{\"test\": true}"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)

        let request = requests.first!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/webhook")
    }

    func testExecuteHTTPRequest_GET() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api/status",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "GET")
    }

    func testExecuteHTTPRequest_PUT() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api/resource",
            method: .PUT,
            headers: nil,
            body: "{\"update\": true}"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "PUT")
    }

    func testExecuteHTTPRequest_DELETE() throws {
        // Given
        setupMockResponse(statusCode: 204)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api/resource/123",
            method: .DELETE,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "DELETE")
    }

    func testExecuteHTTPRequest_PATCH() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api/resource",
            method: .PATCH,
            headers: nil,
            body: "{\"partial\": true}"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "PATCH")
    }

    // MARK: - Header Tests

    func testExecuteHTTPRequest_CustomHeaders() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: [
                "Authorization": "Bearer test-token-123",
                "X-API-Key": "secret-key",
                "X-Custom-Header": "custom-value"
            ],
            body: "{}"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)

        let request = requests.first!
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
    }

    func testExecuteHTTPRequest_DefaultContentType() throws {
        // Given - POST without explicit Content-Type should default to application/json
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: "{\"test\": true}"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testExecuteHTTPRequest_CustomContentTypeOverridesDefault() throws {
        // Given - Custom Content-Type should override default
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: ["Content-Type": "text/plain"],
            body: "plain text body"
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Content-Type"), "text/plain")
    }

    // MARK: - Body Tests

    func testExecuteHTTPRequest_JSONBody() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let jsonBody = "{\"key\": \"value\", \"number\": 42}"
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: jsonBody
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)

        guard let bodyData = requests.first?.httpBody else {
            XCTFail("Request body should not be nil")
            return
        }
        XCTAssertEqual(String(data: bodyData, encoding: .utf8), jsonBody)
    }

    func testExecuteHTTPRequest_EmptyBody() throws {
        // Given - GET request with no body
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests.first?.httpBody)
    }

    func testExecuteHTTPRequest_UnicodeBody() throws {
        // Given
        setupMockResponse(statusCode: 200)
        let unicodeBody = "{\"emoji\": \"🎮\", \"chinese\": \"你好\"}"
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: unicodeBody
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)

        guard let bodyData = requests.first?.httpBody else {
            XCTFail("Request body should not be nil")
            return
        }
        guard let receivedBody = String(data: bodyData, encoding: .utf8) else {
            XCTFail("Body should be valid UTF-8")
            return
        }
        XCTAssertTrue(receivedBody.contains("🎮"), "Body should contain emoji: \(receivedBody)")
        XCTAssertTrue(receivedBody.contains("你好"), "Body should contain Chinese: \(receivedBody)")
    }

    // MARK: - Security Tests

    func testExecuteHTTPRequest_BlocksFileURL() {
        // Given - file:// URL should be blocked
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "file:///etc/passwd",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then - no request should be made
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 0, "file:// URLs should be blocked")
    }

    func testExecuteHTTPRequest_BlocksFTPURL() {
        // Given - ftp:// URL should be blocked
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "ftp://ftp.example.com/file",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then - no request should be made
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 0, "ftp:// URLs should be blocked")
    }

    func testExecuteHTTPRequest_AllowsHTTP() {
        // Given - http:// should be allowed
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "http://example.com/api",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1, "http:// URLs should be allowed")
    }

    func testExecuteHTTPRequest_AllowsHTTPS() {
        // Given - https:// should be allowed
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1, "https:// URLs should be allowed")
    }

    // MARK: - Error Handling Tests

    func testExecuteHTTPRequest_InvalidURL() {
        // Given - malformed URL should fail gracefully
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "not a valid url %%%",
            method: .POST,
            headers: nil,
            body: nil
        )

        // When - should not crash
        executor.execute(command)
        waitForExecution()

        // Then - no request made (URL parsing failed)
        // Just verify no crash occurred
        XCTAssertTrue(true)
    }

    func testExecuteHTTPRequest_EmptyURL() {
        // Given - empty URL should fail gracefully
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "",
            method: .POST,
            headers: nil,
            body: nil
        )

        // When - should not crash
        executor.execute(command)
        waitForExecution()

        // Then
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 0, "Empty URL should not make a request")
    }

    func testExecuteHTTPRequest_URLWithSpaces() {
        // Given - URL with spaces should be percent-encoded
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api/path with spaces",
            method: .GET,
            headers: nil,
            body: nil
        )

        // When
        executor.execute(command)
        waitForExecution()

        // Then - request should be made with encoded URL
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1, "URL with spaces should be encoded and work")
    }

    // MARK: - Response Handling Tests

    func testExecuteHTTPRequest_HandlesErrorResponse() {
        // Given - server returns 500 error
        setupMockResponse(statusCode: 500)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: nil
        )

        // When - should not crash
        executor.execute(command)
        waitForExecution()

        // Then - request was made, error was handled gracefully
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testExecuteHTTPRequest_HandlesNetworkError() {
        // Given - network error
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        }

        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: nil
        )

        // When - should not crash
        executor.execute(command)
        waitForExecution()

        // Then - just verify no crash
        XCTAssertTrue(true)
    }

    // MARK: - Performance Tests

    func testExecuteHTTPRequest_RapidFire() {
        // Given - multiple rapid requests
        setupMockResponse(statusCode: 200)
        let requestCount = 10

        // When
        for i in 0..<requestCount {
            let command = SystemCommand.httpRequest(
                url: "https://example.com/api/\(i)",
                method: .POST,
                headers: nil,
                body: "{\"sequence\": \(i)}"
            )
            executor.execute(command)
        }

        waitForExecution(timeout: 2.0)

        // Then - all requests should be made
        let requests = MockURLProtocol.getCapturedRequests()
        XCTAssertEqual(requests.count, requestCount, "All rapid requests should be sent")
    }

    func testExecuteHTTPRequest_DoesNotBlockMainThread() {
        // Given
        setupMockResponse(statusCode: 200)
        let command = SystemCommand.httpRequest(
            url: "https://example.com/api",
            method: .POST,
            headers: nil,
            body: nil
        )

        // When
        let startTime = CFAbsoluteTimeGetCurrent()
        executor.execute(command)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Then - execute() should return immediately (< 10ms)
        XCTAssertLessThan(elapsed, 0.01, "execute() should return immediately without blocking")
    }
}
