import Foundation
import Combine
import SwiftUI

/// Errors that can occur when importing profiles from the community repository
enum CommunityProfileError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode profile: \(error.localizedDescription)"
        }
    }
}

/// Represents a profile available in the community repository
struct CommunityProfileInfo: Identifiable, Decodable {
    let name: String
    let downloadURL: String

    var id: String { name }

    var displayName: String {
        name.replacingOccurrences(of: ".json", with: "")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "download_url"
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
    }
}

/// Manages profile persistence and selection
@MainActor
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var activeProfileId: UUID?
    @Published var uiScale: CGFloat = 1.0

    var onScreenKeyboardSettings: OnScreenKeyboardSettings {
        activeProfile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
    }

    private let fileManager = FileManager.default
    private let configURL: URL
    private let legacyConfigURL: URL
    private var loadSucceeded = false  // Track if initial load succeeded to prevent clobbering
    
    // Track previous app for restoration logic
    private var previousBundleId: String?
    private var profileIdBeforeBackground: UUID?
    
    private var cancellables = Set<AnyCancellable>()

    init(appMonitor: AppMonitor? = nil, configDirectoryOverride: URL? = nil) {
        let home = fileManager.homeDirectoryForCurrentUser

        // Allow tests to use an isolated temp config directory.
        if let configDirectoryOverride {
            let configDir = configDirectoryOverride
            configURL = configDir.appendingPathComponent("config.json")
            // Keep legacy path scoped to the same override to avoid reading user config in tests.
            legacyConfigURL = configURL
            createDirectoryIfNeeded(at: configDir)
        } else {
            // New location: ~/.controllerkeys/
            let configDir = home.appendingPathComponent(".controllerkeys", isDirectory: true)
            configURL = configDir.appendingPathComponent("config.json")

            // Legacy location: ~/.xbox-controller-mapper/ (for migration)
            let legacyConfigDir = home.appendingPathComponent(".xbox-controller-mapper", isDirectory: true)
            legacyConfigURL = legacyConfigDir.appendingPathComponent("config.json")
            createDirectoryIfNeeded(at: configDir)
        }
        loadConfiguration()
        loadCachedFavicons()

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
        
        // Initialize state for app switching
        self.previousBundleId = Bundle.main.bundleIdentifier
        self.profileIdBeforeBackground = activeProfileId
        
        if let appMonitor = appMonitor {
            setupAutoSwitching(with: appMonitor)
        }
    }
    
    private func setupAutoSwitching(with appMonitor: AppMonitor) {
        appMonitor.$frontmostBundleId
            .removeDuplicates()
            .dropFirst() // Skip initial value to avoid overriding manual selection on launch
            .sink { [weak self] bundleId in
                guard let self = self, let bundleId = bundleId else { return }
                self.handleAppChange(bundleId)
            }
            .store(in: &cancellables)
    }
    
    private func handleAppChange(_ bundleId: String) {
        let appBundleId = Bundle.main.bundleIdentifier

        // Handle switching BACK to the configuration app
        if bundleId == appBundleId {
            // Restore the profile we were editing before we switched away
            if let savedId = profileIdBeforeBackground,
               let profile = profiles.first(where: { $0.id == savedId }) {
                // Only restore if we are not already on it
                if activeProfileId != savedId {
                    #if DEBUG
                    print("🔄 Restoring editing profile: \(profile.name)")
                    #endif
                    setActiveProfile(profile)
                }
            }
            previousBundleId = bundleId
            return
        }
        
        // Handle switching AWAY from the configuration app
        if previousBundleId == appBundleId {
            // Save the current profile so we can restore it when we come back
            profileIdBeforeBackground = activeProfileId
        }
        
        previousBundleId = bundleId

        // Find profile linked to this app
        if let linkedProfile = profiles.first(where: { $0.linkedApps.contains(bundleId) }) {
            // Only switch if not already active
            if activeProfileId != linkedProfile.id {
                #if DEBUG
                print("🔄 Auto-switching to profile: \(linkedProfile.name) for app: \(bundleId)")
                #endif
                setActiveProfile(linkedProfile)
            }
            return
        }
        
        // No specific profile found, switch to default if we are currently in an auto-switched profile
        // OR always switch to default?
        // "Standard" behavior: Switch to default profile when entering an app that has no specific profile.
        if let defaultProfile = profiles.first(where: { $0.isDefault }) {
            if activeProfileId != defaultProfile.id {
                #if DEBUG
                print("🔄 Auto-switching to default profile for app: \(bundleId)")
                #endif
                setActiveProfile(defaultProfile)
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
            newProfile = Profile(
                name: name,
                onScreenKeyboardSettings: activeProfile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
            )
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

    // MARK: - Favicon Cache

    /// Load cached favicons for all website links in all profiles
    private func loadCachedFavicons() {
        for i in 0..<profiles.count {
            for j in 0..<profiles[i].onScreenKeyboardSettings.websiteLinks.count {
                let link = profiles[i].onScreenKeyboardSettings.websiteLinks[j]
                if link.faviconData == nil {
                    if let cached = FaviconCache.shared.loadCachedFavicon(for: link.url) {
                        profiles[i].onScreenKeyboardSettings.websiteLinks[j].faviconData = cached
                    }
                }
            }
        }

        // Update activeProfile reference
        if let activeId = activeProfileId,
           let profile = profiles.first(where: { $0.id == activeId }) {
            activeProfile = profile
        }

        // Trigger async refetch for any still-missing favicons
        refetchMissingFavicons()
    }

    /// Refetch favicons that are missing from cache
    private func refetchMissingFavicons() {
        struct MissingFaviconRequest {
            let profileId: UUID
            let linkId: UUID
            let url: String
        }

        let pendingRequests: [MissingFaviconRequest] = profiles.flatMap { profile in
            profile.onScreenKeyboardSettings.websiteLinks.compactMap { link in
                guard link.faviconData == nil else { return nil }
                return MissingFaviconRequest(profileId: profile.id, linkId: link.id, url: link.url)
            }
        }

        guard !pendingRequests.isEmpty else { return }

        Task { @MainActor in
            var anyUpdated = false

            for request in pendingRequests {
                if Task.isCancelled { break }

                guard let data = await FaviconCache.shared.fetchFavicon(for: request.url) else {
                    continue
                }

                guard let profileIndex = profiles.firstIndex(where: { $0.id == request.profileId }) else {
                    continue
                }
                guard let linkIndex = profiles[profileIndex]
                    .onScreenKeyboardSettings
                    .websiteLinks
                    .firstIndex(where: { $0.id == request.linkId }) else {
                    continue
                }

                if profiles[profileIndex].onScreenKeyboardSettings.websiteLinks[linkIndex].faviconData == nil {
                    profiles[profileIndex].onScreenKeyboardSettings.websiteLinks[linkIndex].faviconData = data
                    anyUpdated = true
                }
            }

            if anyUpdated {
                // Update activeProfile reference
                if let activeId = activeProfileId,
                   let profile = profiles.first(where: { $0.id == activeId }) {
                    activeProfile = profile
                }
                objectWillChange.send()
            }
        }
    }

    // MARK: - Persistence

    private struct Configuration: Codable {
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

            // Migrate legacy global keyboard settings into profiles
            if let legacyKeyboardSettings = config.onScreenKeyboardSettings {
                for i in 0..<self.profiles.count {
                    if self.profiles[i].onScreenKeyboardSettings.quickTexts.isEmpty &&
                       self.profiles[i].onScreenKeyboardSettings.toggleShortcutKeyCode == nil {
                        self.profiles[i].onScreenKeyboardSettings = legacyKeyboardSettings
                    }
                }
                if let activeId = self.activeProfileId,
                   let profile = self.profiles.first(where: { $0.id == activeId }) {
                    self.activeProfile = profile
                }
                didMigrate = true
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

    private func saveConfiguration() {
        // Safety check: don't save if load failed (to avoid clobbering existing config)
        guard loadSucceeded || !fileManager.fileExists(atPath: configURL.path) else {
            NSLog("[ProfileManager] Skipping save - config load failed earlier, refusing to clobber existing config")
            return
        }

        // Capture state for background save
        let config = Configuration(
            profiles: profiles,
            activeProfileId: activeProfileId,
            uiScale: uiScale
        )
        let configURL = self.configURL
        let fileManager = self.fileManager

        // Perform file I/O on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async {
            // Create backup before saving
            self.createBackupAsync(configURL: configURL, fileManager: fileManager)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            do {
                let data = try encoder.encode(config)
                try data.write(to: configURL)
            } catch {
                // Configuration save failed silently
            }
        }
    }

    /// Creates a backup of the config file (called from background thread)
    private nonisolated func createBackupAsync(configURL: URL, fileManager: FileManager) {
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

    // MARK: - Community Profiles

    private static let communityProfilesURL = "https://api.github.com/repos/NSEvent/xbox-controller-mapper/contents/community-profiles"

    /// Fetches the list of available community profiles from GitHub
    nonisolated func fetchCommunityProfiles() async throws -> [CommunityProfileInfo] {
        guard let url = URL(string: Self.communityProfilesURL) else {
            throw CommunityProfileError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw CommunityProfileError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommunityProfileError.invalidResponse
        }

        do {
            let allItems = try JSONDecoder().decode([CommunityProfileInfo].self, from: data)
            // Filter to only .json files
            return allItems.filter { $0.name.hasSuffix(".json") }
        } catch {
            throw CommunityProfileError.decodingError(error)
        }
    }

    /// Fetches a profile for preview without importing it
    nonisolated func fetchProfileForPreview(from urlString: String) async throws -> Profile {
        guard let url = URL(string: urlString) else {
            throw CommunityProfileError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw CommunityProfileError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommunityProfileError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(Profile.self, from: data)
        } catch {
            throw CommunityProfileError.decodingError(error)
        }
    }

    /// Imports a profile that was previously fetched (e.g., from preview cache)
    func importFetchedProfile(_ profile: Profile) -> Profile {
        var importedProfile = profile
        importedProfile.id = UUID()
        importedProfile.isDefault = false

        profiles.append(importedProfile)
        saveConfiguration()

        return importedProfile
    }

    /// Downloads and imports a profile from a URL
    nonisolated func downloadProfile(from urlString: String) async throws -> Profile {
        guard let url = URL(string: urlString) else {
            throw CommunityProfileError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw CommunityProfileError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommunityProfileError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var profile: Profile
        do {
            profile = try decoder.decode(Profile.self, from: data)
        } catch {
            throw CommunityProfileError.decodingError(error)
        }

        // Generate new ID to avoid conflicts
        profile.id = UUID()
        profile.isDefault = false

        await MainActor.run {
            profiles.append(profile)
            saveConfiguration()
        }

        return profile
    }
}
