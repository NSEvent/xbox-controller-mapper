# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.1] - 2026-06-16

### Fixed

- **Window no longer breaks when no controller is connected**: With nothing paired, the "No controller connected" pairing card could push the Buttons tab past the window height — the layout overflowed and shoved the toolbar and tab bar off the top edge while the controller diagram collapsed. The Buttons tab now scrolls when its contents don't fit and the diagram keeps a usable minimum size, so the toolbar and tabs always stay in place.

- **Blocked unsafe URL schemes**: Website and quick-link actions now open only `http`/`https` URLs, so a crafted or imported profile can't use them to launch arbitrary system handlers (e.g. `file://` or system-preference panes).

### Changed

- **Layer toolbar adapts to narrow windows**: The Base / layer / Add Layer / Swap / Cursor Hints / Stream pills are now a fixed height — labels no longer wrap to a second line and grow tall — and they collapse to icon-only buttons when the row gets too narrow. Layers keep their colored activator badge so they stay distinguishable, and tooltips name every icon.

- **Tooltips and VoiceOver labels for icon-only buttons**: Icon-only controls across the Buttons tab, community profiles, and the sequence editor now carry hover tooltips and accessibility labels.

- **Hardened automation handling**: Macros and automation programs are validated and migrated more strictly, with cleanup policies kept in sync between the editor and the runtime — reducing the chance of a malformed automation misbehaving.

## [2.1.0] - 2026-06-15

### Added

- **14-day free trial with license unlock**: ControllerKeys now opens as a 14-day free trial with full functionality — no account needed. A first-launch welcome explains the trial and lets anyone who already purchased on Gumroad paste their license key to activate immediately. When the trial ends, controller mapping pauses (the rest of the app stays usable) until a license is entered; activation verifies against Gumroad and then keeps working offline, and the trial clock is stored in the login keychain so it survives reinstalls. License status, activation, and a buy link live in Settings → General.

- **Automatic updates**: ControllerKeys can now update itself — it checks for new versions in the background and installs them with your approval, with a "Check Now" control in Settings → General. Updates are cryptographically signed (EdDSA) and notarized, so only genuine builds are ever installed.

- **Show/hide the profile sidebar with ⌘B**: The profile sidebar is now shown by default and toggles with ⌘B (the shortcut hint appears next to the menu item). Hiding it persists until you show it again.

### Changed

- **Apple-style Settings**: Settings was rebuilt from one long scrolling form into a System Settings-style sheet — a sidebar of categories (General, Appearance, Layout, Controllers, Remote Mouse, About) with the selected category's controls shown on the right.

- **Reworked toolbar and mapping toggle**: The connection status (status light and controller name) moved to the right side of the toolbar, next to a redesigned mapping toggle — a high-contrast filled pill ("Mapping On" / "Trial ended") that replaces the previous low-contrast accent-on-gray text.

- **More room for the controller map**: Tightened the toolbar, tab bar, and Buttons-tab header so the controller diagram sits higher and renders larger. The Timeline strip is now optional — hide it from the Buttons tab and restore it from Settings → Layout.

### Fixed

- **Stream and Cursor Hints toggles**: These buttons now reliably reflect their on/off state. Previously the highlight could stick after toggling because the underlying preference wasn't observed by the view.

## [2.0.1] - 2026-06-14

### Added

- **Profile switch action**: System-command mappings can now switch directly to another ControllerKeys profile. The action is available across the mapping editor surfaces and is treated as an internal profile action instead of a shell/webhook command.

- **Controller Connection Guides window**: Pairing help now has a dedicated guide window with controller-specific minimaps, reachable from the no-controller pairing hint and the menu bar.

### Changed

- **8BitDo documentation and marketing assets**: The README set and screenshot pipeline now include the 8BitDo Zero 2 and Micro, with the 8BitDo section rewritten to focus on why the tiny-controller support matters in practice.

- **Icon-only control accessibility**: Added missing accessibility labels and tooltips to several toolbar, layer, sidebar, and stream-overlay controls.

### Fixed

- **Configure-button sheet scrolling**: Scrolling inside a Buttons-tab configuration sheet no longer leaks through to the underlying buttons canvas. Canvas two-finger panning now only handles scroll events from the actual canvas window and ignores attached sheet windows.

- **Universal Control secret storage hardening**: The relay no longer falls back to storing shared secrets in UserDefaults when Keychain persistence fails.

## [2.0.0] - 2026-06-13

### Added

- **Shared macro library across TriggerKit apps**: Macros are no longer trapped inside a single ControllerKeys profile. Bindings can now pull from a shared, per-user macro library (`~/Library/Application Support/TriggerKit/macros.json`) that the same library editor in the Macros tab edits in place, and any binding surface — buttons, chords, sequences, gestures, layers, the command wheel — can reference a shared macro through a new **Shared Library** section in every macro picker. Edits to a library macro propagate live to every profile that references it; exported and community profiles stay portable because each referenced program is snapshotted into the profile, and an intentionally-emptied live macro does nothing rather than resurrecting its snapshot. This is the first feature that lets a macro you build in one TriggerKit app show up in another, and it leads the 2.0 bump.

- **Small 8BitDo controller support (Zero 2, Micro, Lite 2, Lite SE)**: These tiny pads impersonate first-party controllers over Bluetooth — the Zero 2 and Micro clone a Pro Controller or DualShock 4 with no analog stick, funneling their physical D-pad through a phantom left-stick axis that macOS mis-calibrates (right often registered as left). ControllerKeys now reads the raw HID reports directly to recover the D-pad correctly on every reconnect, synthesizes the Micro's Home button (which macOS otherwise swallows), and ships product-accurate Buttons-tab previews traced from the official renders for all four pads. A behavioral stickless-clone detector — a real analog stick always sweeps through intermediate magnitudes, while a clone snaps center-to-full — distinguishes the impostors from genuine hardware, so real controllers are never affected. A new **D-Pad** stick mode lets any stickless pad act as a proper D-pad, and because the d-pad feeds the stick axis its mode dropdown also offers Mouse and Scroll — so the pad can drive the cursor or wheel directly. Stickless previews drop the controls these pads don't have (no analog sticks, and no triggers on the Zero 2), relabel the shoulders to match the hardware (L/R, plus L2/R2 on the Micro), and render the 8BitDo home button with its own logo.

- **Redesigned controller previews with photo-traced silhouettes**: The Buttons-tab controller graphic and the stream overlay were rebuilt from generic blob bodies into product-accurate previews for every supported controller — Xbox, Elite Series 2, DualSense, DualSense Edge, DualShock 4, Switch Pro, Steam Controller, the four small 8BitDo pads, and the Siri Remote. Bodies are traced from product photos at their true aspect ratios with per-model materials (carbon black, PlayStation white with light bars, the DS4 light bar, charcoal Pro), controls sit at their real hardware locations, and back paddles render with connector-line anchors — four metallic blades on the Elite, two on the DualSense Edge, four rear grips on the Steam Controller. Face buttons now follow each family's printed letters in their physical diamond, the stream overlay follows the connected controller type instead of being hardcoded to Xbox/PlayStation, and the whole set is backed by a documented photo-trace-to-Swift process so new controllers land at the same quality.

- **Pannable, location-anchored zoom on the buttons canvas**: The mapping canvas used to only zoom around its center. Now you can drag anywhere on empty canvas or a card background to pan, pinch-zoom is anchored at your fingers so the content under them stays put while the scale changes, and two-finger scroll pans directly. Button taps and drag-to-swap still win on the controls themselves. Double-click empty canvas or press Cmd+0 to re-center and reset the scale, and the pan offset is clamped so the canvas can't be flung out of view.

- **Pairing instructions when no controller is connected**: With no controller connected, the Buttons tab now shows a pairing-hint card above the canvas instead of silently rendering a default layout. With no specific model picked, it's a "No controller connected" chooser with a chip for every controller family that auto-connects the moment a controller enters pairing mode; pick a chip and it jumps straight to that model's steps. For a specific preview, the card shows step-by-step Bluetooth pairing for that exact controller, a wired/USB note, model tips, native-support caveats, and "Open Bluetooth Settings" / "Full Guide" buttons. Localized into German, Japanese, and both Chinese variants.

- **Controller layout preview picker**: A new layout menu above the input log lets you manually choose which controller layout the Buttons tab previews — handy for authoring a profile against a controller you don't have in hand. Layouts that match a currently-connected controller are marked, your pinned choice now persists across relaunches, and a small inline note warns when the layout you're previewing doesn't match anything connected.

- **Descriptor-aware SDL fallback and Controller Support Dump**: The generic-HID fallback now validates each SDL controller-database row against the live macOS HID element layout — non-macOS rows are only borrowed when every element they reference actually exists, duplicate database rows per controller are scored independently with later rows winning ties (matching SDL override order), and borrowed-mapping provenance like "SDL Windows fallback" is surfaced in the toolbar and menu bar. A new **Controller Support Dump** (Help menu, plus the no-controller toolbar/menu-bar entry points) exports an AI-prompt markdown alongside a raw HID layout JSON — with no serial numbers or location IDs — to make bringing up an unrecognized controller a copy-paste away.

### Changed

- **Macro execution now runs through the TriggerKit runtime**: Macros are converted to TriggerKit automation programs at execution time and run through the shared runtime instead of the app's own executor. Behavior is held identical — concurrent macros, continue-on-step-failure, the https-only link allowlist, and shell/webhook/OBS handling all carry over and are pinned by behavior tests — but macros now run off the main actor (a regression had inadvertently serialized them onto the UI run loop), held key/mouse/modifier presses replay their releases in reverse on any abnormal exit so a cancelled mid-sequence macro can't leave something stuck down, and emoji/flags/ZWJ sequences type correctly. The controller hot paths (button-to-key, joystick-to-mouse) are untouched.

- **Battery indicator hidden when no battery is reported**: Many controllers expose no battery level to macOS — notably the small 8BitDo pads in D-input mode, which are Bluetooth-Classic HID gamepads with no battery service of any kind. The preview now renders nothing in that slot instead of a permanent "?" gauge that read as broken. Controllers that do report battery are unaffected.

- **Marketing and documentation refresh**: All screenshots and demo GIFs were regenerated through a new reproducible capture pipeline, the German and Japanese READMEs were added (bringing the README to a four-language switcher), and website links now point at the live marketing page. None of this changes app behavior.

- **Test coverage and internal cleanup**: The shared-macro wiring, stickless-clone detector, macro executor contract, and the v1.9.3 audit fixes all gained regression tests, and several large source files were split into focused component files with no behavior change.

