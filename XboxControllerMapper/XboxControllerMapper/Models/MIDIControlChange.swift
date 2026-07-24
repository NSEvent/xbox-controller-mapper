import Foundation

/// A MIDI 1.0 Control Change message emitted by ControllerKeys.
struct MIDIControlChange: Codable, Equatable {
	var channel: Int
	var controller: Int
	var pressValue: Int
	var releaseValue: Int

	init(
		channel: Int = 1,
		controller: Int = 1,
		pressValue: Int = 127,
		releaseValue: Int = 0
	) {
		self.channel = Self.clamp(channel, to: 1...16)
		self.controller = Self.clamp(controller, to: 0...127)
		self.pressValue = Self.clamp(pressValue, to: 0...127)
		self.releaseValue = Self.clamp(releaseValue, to: 0...127)
	}

	private enum CodingKeys: String, CodingKey {
		case channel, controller, pressValue, releaseValue
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			channel: try container.decode(.channel, default: 1),
			controller: try container.decode(.controller, default: 1),
			pressValue: try container.decode(.pressValue, default: 127),
			releaseValue: try container.decode(.releaseValue, default: 0)
		)
	}

	var displayString: String {
		"MIDI CC \(controller) · Ch \(channel)"
	}

	var controllerWarning: String? {
		switch controller {
		case 98...101:
			return "CC \(controller) is commonly used for RPN/NRPN parameter selection."
		case 120...127:
			return "CC \(controller) is reserved for MIDI channel-mode messages."
		default:
			return nil
		}
	}

	private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
		min(range.upperBound, max(range.lowerBound, value))
	}
}
