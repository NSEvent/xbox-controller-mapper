import XCTest
@testable import ControllerKeys

/// Tests for security hardening of SystemCommandExecutor:
/// - URL scheme validation in openLink()
/// - Shell command execution behavior in executeSilently()
///
/// Marker-file tests assert whether commands actually ran. Shell commands are
/// executed as explicit user configuration; external-profile safety is handled at
/// import/review boundaries, not by a brittle shell syntax blocklist.
@MainActor
final class SystemCommandExecutorSecurityTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!
    private var openedURLs: [URL] = []
    private var executor: SystemCommandExecutor!

    private static let markerPollInterval: UInt64 = 20_000_000 // 20ms

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-security-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
        openedURLs = []

        executor = SystemCommandExecutor(
            profileManager: profileManager,
            appURLResolver: { _ in nil },
            appOpener: { _, _, completion in completion(nil, nil) },
            urlOpener: { [weak self] url in
                self?.openedURLs.append(url)
            },
            appleScriptRunner: { _ in nil },
            newWindowShortcutSender: {}
        )
    }

    override func tearDown() async throws {
        executor = nil
        profileManager = nil
        testConfigDirectory = nil
        try await super.tearDown()
    }

    /// Create a unique marker file path for this test
    private func markerPath() -> String {
        "/tmp/controllerkeys-test-\(UUID().uuidString)"
    }

    private func waitForMarkerFile(
        atPath path: String,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            try? await Task.sleep(nanoseconds: Self.markerPollInterval)
        }

        XCTFail("Timed out waiting for marker file: \(path)", file: file, line: line)
    }

    private func waitForMarkerContents(
        atPath path: String,
        expected expectedContents: String,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8),
               contents == expectedContents {
                return
            }
            try? await Task.sleep(nanoseconds: Self.markerPollInterval)
        }

        let actualContents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "<missing>"
        XCTFail(
            "Timed out waiting for marker file \(path) to contain \(expectedContents); found \(actualContents)",
            file: file,
            line: line
        )
    }

    // MARK: - openLink URL Scheme Validation

    func testOpenLink_AllowsHTTPS() async {
        executor.execute(.openLink(url: "https://example.com"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "https://example.com")
    }

    func testOpenLink_AllowsHTTP() async {
        executor.execute(.openLink(url: "http://example.com"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "http://example.com")
    }

    func testOpenLink_PrependsHTTPSWhenNoScheme() async {
        executor.execute(.openLink(url: "example.com"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "https://example.com")
    }

    func testOpenLink_BlocksFileScheme() async {
        executor.execute(.openLink(url: "file:///etc/passwd"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "file:// URLs must be blocked by openLink")
    }

    func testOpenLink_BlocksFTPScheme() async {
        executor.execute(.openLink(url: "ftp://ftp.example.com/file"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "ftp:// URLs must be blocked by openLink")
    }

    func testOpenLink_BlocksTelScheme() async {
        executor.execute(.openLink(url: "tel:+15551234567"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "tel: URLs must be blocked by openLink")
    }

    func testOpenLink_BlocksJavascriptScheme() async {
        executor.execute(.openLink(url: "javascript:alert(1)"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "javascript: URLs must be blocked by openLink")
    }

    func testOpenLink_BlocksDataScheme() async {
        executor.execute(.openLink(url: "data:text/html,<h1>test</h1>"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "data: URLs must be blocked by openLink")
    }

    func testOpenLink_BlocksSSHScheme() async {
        executor.execute(.openLink(url: "ssh://user@host"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "ssh: URLs must be blocked by openLink")
    }

    func testOpenLink_CaseInsensitiveSchemeCheck() async {
        // HTTP in uppercase should still be allowed
        executor.execute(.openLink(url: "HTTP://example.com"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(openedURLs.count, 1, "HTTP (uppercase) should be allowed")
    }

    func testOpenLink_CaseInsensitiveSchemeBlocksMixedCaseFTP() async {
        executor.execute(.openLink(url: "FtP://ftp.example.com"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "FtP:// (mixed case) must be blocked")
    }

    func testOpenLink_InvalidURLDoesNotOpen() async {
        executor.execute(.openLink(url: "http://[::1"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(openedURLs.isEmpty, "Invalid URL should not trigger opener")
    }

    // MARK: - executeSilently: Safe Commands Execute (marker file IS created)

    func testShellCommand_SafeCommandExecutes() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_StderrIsCaptured() async {
        // Run a command that writes to stderr and also creates a marker file.
        // Since stderr is piped (not /dev/null), the process should complete without hanging.
        let marker = markerPath()
        executor.execute(.shellCommand(command: "echo 'error output' >&2 && touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_NonZeroExitDoesNotCrash() async {
        // /usr/bin/false always exits with status 1 — should not crash executor
        let marker = markerPath()
        executor.execute(.shellCommand(command: "/usr/bin/false", inTerminal: false))
        // Follow up with a safe command to verify executor is still functional
        executor.execute(.shellCommand(command: "touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    // MARK: - executeSilently: Explicit User Commands Execute

    func testShellCommand_RejectsEmptyCommand() async {
        // Empty command is rejected before Process.run(), so nothing executes
        executor.execute(.shellCommand(command: "", inTerminal: false))
        try? await Task.sleep(nanoseconds: 100_000_000)
        // No marker to check — empty command can't create one. Verify no crash.
    }

    func testShellCommand_RejectsWhitespaceOnlyCommand() async {
        executor.execute(.shellCommand(command: "   \n\t  ", inTerminal: false))
        try? await Task.sleep(nanoseconds: 100_000_000)
        // No marker to check — whitespace command can't create one. Verify no crash.
    }

    func testShellCommand_AllowsCommandSubstitutionWhenUserConfigured() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "value=$(printf ok); test \"$value\" = ok && touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_AllowsPipelinesWhenUserConfigured() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "printf ok | cat > \(marker)", inTerminal: false))

        await waitForMarkerContents(atPath: marker, expected: "ok")
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_AllowsShellVariablesWhenUserConfigured() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "CK_MARKER=\(marker); touch \"$CK_MARKER\"", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    // MARK: - executeSilently: Simple Commands

    func testShellCommand_AllowsSimpleEchoCommand() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "echo hello && touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_AllowsPathWithoutDangerousPatterns() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker)", inTerminal: false))

        await waitForMarkerFile(atPath: marker)
        try? FileManager.default.removeItem(atPath: marker)
    }
}
