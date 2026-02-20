import Foundation
import CoreGraphics

// MARK: - Parsed Types

struct StreamDeckManifest {
    let name: String
    let actions: [StreamDeckAction]
}

struct StreamDeckAction: Identifiable {
    let id = UUID()
    let position: String
    let name: String
    let title: String?
    let settings: StreamDeckActionSettings
}

enum StreamDeckActionSettings: Equatable {
    case hotkey(CGKeyCode?, ModifierFlags)
    case openApp(path: String)
    case website(url: String)
    case multiAction([StreamDeckAction])
    case text(String)
    case unsupported(pluginUUID: String)

    static func == (lhs: StreamDeckActionSettings, rhs: StreamDeckActionSettings) -> Bool {
        switch (lhs, rhs) {
        case let (.hotkey(lk, lm), .hotkey(rk, rm)):
            return lk == rk && lm == rm
        case let (.openApp(lp), .openApp(rp)):
            return lp == rp
        case let (.website(lu), .website(ru)):
            return lu == ru
        case let (.text(lt), .text(rt)):
            return lt == rt
        case let (.unsupported(lu), .unsupported(ru)):
            return lu == ru
        case let (.multiAction(la), .multiAction(ra)):
            guard la.count == ra.count else { return false }
            return zip(la, ra).allSatisfy { $0.settings == $1.settings }
        default:
            return false
        }
    }
}

// MARK: - Parser Errors

enum StreamDeckParseError: LocalizedError {
    case fileNotFound
    case manifestNotFound
    case invalidManifest
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file could not be found."
        case .manifestNotFound:
            return "No manifest.json found in the Stream Deck profile."
        case .invalidManifest:
            return "The manifest.json file could not be parsed."
        case .extractionFailed(let reason):
            return "Failed to extract profile: \(reason)"
        }
    }
}

// MARK: - Parser

enum StreamDeckProfileParser {

    /// Parse a `.streamDeckProfile` file at the given URL.
    static func parse(fileURL: URL) throws -> StreamDeckManifest {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let manifestData = try loadManifestData(from: fileURL)
        return try parseManifestData(manifestData)
    }

    /// Parse manifest JSON data directly (useful for testing).
    static func parseManifestData(_ data: Data) throws -> StreamDeckManifest {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamDeckParseError.invalidManifest
        }

        let name = json["Name"] as? String ?? "Stream Deck Profile"

        // V2 format wraps Actions inside Controllers array
        let actionsDict: [String: Any]
        if let controllers = json["Controllers"] as? [[String: Any]],
           let first = controllers.first,
           let actions = first["Actions"] as? [String: Any] {
            actionsDict = actions
        } else {
            actionsDict = json["Actions"] as? [String: Any] ?? [:]
        }

        var actions: [StreamDeckAction] = []
        for (position, value) in actionsDict {
            guard let actionDict = value as? [String: Any] else { continue }
            if let parsed = parseAction(position: position, dict: actionDict) {
                actions.append(parsed)
            }
        }

        // Sort by grid position (row first, then column)
        actions.sort { a, b in
            let aParts = a.position.split(separator: ",").compactMap { Int($0) }
            let bParts = b.position.split(separator: ",").compactMap { Int($0) }
            guard aParts.count == 2, bParts.count == 2 else { return a.position < b.position }
            if aParts[0] != bParts[0] { return aParts[0] < bParts[0] }
            return aParts[1] < bParts[1]
        }

