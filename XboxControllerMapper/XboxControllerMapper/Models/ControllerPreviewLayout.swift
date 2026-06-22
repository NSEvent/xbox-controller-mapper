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

	static var concreteLayouts: [ControllerPreviewLayout] {
		allCases.filter { $0 != .active }
	}

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
}
