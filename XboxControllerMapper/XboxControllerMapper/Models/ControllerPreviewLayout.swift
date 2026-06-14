import Foundation

enum ControllerPreviewLayout: String, Codable, CaseIterable, Identifiable {
	case active
	case xbox
	case xboxElite
	case dualSense
	case dualSenseEdge
	case dualShock
	case nintendo
	case steam
	case eightBitDoZero2
	case eightBitDoMicro
	case eightBitDoLite2
	case eightBitDoLiteSE
	case appleTVRemote

	var id: String { rawValue }

	var displayName: String {
		switch self {
		case .active: return "Active Controller"
		case .xbox: return "Xbox"
		case .xboxElite: return "Xbox Elite"
		case .dualSense: return "DualSense"
		case .dualSenseEdge: return "DualSense Edge"
		case .dualShock: return "DualShock 4"
		case .nintendo: return "Nintendo"
		case .steam: return "Steam"
		case .eightBitDoZero2: return "8BitDo Zero 2"
		case .eightBitDoMicro: return "8BitDo Micro"
		case .eightBitDoLite2: return "8BitDo Lite 2"
		case .eightBitDoLiteSE: return "8BitDo Lite SE"
		case .appleTVRemote: return "Apple TV Remote"
		}
	}

	var systemImage: String {
		switch self {
		case .active: return "dot.radiowaves.left.and.right"
		case .xbox, .xboxElite: return "xbox.logo"
		case .dualSense, .dualSenseEdge, .dualShock: return "playstation.logo"
		case .nintendo: return "house"
		case .steam: return "gamecontroller"
		case .eightBitDoZero2, .eightBitDoMicro: return "gamecontroller.circle"
		case .eightBitDoLite2, .eightBitDoLiteSE: return "gamecontroller.circle.fill"
		case .appleTVRemote: return "appletvremote.gen3"
		}
	}

	func isPlayStation(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsPlayStation
		case .dualSense, .dualSenseEdge, .dualShock: return true
		default: return false
		}
	}

	func isDualSense(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualSense
		case .dualSense, .dualSenseEdge: return true
		default: return false
		}
	}

	func isDualSenseEdge(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualSenseEdge
		case .dualSenseEdge: return true
		default: return false
		}
	}

	func isDualShock(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsDualShock
		case .dualShock: return true
		default: return false
		}
	}

	func isXboxElite(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsXboxElite
		case .xboxElite: return true
		default: return false
		}
	}

	func isSteamController(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsSteamController
		case .steam: return true
		default: return false
		}
	}

	func isNintendo(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsNintendo
		case .nintendo: return true
		default: return false
		}
	}

	func eightBitDoModel(using service: ControllerService) -> EightBitDoMinimapModel? {
		switch self {
		case .active: return service.threadSafeEightBitDoMinimapModel
		case .eightBitDoZero2: return .zero2
		case .eightBitDoMicro: return .micro
		case .eightBitDoLite2: return .lite2
		case .eightBitDoLiteSE: return .liteSE
		default: return nil
		}
	}

	func isAppleTVRemote(using service: ControllerService) -> Bool {
		switch self {
		case .active: return service.threadSafeIsAppleTVRemote
		case .appleTVRemote: return true
		default: return false
		}
	}
}
