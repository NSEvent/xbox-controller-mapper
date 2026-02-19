import Foundation

@MainActor
extension ProfileManager {

    /// Apply a single recommendation to the active profile
    func applyRecommendation(_ recommendation: BindingRecommendation) {
        applyRecommendations([recommendation])
    }

    /// Apply multiple recommendations as a single batch (one save operation)
    func applyRecommendations(_ recommendations: [BindingRecommendation]) {
        guard var profile = activeProfile, !recommendations.isEmpty else { return }

        for recommendation in recommendations {
            applyToProfile(&profile, recommendation: recommendation)
        }

        updateProfile(profile)
    }

    // MARK: - Private

    private func applyToProfile(_ profile: inout Profile, recommendation: BindingRecommendation) {
        switch recommendation.type {
        case .swap(let button1, let button2):
            let mapping1 = profile.buttonMappings[button1]
            let mapping2 = profile.buttonMappings[button2]

            if let m2 = mapping2 {
                profile.buttonMappings[button1] = m2
            } else {
                profile.buttonMappings.removeValue(forKey: button1)
            }

            if let m1 = mapping1 {
                profile.buttonMappings[button2] = m1
            } else {
                profile.buttonMappings.removeValue(forKey: button2)
            }

        case .promoteToChord(let fromButton, let fromType, let toChordButtons, let keyCode, let modifiers):
            // Create the new chord
            let chord = ChordMapping(
                buttons: toChordButtons,
                keyCode: keyCode,
                modifiers: modifiers
            )
            profile.chordMappings.append(chord)

            // Clear the source sub-mapping
            if var mapping = profile.buttonMappings[fromButton] {
                switch fromType {
                case .longHold:
                    mapping.longHoldMapping = nil
                case .doubleTap:
                    mapping.doubleTapMapping = nil
                }
                profile.buttonMappings[fromButton] = mapping
            }

        case .demoteToLongHold(let button, let keyCode, let modifiers):
            if var mapping = profile.buttonMappings[button] {
                // Move primary action to long hold
                mapping.longHoldMapping = LongHoldMapping(
                    keyCode: keyCode,
                    modifiers: modifiers
                )
                // Clear primary action
                mapping.keyCode = nil
                mapping.modifiers = ModifierFlags()
                mapping.macroId = nil
                mapping.systemCommand = nil
                // Keep hint on the long hold, clear from primary
                if let hint = mapping.hint {
                    mapping.longHoldMapping?.hint = hint
                    mapping.hint = nil
                }
                profile.buttonMappings[button] = mapping
            }
        }
    }
}
