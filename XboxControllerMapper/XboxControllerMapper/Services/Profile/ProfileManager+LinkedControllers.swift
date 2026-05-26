import Foundation

@MainActor
extension ProfileManager {
    func bindController(_ identity: ControllerIdentity, to profile: Profile) {
        let binding = ControllerProfileBinding(
            displayName: identity.displayName,
            identity: identity,
            lastSeenAt: Date()
        )
        bindController(binding, to: profile)
    }

    func bindController(_ binding: ControllerProfileBinding, to profile: Profile) {
        for var otherProfile in profiles where otherProfile.id != profile.id {
            let originalCount = otherProfile.linkedControllers.count
            otherProfile.linkedControllers.removeAll { existing in
                existing.identity.matches(binding.identity)
            }
            if otherProfile.linkedControllers.count != originalCount {
                updateProfile(otherProfile)
            }
        }

        var updatedProfile = profile
        updatedProfile.linkedControllers.removeAll { existing in
            existing.identity.matches(binding.identity)
        }
        updatedProfile.linkedControllers.append(binding)
        updateProfile(updatedProfile)
    }

    func removeLinkedController(_ bindingId: UUID, from profile: Profile) {
        var updatedProfile = profile
        updatedProfile.linkedControllers.removeAll { $0.id == bindingId }
        updateProfile(updatedProfile)
    }

    func setInputLatencyMode(_ mode: InputLatencyMode, for profile: Profile) {
        var updatedProfile = profile
        updatedProfile.inputLatencyMode = mode
        updateProfile(updatedProfile)
    }
}
