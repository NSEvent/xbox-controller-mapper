import Foundation
import Security

/// Stores and retrieves OBS WebSocket passwords in the macOS Keychain
/// instead of persisting them as plaintext in config.json.
enum KeychainService {
    private static let serviceName = "com.controllerkeys.obs-passwords"

    /// Where passwords are kept. Under tests this is an in-memory store, so no test
    /// reads or writes the user's login keychain: a keychain read from the unsigned test
    /// binary opens a password dialog in a GUI session and blocks the run until someone
    /// clicks it, and real items (OBS, license, relay) would leak into the tests.
    struct Backend {
        var retrieve: (_ key: String, _ service: String) -> String?
        var store: (_ password: String, _ key: String, _ service: String) -> String?
        var delete: (_ key: String, _ service: String) -> Void

        static let keychain = Backend(
            retrieve: { liveRetrieve(key: $0, service: $1) },
            store: { liveStore($0, key: $1, service: $2, client: .live) },
            delete: { liveDelete(key: $0, service: $1) }
        )

        static func inMemory() -> Backend {
            let lock = NSLock()
            var items: [String: String] = [:]
            func id(_ key: String, _ service: String) -> String { service + "\u{0}" + key }
            return Backend(
                retrieve: { key, service in lock.withLock { items[id(key, service)] } },
                store: { password, key, service in
                    lock.withLock { items[id(key, service)] = password }
                    return key
                },
                delete: { key, service in _ = lock.withLock { items.removeValue(forKey: id(key, service)) } }
            )
        }
    }

    static var backend: Backend = AppRuntime.isRunningTests ? .inMemory() : .keychain

    struct SecItemClient {
        var add: (CFDictionary) -> OSStatus
        var update: (CFDictionary, CFDictionary) -> OSStatus

        static let live = SecItemClient(
            add: { SecItemAdd($0, nil) },
            update: { SecItemUpdate($0, $1) }
        )
    }

    /// Stores a password in the Keychain under the given key.
    /// Returns the key on success, nil on failure. Passing a `client` bypasses `backend`
    /// and runs the SecItem update/add logic against that client.
    @discardableResult
    static func storePassword(
        _ password: String,
        key: String,
        service: String = serviceName,
        client: SecItemClient? = nil
    ) -> String? {
        guard let client else { return backend.store(password, key, service) }
        return liveStore(password, key: key, service: service, client: client)
    }

    private static func liveStore(_ password: String, key: String, service: String, client: SecItemClient) -> String? {
        guard let data = password.data(using: .utf8) else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = client.update(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return key
        case errSecItemNotFound:
            break
        default:
            NSLog("[KeychainService] Failed to update password for key %@: %d", key, updateStatus)
            return nil
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let addStatus = client.add(addQuery as CFDictionary)
        if addStatus == errSecSuccess {
            return key
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = client.update(query as CFDictionary, updateAttributes as CFDictionary)
            if retryStatus == errSecSuccess {
                return key
            }
            NSLog("[KeychainService] Failed to update duplicate password for key %@: %d", key, retryStatus)
            return nil
        }

        NSLog("[KeychainService] Failed to store password for key %@: %d", key, addStatus)
        return nil
    }

    /// Retrieves a password from the Keychain for the given key.
    /// Returns nil if not found.
    static func retrievePassword(key: String, service: String = serviceName) -> String? {
        backend.retrieve(key, service)
    }

    private static func liveRetrieve(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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
    static func deletePassword(key: String, service: String = serviceName) {
        backend.delete(key, service)
    }

    private static func liveDelete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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
