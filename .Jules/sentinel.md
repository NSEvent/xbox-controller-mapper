## 2026-06-07 - [Insecure Secret Storage]
**Vulnerability:** The application was storing a sensitive shared secret (`universalControlRelaySharedSecret`) in plaintext within `UserDefaults`.
**Learning:** Even when a secret is written to the secure Keychain, legacy fallback mechanisms or redundant storage can accidentally leave copies in insecure locations like `UserDefaults`, creating an information disclosure vulnerability on the device.
**Prevention:** Avoid writing secrets to `UserDefaults`. Use secure Keychain access APIs exclusively for sensitive data. When migrating secrets from `UserDefaults` to the Keychain, always explicitly delete the old insecure copy immediately after migration.
## 2026-06-15 - [Insecure URL Scheme Execution]
**Vulnerability:** The app allowed opening any URL string without validating the scheme, making it possible for attackers to use NSWorkspace.shared.open with potentially dangerous handlers like file:// or system preference handlers.
**Learning:** Passing untrusted URLs to NSWorkspace.shared.open or /usr/bin/open acts similarly to a shell execution if non-standard or local file schemes are used. It bypasses normal app boundaries.
**Prevention:** Always restrict URL schemes to an explicit allowlist (like http, https) before delegating to system URL openers.
## 2026-06-16 - [Sandbox Escape via URL Handler Scheme]
**Vulnerability:** Execution frameworks allowed untrusted automation configurations to open URLs with schemes like `file` and `x-apple.systempreferences`, effectively allowing arbitrary local execution or sandbox escapes via `NSWorkspace.shared.open`.
**Learning:** `NSWorkspace.shared.open` delegates URL handling directly to the OS, executing system preferences panes or opening arbitrary files. Bounding allowed schemes is critical, and a strict blocklist is required when an allowlist is too restrictive for general automation.
**Prevention:** Apply a strict blocklist for URL handlers (e.g. `file`, `x-apple.systempreferences`) at the core execution and validation levels when evaluating untrusted URL strings.
## 2026-06-25 - [Sandbox Escape via URL Handler Scheme expanded]
**Vulnerability:** Execution frameworks allowed untrusted automation configurations to open URLs with schemes like `shortcuts`, `terminal`, `ssh`, `telnet`, `vnc`, `ftp`, `smb`, `afp`, effectively allowing arbitrary local execution or sandbox escapes via `NSWorkspace.shared.open`.
**Learning:** Adding `file` and `x-apple.systempreferences` is not enough. Other local OS handlers (like `shortcuts://` or `terminal://`) can still perform actions directly from untrusted inputs without validation, acting as potential attack vectors.
**Prevention:** Apply a comprehensive blocklist for URL handlers containing all potentially dangerous schemes (e.g. `shortcuts`, `terminal`, `ssh`, `telnet`, `vnc`, `ftp`, `smb`, `afp`) at the core execution and validation levels when evaluating untrusted URL strings.
## 2026-06-22 - [Insecure Plaintext Fallback Storage]
**Vulnerability:** The application was falling back to storing OBS passwords as plaintext strings inside exported/saved JSON models (`Macro.swift` and `SystemCommand.swift`) if saving to the macOS Keychain failed.
**Learning:** Saving secrets to unencrypted formats simply because secure storage fails is a critical anti-pattern known as "failing open" that results in data exposure.
**Prevention:** Always fail securely. If secure storage operations fail, discard the sensitive credential in memory rather than writing it insecurely to disk, even if it requires the user to re-authenticate later.
