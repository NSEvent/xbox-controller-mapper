import XCTest
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

    func testStoreAndRetrieve() {
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

    func testDeletePassword() {
        let key = makeTestKey()
        KeychainService.storePassword("to-delete", key: key)

        KeychainService.deletePassword(key: key)

        let retrieved = KeychainService.retrievePassword(key: key)
        XCTAssertNil(retrieved, "Password should be nil after deletion")
    }

    func testOverwrite() {
        let key = makeTestKey()
        KeychainService.storePassword("original", key: key)
        KeychainService.storePassword("updated", key: key)

        let retrieved = KeychainService.retrievePassword(key: key)
        XCTAssertEqual(retrieved, "updated")
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
}
