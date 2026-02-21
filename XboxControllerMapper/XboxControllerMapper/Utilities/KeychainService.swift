import Foundation
import Security

/// Stores and retrieves OBS WebSocket passwords in the macOS Keychain
/// instead of persisting them as plaintext in config.json.
enum KeychainService {
    private static let serviceName = "com.controllerkeys.obs-passwords"

    /// Stores a password in the Keychain under the given key.
    /// Returns the key on success, nil on failure.
    @discardableResult
    static func storePassword(_ password: String, key: String) -> String? {
        guard let data = password.data(using: .utf8) else { return nil }

        // Delete any existing item first
        deletePassword(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return key
        } else {
            NSLog("[KeychainService] Failed to store password for key %@: %d", key, status)
            return nil
        }
    }

    /// Retrieves a password from the Keychain for the given key.
    /// Returns nil if not found.
    static func retrievePassword(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes a password from the Keychain.
    static func deletePassword(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Checks if a string looks like a Keychain reference (UUID format).
    /// Used to distinguish between legacy plaintext passwords and Keychain references.
    static func isKeychainReference(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}
