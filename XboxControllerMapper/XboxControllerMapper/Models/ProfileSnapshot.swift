import Foundation

/// User-meaningful checkpoint of the entire profile configuration, captured
/// before destructive operations so the user can roll back via the Settings UI.
///
/// Distinct from `ConfigBackupService` auto-backups: those are a 5-deep ring
/// buffer rotated on every save (crash protection). Snapshots are explicit,
/// reason-tagged, retained longer (20-deep), and surfaced in the UI.
struct ProfileSnapshot: Identifiable, Equatable {
    /// Filename stem (no extension) — also acts as a stable id on disk.
    let id: String
    let timestamp: Date
    let reason: String
    let fileURL: URL
}

/// On-disk shape for a snapshot file. Wraps `ProfileConfiguration` with the
/// reason metadata so a single JSON file is self-describing.
struct SnapshotPayload: Codable {
    let reason: String
    let createdAt: Date
    let configuration: ProfileConfiguration

    private enum CodingKeys: String, CodingKey {
        case reason, createdAt, configuration
    }

    init(reason: String, createdAt: Date = Date(), configuration: ProfileConfiguration) {
        self.reason = reason
        self.createdAt = createdAt
        self.configuration = configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decode(.reason, default: "")
        createdAt = try container.decode(.createdAt, default: Date())
        configuration = try container.decode(ProfileConfiguration.self, forKey: .configuration)
    }
}
