import Foundation
import AppKit
import Combine

struct AppleTVRemoteMicBridgeCommand: Equatable {
    enum Runner: Equatable {
        case installedHelper(URL)
        case adminPython(scriptURL: URL, workingDirectoryURL: URL)
    }

    var runner: Runner
    var outputURL: URL
    var transcriptURL: URL
    var safetySeconds: Int
    var releaseGrace: Double
    var transcribe: Bool

    var shellCommand: String {
        var parts: [String]
        switch runner {
        case .installedHelper(let helperURL):
            parts = [
                Self.shellQuote(helperURL.path),
                "--release-grace",
                String(format: "%.2f", releaseGrace),
                "--seconds",
                "\(safetySeconds)",
                "-o",
                Self.shellQuote(outputURL.path),
                "--transcript",
                Self.shellQuote(transcriptURL.path)
            ]
        case .adminPython(let scriptURL, let workingDirectoryURL):
            parts = [
                "cd",
                Self.shellQuote(workingDirectoryURL.path),
                "&&",
                "/usr/bin/python3",
                Self.shellQuote(scriptURL.path),
                "--capture",
                "--enable-hid",
                "--stop-on-release",
                "--feed-coreaudio",
                "--release-grace",
                String(format: "%.2f", releaseGrace),
                "--seconds",
                "\(safetySeconds)",
                "--no-sudo",
                "-o",
                Self.shellQuote(outputURL.path),
                "--transcript",
                Self.shellQuote(transcriptURL.path)
            ]
        }
        if transcribe {
            parts.append("--transcribe")
        }
        return parts.joined(separator: " ")
    }

    var requiresAdministratorPrivileges: Bool {
        if case .adminPython = runner {
            return true
        }
        return false
    }

    var appleScript: String {
        "do shell script \(Self.appleScriptQuote(shellCommand)) with administrator privileges"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

struct AppleTVRemoteMicStreamCommand: Equatable {
    var runner: AppleTVRemoteMicBridgeCommand.Runner
    var safetySeconds: Int

    var shellCommand: String {
        var parts: [String]
        switch runner {
        case .installedHelper(let helperURL):
            parts = [
                AppleTVRemoteMicBridgeCommand.shellQuote(helperURL.path),
                "--stream-coreaudio",
                "--seconds",
                "\(safetySeconds)"
            ]
        case .adminPython(let scriptURL, let workingDirectoryURL):
            parts = [
                "cd",
                AppleTVRemoteMicBridgeCommand.shellQuote(workingDirectoryURL.path),
                "&&",
                "/usr/bin/python3",
                AppleTVRemoteMicBridgeCommand.shellQuote(scriptURL.path),
                "--capture",
                "--enable-hid",
                "--feed-coreaudio",
                "--coreaudio-only",
                "--seconds",
                "\(safetySeconds)",
                "--no-sudo"
            ]
        }
        return parts.joined(separator: " ")
    }

    var requiresAdministratorPrivileges: Bool {
        if case .adminPython = runner {
            return true
        }
        return false
    }

    var appleScript: String {
        "do shell script \(AppleTVRemoteMicBridgeCommand.appleScriptQuote(shellCommand)) with administrator privileges"
    }
}

@MainActor
final class AppleTVRemoteMicBridge: ObservableObject {
    enum State: String {
        case idle
        case starting
        case capturing
        case finished
        case failed

        var displayName: String {
            switch self {
            case .idle: return "Idle"
            case .starting: return "Starting"
            case .capturing: return "Capturing"
            case .finished: return "Finished"
            case .failed: return "Failed"
            }
        }
    }

    static let enabledDefaultsKey = "appleTVRemoteMicBridgeEnabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                startCoreAudioStream()
            } else {
                stop()
                stopCoreAudioStream()
            }
        }
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var lastStatus = "Remote mic bridge idle"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastWavPath: String?
    @Published private(set) var lastTranscriptPath: String?
    @Published private(set) var lastRawOutput = ""
    @Published private(set) var lastError = ""
    @Published private(set) var lastRunDate: Date?
    @Published private(set) var isCoreAudioStreamRunning = false

