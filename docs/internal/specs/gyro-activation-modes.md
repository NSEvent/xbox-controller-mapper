# Gyro Activation Modes & Virtual Gyro Actions

Make gyro aiming a first-class pointing device: always-on gyro, ratcheting, and bindable
gyro on/off actions that emit no keystrokes — instead of the current "hold the focus-mode
modifier to gyro-aim" model.

## Motivation

Discord support request (ploki, 2026-09-02, DualSense):

> I just want it to work like mouse without focus mode, and when I press mute (or
> anything really) gyro stopping so I can reposition (ratcheting). Right now I need to
> assign a modifier like cmd/shift/option and assign that to mute, but that also sends
> extra commands out I don't necessarily want. I.e. if I want mute to output Z and
> toggle gyro, I can't do that. Right now it's like "hold for focus" to gyro aim.

Three real problems behind that:

1. **Inverted activation model.** Gyro only runs while focus mode is active
   (`JoystickHandler.processGyroAiming` gates on `gyroAimingEnabled && isFocusActive`).
   Gyro-aim users expect the opposite default: gyro on like a mouse, with a button to
   *pause* it so they can re-center the controller ("ratcheting" — the gyro equivalent
   of lifting a mouse off the pad). Steam Input and JoyShockMapper both model it this
   way (Always On / Off-While-Held / On-While-Held / Toggle).
2. **The activation channel leaks real keystrokes.** Focus mode is keyed off genuine CG
   modifier flags (`inputSimulator.isHoldingModifiers`), so the activating button must
   emit a real ⌘/⇧/⌥ to the OS. Games see the modifier held: bindings change, shortcuts
   fire. There is no virtual "gyro on/off" action.
3. **Discoverability.** The feature is documented as an accessory of focus mode
   ("Gyro Aiming (Focus Mode)"), so users looking for "gyro to mouse" don't find it.

## Scope

- New per-profile **gyro activation mode**: Focus Modifier (legacy) / Always On /
  Gyro Button. Decouples gyro from focus mode except in the legacy mode.
- Three new **virtual gyro actions** (special-action keycodes, no OS output):
  - **Gyro Toggle** — flips gyro on/off (tap).
  - **Gyro Hold** — gyro active only while held.
  - **Gyro Pause** — gyro suppressed while held (ratchet). Always wins.
- **Scripting API** gyro functions so one button can compose "output Z + toggle gyro".
- UI: activation-mode picker in the Gestures tab; gyro actions in the special-actions
  key picker; input-log entries; activation haptics.
- Migration: existing profiles decode to `focusModifier` mode — zero behavior change.

Out of scope (v1):

