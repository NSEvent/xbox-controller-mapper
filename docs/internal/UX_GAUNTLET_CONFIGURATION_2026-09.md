# Configuration UX Gauntlet — 2026-09

## Problem

ControllerKeys' controller canvas is a strong spatial editor, but not a strong audit surface. A new user has to infer that the controller labels are clickable; an advanced user cannot quickly answer “what will this profile/layer do?” without scanning a large two-dimensional diagram and then visiting several separate tabs.

The interface needs two complementary representations of the same configuration:

1. **Overview** — compact, searchable, complete, source-aware.
2. **Visual editor** — controller-shaped, direct, tactile.

Neither replaces the other.

## Baseline evidence

- `screenshots/xbox-series-xs/01-buttons.png`: 34 mappings spread around a 3200×2000 controller canvas; attractive, but expensive to scan and compare.
- `screenshots/xbox-series-xs/02-chords.png`: chords become legible only after leaving the controller canvas.
- `screenshots/xbox-series-xs/04-macros.png`: automations are defined separately from the buttons that invoke them.
- `ProfileListRow` reports only `buttonMappings.count` as “mappings,” excluding layers, chords, sequences, and gestures.
- The command palette can jump to individual buttons, but is transient and cannot answer completeness or layer-fallthrough questions.

### Baseline rubric

| Category | Score | Main failure |
|---|---:|---|
| First-action clarity | 6/10 | Onboarding proves input, then lands on a dense canvas without a persistent next-step cue. |
| Configuration scanability | 4/10 | Spatial labels require a large viewport and serial visual search. |
| Layer comprehension | 5/10 | Selected layer is visible, but inherited versus overridden configuration is only encoded by dimming. |
| Advanced findability | 7/10 | Grouped tabs and ⌘K help, but configuration is fragmented across surfaces. |
| Information hierarchy | 6/10 | Profile, navigation, layer, overlays, timeline, and canvas all compete above the core bindings. |
| Accessibility and keyboard use | 7/10 | Existing labels and shortcuts are good; the canvas remains less list/VoiceOver-friendly than a row model. |

## Shipped references

- Apple HIG: use disclosure to keep common actions visible while hiding advanced detail until relevant; use split views when hierarchy exceeds two levels.
- Steam Input: action sets/layers are incremental overlays; the UI must make inheritance and override order explicit.
- Stream Deck: preserve a physical-device canvas while giving profiles/pages a named, navigable structure.

## Iteration 1 — Configuration Overview

Add **Overview** as the first Map destination and surface it once after introduction; keep Buttons as the regular return destination. It is the profile's readable table of contents, not another settings screen.

### Acceptance gates

| Gate | Pass condition |
|---|---|
| Orientation | Active profile and selected scope (`Base` or named layer) are obvious without reading the sidebar. |
| First action | A prominent “Open visual editor” action explains that users configure by choosing a controller control. |
| Completeness | Every non-empty base button mapping appears. A selected layer shows its effective mappings and marks each row `Override` or `Inherited`. |
| Layer semantics | Layer activator, activation style, and override count are visible before the rows. |
| Advanced triggers | Chords, sequences, and gestures appear in the same overview with direct edit affordances. |
| Automation inventory | Macro and script definitions are summarized and route to their management tabs. |
| Search | One field filters controls, action text, hints, trigger type, automation names, and source labels. |
| Empty state | A blank result never becomes an unexplained empty screen; clear-search or configure actions remain visible. |
| Existing workflows | Visual Buttons, Chords, Sequences, Gestures, Macros, and Scripts surfaces remain available and unchanged. |
| Accessibility | Rows expose combined trigger/action labels; no required action is hover-only; controls have labels/help. |
| Regression safety | Pure snapshot/filter behavior has unit tests; full project gate passes on `kmacstudio`. |

## Iteration 2 — Inventory truth and deletion safety

- Replace the sidebar's base-dictionary count with controls, advanced triggers, layers, overrides, and automation counts.
- Show macro/script usage or `Unused` directly in Overview.
- Confirm macro/script deletion with the number of affected binding locations.
- Clear references across base buttons, hold/double-tap actions, layers, chords, sequences, gestures, command wheels, nested macro steps, and legacy touchpad regions.
- Preserve unrelated alternate actions when one referenced automation is deleted.

## Iteration 3 — Hostile review rejection

Three independent first-time, advanced, and architecture critics rejected the first candidate. The defects were semantic, not polish:

- Runtime layer activation silently changed the user's edit scope.
- Hold-only and double-tap-only controls appeared as `None`.
- Controller availability used scattered family booleans, misclassifying saved controls and advanced triggers.
- Layer wheel/stick/LED rows sometimes opened Base editors.
- The automation count and shown inventory described different scopes.
- The overview omitted profile-level configuration families.
- Automation deletion could awaken a dormant lower-priority action in malformed-but-decodable data.

## Iteration 4 — Scope, capability, and action truth