        return StreamDeckManifest(name: name, actions: actions)
    }

    // MARK: - File Loading

    private static func loadManifestData(from url: URL) throws -> Data {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw StreamDeckParseError.fileNotFound
        }

        if isDir.boolValue {
            // It's a directory bundle – look for manifest.json inside
            let manifestURL = url.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw StreamDeckParseError.manifestNotFound
            }
            return try Data(contentsOf: manifestURL)
        } else {
            // Try as a ZIP archive
            return try extractAndLoadManifest(from: url)
        }
    }

    private static func extractAndLoadManifest(from url: URL) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("streamdeck-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw StreamDeckParseError.extractionFailed("unzip returned status \(process.terminationStatus)")
        }

        // Search for manifest.json (may be nested in a subdirectory)
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == "manifest.json" {
                return try Data(contentsOf: fileURL)
            }
        }

        throw StreamDeckParseError.manifestNotFound
    }

    // MARK: - Action Parsing

    private static func parseAction(position: String, dict: [String: Any]) -> StreamDeckAction? {
        let uuid = dict["UUID"] as? String ?? ""
        let name = dict["Name"] as? String ?? ""
        let settings = dict["Settings"] as? [String: Any] ?? [:]
        let states = dict["States"] as? [[String: Any]]
        let title = states?.first?["Title"] as? String

        let displayTitle = (title?.isEmpty == false) ? title : (name.isEmpty ? nil : name)

        let actionSettings: StreamDeckActionSettings

        switch uuid {
        case "com.elgato.streamdeck.system.hotkey":
            // Real profiles store hotkeys in a Hotkeys array inside Settings
            if let hotkeysArray = settings["Hotkeys"] as? [[String: Any]],
               let first = hotkeysArray.first,
               let hotkey = parseHotkey(settings: first) {
                actionSettings = hotkey
            } else if let hotkey = parseHotkey(settings: settings) {
                // Fallback: direct NativeCode/KeyCmd in Settings (legacy/simplified format)
                actionSettings = hotkey
            } else {
                return nil // Sentinel entry, skip entirely
            }

        case "com.elgato.streamdeck.system.hotkeyswitch":
            // Multi-state hotkey – use first state
            if let hotkeyStates = settings["HotKeys"] as? [[String: Any]],
               let first = hotkeyStates.first,
               let hotkey = parseHotkey(settings: first) {
                actionSettings = hotkey
            } else {
                actionSettings = .unsupported(pluginUUID: uuid)
            }

        case "com.elgato.streamdeck.system.open":
            let path = settings["path"] as? String ?? ""
            if !path.isEmpty {
                actionSettings = .openApp(path: path)
            } else {
                actionSettings = .unsupported(pluginUUID: uuid)
            }

        case "com.elgato.streamdeck.system.website":
            let urlString = settings["path"] as? String ?? settings["openInBrowser"] as? String ?? ""
            if !urlString.isEmpty {
                actionSettings = .website(url: urlString)
            } else {
                actionSettings = .unsupported(pluginUUID: uuid)
            }

        case "com.elgato.streamdeck.multiactions", "com.elgato.streamdeck.multiactions.routine":
            // Real profiles: sub-actions in top-level Actions array (first state)
            // Legacy/test format: sub-actions in Settings.Routine
            var subActions: [StreamDeckAction] = []

            if let actionsStates = dict["Actions"] as? [[String: Any]],
               let firstState = actionsStates.first,
               let subDicts = firstState["Actions"] as? [[String: Any]] {
                // V2 format: Actions[0].Actions[]
                for (index, subDict) in subDicts.enumerated() {
                    if let sub = parseAction(position: "\(position).\(index)", dict: subDict) {
                        subActions.append(sub)
                    }
                }
            } else if let routine = settings["Routine"] as? [[String: Any]] {
                // Legacy format: Settings.Routine[]
                for (index, subDict) in routine.enumerated() {
                    if let sub = parseAction(position: "\(position).\(index)", dict: subDict) {
                        subActions.append(sub)
                    }
                }
            }

            actionSettings = .multiAction(subActions)

        case "com.elgato.streamdeck.system.text":
            // Real profiles use "pastedText"; also check "text" and "textToSend" for compatibility
            let text = settings["pastedText"] as? String
                ?? settings["text"] as? String
                ?? settings["textToSend"] as? String
                ?? ""
            if !text.isEmpty {
                actionSettings = .text(text)
            } else {
                actionSettings = .unsupported(pluginUUID: uuid)
            }

        default:
            actionSettings = .unsupported(pluginUUID: uuid)
        }

        return StreamDeckAction(
            position: position,
            name: name,
            title: displayTitle,
            settings: actionSettings
        )
    }

    // MARK: - Hotkey Parsing

    private static func parseHotkey(settings: [String: Any]) -> StreamDeckActionSettings? {
        let nativeCode = settings["NativeCode"] as? Int ?? settings["KeyCode"] as? Int
        let keyCmd = settings["KeyCmd"] as? Bool ?? false
        let keyShift = settings["KeyShift"] as? Bool ?? false
        let keyOption = settings["KeyOption"] as? Bool ?? false
        let keyCtrl = settings["KeyCtrl"] as? Bool ?? false

        // Filter sentinel entries: NativeCode -1 (real profiles) or 146 (legacy) with no modifiers
        if let code = nativeCode, (code == -1 || code == 146) && !keyCmd && !keyShift && !keyOption && !keyCtrl {
            return nil
        }

        // Must have either a valid key code or at least one modifier
        guard (nativeCode != nil && nativeCode != -1) || keyCmd || keyShift || keyOption || keyCtrl else {
            return nil
        }

        let keyCode: CGKeyCode?
        if let code = nativeCode, code >= 0 {
            keyCode = CGKeyCode(code)
        } else {
            keyCode = nil
        }

        let modifiers = ModifierFlags(
            command: keyCmd,
            option: keyOption,
            shift: keyShift,
            control: keyCtrl
        )

        return .hotkey(keyCode, modifiers)
    }
}
