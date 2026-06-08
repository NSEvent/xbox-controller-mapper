## 2026-06-07 - [Insecure Secret Storage]
**Vulnerability:** The application was storing a sensitive shared secret (`universalControlRelaySharedSecret`) in plaintext within `UserDefaults`.
**Learning:** Even when a secret is written to the secure Keychain, legacy fallback mechanisms or redundant storage can accidentally leave copies in insecure locations like `UserDefaults`, creating an information disclosure vulnerability on the device.
**Prevention:** Avoid writing secrets to `UserDefaults`. Use secure Keychain access APIs exclusively for sensitive data. When migrating secrets from `UserDefaults` to the Keychain, always explicitly delete the old insecure copy immediately after migration.
