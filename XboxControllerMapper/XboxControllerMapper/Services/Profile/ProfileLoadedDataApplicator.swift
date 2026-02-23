import Foundation

struct ProfileLoadApplicationResult: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let activeProfileId: UUID?
}

enum ProfileLoadedDataApplicator {
    static func apply(loadedProfiles: [Profile], activeProfileId: UUID?) -> ProfileLoadApplicationResult? {
        let validProfiles = loadedProfiles.filter { profile in
            let valid = profile.isValid()
            if !valid {
                let profileName = profile.name.isEmpty ? "unknown" : profile.name
                let hasEmptyName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let joystickValid = profile.joystickSettings.isValid()
                let ledValid = profile.dualSenseLEDSettings.isValid()
                var reasons: [String] = []
                if hasEmptyName { reasons.append("empty name") }
                if !joystickValid { reasons.append("invalid joystick settings") }
                if !ledValid { reasons.append("invalid LED settings") }
                NSLog("[ProfileLoadedDataApplicator] Dropping invalid profile '%@' (id: %@): %@",
                      profileName, profile.id.uuidString, reasons.joined(separator: ", "))
            }
            return valid
        }
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
