# Discord Customer Requests — 2026-07-23

Status: implemented on 2026-07-23 in `13f0888` and `a078ccb`.

The implementation covers all three approved features. MIDI v1 always emits the
configured release value (default `0`); optional one-shot CC remains future scope.
Live customer validation in MIDI2LR and Keyboard Maestro remains before release.

## Sources

- Discord `#feature-requests`, `ranguard.`, 2026-07-19 through 2026-07-21:
  layer-aware Command Wheels and app-specific overrides without duplicating profiles.
- Discord `#feature-requests`, `rodrigocypriano6871`, 2026-07-23:
  MIDI CC output for MIDI2LR / Lightroom Classic and Keyboard Maestro workflows.
- Discord `#support`, checked through 2026-07-23: no additional unshipped feature
  request. The eight-way joystick request from `jacobusuys` shipped in v2.6.1.

## Triage

| Priority | Feature | Customer outcome | Recommendation |
| --- | --- | --- | --- |
| P1 | Layer-aware Command Wheels | A layer can replace the base wheel while active | Build as the first half of Contextual Layers |
| P1 | App-activated layers | App-specific overrides without copied profiles | Build with layer-aware wheels; defer general profile inheritance |
| P2 | Virtual MIDI CC output | Controller buttons trigger MIDI2LR commands and Keyboard Maestro macros | Ship button-triggered CC actions; continuous controls and direct Keyboard Maestro integration are out of scope |

The first two requests should ship together as **Contextual Layers**. An app-activated
layer is much less useful if the Command Wheel remains profile-global, and both features
need the same active-layer resolution rules.

---

## Feature 1 — Layer-aware Command Wheels

### Customer outcome

The base profile has a normal wheel. A layer may define its own wheel. Holding a layer
activator and then opening the Command Wheel shows that layer's wheel; a layer without a
custom wheel inherits the base wheel.

### Existing architecture

- `Profile.commandWheelActions` owns one profile-global wheel.
- `Layer` already provides transparent overrides for button mappings and per-stick tuning.
- `UIIntegrationService.handleCommandWheelPressed` currently reads
  `profileManager.activeProfile?.commandWheelActions`, without consulting
  `MappingEngineState.activeLayerIds`.
- `CommandWheelManager.prepare` snapshots the actions before showing the wheel. This is
  desirable: the wheel should not change underneath the user while it is open.

### Data model

Add an optional override to `Layer`:

```swift
var commandWheelActions: [CommandWheelAction]?
```

Semantics:

- `nil`: inherit the profile's base wheel.
- non-empty array: use this layer's custom wheel.
- empty array: intentionally disable the wheel in this layer.

Decode with `decodeIfPresent`; old profiles therefore inherit the base wheel.

### Runtime resolution

At wheel-button press:

1. Snapshot the active profile and the topmost active layer under the engine lock.
2. If the topmost layer has a non-`nil` wheel override, use it.
3. Otherwise use `Profile.commandWheelActions`.
4. Pass that action snapshot and the profile into `CommandWheelManager.prepare`.
5. Keep the prepared wheel stable until release, even if a layer changes while open.

Only the topmost active layer participates, matching current button/stick resolution.
Do not walk downward through multiple active layers.

### UI

In **Automate → Wheel**, add a scope picker:

> Base · Layer 1 · Layer 2 · …

For a layer:

- Default state: **Use Base Wheel**.
- Turning that off creates a custom override, initially copied from the base wheel.
- **Clear Wheel** produces an intentional empty override.
- **Revert to Base Wheel** sets the override back to `nil`.
- Existing preview, add/edit/delete, drag ordering, 12-item cap, action picker, and
  haptics remain unchanged.

### Acceptance

