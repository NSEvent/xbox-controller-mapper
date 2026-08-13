# ControllerKeys feedback delivery plan—2026-08

Sources: six emails titled “ControllerKeys feedback,” received 2026-07-25 through 2026-08-07, plus the Steam Controller receiver review.

## Triage

| Priority | Item | Status |
| --- | --- | --- |
| P1 | Mapping text becomes black and unreadable in macOS Light appearance | Planned hotfix |
| P1 | Steam wireless disconnect leaves ControllerKeys connected and can leave outputs held | Fixed in the receiver follow-up |
| P2 | Controller Support Dump collapses composite receiver interfaces | Fixed in the receiver follow-up |
| P2 | Swap a stick's X and Y axes for sideways controllers | Planned |
| P2 | Activate, deactivate, or toggle layers from macros and JavaScript | Planned |
| P2 | Run a separate action when a controller button is released | Planned |
| P3 | Persistent profile/layer keybind cheat sheet | Planned |
| Closed | Independent natural/reversed scrolling per stick axis | Shipped in 2.6.3 |
| Closed | Toggle-style layers | Shipped in 2.6.3 |

## Completed review fixes

### Steam wireless lifecycle

- Parse Triton/Nereid wireless-status reports `0x46` and `0x79` (`1` = disconnected, `2` = connected).
- Treat the first state report as an implicit reconnect, matching Valve/SDL behavior.
- Correlate receiver interfaces by physical identity, so status on one composite interface can disconnect the interface carrying controller state.
- Drain earlier controller callbacks, clear cached physical input, then emit a typed `controllerDisconnected` event on `MappingEngine.inputQueue`.
- Release held keys, modifiers, mouse buttons, MIDI, stick directions, and pending mapping state without executing cancelled actions.
- Cancel a stale UI disconnect if the same wireless receiver reconnects before the main-thread transition completes.
- Allow a newly enumerated interface to replace an active interface that IOHID already removed.

### Support Dump identity

- Include interface number, primary usage page/usage, and IORegistry entry ID in candidate identity.
- Keep distinct composite receiver interfaces instead of deduplicating them by product/location alone.
- Show the interface or usage in the candidate label and JSON.

### Verification

- Mac Studio `make refactor-gate`: 2,019 tests, 37 skipped, 0 failures.
- Regressions cover wireless report parsing, physical receiver matching, input-queue routing, and held-output cleanup.

## Delivery order

Keep these as separate, reviewable changes. Each slice gets profile migration tests and the full Mac Studio gate.

1. P1 main-window contrast hotfix.
2. Stick X/Y axis swap.
3. Shared programmatic layer command path, then macro and script adapters.
4. Release-edge actions.
5. Persistent keybind cheat-sheet overlay.

## 1. P1: Light-appearance contrast

### Root cause

`ContentView` always draws a dark HUD/glass background, but its semantic colors such as `.primary` still follow the system appearance. In Light appearance, `.primary` resolves to black; low window opacity therefore produces black mapping text over dark glass.

### Implementation

- Apply `.preferredColorScheme(.dark)` to the main `ContentView` scene in `XboxControllerMapperApp.swift`.
- Keep the policy scoped to the ControllerKeys editor and its sheets. Do not force the menu-bar extra or standalone Connection Guides window until each surface is visually checked.
- Keep `WindowBackgroundDefaults.opacityKey` behavior unchanged; this is a foreground-color policy, not an opacity workaround.
- Add a small `MainWindowAppearancePolicy` seam only if needed for a direct unit assertion. Avoid a generalized theme system for this hotfix.

### Regression gate

- Launch the deterministic screenshot variant in app-scoped Light and Dark appearances.
- Capture the Buttons tab at background opacity `0.0`, `0.6`, and `1.0`.
- Check base mappings, layer mappings, secondary labels, disabled controls, sheets, banners, and tooltips.
- Acceptance: the main editor uses light text in both system appearances; no semantic mapping label becomes black; other app scenes retain their existing appearance.

Primary files: `XboxControllerMapperApp.swift`, `ContentView.swift`, screenshot capture scripts/tests.

## 2. Stick X/Y axis swap

### Data model

- Add `swapAxes: Bool` to `StickTuning`, defaulting to `false` when absent.
- Add `swapAxes: Bool?` to `StickTuningOverride`; `nil` continues to mean “inherit profile value.”
- Preserve existing downgrade fields. Older builds ignore the new nested key; current builds decode old profiles without behavior changes.

### Input semantics

