import AppKit

/// Represents a file or directory entry for the directory navigator overlay
struct DirectoryEntry: Identifiable, Equatable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let icon: NSImage

    init(url: URL) {
        self.url = url
        self.id = url
        self.name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        self.isDirectory = values?.isDirectory ?? false
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (lhs: DirectoryEntry, rhs: DirectoryEntry) -> Bool {
        lhs.url == rhs.url
    }
}
