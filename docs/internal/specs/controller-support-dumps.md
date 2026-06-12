# Controller Support Dumps

## Problem

When ControllerKeys shows no connected controller, users often still have a USB or Bluetooth HID device attached. The app needs a guided way to collect enough data to support that controller without asking the user to install developer tools or describe raw HID behavior manually.

The same dump should also help power users or AI assistants create a temporary SDL mapping row while official support is pending.

## Goals

- Let users pick a connected USB or Bluetooth HID device when ControllerKeys cannot map it.
- Capture enough static HID metadata and live input observations to add or validate SDL support.
- Make submission to Kevin explicit and user-controlled.
- Produce an AI-friendly artifact users can paste into ChatGPT/Claude/Codex to draft a temporary `gamecontrollerdb.txt` row.
- Avoid collecting private identifiers unless the user explicitly opts in.

## Non-Goals

- Do not upload diagnostics automatically.
- Do not collect unrelated HID devices without user selection.
- Do not require Xcode, Homebrew, or command-line tools.
- Do not promise the generated SDL row is correct without user verification.

## User Flow

Trigger points:

- No controller connected screen.
- Third-party controller settings.
- Support / troubleshooting menu.
- Help menu: `Help > Diagnose Unsupported Controller`.

Flow:

1. User clicks `Diagnose Unsupported Controller`.
2. App lists connected HID devices that look relevant:
   - Generic Desktop GamePad, Joystick, MultiAxisController.
   - Known SDL VID/PID rows even if macOS platform row is missing.
   - Bluetooth / BLE devices with gamepad-like element counts.
3. User selects a device.
4. App shows device identity and a privacy note.
5. User starts a guided input capture.
6. App asks them to press each physical control:
   - Face buttons.
   - D-pad directions.
   - Bumpers.
   - Triggers.
   - Sticks and stick clicks.
   - Menu/view/home/share.
   - Paddles or extra buttons.
7. App records raw element changes for each prompt.
8. App generates:
   - `controller-support-dump.json`
   - `controller-support-dump.md`
   - AI prompt text.
9. User chooses:
   - Copy dump.
   - Copy AI prompt.
   - Open GitHub issue draft.
   - Compose support email with attachment.

No network request happens until the user chooses a submission action.

## Help Menu Entry

Add a Help menu item:

```text
Diagnose Unsupported Controller...
```

Behavior:

- Opens the same diagnostic flow used by the no-controller screen.
- Works even when ControllerKeys currently has no active controller.
- Starts with device selection, not capture, so users can choose the correct USB/Bluetooth HID device.
- Shows the privacy note before generating a support dump.
- Does not submit anything automatically.

This should be discoverable from macOS menu search for terms like `diagnose`, `unsupported`, `controller`, `dump`, and `support`.

## Dump Contents

JSON shape:

```json
{
  "schemaVersion": 1,
  "appVersion": "1.2.3",
  "createdAt": "2026-06-11T12:00:00-07:00",
  "platform": {
    "os": "macOS",
    "version": "15.5",
    "architecture": "arm64"
  },
  "device": {
    "vendorId": "0xc82d",
    "productId": "0x9020",
    "version": "0x0001",
    "transport": "Bluetooth",
    "productName": "8BitDo Micro",
    "manufacturer": "8BitDo",
    "serialHash": "sha256:...",
    "deviceAddressHash": "sha256:..."
  },
  "sdlGuid": {
    "constructed": "05000000c82d00002090000001000000",
    "versionZero": "05000000c82d00002090000000000000"
  },
  "topLevelUsages": [
    { "usagePage": "0x01", "usage": "0x05", "label": "GamePad" }
  ],
  "elementLayout": {
    "buttonCount": 15,
    "axisCount": 4,
    "hasHat": true,
    "buttonUsages": [1, 2, 3, 4, 5],
    "axisUsages": ["X", "Y", "Z", "Rx"]
  },
  "elements": [
    {
      "kind": "button",
      "sdlRef": "b0",
      "usagePage": "0x09",
      "usage": "0x01",
      "logicalMin": 0,
      "logicalMax": 1
    },
    {
      "kind": "axis",
      "sdlRef": "a0",
      "usagePage": "0x01",
      "usage": "0x30",
      "usageName": "X",
      "logicalMin": 0,
      "logicalMax": 255
    }
  ],
  "captures": [
    {
      "prompt": "Press physical A / south face button",
      "observed": [
	{ "sdlRef": "b1", "from": 0, "to": 1, "timestampMs": 1542 },
	{ "sdlRef": "b1", "from": 1, "to": 0, "timestampMs": 1710 }
      ],
      "suggestedSDLName": "a"
    }
  ],
  "candidateRows": [
    {
      "sourcePlatform": "Windows",
      "compatible": true,
      "name": "8BitDo Micro",
      "row": "03000000c82d00002090000000000000,8BitDo Micro,...,platform:Windows,"
    }
  ],
  "privacy": {
    "serialIncluded": false,
    "deviceAddressIncluded": false,
    "serialHashIncluded": true,
    "deviceAddressHashIncluded": true
  }
}
```

