import Foundation

// MARK: - Data Types

/// Reference to a HID element in SDL gamecontrollerdb format
enum SDLElementRef: Equatable {
    case button(Int)
    case axis(Int, inverted: Bool)
    case hat(Int, direction: HatDirection)

    enum HatDirection: Int {
        case up = 1
        case right = 2
        case down = 4
        case left = 8
    }
}

/// A parsed SDL controller mapping entry
struct SDLControllerMapping {
    let guid: String
    let name: String
    let buttonMap: [String: SDLElementRef]   // SDL button name -> element ref
    let axisMap: [String: SDLElementRef]     // SDL axis name -> element ref

    /// Maps SDL standard button names to ControllerButton
    static let sdlToControllerButton: [String: ControllerButton] = [
        "a": .a,
        "b": .b,
        "x": .x,
        "y": .y,
        "leftshoulder": .leftBumper,
        "rightshoulder": .rightBumper,
        "dpup": .dpadUp,
        "dpdown": .dpadDown,
        "dpleft": .dpadLeft,
        "dpright": .dpadRight,
        "start": .menu,
        "back": .view,
        "guide": .xbox,
        "leftstick": .leftThumbstick,
        "rightstick": .rightThumbstick,
        "misc1": .share,
    ]

    /// SDL axis names for stick movement
    static let sdlStickAxes: Set<String> = ["leftx", "lefty", "rightx", "righty"]

    /// SDL axis names for triggers
    static let sdlTriggerAxes: Set<String> = ["lefttrigger", "righttrigger"]
}

// MARK: - GameControllerDatabase

/// Parses and provides lookup for SDL's gamecontrollerdb.txt controller mappings.
class GameControllerDatabase {
    static let shared = GameControllerDatabase()

    private var mappings: [String: SDLControllerMapping] = [:]

    private static var userDatabasePath: String {
        (Config.configDirectory as NSString).appendingPathComponent("gamecontrollerdb.txt")
    }

    init(databaseContentOverride: String? = nil) {
        if let databaseContentOverride {
            parseDatabase(databaseContentOverride)
        } else {
            loadDatabase()
        }
    }

    // MARK: - GUID Construction

    /// Constructs an SDL-format GUID from IOKit HID device properties.
    /// Format: [bus_le16][0000][vendor_le16][0000][product_le16][0000][version_le16][0000]
    static func constructGUID(vendorID: Int, productID: Int, version: Int, transport: String?) -> String {
        let bus: UInt16 = (transport?.lowercased() == "bluetooth") ? 0x0005 : 0x0003

        func le16hex(_ value: UInt16) -> String {
            let lo = value & 0xFF
            let hi = (value >> 8) & 0xFF
            return String(format: "%02x%02x", lo, hi)
        }

        let busHex = le16hex(bus)
        let vendorHex = le16hex(UInt16(vendorID & 0xFFFF))
        let productHex = le16hex(UInt16(productID & 0xFFFF))
        let versionHex = le16hex(UInt16(version & 0xFFFF))

        return "\(busHex)0000\(vendorHex)0000\(productHex)0000\(versionHex)0000"
    }

    // MARK: - Lookup

    /// Look up a controller mapping by GUID string.
    func lookup(guid: String) -> SDLControllerMapping? {
        return mappings[guid.lowercased()]
    }

    /// Look up a controller mapping by device properties. Tries exact version match first,
    /// then falls back to version 0.
    func lookup(vendorID: Int, productID: Int, version: Int, transport: String?) -> SDLControllerMapping? {
        let guid = Self.constructGUID(vendorID: vendorID, productID: productID,
                                       version: version, transport: transport)
        if let mapping = mappings[guid.lowercased()] {
            return mapping
        }
        // Fallback: try with version 0
        if version != 0 {
            let fallbackGuid = Self.constructGUID(vendorID: vendorID, productID: productID,
                                                   version: 0, transport: transport)
            return mappings[fallbackGuid.lowercased()]
        }
        return nil
    }

    // MARK: - Database Loading

    func loadDatabase() {
        mappings.removeAll()

        let userPath = Self.userDatabasePath
        let bundledPath = Bundle.main.path(forResource: "gamecontrollerdb", ofType: "txt")

        let path: String
        if FileManager.default.fileExists(atPath: userPath) {
            path = userPath
        } else if let bp = bundledPath {
            path = bp
        } else {
            #if DEBUG
            print("[GameControllerDB] No database file found")
            #endif
            return
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            #if DEBUG
            print("[GameControllerDB] Failed to read database at \(path)")
            #endif
            return
        }

        parseDatabase(content)
        #if DEBUG
        print("[GameControllerDB] Loaded \(mappings.count) macOS controller mappings")
        #endif
    }

