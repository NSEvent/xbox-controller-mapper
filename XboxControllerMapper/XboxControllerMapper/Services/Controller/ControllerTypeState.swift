import Foundation

enum ControllerJoyConSide: Equatable, Sendable {
	case left
	case right
	case pair
	case unknown

	init(isLeft: Bool, isRight: Bool) {
		switch (isLeft, isRight) {
		case (true, false):
			self = .left
		case (false, true):
			self = .right
		case (true, true):
			self = .pair
		case (false, false):
			self = .unknown
		}
	}

	var isLeft: Bool {
		switch self {
		case .left, .pair:
			return true
		case .right, .unknown:
			return false
		}
	}

	var isRight: Bool {
		switch self {
		case .right, .pair:
			return true
		case .left, .unknown:
			return false
		}
	}
}

enum ControllerTypeState: Equatable, Sendable {
	case xbox
	case xboxElite
	case dualSense
	case dualSenseEdge
	case dualShock
	case nintendo(ControllerJoyConSide)
	case steam
	case appleTVRemote

	init?(screenshotVariant: String) {
		switch screenshotVariant {
		case "xbox", "8bitdo-zero2", "8bitdo-micro", "8bitdo-lite2", "8bitdo-lite-se":
			self = .xbox
		case "xbox-elite":
			self = .xboxElite
		case "dualsense":
			self = .dualSense
		case "dualsense-edge":
			self = .dualSenseEdge
		case "dualshock":
			self = .dualShock
		case "nintendo":
			self = .nintendo(.unknown)
		case "steam":
			self = .steam
		case "appletv":
			self = .appleTVRemote
		default:
			return nil
		}
	}
}

struct ControllerPresentationState: Equatable, Sendable {
	let controllerType: ControllerTypeState
	let eightBitDoModel: EightBitDoMinimapModel?

	var isAppleTVRemote: Bool {
		controllerType == .appleTVRemote
	}

	var isSteamController: Bool {
		controllerType == .steam
	}

	var isDualSense: Bool {
		switch controllerType {
		case .dualSense, .dualSenseEdge:
			return true
		default:
			return false
		}
	}

	var isDualSenseEdge: Bool {
		controllerType == .dualSenseEdge
	}

	var isDualShock: Bool {
		controllerType == .dualShock
	}

	var isPlayStation: Bool {
		switch controllerType {
		case .dualSense, .dualSenseEdge, .dualShock:
			return true
		default:
			return false
		}
	}

	var isNintendo: Bool {
		if case .nintendo = controllerType { return true }
		return false
	}

	var isXboxElite: Bool {
		controllerType == .xboxElite
	}

	var hasMotion: Bool {
		isPlayStation || isSteamController
	}

	var isSingleJoyCon: Bool {
		guard case let .nintendo(side) = controllerType else { return false }
		return side.isLeft || side.isRight
	}
}

extension ControllerStorage {
	func restoreControllerTypeFlags(
		isDualSense: Bool,
		isDualSenseEdge: Bool,
		isDualShock: Bool,
		isNintendo: Bool,
		isXboxElite: Bool,
		isSteamController: Bool,
		isAppleTVRemote: Bool
	) {
		lock.lock()
		defer { lock.unlock() }
		restoreControllerTypeFlagsLocked(
			isDualSense: isDualSense,
			isDualSenseEdge: isDualSenseEdge,
			isDualShock: isDualShock,
			isNintendo: isNintendo,
			isXboxElite: isXboxElite,
			isSteamController: isSteamController,
			isAppleTVRemote: isAppleTVRemote
		)
	}

	/// Caller owns `lock`.
	func restoreControllerTypeFlagsLocked(
		isDualSense: Bool,
		isDualSenseEdge: Bool,
		isDualShock: Bool,
		isNintendo: Bool,
		isXboxElite: Bool,
		isSteamController: Bool,
		isAppleTVRemote: Bool
	) {
		clearControllerTypeFlagsLocked()
		self.isDualSense = isDualSense
		self.isDualSenseEdge = isDualSenseEdge
		self.isDualShock = isDualShock
		self.isNintendo = isNintendo
		self.isXboxElite = isXboxElite
		self.isSteamController = isSteamController
		self.isAppleTVRemote = isAppleTVRemote
		normalizeControllerTypeFlagsLocked()
	}

	/// Caller owns `lock`.
	func clearControllerTypeFlagsLocked() {
		isDualSense = false
		isDualSenseEdge = false
		isDualShock = false
		isNintendo = false
		isJoyConLeft = false
		isJoyConRight = false
		isXboxElite = false
		isSteamController = false
		isAppleTVRemote = false
	}

	/// Caller owns `lock`.
	func applyControllerTypeLocked(_ type: ControllerTypeState) {
		clearControllerTypeFlagsLocked()
		switch type {
		case .xbox:
			break
		case .xboxElite:
			isXboxElite = true
		case .dualSense:
			isDualSense = true
		case .dualSenseEdge:
			isDualSense = true
			isDualSenseEdge = true
		case .dualShock:
			isDualShock = true
		case .nintendo(let side):
			isNintendo = true
			isJoyConLeft = side.isLeft
			isJoyConRight = side.isRight
		case .steam:
			isSteamController = true
		case .appleTVRemote:
			isAppleTVRemote = true
		}
	}

	/// Caller owns `lock`.
	func clearAppleTVRemoteFlagLocked() {
		isAppleTVRemote = false
	}

	/// Caller owns `lock`.
	var controllerTypeStateLocked: ControllerTypeState {
		if isAppleTVRemote { return .appleTVRemote }
		if isSteamController { return .steam }
		if isDualSenseEdge { return .dualSenseEdge }
		if isDualSense { return .dualSense }
		if isDualShock { return .dualShock }
		if isNintendo {
			return .nintendo(ControllerJoyConSide(isLeft: isJoyConLeft, isRight: isJoyConRight))
		}
		if isXboxElite { return .xboxElite }
		return .xbox
	}

	/// Caller owns `lock`.
	func normalizeControllerTypeFlagsLocked() {
		applyControllerTypeLocked(controllerTypeStateLocked)
	}

	/// Caller owns `lock`.
	var controllerPresentationStateLocked: ControllerPresentationState {
		ControllerPresentationState(
			controllerType: controllerTypeStateLocked,
			eightBitDoModel: eightBitDoModel
		)
	}
}
