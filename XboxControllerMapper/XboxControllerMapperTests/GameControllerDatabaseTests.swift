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
	let bluetoothLowEnergyGUID = GameControllerDatabase.constructGUID(
		vendorID: 0x045e,
		productID: 0x028e,
		version: 0x0114,
		transport: "Bluetooth Low Energy"
	)

        XCTAssertEqual(usbGUID, "030000005e0400008e02000014010000")
        XCTAssertEqual(bluetoothGUID, "050000005e0400008e02000014010000")
	XCTAssertEqual(bluetoothLowEnergyGUID, "050000005e0400008e02000014010000")
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
		"rightx:a2",
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

	if case let .axis(index, inverted, polarity)? = mapping?.axisMap["lefty"] {
            XCTAssertEqual(index, 1)
            XCTAssertTrue(inverted)
	    XCTAssertEqual(polarity, .full)
        } else {
            XCTFail("Expected inverted axis mapping for lefty")
        }

	if case let .axis(index, inverted, polarity)? = mapping?.axisMap["rightx"] {
            XCTAssertEqual(index, 2)
            XCTAssertFalse(inverted)
	    XCTAssertEqual(polarity, .full)
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

	func testLookupByDeviceProperties_FallsBackToNonMacMappingForSameVendorProduct() {
		let windowsGuid = GameControllerDatabase.constructGUID(
			vendorID: 0x248a,
			productID: 0x8266,
			version: 0,
			transport: nil
		)
		let content = mappingLine(
			guid: windowsGuid,
			name: "R1 Mobile Controller",
			entries: [
				"a:b3",
				"b:b1",
				"leftx:a0",
				"lefty:a1"
			],
			platform: "Windows"
		)
		let database = GameControllerDatabase(databaseContentOverride: content)

		let mapping = database.lookup(
			vendorID: 0x248a,
			productID: 0x8266,
			version: 12,
			transport: "Bluetooth Low Energy"
		)

		XCTAssertEqual(mapping?.name, "R1 Mobile Controller")
		if case let .button(index)? = mapping?.buttonMap["a"] {
			XCTAssertEqual(index, 3)
		} else {
			XCTFail("Expected Windows fallback button mapping for R1")
		}

		Self.retainedDatabases.append(database)
	}

	func testParsing_PreservesAxisButtonPolarity() {
		let guid = GameControllerDatabase.constructGUID(
			vendorID: 0x1234,
			productID: 0xabcd,
			version: 0,
			transport: nil
		)
		let content = mappingLine(
			guid: guid,
			name: "Axis DPad Controller",
			entries: [
				"dpup:-a1",
				"dpdown:+a1",
				"lefttrigger:+a2",
				"righttrigger:-a2",
				"lefty:~a1",
				"righty:a3~",
				"+rightx:+a3",
				"-rightx:-a4"
			]
		)
		let database = GameControllerDatabase(databaseContentOverride: content)
		let mapping = database.lookup(guid: guid)

		if case let .axis(index, inverted, polarity)? = mapping?.buttonMap["dpup"] {
			XCTAssertEqual(index, 1)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .negative)
		} else {
			XCTFail("Expected negative axis button mapping for dpup")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.buttonMap["dpdown"] {
			XCTAssertEqual(index, 1)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .positive)
		} else {
			XCTFail("Expected positive axis button mapping for dpdown")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["lefttrigger"] {
			XCTAssertEqual(index, 2)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .positive)
		} else {
			XCTFail("Expected positive half-axis trigger mapping for lefttrigger")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["righttrigger"] {
			XCTAssertEqual(index, 2)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .negative)
		} else {
			XCTFail("Expected negative half-axis trigger mapping for righttrigger")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["lefty"] {
			XCTAssertEqual(index, 1)
			XCTAssertTrue(inverted)
			XCTAssertEqual(polarity, .full)
		} else {
			XCTFail("Expected inverted stick axis mapping for lefty")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["righty"] {
			XCTAssertEqual(index, 3)
			XCTAssertTrue(inverted)
			XCTAssertEqual(polarity, .full)
		} else {
			XCTFail("Expected suffix-inverted stick axis mapping for righty")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["+rightx"] {
			XCTAssertEqual(index, 3)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .positive)
		} else {
			XCTFail("Expected positive split-output stick axis mapping for rightx")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["-rightx"] {
			XCTAssertEqual(index, 4)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .negative)
		} else {
			XCTFail("Expected negative split-output stick axis mapping for rightx")
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

    func testKnownVendorProductPairs_DecodesDedupesAndExcludesVendors() {
        let xboxGUID = GameControllerDatabase.constructGUID(
            vendorID: 0x045e,
            productID: 0x028e,
            version: 0,
            transport: nil
        )
        let duplicateXboxGUID = GameControllerDatabase.constructGUID(
            vendorID: 0x045e,
            productID: 0x028e,
            version: 0x0114,
            transport: nil
        )
        let genericGUID = GameControllerDatabase.constructGUID(
            vendorID: 0x1234,
            productID: 0xabcd,
            version: 0,
            transport: nil
        )
        let content = [
            mappingLine(guid: xboxGUID, name: "Xbox", entries: ["a:b0"]),
            mappingLine(guid: duplicateXboxGUID, name: "Xbox Duplicate", entries: ["a:b0"]),
	    mappingLine(guid: genericGUID, name: "Generic", entries: ["a:b0"], platform: "Windows")
        ].joined(separator: "\n")

        let database = GameControllerDatabase(databaseContentOverride: content)

        let pairs = database.knownVendorProductPairs(excludingVendors: [0x045e])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.vendorID, 0x1234)
        XCTAssertEqual(pairs.first?.productID, 0xabcd)

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

	func testGenericHIDInferredMapping_RequiresControllerShape() {
		XCTAssertNil(GenericHIDController.inferredMapping(
			buttonCount: 3,
			axisCount: 2,
			hasHat: false,
			name: "Keyboard-ish HID"
		))
		XCTAssertNil(GenericHIDController.inferredMapping(
			buttonCount: 4,
			axisCount: 2,
			hasHat: false,
			name: "Mouse-ish HID"
		))
	}

	func testGenericHIDInferredMapping_ProvidesUsableDefaultLayout() {
		let mapping = GenericHIDController.inferredMapping(
			buttonCount: 8,
			axisCount: 4,
			hasHat: true,
			name: "Unknown Gamepad"
		)

		XCTAssertEqual(mapping?.name, "Unknown Gamepad")
		if case let .button(index)? = mapping?.buttonMap["a"] {
			XCTAssertEqual(index, 0)
		} else {
			XCTFail("Expected inferred A button")
		}
		if case let .axis(index, inverted, polarity)? = mapping?.axisMap["righty"] {
			XCTAssertEqual(index, 3)
			XCTAssertFalse(inverted)
			XCTAssertEqual(polarity, .full)
		} else {
			XCTFail("Expected inferred right stick Y axis")
		}
		if case let .hat(index, direction)? = mapping?.buttonMap["dpup"] {
			XCTAssertEqual(index, 0)
			XCTAssertEqual(direction, .up)
		} else {
			XCTFail("Expected inferred d-pad hat mapping")
		}
	}

	func testGenericHIDHatTranslation_SupportsCommonEncodings() {
		XCTAssertEqual(GenericHIDController.hatValueToBits(0, logicalMin: 0, logicalMax: 7), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(2, logicalMin: 0, logicalMax: 7), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(4, logicalMin: 0, logicalMax: 7), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(6, logicalMin: 0, logicalMax: 7), 8)
		XCTAssertEqual(GenericHIDController.hatValueToBits(8, logicalMin: 0, logicalMax: 7), -1)

		XCTAssertEqual(GenericHIDController.hatValueToBits(0, logicalMin: 0, logicalMax: 8), -1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(1, logicalMin: 0, logicalMax: 8), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(3, logicalMin: 0, logicalMax: 8), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(5, logicalMin: 0, logicalMax: 8), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(7, logicalMin: 0, logicalMax: 8), 8)

		XCTAssertEqual(GenericHIDController.hatValueToBits(0, logicalMin: 0, logicalMax: 3), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(1, logicalMin: 0, logicalMax: 3), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(2, logicalMin: 0, logicalMax: 3), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(3, logicalMin: 0, logicalMax: 3), 8)

		XCTAssertEqual(GenericHIDController.hatValueToBits(0, logicalMin: 0, logicalMax: 4), -1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(1, logicalMin: 0, logicalMax: 4), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(2, logicalMin: 0, logicalMax: 4), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(3, logicalMin: 0, logicalMax: 4), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(4, logicalMin: 0, logicalMax: 4), 8)

		XCTAssertEqual(GenericHIDController.hatValueToBits(1, logicalMin: 1, logicalMax: 8), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(3, logicalMin: 1, logicalMax: 8), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(5, logicalMin: 1, logicalMax: 8), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(7, logicalMin: 1, logicalMax: 8), 8)
		XCTAssertEqual(GenericHIDController.hatValueToBits(0, logicalMin: 1, logicalMax: 8), -1)

		XCTAssertEqual(GenericHIDController.hatValueToBits(1, logicalMin: 1, logicalMax: 4), 1)
		XCTAssertEqual(GenericHIDController.hatValueToBits(2, logicalMin: 1, logicalMax: 4), 2)
		XCTAssertEqual(GenericHIDController.hatValueToBits(3, logicalMin: 1, logicalMax: 4), 4)
		XCTAssertEqual(GenericHIDController.hatValueToBits(4, logicalMin: 1, logicalMax: 4), 8)
	}

	func testGenericHIDAxisButtons_UseAxisPolarity() {
		XCTAssertTrue(GenericHIDController.axisButtonPressed(-0.75, inverted: false, polarity: .negative))
		XCTAssertFalse(GenericHIDController.axisButtonPressed(0.75, inverted: false, polarity: .negative))
		XCTAssertFalse(GenericHIDController.axisButtonPressed(-0.25, inverted: false, polarity: .negative))

		XCTAssertTrue(GenericHIDController.axisButtonPressed(0.75, inverted: false, polarity: .positive))
		XCTAssertFalse(GenericHIDController.axisButtonPressed(-0.75, inverted: false, polarity: .positive))
		XCTAssertFalse(GenericHIDController.axisButtonPressed(0.25, inverted: false, polarity: .positive))

		XCTAssertTrue(GenericHIDController.axisButtonPressed(0.75, inverted: false, polarity: .full))
		XCTAssertTrue(GenericHIDController.axisButtonPressed(-0.75, inverted: false, polarity: .full))
		XCTAssertFalse(GenericHIDController.axisButtonPressed(0.25, inverted: false, polarity: .full))
	}

	func testGenericHIDStickAxes_UseOutputPolarity() {
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			0.75,
			sourcePolarity: .positive,
			outputPolarity: .positive
		), 0.75)
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			-0.75,
			sourcePolarity: .negative,
			outputPolarity: .positive
		), 0.75)
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			0.75,
			sourcePolarity: .positive,
			outputPolarity: .negative
		), -0.75)
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			-0.75,
			sourcePolarity: .negative,
			outputPolarity: .negative
		), -0.75)
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			-0.75,
			sourcePolarity: .full,
			outputPolarity: .positive
		), 0.0)
		XCTAssertEqual(GenericHIDController.outputStickAxisValue(
			-0.75,
			sourcePolarity: .full,
			outputPolarity: .full
		), -0.75)
	}

	func testGenericHIDTriggerAxes_UseHalfAxisPolarity() {
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.5,
			centeredValue: 0.0,
			inverted: false,
			polarity: .positive
		), 0.0)
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.5,
			centeredValue: 0.0,
			inverted: false,
			polarity: .negative
		), 0.0)
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.875,
			centeredValue: 0.75,
			inverted: false,
			polarity: .positive
		), 0.75)
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.125,
			centeredValue: -0.75,
			inverted: false,
			polarity: .negative
		), 0.75)
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.6,
			centeredValue: 0.2,
			inverted: false,
			polarity: .full
		), 0.6)
		XCTAssertEqual(GenericHIDController.triggerAxisValue(
			minBasedValue: 0.6,
			centeredValue: 0.2,
			inverted: true,
			polarity: .full
		), 0.4, accuracy: 0.0001)
	}

    private func mappingLine(guid: String, name: String, entries: [String], platform: String = "Mac OS X") -> String {
        let body = entries.joined(separator: ",")
	return "\(guid),\(name),\(body),platform:\(platform),"
    }
}
