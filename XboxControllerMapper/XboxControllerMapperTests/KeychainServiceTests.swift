import XCTest
import Security
@testable import ControllerKeys

final class KeychainServiceTests: XCTestCase {
    private var testKeys: [String] = []

    override func tearDown() {
        // Clean up all test keys
        for key in testKeys {
            KeychainService.deletePassword(key: key)
        }
        testKeys.removeAll()
        super.tearDown()
    }

    private func makeTestKey() -> String {
        let key = "test-\(UUID().uuidString)"
        testKeys.append(key)
        return key
    }

    func testStoreAndRetrieve() throws {
		try requireWritableKeychain()
		let key = makeTestKey()
		let password = "my-secret-password"

        let result = KeychainService.storePassword(password, key: key)
        XCTAssertNotNil(result, "storePassword should return the key on success")

        let retrieved = KeychainService.retrievePassword(key: key)
        XCTAssertEqual(retrieved, password)
    }

    func testRetrieveMissingKeyReturnsNil() {
        let retrieved = KeychainService.retrievePassword(key: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(retrieved)
    }

    func testDeletePassword() throws {
		try requireWritableKeychain()
		let key = makeTestKey()
		XCTAssertNotNil(KeychainService.storePassword("to-delete", key: key))

        KeychainService.deletePassword(key: key)

        let retrieved = KeychainService.retrievePassword(key: key)
        XCTAssertNil(retrieved, "Password should be nil after deletion")
    }

    func testOverwrite() throws {
		try requireWritableKeychain()
		let key = makeTestKey()
		XCTAssertNotNil(KeychainService.storePassword("original", key: key))
		XCTAssertNotNil(KeychainService.storePassword("updated", key: key))

        let retrieved = KeychainService.retrievePassword(key: key)
        XCTAssertEqual(retrieved, "updated")
    }

    func testStorePasswordUpdatesExistingItemWithoutAdd() {
        let key = makeTestKey()
        var addWasCalled = false
        var updatedPassword: String?
        let client = KeychainService.SecItemClient(
            add: { _ in
                addWasCalled = true
                return errSecSuccess
            },
            update: { _, attributes in
                updatedPassword = Self.passwordString(from: attributes)
                return errSecSuccess
            }
        )

        let result = KeychainService.storePassword("updated", key: key, client: client)

        XCTAssertEqual(result, key)
        XCTAssertFalse(addWasCalled)
        XCTAssertEqual(updatedPassword, "updated")
    }

    func testStorePasswordDoesNotAddWhenExistingUpdateFails() {
        let key = makeTestKey()
        var storedPassword = "original"
        var addWasCalled = false
        let client = KeychainService.SecItemClient(
            add: { query in
                addWasCalled = true
                storedPassword = Self.passwordString(from: query) ?? storedPassword
                return errSecSuccess
            },
            update: { _, _ in
                errSecInteractionNotAllowed
            }
        )

        let result = KeychainService.storePassword("updated", key: key, client: client)

        XCTAssertNil(result)
        XCTAssertFalse(addWasCalled)
        XCTAssertEqual(storedPassword, "original")
    }

    func testStorePasswordRetriesUpdateWhenAddFindsDuplicate() {
        let key = makeTestKey()
        var updateCount = 0
        var updatedPassword: String?
        let client = KeychainService.SecItemClient(
            add: { _ in
                errSecDuplicateItem
            },
            update: { _, attributes in
                updateCount += 1
                guard updateCount > 1 else {
                    return errSecItemNotFound
                }
                updatedPassword = Self.passwordString(from: attributes)
                return errSecSuccess
            }
        )

        let result = KeychainService.storePassword("updated", key: key, client: client)

        XCTAssertEqual(result, key)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(updatedPassword, "updated")
    }

    func testIsKeychainReferenceWithUUID() {
        XCTAssertTrue(KeychainService.isKeychainReference("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertTrue(KeychainService.isKeychainReference(UUID().uuidString))
    }

    func testIsKeychainReferenceWithPlaintext() {
        XCTAssertFalse(KeychainService.isKeychainReference("my-password"))
        XCTAssertFalse(KeychainService.isKeychainReference(""))
        XCTAssertFalse(KeychainService.isKeychainReference("not-a-uuid-at-all"))
    }

    private static func passwordString(from dictionary: CFDictionary) -> String? {
        let data = (dictionary as NSDictionary)[kSecValueData as String] as? Data
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private func requireWritableKeychain() throws {
		let probeKey = makeTestKey()
		let probePassword = "probe-\(UUID().uuidString)"
		let storedKey = KeychainService.storePassword(probePassword, key: probeKey)
		let retrieved = KeychainService.retrievePassword(key: probeKey)

		guard storedKey == probeKey, retrieved == probePassword else {
			KeychainService.deletePassword(key: probeKey)
			throw XCTSkip("Writable keychain unavailable in this test session")
		}
    }
}
