import Foundation

/// A draft changes only the selected response mode unless the user opts into all modes.
struct StickCalibrationDraft {
	let original: StickTuning
	let side: JoystickSide
	var inner: Double
	var outer: Double
	var applyToAllModes = false

	init(tuning: StickTuning, side: JoystickSide) {
		original = tuning
		self.side = side
		outer = tuning.outerRange
		inner = Self.deadzone(in: tuning, side: side) * tuning.outerRange
	}

	static func deadzone(in tuning: StickTuning, side: JoystickSide) -> Double {
		switch tuning.mode {
		case .scroll: return tuning.scrollDeadzone
		case .custom: return tuning.customDeadzone
		case .dpad, .wasdKeys, .arrowKeys: return side == .left ? tuning.mouseDeadzone : tuning.scrollDeadzone
		default: return tuning.mouseDeadzone
		}
	}

	var modeName: String {
		switch original.mode {
		case .scroll: return "Scroll"
		case .custom: return "Custom directions"
		case .dpad, .wasdKeys, .arrowKeys: return "Direction keys"
		case .none: return "Mouse (stick currently off)"
		default: return "Mouse"
		}
	}
	var isValid: Bool { inner.isFinite && outer.isFinite && (0.5...1).contains(outer) && inner >= 0 && inner < outer }
	var hasChanges: Bool {
		abs(inner - Self.deadzone(in: original, side: side) * original.outerRange) > 0.000000001 ||
		abs(outer - original.outerRange) > 0.000000001 || applyToAllModes
	}
	var proposed: StickTuning {
		guard hasChanges, isValid else { return original }
		var tuning = original
		let value = min(0.99, inner / outer)
		tuning.outerRange = outer
		if applyToAllModes {
			tuning.mouseDeadzone = value; tuning.scrollDeadzone = value; tuning.customDeadzone = value
		} else {
			switch original.mode {
			case .scroll: tuning.scrollDeadzone = value
			case .custom: tuning.customDeadzone = value
			case .dpad, .wasdKeys, .arrowKeys:
				if side == .left { tuning.mouseDeadzone = value } else { tuning.scrollDeadzone = value }
			default: tuning.mouseDeadzone = value
			}
		}
		return tuning
	}
}
