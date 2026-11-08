import Foundation

/// Canonical order makes equality, duplicate checks, and exports deterministic.
struct SequenceStep: Codable, Equatable, Hashable {
	let buttons: [ControllerButton]

	init(_ buttons: Set<ControllerButton>) {
		self.buttons = ControllerButton.allCases.filter { buttons.contains($0) }
	}

	func label(_ name: (ControllerButton) -> String) -> String {
		buttons.map(name).joined(separator: " + ")
	}

	var validationMessage: String? {
		guard !buttons.isEmpty else { return "Choose at least one button." }
		let pairs: [(ControllerButton, ControllerButton)] = [
			(.dpadUp, .dpadDown), (.dpadLeft, .dpadRight),
			(.leftStickUp, .leftStickDown), (.leftStickLeft, .leftStickRight),
			(.rightStickUp, .rightStickDown), (.rightStickLeft, .rightStickRight)
		]
		if pairs.contains(where: { buttons.contains($0.0) && buttons.contains($0.1) }) {
			return "Opposite directions cannot be held together."
		}
		if buttons.contains(where: { button in
			button.chordSequenceAlias.map { buttons.contains($0) } ?? false
		}) { return "Choose either the general control or its specific region." }
		return nil
	}

	private enum CodingKeys: String, CodingKey { case buttons }
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let decoded = try container.decode([ControllerButton].self, forKey: .buttons)
		self.init(Set(decoded))
		if let reason = validationMessage {
			throw DecodingError.dataCorruptedError(forKey: .buttons, in: container, debugDescription: reason)
		}
	}

	func matches(_ actual: SequenceStep) -> Bool {
		// Exact members take precedence, then one-to-one directional aliases.
		var remaining = Set(buttons)
		var unmatched: [ControllerButton] = []
		for button in actual.buttons {
			if remaining.remove(button) == nil { unmatched.append(button) }
		}
		for button in unmatched {
			guard let alias = button.chordSequenceAlias, remaining.remove(alias) != nil else { return false }
		}
		return remaining.isEmpty
	}
}
