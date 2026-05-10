# ControllerKeys — Remaining Issues & Features

Backlog audited May 10, 2026 against git history and current source.

---

## Backlog

### 1. Buttons tab — collapse/expand Active Chords and Active Sequences sections

**Status:** Feature backlog
**Where:** Buttons tab UI

**Goal:** Give users a way to hide and maximize the Active Chords section and the Active Sequences section.

**Expected:**
- Each section can be collapsed/hidden when the user wants more room for button mappings.
- Each section can be maximized/expanded when the user wants to focus on chords or sequences.
- The controls should feel lightweight and remember enough state to avoid surprising layout resets during normal settings use.

**Likely location:** `ButtonMappingsTab.swift`, `ActiveChordsView.swift`, and `ActiveSequencesView.swift`.

**Related but not sufficient:** `38f0d6e feat: add configurable main window sections` lets users hide whole top-level tabs. It does not add per-panel hide/maximize controls for the active chord/sequence sections inside the Buttons tab.

---

## Completed From Old Backlog

### Command wheel doesn't minimize app on second selection

**Status:** Done

**Evidence:**
- `6457a58 fix: command wheel hides app if it is already frontmost`
- `771e72b fix: launchApp system command minimizes already-frontmost app`
- Current code: `CommandWheelManager.activateApp` and `SystemCommandExecutor.launchApplication` both call `frontmost.hide()` when the selected bundle is already frontmost.

### Touchpad quadrant UI — quadrant cells not clickable to configure mappings

**Status:** Done

**Evidence:**
- `d920bd9 feat: touchpad region mapping editor with separate touch/click actions`
- Current code: `TouchpadRegionGrid` opens `TouchpadRegionMappingSheet` via `.sheet(item: $editingRegion)`, and cells say "Tap to map" when empty.

### Controller lock doesn't actually block input on DS4

**Status:** Done by history; re-open only with a fresh repro.

**Evidence:**
- `d5be40b fix: controller lock from double-tap and long-hold mappings`
- Current code: lock mappings are intercepted before locked-state blocking, `performLockToggle()` logs lock/unlock, and joystick/touchpad/motion paths guard on `!state.isLocked`.

### DualSense / DS4 lightbar doesn't change color on layer activation

**Status:** Done

**Evidence:**
- `dbcf331 fix: DS4 lightbar control via GCController.light over Bluetooth`
- Current code: DS4 Bluetooth lightbar updates use `GCController.light`; DS4 USB HID reports remain for USB.

---

## Features Already Shipped

- Command wheel appears immediately on button hold.
- Hide Dock Icon setting.
- Flexible layer modifier behavior.
- Layer activator buttons can be remapped within other layers.
- Controller lock takes precedence when mapped to layer activator, long-hold, or double-tap actions.
- Touchpad quadrants are first-class buttons with touch/click mapping editor.
- DS4 lightbar works over Bluetooth through `GCController.light`, with USB HID report support retained.
- Layer LED data model and apply/revert hooks.

---

## Implementation Notes for Future Work

- Build with `make install BUILD_FROM_SOURCE=1` (not `make install` alone — that path is for packaged users).
- For NSLog visibility on Release builds, run `log show --predicate 'process == "ControllerKeys"' --last 5m --info --debug` (note: many logs show as `<private>` — use format strings with `%{public}@` if needed).
- Config lives at `~/.controllerkeys/config.json` — inspect with `python3 -m json.tool` to verify mappings persist correctly.
- Tests: `xcodebuild -project XboxControllerMapper/XboxControllerMapper.xcodeproj -scheme XboxControllerMapper -configuration Debug test`.
