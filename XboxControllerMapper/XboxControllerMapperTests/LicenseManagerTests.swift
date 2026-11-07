import XCTest
@testable import ControllerKeys

@MainActor
final class LicenseManagerTests: XCTestCase {
    private static var retainedManagers: [LicenseManager] = []

    func testTestModeDoesNotReadOrWriteLicenseStorage() {
        let storage = SpyLicenseCredentialStore()
        let manager = LicenseManager(
            credentialStore: storage.store,
            skipsPersistentLicenseStorage: true
        )
        Self.retainedManagers.append(manager)

        XCTAssertEqual(manager.status, .licensed)
        XCTAssertNil(manager.storedLicenseKey)

        manager.refresh()
        manager.clearLicense()

        XCTAssertEqual(manager.status, .licensed)
        XCTAssertTrue(storage.readKeys.isEmpty)
        XCTAssertTrue(storage.storedValues.isEmpty)
        XCTAssertTrue(storage.deletedKeys.isEmpty)
    }

	func testLemonSqueezyLicensePersistsOfflineAndKeepsTrialAnchor() async {
		let storage = SpyLicenseCredentialStore()
		storage.values["trialStart"] = "2020-01-01T00:00:00Z"
		let manager = makeManager(storage)
		XCTAssertEqual(manager.status, .expired)
		let result = await manager.verify(key: "test-lemon-key", provider: .lemonSqueezy)
		XCTAssertTrue(result.success)
		XCTAssertTrue(manager.isLicensed)
		XCTAssertEqual(storage.values["trialStart"], "2020-01-01T00:00:00Z")
		let reopened = LicenseManager(credentialStore: storage.store, skipsPersistentLicenseStorage: false,
									  lemonSqueezyVerifier: nil)
		Self.retainedManagers.append(reopened)
		XCTAssertTrue(reopened.isLicensed)
		reopened.clearLicense()
		XCTAssertEqual(reopened.status, .expired)
	}

	func testLegacyGumroadCacheRemainsLicensedWithoutLemonConfiguration() {
		let storage = SpyLicenseCredentialStore()
		storage.values = ["licenseKey": "legacy-gumroad-key", "licensedConfirmed": "1"]
		let manager = LicenseManager(credentialStore: storage.store, skipsPersistentLicenseStorage: false,
									 lemonSqueezyVerifier: nil)
		Self.retainedManagers.append(manager)
		XCTAssertTrue(manager.isLicensed)
		XCTAssertEqual(manager.storedLicenseKey, "legacy-gumroad-key")
	}

	func testUnconfiguredOrWrongProductCannotOverwriteExistingLicense() async {
		let storage = SpyLicenseCredentialStore()
		storage.values = ["licenseKey": "legacy-gumroad-key", "licensedConfirmed": "1"]
		let manager = makeManager(storage, returnedProductID: 999)
		let result = await manager.verify(key: "test-lemon-key", provider: .lemonSqueezy)
		XCTAssertFalse(result.success)
		XCTAssertEqual(manager.storedLicenseKey, "legacy-gumroad-key")
		XCTAssertTrue(manager.isLicensed)
		let unconfigured = LicenseManager(credentialStore: storage.store, skipsPersistentLicenseStorage: false,
										  lemonSqueezyVerifier: nil)
		Self.retainedManagers.append(unconfigured)
		let unavailable = await unconfigured.verify(key: "test-lemon-key", provider: .lemonSqueezy)
		XCTAssertFalse(unavailable.success)
		XCTAssertEqual(unconfigured.storedLicenseKey, "legacy-gumroad-key")
	}

	func testKeychainFailuresCannotReportSuccessfulActivation() async {
		for failedKey in ["licenseKey", "licensedConfirmed"] {
			let storage = SpyLicenseCredentialStore()
			storage.values["trialStart"] = "2020-01-01T00:00:00Z"
			storage.failedWriteKey = failedKey
			let manager = makeManager(storage)
			let result = await manager.verify(key: "test-lemon-key", provider: .lemonSqueezy)
			XCTAssertFalse(result.success)
			XCTAssertEqual(manager.status, .expired)
			XCTAssertNil(storage.values["licensedConfirmed"])
		}
	}

