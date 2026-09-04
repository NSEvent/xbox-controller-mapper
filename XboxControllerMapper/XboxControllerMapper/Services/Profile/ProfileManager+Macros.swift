import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    // MARK: - Macros

    func addMacro(_ macro: Macro, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.macros.append(macro)
        updateProfile(targetProfile)
    }

    func removeMacro(_ macro: Macro, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

		targetProfile = ProfileAutomationReferencePolicy.removingReferences(
			to: macro.id,
			kind: .macro,
			from: targetProfile
		)
        targetProfile.macros.removeAll { $0.id == macro.id }

        updateProfile(targetProfile)
    }

    func updateMacro(_ macro: Macro, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.macros.firstIndex(where: { $0.id == macro.id }) {
            targetProfile.macros[index] = macro
        }
        updateProfile(targetProfile)
    }

    func moveMacros(from source: IndexSet, to destination: Int, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.macros.move(fromOffsets: source, toOffset: destination)
        updateProfile(targetProfile)
    }
}
