import XCTest
import Foundation
@testable import ControllerKeys

@MainActor
final class GameControllerDatabaseTests: XCTestCase {
    private var tempRoot: URL!
    private static var retainedDatabases: [GameControllerDatabase] = []

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("game-controller-db-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testConstructGUID_UsesExpectedLittleEndianLayout() {
        let usbGUID = GameControllerDatabase.constructGUID(
            vendorID: 0x045e,
            productID: 0x028e,
            version: 0x0114,
            transport: nil
        )
        let bluetoothGUID = GameControllerDatabase.constructGUID(
            vendorID: 0x045e,
            productID: 0x028e,
            version: 0x0114,
            transport: "bluetooth"
        )

        XCTAssertEqual(usbGUID, "030000005e0400008e02000014010000")
        XCTAssertEqual(bluetoothGUID, "050000005e0400008e02000014010000")
    }

    func testLookupByDeviceProperties_FallsBackToVersionZeroMapping() {
        let guidV0 = GameControllerDatabase.constructGUID(
            vendorID: 0x045e,
            productID: 0x028e,
            version: 0,
            transport: nil
        )

        let content = [
            "# Comment",
            mappingLine(guid: guidV0, name: "Xbox Fallback", entries: [
                "a:b0",
                "b:b1",
                "leftx:a0",
                "lefty:~a1",
                "rightx:+a2",
                "dpup:h0.1"
            ])
        ].joined(separator: "\n")

        let database = GameControllerDatabase(databaseContentOverride: content)

        let mapping = database.lookup(vendorID: 0x045e, productID: 0x028e, version: 0x1234, transport: nil)
        XCTAssertNotNil(mapping)
        XCTAssertEqual(mapping?.name, "Xbox Fallback")

        if case let .button(index)? = mapping?.buttonMap["a"] {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Expected button mapping for SDL button a")
        }

        if case let .axis(index, inverted)? = mapping?.axisMap["lefty"] {
            XCTAssertEqual(index, 1)
            XCTAssertTrue(inverted)
        } else {
            XCTFail("Expected inverted axis mapping for lefty")
        }

        if case let .axis(index, inverted)? = mapping?.axisMap["rightx"] {
            XCTAssertEqual(index, 2)
            XCTAssertFalse(inverted)
        } else {
            XCTFail("Expected axis mapping for rightx")
        }

        if case let .hat(index, direction)? = mapping?.buttonMap["dpup"] {
            XCTAssertEqual(index, 0)
            XCTAssertEqual(direction, .up)
        } else {
            XCTFail("Expected hat mapping for dpup")
        }

        Self.retainedDatabases.append(database)

    }

    func testParsing_IgnoresCommentsNonMacEntriesAndInvalidGUIDs() {
        let validGUID = "030000005e0400008e02000000000000"
        let content = [
            "# ignored comment",
            "010203,too-short,a:b0,platform:Mac OS X,",
            "030000005e0400008e02000001000000,Windows Only,a:b0,platform:Windows,",
            mappingLine(guid: validGUID, name: "Valid Mac Mapping", entries: ["a:b0"])
        ].joined(separator: "\n")

        let database = GameControllerDatabase(databaseContentOverride: content)

        XCTAssertNotNil(database.lookup(guid: validGUID))
        XCTAssertNil(database.lookup(guid: "030000005e0400008e02000001000000"))

        Self.retainedDatabases.append(database)

    }

    func testDatabaseErrors_ExposeLocalizedDescriptions() {
        XCTAssertEqual(GameControllerDatabase.DatabaseError.downloadFailed.errorDescription,
                       "Failed to download controller database")
        XCTAssertEqual(GameControllerDatabase.DatabaseError.invalidData.errorDescription,
                       "Downloaded data is not valid UTF-8 text")
        XCTAssertEqual(GameControllerDatabase.DatabaseError.noMacOSEntries.errorDescription,
                       "No macOS controller entries found in database")
    }

    private func mappingLine(guid: String, name: String, entries: [String]) -> String {
        let body = entries.joined(separator: ",")
        return "\(guid),\(name),\(body),platform:Mac OS X,"
    }
}
