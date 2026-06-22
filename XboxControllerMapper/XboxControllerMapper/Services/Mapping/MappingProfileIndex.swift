import Foundation

/// Profile-derived lookup tables used on the input queue. Keeping this as a
/// value type makes the expensive/semantic part of MappingEngine's profile sync
/// testable without constructing the engine.
struct MappingProfileIndex {
	let chordParticipantButtons: Set<ControllerButton>
	let sequenceParticipantButtons: Set<ControllerButton>
	let chordLookup: [Set<ControllerButton>: ChordMapping]
	let layersById: [UUID: Layer]
	let layerActivatorMap: [ControllerButton: UUID]

	init(profile: Profile?) {
		let chords = profile?.chordMappings ?? []
		chordParticipantButtons = Self.expandedParticipantButtons(for: chords.flatMap { $0.buttons })
		sequenceParticipantButtons = Self.expandedParticipantButtons(for: (profile?.sequenceMappings ?? []).flatMap { $0.steps })
		chordLookup = Dictionary(uniqueKeysWithValues: chords.map { ($0.buttons, $0) })
		layersById = Self.layersById(for: profile)
		layerActivatorMap = Self.layerActivatorMap(for: profile)
	}

	static func expandedParticipantButtons(for buttons: [ControllerButton]) -> Set<ControllerButton> {
		Set(buttons.flatMap { button in
			[button] + button.physicalEquivalentButtons
		})
	}

	private static func layersById(for profile: Profile?) -> [UUID: Layer] {
		Dictionary((profile?.layers ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
	}

	private static func layerActivatorMap(for profile: Profile?) -> [ControllerButton: UUID] {
		guard let profile else { return [:] }
		var result: [ControllerButton: UUID] = [:]
		for layer in profile.layers {
			if let activatorButton = layer.activatorButton {
				result[activatorButton] = layer.id
			}
		}
		return result
	}
}

extension MappingEngine.EngineState {
	/// Applies profile-derived caches. Caller MUST already hold `lock`.
	func applyProfileIndex(_ index: MappingProfileIndex) {
		chordParticipantButtons = index.chordParticipantButtons
		sequenceParticipantButtons = index.sequenceParticipantButtons
		chordLookup = index.chordLookup
		layersById = index.layersById
		layerActivatorMap = index.layerActivatorMap
	}
}
