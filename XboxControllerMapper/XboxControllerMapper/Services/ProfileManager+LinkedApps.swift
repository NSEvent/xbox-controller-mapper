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
}
