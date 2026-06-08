import Foundation

extension GenericHIDController {
	/// Convert common HID hat encodings to SDL-style bitmask:
	/// up=1, right=2, down=4, left=8, neutral=-1.
	static func hatValueToBits(_ value: Int, logicalMin: Int, logicalMax: Int) -> Int {
		switch (logicalMin, logicalMax) {
		case (0, 7):
			return eightWayHatValueToBits(value)
		case (0, 8):
			guard value != 0 else { return -1 }
			return eightWayHatValueToBits(value - 1)
		case (0, 3):
			return fourWayHatValueToBits(value)
		case (0, 4):
			guard value != 0 else { return -1 }
			return fourWayHatValueToBits(value - 1)
		default:
			return -1
		}
	}

	private static func eightWayHatValueToBits(_ value: Int) -> Int {
		switch value {
		case 0: return 1
		case 1: return 1 | 2
		case 2: return 2
		case 3: return 4 | 2
		case 4: return 4
		case 5: return 4 | 8
		case 6: return 8
		case 7: return 1 | 8
		default: return -1
		}
	}

	private static func fourWayHatValueToBits(_ value: Int) -> Int {
		switch value {
		case 0: return 1
		case 1: return 2
		case 2: return 4
		case 3: return 8
		default: return -1
		}
	}
}
