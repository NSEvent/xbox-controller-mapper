import Foundation

struct TriggerMIDIConflict: Identifiable {
	enum Destination { case button(ControllerButton, UUID?), chord(ChordMapping), sequence(SequenceMapping), layer(Layer), precision }
	let id: String
	let description: String
	let destination: Destination

	static func find(in profile: Profile, side: JoystickSide) -> [TriggerMIDIConflict] {
		let trigger: ControllerButton = side == .left ? .leftTrigger : .rightTrigger
		var conflicts: [TriggerMIDIConflict] = []
		if profile.buttonMappings[trigger]?.hasConfiguredBehavior == true {
			conflicts.append(.init(id: "base", description: "A digital trigger mapping also runs in the base layer.", destination: .button(trigger, nil)))
		}
		for layer in profile.layers {
			if layer.buttonMappings[trigger]?.hasConfiguredBehavior == true {
				conflicts.append(.init(id: "mapping.\(layer.id)", description: "A digital trigger mapping also runs in \(layer.name).", destination: .button(trigger, layer.id)))
			}
			if layer.activatorButton == trigger {
				conflicts.append(.init(id: "layer.\(layer.id)", description: "This trigger activates the \(layer.name) layer.", destination: .layer(layer)))
			}
		}
		for chord in profile.chordMappings where chord.buttons.contains(trigger) {
			conflicts.append(.init(id: "chord.\(chord.id)", description: "This trigger is part of a chord: \(chord.hint ?? chord.displayString).", destination: .chord(chord)))
		}
		for sequence in profile.sequenceMappings where sequence.steps.contains(trigger) {
			conflicts.append(.init(id: "sequence.\(sequence.id)", description: "This trigger is part of a sequence: \(sequence.hint ?? sequence.displayString).", destination: .sequence(sequence)))
		}
		let precision = profile.joystickSettings.analogPrecisionTriggerMode
		if precision == .either || (side == .left && precision == .left) || (side == .right && precision == .right) {
			conflicts.append(.init(id: "precision", description: "This trigger also slows pointer and scroll movement.", destination: .precision))
		}
		return conflicts
	}
}
