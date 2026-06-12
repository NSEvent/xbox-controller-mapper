# TriggerKit

Shared macOS automation package for Kevin's apps.

TriggerKit separates **triggers** from **actions**:

- Tardy supplies time-based triggers.
- Plaque supplies Bluetooth connect/disconnect triggers.
- ControllerKeys supplies controller-button triggers.

The shared primitive is `AutomationProgram`: an ordered list of trigger-independent steps such as keyboard input, mouse input, text entry, delays, app launches, URLs, and shell commands. Reusable macros are named `AutomationProgram` values stored once per user and referenced by trigger apps.

## Products

- `TriggerKitCore` - Codable action schema.
- `TriggerKitLibrary` - shared per-user macro store.
- `TriggerKitRuntime` - macOS executor for keyboard, mouse, text, app, URL, delay, and shell steps.
- `TriggerKitUI` - reusable SwiftUI surfaces for displaying/editing programs and macros.

## Current Status

Initial package slice:

- versioned `AutomationProgram` schema
- side-aware modifier model
- keyboard and mouse step models, including modified key/mouse gestures such as `Cmd+Left click`
- text, delay, app, URL, and shell step models
- webhook steps (native URLSession execution) and host-app `custom` steps
- paced typing (`charactersPerMinute`) and run-in-Terminal shell commands
- host `stepOverride` hook, `.concurrent` execution policy, and URL-scheme allowlist
- macOS runtime executor
- shared macro library at `~/Library/Application Support/TriggerKit/macros.json`
- reusable macro manager UI
- basic program summary UI
- schema/model/catalog tests
- macro model/store tests
- runtime executor and input-event mapping tests

## Macro Library

Consumer apps should store a macro UUID plus a snapshot `AutomationProgram`.
At runtime:

- If the macro exists in `AutomationMacroStore.shared`, run the live macro.
- If the live macro exists but has no steps, do nothing.
- If the macro was deleted, run the last stored snapshot.

The standalone TriggerKit.app in `~/projects/triggerkit-mac-app` manages the same
library and can test-run macros from the app process.

## Verify

```sh
swift test
```
