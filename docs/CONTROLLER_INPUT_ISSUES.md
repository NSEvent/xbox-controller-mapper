# Controller Input Issues

Last updated: 2026-05-30

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

Status: queued

Observed:
- Pairing flow alerts can interrupt controller mouse control.
- When the alert is up, controller-driven pointer input is unavailable, so the user must press Enter or use a physical mouse.

Target:
- Pairing prompts should use a UI surface that does not steal controller mouse control.
- The pairing flow should remain operable from ControllerKeys itself.

Investigation notes:
- Audit pairing confirmation dialogs and replace blocking modal alerts where possible.
- Prefer an in-window sheet, nonmodal panel, popover, or app-owned confirmation UI that keeps input routing active.
