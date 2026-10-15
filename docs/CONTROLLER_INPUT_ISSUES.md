# Controller Input Issues

Last updated: 2026-10-14

## Held controller modifiers with a Bluetooth keyboard

A controller button mapped to **Hold Command** can combine with W/V/etc. on a
separate keyboard, including a MoKo/P5 Plus chatpad. Some incoming keyboard
events omit the synthesized modifier even while macOS reports it held. The
held-modifier bridge now adds ControllerKeys' currently held modifiers to those
key-down/up events, preserving the keyboard's existing flags and key data.
ControllerKeys-generated keyboard events, modifier transitions and secure-input
keyboard events are excluded. Physical modifiers remain when the controller
releases its own hold. Tap creation can retry on the next hold after a transient
failure; shutdown also handles a worker that has not entered its run loop yet.
Tap activation, recovery and teardown are serialized so stopping cannot be
followed by a late enable from the startup path.

Regression tests use in-memory keyboard events and an owned run-loop source;
they never post test keystrokes or create a system input tap. MoKo hardware
verification remains a separate check on the affected setup.

## Remote handoff return leaves the local cursor invisible

Observed: after controlling the M3 and returning to the local MacBook, clicks
still work but the system cursor disappears. The return path flashed a temporary
teleport overlay without restoring the actual cursor's visibility. Return and
cancel paths now clear the local keyboard navigation hide and AppKit's
hide-until-mouse-moves state. Restoration runs only after an active remote
session ends and is skipped if a new handoff has already started. It does not
blindly unhide an unknown AppKit hide. Regression tests cover return, cancellation
and preserving keyboard navigation when no remote session was active.

## Physical keyboard focus stays remote after the pointer returns

Apple's native Universal Control can run alongside ControllerKeys' independent
relay. In the M5 investigation, its system log retained the remote keyboard
target while returning only pointing input; a later local trackpad click returned
keyboard focus. ControllerKeys adds held controller modifiers to local keyboard
events, but does not route physical keyboard input between Macs.
This can make the physical keyboard appear disabled locally even when the
ControllerKeys pointer is back. The exact reported typing failure was not
independently reproduced.

If those two sharing systems overlap, disable Apple's sharing on the sending Mac
in **System Settings → Displays → Advanced** using the
**Allow your pointer and keyboard to move between any nearby Mac or iPad** switch.
ControllerKeys pairing remains independent. This also turns off native sharing
for the physical keyboard; re-enable the switch if that feature is needed.
For a temporary native-session disconnect, Apple documents
**Control-Option-Command-Delete**. See [Apple's Universal Control guide](https://support.apple.com/en-us/102459).

## 1. Steam Controller gyro drifts bottom-left

Status: fixed in local branch

Observed:
- With the Steam Controller held steady, entering gyro mouse mode can immediately bias the cursor toward the bottom-left.
- Quitting and reopening ControllerKeys does not clear the bias.

Target:
- Gyro mouse mode should treat the current steady pose as neutral.
- Any persistent sensor offset should be calibrated or filtered before producing mouse movement.

Investigation notes:
- Root cause found: gyro samples accumulated while gyro aiming/focus was inactive, then stale rates could replay when entering gyro aiming.
- Steam gyro bias is now reset when gyro aiming activates so the first steady samples in the mode define neutral.
- Added regression coverage around stale accumulator clearing, Steam bias reset, and steady Steam gyro offsets producing zero motion after calibration.

## 2. Apple TV Remote circular scroll should keep scroll ownership

Status: fixed in local branch

Observed:
- Circular motion on the clickpad perimeter scrolls correctly.
- If the finger brushes the center area during the circular gesture, the clickpad can accidentally resume mouse movement.

Target:
- Once a circular scroll gesture is active, it should keep scroll ownership until the finger fully leaves the touch surface for a short reset interval.
- Center-area touches during the same continuous touch should continue scrolling instead of moving the mouse.

Investigation notes:
- Circular scroll ownership now stays latched for the full touch session instead of dropping when the finger brushes inward.
- Touch-up resets the latch so a new touch session can move the mouse again.
- Added regression coverage for center brushes during active circular scroll.

## 3. Mac-to-Mac handoff pairing alerts steal controller mouse control

Status: fixed in local branch

Observed:
- Pairing flow alerts can interrupt controller mouse control.
- When the alert is up, controller-driven pointer input is unavailable, so the user must press Enter or use a physical mouse.

Target:
- Pairing prompts should use a UI surface that does not steal controller mouse control.
- The pairing flow should remain operable from ControllerKeys itself.

Investigation notes:
- Replaced the blocking `NSAlert.runModal()` pairing-code prompt with a nonactivating floating panel.
- Removed the settings-sheet pairing result alert; pairing progress and errors now stay inline in the settings UI.
- The pairing code presenter does not activate ControllerKeys or require an OK click, so controller-driven pointer input can keep routing.

2026-09-30 multi-Mac repair (local): discovery previously kept only the first
reply and discarded later Macs' codes. With a Studio and M3 MacBook responding,
the M3's displayed code could incorrectly report "Code did not match."
Pairing now keeps responses for 60 seconds and selects the Mac by the entered
code. Duplicate addresses for one handshake are accepted; code collisions
between different handshakes require a retry. Restart/reset/expiry cancel pending
connections. Regression coverage includes real key agreement for two receivers.

## 4. First-run onboarding does not add ControllerKeys to Input Monitoring

Status: fixed in local branch

Observed:
- During first-run onboarding, ControllerKeys can fail to appear automatically in System Settings → Privacy & Security → Input Monitoring.
- The user must manually add ControllerKeys with `+` or by dragging the app/icon into the list before the switch can be enabled.

Target:
- First-run setup should request Input Monitoring before Accessibility so macOS can register ControllerKeys in the Input Monitoring list before Accessibility masks the separate listen permission.
- The onboarding copy should explicitly tell users to add ControllerKeys manually if macOS does not insert it automatically.

Investigation notes:
- `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` is the correct request API, but requesting Accessibility first can make listen access appear granted without a separate Input Monitoring list entry.
- The wizard now walks Input Monitoring before Accessibility, delays opening the pane briefly after requesting access, and makes the manual-add fallback part of the numbered instructions.
