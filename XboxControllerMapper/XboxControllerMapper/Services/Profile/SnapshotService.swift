import Foundation

/// Persists user-meaningful profile checkpoints to `~/.controllerkeys/snapshots/`.
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
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Snapshot] Failed to write snapshot %@: %@", fileURL.lastPathComponent, error.localizedDescription)
            return nil
        }

        pruneOldSnapshots()

        return ProfileSnapshot(id: stem, timestamp: now, reason: reason, fileURL: fileURL)
    }

    /// All available snapshots, newest first.
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
                      let payload = try? decoder.decode(SnapshotPayload.self, from: data) else {
                    NSLog("[Snapshot] Skipping unreadable snapshot file %@", url.lastPathComponent)
                    return nil
                }
                let stem = url.deletingPathExtension().lastPathComponent
                return ProfileSnapshot(id: stem, timestamp: payload.createdAt, reason: payload.reason, fileURL: url)
            }
            .sorted { $0.timestamp > $1.timestamp }
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
