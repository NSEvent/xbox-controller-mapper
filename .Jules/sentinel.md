## 2026-06-07 - [Insecure Secret Storage]
**Vulnerability:** The application was storing a sensitive shared secret (`universalControlRelaySharedSecret`) in plaintext within `UserDefaults`.
**Learning:** Even when a secret is written to the secure Keychain, legacy fallback mechanisms or redundant storage can accidentally leave copies in insecure locations like `UserDefaults`, creating an information disclosure vulnerability on the device.
**Prevention:** Avoid writing secrets to `UserDefaults`. Use secure Keychain access APIs exclusively for sensitive data. When migrating secrets from `UserDefaults` to the Keychain, always explicitly delete the old insecure copy immediately after migration.
## 2026-06-15 - [Insecure URL Scheme Execution]
**Vulnerability:** The app allowed opening any URL string without validating the scheme, making it possible for attackers to use NSWorkspace.shared.open with potentially dangerous handlers like file:// or system preference handlers.
**Learning:** Passing untrusted URLs to NSWorkspace.shared.open or /usr/bin/open acts similarly to a shell execution if non-standard or local file schemes are used. It bypasses normal app boundaries.
**Prevention:** Always restrict URL schemes to an explicit allowlist (like http, https) before delegating to system URL openers.
## 2026-06-16 - [Dangerous URL Scheme execution in automation frameworks]
**Vulnerability:** Although an explicit scheme allowlist is the strongest defense, applying it blindly to a customizable automation framework (like `TriggerKit`) broke critical user functionality relying on standard custom schemes (like `shortcuts://` or `mailto:`). This forced us to roll back a naive allowlist.
**Learning:** In contexts like scripting or macro execution where flexibility is a core requirement, an allowlist can cause severe functional regressions. We must fallback to an explicit blocklist of definitively dangerous system schemes (e.g. `file`, `x-apple.systempreferences`) to mitigate the `NSWorkspace.shared.open` sandbox escape vector without breaking valid user automations.
**Prevention:** Consider the product requirements before applying restrictive allowlists. Use a blocklist targeting known unsafe execution vectors (file://, system preferences) for generalized scripting engines where an allowlist isn't feasible.