- Gyro-control macro steps (macro `.press` steps go straight to `InputSimulator` and
  bypass the engine's special-action intercept — scripts cover the composability ask).
- Relaying gyro-active state to a remote Mac over Universal Control
  (`UniversalControlMouseRelay` continues to relay focus mode only; gyro mouse deltas
  already flow through the normal mouse relay path).
- Flick stick, per-axis yaw/roll config, gyro-to-scroll. Separate requests if they come.

## Design

### 1. Activation model

One pure function decides whether gyro drives the mouse this tick. New file
`Services/Mapping/GyroActivationResolver.swift`:

```swift
enum GyroActivationMode: String, Codable, CaseIterable {
    /// Legacy: gyro active while the focus-mode modifier is held.
    case focusModifier
    /// Gyro active whenever the profile is active and mappings are enabled.
    case alwaysOn
    /// Gyro active only via Gyro Toggle / Gyro Hold actions.
    case gyroButton
}

enum GyroActivationResolver {
    /// - toggledOn: latched state flipped by the Gyro Toggle action.
    ///   Initial value: true for .alwaysOn, false otherwise; reset on profile
    ///   switch / engine reset so a stale "off" can't confuse the user.
    static func isActive(
        mode: GyroActivationMode,
        isFocusActive: Bool,
        toggledOn: Bool,
        holdButtonsDown: Bool,
        pauseButtonsDown: Bool
    ) -> Bool {
        guard !pauseButtonsDown else { return false }   // ratchet always wins
        let base: Bool
        switch mode {
        case .focusModifier: base = isFocusActive || toggledOn  // toggle is additive here
        case .alwaysOn:      base = toggledOn           // starts true; Toggle can park it off
        case .gyroButton:    base = toggledOn           // starts false; Toggle/Hold turn it on
        }
        return base || holdButtonsDown
    }
}
```

Notes:

- In `.alwaysOn`, Gyro Toggle still works (it flips `toggledOn`), so "mostly-on with a
  kill switch" needs no fourth mode.
- In `.focusModifier`, the toggle/hold/pause actions still function (pause in
  particular is useful mid-focus). `toggledOn` starts false there, so Toggle acts as an
  additive on-switch — matching "or anything really" in the request.
- Ratchet (`pauseButtonsDown`) suppresses everything, including holds. That asymmetry
  is the point of ratcheting.

### 2. Engine state & wiring

`MappingEngineState` gains:

```swift
var gyroToggledOn: Bool = false        // re-derived from mode on profile switch/reset
var gyroHoldButtons: Set<ControllerButton> = []
var gyroPauseButtons: Set<ControllerButton> = []
var wasGyroActive: Bool = false        // edge detection for calibration + haptics
```

All three reset in the engine's state-reset path (extend `EngineStateResetTests`).
On profile switch or enable/disable, `gyroToggledOn = (mode == .alwaysOn)`.

`JoystickHandler`:

- `processGyroAiming` swaps its `isFocusActive` parameter for
  `isGyroActive` computed via the resolver each tick.
- Activation-edge work currently living in `updateFocusModeState` (lines ~411–420:
  `prepareForGyroAimingActivation`, filter resets, Steam calibration delay) moves to a
  new `updateGyroActivationState(isGyroActive:)` keyed on `wasGyroActive` transitions,
  so calibration happens on *any* activation edge — focus entry, toggle-on, hold-press,
  pause-release, profile load in always-on. `updateFocusModeState` keeps only its
  focus-specific concerns (indicator, focus haptics, focus exit pause).
- Activation haptic: reuse the existing enter/exit focus haptic pattern on gyro edges,
  gated by `focusModeHapticsEnabled` (no new setting; the footer copy explains it
  covers both). Without some physical confirmation a silent toggle on the mute button
  is guess-and-check.

**Idle bias recalibration (always-on drift).** Today calibration runs only at
activation edges, which is fine when activations are short focus-mode bursts. In
always-on mode the edge fires once per profile load, and gyro bias drifts with
temperature over a session — the cursor would slowly creep. Add an idle
recalibration: when the filtered rates stay below the deadzone continuously for
`Config.gyroIdleRecalibrationWindow` (~2s), re-zero the accumulated bias (Steam: rerun
the bias frames; GCController-path: clear accumulated rates). The controller resting
on a desk is exactly the calibration opportunity. Device pass must include a
resting-drift check after 15+ minutes of always-on use.

`ControllerMotionActivationPolicy` already enables motion whenever
`gyroAimingEnabled` is true, so always-on needs no policy change. Battery note for the
docs: always-on keeps the DualSense IMU streaming whenever the profile is active —
same cost as today's gyro-enabled profiles, since the sensor is already on;
only the *mouse consumption* of the samples changes.

### 3. Virtual gyro actions (special-action keycodes)

Follow the existing `0xF0xx` special-marker pattern (`controllerLock`,
`showLaserPointer`, …) in `KeyCodeMapping`:

```swift
// MARK: - Gyro Control (0xF050 block)
static let gyroToggle: CGKeyCode = 0xF050   // tap: flip gyroToggledOn
static let gyroHold:   CGKeyCode = 0xF051   // held: gyro active while down
static let gyroPause:  CGKeyCode = 0xF052   // held: gyro suppressed while down (ratchet)
```

Why keycodes and not `SystemCommand` cases (the `toggleOuraMotion` precedent):
hold semantics need press *and* release, and system commands are fire-once on press.
Special keycodes already flow through both the press orchestration and release paths.

Execution:

- **Gyro Toggle**: handled in `MappingEngine.handleSpecialActionIntercept` like the
  other intercepts — flip `state.gyroToggledOn`, log
  `InputLog` action "Gyro On"/"Gyro Off", return true. Works from base mappings,
  long-hold, double-tap, chords, and sequences for free (the intercept already covers
  those paths).
- **Gyro Hold / Gyro Pause**: intercepted in the button *press* path before normal key
  execution — insert the button into `gyroHoldButtons`/`gyroPauseButtons`, mark
  `pressConsumedByAction`, emit nothing. On button release, remove from the set. The
  release hook mirrors how held modifiers are cleaned up in the release orchestration.
  If a hold/pause keycode is configured somewhere without a release pair (double-tap,
  sequence step), treat it as a no-op and log a warning — the UI won't offer it there.
- Lock behavior: like other non-lock intercepts, gyro actions are inert while the
  controller is locked. Gyro itself deactivates while locked (resolver isn't consulted;
  the joystick loop is already gated).

Availability: the actions appear for all controllers (profiles roam across
controllers); on gyro-less hardware they simply do nothing, same as gesture mappings.

### 4. Scripting API (composability)

`ScriptEngine` gains gyro functions, following its existing flat-global convention
(`press`, `pressKey`, `hold`, `click`, …):

```javascript
gyroToggle()           // flip latched toggledOn state
gyroSetActive(bool)    // set latched toggledOn state
gyroIsActive()         // resolver output right now
```

In test mode they log instead of mutating, like `press` does. The customer's exact
ask — mute outputs Z *and* toggles gyro — becomes a two-line script bound to mute:

```javascript
pressKey("z");
gyroToggle();
```

This keeps `KeyMapping` single-action (no multi-action schema change), and scripts are
the established escape hatch for composition.

### 5. UI

**Gestures tab** (`GesturesTab.swift`), Gyro Aiming section:

- Toggle renamed "Gyro Aiming" (drop "(Focus Mode)").
- New "Activation" picker, shown when enabled:
  - **Focus modifier (legacy)** — "Gyro aims while the focus-mode modifier is held."
  - **Always on** — "Gyro always moves the cursor. Bind Gyro Pause to a button to
    reposition (ratchet)."
  - **Gyro button** — "Gyro moves the cursor only via Gyro Toggle / Gyro Hold
    bindings."
- Footer gains one sentence pointing at the new bindable actions and that they send no
  keystrokes, plus a hint that the DualSense mute button is a good ratchet button.

**Key picker**: add a "Gyro Control" group next to the existing special actions
(laser pointer, on-screen keyboard, …) exposing Toggle/Hold/Pause with SF Symbols
(`gyroscope`, e.g. badge variants). Hold/Pause hidden in double-tap and sequence-step
contexts (press-only, see §3). Display names via `KeyCodeMapping.displayName`.

**Feedback**: input-log entries for all three actions; activation haptic on edges (§2).
No new on-screen overlay in v1 — the cursor moving *is* the indicator, and the
FocusModeIndicator stays focus-only.

### 6. Settings & migration

`JoystickSettings`:

```swift
/// How gyro aiming activates. Decode default .focusModifier (legacy behavior).
var gyroActivationMode: GyroActivationMode = .focusModifier
```

- Decode with `default: .focusModifier` → every existing profile behaves exactly as
  today. New profiles also default to legacy; the picker is the opt-in.
- No changes to `gyroAimingEnabled` / sensitivity / deadzone.
- Profile import: unknown enum strings decode to `.focusModifier` (use
  `GyroActivationMode(rawValue:) ?? .focusModifier` in the decoder, matching the
  clamped-decode conventions in this file).
- `ProfileImportSafetyAuditor`: gyro keycodes are inert markers, nothing to audit.

## Testing

Unit (no device needed, per testing hierarchy):

- `GyroActivationResolverTests` — truth table over (mode × focus × toggled × hold ×
  pause), especially: pause beats hold; alwaysOn starts toggled-on; toggle-off parks
  alwaysOn off until re-toggled.
- `MappingEngine` tests: press/release of Gyro Hold/Pause mutate the sets and consume
  the press (no keystroke emitted); Gyro Toggle flips state from base mapping and from
  a chord; engine reset clears sets and re-derives `toggledOn` (extend
  `EngineStateResetTests`).
- `JoystickSettings` decode tests: missing field → `.focusModifier`; garbage string →
  `.focusModifier`.
- Calibration-edge test: activation edge calls `prepareForGyroAimingActivation` for
  toggle-on and hold-press paths, not just focus entry (extend
  `SteamGyroAimingPipelineTests` / `ControllerMotionActivationPolicyTests`).

Device verification (kmacstudio, per ControllerKeys testing rule): one DualSense pass —
always-on cursor drift check after calibration, mute-as-ratchet feel, toggle haptic;
one Steam Controller pass for the calibration-delay path.

## Support follow-up

When shipped, reply to ploki: mode = Always On, bind mute → Gyro Pause for ratcheting,
or mute → script (`keyboard.tap("z"); gyro.toggle()`) for the Z+toggle combo.