### Fixed

- **Apple TV Remote battery never showed**: The Siri Remote serves a standard battery service, but its Bluetooth name is a bare serial number, so the name-matching battery monitor never identified it. The monitor now accepts a connected serial-named peripheral while an Apple TV Remote is the active controller (resetting on disconnect so nothing else is misidentified), and the remote's mini preview and the menu-bar badge now show its battery level like every other controller.

- **Swipe-typing debug log growing unbounded**: Release builds were writing a `~/swipe_debug.log` file in the user's home directory that grew without limit. That logging is now gated behind DEBUG builds, and a few force-unwraps in the swipe-typing and indicator paths were replaced with safe lookups.

## [1.9.3] - 2026-06-09

### Added

- **Magicsee R1 controller mapping**: Generic HID fallback now recognizes the Magicsee R1 on macOS and maps its face buttons, triggers, sticks, Back, and Start controls through the SDL controller database.

### Fixed

- **Raw HID controller reliability**: ControllerKeys now filters generic HID input to controller collections when available, ignores stale fallback timers after disconnect, handles device-open failures without phantom controllers, resets stale controller-type flags between detections, and normalizes CRC-bearing SDL GUIDs so more database mappings resolve correctly.

- **Universal Control relay and input-state hardening**: Relay sends now recover from terminal connection failures, bound replay protection per peer, avoid redundant 120 Hz UI-state echoes, and keep hot-path handoff settings cached. Joystick ticks no longer hold mapping locks across network sends, haptics, or re-entrant button handling.

- **Text input and persistence edge cases**: Text typing now preserves full UTF-16 sequences such as emoji, pasteboard writes happen synchronously to avoid stale clipboard races, and queued profile/config saves flush during app termination.

### Changed

- **Test and CI coverage**: Added a GitHub Actions macOS test workflow, split the large test file into focused suites, added Magicsee R1 regression coverage, and made benchmark tests opt-in.

## [1.9.2] - 2026-06-08

### Fixed

- **Off-brand controller detection**: ControllerKeys now falls back to raw HID for controller-shaped devices that are missing from macOS GameController, including generic Bluetooth Low Energy gamepads and devices with known SDL vendor/product mappings. This lets many inexpensive third-party controllers appear as mappable controllers instead of showing "No controller."

- **Generic HID mapping coverage**: Fallback controllers now handle common D-pad hat encodings, version-zero and all-platform SDL controller database matches, trigger axis polarity, and axis-backed button polarity so more nonstandard controllers map their sticks, triggers, buttons, and D-pad correctly.

- **Generic HID false-positive guards**: The fallback path avoids inferring mouse-style HID devices as controllers, ignores non-HID controller database GUID rows when building vendor/product matches, and prefers macOS mappings when duplicate SDL GUIDs exist.

## [1.9.1] - 2026-06-08

### Added

- **Per-action scroll tuning**: Scroll Up / Down / Left / Right actions now carry their own speed and acceleration settings. Ordinary buttons, D-pad directions, and custom stick-direction mappings can all scroll smoothly while held, without relying on the global stick scroll settings.

- **Left/right modifier mapping support**: Modifier mappings can distinguish left and right Command, Option, Shift, and Control keys. Capture, keyboard visual selection, profile storage, macro execution, and Universal Control relay frames now preserve the selected physical side instead of collapsing everything to "any" modifier.

- **Shared keyboard profile settings**: On-screen keyboard profile settings now round-trip through profile storage, making keyboard-related profile choices visible and persistent alongside the rest of the active profile configuration.

### Changed

- **ControllerKeys config path now follows XDG-style storage**: The default config file moved to `~/.config/controllerkeys/config.json`, while legacy `~/.controllerkeys/config.json` and `~/.xbox-controller-mapper/config.json` remain readable for existing installs.

- **Scroll event plumbing cleanup**: Scroll delivery now routes through a typed `ScrollEvent` path, which keeps joystick, touchpad, button, relay, and zoom-related scroll behavior consistent.

- **UI accessibility and performance polish**: Added missing tooltips/accessibility labels to icon-only controls across mapping, keyboard, macro/script, command wheel, linked app/controller, and swipe typing surfaces. Date/ISO formatter use, favicon reads, visible-tab selection, and swipe custom-word checks were tightened to reduce avoidable work.

### Fixed

- **Universal Control shared-secret storage**: The relay shared secret now stays in Keychain instead of insecure local storage. Relay setup also handles Keychain persistence failures, gates key-event encoding more defensively, and clears remote-input grace state when a handoff is cancelled.

- **Custom scroll mappings**: Mouse-style scroll actions are available as first-class mappings, custom stick-direction scroll bindings repeat while held, diagonal custom direction keys are preserved, and smooth-scroll timers are cancelled when a chord resolves so a scroll button does not leak scroll events into its chord action.

- **Keyboard modifier side persistence**: Side-specific keyboard modifier selections now survive save/load and relaunch, including profile settings and keyboard visual state.

- **Mapping editor header wrapping**: Primary action section titles such as "Primary Action" no longer wrap into multiple lines when keyboard/mouse panels are collapsed.

- **Stream Deck import safety**: Stream Deck profile import now validates unzip process arguments to prevent argument injection through crafted archive paths.

## [1.9.0] - 2026-05-31

### Added

- **Apple TV / Siri Remote support**: ControllerKeys now recognizes the 2nd-generation Siri Remote (and other Apple TV remotes paired to your Mac over Bluetooth) as a first-class controller. The clickpad reports both touch and physical click, the surrounding D-pad ring maps to the four cardinal directions, and the side controls — TV/Home, Back, Play/Pause, Siri, Power, Mute, and the volume rocker — all show up as individually mappable buttons with their Apple-Remote labels (Clickpad / OK / ▶ / ← / TV) instead of Xbox names. A dedicated tall remote preview replaces the controller graphic when the remote is active, with the larger center clickpad target everyone keeps trying to tap. Wake from sleep automatically tears down and re-establishes HID monitoring after a short delay so the remote keeps working without a relaunch. The remote runs entirely over raw IOKit HID — no Apple TV or Home app required — and the new mic-research note documents why true Siri-button voice capture stays out of scope for now.

- **Clickpad edge scroll for Apple TV Remote**: New Touchpad settings section (visible only when an Apple TV Remote is connected) exposes an **Edge Scroll** toggle and **Scroll Speed** slider. Dragging your finger around the outer ring of the clickpad scrolls the foreground app in the same iPod-wheel motion the remote already uses on tvOS. Once a circular scroll gesture starts, ownership latches to scroll for the rest of the touch — brushing back through the center no longer flips the gesture back into mouse movement mid-stroke. Lift your finger to release the latch and the next touch can drive the cursor again.

- **Script names on chord rows**: Chords (and their preview rows in community profile imports) bound to a script now show the script's name in the active-chords overlay and the chords list, matching how macros already display. Previously a script-backed chord showed a generic action string, making it hard to identify what a chord actually did at a glance.

### Changed

