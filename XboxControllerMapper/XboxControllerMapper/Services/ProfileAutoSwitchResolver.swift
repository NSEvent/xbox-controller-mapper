import Foundation

struct ProfileAutoSwitchState: Equatable {
    let previousBundleId: String?
    let profileIdBeforeBackground: UUID?
    let activeProfileId: UUID?
}

enum ProfileAutoSwitchReason: Equatable {
    case restoreEditingProfile
    case linkedApp(bundleId: String)
    case defaultProfile(bundleId: String)
}

struct ProfileAutoSwitchAction: Equatable {
    let profileId: UUID
    let reason: ProfileAutoSwitchReason
}

struct ProfileAutoSwitchResult: Equatable {
    let action: ProfileAutoSwitchAction?
    let previousBundleId: String?
    let profileIdBeforeBackground: UUID?
}

enum ProfileAutoSwitchResolver {
    static func resolve(
        bundleId: String,
        appBundleId: String?,
        profiles: [Profile],
        state: ProfileAutoSwitchState
    ) -> ProfileAutoSwitchResult {
        if bundleId == appBundleId {
            return resolveWhenReturningToConfigApp(
                bundleId: bundleId,
                profiles: profiles,
                state: state
            )
        }

        var profileIdBeforeBackground = state.profileIdBeforeBackground
        if state.previousBundleId == appBundleId {
            profileIdBeforeBackground = state.activeProfileId
        }

        if let linkedProfile = profiles.first(where: { $0.linkedApps.contains(bundleId) }) {
            if state.activeProfileId == linkedProfile.id {
                return ProfileAutoSwitchResult(
                    action: nil,
                    previousBundleId: bundleId,
                    profileIdBeforeBackground: profileIdBeforeBackground
                )
            }

            return ProfileAutoSwitchResult(
                action: ProfileAutoSwitchAction(
                    profileId: linkedProfile.id,
                    reason: .linkedApp(bundleId: bundleId)
                ),
                previousBundleId: bundleId,
                profileIdBeforeBackground: profileIdBeforeBackground
            )
        }

        if let defaultProfile = profiles.first(where: { $0.isDefault }),
           state.activeProfileId != defaultProfile.id {
            return ProfileAutoSwitchResult(
                action: ProfileAutoSwitchAction(
                    profileId: defaultProfile.id,
                    reason: .defaultProfile(bundleId: bundleId)
                ),
                previousBundleId: bundleId,
                profileIdBeforeBackground: profileIdBeforeBackground
            )
        }

        return ProfileAutoSwitchResult(
            action: nil,
            previousBundleId: bundleId,
            profileIdBeforeBackground: profileIdBeforeBackground
        )
    }

    private static func resolveWhenReturningToConfigApp(
        bundleId: String,
        profiles: [Profile],
        state: ProfileAutoSwitchState
    ) -> ProfileAutoSwitchResult {
        guard let savedProfileId = state.profileIdBeforeBackground,
              profiles.contains(where: { $0.id == savedProfileId }),
              state.activeProfileId != savedProfileId else {
            return ProfileAutoSwitchResult(
                action: nil,
                previousBundleId: bundleId,
                profileIdBeforeBackground: state.profileIdBeforeBackground
            )
        }

        return ProfileAutoSwitchResult(
            action: ProfileAutoSwitchAction(
                profileId: savedProfileId,
                reason: .restoreEditingProfile
            ),
            previousBundleId: bundleId,
            profileIdBeforeBackground: state.profileIdBeforeBackground
        )
    }
}