    // MARK: - Parsing

    private func parseDatabase(_ content: String) {
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard trimmed.contains("platform:Mac OS X") else { continue }

            if let mapping = parseLine(trimmed) {
                mappings[mapping.guid.lowercased()] = mapping
            }
        }
    }

    private func parseLine(_ line: String) -> SDLControllerMapping? {
        let components = line.components(separatedBy: ",")
        guard components.count >= 3 else { return nil }

        let guid = components[0].trimmingCharacters(in: .whitespaces)
        let name = components[1].trimmingCharacters(in: .whitespaces)
        guard guid.count == 32 else { return nil }

        var buttonMap: [String: SDLElementRef] = [:]
        var axisMap: [String: SDLElementRef] = [:]

        for i in 2..<components.count {
            let part = components[i].trimmingCharacters(in: .whitespaces)
            guard part.contains(":"), !part.hasPrefix("platform:") else { continue }

            let kv = part.components(separatedBy: ":")
            guard kv.count == 2 else { continue }

            let sdlName = kv[0]
            let elementStr = kv[1]
            guard let ref = parseElementRef(elementStr) else { continue }

            if SDLControllerMapping.sdlStickAxes.contains(sdlName) ||
               SDLControllerMapping.sdlTriggerAxes.contains(sdlName) {
                axisMap[sdlName] = ref
            } else {
                buttonMap[sdlName] = ref
            }
        }

        return SDLControllerMapping(guid: guid, name: name,
                                     buttonMap: buttonMap, axisMap: axisMap)
    }

    /// Parse an element reference string: b0, a1, +a2, -a3, ~a4, h0.1, etc.
    private func parseElementRef(_ str: String) -> SDLElementRef? {
        let s = str.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Hat switch: h0.1, h0.2, h0.4, h0.8
        if s.hasPrefix("h") {
            let parts = String(s.dropFirst()).components(separatedBy: ".")
            guard parts.count == 2,
                  let dirValue = Int(parts[1]),
                  let dir = SDLElementRef.HatDirection(rawValue: dirValue) else { return nil }
            return .hat(0, direction: dir)
        }

        // Button: b0, b1, ...
        if s.hasPrefix("b") {
            guard let idx = Int(String(s.dropFirst())) else { return nil }
            return .button(idx)
        }

        // Axis: a0, +a1, -a2, ~a3
        var axisStr = s
        var inverted = false
        if s.hasPrefix("~") {
            inverted = true
            axisStr = String(s.dropFirst())
        } else if s.hasPrefix("+") || s.hasPrefix("-") {
            axisStr = String(s.dropFirst())
        }

        if axisStr.hasPrefix("a"), let idx = Int(String(axisStr.dropFirst())) {
            return .axis(idx, inverted: inverted)
        }

        return nil
    }

    // MARK: - Database Refresh

    /// Downloads the latest database from GitHub and saves to the user config directory.
    /// Returns the number of macOS controller mappings loaded.
    func refreshFromGitHub() async throws -> Int {
        guard let url = URL(string: "https://raw.githubusercontent.com/gabomdq/SDL_GameControllerDB/master/gamecontrollerdb.txt") else {
            throw DatabaseError.downloadFailed
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DatabaseError.downloadFailed
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw DatabaseError.invalidData
        }

        // Verify it contains macOS entries before saving
        let macEntries = content.components(separatedBy: .newlines)
            .filter { $0.contains("platform:Mac OS X") && !$0.hasPrefix("#") }
        guard !macEntries.isEmpty else {
            throw DatabaseError.noMacOSEntries
        }

        // Ensure config directory exists
        try FileManager.default.createDirectory(atPath: Config.configDirectory,
                                                 withIntermediateDirectories: true)

        try content.write(toFile: Self.userDatabasePath, atomically: true, encoding: .utf8)
        loadDatabase()
        return mappings.count
    }

    enum DatabaseError: LocalizedError {
        case downloadFailed
        case invalidData
        case noMacOSEntries

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Failed to download controller database"
            case .invalidData: return "Downloaded data is not valid UTF-8 text"
            case .noMacOSEntries: return "No macOS controller entries found in database"
            }
        }
    }
}
