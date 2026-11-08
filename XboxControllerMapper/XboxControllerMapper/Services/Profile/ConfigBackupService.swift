import Foundation

struct ConfigBackupService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Saves arrive in bursts (every slider tick saves), so at most one backup
    /// is taken per `minimumInterval`. The backup that opens a burst holds the
    /// config from before it; backing up every save would let one drag push
    /// all older backups out of the ring.
    func createBackupIfNeeded(
        for configURL: URL,
        maxBackups: Int = 5,
        minimumInterval: TimeInterval = 60,
        now: Date = Date()
    ) {
        guard fileManager.fileExists(atPath: configURL.path) else { return }

        let backupDir = configURL
            .deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)

        if let newest = newestBackupDate(in: backupDir), now.timeIntervalSince(newest) < minimumInterval {
            return
        }

        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[ConfigBackup] Failed to create backup directory: %@", error.localizedDescription)
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: now)
        // Guards against a clock change landing on an existing name.
        var backupURL = backupDir.appendingPathComponent("config_\(timestamp).json")
        var suffix = 2
        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = backupDir.appendingPathComponent("config_\(timestamp)_\(suffix).json")
            suffix += 1
        }

        do {
            try AtomicFileWriter.copyResolvedItem(from: configURL, to: backupURL, fileManager: fileManager)
        } catch {
            NSLog("[ConfigBackup] Failed to copy config to backup: %@", error.localizedDescription)
        }

        cleanupOldBackups(in: backupDir, maxBackups: maxBackups)
    }

    private func newestBackupDate(in backupDir: URL) -> Date? {
        guard let backups = try? fileManager.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return nil }
        return backups
            .filter { $0.pathExtension == "json" }
            .compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
            .max()
    }

    private func cleanupOldBackups(in backupDir: URL, maxBackups: Int) {
        let backups: [URL]
        do {
            backups = try fileManager.contentsOfDirectory(
                at: backupDir,
                includingPropertiesForKeys: [.creationDateKey]
            )
        } catch {
            NSLog("[ConfigBackup] Failed to list backup directory: %@", error.localizedDescription)
            return
        }

        let sortedBackups = backups
            .filter { $0.pathExtension == "json" }
            .sorted {
                (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast >
                (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            }

        for backup in sortedBackups.dropFirst(maxBackups) {
            do {
                try fileManager.removeItem(at: backup)
            } catch {
                NSLog("[ConfigBackup] Failed to delete old backup %@: %@", backup.lastPathComponent, error.localizedDescription)
            }
        }
    }
}
