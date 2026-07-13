import CoreGraphics
import Carbon.HIToolbox

/// Pure policy for deciding which physical modifier key should be emitted for
/// a modifier mask. Keeps left/right side selection testable without posting
/// CGEvents or requiring Accessibility permissions.
enum ModifierKeyEmissionPolicy {
	static let modifierMasks: [CGEventFlags] = [
		.maskCommand, .maskAlternate, .maskShift, .maskControl
	]

	static let modifierPressOrder: [CGEventFlags] = [
		.maskCommand, .maskShift, .maskAlternate, .maskControl
	]

	static let modifierReleaseOrder: [CGEventFlags] = [
		.maskControl, .maskAlternate, .maskShift, .maskCommand
	]

	private static let defaultKeyCodes: [UInt64: CGKeyCode] = [
		CGEventFlags.maskCommand.rawValue: CGKeyCode(kVK_Command),
		CGEventFlags.maskAlternate.rawValue: CGKeyCode(kVK_Option),
		CGEventFlags.maskShift.rawValue: CGKeyCode(kVK_Shift),
		CGEventFlags.maskControl.rawValue: CGKeyCode(kVK_Control)
	]

	static func defaultKeyCode(for mask: CGEventFlags) -> CGKeyCode? {
		defaultKeyCode(forRawMask: mask.rawValue)
	}

	static func defaultKeyCode(forRawMask rawMask: UInt64) -> CGKeyCode? {
		defaultKeyCodes[rawMask]
	}

	static func keyCode(for mask: CGEventFlags, sides: ModifierFlags?) -> CGKeyCode? {
		if let sides, let sidedKeyCode = sides.virtualKey(forMask: mask) {
			return sidedKeyCode
		}
		return defaultKeyCode(for: mask)
	}
}
