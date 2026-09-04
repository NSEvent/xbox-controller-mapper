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
		!isStickless && !isOuraRing && !isBeamdeskHands && !isAppleTVRemote
	}

	var supportsMotionGestures: Bool {
		isPlayStation || isSteamController
	}

	/// The command wheel is driven by the right stick.
	var supportsCommandWheel: Bool {
		hasSticks
	}

	var hasTriggers: Bool {
		eightBitDoModel != .zero2
			&& !isOuraRing
			&& !isBeamdeskHands
			&& !isAppleTVRemote
	}

	/// Exact logical controls represented by this descriptor's editor. Keep
	/// configuration inventory on the same availability truth as the canvas.
	var supportedButtons: Set<ControllerButton> {
		var buttons: Set<ControllerButton>
		switch family {
		case .ouraRing:
			return Set(ControllerButton.ouraRingButtons)
		case .beamdeskHands:
			return Set(ControllerButton.beamdeskHandButtons)
		case .appleTVRemote:
			return Set(ControllerButton.appleTVRemoteButtons)
		case .dualShock:
			buttons = Set(ControllerButton.dualShockButtons)
		case .dualSense:
			buttons = Set(ControllerButton.dualSenseButtons)
		case .dualSenseEdge:
			buttons = Set(ControllerButton.dualSenseButtons)
			buttons.formUnion([.leftPaddle, .rightPaddle, .leftFunction, .rightFunction])
		case .steam:
			buttons = Set(ControllerButton.xboxButtons)
			buttons.formUnion(ControllerButton.allCases.filter(\.isSteamControllerOnly))
			buttons.formUnion(ControllerButton.xboxEliteButtons)
			buttons.formUnion([.leftPaddle, .rightPaddle, .leftFunction, .rightFunction])
		case .xboxElite:
			buttons = Set(ControllerButton.xboxButtons)
			buttons.remove(.share)
			buttons.formUnion(ControllerButton.xboxEliteButtons)
			buttons.formUnion([.leftPaddle, .rightPaddle, .leftFunction, .rightFunction])
		case .xbox, .nintendo:
			buttons = Set(family == .nintendo ? ControllerButton.nintendoButtons : ControllerButton.xboxButtons)
		case let .eightBitDo(model):
			buttons = Set(ControllerButton.xboxButtons)
			buttons.remove(.share)
			if model == .zero2 { buttons.remove(.xbox) }
		}

		if isStickless {
			buttons.remove(.leftThumbstick)
			buttons.remove(.rightThumbstick)
			buttons.subtract(ControllerButton.allCases.filter(\.isJoystickDirection))
		}
		if !hasTriggers {
			buttons.remove(.leftTrigger)
			buttons.remove(.rightTrigger)
		}
		return buttons
	}

	var displayName: String {
		switch family {
		case .xbox: return "Xbox"
		case .xboxElite: return "Xbox Elite"
		case .dualSense: return "DualSense"
		case .dualSenseEdge: return "DualSense Edge"
		case .dualShock: return "DualShock 4"
		case .nintendo: return "Nintendo"
		case .steam: return "Steam Controller"
		case .eightBitDo(.zero2): return "8BitDo Zero 2"
		case .eightBitDo(.micro): return "8BitDo Micro"
		case .eightBitDo(.lite2): return "8BitDo Lite 2"
		case .eightBitDo(.liteSE): return "8BitDo Lite SE"
		case .appleTVRemote: return "Apple TV Remote"
		case .ouraRing: return "Oura Ring"
		case .beamdeskHands: return "Beamdesk Hands"
		}
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
		if isOuraRing || isBeamdeskHands || isAppleTVRemote { return [] }
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

enum ControllerLEDPresentationPolicy {
	static func supportsPlayerAndMuteLEDs(
		descriptor: ControllerVisualDescriptor,
		previewLayout: ControllerPreviewLayout,
		activeConnectionIsBluetooth: Bool
	) -> Bool {
		guard descriptor.isDualSense else { return false }
		return previewLayout != .active || !activeConnectionIsBluetooth
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
		active(
			from: service.threadSafeControllerPresentationState,
			ouraRingIsActive: service.isOuraRingActiveInputSource,
			beamdeskHandsAreActive: service.isBeamdeskHandsActiveInputSource
		)
	}

	static func active(
		from state: ControllerPresentationState,
		ouraRingIsActive: Bool,
		beamdeskHandsAreActive: Bool
	) -> ControllerVisualDescriptor {
		if ouraRingIsActive {
			return ControllerVisualDescriptor(family: .ouraRing)
		}
		if beamdeskHandsAreActive {
			return ControllerVisualDescriptor(family: .beamdeskHands)
		}
		return active(from: state)
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