- Old profiles decode with every layer inheriting the base wheel.
- A custom layer wheel appears while that layer is active.
- A layer with no override uses the base wheel.
- An intentional empty override gives the existing error haptic and shows no wheel.
- Manual layer changes while the wheel is open do not swap its items.
- Macro/script/system-command references execute against the active profile as today.
- Imported/exported profiles preserve all three states: inherit, custom, and disabled.
- Universal Control executes the wheel resolved by the receiving Mac's active state.

### Tests

- `Layer` Codable coverage for `nil`, empty, and populated overrides.
- Pure resolver tests for base / inherited / custom / disabled cases.
- Topmost-layer precedence test.
- Wheel-open snapshot stability test.
- `ProfileManager+CommandWheel` mutation tests for base and layer scopes.

---

## Feature 2 — App-activated Layers

### Customer outcome

One durable base profile contains universal mappings. A frontmost app can automatically
activate a layer that contains only that app's overrides. Switching apps reveals the base
again. The user no longer maintains near-duplicate app profiles.

### Decision: layer binding before general profile inheritance

Build app-activated layers first. Do not generalize profiles into parent/child inheritance
for this release.

Why:

- `Layer` already has the requested transparent behavior: missing button and stick fields
  fall through to the profile.
- The app already monitors frontmost bundle IDs and links apps to full profiles.
- General profile inheritance needs merge semantics for buttons, chords, sequences,
  macros, scripts, wheels, joysticks, hardware settings, linked apps/controllers, and
  deletion/import behavior.
- The existing `inheritedOnScreenKeyboardProfileId` is deliberately narrow. It provides
  cycle-detection precedent, not a safe whole-profile merge.

If customers later need app overrides for surfaces a layer cannot express, revisit a
single **Base Profile** relationship. Do not stack arbitrary parents.

### Data model

Add profile-local app-to-layer bindings:

```swift
var appLayerBindings: [String: UUID] // bundle ID -> layer ID
```

Decode missing data as `[:]`. Enforce one automatic layer per app within a profile.
Deleting a layer removes bindings that reference it.

Keeping the binding on `Profile` rather than `Layer` makes the one-app/one-layer
invariant explicit and avoids duplicate bundle IDs scattered across layers.

### Runtime state

Track the automatic layer separately from held/manual layers:

```swift
var appActivatedLayerId: UUID?
var manualActiveLayerIds: [UUID]
```

Resolved precedence, lowest to highest:

1. Base profile
2. App-activated layer
3. Most recently activated manual layer

Manual layers therefore remain temporary overrides over the automatic app context. Do
not insert the automatic layer into the same collection used by button-release cleanup;
releasing a physical activator must never deactivate it.

### App/profile precedence

1. Existing full-profile app link resolves first.
2. Existing linked-controller/default rules choose the active profile.
3. The frontmost app's layer binding is then resolved inside that active profile.
4. ControllerKeys' own settings window suppresses app-layer activation while editing,
   matching the current "restore editing profile" behavior.

It is legal for a full-profile app link to land on a profile that also has an app-layer
binding. The destination profile resolves first, then its app layer activates.

### UI

In the layer editor, add **Linked Apps…** using the existing installed/running-app picker.

Explain the distinction:

> When a linked app is frontmost, this layer activates automatically. A manually held
> layer temporarily takes priority.

The existing profile-level **Linked Apps…** remains a full-profile switch. Label the two
surfaces clearly:

- Profile: **Switch to this profile for apps**
- Layer: **Activate this layer for apps**

Show linked app icons beside the layer name, as the profile sidebar already does.

### Transition safety

When the automatic layer changes:

- Resolve the new layer atomically with the current profile.
- Release any held key/modifier/repeat state whose mapping came from the outgoing layer.
- Apply the incoming layer's LED and stick tuning without synthesizing an activator press.
- Fall back to the profile LED/tuning when no app layer is active.
- Re-resolve the Command Wheel only on its next open; never mutate an open wheel.

### Scope boundary

Version 1 app layers override only what `Layer` owns after Feature 1:

- button mappings
- left/right stick tuning
- DualSense/DS4 LED settings
- Command Wheel

