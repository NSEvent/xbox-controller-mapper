# ControllerKeys regression audit since 2.12.0

Scope: `v2.12.0..06c719cd`, plus the changes in this audit. No release, version bump, or push. Review focused on event identity, delayed work crossing state changes, incomplete cleanup, configuration preservation, and UI consistency. This is a targeted code and regression-test audit, not proof that every possible hardware interaction is covered.

## Findings addressed

- **Controller selection was tied to primary hardware in secondary surfaces.** Capture/workflow labels, preset review, recommendations, community preview rows, timeline, statistics, and stream overlay now resolve the Buttons selection. HID routing, live hardware settings, and pairing diagnostics still use actual hardware state.
- **Profile changes could restore an old layout.** Once the app binds automatic selection, the current choice carries across manual/automatic profile switches. Saving an older profile draft or restoring mappings from History cannot overwrite it. Standalone unbound profile tools retain their per-profile preview behavior.
- **Automatic navigation could overwrite a failed-load configuration.** Preview changes and automatic profile activation no longer count as user edits that authorize recovery saves. The original bytes and load error remain intact.
- **Some auxiliary buttons still borrowed primary identity.** Wii Remote, Apple TV Remote, Steam Deck, and Beamdesk gamepad button paths explicitly identify their source. A fresh source-tagged press also updates selection when another device is holding the same shared button; repeated reports from that source do not. Auxiliary Wii/Apple TV connection announcements select their layout even when another controller owns the hardware routing slot.
- **Filtered list offsets are not persistent list offsets.** Compatible-first grouping uses all-button containment, stable partitions, and ID-based reordering within original slots. Invalid/stale drags and events from an old profile are rejected. Editing/deleting still targets mapping IDs.
- **Other editors shared the command-wheel's stale-profile risk.** Button, chord, sequence, and Add/Edit Layer sheets now bind to the opening profile, disable and dismiss on a profile change, and guard save/clear actions. Controller selection alone does not invalidate the draft.
- **Quick-text restoration still lost non-text formats.** Snapshot every clipboard item/type, preserve overlapping-paste ownership, restore an empty clipboard, and leave a newer user copy alone. Tests use a private pasteboard, never Kevin's clipboard.
- **Script callbacks retained state but read a newer trigger.** Both state and trigger are invocation-local. State clearing advances a callback generation; old callbacks cannot press keys or recreate old state. JSValue inspection now happens on the script queue.
- **Stopping mic startup did not reject queued meter samples.** Meter updates carry the monitor generation and old samples are ignored after stop/restart.

## Regression coverage

| Area reviewed | Coverage |
| --- | --- |
| Controller labels, button availability, profile/manual selection | `MappingControllerPresentationTests`, `ControllerPreviewBindingTests`, `LayerActivatorPickerTests`, `DeviceMappingButtonGridTests` |
| Input source and latest-device ordering | `ControllerPreviewAutoFollowTests`, `MultiDevicePreviewActivityTests`, `ControllerSourceAuditTests` |
| Stable compatibility groups, shared buttons, mixed-device triggers, persistence, stale drags | `ControllerMappingGroupsTests` |
| Actual chord/sequence tabs and live regrouping | `ControllerMappingGroupingRenderingTests` (light/dark, offscreen rendering and text order) |
| Draft ownership, swap capture, runtime layer display | `ControllerSourceAuditTests`, `CommandWheelEditorProfileTests`, `ButtonSwapSelectionTests`, `RuntimeLayerSelectionTests` |
| Failed config load, initial save, backup bursts | `ProfileConfigLoadFailureTests`, `ConfigBackupServiceTests`, configuration save/load suites |
| Local/peer held output, chords and disconnect cleanup | `HeldOutputRoutesTests`, `UniversalControlHandoffReleaseTests`, `OverlayReleaseCleanupTests` |
| Steam takeover/wake and auxiliary Wii precedence | Controller callback/Steam suites, `WiimoteDisplayPrecedenceTests` |
| Touchpad mode changes, momentum, repeated lift reports, pinch | `TouchpadClickModeSwitchTests`, `TouchpadMomentumInterruptTests`, `TwoFingerTapRefireTests`, touchpad gesture suites |
| Oura overlap and MIDI hold/double-tap | `OuraRingInputTests`, `MIDIHoldDoubleTapTests`, `DoubleTapAndLongHoldTests` |
| Overlay re-show, hidden keyboard, hover controls | `OverlayFadeReshowTests`, `TypingBufferTests`, `MappingQuickActionLayoutTests` |
| Overlapping paste and multi-format restoration | `ClipboardRestoreSessionTests`, existing TriggerKit pasteboard tests |
| Script state, callbacks, watchdog | `ScriptStateProfileRepublishTests`, `ScriptAsyncCallbackTests`, `ScriptRunawayTerminationTests` |
| Microphone cancellation, telemetry opt-out, license persistence | `MicLevelMonitorStopTests`, `TelemetryServiceTests`, `LicenseManagerTests` (mock transport/store) |

## Boundaries

- Tests run only on Mac Studio. Rendering tests create offscreen windows and close them; mapping tests use simulated output. No live license requests, telemetry sends, purchases, or releases are needed for the new tests.
- Existing routing exclusions are preserved: for example, a Steam Deck session rejected while Xiaomi is connected does not become the selected controller.
- Physical device presses and a real 2-Mac handoff still require hardware verification; fixtures exercise the production routing and lifecycle paths without claiming those physical checks.
- The existing representation identifies controls by shared `ControllerButton` values. Compatibility means the selected controller can express every stored control, not that the mapping was originally authored for that model. Dedicated pedal keys remain distinct; D-pad-only mappings can be compatible with several devices.
- Mixed button/chord sequences are a design proposal in `chord-sequences-design.md`, not a released/runtime feature. Extend Sequences rather than adding a parallel tab, and preserve existing sequence timing during migration.

## Verification result — 2026-11-08

- Mac Studio `make test-full`: 2,687 native tests, 35 skipped, 0 failures; 15 Python tests, 3 skipped, 0 failures.
- Mac Studio `swift test --package-path TriggerKit`: 119 XCTest cases across runtime, library, and core, 0 failures.
- Added 26 native regression tests. Inspected rendered light/dark chord and sequence sections, live regrouping, and the Hands overlay.
- Built and installed with `make install BUILD_FROM_SOURCE=1`; verified the installed signature and running `/Applications/ControllerKeys.app` process.
- Test logs and inspected screenshots: `~/Downloads/controllerkeys-release-audit/`. Physical pedal/controller presses and real peer handoff were not performed by this audit.