Markdown shape:

- Human summary.
- Device identity.
- SDL GUIDs.
- Element layout.
- Button capture table.
- Axis capture table.
- Candidate SDL row.
- Reproduction notes.

## Privacy

Default behavior:

- Include VID/PID/version/transport/product/manufacturer.
- Include hashed serial and device address when available.
- Do not include raw serial, raw Bluetooth address, usernames, paths, or profile contents.

Optional advanced toggle:

```text
Include raw hardware identifiers for support
```

Use only if stable device identity debugging requires it. Keep default off.

## AI Prompt Export

The app should generate a copyable prompt containing the dump and clear constraints.

Prompt template:

```text
I am trying to add a temporary SDL gamecontrollerdb mapping for ControllerKeys on macOS.

Use the HID dump below to draft a single `platform:Mac OS X` SDL mapping row.

Rules:
- Use the constructed SDL GUID from the dump unless the dump says to use version-zero.
- Map physical controls from the `captures` section, not from assumptions about the product name.
- Use SDL names: a, b, x, y, leftshoulder, rightshoulder, lefttrigger, righttrigger, leftstick, rightstick, dpup, dpdown, dpleft, dpright, back, start, guide, misc1, paddle1, paddle2, paddle3, paddle4.
- Use refs like b0, a0, +a2, -a2, h0.1.
- If a physical control was not captured, omit it.
- Return:
  1. The SDL row.
  2. A short explanation of uncertain controls.
  3. A checklist for testing the row in ControllerKeys.

HID dump:
```json
...
```
```

The app should also show where to put the row:

```text
~/.config/controllerkeys/gamecontrollerdb.txt
```

Never instruct users to edit the app bundle resource.

## Temporary Mapping Install

Power-user flow:

1. User copies AI-generated SDL row.
2. App offers `Import SDL Mapping Row`.
3. App validates:
   - GUID is 32 hex chars.
   - `platform:Mac OS X` exists.
   - VID/PID matches selected device.
   - Element refs are compatible with current `HIDElementLayout`.
4. App writes to user database path:
   - `~/.config/controllerkeys/gamecontrollerdb.txt`
5. App reloads `GameControllerDatabase`.
6. App reconnects/retries generic HID fallback.

This should be treated as user-supplied configuration, not bundled official support.

## Submission

Preferred MVP:

- `Copy Support Dump`
- `Open GitHub Issue`
- `Compose Email to Support`

GitHub issue draft should include:

- Controller name.
- macOS version.
- Connection type.
- Dump markdown.
- Attach JSON if possible.

Future optional endpoint:

- `Submit to Kevin`
- Requires an explicit click.
- Shows exactly what will be submitted.
- Returns a copyable support ID.

## Implementation Notes

- Reuse the future `HIDElementLayout` builder from the SDL platform compatibility work.
- The dump script and in-app diagnostic should share the same core model.
- Keep the standalone script useful for support outside the app:
  - `swift Scripts/controller-support-dump.swift`
  - list devices
  - select device
  - write JSON/Markdown to Desktop
- Capture mode should listen only to the selected `IOHIDDevice`.
- Show live raw refs as the user presses controls, e.g. `b1 down`, `a0 0.52`.
- Store capture events with timestamps, but derive final mapping from stable element refs.
- If macOS denies device open, report the IOKit error code and suggest reconnecting or changing controller mode.

## Tests

- JSON dump redacts raw serial/address by default.
- SDL GUID construction matches `GameControllerDatabase.constructGUID`.
- Element layout matches `GenericHIDController` runtime enumeration.
- Imported SDL row rejects missing `bN`, missing `aN`, and missing hat refs.
- AI prompt contains no raw serial/address when privacy defaults are used.
- Device list excludes obvious keyboards/mice unless they also expose a controller top-level usage.

## Rollout

1. Build standalone dump script for developer/support use.
2. Extract shared dump model into app code.
3. Add in-app unsupported-controller diagnostic UI.
4. Add Help menu entry for the same diagnostic flow.
5. Add copy/export flows.
6. Add user SDL row import and validation.
7. Add explicit submission flow if support volume justifies it.
