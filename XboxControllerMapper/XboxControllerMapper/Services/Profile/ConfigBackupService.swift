import Foundation

struct ConfigBackupService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createBackupIfNeeded(for configURL: URL, maxBackups: Int = 5) {
        guard fileManager.fileExists(atPath: configURL.path) else { return }

        let backupDir = configURL
            .deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupURL = backupDir.appendingPathComponent("config_\(timestamp).json")

        try? fileManager.copyItem(at: configURL, to: backupURL)
        cleanupOldBackups(in: backupDir, maxBackups: maxBackups)
    }

    private func cleanupOldBackups(in backupDir: URL, maxBackups: Int) {
        guard let backups = try? fileManager.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return
        }

        let sortedBackups = backups
            .filter { $0.pathExtension == "json" }
            .sorted {
                (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast >
                (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            }

        for backup in sortedBackups.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: backup)
        }
    }
}
