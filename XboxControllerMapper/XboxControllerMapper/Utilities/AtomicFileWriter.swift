import Foundation

enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    static func write(_ string: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        try string.write(to: url.resolvingSymlinksInPath(), atomically: true, encoding: encoding)
    }

    static func copyResolvedItem(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.copyItem(at: sourceURL.resolvingSymlinksInPath(), to: destinationURL)
    }
}
