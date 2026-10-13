import Foundation

/// Full state, not mapped actions. ControllerKeys on the destination owns mappings.
struct SteamDeckFrame: Codable, Equatable {
	struct Pad: Codable, Equatable {
		var x: Float
		var y: Float
		var touching: Bool
		var pressed: Bool
		var valid: Bool { x.isFinite && y.isFinite && abs(x) <= 1 && abs(y) <= 1 }
	}
	var version: Int
	var active: Bool
	var buttons: [String]
	var axes: [Float]
	var pads: [Pad]
	var session: UUID?
	var sequence: UInt64?
	/// Raw accelerometer X/Y/Z then gyro X/Y/Z, matching Valve's report units.
	var motion: [Int16]?

	static let capability = "controllerKeysSteamDeck"
	static let notification = "xyz.kevintang.screenshell.controllerkeys-gamepad"
	static let allowedButtons: Set<String> = [
		"a", "b", "x", "y", "leftBumper", "rightBumper", "menu", "view", "xbox",
		"leftThumbstick", "rightThumbstick", "dpadUp", "dpadDown", "dpadLeft", "dpadRight",
		"xboxPaddle1", "xboxPaddle2", "xboxPaddle3", "xboxPaddle4",
	]
	var isNeutral: Bool {
		buttons.isEmpty && axes.allSatisfy { abs($0) < 0.15 } &&
		pads.allSatisfy { !$0.touching && !$0.pressed }
	}
	static func parse(_ text: String?) -> Self? {
		guard let text, text.utf8.count <= 4096,
			  let frame = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)),
			  frame.version == 1, frame.axes.count == 6, frame.pads.count == 2,
			  frame.buttons.count <= allowedButtons.count,
			  Set(frame.buttons).count == frame.buttons.count,
			  Set(frame.buttons).isSubset(of: allowedButtons), frame.pads.allSatisfy(\.valid),
			  frame.motion == nil || frame.motion?.count == 6,
			  frame.axes.enumerated().allSatisfy({ index, value in
				  value.isFinite && value <= 1 && value >= (index < 4 ? -1 : 0)
			  }) else { return nil }
		return frame
	}
	static var released: Self {
		Self(version: 1, active: false, buttons: [], axes: [0, 0, 0, 0, 0, 0],
			 pads: [.init(x: 0, y: 0, touching: false, pressed: false),
					.init(x: 0, y: 0, touching: false, pressed: false)])
	}
}
