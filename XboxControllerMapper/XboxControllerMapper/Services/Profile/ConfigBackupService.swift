import Foundation

struct ConfigBackupService {
    private let fileManager: FileManager

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createBackupIfNeeded(for configURL: URL, maxBackups: Int = 5) {
        guard fileManager.fileExists(atPath: configURL.path) else { return }

        let backupDir = configURL
            .deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[ConfigBackup] Failed to create backup directory: %@", error.localizedDescription)
            return
        }

        let timestamp = Self.dateFormatter.string(from: Date())
        let backupURL = backupDir.appendingPathComponent("config_\(timestamp).json")

        do {
            try AtomicFileWriter.copyResolvedItem(from: configURL, to: backupURL, fileManager: fileManager)
        } catch {
            NSLog("[ConfigBackup] Failed to copy config to backup: %@", error.localizedDescription)
        }

        cleanupOldBackups(in: backupDir, maxBackups: maxBackups)
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
