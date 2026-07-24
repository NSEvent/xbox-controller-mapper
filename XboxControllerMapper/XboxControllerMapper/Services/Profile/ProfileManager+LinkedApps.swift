import Foundation

@MainActor
extension ProfileManager {
    // MARK: - Linked Apps

    func addLinkedApp(_ bundleId: String, to profile: Profile) {
        // Remove this app from any other profiles first (enforce 1:1 mapping)
        for var otherProfile in profiles where otherProfile.id != profile.id {
            if let index = otherProfile.linkedApps.firstIndex(of: bundleId) {
                otherProfile.linkedApps.remove(at: index)
                updateProfile(otherProfile)
            }
        }

        var updatedProfile = profile
        if !updatedProfile.linkedApps.contains(bundleId) {
            updatedProfile.linkedApps.append(bundleId)
            updateProfile(updatedProfile)
        }
    }

    func removeLinkedApp(_ bundleId: String, from profile: Profile) {
        var updatedProfile = profile
        updatedProfile.linkedApps.removeAll { $0 == bundleId }
        updateProfile(updatedProfile)
    }

    // MARK: - Layer-Linked Apps

    func linkApp(_ bundleId: String, toLayer layerId: UUID, in profile: Profile) {
		guard profile.layers.contains(where: { $0.id == layerId }) else { return }
		var updatedProfile = profile
		updatedProfile.appLayerBindings[bundleId] = layerId
		updateProfile(updatedProfile)
    }

    func unlinkApp(_ bundleId: String, fromLayer layerId: UUID, in profile: Profile) {
		guard profile.appLayerBindings[bundleId] == layerId else { return }
		var updatedProfile = profile
		updatedProfile.appLayerBindings.removeValue(forKey: bundleId)
		updateProfile(updatedProfile)
    }
}
