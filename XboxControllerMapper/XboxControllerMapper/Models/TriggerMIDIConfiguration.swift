import Foundation

struct TriggerMIDIConfiguration: Codable, Equatable {
	var message = MIDIControlChange()
	var inverted = false
	var deadzone = 0.05

	init(message: MIDIControlChange = MIDIControlChange(), inverted: Bool = false, deadzone: Double = 0.05) {
		self.message = message
		self.inverted = inverted
		self.deadzone = min(0.9, max(0, deadzone))
	}

	static func suggested(for side: JoystickSide, avoiding other: TriggerMIDIConfiguration?) -> TriggerMIDIConfiguration {
		var config = TriggerMIDIConfiguration(message: MIDIControlChange(controller: side == .left ? 1 : 11))
		if let other, other.message.channel == config.message.channel, other.message.controller == config.message.controller {
			config.message.controller = (config.message.controller + 1) % 128
		}
		return config
	}

	private enum CodingKeys: String, CodingKey { case message, inverted, deadzone }
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(message: try container.decode(.message, default: MIDIControlChange()),
				  inverted: try container.decode(.inverted, default: false),
				  deadzone: try container.decode(.deadzone, default: 0.05, clampedTo: 0...0.9))
	}

	func value(for raw: Double) -> Int {
		let normalized = min(1, max(0, (raw - deadzone) / (1 - deadzone)))
		let fraction = inverted ? 1 - normalized : normalized
		return min(127, max(0, Int((Double(message.releaseValue) + fraction * Double(message.pressValue - message.releaseValue)).rounded())))
	}

	func output(value: Int) -> MIDIControlChange {
		MIDIControlChange(channel: message.channel, controller: message.controller,
						  pressValue: value, releaseValue: self.value(for: 0))
	}
}
