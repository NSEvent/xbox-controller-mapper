import Foundation
import Combine
import SwiftUI

/// Manages profile persistence and selection
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var activeProfileId: UUID?
    @Published var uiScale: CGFloat = 1.0

    private let fileManager = FileManager.default
    private let configURL: URL

    init() {
        // Create ~/.xbox-controller-mapper directory
        let home = fileManager.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".xbox-controller-mapper", isDirectory: true)
        configURL = configDir.appendingPathComponent("config.json")

        createDirectoryIfNeeded(at: configDir)
        loadConfiguration()

        // Create default profile if none exist
        if profiles.isEmpty {
            let defaultProfile = Profile.createDefault()
            profiles.append(defaultProfile)
            setActiveProfile(defaultProfile)
        } else if activeProfile == nil {
             if let defaultProfile = profiles.first(where: { $0.isDefault }) {
                setActiveProfile(defaultProfile)
            } else if let firstProfile = profiles.first {
                setActiveProfile(firstProfile)
            }
        }
    }

    private func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            // Directory creation failed, but we'll handle it gracefully
        }
    }
    
    // MARK: - UI Settings
    
    func setUiScale(_ scale: CGFloat) {
        uiScale = scale
        saveConfiguration()
    }

    // MARK: - Profile Management

    func createProfile(name: String, basedOn template: Profile? = nil) -> Profile {
        var newProfile: Profile
        if let template = template {
        newProfile = template
            newProfile.id = UUID()
            newProfile.name = name
            newProfile.isDefault = false
            newProfile.createdAt = Date()
            newProfile.modifiedAt = Date()
        } else {
            newProfile = Profile(name: name)
        }

        profiles.append(newProfile)
        saveConfiguration()
        return newProfile
    }

    func deleteProfile(_ profile: Profile) {
        // Don't delete the last profile
        guard profiles.count > 1 else { return }

        profiles.removeAll { $0.id == profile.id }
        saveConfiguration()

        // If we deleted the active profile, switch to another
        if activeProfileId == profile.id {
            if let firstProfile = profiles.first {
                setActiveProfile(firstProfile)
            }
        }
    }

    func duplicateProfile(_ profile: Profile) -> Profile {
        createProfile(name: "\(profile.name) Copy", basedOn: profile)
    }

    func updateProfile(_ profile: Profile) {
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        }

        saveConfiguration()

        if activeProfileId == profile.id {
            activeProfile = updatedProfile
        }
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfile = profile
        activeProfileId = profile.id
        saveConfiguration()
    }

    func renameProfile(_ profile: Profile, to newName: String) {
        var updatedProfile = profile
        updatedProfile.name = newName
        updateProfile(updatedProfile)
    }

    // MARK: - Button Mapping

    func setMapping(_ mapping: KeyMapping, for button: ControllerButton, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.buttonMappings[button] = mapping
        updateProfile(targetProfile)
    }

    func removeMapping(for button: ControllerButton, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.buttonMappings.removeValue(forKey: button)
        updateProfile(targetProfile)
    }

    func getMapping(for button: ControllerButton, in profile: Profile? = nil) -> KeyMapping? {
        let targetProfile = profile ?? activeProfile
        return targetProfile?.buttonMappings[button]
    }

    // MARK: - Chord Mapping

    func addChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.append(chord)
        updateProfile(targetProfile)
    }

    func removeChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.removeAll { $0.id == chord.id }
        updateProfile(targetProfile)
    }

    func updateChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.chordMappings.firstIndex(where: { $0.id == chord.id }) {
            targetProfile.chordMappings[index] = chord
        }
        updateProfile(targetProfile)
    }

    func moveChords(from source: IndexSet, to destination: Int, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.move(fromOffsets: source, toOffset: destination)
        updateProfile(targetProfile)
    }

    // MARK: - Joystick Settings

    func updateJoystickSettings(_ settings: JoystickSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.joystickSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - DualSense LED Settings

    func updateDualSenseLEDSettings(_ settings: DualSenseLEDSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.dualSenseLEDSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - Persistence

    private struct Configuration: Codable {
        var profiles: [Profile]
        var activeProfileId: UUID?
        var uiScale: CGFloat?
    }

    private func loadConfiguration() {
        // Check if file exists first to differentiate between "no config" and "read error"
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let config = try decoder.decode(Configuration.self, from: data)
            var didMigrate = false

            let migratedProfiles = config.profiles.map { profile in
                var updated = profile
                if updated.joystickSettings.touchpadSensitivity == 0.8 &&
                    updated.joystickSettings.touchpadAcceleration == 0.9 &&
                    updated.joystickSettings.touchpadDeadzone == 0.0 &&
                    updated.joystickSettings.touchpadSmoothing == 0.4 {
                    updated.joystickSettings.touchpadSensitivity = 0.5
                    updated.joystickSettings.touchpadAcceleration = 0.5
                    didMigrate = true
                } else if updated.joystickSettings.touchpadSensitivity == 0.5 &&
                            updated.joystickSettings.touchpadAcceleration == 0.5 &&
                            updated.joystickSettings.touchpadDeadzone == 0.01 &&
                            updated.joystickSettings.touchpadSmoothing == 0.4 {
                    updated.joystickSettings.touchpadDeadzone = 0.0
                    didMigrate = true
                }
                return updated
            }
            
            // Validation: Filter out invalid profiles
            let validProfiles = migratedProfiles.filter { $0.isValid() }
            
            if !validProfiles.isEmpty {
                self.profiles = validProfiles.sorted { $0.createdAt < $1.createdAt }
                
                if let activeId = config.activeProfileId,
                   let profile = profiles.first(where: { $0.id == activeId }) {
                    self.activeProfile = profile
                    self.activeProfileId = activeId
                } else {
                    self.activeProfile = nil
                    self.activeProfileId = nil
                }
            }
            
            if let scale = config.uiScale {
                self.uiScale = scale
            }
            
            if didMigrate {
                saveConfiguration()
            }
        } catch {
            // Configuration load failed, will use defaults
        }
    }

    private func saveConfiguration() {
        let config = Configuration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            // Configuration save failed silently
        }
    }

    // MARK: - Import/Export

    func exportProfile(_ profile: Profile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(profile)
        try data.write(to: url)
    }

    func importProfile(from url: URL) throws -> Profile {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var profile = try decoder.decode(Profile.self, from: data)

        // Generate new ID to avoid conflicts
        profile.id = UUID()
        profile.isDefault = false

        profiles.append(profile)
        saveConfiguration()

        return profile
    }
}