- Add a pure `JoystickMath.orientedStick(_:swapAxes:)` transform.
- Swap physical axes first: `(x, y) -> (y, x)`. Apply existing mode-specific X/Y inversion after the swap, so “Invert Y” continues to describe the resulting on-screen Y axis.
- Resolve effective per-layer stick tuning early enough that the transformed point feeds every downstream consumer: mouse, scroll, WASD/arrows, custom directions, D-pad mode, swipe typing, Directory Navigator, and Command Wheel.
- Keep the raw `ControllerService` snapshot unchanged. Axis swap is profile/layer behavior, not a device-global HID rewrite.

### UI

- Add “Swap X and Y Axes” to each stick's tuning controls in `SettingsViews.swift`.
- Add the matching tri-state layer override: Inherit / On / Off, following the existing per-layer override pattern.
- Explain the 8BitDo Micro use case in help text: useful when a controller is held or mounted sideways.

### Tests

- Codable defaults and round-trip for base and override settings.
- Four cardinal directions plus diagonals through `JoystickMath`.
- Swap combined with mouse-Y, scroll-X, and scroll-Y inversion.
- Each strategy family, especially `.dpad` for a sideways 8BitDo Micro.
- Active-layer override on/off/inherit and profile switching.
- Directory Navigator and Command Wheel consume the oriented point rather than the raw point.

Primary files: `StickTuning.swift`, `JoystickSettings.swift`, `JoystickHandler.swift`, `JoystickMath.swift`, `SettingsViews.swift`, `LayerStickModeOverrideTests.swift`, joystick strategy/math tests.

## 3. Layer commands for macros and JavaScript

### Shared command path

- Introduce `LayerCommandOperation`: `activate`, `deactivate`, `toggle`.
- Introduce a `LayerCommandRouter` owned by `MappingEngine`. Script and macro runtimes submit commands to the router; the router serializes mutations on `inputQueue`.
- Programmatic activation writes `EngineState.latchedLayerId`. App-activated layers remain lower priority; physically held layers remain higher priority.
- Reuse the routing-boundary cleanup used by app/toggle layer transitions. Preserve an unchanged held mapping, stop changed held outputs, consume cancelled physical releases, then refresh LED and published layer presentation.
- Missing/deleted layer IDs and ambiguous script names log a no-op instead of selecting an arbitrary layer.

### Macro surface

- Add `MacroStep.layerCommand(layerId: UUID, layerName: String, operation: LayerCommandOperation)` with exhaustive Codable handling.
- Add a Layer step editor in `MacroEditorSheet`: operation picker plus a layer picker from the active profile.
- Convert the step to a namespaced TriggerKit custom step in `MacroAutomationBridge`; execute that namespace through `MacroExecutor` and the shared router.
- Update reverse conversion, display strings, shared-macro snapshots, import-safety visitor switches, and all exhaustive `MacroStep` tests.

### Script surface

- Add `activateLayer(nameOrId)`, `deactivateLayer(nameOrId)`, and `toggleLayer(nameOrId)` to `ScriptEngine`.
- UUID lookup wins. Name lookup requires one exact match; duplicate names return/log an ambiguity error.
- Test mode records the intended command but does not mutate live layer state.
- Add examples and API documentation in the script editor/gallery.

### Tests and acceptance

- Activate/deactivate/toggle from both a macro and JavaScript.
- App layer + programmatic layer + held layer priority.
- Changed held mappings release; identical held mappings remain held.
- Profile switch clears programmatic layer state and a queued old-profile command cannot activate a same-ID layer later.
- Deleted layer, duplicate name, locked/disabled engine, and rapid command sequences.
- Imported/older macros decode unchanged.
- Acceptance: a user can run a macro or script that deterministically turns a named layer on, off, or toggles it; the UI selection, effective mappings, LED, and overlay state agree.

Primary files: `MappingEngine.swift`, `MappingEngineState.swift`, new `LayerCommandRouter.swift`, `Macro.swift`, `MacroAutomationBridge.swift`, `MacroExecutor.swift`, `MacroEditorSheet.swift`, `ScriptEngine.swift`, `ScriptExamplesData.swift`, `ProfileSurfaceVisitor.swift`.

## 4. Separate release action

### Data model

- Add `ReleaseMapping`, a non-recursive `ExecutableAction` sibling of `LongHoldMapping` and `DoubleTapMapping`.
- Add `releaseMapping: ReleaseMapping?` to `KeyMapping`, defaulting to `nil` for existing profiles.
- Support key/modifier, macro, script, system command, MIDI CC, hint, and haptic fields. Do not put long-hold, double-tap, repeat, or another release action inside it.
- Extend `KeyMapping.accept`, macro/script deletion cleanup, macro reference collection, import safety, community-profile rendering, compact labels, copy/paste, and conflict validation.

### Runtime semantics

