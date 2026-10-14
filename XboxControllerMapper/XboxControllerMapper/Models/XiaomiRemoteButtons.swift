import Foundation

extension ControllerButton {
	var isXiaomiRemoteOnly: Bool {
		Self.xiaomiRemoteActionButtons.contains(self)
	}

	static var xiaomiRemoteActionButtons: [ControllerButton] {
		[.xiaomiOK, .xiaomiBack, .xiaomiHome, .xiaomiMenu, .xiaomiVolumeUp,
		 .xiaomiVolumeDown, .xiaomiTV, .xiaomiMicrophone, .xiaomiPower]
	}

	static var xiaomiRemoteButtons: [ControllerButton] {
		[.dpadUp, .dpadDown, .dpadLeft, .dpadRight] + xiaomiRemoteActionButtons
	}

	var xiaomiRemoteSystemImage: String? {
		switch self {
		case .xiaomiOK: return "circle"
		case .xiaomiBack: return "chevron.left"
		case .xiaomiHome: return "house"
		case .xiaomiMenu: return "line.3.horizontal"
		case .xiaomiVolumeUp: return "plus"
		case .xiaomiVolumeDown: return "minus"
		case .xiaomiTV: return "tv"
		case .xiaomiMicrophone: return "mic"
		case .xiaomiPower: return "power"
		default: return nil
		}
	}
}