Chords, sequences, gestures, macros, scripts, touchpad configuration, and other
profile-wide settings continue to come from the profile. This must be stated in the UI
and release notes.

### Acceptance

- Linking Lightroom to a "Lightroom" layer in the default profile activates its
  overrides only while Lightroom is frontmost.
- Unmapped controls fall through to the base profile.
- A manually held layer wins over the app layer, then returns to the app layer on release.
- Switching away safely releases outputs started by the app layer.
- Full-profile app links retain existing behavior.
- Layer deletion clears stale bindings.
- Old profiles decode unchanged.
- Export/import round-trips bindings and handles missing referenced layer IDs safely.

### Tests

- Pure app-layer resolver tests covering all precedence rules.
- Profile Codable and equality coverage.
- Layer-deletion cleanup.
- App transition held-output cleanup.
- LED/stick/wheel resolution with automatic plus manual layers.
- Regression tests for existing profile-linked-app and linked-controller switching.

---

## Feature 3 — Virtual MIDI CC Output

### Scope decision

Kevin confirmed on 2026-07-23:

- Version 1 only needs controller buttons to trigger commands.
- Receiving MIDI CC from a virtual **ControllerKeys** device is sufficient for Keyboard
  Maestro.
- Direct Keyboard Maestro macro discovery/execution is not needed.
- Sticks, triggers, and touchpad do not need continuous MIDI behavior in this version.

### Customer outcome

ControllerKeys appears to other macOS apps as a virtual MIDI device named
**ControllerKeys**. A customer can use MIDI Learn in MIDI2LR or Keyboard Maestro, press
a controller input, and bind the resulting MIDI Control Change message.

This is technically feasible without a third-party dependency. CoreMIDI can create a
virtual source with `MIDISourceCreateWithProtocol`, then transmit through it with
`MIDIReceivedEventList`.

### Compatibility facts

- MIDI2LR receives CC, Pitch Bend, and Note messages. For normal MIDI CC, it expects
  continuous controls in absolute `0...127` mode and buttons to send `127` on press and
  `0` on release.
- MIDI2LR recommends avoiding CC 98-101 and 120-127 because those ranges have
  NRPN/RPN/mode meanings.
- Keyboard Maestro can learn a MIDI controller change and filter by device, channel,
  controller number, value, increases, or decreases.

References:

- <https://github.com/rsjaffe/MIDI2LR/wiki/MIDI-Controller-Setup>
- <https://wiki.keyboardmaestro.com/trigger/MIDI>
- <https://developer.apple.com/documentation/coremidi/midisourcecreatewithprotocol(_:_:_:_:)>

### Version 1 — Discrete CC actions

Button-like inputs emit MIDI CC. This is the complete approved scope, not a prerequisite
for continuous controls.

#### Action model

```swift
struct MIDIControlChange: Codable, Equatable {
    var channel: UInt8       // UI 1...16; encoded internally 0...15 if needed
    var controller: UInt8    // 0...127
    var pressValue: UInt8    // default 127
    var releaseValue: UInt8? // default 0; nil = one-shot
}
```

Add `midiControlChange` as a first-class optional action to every
`ExecutableAction` surface rather than hiding it inside a shell command:

- button, long-hold, and double-tap mappings
- chords and sequences
- gestures
- Command Wheel actions

Extend `ActionType`, conflict validation, display strings, stats, import auditing, and
the shared mapping editor. Exactly one action type remains valid.

#### Emission behavior

- Normal button mapping: send the press value on physical press and release value on
  physical release.
- Chord, sequence, gesture, double-tap, long-hold, or wheel action: pulse the press
  value, then release value after a short fixed interval.
- A `nil` release value sends only the configured press value.
- Profile/layer change, mapping disable, controller disconnect, or app termination sends
  pending release values before teardown.
