import Foundation

enum LayerAppLinkResult: Equatable {
	case linked
	case profileConflict(profileName: String)
	case invalidLayer
}

@MainActor
extension ProfileManager {
    // MARK: - Linked Apps

    func addLinkedApp(_ bundleId: String, to profile: Profile) {
		guard var updatedProfile = profiles.first(where: { $0.id == profile.id }) else { return }

		// Full-profile links own routing for this app. Remove stale full-profile
		// and app-layer links from every other profile, while preserving a layer
		// binding inside the destination profile (profile resolves, then layer).
        for var otherProfile in profiles where otherProfile.id != profile.id {
			let previousLinkedApps = otherProfile.linkedApps
			let removedLayerBinding = otherProfile.appLayerBindings.removeValue(forKey: bundleId) != nil
			otherProfile.linkedApps.removeAll { $0 == bundleId }
			if otherProfile.linkedApps != previousLinkedApps || removedLayerBinding {
                updateProfile(otherProfile)
            }
        }

        if !updatedProfile.linkedApps.contains(bundleId) {
            updatedProfile.linkedApps.append(bundleId)
            updateProfile(updatedProfile)
        }
    }

    func removeLinkedApp(_ bundleId: String, from profile: Profile) {
		guard var updatedProfile = profiles.first(where: { $0.id == profile.id }) else { return }
        updatedProfile.linkedApps.removeAll { $0 == bundleId }
        updateProfile(updatedProfile)
    }

    // MARK: - Layer-Linked Apps

	@discardableResult
    func linkApp(_ bundleId: String, toLayer layerId: UUID, in profile: Profile) -> LayerAppLinkResult {
		guard let storedProfile = profiles.first(where: { $0.id == profile.id }),
			  storedProfile.layers.contains(where: { $0.id == layerId }) else {
			return .invalidLayer
		}
		if let conflict = fullProfileLinkConflict(for: bundleId, excluding: storedProfile.id) {
			return .profileConflict(profileName: conflict.name)
		}

		var updatedProfile = storedProfile
		updatedProfile.appLayerBindings[bundleId] = layerId
		updateProfile(updatedProfile)
		return .linked
    }

    func unlinkApp(_ bundleId: String, fromLayer layerId: UUID, in profile: Profile) {
		guard var updatedProfile = profiles.first(where: { $0.id == profile.id }),
			  updatedProfile.appLayerBindings[bundleId] == layerId else {
			return
		}
		updatedProfile.appLayerBindings.removeValue(forKey: bundleId)
		updateProfile(updatedProfile)
    }

	func fullProfileLinkConflict(for bundleId: String, excluding profileId: UUID) -> Profile? {
		profiles.first {
			$0.id != profileId && $0.linkedApps.contains(bundleId)
		}
	}
}
