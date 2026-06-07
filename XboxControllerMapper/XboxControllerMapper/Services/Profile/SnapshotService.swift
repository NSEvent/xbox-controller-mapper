import Foundation

/// Persists user-meaningful profile checkpoints under the ControllerKeys config directory.
/// Separate from `ConfigBackupService` auto-backups: this store is reason-tagged,
/// retained longer (20-deep), and surfaced in the Settings UI.
struct SnapshotService {
    private let fileManager: FileManager
    private let snapshotsDirectory: URL
    private let maxSnapshots: Int

    /// Millisecond precision so back-to-back snapshots (e.g. "before restore"
    /// followed immediately by the restore loading the original file) don't
    /// collide on the same filename and clobber each other.
    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(snapshotsDirectory: URL, fileManager: FileManager = .default, maxSnapshots: Int = 20) {
        self.fileManager = fileManager
        self.snapshotsDirectory = snapshotsDirectory
        self.maxSnapshots = maxSnapshots
    }

    /// Encode `configuration` and write it as a new snapshot. Returns the
    /// resulting `ProfileSnapshot`, or nil if the directory could not be
    /// prepared or the write failed (errors are logged via NSLog).
    @discardableResult
    func writeSnapshot(_ configuration: ProfileConfiguration, reason: String, now: Date = Date()) -> ProfileSnapshot? {
        do {
            try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("[Snapshot] Failed to create snapshots directory: %@", error.localizedDescription)
            return nil
        }

        let stem = "snapshot_" + Self.filenameDateFormatter.string(from: now)
        let fileURL = snapshotsDirectory.appendingPathComponent("\(stem).json")
        let payload = SnapshotPayload(reason: reason, createdAt: now, configuration: configuration)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try AtomicFileWriter.write(data, to: fileURL)
        } catch {
            NSLog("[Snapshot] Failed to write snapshot %@: %@", fileURL.lastPathComponent, error.localizedDescription)
            return nil
        }

        pruneOldSnapshots()

        return ProfileSnapshot(id: stem, timestamp: now, reason: reason, fileURL: fileURL)
    }

    /// Lightweight projection used for listing snapshots without paying the
    /// cost of decoding the full ProfileConfiguration tree (which can include
    /// many profiles × many mappings × many macros). JSONDecoder ignores keys
    /// not present here, so reading from a SnapshotPayload-shaped file works.
    private struct SnapshotMetadata: Decodable {
        let reason: String
        let createdAt: Date

        private enum CodingKeys: String, CodingKey {
            case reason, createdAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reason = try c.decode(.reason, default: "")
            createdAt = try c.decode(.createdAt, default: Date())
        }
    }

    /// All available snapshots, newest first. Reads only the `reason` and
    /// `createdAt` metadata from each file — the heavy `ProfileConfiguration`
    /// payload is loaded lazily by `loadConfiguration(from:)` only on restore.
    func listSnapshots() -> [ProfileSnapshot] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("snapshot_") }
            .compactMap { url -> ProfileSnapshot? in
                guard let data = try? Data(contentsOf: url),
                      let metadata = try? decoder.decode(SnapshotMetadata.self, from: data) else {
                    NSLog("[Snapshot] Skipping unreadable snapshot file %@", url.lastPathComponent)
                    return nil
                }
                let stem = url.deletingPathExtension().lastPathComponent
                return ProfileSnapshot(id: stem, timestamp: metadata.createdAt, reason: metadata.reason, fileURL: url)
            }
            .sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp > $1.timestamp
                }
                return $0.id > $1.id
            }
    }

    /// Decode the snapshot file and return its captured configuration.
    func loadConfiguration(from snapshot: ProfileSnapshot) throws -> ProfileConfiguration {
        let data = try Data(contentsOf: snapshot.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(SnapshotPayload.self, from: data)
        return payload.configuration
    }

    private func pruneOldSnapshots() {
        let snapshots = listSnapshots()
        guard snapshots.count > maxSnapshots else { return }
        for snapshot in snapshots.dropFirst(maxSnapshots) {
            do {
                try fileManager.removeItem(at: snapshot.fileURL)
            } catch {
                NSLog("[Snapshot] Failed to delete old snapshot %@: %@", snapshot.fileURL.lastPathComponent, error.localizedDescription)
            }
        }
    }
}