    var safetySeconds: Int = 20
    var streamSafetySeconds: Int = 86_400
    var releaseGrace: Double = 0.20

    private static let installedCaptureHelperPath = "/Library/Application Support/ControllerKeys/RemoteMicBridge/controllerkeys-remote-mic-capture"
    private static let installedDriverPath = "/Library/Audio/Plug-Ins/HAL/ControllerKeysRemoteMic.driver"

    private let fileManager: FileManager
    private var process: Process?
    private var streamProcess: Process?
    private var isStoppingCoreAudioStream = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        if isEnabled {
            Task { @MainActor [weak self] in
                self?.startCoreAudioStream()
            }
        }
    }

    var isRunning: Bool {
        state == .starting || state == .capturing
    }

    func startPushToTalkCapture() {
        guard isEnabled else {
            lastError = "Enable the remote mic bridge first."
            state = .failed
            return
        }
        startCoreAudioStream()
        guard !isRunning else { return }

        guard let command = makeCommand() else {
            state = .failed
            return
        }

        let process = Process()
        if command.requiresAdministratorPrivileges {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", command.appleScript]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-lc", command.shellCommand]
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        state = .starting
        lastStatus = command.requiresAdministratorPrivileges ? "Requesting administrator access" : "Starting installed capture helper"
        lastError = ""
        lastRawOutput = ""
        lastTranscript = ""
        lastWavPath = command.outputURL.path
        lastTranscriptPath = command.transcriptURL.path
        self.process = process

        process.terminationHandler = { [weak self] process in
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                self?.handleTermination(
                    process: process,
                    stdout: stdout,
                    stderr: stderr,
                    command: command
                )
            }
        }

        do {
            try process.run()
            state = .capturing
            lastStatus = "Hold Siri to feed remote audio"
        } catch {
            self.process = nil
            state = .failed
            lastStatus = "Failed to start bridge"
            lastError = error.localizedDescription
        }
    }

    func handleSiriButtonChanged(isPressed: Bool) {
        guard isPressed, isEnabled else { return }
        startCoreAudioStream()
        startPushToTalkCapture()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        lastStatus = "Stopping bridge"
    }

    func startCoreAudioStream() {
        guard isEnabled else { return }
        guard streamProcess?.isRunning != true else {
            isCoreAudioStreamRunning = true
            return
        }
        guard let command = makeStreamCommand() else { return }

        let process = Process()
        if command.requiresAdministratorPrivileges {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", command.appleScript]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-lc", command.shellCommand]
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        isStoppingCoreAudioStream = false
        streamProcess = process

        process.terminationHandler = { [weak self] process in
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                guard let self, self.streamProcess === process else { return }
                self.streamProcess = nil
                self.isCoreAudioStreamRunning = false
                let shouldRestart = self.isEnabled && !self.isStoppingCoreAudioStream
                self.isStoppingCoreAudioStream = false
                if process.terminationStatus != 0, shouldRestart {
                    self.lastError = stderr.isEmpty ? stdout : stderr
                }
                if shouldRestart {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard let self, self.isEnabled, self.streamProcess == nil else { return }
                        self.startCoreAudioStream()
                    }
                }
            }
        }

        do {
            try process.run()
            isCoreAudioStreamRunning = true
        } catch {
            streamProcess = nil
            isCoreAudioStreamRunning = false
            lastError = "Could not start virtual mic stream: \(error.localizedDescription)"
        }
    }

    func stopCoreAudioStream() {
        guard let streamProcess else {
            isCoreAudioStreamRunning = false
            isStoppingCoreAudioStream = false
            return
        }
        isStoppingCoreAudioStream = true
        if streamProcess.isRunning {
            streamProcess.terminate()
        }
        self.streamProcess = nil
        isCoreAudioStreamRunning = false
    }

    func revealLastWavInFinder() {
        guard let lastWavPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastWavPath)])
    }

    var isCaptureHelperInstalled: Bool {
        fileManager.isExecutableFile(atPath: Self.installedCaptureHelperPath)
    }

    var isVirtualMicDriverInstalled: Bool {
        fileManager.fileExists(atPath: Self.installedDriverPath)
    }

    func makeCommand(now: Date = Date()) -> AppleTVRemoteMicBridgeCommand? {
        let outputDirectory = remoteMicOutputDirectory()
        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            lastError = "Could not create output directory: \(error.localizedDescription)"
            return nil
        }

        let runner: AppleTVRemoteMicBridgeCommand.Runner
        if let helperURL = locateInstalledCaptureHelper() {
            runner = .installedHelper(helperURL)
        } else if let scriptURL = locateBridgeScript() {
            runner = .adminPython(
                scriptURL: scriptURL,
                workingDirectoryURL: scriptURL.deletingLastPathComponent().deletingLastPathComponent()
            )
        } else {
            lastError = "Missing remote mic capture helper and apple-tv-remote-packetlogger-live.py. Run make install-remote-mic-components BUILD_FROM_SOURCE=1."
            return nil
        }

        let stamp = Self.timestampFormatter.string(from: now)
        return AppleTVRemoteMicBridgeCommand(
            runner: runner,
            outputURL: outputDirectory.appendingPathComponent("siri-remote-\(stamp).wav"),
            transcriptURL: outputDirectory.appendingPathComponent("siri-remote-\(stamp).txt"),
            safetySeconds: safetySeconds,
            releaseGrace: releaseGrace,
            transcribe: true
        )
    }

    func makeStreamCommand() -> AppleTVRemoteMicStreamCommand? {
        let runner: AppleTVRemoteMicBridgeCommand.Runner
        if let helperURL = locateInstalledCaptureHelper() {
            runner = .installedHelper(helperURL)
        } else if let scriptURL = locateBridgeScript() {
            runner = .adminPython(
                scriptURL: scriptURL,
                workingDirectoryURL: scriptURL.deletingLastPathComponent().deletingLastPathComponent()
            )
        } else {
            lastError = "Missing remote mic capture helper and apple-tv-remote-packetlogger-live.py. Run make install-remote-mic-components BUILD_FROM_SOURCE=1."
            return nil
        }

        return AppleTVRemoteMicStreamCommand(
            runner: runner,
            safetySeconds: streamSafetySeconds
        )
    }

    private func handleTermination(
        process: Process,
        stdout: String,
        stderr: String,
        command: AppleTVRemoteMicBridgeCommand
    ) {
        self.process = nil
        lastRunDate = Date()
        lastRawOutput = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        if let transcript = try? String(contentsOf: command.transcriptURL, encoding: .utf8) {
            lastTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if process.terminationStatus == 0 {
            state = .finished
            lastStatus = lastTranscript.isEmpty ? "Capture finished" : "Capture transcribed"
            lastError = ""
        } else {
            state = .failed
            lastStatus = "Bridge failed"
            lastError = stderr.isEmpty ? stdout : stderr
        }
    }

    private func locateBridgeScript() -> URL? {
        let scriptName = "apple-tv-remote-packetlogger-live.py"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/\(scriptName)"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Scripts/\(scriptName)"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("projects/xbox-controller-mapper/Scripts/\(scriptName)")
        ].compactMap { $0 }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) || fileManager.fileExists(atPath: $0.path) }
    }

    private func locateInstalledCaptureHelper() -> URL? {
        let url = URL(fileURLWithPath: Self.installedCaptureHelperPath)
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func remoteMicOutputDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ControllerKeys/RemoteMic", isDirectory: true)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
