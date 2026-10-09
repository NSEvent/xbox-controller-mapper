# Bluetooth light-bar regression follow-up

## Report

Sal / anonrandomdoc reported a Bluetooth DS4 reverting to white when
ControllerKeys backgrounds. ds4color restores the color from the background.
Reported system: M4 MacBook Air, macOS 27.0 (26A428).
The September 22 follow-up says the problem persists after the 2.9.0 fix.
This is customer evidence, not a local hardware reproduction.

## Confirmed code defect

Commit `34bbdc6f` enabled raw Bluetooth reports on macOS 27, but its DS4 and
DualSense builders return 77 bytes with the report ID removed. Numbered reports
must retain the ID in the buffer passed to `IOHIDDeviceSetReport`, even though
the API also takes a separate report ID argument.

Evidence:

- [ds4color's builder and write](https://github.com/bitmap4/ds4-lightbar-macos/blob/a6e491de82e7969eda1d0341583a31cb3b01ea1a/ds4color/core.py):
  78-byte DS4 report starting `11 C0 00 07`, RGB at bytes 8–10, little-endian
  CRC at bytes 74–77 over `A2` plus the first 74 report bytes.
- [HIDAPI's macOS transport](https://github.com/libusb/hidapi/blob/852cc68b8e0e4c7eba0815ef992951cd8b75c55b/mac/hid.c#L1022):
  `set_report` strips byte zero only for an unnumbered report (ID zero).
  For DS4's `0x11`, it passes the entire buffer to `IOHIDDeviceSetReport`.
- Existing ControllerKeys USB writers already retain their report IDs.
- Existing Bluetooth unit tests asserted the truncated 77-byte layout, so they
  could pass without detecting this transport-contract error.

## Patch scope

Both Bluetooth builders now return full 78-byte reports. DS4 also enables the
blink-update flag with zero durations, matching ds4color's solid-color packet.
The keep-alive writers share these builders. DS4 write failures use NSLog in
release builds. Regression tests include full independent fixtures and zlib-
derived CRC trailers; they do not establish physical delivery.

The macOS 27 gate and raw-then-framework ordering are retained. Earlier claims
that all older macOS versions silently block raw Bluetooth output are not
established by the malformed packets. Likewise, foreground-scoped GCDeviceLight
is a hypothesis from the report, not a verified Apple API contract.

## Remaining hardware acceptance

Use the affected Bluetooth DS4 and exact OS build, with ds4color's automatic
agent disabled during the test to avoid competing writers:

1. Set a distinctive color; background ControllerKeys; wait over 90 seconds.
2. Change layers in the background; check each configured color and light-off.
3. Reconnect the controller; repeat. Capture `[LED]` write errors if any.
4. Compare a raw-only write with framework-then-raw and raw-then-framework.
   Check immediately after backgrounding and after a delayed raw-only reapply.

Only if correct packets still lose color should a lifecycle reapply or change
in framework ownership become the next patch. The current observer fires on
`didBecomeActive`, not `didResignActive`, and the keep-alive waits for idle;
neither guarantees immediate recovery after a background reset.

No release or customer reply is part of this investigation. A passing host test
gate must not be described as proof that the user's background issue is fixed.

## Validation

On 2026-10-09, an isolated Mac Studio source copy passed `make test-full`:
2,384 Swift tests, 38 skipped, zero failures, including all 10 LED tests;
15 Python checks, three skipped, zero failures. Host: macOS 26.6.2 (25G83),
so this does not exercise the macOS 27 gate or physical Bluetooth delivery.
Log: Studio `/tmp/controllerkeys-led-20261009.VHD36B/gate.log`.
The first harness attempt used a nonexistent XCTest configuration path and
exited before running tests; the normal runner above completed successfully.
