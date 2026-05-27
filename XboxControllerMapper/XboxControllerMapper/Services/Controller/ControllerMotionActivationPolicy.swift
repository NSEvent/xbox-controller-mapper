import Foundation

enum ControllerMotionActivationPolicy {
    /// `hasMotion` is true for any controller with gyroscope sensors.
    static func shouldEnableMotion(profile: Profile?, hasMotion: Bool) -> Bool {
        if Config.performanceForceMotionDisabled {
            return false
        }

        if Config.performanceForceLegacyAlwaysOnMotion {
            return hasMotion
        }

        guard hasMotion, let profile else { return false }

        if profile.joystickSettings.gyroAimingEnabled {
            return true
        }

        return profile.gestureMappings.contains(where: \.hasAction)
    }
}
