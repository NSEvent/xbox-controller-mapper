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

		targetProfile = ProfileAutomationReferencePolicy.removingReferences(
			to: script.id,
			kind: .script,
			from: targetProfile
		)
        targetProfile.scripts.removeAll { $0.id == script.id }

        updateProfile(targetProfile)

        // Clean up orphaned script state in the engine
        ServiceContainer.shared.mappingEngine.scriptEngine.removeState(for: script.id)
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