- Editing scope is now an explicit user choice. Runtime state is a separate status chip with an opt-in **Edit Active Layer** action.
- The effective runtime layer includes app-activated layers; the manual-layer property remains available for other presentation needs.
- `ControllerVisualDescriptor.supportedButtons` is the shared capability truth for the canvas and overview. Unsupported saved controls/settings move into a named disclosure for the current device.
- Action summaries follow the executor's real priority order: system command → macro → script → MIDI → key.
- Alternate-only mappings receive explicit summaries instead of `None`.
- Every overview target captures its layer/profile scope. Wheels, sticks, LEDs, linked apps, and linked controllers open their canonical scoped editors.
- Profile inventory now includes D-pad preset, controller preview, latency, keyboard ownership/content, automatic switching, touchpad mode/migration data, stick tuning, and LEDs.
- Automation inventory is profile-scoped: profile macros/scripts plus referenced shared snapshots. Live shared items show live content; unavailable items remain inspectable as read-only saved copies.
- Deletion cleanup applies executor precedence across primary/alternate mappings, layers, triggers, wheels, macro steps, and legacy touchpad regions. Removing an effective reference clears lower dormant actions; removing a dormant reference preserves the effective action.
- All new Overview copy and dynamic setting values have German, Japanese, Simplified Chinese, and Traditional Chinese coverage with placeholder-parity tests.

## Iteration 5 — Runtime-equivalent audit truth

- Chord and sequence availability now uses the selected layer's effective stick modes, matching the runtime input pipeline in both directions.
- Duplicate imported layer activators use the runtime's last-wins index instead of first-wins lookup; shadowed activators remain visible with an explicit conflict explanation.
- Apple TV Remote always audits its clickpad as whole-pad input, exposes no analog triggers, and keeps saved trigger tuning visible only as unavailable legacy configuration.
- 8BitDo Micro Star remains decorative/unavailable because empirical D-input capture sees no event; stickless 8BitDo models no longer claim active stick settings.
- LED editors preview only the active profile's runtime-effective scope and restore runtime feedback on dismissal, so inspecting Base or an inactive layer cannot hijack the physical controller.
- Stick rows deep-link to the exact left/right and Base/layer editor anchor. Automatic layer activation remains discoverable before any apps are linked.
- Inert macro/script IDs embedded in legacy macro keystroke steps no longer inflate destructive-action dependency warnings.
- Overview settings and capability regressions were split into focused files below the repository's size ceiling.

## Iteration 6 — LED and destructive-state truth

- Layer LED inspection can no longer overwrite Base, another runtime layer, Party Mode, or the controller-lock red indicator. Only the active runtime scope previews on hardware; closing restores the effective runtime settings.
- Scoped layer LED sheets no longer expose the global Party Mode switch. Turning Party Mode off in the Base editor restores the runtime-effective layer instead of whichever settings happened to be open.
- The compact layer editor names the full **Layer LED Override** operation, warns before its removal, preserves an untouched override exactly, and disables battery-follow mode only after an intentional custom-color edit.
- DualShock 4 and Bluetooth brightness now follow the runtime's RGB-scaling behavior. Only player/mute LEDs are described as unavailable.
- LED capability follows the edited profile's preview controller. Active Bluetooth transport limits only an `Active Controller` preview, never an explicit DualSense preview for a different saved configuration.
- Direct stick navigation is consumed once, preventing later generic Joystick visits from jumping to a stale anchor.
- The 8BitDo Micro Star remains visible as hardware decoration but is not offered as a mapping target because verified D-input captures emit no event.

### Regression matrix

- Base versus selected-layer inheritance and routing
- Runtime app layer versus manual edit scope
- Hold-only and double-tap-only mappings
- Conflicted action precedence
- Exact 8BitDo Zero 2 control capability
- Explicit-versus-active controller preview LED capability
- Locked, inactive-scope, Party Mode, and no-op layer LED safety
- Unsupported chord/sequence/gesture classification
- Layer wheel/stick/LED destinations
- Complete profile-settings families
- Profile-owned, live shared, and orphaned shared automation inventory
- Destructive macro/script cleanup on every executable shape
- One-time introduction and sheet-contention policy
- Four-locale key and format-placeholder parity

Runtime screenshot automation was unavailable in this environment, so visual evidence remains the checked-in baseline screenshots plus build/test verification. No running ControllerKeys process was quit or replaced during the loop.

### Target scores

- Every category: **≥8/10**
- Overview hero/readability: **≥9/10**
- No P0/P1 findings from an independent fresh-context critic

### Final gate

- Local Release build: **PASS**
- Mac Studio full suite: **2,129 tests executed, 37 skipped, 0 failures**
- First-time hostile review: **PASS**, no P0/P1; hero/readability **9/10**
- Advanced hostile review: **PASS**, no P0/P1; overall source audit **8.3/10**
- Architecture hostile review: **PASS**, no P0/P1; correctness **9.1/10**, state ownership **9.0/10**
- Static gates: `git diff --check` and all four localization plist checks **PASS**
- Remaining caveat: runtime screenshot automation was unavailable; rendered polish is provisional until a safe visual session can run without replacing the user's active app.

## Later iterations

1. Persistent cheat sheet derived from the same snapshot model.
2. Progressive disclosure inside mapping sheets: common action first; hold/double-tap/repeat/haptics under one Advanced section.
3. Cross-profile comparison, sorting, and conflict detection for large libraries.