- **Steam Controller gyro aiming feel**: Reworked focus-mode gyro aiming on the Steam Controller. Horizontal gain now uses a Steam-specific boost so left/right turns feel proportional to vertical tilt, the 1-Euro smoothing filter is bypassed in favor of the raw rate (the Steam Controller's IMU is clean enough that smoothing only added input lag), and the default sensitivity multiplier moved from 2.0 to 2.4 so the cursor actually reaches edges of a 5K display in a single sweep. Pair this with the haptics fix below for a noticeably tighter aim experience.

- **Floating panel for Mac-to-Mac pairing code**: The "show pairing code" flow no longer pops a blocking `NSAlert.runModal()` that activated the app and stole controller-mouse routing for the duration. The pairing code now appears as a nonactivating floating toast panel with a dismiss button (Escape works too), and pairing-result errors are surfaced inline in the Universal Control settings panel instead of as a follow-up alert. Controller-driven pointer input keeps routing the whole time, so you can finish a handoff or hand the pairing code off to a peer without the host Mac going inert.

### Fixed

- **Stuck Steam Controller gyro drift on focus-mode entry**: Entering focus mode while gyro aiming was enabled would re-apply stale accumulated motion samples and a stale 1-Euro filter state, so the cursor lurched in the direction of the last gesture and then drifted until the bias re-converged. Focus-mode entry now clears accumulated rates, resets the smoothing filter, and re-runs the Steam Controller bias calibration. The calibration itself is deferred ~110 ms past the focus-entry haptic so the buzz doesn't contaminate the new zero-rate baseline.

- **Touchpad click-induced cursor jitter on Steam Controller and Apple TV Remote**: A physical clickpad press on either device tended to shift the finger 1–2 mm in the moment the switch actuates, which the cursor would faithfully report as movement. Both pipelines now arm a short suppression window on click-down: tracked finger motion under the click-movement threshold is ignored until the user either lifts the finger or moves far enough to clearly be a drag. One physical click stays one click in place, instead of one click plus a small involuntary nudge.

- **Apple TV Remote volume and Mute keys colliding with Mac keyboard media keys**: The previous Apple TV Remote system-event suppression was overly broad — it dropped Volume Up / Volume Down / Mute / Power even when those events originated from your Mac's keyboard, because the suppression check didn't require correlation with an actual remote HID button report. Suppression is now gated on either an active Apple TV Remote system key or an explicit short-lived correlation timer set when the remote itself fired the key. Keyboard media keys pass through normally, while the remote's volume rocker keeps suppressing the duplicate macOS HID volume event it would otherwise generate.

- **Elite Series 2 paddles in layer activators, mapping resolution, and the controller preview**: P1–P4 paddles are now treated as edges of the same logical control as the equivalent DualSense Edge paddle/function button: layer activators bound to a paddle fire when the physical Xbox paddle is pressed, the controller preview lights up the right paddle slot, mapping lookups fall back through the logical equivalent so a profile authored against `leftPaddle` still works on Xbox Elite, and the swap-mode logic recognizes the held button. Previously paddles could silently fail to trigger their bound action depending on how the binding was authored.

- **Controller mouse motion stuck after edge-handoff handshake**: When the Mac-to-Mac relay was activating, the local cursor would briefly post off-screen `CGEvent` positions to "feel out" the handoff edge, which could trigger WindowServer / Universal Control edge-routing latency and leave the local cursor feeling stuck for a beat. Local mouse posting now always clamps to screen bounds, and movement is only routed to the remote once the remote has confirmed it has the cursor — closing the brief dead zone between handshake start and confirmation.

- **Pairing-code prompt could not be dismissed**: The new floating pairing-code panel didn't accept mouse or keyboard input — it was `ignoresMouseEvents = true` with no close affordance, so the only way to dismiss it was to wait out the 60-second timer. The panel now accepts key focus, has an explicit close button, and binds Escape to dismiss.

## [1.8.3] - 2026-05-28

### Changed

- **README refresh**: Updated the English and Simplified Chinese READMEs to reflect recent ControllerKeys features, including Steam Controller support, realtime input mode, linked controllers, profile snapshots, Mac-to-Mac relay, grouped navigation, localized UI coverage, and expanded controller support.

### Fixed

- **Mac-to-Mac relay edge handling**: Controller-driven local cursor tracking now stays clamped in-bounds at display edges, so edge movement no longer builds hidden overshoot or feels sticky. Plain mouse movement can still post past an edge when no configured relay handles it, preserving normal macOS handoff behavior.

- **Bidirectional Mac-to-Mac handoff**: Removed the Mac Studio receiver-only hostname heuristic. Any paired Mac can now both receive remote pointer input and initiate handoff back to its peer.

- **Remote pairing code entry**: Widened the six-digit pairing-code field so the full code stays visible while entering the final digit.

- **Remote handoff cursor visibility**: Remote pointer handoff now avoids over-balancing cursor show/hide repairs after on-screen keyboard navigation and keeps portal overlays below screen-saver level, preventing an invisible-but-hovering cursor during bidirectional controller sessions.

## [1.8.2] - 2026-05-27

### Added

- **Realtime input latency mode**: New per-profile Input section under Hardware. Realtime mode sends simple key mappings as key-down on press and key-up on release, bypassing the normal chord window for buttons that are not part of chords. Double-tap, long-hold, repeat, and chord mappings stay on the standard timing path so advanced interactions keep their existing behavior.

- **Linked controllers**: Profiles can now bind to the currently connected controller and auto-activate when that controller connects. Linked Apps keep precedence over Linked Controllers when the frontmost app has its own linked profile, matching the UI copy in the linked-controller sheet.

- **Profile sidebar status indicators**: Profile rows now show small Linked Apps icons next to the profile name, plus compact badges for realtime input mode, linked controllers, custom profile icons, and the default profile.

- **Steam Controller support**: ControllerKeys now detects the Steam Controller over raw HID without requiring Steam to run. The app parses Steam Controller buttons, sticks, triggers, grip buttons, battery reports, haptics, gyroscope motion, and both square touchpads directly, while ignoring the duplicate macOS GameController route so inputs are not double-processed.

- **Steam Controller preview and touchpad mapping UI**: The Buttons tab now has a dedicated Steam Controller preview layout with symmetric sticks, physical D-pad/face-button placement, a Steam-logo system button, a three-dot menu/share glyph, and live touch points on both square touchpads. Steam touchpads can run in Whole Pad or Quadrants mode; in Quadrants mode, each pad splits into four independently mappable click/touch regions.

- **Steam Controller gestures and feedback**: Steam Controller touchpads now support two-pad pinch-to-zoom, touchpad haptics, gyro aiming, and gyro gesture mappings through the same mapping and focus-mode systems used by other controller families.

### Changed

- **Input latency mode comparison**: The profile Input section now compares Standard vs Realtime modes more explicitly, including the tradeoff that Realtime is lower-latency for simple held key mappings while Standard keeps the timing window needed for chords, double-tap, long-hold, and Repeat while held behavior.

- **Steam Controller button presentation**: Steam-specific button icons now render in mapping rows, chord/sequence editors, active lists, the input timeline, and the controller preview instead of falling back to Xbox labels.

- **Steam Controller touchpad feel**: Touchpad movement, click movement thresholds, swipe typing, and two-pad pinch sensitivity were tuned for the Steam Controller's noisier square pads. Swipe typing now uses the normal cursor path by default and only switches to the swipe cursor while the user holds left click.

- **AnKing community profile docs**: Clarified which bindings are stock Anki, which are AnKing notetype cloze controls, and which still depend on contributor-specific addons.

- **Monterey compatibility triage**: Added an audit note for macOS 12 support, including known SwiftUI blockers and a legacy-build decision gate.

### Fixed

- **Held diagonal movement mappings**: WASD/arrow-key stick presets and D-pad presets now hold independent cardinal keys instead of treating directions as mutually exclusive taps, so diagonal movement works smoothly in games such as Factorio.

- **Steam Controller detection and default command suppression**: Steam Controller input is now owned by the raw HID path, avoiding the duplicate GameController path and suppressing stray default commands such as the left menu/select button sending Tab alongside its mapped ControllerKeys action.

- **Steam Controller scroll direction and lizard-mode handoff**: Touchpad scroll inversion settings now cover PlayStation and Steam touchpads, Steam left-pad horizontal panning follows the expected webpage-pan direction, Steam input is held back until lizard mode is actually disabled, and ControllerKeys keeps macOS' "ignore built-in trackpad when mouse is present" behavior disabled so the Steam Controller puck does not disable the built-in trackpad.

- **Steam Controller touchpad click/tap reliability**: Physical touchpad clicks now debounce press bounce, delay release through click wobble, suppress nearby tap dispatch, and ignore click-induced thumb drift so one physical click stays one mapped click even when the finger moves slightly.

- **Steam Controller two-pad pinch isolation**: While both pads are actively participating in a pinch gesture, single-pad cursor movement, scrolling, and touchpad actions are latched out. Resting one finger on one pad while using the other pad still works.

- **Steam Controller cursor and gyro behavior**: Steam touchpad deadzones and click thresholds reduce cursor jitter while resting a thumb or holding a window. Gyro aiming now handles horizontal movement more consistently, the purple focus-mode ring follows the gyro-driven cursor, and gyro gestures use the Steam Controller's raw gyro scale so turn left/right and tilt forward/back trigger at usable sensitivity.

- **PlayStation linked-controller ambiguity**: DualSense, DualSense Edge, and DualShock 4 identity matching now avoids binding a profile to the wrong physical controller when multiple PlayStation HID devices are present. Mixed DualShock 4 + DualSense setups now filter HID candidates to the active controller model before showing or binding the current controller. When the app cannot prove the matching HID interfaces belong to one physical controller, PlayStation-only HID extras such as PS, mic, and Edge buttons are disabled until the ambiguity clears.

- **Script execution cleanup**: Script runs now clear JavaScriptCore exception state and cancel timeout timers via deferred cleanup, reducing stale-state risk after script errors or timeouts.

- **Test-suite side effects**: App startup skips live update checks, battery monitoring, Universal Control relay listening, and stream-overlay restoration while running unit tests.

## [1.8.1] - 2026-05-14

### Added

- **Per-layer stick mode override**: Each layer can now override the **Mouse / Scroll / WASD / Custom** mode of either stick, independent of the profile-level default. Edit a layer in the Buttons tab and pick a mode from the inline dropdown on the stick — that choice applies only while the layer is active; release the activator and the base mode resumes. A new **Inherit from Base** menu item drops the override; inherited values render in italic so it's obvious which stick is layer-scoped vs. profile-scoped. Addresses [#14](https://github.com/NSEvent/xbox-controller-mapper/issues/14) — previously the inline mode dropdown silently wrote to profile-level state regardless of which layer was being edited, so customers swapping `Mouse`/`Scroll` per layer found the change leaking to all layers. Profile-level mode still lives in the Joysticks tab; the rest of the joystick tuning (sensitivity, deadzone, acceleration) stays profile-level for now and can move per-layer later if anyone asks.

- **Inert direction-binding warning**: When a layer (or the base) has custom stick-direction button mappings but the effective stick mode for that side isn't Custom — i.e. the bindings won't fire — a small orange warning appears next to the stick's mode dropdown explaining that switching to Custom is required. Prevents a silent-no-op confusion that's easy to land in after toggling mode away from Custom.

- **Layer-aware controller minimap**: The controller minimap now shows a compact `BASE` / `LAYER <name>` chip and outlines layer-specific overrides in that layer's color on both the mapping tiles and the physical controller controls. Face buttons, sticks, shoulders, D-pad directions, system buttons, and touchpad regions all pick up the same color language, making it easier to see what the current layer changes at a glance.

- **Menu bar battery badge**: The menu bar popup now shows the connected controller's battery level in the header, matching the main window's known/unknown battery policy.

### Changed

- **Main window tint default**: The main window background tint now uses a softer dark gray with a higher default opacity, improving contrast over the liquid-glass backdrop while avoiding a flat black pane.

### Fixed

- **Xbox battery notification race**: Xbox controllers no longer briefly report an unverified `0%` battery level when they first connect. ControllerKeys now waits for the Bluetooth Battery Service reading before showing battery state or firing low-battery notifications, so the app and notification agree. Closes [#18](https://github.com/NSEvent/xbox-controller-mapper/issues/18).

- **Elite Series 2 stale Guide recovery**: Centralized stale Guide-button recovery across the Elite helper and controller service callback path so missed release callbacks do not leave Guide stuck after routing handoffs.

## [1.8.0] - 2026-05-13

### Added

- **Universal Control-style remote mouse relay between Macs**: New Settings → Universal Control panel lets you pair two ControllerKeys-running Macs by exchanging a one-time pairing code. Once paired, push your controller's cursor against the configured screen edge to seamlessly hand off mouse, keyboard, and *button-mapped actions* to the second Mac — the receiving Mac runs the actions against its own active profile, so a chord that opens Finder on the host opens Finder on the remote. Reverse handoff brings the cursor home. Pairing is local-network only (private/link-local IPv4/IPv6, Tailscale `100.64.0.0/10`, localhost), every frame is HMAC-SHA256 authenticated with a Keychain-stored shared secret, and oversized/replayed/tampered frames are dropped. Portal indicators on both screens light up when the cursor enters or returns through a handoff zone, swipe typing and on-screen overlays relay through the same channel, and the receiving cursor stays visible whether or not the remote app is frontmost. See `SECURITY.md` for the full threat model — this is the first feature in the app that touches the network and it is deliberately conservative.

- **Custom stick direction mappings (WASD / Arrow keys / anything else)**: Set either stick's mode to **Custom** in the Joysticks tab and each of its 8 directions (4 cardinal + 4 diagonals) becomes a real `ControllerButton` you can bind from the controller graphic. One-click presets seed the four cardinal directions with WASD or Arrow Keys; from there you can override individual directions, add long-hold/double-tap variants, or chain them into chords and sequences — stick directions are now first-class buttons everywhere a regular button is. Replaces the old hard-coded `wasd` / `arrowKeys` stick modes, both of which auto-migrate into Custom mode with the matching preset applied.

- **Profile snapshots and undo via new History tab**: ControllerKeys now silently snapshots your full configuration before every destructive operation (deleting a profile, importing a profile, restoring an earlier snapshot). The new global **History** tab lists snapshots with their trigger reason and lets you restore any of them — the restore itself is snapshotted first, so undoing is itself undoable. Snapshots live at `~/.controllerkeys/snapshots/` (capped at 20, separate from the existing 5-deep auto-backup ring) and the History tab live-updates when a new snapshot lands instead of waiting for a tab switch.

- **Profile-import safety prompts (replaces the shell-command blocklist)**: When you import a profile — community, file, or Stream Deck — that runs any shell command, opens any script, or fires a webhook with a shell follow-up, a new sheet lists every code-execution surface verbatim (button context, macro step, layer long-hold variant, webhook on-success/on-error commands, embedded macro `KeyMapping`s, etc.) and requires an explicit **Import Anyway** confirmation. Replaces the prior 40+ regex blocklist in `SystemCommandExecutor`, which gave false confidence — every syntax-level shell filter is trivially bypassable via `eval`, process substitution, or `IFS=`, so the right place for a code-execution policy is informed consent at the import boundary, not pretend-sandboxing at execution time. The auditor walks every binding type (chords, sequences, gestures, layer mappings with their long-hold and double-tap variants, macro `.press`/`.hold` steps and their embedded mappings, command wheel actions, touchpad regions, scripts) with compiler-enforced exhaustiveness, so adding a new binding type can't silently bypass it.

- **Community profile setup guides**: Community profiles can now ship a `<name>.md` sidecar alongside their JSON, and the preview panel renders it inline above the mappings list — full block-level markdown (headings, GFM tables, fenced code blocks, lists, blockquotes), with a copy button on every code block (1.5-second green-checkmark confirmation) for the inevitable `defaults write` / Anki snippet / shell incantation users would otherwise transcribe by hand.

- **Anki - AnKing (USMLE) community profile**: Three-layer profile for medical students reviewing Anki decks with the AnKing Overhaul note type. Base layer covers review (Again/Hard/Good/Easy on the face buttons), shift layer 1 handles productivity, shift layer 2 jumps directly to First Aid / Sketchy / Pathoma / etc. sections via Opt+Shift+digit chords consumed by a small JS snippet pasted into the Back Template. Works on Xbox, DualSense, and DualShock 4. Contributed by `anonrandomdoc` on Discord. The sidecar markdown setup guide documents every Anki-side prerequisite — without it, Layer 2 fires keystrokes Anki has no handler for.

- **Redesigned main window navigation with grouped tabs**: Tabs are now organized into four nav groups — **Map** (Buttons / Chords / Sequences / Gestures), **Automate** (Macros / Scripts / Wheel / Keyboard), **Hardware** (Joysticks / Touchpad / LEDs / Microphone), and **Activity** (Stats / History) — with the group switcher above the per-tab row. Each tab also gained an SF Symbol icon, and the input log was rebuilt as a compact "Timeline" strip with a placeholder state when no presses have happened yet. Considerably less to visually parse when you're in a tab you haven't used before.

- **Hide individual sections in the Buttons tab**: New Settings toggles let you hide the input log, mapped chords/sequences/gestures lists, or the touchpad regions section from the Buttons tab. The controller graphic and tab bar always stay visible — only list-style sections are hideable.

- **Window background opacity setting**: New Settings → Appearance slider controls how opaque the main window's dark tint is over the liquid glass background. Addresses the issue where the window picked up too much color from underlying apps, making content harder to read. Defaults to 30% (mostly glass, with enough tint to dampen color bleed-through); drag it to 0% for pure liquid glass or 100% for a fully opaque dark background. The previous `Color.black.opacity(0.92)` tint had been placed behind the visual effect view in the ZStack so it never actually rendered — now layered on top so the opacity is meaningful.

### Changed

- **Shell-command blocklist removed in favor of informed consent**: `SystemCommandExecutor`'s 40+ regex `dangerousShellPatterns` and `validateShellCommand` are gone. Shell commands run as the user with full permissions, so any syntax-level filter is bypassable; the new import-time safety prompt is where the actual policy now lives. The only remaining execution-time check is "command must not be empty."

- **Atomic file writes preserve symlinks**: Every code path that writes config, profiles, snapshots, backups, swipe-typing model state, favicon cache, scripts, and debug logs now resolves symlinks before writing. Previously, `Foundation.write(to:atomically:)` would replace the symlink with a regular file at the link's path — fine for normal users, but it broke setups where `~/.controllerkeys/config.json` was symlinked into a dotfiles repo or cloud-synced folder. All writers route through a single `AtomicFileWriter` helper now, so this stays consistent.

### Fixed

- **Elite Series 2 paddle handling restored after the BLE refactor**: The 1.7.7 BLE work that fixed Guide-button crosstalk also broke paddle reporting on the same firmware — paddle bits were being read against the old 11-button descriptor offsets. The Elite helper now enumerates each device's HID descriptor at connection time, caches whether it has extended buttons (>15 button usages) and whether it exposes Consumer Page AC Home (0x0223), and routes each report variant — Classic BT, BLE, and USB — through the correct paddle bitmask. The helper also gained a `--guide-only` mode for environments where GameController already exposes paddles, and the paddle bit order is corrected (P2 = upper right, P3 = lower left, matching the `GCXboxGamepad` convention).

- **Elite Series 2 Guide-button routing on mixed firmware**: Hardened the guide-monitor's per-device descriptor classification so a Classic BT Elite 2 connected over USB (which exposes both Consumer AC Home and 17 buttons) and a BLE Elite 2 (which uses Button Page 13 but no AC Home) each route Guide through the right HID usage. Adds explicit test coverage for the four descriptor combinations.

- **Touchpad whole-pad/quadrants mode now respects explicit user choice on v3 configs**: After 1.7.10's quadrants migration, switching back to whole-pad mode would silently flip to quadrants on every relaunch as long as any leftover quadrant button mappings sat in the profile. Decode now distinguishes v3 configs (which always write `touchpadInputMode` and must be honored verbatim) from v1/v2 configs (which omit the field and have to be inferred from data shape). The migration step only auto-flips when it actually drained legacy v1 entries this pass.

- **Stuck buttons when a controller hands off mid-press to a remote Mac**: When the cursor crossed a handoff zone with buttons held, the remote receiver never got the press events and the local Mac never got the release events, leaving inputs hanging on both sides. `endRemoteSession` now sends an explicit `bclear` reset frame before handing back, and the receiver's `MappingEngine` clears its `pressedButtons` and `heldModifiers` on session start and end.

- **Remote cursor escaping past the handoff edge**: Without explicit handoff zones, fast diagonal movement could push the relay cursor across both the host edge and the receiver edge in a single frame, "escaping" through both sides. Edges are now configured explicitly (left/right/top/bottom) instead of inferred from cursor velocity, default to a conservative single-edge layout, and the remote session keeps state across brief idle windows so the cursor doesn't snap home on the first frame where the stick centers.

- **Remote cursor not restored after reconnect or idle**: Several follow-ups after the initial relay landing — the cursor stays visible on the remote Mac when ControllerKeys isn't frontmost there, the on-screen keyboard manager re-shows the cursor when the session ends, and the relay survives a short network hiccup or controller idle without tearing down and rebuilding the whole session.

- **Pairing-code text field jitter while typing**: The Settings pairing UI was rebuilding the field on every keystroke, dropping focus and re-rendering caret position. Field state is now held locally with `@FocusState` and only commits to the backing store on submit.

## [1.7.11] - 2026-05-08

### Added

- **Disable Touchpad as Mouse**: New per-profile toggle in Touchpad settings stops single-finger swipes from driving the system cursor. Two-finger gestures, taps, region clicks, and swipe typing keep working. Applies to DualSense, DualSense Edge, and DualShock 4 — all three share the same touchpad pipeline.

### Fixed

- **Command wheel showing immediately when on-screen keyboard held**: Holding the OSK button revealed the command wheel right away. Now the wheel stays hidden until the right stick crosses the deadzone, so the keyboard is visible alone unless the user opts in by moving the stick. The standalone command wheel trigger still shows the wheel immediately on press.

## [1.7.10] - 2026-05-08

### Added

- **Touchpad quadrants as first-class buttons**: New per-profile **whole-pad vs quadrants** input mode. In quadrants mode, each of the 4 touchpad regions becomes two real `ControllerButton` cases (Click and Touch) so layers, long hold, double tap, and repeat all work on per-quadrant bindings via the standard button machinery. Whole-pad mode keeps the classic 4 touchpad buttons. Two-finger buttons stay active in both modes. Existing chord/sequence mappings keep working — quadrant clicks alias to `.touchpadButton` and quadrant touches to `.touchpadTap` so nothing fires twice. Schema bumped to v3 with full migration: v1 region rows fan out to Click/Touch buttons (`.both` fans out to both variants — no data loss for dual-action quadrants); profiles with quadrant data auto-switch to quadrants mode.
- **Configurable main window sections**: New Settings panel lets you toggle visibility of individual sections in the main window. Hide what you don't use to keep the UI focused.
- **Open Main Window menu bar item**: When "Hide Dock Icon" is enabled, the menu bar now exposes an explicit "Open Main Window" command so the window remains reachable without the Dock.
- **Localizations: German, Japanese, Traditional Chinese**: New `de`, `ja`, and `zh-Hant` `.strings` catalogs mirror the existing `zh-Hans` entries (510 keys each, all passing `plutil -lint`). Traditional Chinese uses Taiwan/Apple-Mac vocabulary (巨集 / 指令碼 / 觸控板 / 設定檔 / 對應) rather than a script-only conversion from Simplified.

### Changed

- **Hide Dock Icon lifecycle**: Replaced the static `LSUIElement`-style activation policy with a `DockVisibilityController` that ties dock-icon visibility to user-facing window visibility. Window state changes now drive the activation policy directly, so closing/reopening the main window behaves predictably while Hide Dock Icon is on.
- **Touchpad button clearing now actually disables the action**: `ButtonMappingResolutionPolicy.defaultMapping` no longer hardcodes mouse click as a fallback for cleared touchpad buttons. First-run defaults are unchanged (still populated by `Profile.createDefault`), but explicitly clearing a touchpad binding now leaves it disabled.

### Fixed

- **Touchpad quadrant click misfires after finger lift**: Stale `(x, y)` positions reported by the controller after a finger lift were being misclassified as quadrant clicks. New `requireActiveTouchForRegionClick` setting (default on) suppresses these; the classification helper was extracted for unit testing.
- **Touchpad quadrant connector lines land on the wrong quadrant**: Anchor placement in SwiftUI's preference machinery wasn't propagating per-quadrant rects reliably. The eight `.touchpadRegion*` anchors are now siblings on `miniTouchpad`'s outer chain alongside the whole-pad anchor, and `ConnectorLayer` slices the shared rect down to each quadrant's quarter at draw time so the line terminates at the correct corner.
- **Touchpad quadrant action detection**: Fixed the resolution path so the correct quadrant action fires for both touch and click in all four regions.
- **Layer activator badge shown on inert activators**: The "L" badge in the corner of a button icon advertised "this button activates layer X" — but when the user is already inside a different layer those activators are dimmed and don't function as activators. Badge is now gated on the same `isEditingDifferentLayer` check the label area uses, so it only shows on the base view and on the current layer's own activator.

## [1.7.9] - 2026-05-07

### Added

- **Hover-revealed connector lines**: Hovering any mini button on the controller graphic or any action label row draws an accent-color Bezier curve between the two, terminating at the action box edge facing the controller. Makes the spatial mapping between physical buttons and their actions explicit, REWASD-style. Lines are on-demand: the resting state shows nothing.
- **Drag-and-drop to swap button mappings**: Any action label row or mini button on the controller graphic can be dragged onto another to swap their mappings. Mirrors the existing tap-select-tap swap mode (uses base-layer or layer-specific swap depending on context). Drop targets glow in the accent color and scale up while a drag is hovering them.
- **Drag-and-drop to swap touchpad region mappings**: Each touchpad quadrant cell in the region editor is now both draggable and a drop target. Dropping one quadrant onto another swaps all of their mappings (touch + click) together. Same glow + scale-up drop-target feedback as the button swap.
- **DualShock 4 lightbar control**: The lightbar tab now works for DS4 over both USB and Bluetooth. macOS's `IOHIDDeviceSetReport` returns success but silently drops user-space HID output reports for controllers managed by the GameController framework, so we route DS4 BT through `GCController.light` (the same privileged path DualSense uses). USB uses raw HID output report 0x05 with the correct Linux `hid-playstation` byte layout.
- **DualShock 4 gyroscope support**: Gestures (tilt/snap mappings) and gyro aiming both work on DS4. Apple's `GCMotion` exposes the API but the rotation rates are always zero, so we parse the gyro from raw HID input reports. Auto-calibrates the gyro bias from the first ~60 samples after motion enable to fix asymmetric drift between left/right tilts.
- **Layer-aware lightbar**: Each layer can have its own lightbar color that activates while the layer is held. New layers get a distinct color auto-assigned from a 12-color palette. Configure via the layer editor or right-click "Change Color…" on a layer tab. Layer activator badges in the tab bar and on the controller view are tinted with the layer's color.
- **Flexible layer modifier behavior**: When a layer is already active, other layer activator buttons are freed up — they no longer activate their own layers and can be remapped within the current layer. Pressing the same activator with no other layer active still activates its layer as before.
- **Touchpad quadrant remapping**: Split the DualSense/DS4 touchpad into 4 regions (top-left, top-right, bottom-left, bottom-right). Each region can have separate actions for touch and click (or the same action for both via a `.both` mapping). Region action takes precedence over the regular touchpad button/tap when fired.
- **Command wheel shows immediately on hold**: The command wheel now appears as soon as the assigned button is held, rather than waiting for stick movement past the deadzone.
- **Hide Dock Icon option**: New Settings toggle that switches the app's activation policy to `.accessory`, hiding the Dock icon while keeping the menu bar icon. Applied immediately and on next launch.
- **Visible lock state**: When the controller is locked, the lightbar turns solid red and the menu bar icon shows the gamecontroller dimmed at 45% with a red lock symbol overlaid. Lock state restores the layer/profile color (and re-enables battery-light-bar mode) on unlock.
- **Per-quadrant action display**: Touchpad region cells now use the same `MappingLabelView` the buttons tab uses, so hints, system command badges, and macro names render consistently.

### Fixed

- **Controller lock from double-tap or long-hold**: Special action keycodes (controller lock, laser pointer, on-screen keyboard, directory navigator) were only intercepted on primary press, sequence, and chord paths. Mapping controller lock to a double-tap or long-hold sent the bogus internal keycode (0xF012) as a real keypress to macOS instead. Now intercepted correctly.
- **Unlock via the same gesture used to lock**: When locked, double-tap or long-hold timestamps are still tracked for buttons whose alternates resolve to controller lock. After unlocking, the press is marked consumed so the regular single-tap action doesn't fire spuriously.
- **Lightbar reverts after layer release**: After applying a layer's LED settings on release, also call `updateBatteryLightBar()` so battery-light-bar mode resumes when the profile uses it; without this, the next periodic battery update would override the revert color.
- **Command wheel parity for app launch**: `SystemCommand.launchApp` now hides the app if it's already frontmost (matches the keyboard command wheel's app-toggle behavior) for the non-newWindow case.
- **Touchpad region action firing alongside regular click/tap**: When a region mapping fires for a click or tap, the regular `.touchpadButton` / `.touchpadTap` action is now suppressed for that event so only the region action runs.
- **Touchpad region corner clicks misclassified**: Clicks where the finger position is reported as `(0, 0)` (no real position registered) no longer mis-classify as bottom-left and instead fall through to the base touchpad click action.
- **AppleScript injection in Safari incognito**: Quotes in URL strings are now escaped before being interpolated into AppleScript.
- **Elite Series 2 paddle bit mapping**: P2 and P3 paddles were swapped on Classic BT firmware versus the `GCXboxGamepad` convention.

## [1.7.8] - 2026-05-05

### Fixed

- **Chords/Sequences broken after disable→enable cycle**: Fixed chord mappings, sequence mappings, and layer activators silently stopping after any mapping engine disable/re-enable cycle (e.g., controller lock toggle, app auto-disable). The precomputed lookup caches were cleared on disable but never rebuilt on re-enable.

## [1.7.7] - 2026-05-04

### Fixed

- **Elite Series 2 Guide/Paddle Crosstalk (Classic BT Firmware)**: Fixed B button triggering the Xbox Guide button on Elite Series 2 controllers with older (pre-BLE) firmware. The Elite 2 has two firmware variants with completely different HID descriptors — old firmware (Classic BT, PID 0x0B05) puts paddles on Button Page usages 11-14 where usage 13 collides with Guide on newer controllers, while new firmware (BLE, PID 0x0B22) uses 15-button descriptors where usage 13 IS Guide. The monitor now enumerates each device's Button Page elements at connection time and only treats usage 13 as Guide on 15-button descriptors. Usage 17 (Guide on USB/Classic BT) always works regardless.

## [1.7.6] - 2026-04-28

### Added

- **Xbox Elite Series 2 Full Support**: Reliable detection by USB product ID (works regardless of hardware profile or firmware version), correct "Xbox Elite Series 2 Controller" name in the UI, and dedicated Elite paddle section.
- **Elite Series 2 Guide Button**: The Xbox/Guide button now works on the Elite 2 via IOKit HID input value callbacks, bypassing the GameController framework's `buttonHome` handler which never fires for this controller over Bluetooth.
- **Elite Series 2 Paddles via HID**: All 4 back paddles (P1–P4) are detected through Consumer Page usage 0x81 bitmask on firmware 5.x+ where `GCXboxGamepad.paddleButton1-4` are always nil. Works independently of the Xbox Accessories app profile configuration.
- **Elite Helper Process**: Bundled standalone helper binary (`XboxEliteHelper`) that monitors the Elite 2 via IOKit HID without the GameController framework, for environments where `gamecontrollerd` blocks direct HID access.
- **Command Wheel**: Standalone command wheel with per-profile action support and configurable items.
- **Custom Tab Bar**: Replaced native macOS TabView with a custom tab bar using the app's dark glass style. Per-profile tabs use accent highlight, global tabs (Keyboard, Stats) use muted highlight, grouped into separate rounded containers. Keyboard and Stats tabs are now positioned last as global settings.
- **Scalable Command Wheel Editor**: The wheel preview in the Wheel tab now scales with available space and mirrors the actual command wheel's appearance (dark material backdrop, accent highlights, scale effects, shadow styling). App and website icons stay in full color.

### Fixed

- **Elite Series 2 RT False Trigger**: Removed raw HID report callbacks that caused the right trigger to false-trigger the Xbox/Guide button. The Elite 2 exposes two HID interfaces with different report layouts — byte 11 is button data on one but analog trigger data on the other.
- **Elite Series 2 Share Button Hidden**: The Elite 2's Share button is a firmware-only hardware profile cycle button (not mappable), so it is now hidden from the UI when an Elite controller is detected.
- **SwiftUI Elite State Timing**: Fixed Elite UI not appearing by deferring `objectWillChange` to ensure SwiftUI re-reads storage flags after `setupInputHandlers` completes.
- **Command Wheel Row Click**: Row click now opens the editor, info style matches keyboard tab.
- **Input Log Bar Styling**: Restyled the button feedback bar to match the app's dark glass style (rounded container with subtle border) for visual cohesion.

## [1.7.5] - 2026-04-27

### Added

- **Update Notifications**: The app now checks GitHub Releases on launch (once per day) and shows an in-app alert when a newer version is available, with a link to download from Gumroad. Users can skip a specific version or snooze the reminder for 3 days.

### Fixed

- **Bluetooth Reconnection Input Loss**: Fixed a race condition where a controller would reconnect (vibrate confirming connection) but all input—button mappings, mouse cursor, everything—would stop working. Caused by macOS delivering a late `GCControllerDidDisconnect` notification *after* `GCControllerDidConnect` during Bluetooth reconnect, tearing down the just-established connection. The disconnect handler now verifies the controller is actually gone from the system before processing.
- **Button Mapping Sheet Clipping**: The button mapping sheet content was clipped on left/right edges because the system command category picker labels exceeded the sheet width. Widened the sheet and shortened picker labels.

## [1.7.4] - 2026-04-25

### Added

- **Xbox Elite Series 2 Back Paddles**: All 4 back paddles (P1–P4) are now detected and mappable via Apple's `GCXboxGamepad` API. Upper and lower paddle pairs use distinct SF Symbols (outline vs filled) and positional names for easy identification. Paddles appear in the "ELITE PADDLES" section on the main view, chord editor, and sequence editor when an Elite controller is connected. Note: paddles only report when no hardware remapping profile is active on the controller (all 3 front LEDs unlit).

## [1.7.3] - 2026-04-24

### Added

- **Quick-Clear Context Menus**: Right-click any button, chord, sequence, or gesture mapping row to clear all actions in one click. Chord and sequence clear preserves the button combination / steps while removing the mapped action. Also adds "Delete" option for chords and sequences.
- **HTTP Response Handling**: Webhooks now support response capture with configurable retry (exponential backoff, up to 5 attempts), macOS notifications on completion, configurable timeout, and follow-up shell commands for success/error paths. New "Response Handling" section in the webhook configuration UI.

### Fixed

- **Modifier Key Stuck State**: Added consistency check in InputSimulator to force-remove modifiers stuck in `heldModifiers` when their reference count reaches zero, preventing keys from staying held after rapid overlapping button releases.
- **Zoom Cache Thread Safety**: Protected `cachedZoomActive` and `cachedZoomCheckTime` with NSLock to prevent data races across threads.
- **Zoom Accumulator Data Race**: Wrapped accessibility zoom accumulator updates with `stateLock` to prevent corruption from concurrent scroll events.
- **Zoom Warning Panel Orphaning**: Added 30-second auto-dismiss timer to the zoom keyboard shortcut warning panel to prevent orphaned windows.
- **Gesture Detector Not Reset on Profile Change**: Motion gesture detector pitch/roll state machines are now reset when switching profiles, preventing a mid-tracking gesture from Profile A completing in Profile B.
- **Null Profile Silent Input Loss**: Added DEBUG warning logs when button presses or chords are silently dropped due to nil active profile.
- **Controller Disconnect State Reset**: Trigger, paddle, function button, and PS button state are now properly cleared under lock when a controller disconnects.
- **Profile Property Desynchronization**: `activeProfileId` is now set before `activeProfile` so downstream `@Published` observers see a consistent state.
- **Config Save Validation**: `saveConfiguration()` now validates that `activeProfileId` references an existing profile, falling back to the first profile if orphaned.
- **MappingEngine Teardown**: Added `tearDown()` method to properly clean up Combine subscriptions and timers.
- **Directory Navigator Hardcoded Deadzone**: Now uses the profile's configured mouse deadzone instead of a hardcoded 0.4 value.
- **MacroExecutor Deadlock Risk**: Replaced `DispatchSemaphore` blocking pattern with `async/await` to eliminate potential main thread deadlocks when opening apps or URLs.

## [1.7.2] - 2026-04-21

### Performance

- **Button Press Lookup (10–22x faster)**: Chord and sequence membership checks (`isButtonUsedInChords`, `isButtonUsedInSequences`) replaced O(m×k) linear scans of heap-allocated Sets with O(1) precomputed Set lookups, built once at profile load time. Chord matching replaced O(m) linear scan with Set equality comparisons with O(1) dictionary lookup.
- **120 Hz Joystick Polling (31% fewer lock cycles)**: Controller input reads consolidated from 5 individual lock/unlock cycles per tick into a single `ControllerSnapshot` struct captured in one lock acquisition. All ~40 bytes of stick/trigger state fit in a single cache line.
- **UI Singleton Reads (33% faster)**: Batched per-frame reads from `OnScreenKeyboardManager` and `SwipeTypingEngine` into single-lock snapshot methods, eliminating duplicate reads (6 lock cycles → 3 per tick).
- **Letter Area Geometry Cache (58% faster)**: `threadSafeLetterAreaScreenRect` now caches the coordinate-transform result and only recomputes when the overlay frame or panel position changes, eliminating redundant math at 120 Hz.
- **Debug-only NSLog**: Guarded `MappingActionExecutor` error-path NSLog with `#if DEBUG` to avoid system log IPC overhead in release builds.
- **CGWarpMouseCursorPosition Removed**: Profiling (`sample`) revealed this single call consumed 98.7% of mouse-queue CPU (586/594 samples). It was a synchronous Mach IPC round-trip to WindowServer on every frame, redundant with the CGEvent that already positions the cursor.
- **Touchpad Debug Logging**: `ProcessInfo.environment` dictionary copy (called on every touchpad update) replaced with a one-time cached check at launch. `UserDefaults` check cached with 2-second refresh interval.
- **Display Timer Window Visibility**: Overlay panels (on-screen keyboard, laser pointer, focus mode indicator) no longer prevent the display timer from suspending when the main window is minimized. Filter changed from any-window-visible to normal-level-window-visible.
- **Decoupled Analog Display from objectWillChange**: 12 analog display properties (`displayLeftStick`, `displayRightStick`, etc.) changed from `@Published` to `CurrentValueSubject`. Previously, each 15Hz analog update triggered `objectWillChange` on `ControllerService`, causing all 26 observing SwiftUI views to re-evaluate — even though only 2 views (`ControllerAnalogOverlay`, `StreamOverlayView`) read analog values. Body evaluations for `ControllerVisualView` dropped from 44 to 13 samples, `ContentView` from 21 to 8.
- **Date() → CFAbsoluteTimeGetCurrent()**: Replaced heap-allocating `Date()` with stack-allocated `CFAbsoluteTimeGetCurrent()` in button tap timing, consistent with the rest of the input pipeline.

## [1.7.1] - 2026-04-16

### Fixed

- **Single Joy-Con Button Binding**: Single Joy-Cons don't expose `GCExtendedGamepad` or `GCMicroGamepad` — they only provide `GCPhysicalInputProfile`. The previous fallback path failed silently, leaving zero handlers bound. Now dynamically enumerates the physical input profile to bind all available buttons, D-pad, and analog stick elements.
- **Joy-Con L/R Detection**: Improved left/right Joy-Con identification by checking both `vendorName` and `productCategory`, and excluding paired "(L/R)" from single-side detection.
- **Profile Import File Picker**: The "Import Profile..." file picker was not appearing because SwiftUI only honors the last `.fileImporter` modifier on a view. Consolidated the regular and Stream Deck import into a single file importer with a type-based dispatch.

## [1.7.0] - 2026-04-15

### Added

- **Nintendo Joy-Con & Pro Controller Support**: Nintendo controllers are now recognized and display correct button labels (L/R, ZL/ZR, +/−, Capture, Home). Pro Controller and paired Joy-Cons work via the standard `GCExtendedGamepad` path.

### Fixed

- **Active Controller CPU Usage**: Reduced CPU and energy impact while actively using the controller (e.g., joystick mouse movement). Cached expensive Accessibility Zoom state checks, eliminated per-frame object allocations in the 120 Hz mouse movement path, and reused system resources instead of recreating them every frame.
- **Display Timer Paused When Hidden**: The 15 Hz UI display update timer now automatically suspends when all app windows are minimized or hidden, eliminating unnecessary SwiftUI invalidation while the app is not visible.

## [1.6.5] - 2026-04-06

### Fixed

- **Idle DualSense / Controller CPU Usage**: Eliminated idle UI state churn that was re-publishing unchanged controller display state at 15 Hz, significantly reducing background CPU usage while a controller sits untouched
- **DualSense Motion Activation**: Motion processing now activates only when the active profile actually uses gyro aiming or motion gestures, while preserving connect-time ordering so motion features still come online correctly when enabled

## [1.6.4] - 2026-04-02

### Added

- **Simulate Key Repeat While Held**: New opt-in option under "Hold action while button is held" that re-posts key-down events on a timer, simulating physical keyboard key repeat. Fixes games that require repeated key-down events (e.g., hold-to-jump) rather than just checking if a key is currently pressed. Configurable rate from 10–60 per second.

## [1.6.3] - 2026-04-02

### Added

- **Simplified Chinese (zh-Hans) Localization**: Full Chinese translation covering all UI strings (contributed by [李杰](https://github.com/lijie2333))

## [1.6.2] - 2026-03-30

### Added

- **Scroll Up / Scroll Down Actions**: Map any controller button, chord, or sequence to scroll up or scroll down
- Tests for scroll action key codes, display names, classifiers, and picker availability

### Fixed

- Button mapping sheet too narrow to show all keyboard keys when "Show Keyboard" is toggled
- "Show Keyboard" button text wrapping into multiple lines
- Navigation & special keys row overflowing in the visual keyboard picker (split into two centered rows)

## [1.6.1] - 2026-02-28

### Added

- **Per-Mapping Haptic Feedback**: Configure haptic feedback individually for buttons, chords, and sequences
- **Battery Level Light Bar**: DualSense light bar reflects battery level with color gradient
  - Low battery blink animation
  - Charging animation with pulsing effect
  - Instant transitions via HID report battery/charging state parsing
- **Bluetooth Light Bar Control**: Light bar colors now work over Bluetooth via GCController.light
- **Bluetooth Keep-Alive**: Prevents controller from disconnecting during idle periods
- **30 New Community Profiles**: Spotify, Apple Music, Xcode, VS Code, iMovie, Claude, ChatGPT, Codex, Finder, Messages, Discord, Slack, Chrome, Notes, Zoom, Web Browsing, Blender, Premiere, Figma, PDF, Ableton, Terminal, iTerm2, Ghostty, and 9 targeted-audience profiles
- **Accessibility Zoom Regression Tests**: Prevent fragile overlay/cursor behavior from breaking

### Fixed

- Accessibility Zoom cursor flash on mouse click events (now uses IOHIDPostEvent with kIOHIDSetCursorPosition)
- Accessibility Zoom drag cursor flash, extracted testable overlay position policies
- Overlay positioning during Accessibility Zoom (oscillation filter)
- Media key events routing to wrong app
- Battery light bar not applying on app restart
- Gesture buttons missing from isPlayStationOnly classification
- Division-by-zero in normalizedMagnitude when deadzone = 1.0
- Auto-insert space between consecutive swiped words
- Memory leaks: IOKit port, retain cycles, observer cleanup
- Data races in haptics, script state, and usage stats
- Duplicate windows from Cmd+N
- Bugs across 13 community profiles (naming consistency, missing shortcuts, lightBarBrightness enum)

## [1.6.0] - 2026-02-24

### Added

- **JavaScript Scripting System (Beta)**: Write custom automation scripts powered by JavaScriptCore
  - Full API: `press()`, `hold()`, `click()`, `type()`, `paste()`, `delay()`, `clipboard.get()/set()`, `shell()`, `openURL()`, `openApp()`, `notify()`, `haptic()`, `log()`, `state.get()/set()/toggle()`
  - App-aware scripting with `app.name`, `app.bundleId`, `app.is()` for context-sensitive actions
  - Trigger context (`trigger.button`, `trigger.pressType`, `trigger.holdDuration`)
  - `screenshotWindow()` API for capturing the focused window to clipboard or file
  - Per-script persistent state that survives across invocations
  - Built-in example gallery with ready-to-use scripts
  - Script editor with syntax reference and AI prompt assistant
  - "Create New Script" button accessible from mapping sheet pickers
  - Security: shell command blocklist, URL scheme validation (http/s only)
- **Swipe Typing for On-Screen Keyboard**: Slide across letters to type words
  - SHARK2 template matching algorithm for accurate predictions
  - Haptic feedback on swipe begin/end and prediction navigation
  - Custom words UI in swipe typing settings
  - Dictionary includes Brown corpus inflected forms, computing terms, and user's shell aliases
- **Button Sequence Mappings**: Trigger actions with ordered button combos (e.g., Up-Up-Down-Down)
  - Zero-latency detection with configurable step timeout
  - Active sequences displayed on Buttons tab
- **DualSense Gyroscope Gestures**: Map controller tilts and steers to actions
  - Tilt forward/back and steer left/right gesture types
  - Per-profile gesture sensitivity and cooldown sliders
- **Gyro Aiming**: Use DualSense gyroscope for precise mouse control in focus mode
  - 1-Euro filter for jitter-free smoothing with responsive tracking
  - Smooth deadzone transitions, cubic sensitivity curve, horizontal roll boost
  - Configurable sensitivity and deadzone
- **Stream Overlay for OBS**: Floating overlay showing active button presses for stream capture
- **Laser Pointer Overlay**: On-screen pointer for presentations
- **Directory Navigator**: Controller-driven file browser overlay
  - Right stick navigation, B to confirm, Y to dismiss
  - Mouse support, position memory, click-outside-dismiss
- **Controller Lock Toggle**: Lock/unlock controller input with haptic feedback
- **Stream Deck Profile Import**: Import Stream Deck V2 format profiles
- **Shannon-Optimal Binding Analysis**: Recommendations for efficient button assignments with button icons
- **On-Screen Keyboard Typing Buffer**: Visual buffer showing typed text (36pt font)
- **Keyboard Navigation**: Cmd+Left/Right and Cmd+Opt+Arrow to switch tabs; Home/End/PageUp/PageDown for scroll navigation; Escape and Cmd+Enter for all dialogs
- **VoiceOver Accessibility**: Support across 12 view files
- **Visual Press Feedback**: Controller activation highlights on on-screen keyboard
- **On-Screen Keyboard Auto-Scaling**: Keyboard scales to fit smaller displays

### Changed

- Script execution timeout increased from 500ms to 2000ms to support scripts with delays
- Decomposed ControllerService and ContentView god objects into focused extension files
- Unified input pipeline with ControllerInputEvent type and extracted gesture detectors
- Command pattern for action dispatch via MacroExecutor and ActionCommand protocol
- MappingEngine split into focused extension files with proper lock discipline
- Services reorganized into subdirectories
- Profile equality excludes timestamps to prevent unnecessary re-renders
- String-based PressType replaced with type-safe enum

### Fixed

- Clipboard race condition in "Search Selected Text" example script (now compares before/after clipboard)
- Action hints showing held modifiers together with current action
- Mouse click buttons getting stuck held down
- IOKit use-after-free in GenericHID and PlayStation HID callbacks
- XboxGuideMonitor use-after-free crash
- Modifier state race condition (heldModifiers read moved inside keyboardQueue)
- releaseAllModifiers race condition with Release-build CGEvent failure logging
- Linked profile not staying active for its linked app
- Joystick cursor visibility and swipe drag line stability
- Gyro aiming blocked by joystick deadzone early return
- Gyro aiming horizontal axis reversed
- Stream overlay not showing combined held actions
- Script editor showing blank on first example selection
- Keyboard window draggable during swipe mode
- On-screen keyboard key presses firing during swipe typing
- Config saves now atomic with symlink preservation (stow compatibility)
- Stable Keychain keys with plaintext fallback for OBS passwords
- Stats top button bars aligned with fixed-width icon column
- Sequence step bar fixed height in mapping sheet
- Shell blocklist whitespace bypass and JSContext exception capture
- AppleScript injection in terminal commands
- HID report bounds checking

### Security

- OBS passwords stored in macOS Keychain
- ScriptEngine shell command blocklist hardened with validation
- SystemCommandExecutor URL scheme validation and command logging
- openURL restricted to http(s) schemes only
- Defense-in-depth bounds check on HID report data
- Threading safety: eliminated `nonisolated(unsafe)`, protected timer access
- Force unwraps eliminated in SwipeTypingModel and InputSimulator

## [1.5.0] - 2026-02-18

### Added

- **PS4 DualShock 4 Controller Support**: Full support for DualShock 4 (v1 and v2) controllers
  - Touchpad mouse control and gestures (same as DualSense)
  - PlayStation-style button labels and icons throughout the UI
  - PS button works via HID monitoring (report IDs `0x01` USB, `0x11` Bluetooth)
  - DualShock 4's Share button correctly maps to Options/View
- **Controller Wrapped**: Usage stats with shareable personality-typed cards
  - Track every button press, macro, webhook, app launch, and more
  - Streak tracking and personality typing based on usage patterns
  - Copy shareable card to clipboard for social media
  - Detailed breakdown: input types, output actions, mouse/scroll distance, automation stats
- **HTTP Webhook Support**: Send HTTP requests from controller buttons and chords
  - Supports GET, POST, PUT, DELETE, and PATCH methods
  - Configurable headers and request body
  - Visual feedback above cursor showing response status (e.g., "Webhook 200")
  - Haptic feedback on success (crisp pulse) or failure (double pulse)
- **OBS WebSocket Commands**: Control OBS Studio directly from controller buttons
- **System Command Macro Steps**: Macros can now include shell commands, webhooks, and OBS WebSocket requests as steps

### Changed

- Extracted shared touchpad handler to eliminate code duplication between DualSense and DualShock
- Renamed HID monitoring from DualSense-specific to general PlayStation monitoring
- Button display throughout the app (stats, wrapped card, input log, chord sheets) now uses `isPlayStation` for correct labels on both PS4 and PS5 controllers
- Major ProfileManager refactor: extracted 15+ single-responsibility services for better testability
- Comprehensive test suite expansion across mapping engine, profile manager, command wheel, on-screen keyboard, and system commands

### Fixed

- Zoom-aware mouse click coordinates not resolving correctly
- System command hints not displaying when user sets a custom hint
- Macros without a name blocking save (now auto-generates timestamped name)
- Macro system command handler wiring broken by protocol extraction
- Keyboard and command wheel transient state not clearing on reset
- Webhook request body incorrectly sent for GET/DELETE methods
- Usage stats publishing not throttled on input hot path

## [1.4.3] - 2026-02-16

### Added

- **Favicon Caching**: Website link favicons now persist across app restarts
  - Cached in `~/.controllerkeys/favicons/`
  - Missing favicons automatically refetched in background
- **Press Enter Option**: Type Text macro step can optionally press Enter after typing
- **Edit Sheets**: App bar items and website links can be edited after creation
  - App search in edit sheet for quick app selection
- **Hover Highlighting**: Visual feedback across all interactive elements
  - Toolbar buttons, mapping toggle, settings rows
  - Consistent cursor behavior with reusable modifiers

### Fixed

- DualSense Edge layout (paddles, function buttons) persists when controller disconnects
- Drag-to-reorder in all settings lists (chords, macros, text snippets, apps, websites)
- Inconsistent row heights in active chords display
- App bar and website list not updating immediately after changes
- App bar list height cutting off last item
- Hover modifiers blocking clicks and not showing highlight
- Number key 5 mapped to wrong key code on visual keyboard
- Macro labels showing generic "Macro" for long hold and double tap actions

## [1.4.2] - 2026-02-16

### Added

- **Accessibility Zoom Support**: Controller input now works correctly when macOS Accessibility Zoom is active
  - Cursor movement, clicks, and scroll positions are properly scaled to zoomed coordinates
  - Focus mode ring and action hints position correctly within the zoomed viewport
  - Automatic detection with warning dialog if Zoom keyboard shortcuts aren't enabled
- **Chord Duplicate Prevention**: Visual feedback when creating chords that would conflict
  - Gray out buttons that would create duplicate chord combinations
  - Show conflicting chord name on grayed out buttons
- **Clickable Active Chords**: Click any active chord to open its edit sheet directly

### Fixed

- Focus mode ring positioning during Accessibility Zoom
- Action hint positioning during Accessibility Zoom with touchpad
- Action hint flashing when Accessibility Zoom is active
- Click position offset when Accessibility Zoom is active
- Cursor position reset when Accessibility Zoom is active
- Zoom warning dialog blocking input and repeated sounds
- Held modifier flags not forwarded to scroll events
- Long words overflowing in button mapping labels
- Non-deterministic JSON ordering in config.json

## [1.4.1] - 2026-02-14

### Added

- **Stick Mode Settings**: Configure left/right stick behavior independently
  - WASD keys mode for left stick (gaming-style movement)
  - Arrow keys mode for right stick (navigation)
  - Disable option to turn off stick input entirely
- **Held Modifier Feedback**: Purple "hold" badge in cursor hints when modifier buttons are held
  - Shows combined hint when multiple modifiers are held simultaneously
  - Badge also appears in Buttons tab mapping labels

### Fixed

- Typed text in macros being affected by held controller modifiers (e.g., Shift held while typing)
- Cursor hint text truncation now shows ellipsis instead of clipping
- Community profile preview showing Xbox button icons for DualSense controllers
- ChordMappingSheet now scrollable when content exceeds window height (DualSense Edge + keyboard)

### Changed

- Favicon data no longer persisted to config file (fetched on demand, reduces file size)

### Removed

- Keep Alive feature removed (was causing issues and determined unnecessary)

## [1.4.0] - 2026-02-12

### Added

- **Cursor Hints**: Visual feedback showing executed actions above the cursor
  - Shows action name, keyboard shortcut, or macro name when buttons are pressed
  - Type badges for double-tap (2×), long-press (⏱), and chord (⌘) actions
  - Held actions stay visible until button released with minimum display time
  - Toggle button in the Buttons tab to enable/disable
- **Focus Mode Cursor Highlight**: Purple ring around cursor when focus mode is active
  - Toggle setting in Joysticks > Focus Mode > "Highlight Focused Cursor"
- **Button Mapping Swap**: Quickly swap all mappings between two buttons
  - Click "Swap" button, select first button, select second button
  - Swaps primary action, double-tap, long-hold, repeat settings, and hints
  - Works within layers; does not affect chords
- **Layers Feature**: Create alternate button mapping sets activated by holding a designated button
  - Up to 2 additional layers beyond the base layer
  - Momentary activation - layer active while activator button is held
  - Fallthrough behavior - unmapped buttons use base layer mappings
  - User-named layers (e.g., "Combat Mode", "Navigation")
  - Visual layer tabs in the UI with activator button badges
- **DualSense Edge (Pro) Controller Support**
  - Full support for Edge-specific controls: function buttons and paddles
  - USB HID fallback for Edge controllers not recognized by GameController framework
  - Edge buttons available as layer activators when Edge controller is detected
- **Auto-Scaling UI**: Controller view and window content scale automatically when resized
  - Scales both up and down based on window size
  - Combines with manual zoom setting for full control

### Fixed

- Macro feedback now shows macro name instead of generic "Macro" text in cursor hints
- Chord macro feedback also displays actual macro name
- Accidental horizontal panning when scrolling vertically with right stick (now requires deliberate horizontal input)
- Deadlock in button release handler that caused mappings to stop working
- Command Wheel hint centering on on-screen keyboard
- Mapping label alignment across different button sizes (shoulder buttons vs others)

### Changed

- Edge controller row order: function buttons on top, paddles on bottom
- Layer activator labels now use consistent chip styling matching other mapping labels
- Re-applied CPU optimization for joystick callbacks (reduces idle CPU usage)

## [1.3.0] - 2026-02-09

### Added

- **Community Profiles**: Browse and import pre-made controller profiles from the community
  - New "Import Community Profile..." option in the profile menu
  - Preview profiles before importing (see all button mappings and chords)
  - Multi-select to import multiple profiles at once
  - Already-imported profiles are marked and cannot be re-imported
  - Profiles are fetched from the GitHub repository

## [1.2.3] - 2026-02-08

### Fixed

- F13-F20 keys not triggering hotkeys in terminals using CSI u / Kitty keyboard protocol (was outputting escape sequences like `[57376u` instead)

## [1.2.2] - 2026-02-03

### Added

- **D-pad Navigation for On-Screen Keyboard**
  - Navigate the entire keyboard using D-pad when on-screen keyboard is visible
  - Floating overlay highlight shows current selection
  - Special handling for arrow key cluster layout
  - Optimized responsiveness with navigation bounds on all keys
- **Third-Party Controller Support**: Fallback for controllers not recognized by GameController framework
  - IOKit HID + SDL gamecontrollerdb.txt maps raw inputs to Xbox-standard layout
  - ~313 macOS controllers supported (8BitDo, Logitech, PowerA, Hori, etc.)
  - 1-second fallback timer gives GameController framework priority
  - Bundled database with manual refresh from GitHub in Settings
  - No manual configuration needed; detected controllers use Xbox button labels
- **Macros System**: Full macro recording and playback with multi-step sequences
  - Macro steps: Key Press, Type Text, Delay, Paste
  - Type Text supports configurable speed settings
  - Macros assignable to buttons, chords, long hold, and double tap actions
  - Dedicated Macros tab for management
- **System Commands**: Automate actions beyond key presses
  - Launch App: open any application by bundle identifier with browse dialog
  - Shell Command: run terminal commands silently or in a terminal window
  - Open Link: open URLs in default browser
  - Assignable to buttons, chords, long hold, and double tap actions
- **Battery Notifications**: alerts at low (20%), critical (10%), and fully charged (100%)
- **Command Wheel**: GTA 5-inspired radial menu for quick app/website switching
  - Right stick navigates segments; releasing activates the selected item
  - Full-range stick actions (push all the way for force quit / new window)
  - Haptic feedback during navigation
  - Modifier key to toggle alternate content (apps vs websites)
  - Incognito long-hold action for websites
  - Three-tier icon positioning for varying item counts
- **App-Specific Profile Auto-Switching**
  - Link profiles to specific applications
  - Automatic profile switching when apps gain focus
  - Falls back to default profile for unlinked apps
- **On-Screen Keyboard Improvements**
  - Keyboard position remembered per screen within session
  - Global keyboard shortcut toggle (configurable in Keyboard tab)
  - "Activate All Windows" setting for app switching (on by default)
- **Mapping Enhancements**
  - Long hold and double tap now support macros and system commands (not just keys)
  - Optional hint field for button and chord mappings (primary, long hold, double tap)
  - Hints display instead of raw shortcuts; hover shows actual shortcut in tooltip
  - Caps Lock key properly shows display name in key picker
  - FN key disabled from being mapped as a regular key
- **Comprehensive Test Suite**
  - Tests for InputLogService and ProfileManager
  - Edge case tests for mapping engine
  - Chord fallback and modifier handling tests

### Changed

- Modern dark glass aesthetic for main window, on-screen keyboard, and command wheel
- Wrapping flow layout for active chords display (replaces horizontal scroll)
- Green battery indicator when controller is charging
- All config structs use resilient custom decoders (missing/new fields won't break configs)
- Schema version tracking for future migrations
- Repeat action rate defaults to 5/s (previously 20/s)
- Chord creation shows gray outlines when button combination already exists
- Center column buttons match side column width in Buttons tab
- Code refactored: unified mapping execution, extracted helpers, thread-safe screen cache
- Touchpad two-finger pan speed slightly reduced
- Touchpad momentum tuned for shorter, lighter glide
- Default pan-to-zoom ratio increased to 1.95
- Touchpad smoothing description clarified to "Reduce mouse jitter"

### Fixed

- System commands now show in green in Active Chords section
- Macro hints, trailing whitespace visibility, and button backgrounds
- Chord fallback bug when releasing buttons
- Event flags now always set to prevent inherited modifiers
- Smooth diagonal touchpad panning
- Touchpad pan scrolling
- On-screen keyboard appears on screen where mouse cursor is (not always primary display)
- Key capture field no longer intercepts clicks outside its bounds
- Long hold/double tap settings not loading when re-opening configure button page
- DualSense button icons displaying as Xbox style in configure button page header
- Save button properly handles empty system command/macro state
- Chord reordering preserved correctly
- Deadlock risk in InputSimulator removed (replaced DispatchQueue.main.sync with CoreGraphics API)
- Short pinch-to-zoom snap-back (direction lock on quick releases)
- Choppy two-finger scrolling from low touchpad sample rate (120Hz interpolation)

### Removed

- Touchpad scroll momentum for DualSense two-finger gestures (caused inconsistent behavior)

## [1.2.1] - 2026-01-21

### Fixed

- Website links and app bar lists cutting off last item
- Favicon not loading for websites with favicons in subdirectories

## [1.2.0] - 2026-01-21

### Added

- Custom profile icons
  - Choose from 35 SF Symbol icons organized in 7 categories
  - Right-click profile → Set Icon to customize
  - Icons display in sidebar and menu bar

### Changed

- App name changed from Xbox Controller Mapper to ControllerKeys
- Distribution format changed from ZIP to DMG with drag-to-Applications install

## [1.1.2] - 2026-01-21

### Added

- Website links feature in on-screen keyboard settings
  - Add URLs that display with favicon and title
  - Click to open in default browser
- Media key controls in on-screen keyboard
  - Playback: Previous, Rewind, Play/Pause, Fast Forward, Next
  - Volume: Mute, Down, Up
  - Brightness: Down, Up
- Media keys available in visual keyboard picker for button and chord mapping

### Changed

- Swap order of Commands and Text sections in on-screen keyboard
- Increase app bar and website bar to 12 items per row
- Move media controls above extended function keys in keyboard picker
- Increase spacing between media control groups

### Fixed

- App activation in app bar not working for most apps
- Apps not launching focused when opened from app bar

## [1.1.0] - 2026-01-20

### Added

#### DualSense Touchpad
- Touchpad support for mouse control with configurable sensitivity
- Tap-to-click gesture (defaults to left click)
- Two-finger tap gesture for right-click
- Double-tap gesture support
- Long tap gesture support
- Pinch-to-zoom with native macOS magnify gestures or Cmd+Plus/Minus
- Two-finger scroll with momentum and Chrome compatibility
- Dedicated Touchpad settings tab
- Live touch point visualization for one and two fingers in controller preview in Buttons tab

#### DualSense LEDs
- LED control tab for lightbar color and brightness
- Player LED patterns (symmetric patterns only)
- Party mode for animated LED effects
- Bluetooth LED control support (with limitations notice)

#### DualSense Microphone
- Microphone tab with mute control and audio level meter
- Auto-enable microphone on USB connect

#### On-Screen Keyboard
- Full on-screen keyboard accessible via button mapping
- Quick text snippets with configurable typing speed
- Terminal command shortcuts that open a new terminal window
- App bar for quick app switching
- Variable expansion system with date/time, clipboard, app context, and file path variables
- Extended function keys toggle (F13-F20)
- Caps lock toggle
- Keyboard navigation for app picker and variable suggestions

#### UI Improvements
- Accurate DualSense controller visualization with touchpad display
- Controller-specific UI styling for DualSense vs Xbox
- Visual keyboard in chord mapping sheet
- Remember last connected controller type

### Fixed

- DualSense PS button not triggering over Bluetooth
- Improve chords tab to match app style
- Improve chords tab reordering
- Magnify gestures triggering button taps on Buttons tab
- Touchpad causing unintended mouse movement on tap
- Touchpad scroll not working in Chrome
- Touchpad click causing cursor jump
- Various LED control issues over Bluetooth

## [1.0.0] - 2026-01-16

### Added

- Button mapping with support for modifier-only, key-only, and modifier+key combinations
- Long-hold actions for alternate button behavior
- Double click actions for alternate button behavior
- Chord mappings (multiple buttons trigger a single action)
- Left joystick to mouse movement with configurable sensitivity and deadzone
- Right joystick to scroll with configurable sensitivity and deadzone
- Modifier key (RT by default) for sensitive mouse movement mode
- Profile system for multiple mapping configurations (saved in ~/.controllerkeys/config.json)
- Interactive controller visualization UI for easy configuration
- Menu bar icon for quick enable/disable and profile switching
- Default mappings optimized for general macOS navigation

[1.0.0]: https://github.com/NSEvent/xbox-controller-mapper/releases/tag/v1.0.0
