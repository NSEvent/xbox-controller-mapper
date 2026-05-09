import Foundation
import SwiftUI

struct ProfileConfiguration: Codable {
    /// Current schema version. Bump this when making breaking changes to the config format.
    /// Version 1: Initial schema (all fields use decodeIfPresent with defaults).
    /// Version 2 (internal-only, never released): Touchpad quadrants promoted to
    ///            four first-class `ControllerButton` cases. Per-quadrant trigger
    ///            sense stored in `Profile.touchpadRegionTriggerModes`.
    /// Version 3: Touchpad quadrant cases split into `*Click` and `*Touch` variants
    ///            (8 total), restoring the legacy ability to assign separate
    ///            actions per trigger. A new `Profile.touchpadInputMode` field
    ///            picks between whole-pad mode (classic 4 buttons) and quadrants
    ///            mode (8 region buttons). Migration happens on load via
    ///            `Profile.rewriteV2QuadrantKeys` (decode-time, v2 → v3 key
    ///            rewrite) and `ProfileConfigurationMigrationService.migrateTouchpadRegionsToButtons`
    ///            (post-decode, v1 list → v3 buttons + mode flip).
    static let currentSchemaVersion = 3

    var schemaVersion: Int = currentSchemaVersion
    var profiles: [Profile]
    var activeProfileId: UUID?
    var uiScale: CGFloat?
    /// Legacy field: only decoded for migration to per-profile settings
    var onScreenKeyboardSettings: OnScreenKeyboardSettings?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profiles, activeProfileId, uiScale, onScreenKeyboardSettings
    }

    init(profiles: [Profile], activeProfileId: UUID?, uiScale: CGFloat?) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.uiScale = uiScale
        self.onScreenKeyboardSettings = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(.schemaVersion, default: 1)
        if schemaVersion > Self.currentSchemaVersion {
            NSLog("[ProfileConfiguration] Warning: config has schemaVersion %d but app only knows up to %d. Some settings may be lost or ignored.", schemaVersion, Self.currentSchemaVersion)
        }
        profiles = try container.decode(.profiles, default: [])
        activeProfileId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId)
        uiScale = try container.decodeIfPresent(CGFloat.self, forKey: .uiScale)
        onScreenKeyboardSettings = try container.decodeIfPresent(OnScreenKeyboardSettings.self, forKey: .onScreenKeyboardSettings)
    }
}

enum ProfileConfigurationCodec {
    static func decode(from data: Data) throws -> ProfileConfiguration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileConfiguration.self, from: data)
    }

    static func encode(_ configuration: ProfileConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }
}
