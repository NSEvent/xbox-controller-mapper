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

    /// Promotes legacy v1 `Profile.touchpadRegionMappings` rows into the v3
    /// per-trigger first-class button cases (`*Click` and `*Touch`), and
    /// switches the profile's `touchpadInputMode` to `.quadrants` whenever any
    /// quadrant data is present.
    ///
    /// v2 configs (4 single-case quadrant keys + trigger-mode map) are handled
    /// at decode time inside `Profile.rewriteV2QuadrantKeys`. By the time
    /// profiles reach this function their v2 keys have already been unfolded
    /// into the v3 button mapping shape — this function only needs to drain
    /// the legacy v1 list and flip the mode.
    ///
    /// Per-region behavior:
    /// - `.click`-trigger entries → write to the `*Click` button case
    /// - `.touch`-trigger entries → write to the `*Touch` button case
    /// - `.both`-trigger entries → write to BOTH cases (KeyMapping duplicated;
    ///   users can edit them independently afterwards)
    /// - If a button mapping already exists for a target case (typical when v2
    ///   already populated it), the legacy entry is skipped without
    ///   overwriting.
    static func migrateTouchpadRegionsToButtons(in profiles: [Profile]) -> ([Profile], Bool) {
        var anyDidMigrate = false
        let migratedProfiles = profiles.map { profile -> Profile in
            var updated = profile
            var didMigrateThisProfile = false

            // Drain the legacy v1 array.
            for legacy in updated.touchpadRegionMappings where !legacy.isEmpty {
                let triggers: [TouchpadTriggerMode]
                switch legacy.triggerMode {
                case .both: triggers = [.click, .touch]
                case .click: triggers = [.click]
                case .touch: triggers = [.touch]
                }
                for trigger in triggers {
                    guard let buttonCase = ControllerButton.from(region: legacy.region, trigger: trigger) else { continue }
                    if updated.buttonMappings[buttonCase] != nil {
                        NSLog("[Migration] Skipping legacy %@ region %@ — a button mapping already exists for %@",
                              trigger.rawValue, legacy.region.rawValue, buttonCase.rawValue)
                        continue
                    }
                    updated.buttonMappings[buttonCase] = KeyMapping(
                        keyCode: legacy.keyCode,
                        modifiers: legacy.modifiers,
                        macroId: legacy.macroId,
                        systemCommand: legacy.systemCommand,
                        hint: legacy.hint
                    )
                    didMigrateThisProfile = true
                    anyDidMigrate = true
                }
            }

            // Only flip to quadrants when we actually drained v1 entries this
            // pass. v2-decoded profiles already had their mode inferred at
            // decode time via Profile.init(from:), and v3 profiles must keep
            // whatever mode the user explicitly saved — flipping based purely
            // on the presence of quadrant button mappings would clobber a
            // deliberate `.wholePad` choice every time the app reopens.
            if didMigrateThisProfile {
                let hasQuadrantData = updated.buttonMappings.keys.contains(where: { $0.isTouchpadQuadrant })
                if hasQuadrantData && updated.touchpadInputMode == .wholePad {
                    updated.touchpadInputMode = .quadrants
                    anyDidMigrate = true
                }
                updated.touchpadRegionMappings = []
            }
            return updated
        }
        return (migratedProfiles, anyDidMigrate)
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
