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
- Log or record your keystrokes
- Transmit any data over the network
- Access files outside its sandbox
- Run any background processes when quit

### Why Open Source?

The source code is publicly available specifically so users can verify the app's behavior before granting sensitive permissions. You are encouraged to:

- Audit the source code
- Build from source to verify the binary
- Report any concerns

### Code Signing & Notarization

Official releases are:
- Signed with an Apple Developer ID certificate
- Notarized by Apple
- Distributed via Gumroad

This ensures the binary hasn't been tampered with and matches what Apple has verified.

## Supported Versions

Only the latest version receives security updates. Please keep your installation up to date by downloading the newest release from [Gumroad](https://thekevintang.gumroad.com/l/xbox-controller-mapper).
