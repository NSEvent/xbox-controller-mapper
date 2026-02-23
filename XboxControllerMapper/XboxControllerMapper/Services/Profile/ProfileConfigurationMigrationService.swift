import Foundation

struct ProfileLegacyKeyboardMigrationResult: Equatable {
    let profiles: [Profile]
    let activeProfile: Profile?
    let didMigrate: Bool
}

enum ProfileConfigurationMigrationService {
    private static func approxEqual(_ a: Double, _ b: Double, epsilon: Double = 0.0001) -> Bool {
        abs(a - b) < epsilon
    }

    static func migrateTouchpadSettingsIfNeeded(in profiles: [Profile]) -> ([Profile], Bool) {
        var didMigrate = false
        let migratedProfiles = profiles.map { profile in
            var updated = profile
            if approxEqual(updated.joystickSettings.touchpadSensitivity, 0.8) &&
                approxEqual(updated.joystickSettings.touchpadAcceleration, 0.9) &&
                approxEqual(updated.joystickSettings.touchpadDeadzone, 0.0) &&
                approxEqual(updated.joystickSettings.touchpadSmoothing, 0.4) {
                updated.joystickSettings.touchpadSensitivity = 0.5
                updated.joystickSettings.touchpadAcceleration = 0.5
                didMigrate = true
            } else if approxEqual(updated.joystickSettings.touchpadSensitivity, 0.5) &&
                        approxEqual(updated.joystickSettings.touchpadAcceleration, 0.5) &&
                        approxEqual(updated.joystickSettings.touchpadDeadzone, 0.01) &&
                        approxEqual(updated.joystickSettings.touchpadSmoothing, 0.4) {
                updated.joystickSettings.touchpadDeadzone = 0.0
                didMigrate = true
            }
            return updated
        }
        return (migratedProfiles, didMigrate)
    }

    static func migrateLegacyKeyboardSettings(
        _ legacyKeyboardSettings: OnScreenKeyboardSettings,
        in profiles: [Profile],
        activeProfileId: UUID?
    ) -> ProfileLegacyKeyboardMigrationResult {
        var updatedProfiles = profiles
        for i in 0..<updatedProfiles.count {
            if updatedProfiles[i].onScreenKeyboardSettings.quickTexts.isEmpty &&
               updatedProfiles[i].onScreenKeyboardSettings.toggleShortcutKeyCode == nil {
                updatedProfiles[i].onScreenKeyboardSettings = legacyKeyboardSettings
            }
        }

        let activeProfile = activeProfileId.flatMap { id in
            updatedProfiles.first(where: { $0.id == id })
        }

        // Preserve existing behavior: presence of legacy field counts as migration.
        return ProfileLegacyKeyboardMigrationResult(
            profiles: updatedProfiles,
            activeProfile: activeProfile,
            didMigrate: true
        )
    }
}
