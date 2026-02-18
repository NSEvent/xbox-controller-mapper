import Foundation
import SwiftUI

struct ProfileConfiguration: Codable {
    var schemaVersion: Int = 1
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
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
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
