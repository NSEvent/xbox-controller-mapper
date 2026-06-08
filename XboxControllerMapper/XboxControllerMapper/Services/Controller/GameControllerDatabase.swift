import Foundation

// MARK: - Data Types

/// Reference to a HID element in SDL gamecontrollerdb format
enum SDLElementRef: Equatable {
    case button(Int)
    case axis(Int, inverted: Bool, polarity: AxisPolarity)
    case hat(Int, direction: HatDirection)

    enum AxisPolarity: Equatable {
	case full
	case positive
	case negative
    }

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

	static func normalizedAxisName(_ sdlName: String) -> (name: String, polarity: SDLElementRef.AxisPolarity)? {
		if sdlStickAxes.contains(sdlName) || sdlTriggerAxes.contains(sdlName) {
			return (sdlName, .full)
		}

		guard let prefix = sdlName.first, prefix == "+" || prefix == "-" else { return nil }
		let baseName = String(sdlName.dropFirst())
		guard sdlStickAxes.contains(baseName) || sdlTriggerAxes.contains(baseName) else { return nil }
		return (baseName, prefix == "+" ? .positive : .negative)
	}
}

// MARK: - GameControllerDatabase

/// Parses and provides lookup for SDL's gamecontrollerdb.txt controller mappings.
class GameControllerDatabase {
    static let shared = GameControllerDatabase()

    private var mappings: [String: SDLControllerMapping] = [:]
	private var allPlatformMappings: [String: SDLControllerMapping] = [:]

    private static var userDatabasePath: String {
        (Config.configDirectory as NSString).appendingPathComponent("gamecontrollerdb.txt")
    }

    private static var previousUserDatabasePath: String {
	(Config.previousConfigDirectory as NSString).appendingPathComponent("gamecontrollerdb.txt")
    }

