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

	func testLookupByDeviceProperties_PrefersMacMappingWhenDuplicateGuidFallbackExists() {
		let duplicateGuid = GameControllerDatabase.constructGUID(
			vendorID: 0x1915,
			productID: 0x7856,
			version: 0x0110,
			transport: nil
		)
		let content = [
			mappingLine(
				guid: duplicateGuid,
				name: "Mac Layout",
				entries: [
					"a:b3",
					"leftx:a1"
				]
			),
			mappingLine(
				guid: duplicateGuid,
				name: "Linux Layout",
				entries: [
					"a:b0",
					"leftx:a0"
				],
				platform: "Linux"
			)
		].joined(separator: "\n")
		let database = GameControllerDatabase(databaseContentOverride: content)

		let mapping = database.lookup(
			vendorID: 0x1915,
			productID: 0x7856,
			version: 0x9999,
			transport: nil
		)

		XCTAssertEqual(mapping?.name, "Mac Layout")
		if case let .button(index)? = mapping?.buttonMap["a"] {
			XCTAssertEqual(index, 3)
		} else {
			XCTFail("Expected duplicate GUID fallback to use the macOS button layout")
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

	func testKnownVendorProductPairs_IgnoresNonDevicePropertyGUIDs() {
		let malformedGUIDWithCollidingVIDPID = "03000000341241417856424200004343"
		let validWindowsGUID = GameControllerDatabase.constructGUID(
			vendorID: 0x9abc,
			productID: 0xdef0,
			version: 0,
			transport: nil
		)
		let content = [
			mappingLine(
				guid: malformedGUIDWithCollidingVIDPID,
				name: "Text GUID Collision",
				entries: ["a:b0"],
				platform: "Android"
			),
			mappingLine(
				guid: validWindowsGUID,
				name: "Valid Windows HID GUID",
				entries: ["a:b1"],
				platform: "Windows"
			)
		].joined(separator: "\n")
		let database = GameControllerDatabase(databaseContentOverride: content)

		let pairs = database.knownVendorProductPairs()
		XCTAssertFalse(pairs.contains { $0.vendorID == 0x1234 && $0.productID == 0x5678 })
		XCTAssertTrue(pairs.contains { $0.vendorID == 0x9abc && $0.productID == 0xdef0 })
		XCTAssertNil(database.lookup(
			vendorID: 0x1234,
			productID: 0x5678,
			version: 0,
			transport: nil
		))

		Self.retainedDatabases.append(database)
	}

	func testLookup_MatchesDatabaseEntryWithEmbeddedNameCRC() {
		// SDL embeds a CRC16 of the controller name in bytes 2-3 (chars 4-7) of
		// HID GUIDs. Lookups construct zero-CRC GUIDs, so the database key must
		// be normalized at parse time or such entries can never match.
		let zeroCRCGuid = GameControllerDatabase.constructGUID(
			vendorID: 0x045e,
			productID: 0x0b13,
			version: 0x0509,
			transport: nil
		)
		var crcGuid = zeroCRCGuid
		let crcStart = crcGuid.index(crcGuid.startIndex, offsetBy: 4)
		let crcEnd = crcGuid.index(crcGuid.startIndex, offsetBy: 8)
		crcGuid.replaceSubrange(crcStart..<crcEnd, with: "8db0")

		XCTAssertEqual(GameControllerDatabase.normalizedDatabaseGUID(crcGuid), zeroCRCGuid)

		let content = mappingLine(guid: crcGuid, name: "Xbox Series X CRC", entries: ["a:b0"])
		let database = GameControllerDatabase(databaseContentOverride: content)

		let mapping = database.lookup(
			vendorID: 0x045e,
			productID: 0x0b13,
			version: 0x0509,
			transport: nil
		)
		XCTAssertEqual(mapping?.name, "Xbox Series X CRC")
		XCTAssertNotNil(database.lookup(guid: zeroCRCGuid))
		XCTAssertTrue(database.hasKnownVendorProduct(vendorID: 0x045e, productID: 0x0b13))
		XCTAssertTrue(database.knownVendorProductPairs().contains {
			$0.vendorID == 0x045e && $0.productID == 0x0b13
		})

		Self.retainedDatabases.append(database)
	}

	func testGUIDNormalization_LeavesNonHIDGUIDsAlone() {
		// "xinput"-style text GUID: the fixed fields at bytes 6-7/10-11/14-15
		// happen to be zero, but the bus field is ASCII rather than a recognized
		// HID bus. Zeroing its "CRC" would decode the ASCII bytes into a bogus
		// vendor/product pair (0x7475/0x0000), regressing the non-HID GUID
		// exclusion from commit e83efd0.
		let textGuid = "78696e70757400000000000000000000"
		XCTAssertEqual(GameControllerDatabase.normalizedDatabaseGUID(textGuid), textGuid)

		let content = mappingLine(
			guid: textGuid,
			name: "XInput Text GUID",
			entries: ["a:b0"],
			platform: "Windows"
		)
		let database = GameControllerDatabase(databaseContentOverride: content)

		XCTAssertFalse(database.knownVendorProductPairs().contains { $0.vendorID == 0x7475 })
		XCTAssertFalse(database.hasKnownVendorProduct(vendorID: 0x7475, productID: 0x0000))
		XCTAssertNil(database.lookup(vendorID: 0x7475, productID: 0x0000, version: 0, transport: nil))

		Self.retainedDatabases.append(database)
	}

	func testConcurrentLookupsDuringReload_NoCrash() {
		let guid = GameControllerDatabase.constructGUID(
			vendorID: 0x045e,
			productID: 0x028e,
			version: 0,
			transport: nil
		)
		let content = mappingLine(guid: guid, name: "Xbox", entries: ["a:b0"])
		let database = GameControllerDatabase(databaseContentOverride: content)

		// Mix readers with full reloads (which rebuild and swap both mapping
		// dictionaries). Without locking, the dictionary swap races the readers.
		DispatchQueue.concurrentPerform(iterations: 200) { i in
			switch i % 5 {
			case 0:
				database.loadDatabase()
			case 1:
				_ = database.lookup(guid: guid)
			case 2:
				_ = database.lookup(vendorID: 0x045e, productID: 0x028e, version: 0x0114, transport: "bluetooth")
			case 3:
				_ = database.knownVendorProductPairs()
			default:
				_ = database.hasKnownVendorProduct(vendorID: 0x045e, productID: 0x028e)
			}
		}

		// No crash = success.
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
