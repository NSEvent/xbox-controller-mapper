import Foundation
import AppKit

/// Executes system commands triggered by button or chord mappings
class SystemCommandExecutor: @unchecked Sendable {
    typealias OBSClientFactory = (URL, String?) -> OBSWebSocketClientProtocol
    typealias AppURLResolver = (String) -> URL?
    typealias AppOpener = (URL, NSWorkspace.OpenConfiguration, @escaping (NSRunningApplication?, Error?) -> Void) -> Void
    typealias URLOpener = (URL) -> Void
    typealias AppleScriptRunner = (String) -> NSDictionary?
    typealias NewWindowShortcutSender = () -> Void

    private let profileManager: ProfileManager
    private let urlSession: URLSession
    private let obsClientFactory: OBSClientFactory
    private let appURLResolver: AppURLResolver
    private let appOpener: AppOpener
    private let urlOpener: URLOpener
    private let appleScriptRunner: AppleScriptRunner
    private let newWindowShortcutSender: NewWindowShortcutSender
    private let executionQueue = DispatchQueue(label: "com.controllerkeys.systemcommand", qos: .userInteractive)

    /// Callback for webhook feedback (success: Bool, displayMessage: String)
    /// Called on completion of HTTP requests to provide user feedback
    var webhookFeedbackHandler: ((Bool, String) -> Void)?

    init(
        profileManager: ProfileManager,
        urlSession: URLSession = .shared,
        obsClientFactory: @escaping OBSClientFactory = { url, password in
            OBSWebSocketClient(url: url, password: password)
        },
        appURLResolver: @escaping AppURLResolver = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        appOpener: @escaping AppOpener = { url, config, completion in
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
        },
        urlOpener: @escaping URLOpener = { url in
            NSWorkspace.shared.open(url)
        },
        appleScriptRunner: @escaping AppleScriptRunner = { script in
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            return error
        },
        newWindowShortcutSender: @escaping NewWindowShortcutSender = {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: true) // kVK_ANSI_N
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    ) {
        self.profileManager = profileManager
        self.urlSession = urlSession
        self.obsClientFactory = obsClientFactory
        self.appURLResolver = appURLResolver
        self.appOpener = appOpener
        self.urlOpener = urlOpener
        self.appleScriptRunner = appleScriptRunner
        self.newWindowShortcutSender = newWindowShortcutSender
    }

    func execute(_ command: SystemCommand) {
        switch command {
        case .launchApp(let bundleIdentifier, let newWindow):
            launchApplication(bundleIdentifier: bundleIdentifier, newWindow: newWindow)

        case .shellCommand(let command, let inTerminal):
            if inTerminal {
                executeInTerminal(command)
            } else {
                executeSilently(command)
            }

        case .openLink(let urlString):
            openLink(urlString)

        case .httpRequest(let url, let method, let headers, let body):
            executeHTTPRequest(url: url, method: method, headers: headers, body: body)

        case .obsWebSocket(let url, let password, let requestType, let requestData):
            executeOBSWebSocket(url: url, password: password, requestType: requestType, requestData: requestData)
        }
    }

    // MARK: - App Launching

