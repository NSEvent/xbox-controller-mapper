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
    @Published var onScreenKeyboardSettings = OnScreenKeyboardSettings()

    private let fileManager = FileManager.default
    private let configURL: URL
    private let legacyConfigURL: URL
    private var loadSucceeded = false  // Track if initial load succeeded to prevent clobbering

    init() {
        let home = fileManager.homeDirectoryForCurrentUser

        // New location: ~/.controllerkeys/
        let configDir = home.appendingPathComponent(".controllerkeys", isDirectory: true)
        configURL = configDir.appendingPathComponent("config.json")

        // Legacy location: ~/.xbox-controller-mapper/ (for migration)
        let legacyConfigDir = home.appendingPathComponent(".xbox-controller-mapper", isDirectory: true)
        legacyConfigURL = legacyConfigDir.appendingPathComponent("config.json")

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

    func setProfileIcon(_ profile: Profile, icon: String?) {
        var updatedProfile = profile
        updatedProfile.icon = icon
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

    // MARK: - On-Screen Keyboard Settings

    func updateOnScreenKeyboardSettings(_ settings: OnScreenKeyboardSettings) {
        onScreenKeyboardSettings = settings
        saveConfiguration()
    }

    func addQuickText(_ quickText: QuickText) {
        onScreenKeyboardSettings.quickTexts.append(quickText)
        saveConfiguration()
    }

    func removeQuickText(_ quickText: QuickText) {
        onScreenKeyboardSettings.quickTexts.removeAll { $0.id == quickText.id }
        saveConfiguration()
    }

    func updateQuickText(_ quickText: QuickText) {
        if let index = onScreenKeyboardSettings.quickTexts.firstIndex(where: { $0.id == quickText.id }) {
            onScreenKeyboardSettings.quickTexts[index] = quickText
        }
        saveConfiguration()
    }

    func moveQuickTexts(from source: IndexSet, to destination: Int) {
        onScreenKeyboardSettings.quickTexts.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }

    func setDefaultTerminalApp(_ appName: String) {
        onScreenKeyboardSettings.defaultTerminalApp = appName
        saveConfiguration()
    }

    func setTypingDelay(_ delay: Double) {
        onScreenKeyboardSettings.typingDelay = delay
        saveConfiguration()
    }

    // MARK: - App Bar Items

    func addAppBarItem(_ item: AppBarItem) {
        onScreenKeyboardSettings.appBarItems.append(item)
        saveConfiguration()
    }

    func removeAppBarItem(_ item: AppBarItem) {
        onScreenKeyboardSettings.appBarItems.removeAll { $0.id == item.id }
        saveConfiguration()
    }

    func moveAppBarItems(from source: IndexSet, to destination: Int) {
        onScreenKeyboardSettings.appBarItems.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }

    // MARK: - Website Links

    func addWebsiteLink(_ link: WebsiteLink) {
        onScreenKeyboardSettings.websiteLinks.append(link)
        saveConfiguration()
    }

    func removeWebsiteLink(_ link: WebsiteLink) {
        onScreenKeyboardSettings.websiteLinks.removeAll { $0.id == link.id }
        saveConfiguration()
    }

    func updateWebsiteLink(_ link: WebsiteLink) {
        if let index = onScreenKeyboardSettings.websiteLinks.firstIndex(where: { $0.id == link.id }) {
            onScreenKeyboardSettings.websiteLinks[index] = link
            saveConfiguration()
        }
    }

    func moveWebsiteLinks(from source: IndexSet, to destination: Int) {
        onScreenKeyboardSettings.websiteLinks.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }

    // MARK: - Persistence

    private struct Configuration: Codable {
        var schemaVersion: Int = 1
        var profiles: [Profile]
        var activeProfileId: UUID?
        var uiScale: CGFloat?
        var onScreenKeyboardSettings: OnScreenKeyboardSettings?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, profiles, activeProfileId, uiScale, onScreenKeyboardSettings
        }

        init(profiles: [Profile], activeProfileId: UUID?, uiScale: CGFloat?, onScreenKeyboardSettings: OnScreenKeyboardSettings?) {
            self.profiles = profiles
            self.activeProfileId = activeProfileId
            self.uiScale = uiScale
            self.onScreenKeyboardSettings = onScreenKeyboardSettings
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

    private func loadConfiguration() {
        // Determine which config file to load:
        // 1. New location (~/.controllerkeys/) takes priority
        // 2. Fall back to legacy location (~/.xbox-controller-mapper/) for migration
        let urlToLoad: URL
        var migratingFromLegacy = false

        if fileManager.fileExists(atPath: configURL.path) {
            urlToLoad = configURL
        } else if fileManager.fileExists(atPath: legacyConfigURL.path) {
            urlToLoad = legacyConfigURL
            migratingFromLegacy = true
            NSLog("[ProfileManager] Migrating config from legacy location: \(legacyConfigURL.path)")
        } else {
            return  // No config file exists yet
        }

        do {
            let data = try Data(contentsOf: urlToLoad)
            
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

            if let keyboardSettings = config.onScreenKeyboardSettings {
                self.onScreenKeyboardSettings = keyboardSettings
            }

            loadSucceeded = true  // Mark that we successfully loaded the config

            // Save to new location if migrating from legacy or if data migrations occurred
            if migratingFromLegacy || didMigrate {
                saveConfiguration()
                if migratingFromLegacy {
                    NSLog("[ProfileManager] Config migrated to new location: \(configURL.path)")
                }
            }
        } catch {
            NSLog("[ProfileManager] Configuration load failed: \(error)")
            // DO NOT set loadSucceeded = true, so we won't overwrite corrupted/incompatible config
        }
    }

    /// Creates a backup of the config file before saving
    private func createBackup() {
        guard fileManager.fileExists(atPath: configURL.path) else { return }

        let backupDir = configURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Keep last 5 backups with timestamps
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupURL = backupDir.appendingPathComponent("config_\(timestamp).json")

        try? fileManager.copyItem(at: configURL, to: backupURL)

        // Clean up old backups (keep only last 5)
        if let backups = try? fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey]) {
            let sortedBackups = backups
                .filter { $0.pathExtension == "json" }
                .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast >
                          (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast }

            for backup in sortedBackups.dropFirst(5) {
                try? fileManager.removeItem(at: backup)
            }
        }
    }

    private func saveConfiguration() {
        // Safety check: don't save if load failed (to avoid clobbering existing config)
        guard loadSucceeded || !fileManager.fileExists(atPath: configURL.path) else {
            NSLog("[ProfileManager] Skipping save - config load failed earlier, refusing to clobber existing config")
            return
        }

        // Create backup before saving
        createBackup()

        let config = Configuration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale,
            onScreenKeyboardSettings: onScreenKeyboardSettings
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