- Snapshot an `ArmedReleaseAction` against the resolved physical-button press. Do not look up the current profile/layer mapping again on key-up.
- Arm only after a single-button mapping actually resolves. A consumed chord, layer activator, controller lock, or UI intercept does not arm the base button's release action.
- On physical release, stop the primary held output first, then execute the release mapping exactly once with `PressType.release`.
- A long-hold or double-tap alternate does not suppress the already armed release action; it still represents the same physical release edge.
- Controller disconnect, profile switch, app/layer routing transition, engine disable/lock, or shutdown disarms without executing. Cleanup must never turn an unsafe boundary into an action trigger.
- Add `InputEventType.release` and map it to the already existing `PressType.release` script trigger.
- Realtime mode is the exact “C on press, C on release” path. Standard mode may defer the primary action until release for chord/double-tap resolution; the release action still fires on the release edge, and the UI should explain this timing distinction.

### UI

- Add an optional “On Release” section beside Long Hold and Double Tap in `ButtonMappingSheet` using `MappingEditorState` and `ActionMappingEditor`.
- Show a release badge/row in `MappingLabelView`, controller compact badges, community previews, and cheat-sheet output.
- Disable or explain combinations whose primary action is an overlay/layer special intercept and therefore has no ordinary release-action lifecycle.

### Tests

- Realtime `C` key-down/up plus release-mapped `C` produces two complete `C` actions in order.
- Held modifier or mouse button is released before the release action runs.
- Standard/realtime modes, chord winner/loser, long hold, double tap, repeat, and rapid re-press.
- Script receives `trigger.pressType === "release"` and hold duration if exposed.
- Macro, system command, MIDI, and haptic release actions.
- Disconnect/profile/layer/disable/shutdown never execute the release mapping.
- Codable migration and every profile-surface visitor.

Primary files: `KeyMapping.swift`, `MappingEngine.swift`, `MappingEngineState.swift`, `ButtonInteractionFlowPolicy.swift`, `MappingActionExecutor.swift`, `InputLog.swift`, `ButtonMappingSheet.swift`, `MappingLabelView.swift`, `ProfileSurfaceVisitor.swift`, profile cleanup visitors/tests.

## 5. Persistent profile/layer cheat sheet

### Product scope: first release

- A separate nonactivating floating panel, not an action-history overlay.
- Global visibility and per-display frame persist across app launches and while the main editor is closed.
- Content is derived automatically from the active profile and effective layer. Users do not maintain a second copy of mapping text.
- Header: profile name plus Base or effective layer name. Body: mapped controller control, primary hint/action, then Long Hold / Double Tap / On Release variants.
- Layer rows show the effective mapping after layer fallthrough, not only the layer's sparse overrides.

### Architecture

- Add a pure `CheatSheetSnapshotBuilder` that resolves effective mappings, macro/script display names, controller-specific ordering, and empty-row filtering.
- Publish an `activeEffectiveLayerId` (or immutable layer-presentation snapshot) from `MappingEngine`; keep `activeManualLayerId` unchanged because the editor intentionally excludes app-activated layers.
- Add `CheatSheetOverlayManager` and `CheatSheetOverlayView`. Reuse/extract panel frame persistence from `StreamOverlayManager`, but keep the two panels' content and preferences independent.
- Own startup/visibility from `ServiceContainer` or app lifecycle, not `ContentView.onChange`, so “persistent” works when the main window is closed.
- Panel behavior: nonactivating, movable, resizable with a minimum size, joins all spaces/full-screen auxiliary, optional click-through, close button on hover, saved frame per display.
- Add a toolbar/layer-bar toggle and menu-bar toggle using one `@AppStorage` key.

### Tests and acceptance

- Base mapping and sparse layer fallthrough.
- Manual, app-activated, and programmatic layer changes update the snapshot atomically.
- Profile switch, mapping edit, macro/script rename/delete, and controller-layout change.
- Stable controller-specific row ordering; unmapped controls omitted.
- Frame/visibility persistence and no duplicate panel on repeated show calls.
- Manual visual checks across spaces, full-screen apps, multiple displays, main-window closure, and relaunch.
- Acceptance: the panel remains visible until explicitly closed and always describes the mappings ControllerKeys would execute in the current profile/layer context.

Primary files: new `CheatSheetSnapshotBuilder.swift`, `CheatSheetOverlayManager.swift`, `CheatSheetOverlayView.swift`; `MappingEngine.swift`, `ServiceContainer`, `LayerTabBar.swift`, `MenuBarView.swift`; shared mapping-display resolver extracted from `MappingLabelView` as needed.

## Release discipline

- One commit/PR per numbered slice; do not combine data-model-heavy release actions with the overlay.
- Add a changelog entry and backward-compatibility fixture for every persisted-model change.
- Run `make refactor-gate` only on `kmacstudio` before each handoff.
- Hardware closeout: Steam receiver power-cycle for the reviewed fix; sideways 8BitDo Micro for axis swap; real controller timing for release actions; multiple spaces/displays for the cheat sheet.
