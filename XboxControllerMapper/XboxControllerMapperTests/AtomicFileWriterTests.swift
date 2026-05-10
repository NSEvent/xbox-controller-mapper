import XCTest
@testable import ControllerKeys

final class AtomicFileWriterTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = .default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "controllerkeys-atomic-writer-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testDataWritePreservesSymlink() throws {
        let targetURL = tempDirectory.appendingPathComponent("target-data.json")
        let linkURL = tempDirectory.appendingPathComponent("link-data.json")
        try Data("old".utf8).write(to: targetURL)
        try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        try AtomicFileWriter.write(Data("new".utf8), to: linkURL)

        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: linkURL.path), targetURL.path)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "new")
    }

    func testStringWritePreservesSymlink() throws {
        let targetURL = tempDirectory.appendingPathComponent("target-string.txt")
        let linkURL = tempDirectory.appendingPathComponent("link-string.txt")
        try "old".write(to: targetURL, atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        try AtomicFileWriter.write("new", to: linkURL)

        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: linkURL.path), targetURL.path)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "new")
    }

    func testCopyResolvedItemCopiesFileInsteadOfSymlink() throws {
        let targetURL = tempDirectory.appendingPathComponent("target-copy.json")
        let linkURL = tempDirectory.appendingPathComponent("link-copy.json")
        let destinationURL = tempDirectory.appendingPathComponent("backup.json")
        try Data("payload".utf8).write(to: targetURL)
        try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        try AtomicFileWriter.copyResolvedItem(from: linkURL, to: destinationURL, fileManager: fileManager)

        XCTAssertThrowsError(try fileManager.destinationOfSymbolicLink(atPath: destinationURL.path))
        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "payload")
    }
}
