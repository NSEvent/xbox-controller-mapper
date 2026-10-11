/// Shipping touchpad baseline, calibrated from Kevin's Default profile (2026-10-11).
/// Keep the full precision: creation and missing-field decoding must agree.
/// Explicit settings in saved/imported profiles remain authoritative.
enum TouchpadDefaults {
	static let sensitivity = 0.49725684691011235
	static let acceleration = 0.5011192064606742
	static let deadzone = 0.0013147384129213483
	static let smoothing = 0.40300649578651687
	static let panSensitivity = 0.4986064782303371
	static let zoomToPanRatio = 1.9511488325140447
	static let requireActiveTouchForRegionClick = false
}