- Repeated presses must produce repeatable `127 → 0 → 127 → 0` transitions so MIDI Learn
  triggers that look for "changed to 127" continue to fire.

#### Service

Add a serial `MIDIOutputService`:

- Lazily create a MIDI 1.0 virtual source named **ControllerKeys**.
- Assign a stable CoreMIDI unique ID so clients can retain the endpoint across launches.
- Encode and send CC status/data bytes.
- Clamp malformed decoded values before emission.
- Log CoreMIDI creation/send failures with `NSLog`.
- Dispose the endpoint and client cleanly.

No MIDI permission or DriverKit extension is required for an app-owned virtual source.

#### UI

Add **MIDI** beside Key / Macro / System / Script in the shared action editor:

- Channel: 1-16
- Controller: 0-127
- Press value: 0-127, default 127
- **Send on release**: on by default
- Release value: 0-127, default 0
- **Test** button

Show a non-blocking MIDI2LR warning for CC 98-101 and 120-127. Do not prohibit them;
other MIDI clients may intentionally use those values.

#### Acceptance

- ControllerKeys appears as a stable source in MIDI-capable apps after launch/use.
- MIDI2LR MIDI Learn sees the device, channel, CC number, and `127/0` button behavior.
- Keyboard Maestro MIDI Learn sees ControllerKeys and repeated presses re-trigger.
- Every mapping surface round-trips MIDI actions through profile export/import.
- Old profiles decode unchanged.
- Output teardown cannot leave a logical MIDI control held.
- Existing key/macro/script/system actions retain their priority and behavior.

#### Tests

- MIDI packet byte encoding for channels and edge values.
- Value clamping and reserved-range warning policy.
- Action conflict/effective-type coverage.
- Press/release and pulse lifecycle tests with a fake MIDI sink.
- Profile round-trip coverage across every executable surface.
- CoreMIDI smoke test with a temporary virtual destination.

### Future — Continuous controller inputs

Out of scope for version 1. Revisit only after a new customer request identifies a
specific continuous Lightroom workflow.

A gamepad is not a normal control surface:

- Sticks spring back to center, so absolute CC would reset a Lightroom slider to midpoint.
- Triggers spring back to zero, so absolute CC would reset a parameter on release.
- Sticks are usually better as **relative** CC controls: deflection repeatedly emits
  increment/decrement values, with rate or step size based on magnitude.
- MIDI2LR supports relative two's-complement, sign-and-magnitude, and binary-offset
  controller modes, but the customer must configure the matching mode.

Possible later scope:

- Per-stick MIDI mode with separate X/Y CC numbers.
- Relative mode by default for sticks; optional absolute mode.
- Trigger and touchpad axes only if a concrete workflow needs them.
- Inversion, deadzone, update-rate cap, integer-value deduplication, and recenter behavior.

Out of scope for the initial feature:

- MIDI input/feedback from Lightroom to ControllerKeys
- Note, Pitch Bend, NRPN, RPN, SysEx, MIDI clock, or MIDI 2.0-specific messages
- Connecting directly to hardware MIDI destinations
- Direct Keyboard Maestro macro enumeration/execution; MIDI CC already provides the
  supported integration boundary

---

## Recommended implementation order

1. [x] Layer-aware Command Wheels.
2. [x] App-activated layers in the same Contextual Layers release.
3. [x] CoreMIDI virtual source plus discrete CC action.
4. [ ] Validate button-triggered CC with MIDI2LR and Keyboard Maestro.

## Implementation verification

- Debug app and test bundle build on `kmacstudio`.
- CoreMIDI enumerates `ControllerKeys` with stable unique ID `0x434B5953`.
- 198 affected action, profile, layer, wheel, MIDI, and lifecycle tests pass.
- Focused app-host regression gate passes: 29 tests.
- Full app-host suite passes through the new feature suites. One pre-existing
  `OBSWebSocketCommand_Encoding` test hangs both alone and in the full suite; the
  full suite was rerun with only that test skipped.