    private func launchApplication(bundleIdentifier: String, newWindow: Bool) {
        DispatchQueue.main.async {
            if let url = self.appURLResolver(bundleIdentifier) {
                let config = NSWorkspace.OpenConfiguration()
                self.appOpener(url, config) { _, error in
                    if let error = error {
                        NSLog("[SystemCommand] Failed to launch app \(bundleIdentifier): \(error.localizedDescription)")
                        return
                    }
                    if newWindow {
                        // Send Cmd+N after a short delay to open a new window
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.newWindowShortcutSender()
                        }
                    }
                }
            } else {
                NSLog("[SystemCommand] App not found for bundle identifier: \(bundleIdentifier)")
            }
        }
    }

    // MARK: - Open Link

    /// Allowed URL schemes for openLink. Only http and https are permitted.
    private static let allowedLinkSchemes: Set<String> = ["http", "https"]

    private func openLink(_ urlString: String) {
        DispatchQueue.main.async {
            // Try to create URL, prepending https:// if no scheme is provided
            var resolved = urlString
            if !resolved.contains("://") {
                resolved = "https://" + resolved
            }
            guard let url = URL(string: resolved) else {
                NSLog("[SystemCommand] Invalid URL: %@", urlString)
                return
            }

            // Security: Only allow http/https schemes
            guard let scheme = url.scheme?.lowercased(), Self.allowedLinkSchemes.contains(scheme) else {
                NSLog("[SystemCommand] Blocked non-HTTP URL scheme in openLink: %@", urlString)
                return
            }

            self.urlOpener(url)
        }
    }

    // MARK: - Shell Command (Silent)

    /// Patterns that indicate potentially dangerous shell command injection.
    /// These are blocked to prevent config-based attacks where a malicious config
    /// could exfiltrate data or download/execute arbitrary code.
    private static let dangerousShellPatterns: [String] = [
        "`",           // backtick command substitution
        "$(",          // $() command substitution
        "| sh",        // pipe to shell
        "| bash",      // pipe to bash
        "| zsh",       // pipe to zsh
        "|sh",         // pipe to shell (no space)
        "|bash",       // pipe to bash (no space)
        "|zsh",        // pipe to zsh (no space)
        "| /bin/sh",   // pipe to absolute shell path
        "| /bin/bash", // pipe to absolute bash path
        "| /bin/zsh",  // pipe to absolute zsh path
        "| /usr/bin/sh",   // pipe to /usr/bin shell path
        "| /usr/bin/bash", // pipe to /usr/bin bash path
        "| /usr/bin/zsh",  // pipe to /usr/bin zsh path
        "| perl",      // pipe to perl interpreter
        "|perl",       // pipe to perl (no space)
        "| python",    // pipe to python interpreter
        "|python",     // pipe to python (no space)
        "| ruby",      // pipe to ruby interpreter
        "|ruby",       // pipe to ruby (no space)
        "; curl ",     // chained curl (data exfiltration)
        "; wget ",     // chained wget
        "&& curl ",    // conditional curl
        "&& wget ",    // conditional wget
        "|| curl ",    // fallback curl
        "|| wget ",    // fallback wget
        "; /usr/bin/curl ",  // chained absolute curl path
        "; /usr/bin/wget ",  // chained absolute wget path
        "&& /usr/bin/curl ", // conditional absolute curl path
        "&& /usr/bin/wget ", // conditional absolute wget path
    ]

    private func executeSilently(_ command: String) {
        // Validate: reject empty commands
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSLog("[SystemCommand] Shell command rejected: empty command")
            return
        }

        // Validate: reject commands containing dangerous injection patterns
        let lowercased = trimmed.lowercased()
        for pattern in Self.dangerousShellPatterns {
            if lowercased.contains(pattern) {
                NSLog("[SystemCommand] Shell command rejected — dangerous pattern detected: %@", command)
                return
            }
        }

        NSLog("[SystemCommand] Executing shell command: %@", command)

        executionQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice

            // Capture stderr for logging instead of silencing it
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()

                // Read stderr pipe BEFORE waitUntilExit to avoid deadlock when
                // stderr output exceeds the pipe buffer size (~64KB).
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if !stderrData.isEmpty, let stderrString = String(data: stderrData, encoding: .utf8) {
                    NSLog("[SystemCommand] Shell stderr: %@", stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                let status = process.terminationStatus
                if status != 0 {
                    NSLog("[SystemCommand] Shell command exited with status %d: %@", status, command)
                }
            } catch {
                NSLog("[SystemCommand] Shell command failed to launch: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Shell Command (Terminal)

    private func executeInTerminal(_ command: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let terminalApp = self.profileManager.onScreenKeyboardSettings.defaultTerminalApp

            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let script: String
            switch terminalApp {
            case "iTerm":
                script = """
                tell application "iTerm"
                    activate
                    create window with default profile
                    delay 0.3
                    tell current session of current window
                        write text "\(escapedCommand)"
                    end tell
                end tell
                """

            case "Warp":
                script = """
                tell application "Warp"
                    activate
                    delay 0.5
                    tell application "System Events"
                        tell process "Warp"
                            keystroke "t" using command down
                            delay 0.3
                            keystroke "\(escapedCommand)"
                            delay 0.1
                            keystroke return
                        end tell
                    end tell
                end tell
                """

            case "Alacritty", "Kitty", "Hyper":
                script = """
                tell application "\(terminalApp)"
                    activate
                    delay 0.5
                    tell application "System Events"
                        tell process "\(terminalApp)"
                            keystroke "n" using command down
                            delay 0.3
                            keystroke "\(escapedCommand)"
                            delay 0.1
                            keystroke return
                        end tell
                    end tell
                end tell
                """

            default: // Terminal.app
                script = """
                tell application "Terminal"
                    activate
                    delay 0.2
                    do script "\(escapedCommand)"
                end tell
                """
            }

            if let error = self.appleScriptRunner(script) {
                NSLog("[SystemCommand] AppleScript error: \(error)")
            }
        }
    }

    // MARK: - HTTP Request / Webhook

    private func executeHTTPRequest(url urlString: String, method: HTTPMethod, headers: [String: String]?, body: String?) {
        // Attempt to create URL, with percent-encoding fallback for special characters
        var url = URL(string: urlString)
        if url == nil, let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            url = URL(string: encoded)
        }

        guard let validURL = url else {
            NSLog("[SystemCommand] Invalid URL for HTTP request: %@", urlString)
            return
        }

        // Security: Only allow http/https schemes to prevent file:// access
        guard let scheme = validURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            NSLog("[SystemCommand] Blocked non-HTTP URL scheme: %@", urlString)
            return
        }

        executionQueue.async { [url = validURL, urlSession = self.urlSession, feedbackHandler = self.webhookFeedbackHandler] in
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.timeoutInterval = 10

            // Set default Content-Type for methods that typically have a body
            if [.POST, .PUT, .PATCH].contains(method) {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            // Apply custom headers (can override Content-Type if specified)
            if let headers = headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            // Set body if provided (only for methods that support a body)
            if [.POST, .PUT, .PATCH].contains(method), let body = body, !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
            }

            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    NSLog("[SystemCommand] HTTP request failed: %@", error.localizedDescription)
                    feedbackHandler?(false, "Webhook Error")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    if statusCode >= 200 && statusCode < 300 {
                        NSLog("[SystemCommand] HTTP %@ %@ → %d OK", method.rawValue, urlString, statusCode)
                        feedbackHandler?(true, "Webhook \(statusCode)")
                    } else {
                        NSLog("[SystemCommand] HTTP %@ %@ → %d", method.rawValue, urlString, statusCode)
                        feedbackHandler?(false, "Webhook \(statusCode)")
                    }
                }
            }
            task.resume()
        }
    }

    // MARK: - OBS WebSocket

    private func executeOBSWebSocket(url urlString: String, password: String?, requestType: String, requestData: String?) {
        guard let validURL = URL(string: urlString) else {
            NSLog("[SystemCommand] Invalid OBS WebSocket URL: %@", urlString)
            return
        }

        guard let scheme = validURL.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
            NSLog("[SystemCommand] Blocked non-WebSocket OBS URL scheme: %@", urlString)
            return
        }

        let trimmedRequestType = requestType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequestType.isEmpty else {
            NSLog("[SystemCommand] OBS requestType is required")
            return
        }

        let normalizedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPassword = (normalizedPassword?.isEmpty == false) ? normalizedPassword : nil
        let finalRequestData = requestData?.trimmingCharacters(in: .whitespacesAndNewlines)

        executionQueue.async { [url = validURL, clientFactory = self.obsClientFactory, feedbackHandler = self.webhookFeedbackHandler] in
            Task {
                do {
                    let client = clientFactory(url, finalPassword)
                    let result = try await client.executeRequest(
                        requestType: trimmedRequestType,
                        requestDataJSON: finalRequestData,
                        timeout: 5
                    )
                    NSLog("[SystemCommand] OBS %@ %@ → %d", trimmedRequestType, urlString, result.code)
                    feedbackHandler?(true, "OBS \(result.code)")
                } catch {
                    NSLog("[SystemCommand] OBS request failed: %@", error.localizedDescription)
                    feedbackHandler?(false, "OBS Error")
                }
            }
        }
    }
}
