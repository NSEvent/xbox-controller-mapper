import Foundation

/// Resolved controller family for the mapping canvas. This is the view-facing
/// descriptor layer between persisted preview choices / active hardware state
/// and the SwiftUI rows/minimap branches.
enum ControllerVisualFamily: Equatable {
	case xbox
	case xboxElite
	case dualSense
	case dualSenseEdge
	case dualShock
	case nintendo
	case steam
	case eightBitDo(EightBitDoMinimapModel)
	case appleTVRemote
	case ouraRing
	case beamdeskHands
}

struct ControllerVisualDescriptor: Equatable {
	let family: ControllerVisualFamily

	var isAppleTVRemote: Bool {
		family == .appleTVRemote
	}

	var isOuraRing: Bool {
		family == .ouraRing
	}

	var isBeamdeskHands: Bool {
		family == .beamdeskHands
	}

	var isPlayStation: Bool {
		switch family {
		case .dualSense, .dualSenseEdge, .dualShock:
			return true
		default:
			return false
		}
	}

	var isDualSense: Bool {
		switch family {
		case .dualSense, .dualSenseEdge:
			return true
		default:
			return false
		}
	}

	var isDualSenseEdge: Bool {
		family == .dualSenseEdge
	}

	var isDualShock: Bool {
		family == .dualShock
	}

	var isXboxElite: Bool {
		family == .xboxElite
	}

	var isSteamController: Bool {
		family == .steam
	}

	var isNintendo: Bool {
		family == .nintendo
	}

	var eightBitDoModel: EightBitDoMinimapModel? {
		if case let .eightBitDo(model) = family {
			return model
		}
		return nil
	}

	var isStickless: Bool {
		eightBitDoModel?.isStickless == true
	}

	var hasSticks: Bool {
		!isStickless && !isOuraRing && !isBeamdeskHands
	}

	var hasTriggers: Bool {
		eightBitDoModel != .zero2 && !isOuraRing && !isBeamdeskHands
	}

	var showsPlayStationTouchpad: Bool {
		isPlayStation && !isSteamController
	}

	var showsSteamTouchpads: Bool {
		isSteamController
	}

	var showsDualSenseEdgeControls: Bool {
		isDualSenseEdge
	}

	var showsGripOrPaddleSection: Bool {
		isXboxElite || isSteamController
	}

	var gripOrPaddleSectionTitle: String {
		isSteamController ? "STEAM GRIP BUTTONS" : "ELITE PADDLES"
	}

	var minimapStyle: ControllerMinimapStyle? {
		switch family {
		case .xbox:
			return .xbox
		case .xboxElite:
			return .xboxElite
		case .dualSense:
			return .dualSense
		case .dualSenseEdge:
			return .dualSenseEdge
		case .dualShock:
			return .dualShock
		case .nintendo:
			return .nintendo
		case .steam:
			return .steam
		case let .eightBitDo(model):
			return model.minimapStyle
		case .appleTVRemote:
			return nil
		case .ouraRing:
			return nil
		case .beamdeskHands:
			return nil
		}
	}

	func shoulderButtons(side: JoystickSide) -> [ControllerButton] {
		if isOuraRing || isBeamdeskHands { return [] }
		switch side {
		case .left:
			return hasTriggers ? [.leftTrigger, .leftBumper] : [.leftBumper]
		case .right:
			return hasTriggers ? [.rightTrigger, .rightBumper] : [.rightBumper]
		}
	}

	var leftSystemButtons: [ControllerButton] {
		if isOuraRing || isBeamdeskHands { return [] }
		var buttons: [ControllerButton] = [.view]
		if eightBitDoModel != .zero2 {
			buttons.append(.xbox)
		}
		return buttons
	}

	var rightSystemButtons: [ControllerButton] {
		if isOuraRing || isBeamdeskHands { return [] }
		var buttons: [ControllerButton] = [.menu]
		if isDualSense {
			buttons.append(.micMute)
		} else if !isDualShock && (!isXboxElite || isSteamController) && eightBitDoModel == nil {
			buttons.append(.share)
		}
		return buttons
	}
}

extension ControllerVisualDescriptor {
	static func concrete(for layout: ControllerPreviewLayout) -> ControllerVisualDescriptor? {
		switch layout {
		case .active:
			return nil
		case .xbox:
			return ControllerVisualDescriptor(family: .xbox)
		case .xboxElite:
			return ControllerVisualDescriptor(family: .xboxElite)
		case .dualSense:
			return ControllerVisualDescriptor(family: .dualSense)
		case .dualSenseEdge:
			return ControllerVisualDescriptor(family: .dualSenseEdge)
		case .dualShock:
			return ControllerVisualDescriptor(family: .dualShock)
		case .nintendo:
			return ControllerVisualDescriptor(family: .nintendo)
		case .steam:
			return ControllerVisualDescriptor(family: .steam)
		case .eightBitDoZero2:
			return ControllerVisualDescriptor(family: .eightBitDo(.zero2))
		case .eightBitDoMicro:
			return ControllerVisualDescriptor(family: .eightBitDo(.micro))
		case .eightBitDoLite2:
			return ControllerVisualDescriptor(family: .eightBitDo(.lite2))
		case .eightBitDoLiteSE:
			return ControllerVisualDescriptor(family: .eightBitDo(.liteSE))
		case .appleTVRemote:
			return ControllerVisualDescriptor(family: .appleTVRemote)
		case .ouraRing:
			return ControllerVisualDescriptor(family: .ouraRing)
		case .beamdeskHands:
			return ControllerVisualDescriptor(family: .beamdeskHands)
		}
	}

	static func active(from state: ControllerPresentationState) -> ControllerVisualDescriptor {
		if state.isAppleTVRemote {
			return ControllerVisualDescriptor(family: .appleTVRemote)
		}
		if let model = state.eightBitDoModel {
			return ControllerVisualDescriptor(family: .eightBitDo(model))
		}
		switch state.controllerType {
		case .xbox:
			return ControllerVisualDescriptor(family: .xbox)
		case .xboxElite:
			return ControllerVisualDescriptor(family: .xboxElite)
		case .dualSense:
			return ControllerVisualDescriptor(family: .dualSense)
		case .dualSenseEdge:
			return ControllerVisualDescriptor(family: .dualSenseEdge)
		case .dualShock:
			return ControllerVisualDescriptor(family: .dualShock)
		case .nintendo:
			return ControllerVisualDescriptor(family: .nintendo)
		case .steam:
			return ControllerVisualDescriptor(family: .steam)
		case .appleTVRemote:
			return ControllerVisualDescriptor(family: .appleTVRemote)
		}
	}

	static func active(using service: ControllerService) -> ControllerVisualDescriptor {
		if service.isOuraRingConnected {
			return ControllerVisualDescriptor(family: .ouraRing)
		}
		if service.isBeamdeskHandsConnected {
			return ControllerVisualDescriptor(family: .beamdeskHands)
		}
		return active(from: service.threadSafeControllerPresentationState)
	}

	static func resolved(
		previewLayout: ControllerPreviewLayout,
		presentationState: ControllerPresentationState
	) -> ControllerVisualDescriptor {
		concrete(for: previewLayout) ?? active(from: presentationState)
	}

	static func resolved(previewLayout: ControllerPreviewLayout, using service: ControllerService) -> ControllerVisualDescriptor {
		concrete(for: previewLayout) ?? active(using: service)
	}
}