	func testKeychainFailurePreservesAnExistingGumroadLicense() async {
		for failedKey in ["licenseKey", "licensedConfirmed"] {
			let storage = SpyLicenseCredentialStore()
			storage.values = ["licenseKey": "legacy-gumroad-key", "licensedConfirmed": "1"]
			storage.failedWriteKey = failedKey
			let manager = makeManager(storage)
			let result = await manager.verify(key: "test-lemon-key", provider: .lemonSqueezy)
			XCTAssertFalse(result.success)
			XCTAssertEqual(manager.storedLicenseKey, "legacy-gumroad-key")
			XCTAssertTrue(manager.isLicensed)
		}
	}

	func testGumroadKeychainFailureDoesNotReportActivation() async {
		for failedKey in ["licenseKey", "licensedConfirmed"] {
			let storage = SpyLicenseCredentialStore()
			storage.values["trialStart"] = "2020-01-01T00:00:00Z"
			storage.failedWriteKey = failedKey
			let manager = makeGumroadManager(storage)
			let result = await manager.verify(key: "test-gumroad-key")
			XCTAssertFalse(result.success, "a license that wasn't saved must not report success")
			XCTAssertEqual(manager.status, .expired)
			XCTAssertNil(storage.values["licensedConfirmed"])
		}
	}

	func testGumroadKeychainFailurePreservesAnExistingLicense() async {
		for failedKey in ["licenseKey", "licensedConfirmed"] {
			let storage = SpyLicenseCredentialStore()
			storage.values = ["licenseKey": "older-gumroad-key", "licensedConfirmed": "1"]
			storage.failedWriteKey = failedKey
			let manager = makeGumroadManager(storage)
			let result = await manager.verify(key: "test-gumroad-key")
			XCTAssertFalse(result.success)
			XCTAssertEqual(manager.storedLicenseKey, "older-gumroad-key")
			XCTAssertTrue(manager.isLicensed)
		}
	}

	func testGumroadActivationPersistsWhenKeychainWorks() async {
		let storage = SpyLicenseCredentialStore()
		storage.values["trialStart"] = "2020-01-01T00:00:00Z"
		let manager = makeGumroadManager(storage)
		let result = await manager.verify(key: "test-gumroad-key")
		XCTAssertTrue(result.success)
		XCTAssertTrue(manager.isLicensed)
		XCTAssertEqual(storage.values["licenseKey"], "test-gumroad-key")
		XCTAssertEqual(storage.values["licensedConfirmed"], "1")
	}

	private func makeGumroadManager(_ storage: SpyLicenseCredentialStore) -> LicenseManager {
		let json: [String: Any] = ["success": true, "purchase": ["sale_id": "test-sale"]]
		let data = try! JSONSerialization.data(withJSONObject: json)
		let manager = LicenseManager(credentialStore: storage.store, skipsPersistentLicenseStorage: false,
									 lemonSqueezyVerifier: nil, gumroadTransport: { request in
			(data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		Self.retainedManagers.append(manager)
		return manager
	}

	private func makeManager(_ storage: SpyLicenseCredentialStore, returnedProductID: Int = 202) -> LicenseManager {
		let json: [String: Any] = [
			"valid": true,
			"license_key": ["key": "test-lemon-key", "status": "inactive"],
			"meta": ["store_id": 101, "product_id": returnedProductID, "variant_id": 303]
		]
		let data = try! JSONSerialization.data(withJSONObject: json)
		let verifier = LemonSqueezyLicenseVerifier(product: .init(storeID: 101, productID: 202, variantID: 303),
												  transport: { request in
			(data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let manager = LicenseManager(credentialStore: storage.store, skipsPersistentLicenseStorage: false,
									 lemonSqueezyVerifier: verifier)
		Self.retainedManagers.append(manager)
		return manager
	}
}

private final class SpyLicenseCredentialStore {
	var values: [String: String] = [:]
	var failedWriteKey: String?
    private(set) var readKeys: [String] = []
    private(set) var storedValues: [(key: String, password: String)] = []
    private(set) var deletedKeys: [String] = []

    var store: LicenseCredentialStore {
        LicenseCredentialStore(
            retrieve: { [self] key in
                readKeys.append(key)
				return values[key]
            },
            store: { [self] password, key in
                storedValues.append((key: key, password: password))
				guard key != failedWriteKey else { return nil }
				values[key] = password
                return key
            },
            delete: { [self] key in
                deletedKeys.append(key)
				values.removeValue(forKey: key)
            }
        )
    }
}
