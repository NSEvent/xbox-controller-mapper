# Xiaomi Remote Pro 2 — RC003 probe

Observed on Kevin's paired remote, 2026-10-13. All 13 buttons below verified
with labelled physical presses. This model has no Play/Pause button (Kevin).

## Identity

- Bluetooth name: `小米蓝牙语音遥控器` (Xiaomi Bluetooth voice remote).
- Vendor/product: `0x2717:0x32B8` (10007:12984).
- Manufacturer: `MIOM`; model `RC003`; hardware `V2.0`; firmware `2671`.
- Transport: `Bluetooth Low Energy`.
- Primary HID usage: Generic Desktop / Keyboard (`0x01:0x06`).
- Product name was initially empty in IORegistry; later present through IOKit.
  Match VID/PID and transport rather than requiring the advertised name.
- Maximum input report length: 121 bytes, including report ID.

## Descriptor

```text
05010906a10105070906a101850195037510150025fe190029fe8100c00600ff0900a101850675089578150025ff190029ff8100850775089578150025ff190029ff8100850875089578150025ff190029ff8100c0c0
```

| Report | Payload | Meaning from descriptor |
| --- | --- | --- |
| 1 | 6 bytes | Three 16-bit array entries, Keyboard page, usage/logical range 0–254 |
| 6 | 120 bytes | Vendor page `0xFF00`, byte array; semantics unverified |
| 7 | 120 bytes | Vendor page `0xFF00`, byte array; semantics unverified |
| 8 | 120 bytes | Vendor page `0xFF00`, byte array; semantics unverified |

Report 1 is a complete key snapshot, not a gamepad button bitmask. Decode
little-endian pairs and diff the active key set for presses/releases. Repeated
identical snapshots should not generate extra presses. Read all three slots;
the tested physical Up + OK chord did not expose simultaneous keys.

## Verified physical buttons

Kevin pressed Up → Down → Left → Right → center OK on 2026-10-13,
followed by the function-button passes recorded in the fixture provenance.
Each press produced the following report, followed by `01 00 00 00 00 00 00`
on release. All codes are on the Keyboard page. The key appeared in the second
slot, so a decoder must inspect all three slots.

| Button | Usage | Full input report |
| --- | --- | --- |
| Up | `0x52` (82) | `01 00 00 52 00 00 00` |
| Down | `0x51` (81) | `01 00 00 51 00 00 00` |
| Left | `0x50` (80) | `01 00 00 50 00 00 00` |
| Right | `0x4F` (79) | `01 00 00 4f 00 00 00` |
| Center OK | `0x28` (40) | `01 00 00 28 00 00 00` |
| Back | `0xF1` (241) | `01 00 00 f1 00 00 00` |
| Home | `0x4A` (74) | `01 00 00 4a 00 00 00` |
| Menu | `0x65` (101) | `01 00 00 65 00 00 00` |
| Volume Up | `0x80` (128) | `01 00 00 80 00 00 00` |
| Volume Down | `0x81` (129) | `01 00 00 81 00 00 00` |
| TV | `0x35` (53) | `01 00 00 35 00 00 00` |
| Microphone | `0x3E` (62) | `01 00 00 3e 00 00 00` |
| Power | `0x66` (102) | `01 00 00 66 00 00 00` |

Replay evidence: `xiaomi-remote-navigation-fixture.json` and
`xiaomi-remote-function-fixture.json` beside this document. Volume Down was
repeated twice with identical results. Microphone's tap produces a key event;
voice audio support is a separate, unverified capability. No reports 6–8 were
seen during these button taps.

The initial function pass yielded only four responses; the subsequent isolated
pass resolved Volume Down and microphone and added TV and Power.

## Holds and combinations

- Volume Up: one press, zero snapshot on release after 1.935 seconds.
- Volume Down: one press, zero snapshot on release after 2.010 seconds.
- OK: one press, zero snapshot on release after 2.520 seconds.
- D-pad Up: one press, zero snapshot on release after 1.425 seconds.
- No repeat reports arrived while those buttons were held. Keep the control
  pressed until a snapshot removes it; mapping-engine timers can provide
  long-hold/repeat actions without hardware autorepeat.
- Volume Up + OK attempt exposed only Volume Up; the separately requested
  D-pad Up + OK attempt emitted only a zero snapshot, with no active key.
  This is evidence against those two chords, not a test of every combination.
- No vendor reports arrived in these holds. Disconnect-while-held remains
  untested; any driver must release held controls on disconnect/stop.

Full timestamped traces: `xiaomi-remote-session-1.jsonl` and
`xiaomi-remote-session-2.jsonl` beside this document. The first holds were on
the volume rocker; the second session disambiguated the directional ring.

## Capture

```sh
swift Scripts/probe-xiaomi-remote.swift 900 --shared > /tmp/xiaomi-remote-capture.jsonl
```

The script matches only this VID/PID and logs raw reports plus decoded report-1
slots as JSONL. It exits after the requested duration (maximum 30 minutes).
Default exclusive mode fails on this Mac with `kIOReturnNotPrivileged`
(`0xE00002C1`); shared mode is supported. Shared capture leaves native input
active, so keep a harmless target foreground. Power was physically tapped in
this investigation and produced the report in the table above.

Karabiner initially exclusively opened this keyboard interface. Shared capture
then failed with `kIOReturnExclusiveAccess` (`0xE00002C5`). Temporarily setting
`ignore: true` for only VID/PID 10007:12984, `is_keyboard: true`, released the
interface and allowed capture. Restore this probe-only exclusion afterward.
Both manager-level and direct-device exclusive opens returned NotPrivileged.
The temporary exclusion was restored byte-for-byte after both sessions.

## Driver work remaining

1. Use the 13 captured mappings; give this remote its own button availability
   (especially TV and microphone, with no invented Play/Pause or touch surface).
2. Release held buttons on stop/disconnect; do not promise hardware chords
   from the descriptor alone. Additional combinations remain untested.
3. Determine vendor-report semantics without treating vendor bytes as keys.
4. Implement a pure snapshot decoder, scoped HID service, controller identity,
   availability/presentation, and regression fixtures using captured reports.
5. Resolve native-input suppression and Karabiner coexistence before claiming
   remapping support. Reuse the S29 service lifecycle patterns (mapping toggle,
   permission gating, callback teardown, held-button release).
6. Run ControllerKeys tests on kmacstudio; build/install on the MacBook for
   final hardware verification. No production support has been added yet.
