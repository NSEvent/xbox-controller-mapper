import Foundation

struct ProfileLoadApplicationResult: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let activeProfileId: UUID?
}

enum ProfileLoadedDataApplicator {
    static func apply(loadedProfiles: [Profile], activeProfileId: UUID?) -> ProfileLoadApplicationResult? {
        let validProfiles = loadedProfiles.filter { $0.isValid() }
        guard !validProfiles.isEmpty else { return nil }

        let sortedProfiles = validProfiles.sorted { $0.createdAt < $1.createdAt }
        guard let activeProfileId,
              let activeProfile = sortedProfiles.first(where: { $0.id == activeProfileId }) else {
            return ProfileLoadApplicationResult(
                profiles: sortedProfiles,
                activeProfile: nil,
                activeProfileId: nil
            )
        }

        return ProfileLoadApplicationResult(
            profiles: sortedProfiles,
            activeProfile: activeProfile,
            activeProfileId: activeProfileId
        )
    }
}
