import Foundation

struct ProfileAutoSwitchState: Equatable {
    let previousBundleId: String?
    let profileIdBeforeBackground: UUID?
    let activeProfileId: UUID?
	var lastActiveProfileId: UUID? = nil
}

enum ProfileAutoSwitchReason: Equatable {
    case restoreEditingProfile
    case linkedApp(bundleId: String)
    case linkedController(displayName: String)
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
        state: ProfileAutoSwitchState,
        controllerIdentity: ControllerIdentity? = nil
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

		// Community imports may share an app link (e.g. basic Anki vs AnKing).
		// Honor the explicitly selected variant, including after visiting an
		// unrelated app, rather than silently choosing whichever was imported first.
		let linkedProfiles = profiles.filter { $0.linkedApps.contains(bundleId) }
		let preferredLinkedProfile = linkedProfiles.first { $0.id == state.activeProfileId }
			?? linkedProfiles.first { $0.id == profileIdBeforeBackground }
			// The editing bookmark is session-only, but the previous profile
			// survives restarting while an unrelated app has selected Default.
			?? linkedProfiles.first { $0.id == state.lastActiveProfileId }
			?? linkedProfiles.first
		if let linkedProfile = preferredLinkedProfile {
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

        if let controllerIdentity,
           let linkedProfile = resolveControllerProfile(
                identity: controllerIdentity,
                profiles: profiles
           ) {
            if state.activeProfileId == linkedProfile.profile.id {
                return ProfileAutoSwitchResult(
                    action: nil,
                    previousBundleId: bundleId,
                    profileIdBeforeBackground: profileIdBeforeBackground
                )
            }

            return ProfileAutoSwitchResult(
                action: ProfileAutoSwitchAction(
                    profileId: linkedProfile.profile.id,
                    reason: .linkedController(displayName: linkedProfile.binding.displayName)
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

    private static func resolveControllerProfile(
        identity: ControllerIdentity,
        profiles: [Profile]
    ) -> (profile: Profile, binding: ControllerProfileBinding)? {
        let exactMatches = profiles.compactMap { profile -> (Profile, ControllerProfileBinding)? in
            guard let binding = profile.linkedControllers.first(where: {
                $0.identity.exactMatches(identity)
            }) else { return nil }
            return (profile, binding)
        }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        let fallbackMatches = profiles.compactMap { profile -> (Profile, ControllerProfileBinding)? in
            guard let binding = profile.linkedControllers.first(where: {
                $0.identity.stableId == nil && $0.identity.fallbackId == identity.fallbackId
            }) else { return nil }
            return (profile, binding)
        }
        if fallbackMatches.count == 1 {
            return fallbackMatches[0]
        }

        if fallbackMatches.count > 1 {
            NSLog("[ProfileAutoSwitch] Ambiguous controller fallback match for %@", identity.fallbackId)
        }
        return nil
    }
}
