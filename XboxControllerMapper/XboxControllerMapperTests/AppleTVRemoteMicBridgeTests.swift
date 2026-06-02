import XCTest
@testable import ControllerKeys

final class AppleTVRemoteMicBridgeTests: XCTestCase {
    func testCommandIncludesRequiredRemoteMicFlags() {
        let command = AppleTVRemoteMicBridgeCommand(
            runner: .adminPython(
                scriptURL: URL(fileURLWithPath: "/tmp/Project Scripts/apple-tv-remote-packetlogger-live.py"),
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/Project Scripts")
            ),
            outputURL: URL(fileURLWithPath: "/tmp/Remote Mic/out.wav"),
            transcriptURL: URL(fileURLWithPath: "/tmp/Remote Mic/out.txt"),
            safetySeconds: 20,
            releaseGrace: 0.2,
            transcribe: true
        )

        XCTAssertTrue(command.shellCommand.contains("--capture"))
        XCTAssertTrue(command.shellCommand.contains("--enable-hid"))
        XCTAssertTrue(command.shellCommand.contains("--stop-on-release"))
        XCTAssertTrue(command.shellCommand.contains("--feed-coreaudio"))
        XCTAssertTrue(command.shellCommand.contains("--release-grace 0.20"))
        XCTAssertTrue(command.shellCommand.contains("--seconds 20"))
        XCTAssertTrue(command.shellCommand.contains("--no-sudo"))
        XCTAssertTrue(command.shellCommand.contains("--transcribe"))
        XCTAssertTrue(command.shellCommand.contains("'/tmp/Remote Mic/out.wav'"))
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(
            AppleTVRemoteMicBridgeCommand.shellQuote("/tmp/Kevin's Remote/out.wav"),
            "'/tmp/Kevin'\\''s Remote/out.wav'"
        )
    }

    func testAppleScriptWrapsShellCommandWithAdministratorPrivileges() {
        let command = AppleTVRemoteMicBridgeCommand(
            runner: .adminPython(
                scriptURL: URL(fileURLWithPath: "/tmp/script.py"),
                workingDirectoryURL: URL(fileURLWithPath: "/tmp")
            ),
            outputURL: URL(fileURLWithPath: "/tmp/out.wav"),
            transcriptURL: URL(fileURLWithPath: "/tmp/out.txt"),
            safetySeconds: 10,
            releaseGrace: 0.35,
            transcribe: false
        )

        XCTAssertTrue(command.appleScript.hasPrefix("do shell script \""))
        XCTAssertTrue(command.appleScript.hasSuffix("\" with administrator privileges"))
        XCTAssertFalse(command.shellCommand.contains("--transcribe"))
    }

    func testInstalledHelperCommandDoesNotRequireAdministratorPrivileges() {
        let command = AppleTVRemoteMicBridgeCommand(
            runner: .installedHelper(URL(fileURLWithPath: "/Library/Application Support/ControllerKeys/RemoteMicBridge/controllerkeys-remote-mic-capture")),
            outputURL: URL(fileURLWithPath: "/tmp/Remote Mic/out.wav"),
            transcriptURL: URL(fileURLWithPath: "/tmp/Remote Mic/out.txt"),
            safetySeconds: 20,
            releaseGrace: 0.2,
            transcribe: true
        )

        XCTAssertFalse(command.requiresAdministratorPrivileges)
        XCTAssertFalse(command.shellCommand.contains("--capture"))
        XCTAssertTrue(command.shellCommand.contains("controllerkeys-remote-mic-capture'"))
        XCTAssertTrue(command.shellCommand.contains("--release-grace 0.20"))
        XCTAssertTrue(command.shellCommand.contains("--transcribe"))
    }
}
