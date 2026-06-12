# SDL Platform Compatibility Fallback

## Problem

SDL `gamecontrollerdb.txt` often has useful Windows or Linux mappings for a controller before it has a `platform:Mac OS X` row.

ControllerKeys already falls back from macOS mappings to same VID/PID mappings from any platform. That helps coverage, but today it does not validate whether the connected Mac HID descriptor can actually satisfy the borrowed row. A Windows row can reference `b17`, `a5`, or `h0.1` even when macOS exposes fewer buttons, fewer axes, or no hat switch.

This design makes cross-platform SDL fallback descriptor-aware instead of blind.

## Goals

- Safely reuse non-macOS SDL rows when the live Mac HID descriptor is compatible.
- Prefer real macOS SDL rows whenever available.
- Reject borrowed rows that reference unavailable buttons, axes, or hat switches.
- Keep generic HID input deterministic and debuggable.
- Show users when ControllerKeys is borrowing a compatible non-macOS SDL row.
- Avoid bulk-generating Mac rows from Windows rows without live validation.

## Benefits

- More controllers work on Mac without waiting for upstream SDL to add macOS rows.
- Windows/Linux SDL rows become useful coverage instead of dead data.
- Bad borrowed rows fail fast instead of silently producing half-working buttons.
- Device support is easier to debug because ControllerKeys can explain which row it selected and why it rejected others.
- Physical controller testing gets cheaper: one live descriptor scan can validate whether an existing SDL row is safe to reuse.
- The bundled database stays closer to upstream because ControllerKeys does not need to copy every Windows row into hand-written Mac rows.
- UI provenance builds trust: when a user sees "using Windows SDL fallback," they understand why a third-party controller works and why it may still need validation.

## Non-Goals

- Do not support XInput-only text GUID rows as HID mappings.
- Do not infer keyboard-mode controllers as gamepads.
- Do not rewrite SDL mappings or auto-upload generated rows upstream.
- Do not solve vendor-specific report protocols.

## Current Behavior

Relevant files:

- `XboxControllerMapper/XboxControllerMapper/Services/Controller/GameControllerDatabase.swift`
- `XboxControllerMapper/XboxControllerMapper/Services/Controller/GenericHIDController.swift`
- `XboxControllerMapper/XboxControllerMapper/Services/Controller/GenericHIDController+Inference.swift`
- `XboxControllerMapper/XboxControllerMapper/Services/Controller/ControllerService+GenericHID.swift`

Related design:

- `docs/internal/specs/controller-support-dumps.md`

Lookup order today:

1. Exact macOS GUID.
2. macOS GUID with version `0`.
3. Best same VID/PID row from any platform.
4. Inferred generic mapping.

The weak point is step 3. Same VID/PID is necessary, but not sufficient.

## Compatibility Header

Add a small runtime descriptor summary from the connected `IOHIDDevice`.

```swift
struct HIDElementLayout: Equatable {
    let buttonCount: Int
    let axisCount: Int
    let hasHat: Bool
    let axisUsages: [Int]
    let buttonUsages: [Int]
}
```

This header must be built with the exact same rules `GenericHIDController` uses for runtime input:

- Use only supported input elements: button, misc input, axis input.
- If any input element belongs to a controller collection, ignore input elements outside controller collections.
- Button indices are `kHIDPage_Button` elements sorted by usage.
- Axis indices are Generic Desktop `X`, `Y`, `Z`, `Rx`, `Ry`, `Rz` sorted by usage.
- Hat support comes from Generic Desktop `Hatswitch`.

Important: do not use the current `GenericHIDController+Inference.elementSummary` as-is. It counts all input elements and does not apply the controller-collection filter. The compatibility header must match runtime enumeration or validation will lie.

## Mapping Compatibility

A candidate SDL row is compatible with a live Mac HID descriptor when every referenced element exists.

Button refs:

```swift
.button(index) is valid if index < layout.buttonCount
```

Axis refs:

```swift
.axis(index, _, _) is valid if index < layout.axisCount
```

Hat refs:

```swift
.hat(0, _) is valid if layout.hasHat
```

Anything else is invalid.

Validate both `buttonMap` and `axisMap`, because SDL allows triggers to be mapped from buttons and D-pad directions to be mapped from axes.

## Candidate Model

Store parsed rows as candidates, not only one dictionary entry per normalized GUID.

```swift
struct SDLControllerMappingCandidate {
    let mapping: SDLControllerMapping
    let originalGUID: String
    let normalizedGUID: String
    let platform: String?
    let properties: GUIDDeviceProperties?
}
```

Keep existing fast macOS dictionary for exact lookup, but add an array or multimap for platform fallback:

```swift
private var macMappings: [String: SDLControllerMapping]
private var allPlatformCandidatesByVendorProduct: [VendorProduct: [SDLControllerMappingCandidate]]
```

Why: duplicate normalized GUIDs exist. A single `allPlatformMappings[guid] = mapping` can overwrite a useful row before scoring sees it.

## Selection Algorithm

Inputs:

- `vendorID`
- `productID`
- `version`
- `transport`
- `layout: HIDElementLayout`

Algorithm:

```swift
func lookup(..., layout: HIDElementLayout?) -> SDLControllerMapping? {
    if let exactMac = macMapping(exactGUID) {
	return exactMac
    }

    if let versionZeroMac = macMapping(versionZeroGUID) {
	return versionZeroMac
    }

    let candidates = allPlatformCandidatesByVendorProduct[VendorProduct(vendorID, productID)] ?? []

    let compatible = candidates.filter { candidate in
	guard candidate.properties?.vendorID == vendorID,
	      candidate.properties?.productID == productID else {
	    return false
	}
	guard let layout else {
	    return candidate.platform == "Mac OS X"
	}
	return candidate.mapping.isCompatible(with: layout)
    }

    return compatible
	.sorted(by: candidateScore)
	.first?
	.mapping
}
```

Scoring:

| Rank | Condition |
|------|-----------|
| 0 | macOS exact GUID |
| 1 | macOS version-zero GUID |
| 2 | compatible macOS same VID/PID |
| 3 | compatible same-bus, same-version platform row |
| 4 | compatible same-bus, version-zero platform row |
| 5 | compatible same-bus platform row |
| 6 | compatible any-bus, same-version platform row |
| 7 | compatible any-bus platform row |

Tie-breakers:

1. Prefer `platform:Mac OS X`.
2. Prefer same bus.
3. Prefer same version.
4. Prefer version `0`.
5. Stable sort by original GUID, then name.

## Integration Flow

Current fallback:

```swift
let mapping = database.lookup(vendorID:productID:version:transport:)
    ?? GenericHIDController.inferredMapping(...)
```

New fallback:

```swift
let layout = GenericHIDController.elementLayout(for: device)
let mapping = database.lookup(
    vendorID: vendorID,
    productID: productID,
    version: version,
    transport: transport,
    compatibleWith: layout
) ?? GenericHIDController.inferredMapping(...)
```

Expose `elementLayout(for:)` from `GenericHIDController` so compatibility validation and runtime enumeration use one source of truth.

## Debug Logging

When debug logging is enabled, emit:

- Connected HID identity: VID, PID, version, transport, product name.
- Compatibility header: button count, axis count, hat presence.
- Selected SDL row: name, platform, original GUID.
- Rejected candidate count.
- First few rejection reasons:
  - `missing button b17`
  - `missing axis a5`
  - `missing hat h0`

This matters for 8BitDo devices because support often starts with "the Windows SDL row exists, but Mac does not work."

## UI Behavior

When ControllerKeys selects a compatible non-macOS row, show the borrowed platform in the third-party controller diagnostics/settings UI.

Example copy:

```text
Mapping source: SDL Windows fallback
```

For normal connected-controller surfaces, keep the main controller name clean. Do not clutter the button-mapping view with platform provenance unless the user opens controller details or troubleshooting.

## Tests

Unit tests:

- Exact macOS row still wins over compatible Windows row.
- Version-zero macOS row still wins over compatible Windows row.
- Windows row with same VID/PID and valid element refs is selected.
- Windows row with missing button ref is rejected.
- Windows row with missing axis ref is rejected.
- Windows row with hat refs is rejected when `hasHat == false`.
- Duplicate normalized GUID candidates do not overwrite each other before scoring.
- No layout means non-macOS rows are not blindly accepted.

Regression fixtures:

- 8BitDo Micro: validate a Windows-only row can be borrowed if descriptor matches.
- 8BitDo Zero 2: validate `righty:a3`, not `righty:a31`.
- 8BitDo Pro 3 / Ultimate: validate `paddle1...paddle4` stay mappable.

## Rollout

1. Extract runtime element-layout builder from `GenericHIDController`.
2. Add compatibility checks to `SDLControllerMapping`.
3. Replace single `allPlatformMappings` fallback with candidate storage.
4. Add debug logging for selected and rejected rows.
5. Update architecture docs after behavior ships.
6. Test with physical 8BitDo Micro, Zero 2, Lite 2, and one Ultimate/Pro controller.

## Open Questions

- Should a user-approved validated mapping be saved into the user database as `platform:Mac OS X`?
- Should BLE use SDL bus `0x0006` when IOKit transport says Bluetooth Low Energy, or keep current `0x0005` behavior for compatibility?
- Should `misc2`, `paddle5`, or future SDL names get mapped now, or only when a physical controller proves need?
