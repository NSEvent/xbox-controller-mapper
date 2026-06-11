Turn any game controller into the best productivity tool on your desk. Not for gaming — for everything else. (Previously Xbox Controller Mapper)

Every button maps to any keyboard shortcut. Copy, paste, undo, save — all on the face buttons. Left stick moves the mouse. Right stick scrolls. Bumpers and triggers become modifiers. You can drive your entire Mac from the couch without touching the keyboard, and setup takes about two minutes.

I built this because I wanted to vibe code with a controller and keep all my regular shortcuts. The existing Mac apps were either abandoned years ago or not configurable enough, so I wrote the one I wanted.

Pair any button with a voice transcription app (mine is the open-source VoiceInk) and you can "type" anything by talking — controller in one hand, coffee in the other.

**One-time purchase. No subscription.** Every update since launch has been free to all customers.

## What people use it for

- **Vibe coding from the couch** — map shortcuts, run macros, and pair with voice transcription for fully hands-free coding
- **Couch computing & media browsing** — navigate macOS, switch apps, scroll, and type from across the room
- **Accessibility** — alternative input for people who can't use a keyboard or mouse; works with macOS Accessibility Zoom and VoiceOver
- **Streaming** — trigger OBS scenes, mute/unmute, fire webhooks, and show a button overlay on stream
- **Presentations** — laser pointer overlay, app switching, and clicker-style navigation with any gamepad

## Where it gets interesting

**Need to type?** Hold a trigger and an on-screen keyboard appears. Swipe the stick across the letters in one motion and it predicts the word — spaces are automatic. It's the same class of algorithm (SHARK2) your phone keyboard uses. You can write full sentences without pecking one letter at a time.

**Switching apps?** Hold a button and a GTA-style radial wheel appears with your apps in a circle. Point the stick, let go. After a day you're doing it from muscle memory.

**Want precision?** On DualSense, DualShock 4, and Steam Controller, the gyroscope becomes a precision mouse. Tilt the controller and the cursor follows your hand, with a smoothing filter that kills hand tremor but lets fast flicks through. You can hit a 10-pixel close button on the first try.

**Want more buttons?** Press two buttons together for chord shortcuts. Enter button sequences (Up-Up-Down-Down). Hold a button to swap your entire layout to an alternate layer — that triples your button count. All 8 directions of each stick can be mapped as buttons too.

**Want automation?** Record macros that chain key presses, typed text, app launches, shell commands, and webhooks into a single button press. Control OBS scenes directly. Or write JavaScript for fully custom automation — clipboard access, app detection, notifications, window screenshots, persistent state, with a built-in example gallery and editor.

**Got two Macs?** This is the one nobody else does: pair two Macs running ControllerKeys and push your cursor against the screen edge to hand off mouse, keyboard, and button mappings to the second Mac — like Universal Control, but for your controller. Local network only, every frame HMAC-authenticated. A chord that opens Finder on one Mac opens Finder on the other.

## Works with practically everything

- **Xbox Series X|S / One** — including Elite Series 2 paddles
- **PS5 DualSense & DualSense Edge** — touchpad gestures, gyro aiming, custom LED light bar colors, Edge paddles and function buttons, even the built-in microphone (USB)
- **PS4 DualShock 4** — touchpad and gyro included, PlayStation-style labels throughout
- **Steam Controller** — full native support with no Steam running: both touchpads (whole-pad or quadrants), gyro aiming, grip buttons, haptics
- **Nintendo Joy-Con** (single or paired) **and Switch Pro Controller**
- **Apple TV Siri Remote** — clickpad as cursor, iPod-wheel edge scrolling, every side button mappable
- **300+ third-party controllers** (8BitDo, Logitech, PowerA, Hori, generic Bluetooth gamepads…) via the SDL controller database — plug in and it just works

## Full feature rundown

**Mapping**
- Buttons → shortcuts, with long-hold, double-tap, and repeat-while-held variants
- Chords (multi-button), sequences (ordered combos), and motion gestures (tilt/steer)
- Layers: alternate mapping sets while holding an activator button, with per-layer stick modes
- Custom stick directions — WASD/arrow presets or bind anything to any of 8 directions
- Left/right modifier distinction (left ⌘ vs right ⌘)
- Realtime input mode: low-latency key-down/key-up passthrough for games
- Touchpad: tap to click, two-finger scroll and right-click, pinch to zoom

**Automation**
- Macros: key presses, typed text, delays, paste, shell commands, webhooks, OBS steps
- JavaScript scripting: press(), type(), shell(), openApp(), notify(), haptic(), screenshotWindow(), app-aware context, persistent state, AI prompt assistant
- HTTP webhooks (GET/POST/PUT/DELETE/PATCH) with response feedback above the cursor
- OBS WebSocket control, app launching, links, terminal commands

**Typing & navigation**
- On-screen keyboard with swipe typing, D-pad navigation, quick text snippets, app bar, website links, and media keys
- Command wheel radial menu for apps and websites
- Controller-driven file navigator and presentation laser pointer

**Profiles**
- Unlimited profiles with per-app auto-switching and per-controller linking
- Community profile library with one-click import: Xcode, VS Code, Premiere, Figma, Blender, Ableton, Spotify, Claude, Anki, and more
- Stream Deck V2 profile import
- Automatic snapshots with a History tab — every destructive change is undoable
- Smart recommendations: after a few days of use, the app analyzes your press patterns and suggests more efficient mappings, applied in one click

**For streamers**
- Stream overlay showing live button presses for OBS capture
- Controller Wrapped: shareable usage-stats cards with personality typing

**Hardware extras**
- Battery notifications, light-bar battery indicator, party mode LEDs, per-mapping haptic feedback, controller lock toggle, Bluetooth keep-alive

**Accessibility**
- VoiceOver support, full compatibility with macOS Accessibility Zoom, gyro aiming for tremor-resistant precision
- Localized in English, Simplified & Traditional Chinese, German, and Japanese

## Actively developed

Nearly 40 releases since January, with new features shipping monthly — Steam Controller and Apple TV Remote support, Mac-to-Mac handoff, and realtime input mode all landed in the last few weeks. See the [full changelog on GitHub](https://github.com/NSEvent/xbox-controller-mapper/blob/main/CHANGELOG.md), and join the [Discord community](https://discord.gg/WsZJkRsPPg) for profiles, support, and feature requests.

## Open source for transparency

ControllerKeys needs macOS Accessibility permissions to simulate input, so the [complete source code is public](https://github.com/NSEvent/xbox-controller-mapper) for security audit. Official binaries are signed and notarized by Apple. Your purchase funds continued development.

## Requirements

- macOS 14.6 or later
- Any supported controller (see list above)
- Accessibility permission (the app walks you through it)

Questions before buying? Ask in the [Discord](https://discord.gg/WsZJkRsPPg).
