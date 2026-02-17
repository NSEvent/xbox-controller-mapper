import Foundation
import AppKit

/// Executes system commands triggered by button or chord mappings
class SystemCommandExecutor: @unchecked Sendable {
    private let profileManager: ProfileManager
    private let urlSession: URLSession
    private let executionQueue = DispatchQueue(label: "com.controllerkeys.systemcommand", qos: .userInteractive)

    init(profileManager: ProfileManager, urlSession: URLSession = .shared) {
        self.profileManager = profileManager
        self.urlSession = urlSession
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
        }
    }

    // MARK: - App Launching

    private func launchApplication(bundleIdentifier: String, newWindow: Bool) {
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    if let error = error {
                        NSLog("[SystemCommand] Failed to launch app \(bundleIdentifier): \(error.localizedDescription)")
                        return
                    }
                    if newWindow {
                        // Send Cmd+N after a short delay to open a new window
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            let src = CGEventSource(stateID: .hidSystemState)
                            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: true) // kVK_ANSI_N
                            keyDown?.flags = .maskCommand
                            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: false)
                            keyUp?.flags = .maskCommand
                            keyDown?.post(tap: .cghidEventTap)
                            keyUp?.post(tap: .cghidEventTap)
                        }
                    }
                }
            } else {
                NSLog("[SystemCommand] App not found for bundle identifier: \(bundleIdentifier)")
            }
        }
    }

    // MARK: - Open Link

    private func openLink(_ urlString: String) {
        DispatchQueue.main.async {
            // Try to create URL, prepending https:// if no scheme is provided
            var resolved = urlString
            if !resolved.contains("://") {
                resolved = "https://" + resolved
            }
            if let url = URL(string: resolved) {
                NSWorkspace.shared.open(url)
            } else {
                NSLog("[SystemCommand] Invalid URL: \(urlString)")
            }
        }
    }

    // MARK: - Shell Command (Silent)

    private func executeSilently(_ command: String) {
        executionQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                NSLog("[SystemCommand] Shell command failed: \(error.localizedDescription)")
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

            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    NSLog("[SystemCommand] AppleScript error: \(error)")
                }
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

        executionQueue.async { [url = validURL, urlSession = self.urlSession] in
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

            // Set body if provided
            if let body = body, !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
            }

            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    NSLog("[SystemCommand] HTTP request failed: %@", error.localizedDescription)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    if statusCode >= 200 && statusCode < 300 {
                        NSLog("[SystemCommand] HTTP %@ %@ → %d OK", method.rawValue, urlString, statusCode)
                    } else {
                        NSLog("[SystemCommand] HTTP %@ %@ → %d", method.rawValue, urlString, statusCode)
                    }
                }
            }
            task.resume()
        }
    }
}
