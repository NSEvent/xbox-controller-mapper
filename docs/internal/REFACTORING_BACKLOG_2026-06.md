# Refactoring Backlog — June 2026

**Date:** 2026-06-10
**Status:** Tier 1 + 2 landed; this doc tracks the deferred Tier 3 items.

Ranking method: git churn (commits/6 weeks) × file complexity. The hot files were
`ControllerService` (33 commits, 2.7k lines + 7.9k in extensions), `ControllerVisualView`
(32, 3.5k), `UniversalControlMouseRelay` (32, 3.4k), `MappingEngine` (31, 1.8k),
`SettingsViews` (28, 1.6k).

## Already done (June 2026)

- Split `ControllerVisualView.swift`: body shapes + `BatteryView` → `ControllerBodyShapes.swift`,
  `ControllerAnalogOverlay` → own file, Apple TV remote builders → `ControllerVisualView+AppleTVRemote.swift`.
- Trimmed `UniversalControlMouseRelay.swift`: pairing-code UI → `UniversalControlPairingUI.swift`,
  pure policy/encoding types → `UniversalControlRelayPolicies.swift`.
- `MappingEngine` timer machinery → `MappingEngine+Timers.swift`.
- `ControllerService` 15Hz display timer → `+DisplayUpdates.swift`, battery polling/LED
  animation → `+Battery.swift`.
- `LEDSettingsView` + `LightBarColorPicker` → `LEDSettingsView.swift`.

## Tier 3 — deferred, do when the area is next touched

### 1. Data-driven controller layouts (do alongside the next new controller type)

`ControllerVisualView` + `ControllerAnalogOverlay` contain ~56 per-controller-type branches
(`isXboxElite` / `isDualSense` / `isSteamController` / `isAppleTVRemote` / ...) and four
near-duplicate mini-overlay builders (`xboxOverlay`, `steamOverlay`, `nintendoOverlay`,
`dualSenseOverlay`) with hardcoded positions/spacing.

Plan: introduce a per-controller `LayoutMetrics` value type (preview size, button positions,
touchpad geometry) and collapse the overlay builders into one data-driven builder. Also unify
`miniTouchpad()` vs `miniSteamTouchpad()` (shared quadrant divider/highlight/tap-zone code) and
`compactActionTile()` vs `referenceRow()` (near-identical context menu + layer indicator logic).

- Payoff: adding a controller type becomes mostly a data entry, not view surgery.
- Risk: visual regressions; there are no snapshot tests. Do it as its own session with
  side-by-side screenshots per controller type.
- Effort: ~3-5 hours.

### 2. HID driver protocol (do when adding the next HID controller)

~80% of the IOHIDManager setup (Create → SetDeviceMatching → RegisterCallback → Open, plus
teardown) is duplicated across `+SteamHID.swift`, `+GenericHID.swift`, `+AppleTVRemoteHID.swift`,
`+PlayStationHID.swift` (~150-200 lines). Callback wiring to `handleButton` / `updateLeftStick`
etc. repeats per extension. Apple TV additionally has three separate button-routing paths
(HID buttons, system events, touchpad events) where Steam/Generic centralize.

Plan: a `HIDControllerDriver` protocol (device matching, lifecycle, callback surface) + a setup
helper for the manager boilerplate. ControllerService talks to drivers through the protocol.

- Payoff: one place to debug HID lifecycle; drivers swappable for tests.
- Risk: medium — touches 4-5 working device integrations at once; needs hardware re-testing
  per controller. Don't do it speculatively.
- Effort: ~10-14 hours.

### 3. UniversalControlMouseRelay decomposition (only if bugs cluster here)

The relay is a 3.1k-line `@unchecked Sendable` god class: ~45 stored properties behind one
`NSLock`, mixing pairing/auth state machine, TCP transport + framing, remote input dispatch
(60+ command types), cursor/handoff session state, and config caching.

The June 2026 pass deliberately stopped at the mechanical extractions. Peer discovery
(`discoverRelayPingTargets` and friends, ~250 lines) was evaluated and **skipped**: moving it to
an extension file would have required making `lock`, `queue`, `subprocessQueue`, `pairingBrowser`
and ~7 more members internal — exposing the concurrency primitives module-wide isn't worth the
line count. The right shape is a standalone `RelayPeerDiscovery` type with config-in/callback-out
(zones, default host/port, tailscale path in; targets out), which removes the need to share any
relay state.

Candidate seams, in order: (a) `RelayPeerDiscovery` as above; (b) pairing/auth state machine
(its state is 5 properties, mostly self-contained); (c) remote-input command dispatch table.
The cursor/handoff session core should be split last, if ever — it's the part under active
feature development.

- Risk: high while the feature is still evolving; revisit when it stabilizes.
- Effort: ~1-2 days for (a)+(b).

## Evaluated and rejected — do not bother

- **The 21 `threadSafe*` accessors on ControllerService** — intentional pattern, already
  optimized via `snapshot()` for hot paths. Boilerplate-y but correct; a macro/protocol would
  add indirection for no behavior win.
- **`Config.swift` churn** — it's a tuning-constants file; high commit count is healthy
  (gyro sensitivities, timing windows), not a smell.
- **Unifying per-extension HID callback wiring on its own** — saves ~8 lines per extension;
  only worth it as part of item 2.
- **`updateSettings` triplication in SettingsViews** — looks like duplication but each copy
  mutates a different model type (JoystickSettings / LED settings); merging would need
  generics over key paths for ~20 lines saved.
- **Splitting `SettingsSheet`** — 75% of it is integration glue bound to its own @State;
  no clean seam.
