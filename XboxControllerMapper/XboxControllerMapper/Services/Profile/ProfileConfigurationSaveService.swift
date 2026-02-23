import Foundation

struct ProfileConfigurationSaveService {
    private let fileManager: FileManager
    private let backupService: ConfigBackupService
    private let scheduleWrite: (@escaping () -> Void) -> Void
    private let logSaveFailure: (String) -> Void

    init(
        fileManager: FileManager = .default,
        backupService: ConfigBackupService? = nil,
        scheduleWrite: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.global(qos: .utility).async(execute: work)
        },
        logSaveFailure: @escaping (String) -> Void = { message in
            NSLog("%@", message)
        }
    ) {
        self.fileManager = fileManager
        self.backupService = backupService ?? ConfigBackupService(fileManager: fileManager)
        self.scheduleWrite = scheduleWrite
        self.logSaveFailure = logSaveFailure
    }

    func shouldSave(loadSucceeded: Bool, configURL: URL) -> Bool {
        loadSucceeded || !fileManager.fileExists(atPath: configURL.path)
    }

    func save(_ config: ProfileConfiguration, to configURL: URL) {
        scheduleWrite {
            backupService.createBackupIfNeeded(for: configURL)
            do {
                let data = try ProfileConfigurationCodec.encode(config)
                try data.write(to: configURL.resolvingSymlinksInPath(), options: .atomic)
            } catch {
                logSaveFailure("[ProfileManager] Configuration save failed: \(error.localizedDescription)")
            }
        }
    }
}
