# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in ControllerKeys, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please report security issues by emailing the maintainer directly or using GitHub's private vulnerability reporting feature.

### What to Include

When reporting a vulnerability, please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

### Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial Assessment:** Within 1 week
- **Resolution:** Depends on severity and complexity

## Security Considerations

### Accessibility Permissions

ControllerKeys requires macOS Accessibility permissions to function. This permission allows the app to:

- Simulate keyboard input
- Simulate mouse movement and clicks
- Simulate scroll events

**The app does NOT:**
- Transmit raw controller reports, typed text, mappings, scripts, or quick text as analytics
- Run any background processes when quit

ControllerKeys does keep aggregate button/action counts, movement distances, and session totals locally for recommendations and Controller Wrapped.

### Data and Network Activity

ControllerKeys sends pseudonymous, opt-out lifecycle analytics: a random install ID, app/build and Mac details, locale, install channel, and trial/license state. License activation includes its Gumroad sale ID, making the install linkable to that purchase record; the analytics database does not store buyer names or email addresses. The server stores approximate country and a salted IP hash rather than the raw IP. Disable this in **Settings → General → Privacy**; the same toggle disables Sparkle system profiling. Update and license checks still connect.

Other connections support explicit features: Sparkle/GitHub updates, Gumroad license verification, GitHub community profiles and controller-database refreshes, website favicon downloads, local Mac-to-Mac relay, and user-configured webhooks, OBS endpoints, scripts, and links. See the [Privacy Policy](https://www.kevintang.xyz/apps/controller-keys/privacy-policy.html) for the current inventory.

### Remote Mouse Relay

ControllerKeys includes an optional same-network remote mouse relay for controlling another Mac running ControllerKeys. The relay:

- Listens on TCP port 38383 for ControllerKeys relay frames
- Accepts connections only from local/private network ranges, link-local ranges, IPv6 ULA ranges, localhost, or Tailscale/CGNAT `100.64.0.0/10`
- Requires every protocol frame to be authenticated with an HMAC-SHA256 shared secret
- Rejects plaintext, tampered, replayed, oversized, or rate-limited frames
- Does not accept remote shell/system-command execution

The relay secret is stored in Keychain. A manually supplied shared secret can be configured with the `universalControlRelaySharedSecret` user default when pairing machines.

### System Access

ControllerKeys is not sandboxed because system-wide controller remapping requires Accessibility event posting, app launching, optional Apple Events automation, and user-configured shell/webhook actions.

### Why Source Available?

The app source is publicly available under the PolyForm Noncommercial 1.0.0 license so users can inspect its behavior before granting sensitive permissions. You are encouraged to:

- Audit the source code
- Build your own copy from source
- Report any concerns

Source inspection or a local build does not prove that an official binary is byte-for-byte identical to the repository.

### Code Signing & Notarization

Official releases are:
- Signed with an Apple Developer ID certificate
- Notarized by Apple
- Distributed through GitHub Releases and Homebrew

Code signing establishes the publisher and protects release integrity. Apple notarization scans the submitted build for known malicious content; neither mechanism proves equivalence with the public source.

## Supported Versions

Only the latest version receives security updates. Keep ControllerKeys current through its built-in updater, Homebrew, or the latest [GitHub Release](https://github.com/NSEvent/xbox-controller-mapper/releases/latest).
