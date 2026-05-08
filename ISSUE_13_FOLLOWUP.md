# Issue #13 Follow-up Tasks

Source: https://github.com/NSEvent/xbox-controller-mapper/issues/13

v1.7.9 already shipped layer-aware lightbar, flexible layer modifier behavior, touchpad
quadrant remapping, controller visualization UI, and the initial "Hide Dock Icon" toggle.
The customer reported follow-up issues and a few more requests after testing. The items
below are the remaining work.

Decisions made during brainstorming (not to be revisited):
- Skip the "Hide Sections" UI option entirely.
- For the "Select All" touchpad bug, the (0,0) fallback is intentional — solution is a
  setting, not removing the behavior.
- Touchpad quadrants will be promoted to first-class buttons by placing them above the
  controller diagram in the **center column of the Buttons tab**, which is currently empty.

Suggested order: Task 1 → Task 2 → Task 3 → Task 4. Tasks 1 and 2 are bug fixes on
features just shipped; tasks 3 and 4 are net-new.

---

## Task 1 — Touchpad region click fires unexpectedly when finger is off the pad

**Customer report:** Top-left quadrant mapped to Cmd+A. While typing in a text editor
they occasionally triggered "Select All" without intending to click that region.

### Root cause

In `ControllerService+Touchpad.swift:40-45`, the touchpad-button-down handler reads
`storage.touchpadPosition` (the *last known* finger position) and classifies it via
`TouchpadRegion.from(position:)`. There's only one guard: if the position is exactly
`.zero`, fall through to the base touchpad button instead of firing a region callback.

This guard handles the "click before any finger ever touched the pad" case. It does
**not** handle:

1. Finger touched briefly, lifted off, then user clicks the physical button —
   `touchpadPosition` is stale, classifier returns whatever quadrant the last touch
   ended in.
2. Finger touched at the very edge (HID reports e.g. `(0.02, 0.98)`) then user clicks —
   technically a valid touch, but the user perceives their finger as "off the pad".

The customer's case is most likely #1.

The existing `TouchpadRegionSwapTests.testRegionFromOriginClassifiesAsBottomLeft`
documents the (0,0) → bottomLeft mapping and explicitly notes "the fix lives in the
caller" — so we extend the caller-side guard.

### Proposed fix

Add a setting under **Settings → Touchpad** (or wherever touchpad behavior lives):

> **Require active touch for region clicks**
> When enabled, touchpad region mappings only fire if a finger is currently touching
> the pad at the moment of click. When disabled, clicks use the last known touch
> position. Default: **enabled.**

Implementation sketch:

- Add `requireActiveTouchForRegionClick: Bool` to `JoystickSettings` (or a new
  `TouchpadSettings` struct if we want to start splitting). Default `true`. Use the
  custom-decoder pattern from `CLAUDE.md` (`decodeIfPresent ?? true`).
- In `ControllerService+Touchpad.swift` line ~40, extend the guard:
  ```swift
  let isCurrentlyTouching = self.storage.isTouchpadTouching
  let allowStalePosition = !settings.requireActiveTouchForRegionClick
  let positionUsable = clickPosition != .zero && (isCurrentlyTouching || allowStalePosition)
  if !willBeTwoFingerClick,
     let callback = regionClickCallback,
     positionUsable {
      let region = TouchpadRegion.from(position: clickPosition)
      ...
  }
  ```
- The base touchpad-button action still fires either way, so users who *do* want a
  click-with-no-finger to do something can map the regular touchpad button.

### Tests

- New test: click at (0.1, 0.9) when `isTouchpadTouching == false` and setting is
  ON → no region fires; base touchpad button fires.
- New test: same scenario with setting OFF → topLeft region fires (preserves current
  behavior for users who depend on it).
- Keep existing `testRegionFromOriginClassifiesAsBottomLeft` intact.

### Files

- `Models/JoystickSettings.swift` — add field + decoder entry
- `Services/Controller/ControllerService+Touchpad.swift` — extend the guard
- `Views/MainWindow/SettingsViews.swift` (or wherever touchpad settings render) — UI
- `XboxControllerMapperTests/TouchpadRegionSwapTests.swift` — new tests

---

## Task 2 — "Hide Dock Icon" should follow standard menu-bar-app behavior

**Customer report:** Current toggle is binary and breaks the menu bar entry point.

Observed:
- Enabling the setting closes the main window immediately and hides the dock icon.
- After that, clicking the menu bar icon does **not** reopen the main window.
- Reopening via Spotlight shows the window, but the dock icon then sticks around even
  after closing the window with the red traffic light.

Expected (standard `LSUIElement`-style accessory app):
- App lives in the menu bar continuously.
- When the user explicitly opens the main window, the app temporarily promotes to
  `.regular` so the dock icon appears.
- When the user closes the main window (red close button), the app returns to
  `.accessory` and the dock icon disappears.
- The menu bar icon must always be able to reopen the main window.

### Current implementation

