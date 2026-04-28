import Foundation

// MARK: - Xbox Elite Series 2 Helper Process
//
// Launches a standalone helper binary that monitors the Elite Series 2 controller
// via IOKit HID without the GameController framework. This bypasses gamecontrollerd's
// exclusive access to the Elite 2's BLE HID device.
//
// The helper outputs JSON lines to stdout for Guide button and paddle state changes.

@MainActor
extension ControllerService {

    func startEliteHelper() {
        // Don't start if already running
        guard eliteHelperProcess == nil else { return }

        let helperPath = Bundle.main.bundlePath + "/Contents/Helpers/XboxEliteHelper"

        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            guideLog("Elite helper not found at \(helperPath)")
            return
        }

        guideLog("Starting Elite helper process")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)

        let pipe = Pipe()
        process.standardOutput = pipe

        // Read stdout on a background queue
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — process terminated. Clear the handler to stop repeated calls.
                handle.readabilityHandler = nil
                DispatchQueue.main.async { [weak self] in
                    self?.eliteHelperProcess = nil
                    guideLog("Elite helper process terminated (EOF)")
                }
                return
            }

            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    self?.handleEliteHelperLine(String(line))
                }
            }
        }

        process.terminationHandler = { _ in
            fileHandle.readabilityHandler = nil
        }

        do {
            try process.run()
            eliteHelperProcess = process
            guideLog("Elite helper process started (pid \(process.processIdentifier))")
        } catch {
            guideLog("Failed to start Elite helper: \(error)")
        }
    }

    func stopEliteHelper() {
        guard let process = eliteHelperProcess, process.isRunning else {
            eliteHelperProcess = nil
            return
        }
        guideLog("Stopping Elite helper process")
        process.terminate()
        eliteHelperProcess = nil
    }

    private nonisolated func handleEliteHelperLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            guideLog("Elite helper: ready")

        case "connected":
            let pid = json["pid"] as? Int ?? 0
            guideLog("Elite helper: controller connected (PID=0x\(String(pid, radix: 16)))")

        case "guide":
            if let pressed = json["pressed"] as? Bool {
                guideLog("Elite helper: Guide \(pressed ? "PRESSED" : "RELEASED")")
                controllerQueue.async { [weak self] in
                    self?.handleButton(.xbox, pressed: pressed)
                }
            }

        case "paddle":
            if let index = json["index"] as? Int, let pressed = json["pressed"] as? Bool {
                let button: ControllerButton
                switch index {
                case 1: button = .xboxPaddle1
                case 2: button = .xboxPaddle2
                case 3: button = .xboxPaddle3
                case 4: button = .xboxPaddle4
                default: return
                }
                guideLog("Elite helper: Paddle \(index) \(pressed ? "PRESSED" : "RELEASED")")
                controllerQueue.async { [weak self] in
                    self?.handleButton(button, pressed: pressed)
                }
            }

        default:
            break
        }
    }
}
