# ControllerKeys — Remaining Issues & Features

Tracked from May 7, 2026 testing session. Items below are NOT yet working as expected.

---

## Bugs to Fix

### 1. Command wheel doesn't minimize app on second selection

**Status:** Bug
**Where:** Standalone command wheel (the new one triggered by a dedicated button mapping)

**Expected:** Selecting an already-frontmost app a second time should minimize it (matches keyboard command wheel behavior).
**Actual:** Selecting Chrome twice in a row doesn't minimize Chrome.
**Note:** The keyboard command wheel (the one inside the on-screen keyboard hold) does this correctly. The behavior should be ported to the standalone command wheel.

**Likely location:** `CommandWheelManager.swift` activation/selection handling, or wherever app activation is performed for `.app` items. Look for the keyboard command wheel's app activation code (something around `NSWorkspace` activate/hide) and mirror it.

**Test to add:** Selecting the same frontmost app twice should call hide/minimize on the second selection.

---

### 2. Touchpad quadrant UI — quadrant cells not clickable to configure mappings

**Status:** Partial — model + engine integration done, UI is read-only
**Where:** `SettingsViews.swift` → `TouchpadRegionGrid`

**Current state:** The 2×2 grid in Touchpad settings shows "Not mapped" cells but clicking only removes existing mappings. There's no editor to assign keys/macros/system commands to a quadrant.

**Needed:**
- Sheet/popover to edit a region mapping (key picker, modifiers, macro/system command picker, trigger mode picker [touch/click/both], hint text)
- Reuse `ButtonMappingSheet` patterns where possible — region mappings already use the same `KeyMapping`-shaped fields (keyCode, modifiers, macroId, systemCommand, hint)

**Files:** `SettingsViews.swift` (`TouchpadRegionGrid`), possibly new `TouchpadRegionMappingSheet.swift`

---

### 3. Controller lock doesn't actually block input on DS4

**Status:** Bug — lock toggle fires but movement still works
**Where:** Unknown — needs investigation

**Expected:** When locked, ALL movement (mouse from joystick, mouse from touchpad, key presses, scroll) should be blocked until unlocked.
**Actual:** After locking on DS4, mouse cursor still moves, etc.

**What I checked already:**
- `state.isLocked` checks ARE present in `processJoysticks()` (JoystickHandler.swift:43), `processTouchpadMovement()` (TouchpadInputHandler.swift:18), tap handlers (lines 101, 133, 173, 197, 472)
- `performLockToggle()` correctly sets `state.isLocked = true` inside `state.lock`

**Hypotheses to investigate:**
- The button mapped to lock might not actually be reaching `performLockToggle()` on DS4 (verify with input log when toggling)
- Lock state might be on a different `state` instance than the polling timer reads (rare)
- Mouse movement might be coming through a path that doesn't check `state.isLocked` (e.g., directly via system if the touchpad emulates a mouse at OS level — but DS4 doesn't do this on macOS)

**Concrete next step:** Add an input log entry on lock toggle and verify it fires when Kevin presses the lock button. If it does, dump the lock state from each handler when movement is observed.

---

### 4. ~~DualSense / DS4 lightbar doesn't change color on layer activation~~ ✅ FIXED

**Resolution:** Two fixes:
1. Corrected DS4 HID report byte layout per Linux `hid-playstation.c` (USB byte 1 = `0x03` MOTOR|LED flag; BT report needed proper `hw_control` header at byte 0 and CRC32 at end)
2. Discovered `IOHIDDeviceSetReport` returns success on macOS but the kernel silently drops reports for controllers managed by the GameController framework. Switched DS4 BT to use `GCController.light` (the same privileged path DualSense BT uses).

The HID report code is still useful for DS4 over USB and serves as documentation of the correct format.

---

## Features Already Shipped (Verified Working)

- Command wheel appears immediately on button hold
- Hide Dock Icon setting
- Flexible layer modifier behavior (other layer activators are freed up when a layer is active)
- Layer activator buttons can be remapped within other layers
- Controller lock takes precedence when mapped to a layer activator button
- Touchpad quadrant model + engine integration (region tap/click events route through `processTouchpadRegionEvent`)
- DS4 lightbar HID output reports (code paths exist; visible behavior is bug #4 above)
- Layer LED data model and apply/revert hooks (code paths exist; visible behavior is bug #4 above)

---

## Implementation Notes for Future Work

- Build with `make install BUILD_FROM_SOURCE=1` (not `make install` alone — that path is for packaged users)
- For NSLog visibility on Release builds, run `log show --predicate 'process == "ControllerKeys"' --last 5m --info --debug` (note: many logs show as `<private>` — use format strings with `%{public}@` if needed)
- Config lives at `~/.controllerkeys/config.json` — inspect with `python3 -m json.tool` to verify mappings persist correctly
- Tests: `xcodebuild -project XboxControllerMapper/XboxControllerMapper.xcodeproj -scheme XboxControllerMapper -configuration Debug test`
