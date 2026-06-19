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
}

private final class SpyLicenseCredentialStore {
    private(set) var readKeys: [String] = []
    private(set) var storedValues: [(key: String, password: String)] = []
    private(set) var deletedKeys: [String] = []

    var store: LicenseCredentialStore {
        LicenseCredentialStore(
            retrieve: { [self] key in
                readKeys.append(key)
                return nil
            },
            store: { [self] password, key in
                storedValues.append((key: key, password: password))
                return key
            },
            delete: { [self] key in
                deletedKeys.append(key)
            }
        )
    }
}
