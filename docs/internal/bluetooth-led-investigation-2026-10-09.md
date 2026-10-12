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

A passing host test gate must not be described as proof that the user's
background issue is fixed.

## Lifecycle candidate — 2026-10-12

Sal tested signed/notarized 2.9.0 (32.1). His October 10 UTC replies confirm
background layer colors work, but initial backgrounding and reconnect remain
white until a colored layer is pressed and released. He accepts the workaround;
this is a partial fix, not full acceptance.
[Detailed reply](https://discord.com/channels/1497793147059834910/1497793250344439829/1558374205761003564).

The follow-up candidate schedules raw-only DS4 writes at 100, 500 and 1,500 ms
after `didResignActive` or PlayStation HID setup. Each attempt reads the latest
settings, including layer, brightness and disabled light bar. Foreground entry,
HID cleanup/controller switch and service cleanup invalidate outstanding work.
A new recovery supersedes previous attempts; successful writes don't suppress
later attempts because IOKit success does not prove the OS kept the color.
Missing HID/settings skip that attempt; no unbounded polling or HID re-enumeration
is introduced. Release logs include the trigger, attempt and IOKit result.

Scope remains DS4 Bluetooth on macOS 27. The normal framework path, other
controllers and older OS versions are unchanged. Timing/OS ownership remains a
hypothesis; 32.2 will test whether automatic delayed writes replace Sal's manual
layer workaround. Test build remains based on released 2.9.0 plus LED changes.

Acceptance without pressing a layer button:

1. Set a color, switch to Anki and wait two seconds; record any initial flash.
2. Reconnect while ControllerKeys stays in the background; wait two seconds.
3. Leave idle for 90+ seconds; check separately from reconnect.

Then check layer press/release, rapid app switching and light-off still behave.
Six deterministic scheduler regressions cover bounded delayed writes, fresh
layer/brightness/off state, late settings, cancellation, supersession and teardown.

## Validation

On 2026-10-09, an isolated Mac Studio source copy passed `make test-full`:
2,384 Swift tests, 38 skipped, zero failures, including all 10 LED tests;
15 Python checks, three skipped, zero failures. Host: macOS 26.6.2 (25G83),
so this does not exercise the macOS 27 gate or physical Bluetooth delivery.
Log: Studio `/tmp/controllerkeys-led-20261009.VHD36B/gate.log`.
The first harness attempt used a nonexistent XCTest configuration path and
exited before running tests; the normal runner above completed successfully.

On 2026-10-12, the lifecycle patch on current main passed the isolated Studio
`make test-full` gate: 2,397 Swift cases (34 skipped, zero failures), including
all six recovery regressions; 15 Python checks (three skipped, zero failures).
Studio remains macOS 26.6.2; scheduler tests inject time and do not prove physical
macOS 27 delivery. Log: `/tmp/controllerkeys-led-followup-main.yxuy9c1h/gate.log`.

The isolated 2.9.0-based test candidate (32.2) also passed `make test-full` on
Studio: 2,222 Swift cases (37 skipped) and 15 Python checks (three skipped),
zero failures. Candidate log: `/tmp/controllerkeys-led-followup-sal.d9fl88qh/gate.log`.
Universal Developer ID build was accepted by Apple notarization; the stapled
app inside the DMG passed strict signature and Gatekeeper verification.
Anonymous download matched SHA-256
`8e984e4a85cf686e2e6c0b608c715b3be96803d5df9d3091823e14b690e272b8`.
