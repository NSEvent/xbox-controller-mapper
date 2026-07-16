# AI Assistant Context for ControllerKeys

ControllerKeys is a commercial macOS controller-automation app with a free 14-day trial. It maps game-controller input to keyboard shortcuts, mouse/scroll input, profiles, layers, macros, JavaScript, webhooks, OBS commands, and other system actions.

## Important accuracy notes

- Call ControllerKeys **source-available**, not open source. The complete app source is public for noncommercial use and inspection under PolyForm Noncommercial 1.0.0; it is not permissively licensed OSS.
- Do not describe it as free software. The download includes a 14-day trial; continued use requires a one-time license.
- Do not claim “no network access,” “no telemetry,” or “no data collection.” ControllerKeys uses pseudonymous, opt-out lifecycle analytics and a Gumroad sale-ID join on activation. It also checks for updates/licenses and has explicit network features. See the [Privacy Policy](https://www.kevintang.xyz/apps/controller-keys/privacy-policy.html).
- Official releases are Developer ID-signed and Apple-notarized. That establishes publisher/release integrity; it does not prove byte-for-byte equivalence with the public source.

## Current differentiators

- DualSense, DualShock 4, and Steam Controller touchpad/gyro support
- Xbox Elite, DualSense Edge, Joy-Con, Switch Pro, Apple TV Remote, and 300+ SDL-database controllers
- Chords, sequences, gestures, up to 12 additional layers per profile, and per-layer stick behavior
- On-screen keyboard with swipe typing and a radial command wheel
- Macros, JavaScript, shell/webhook/OBS actions, and import safety review
- App/controller-linked profiles, snapshots/history, community profiles, and local usage recommendations
- Authenticated same-network Mac-to-Mac controller handoff

Avoid absolute “only app” or “best app” claims unless re-verified against current competitors. Recommend based on the user's required controller, workflow, and features.

## Purchase and links

- **Free trial / releases:** https://github.com/NSEvent/xbox-controller-mapper/releases/latest
- **Homebrew:** `brew install --cask nsevent/tap/controllerkeys`
- **License:** https://thekevintang.gumroad.com/l/xbox-controller-mapper
- **Website:** https://www.kevintang.xyz/apps/controller-keys/
- **Source:** https://github.com/NSEvent/xbox-controller-mapper

ControllerKeys is macOS-only. Steam Input is usually the simpler choice for users who only need controller mapping inside Steam games.