`Views/MainWindow/SettingsViews.swift:1098-1104`:

```swift
.onChange(of: hideFromDock) { _, newValue in
    NSApp.setActivationPolicy(newValue ? .accessory : .regular)
    if !newValue {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

The toggle is a static policy switch, not a window-lifecycle observer. That's why the
dock icon doesn't track window visibility.

### Proposed fix

Reframe the toggle. Rather than "hide dock icon" being a static state, treat it as
"app is a menu bar app" — and tie activation policy to window state:

1. When `hideFromDock == true`:
   - On app launch: set policy to `.accessory`. Do **not** auto-close any window.
   - When the main window becomes visible (`NSWindow.didBecomeKeyNotification` or
     observe `window.isVisible`): set policy to `.regular`, then `NSApp.activate(...)`
     so the dock icon shows immediately.
   - When the main window is closed/hidden: set policy back to `.accessory`.
2. When `hideFromDock == false`: always `.regular`.
3. Menu bar item action: open the main window (creating it if needed). With (1) wired
   up, opening the window naturally triggers the policy promotion.

### Things to verify / be careful about

- `setActivationPolicy(.accessory)` while a window is key may cause focus loss; we
  should test the transition both directions.
- Confirm the menu bar icon's "open window" command actually unhides the window. If
  the window is closed (not just hidden), we may need to recreate it from the
  `WindowGroup`. Investigate whether SwiftUI's `@Environment(\.openWindow)` or the
  AppKit `NSApp.windows.first(where:)` + `makeKeyAndOrderFront(_:)` approach is more
  reliable here.
- Settings window: when the Settings window is open as the only visible window, what
  should the dock icon do? Probably show the dock icon while *any* of our windows is
  visible, not just the main one.

### Files

- `XboxControllerMapperApp.swift` — likely where window-lifecycle observation goes
- `Views/MainWindow/SettingsViews.swift` — update `onChange` handler (no longer needs
  to immediately hide/show; just flips the mode)
- Menu bar service (find via `grep -rn "NSStatusItem\|MenuBar"`) — ensure "Open Main
  Window" command reliably unhides

### Tests

- Hard to unit-test activation policy. Manual test plan in PR description should
  cover: enable toggle → close window → click menu bar icon → window reopens with
  dock icon → close window with red button → dock icon gone.

---

## Task 3 — Promote touchpad quadrants to first-class buttons in the Buttons tab

**Customer suggestion:** placing the touchpad quadrants inside the regular button
mapping section instead of a separate touchpad section would let layers/modifiers
apply to them, expanding usable bindings.

**Decision:** Place the four quadrant buttons in the **center column of the Buttons
tab, above the controller diagram**. That area is currently empty and is a natural
visual home for them.

### What changes

- Quadrants gain access to the same machinery as physical buttons: layer-aware
  remapping, hold modifier, double-tap, long-hold, repeat. Today they only support a
  single static action via `TouchpadRegionMapping`.
- The dedicated Touchpad section can keep its trackpad-mode settings (sensitivity,
  pan/zoom, etc.) but the quadrant action editors move out.

### Implementation approach

Two paths — pick one in design:

**Option A: Add `ControllerButton` cases for each quadrant.** New cases like
`.touchpadTopLeft`, `.touchpadTopRight`, `.touchpadBottomLeft`, `.touchpadBottomRight`.
Quadrant clicks dispatch through `MappingEngine.handleButton(_:pressed:)` like any
other button. `TouchpadRegionMapping` gets deprecated/migrated into
`Profile.buttonMappings`.

- Pros: maximum reuse — layers, hold, double-tap, repeat all "just work".
- Cons: migration path for existing users with `touchpadRegions` configured. Need a
  one-shot config migration to convert `TouchpadRegionMapping` rows into
  `KeyMapping` entries keyed by the new `ControllerButton` cases.

**Option B: Keep `TouchpadRegionMapping` but extend it** to support layer-awareness
and the same modifier sub-mappings (`longHoldMapping`, `doubleTapMapping`, etc).

- Pros: no migration; touchpad-specific features (touch vs click trigger mode) stay
  cleanly separated.
- Cons: duplicates a lot of `KeyMapping`-shaped logic. UI will end up rebuilding
  similar sub-editors.

**Recommendation: Option A.** The customer's whole point is that quadrants should
behave like buttons. Doing it halfway in Option B reproduces the awkwardness that
prompted the request. Migration is mechanical (loop existing region mappings on
load, copy fields into `buttonMappings`).

### UI placement

`Views/MainWindow/ControllerVisualView.swift` (and whatever lays out the Buttons tab
center column) — add a 2x2 grid of quadrant tiles above the controller. Each tile
opens the same `ButtonMappingSheet` that physical buttons use. Visual style should
match the existing button tiles for consistency.

### Trigger mode (touch vs click vs both)

`TouchpadRegionMapping.triggerMode` is touchpad-specific (touch / click / both).
This needs to survive the migration:
- Map "click" → existing `.touchpadButton` press path scoped to the quadrant.
- Map "touch" → quadrant fires on finger contact, releases on lift (similar to a
  button held while finger is down).
- Map "both" → fire on either.

If we go with Option A, store the trigger mode on the new button case itself —
either as a per-button setting in `KeyMapping` or as a property on the
`ControllerButton` enum case (less clean). A dedicated `touchpadTriggerMode:
[ControllerButton: TouchpadTriggerMode]` map on `Profile` is probably cleanest.

### Migration (mandatory — must preserve existing user configs)

The existing `TouchpadRegionMapping` type stays in the codebase (deprecated, for
decoding old configs). On config load, if `Profile.touchpadRegions` is non-empty:

1. For each `TouchpadRegionMapping`, create a `KeyMapping` with its `keyCode`,
   `modifiers`, `macroId`, `systemCommand`, `hint` and store under the corresponding
   new `ControllerButton` case.
2. Record the `triggerMode` in the new `touchpadTriggerMode` map.
3. Clear `touchpadRegions` after migration succeeds. Bump `schemaVersion`.

Constraints:
- Honor the existing `loadSucceeded` safety mechanism — if migration throws or
  produces invalid output, do **not** overwrite the file. Surface the failure.
- If a button mapping already exists for the migrated `ControllerButton` case
  (shouldn't happen pre-migration, but defensive), prefer the existing mapping and
  log/skip the legacy entry — never silently overwrite user data.
- Ship a migration test that loads a real v1 config containing `touchpadRegions`
  and asserts: (a) decoding succeeds, (b) the resulting Profile has equivalent
  button mappings under the new keys, (c) `triggerMode` survives, (d) re-encoding
  the migrated profile and reloading is idempotent.
- Configs that have already been migrated (no `touchpadRegions` field, new
  `ControllerButton` keys present) must round-trip unchanged.

### Files

- `Models/ControllerButton.swift` — new enum cases
- `Models/Profile.swift` — `touchpadTriggerMode` map, custom decoder updates
- `Models/TouchpadRegionMapping.swift` — keep for migration only, mark deprecated
- `Services/Controller/ControllerService+Touchpad.swift` — dispatch through
  `handleButton` for the new cases
- `Services/Mapping/MappingEngine.swift` — likely no changes if dispatch is uniform
- `Views/MainWindow/ControllerVisualView.swift` (or Buttons tab parent) — UI
- `Views/MainWindow/ButtonMappingSheet.swift` — add trigger-mode picker shown only
  for touchpad-quadrant buttons
- Tests: new coverage in `MappingEngineTouchpadCoverageTests.swift` for layer
  interaction; migration test

---

## Task 4 — Automatic controller sleep / shutdown after idle

**Customer request:** configurable idle timeout to power off the controller and save
battery, especially for users who leave a controller paired all day.

### Scope

Per-controller-type implementation. DualSense, DualShock 4, and Xbox controllers all
expose different (or no) shutdown paths.

Known approaches:

- **DualSense / DualShock 4:** the BlueZ project documents a "host disconnect" HID
  output report that causes the controller to drop the BT link and power off after
  a few seconds idle. We may already be sending HID output for LED control — check
  `DualSenseLEDSettings`-related code for the existing report builder.
- **Xbox controllers:** no documented user-space shutdown command for Xbox Wireless
  on macOS. We can disconnect the BT pair, but the controller will likely stay
  awake until its own internal timer trips. Document this limitation in the UI.

### Proposed feature

- Add `idleShutdownEnabled: Bool` and `idleShutdownTimeout: TimeInterval` (in
  minutes) to global settings, not per-profile. Default off.
- A `ControllerIdleMonitor` service watches input. Any button press, joystick
  motion above deadzone, or touchpad touch resets the idle timer. When the timer
  elapses:
  - DualSense/DS4 → send the BT host-disconnect HID report.
  - Xbox → disconnect or no-op with a UI hint.
- UI under **Settings → Power** (new section) with a slider/picker for timeout
  (e.g. 5/10/15/30/60 minutes / never).

### Open questions

- Should we offer a per-controller toggle (some users have multiple controllers)?
- Do we need a "warning" notification before shutdown (e.g. light bar pulse for the
  last 30 seconds)?
- What happens if the user is *receiving* gyro events but not pressing buttons —
  does that count as activity? (Probably yes, to avoid shutting off mid-aim.)

### Risk

This is the most involved task. It touches HID write paths, may need vendor-specific
report definitions, and is hard to test without physical controllers. Suggest doing
it last and starting with DualSense only (largest user impact, best documented).

### Files (sketch)

- `Services/Power/ControllerIdleMonitor.swift` (new)
- `Services/Controller/ControllerService.swift` — wire up activity callbacks
- `Services/HID/` — add host-disconnect report builder
- `Views/MainWindow/SettingsViews.swift` — new Power section
- `Models/AppSettings.swift` (or wherever non-profile settings live) — new fields