    private static var legacyUserDatabasePath: String {
	(Config.legacyConfigDirectory as NSString).appendingPathComponent("gamecontrollerdb.txt")
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
	let bus = Self.busValue(transport: transport)

        func le16hex(_ value: UInt16) -> String {
            let lo = value & 0xFF
            let hi = (value >> 8) & 0xFF
            return String(format: "%02x%02x", lo, hi)
        }

	let busHex = le16hex(UInt16(bus & 0xFFFF))
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
    /// then falls back to version 0 and non-macOS mappings for the same VID/PID.
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
	    if let mapping = mappings[fallbackGuid.lowercased()] {
		return mapping
	    }
        }
	return platformFallbackMapping(
		vendorID: vendorID,
		productID: productID,
		version: version,
		transport: transport
	)
    }

    func knownVendorProductPairs(excludingVendors: Set<Int> = []) -> [(vendorID: Int, productID: Int)] {
	let pairs = allPlatformMappings.keys.compactMap { guid -> (vendorID: Int, productID: Int)? in
            guard let vendorID = Self.le16Value(in: guid, byteOffset: 4),
                  let productID = Self.le16Value(in: guid, byteOffset: 8),
                  !excludingVendors.contains(vendorID) else {
                return nil
            }
            return (vendorID, productID)
        }

        var seen = Set<String>()
        return pairs
            .filter { pair in
                seen.insert("\(pair.vendorID):\(pair.productID)").inserted
            }
            .sorted {
                $0.vendorID == $1.vendorID
                    ? $0.productID < $1.productID
                    : $0.vendorID < $1.vendorID
            }
    }

	func hasKnownVendorProduct(vendorID: Int, productID: Int) -> Bool {
		allPlatformMappings.keys.contains { guid in
			guard let knownVendorID = Self.le16Value(in: guid, byteOffset: 4),
			      let knownProductID = Self.le16Value(in: guid, byteOffset: 8) else {
				return false
			}
			return knownVendorID == vendorID && knownProductID == productID
		}
	}

	private func platformFallbackMapping(
		vendorID: Int,
		productID: Int,
		version: Int,
		transport: String?
	) -> SDLControllerMapping? {
		let preferredBus = Self.busValue(transport: transport)
		let candidates = allPlatformMappings.compactMap { guid, mapping -> (score: Int, guid: String, mapping: SDLControllerMapping)? in
			guard let candidateVendorID = Self.le16Value(in: guid, byteOffset: 4),
			      let candidateProductID = Self.le16Value(in: guid, byteOffset: 8),
			      candidateVendorID == vendorID,
			      candidateProductID == productID else {
				return nil
			}

			let candidateBus = Self.le16Value(in: guid, byteOffset: 0)
			let candidateVersion = Self.le16Value(in: guid, byteOffset: 12)
			let isMacMapping = mappings[guid] != nil
			var score = 0
			if isMacMapping { score -= 1_000 }
			if candidateBus == preferredBus { score -= 100 }
			if candidateVersion == version {
				score -= 20
			} else if candidateVersion == 0 {
				score -= 10
			}
			return (score: score, guid: guid, mapping: mapping)
		}

		return candidates.sorted {
			$0.score == $1.score ? $0.guid < $1.guid : $0.score < $1.score
		}.first?.mapping
	}

	private static func busValue(transport: String?) -> Int {
		transport?.lowercased().contains("bluetooth") == true ? 0x0005 : 0x0003
	}

    private static func le16Value(in guid: String, byteOffset: Int) -> Int? {
        let hexOffset = guid.index(guid.startIndex, offsetBy: byteOffset * 2)
        let nextByteOffset = guid.index(hexOffset, offsetBy: 2)
        let highByteOffset = guid.index(nextByteOffset, offsetBy: 2)
        guard highByteOffset <= guid.endIndex,
              let lowByte = UInt8(guid[hexOffset..<nextByteOffset], radix: 16),
              let highByte = UInt8(guid[nextByteOffset..<highByteOffset], radix: 16) else {
            return nil
        }
        return Int(lowByte) | (Int(highByte) << 8)
    }

    // MARK: - Database Loading

    func loadDatabase() {
        mappings.removeAll()
	allPlatformMappings.removeAll()

	let userPaths = [
	    Self.userDatabasePath,
	    Self.previousUserDatabasePath,
	    Self.legacyUserDatabasePath
	]
        let bundledPath = Bundle.main.path(forResource: "gamecontrollerdb", ofType: "txt")
	var loadedAnyDatabase = false

	if let bundledPath,
	   let content = try? String(contentsOfFile: bundledPath, encoding: .utf8) {
		parseDatabase(content)
		loadedAnyDatabase = true
	}

	if let userPath = userPaths.first(where: { FileManager.default.fileExists(atPath: $0) }),
	   let content = try? String(contentsOfFile: userPath, encoding: .utf8) {
		parseDatabase(content)
		loadedAnyDatabase = true
	}

	guard loadedAnyDatabase else {
            #if DEBUG
		print("[GameControllerDB] No database file found")
            #endif
            return
        }

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

            if let mapping = parseLine(trimmed) {
		allPlatformMappings[mapping.guid.lowercased()] = mapping
		if trimmed.contains("platform:Mac OS X") {
			mappings[mapping.guid.lowercased()] = mapping
		}
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

	    if SDLControllerMapping.normalizedAxisName(sdlName) != nil {
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
		var polarity: SDLElementRef.AxisPolarity = .full
		if axisStr.hasSuffix("~") {
			inverted = true
			axisStr = String(axisStr.dropLast())
		}
		if axisStr.hasPrefix("~") {
			inverted = true
			axisStr = String(axisStr.dropFirst())
		} else if axisStr.hasPrefix("+") {
			polarity = .positive
			axisStr = String(axisStr.dropFirst())
		} else if axisStr.hasPrefix("-") {
			polarity = .negative
			axisStr = String(axisStr.dropFirst())
		}

        if axisStr.hasPrefix("a"), let idx = Int(String(axisStr.dropFirst())) {
	    return .axis(idx, inverted: inverted, polarity: polarity)
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
