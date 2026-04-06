import Foundation

enum ControllerMotionActivationPolicy {
    static func shouldEnableMotion(profile: Profile?, isDualSense: Bool) -> Bool {
        if Config.performanceForceMotionDisabled {
            return false
        }

        if Config.performanceForceLegacyAlwaysOnMotion {
            return isDualSense
        }

        guard isDualSense, let profile else { return false }

        if profile.joystickSettings.gyroAimingEnabled {
            return true
        }

        return profile.gestureMappings.contains(where: \.hasAction)
    }
}
