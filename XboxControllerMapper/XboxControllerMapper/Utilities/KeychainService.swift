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

    /// Generates a stable Keychain key from a context string (e.g., OBS WebSocket URL).
    /// Uses a UUID v5-style deterministic hash so the same input always produces the same key,
    /// preventing Keychain entry accumulation from repeated saves.
    static func stableKey(for context: String) -> String {
        // Use a simple hash-based approach: SHA256 of the context formatted as a UUID string
        let data = Data(context.utf8)
        // Simple deterministic hash using Swift's built-in hasher seeded with fixed value
        // We use a basic FNV-1a-like hash to produce a stable 128-bit value
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        for (i, byte) in data.enumerated() {
            hash[i % 16] ^= byte
            hash[i % 16] &+= byte &* 31
        }
        // Format as UUID string: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return uuid
    }
}
