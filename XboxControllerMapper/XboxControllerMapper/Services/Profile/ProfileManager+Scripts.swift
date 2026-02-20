import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    // MARK: - Scripts

    func addScript(_ script: Script, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.scripts.append(script)
        updateProfile(targetProfile)
    }

    func removeScript(_ script: Script, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        // Remove script from list
        targetProfile.scripts.removeAll { $0.id == script.id }

        // Unmap any buttons using this script (including longHold and doubleTap sub-mappings)
        for (button, mapping) in targetProfile.buttonMappings {
            var updated = mapping
            var changed = false

            if updated.scriptId == script.id {
                targetProfile.buttonMappings.removeValue(forKey: button)
                continue
            }
            if updated.longHoldMapping?.scriptId == script.id {
                updated.longHoldMapping = nil
                changed = true
            }
            if updated.doubleTapMapping?.scriptId == script.id {
                updated.doubleTapMapping = nil
                changed = true
            }
            if changed {
                targetProfile.buttonMappings[button] = updated
            }
        }

        // Unmap any chords using this script
        targetProfile.chordMappings = targetProfile.chordMappings.map { chord in
            var updatedChord = chord
            if updatedChord.scriptId == script.id {
                updatedChord.scriptId = nil
            }
            return updatedChord
        }

        // Unmap any sequences using this script
        targetProfile.sequenceMappings = targetProfile.sequenceMappings.map { seq in
            var updatedSeq = seq
            if updatedSeq.scriptId == script.id {
                updatedSeq.scriptId = nil
            }
            return updatedSeq
        }

        // Clean up layer button mappings too
        for i in targetProfile.layers.indices {
            for (button, mapping) in targetProfile.layers[i].buttonMappings {
                var updated = mapping
                var changed = false

                if updated.scriptId == script.id {
                    targetProfile.layers[i].buttonMappings.removeValue(forKey: button)
                    continue
                }
                if updated.longHoldMapping?.scriptId == script.id {
                    updated.longHoldMapping = nil
                    changed = true
                }
                if updated.doubleTapMapping?.scriptId == script.id {
                    updated.doubleTapMapping = nil
                    changed = true
                }
                if changed {
                    targetProfile.layers[i].buttonMappings[button] = updated
                }
            }
        }

        updateProfile(targetProfile)
    }

    func updateScript(_ script: Script, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.scripts.firstIndex(where: { $0.id == script.id }) {
            targetProfile.scripts[index] = script
        }
        updateProfile(targetProfile)
    }

    func moveScripts(from source: IndexSet, to destination: Int, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.scripts.move(fromOffsets: source, toOffset: destination)
        updateProfile(targetProfile)
    }
}
