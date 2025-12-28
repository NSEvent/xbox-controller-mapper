import Foundation
import Combine

/// Manages profile persistence and selection
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var activeProfileId: UUID?

    private let fileManager = FileManager.default
    private let profilesDirectory: URL

    init() {
        // Create profiles directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        profilesDirectory = appSupport.appendingPathComponent("XboxControllerMapper/Profiles", isDirectory: true)

        createDirectoryIfNeeded()
        loadProfiles()

        // Create default profile if none exist
        if profiles.isEmpty {
            let defaultProfile = Profile.createDefault()
            profiles.append(defaultProfile)
            saveProfile(defaultProfile)
            setActiveProfile(defaultProfile)
        } else if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            setActiveProfile(defaultProfile)
        } else if let firstProfile = profiles.first {
            setActiveProfile(firstProfile)
        }
    }

    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create profiles directory: \(error)")
        }
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
        saveProfile(newProfile)
        return newProfile
    }

    func deleteProfile(_ profile: Profile) {
        // Don't delete the last profile
        guard profiles.count > 1 else { return }

        profiles.removeAll { $0.id == profile.id }

        // Delete file
        let fileURL = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)

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

        saveProfile(updatedProfile)

        if activeProfileId == profile.id {
            activeProfile = updatedProfile
        }
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfile = profile
        activeProfileId = profile.id

        // Save preference
        UserDefaults.standard.set(profile.id.uuidString, forKey: "activeProfileId")
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

    // MARK: - App Overrides

    func setAppOverride(_ mapping: KeyMapping, for button: ControllerButton, appBundleId: String, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if targetProfile.appOverrides[appBundleId] == nil {
            targetProfile.appOverrides[appBundleId] = [:]
        }
        targetProfile.appOverrides[appBundleId]?[button] = mapping
        updateProfile(targetProfile)
    }

    func removeAppOverride(for button: ControllerButton, appBundleId: String, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.appOverrides[appBundleId]?.removeValue(forKey: button)
        if targetProfile.appOverrides[appBundleId]?.isEmpty == true {
            targetProfile.appOverrides.removeValue(forKey: appBundleId)
        }
        updateProfile(targetProfile)
    }

    func getAppsWithOverrides(in profile: Profile? = nil) -> [String] {
        guard let targetProfile = profile ?? activeProfile else { return [] }
        return Array(targetProfile.appOverrides.keys)
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

    // MARK: - Joystick Settings

    func updateJoystickSettings(_ settings: JoystickSettings, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.joystickSettings = settings
        updateProfile(targetProfile)
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let files = try? fileManager.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        profiles = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Profile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Profile.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }

        // Restore active profile
        if let savedId = UserDefaults.standard.string(forKey: "activeProfileId"),
           let uuid = UUID(uuidString: savedId),
           let profile = profiles.first(where: { $0.id == uuid }) {
            activeProfile = profile
            activeProfileId = uuid
        }
    }

    private func saveProfile(_ profile: Profile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(profile)
            let fileURL = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
            try data.write(to: fileURL)
        } catch {
            print("Failed to save profile: \(error)")
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
        saveProfile(profile)

        return profile
    }
}
