# macOS 12 Monterey Compatibility Audit

Status: audit-first. Do not promise Monterey support until this compiles and runs on real macOS 12 hardware or a VM.

## Known Compile Blockers

- App target deployment target is currently `14.6`; `LSMinimumSystemVersion` follows `MACOSX_DEPLOYMENT_TARGET`.
- `MenuBarExtra` and `.menuBarExtraStyle(.window)` require macOS 13+.
- `@Environment(\.openWindow)` and `openWindow(id:)` require macOS 13+.
- `.windowResizability(.contentSize)` requires macOS 13+.
- `Grid` / `GridRow` require macOS 13+.
- Two-argument `.onChange(of:) { old, new in ... }` requires macOS 14+; Monterey needs the older one-argument form.

## Likely Compatible Core Path

- `GCDualSenseGamepad`, DualSense touchpad, `GCController.shouldMonitorBackgroundEvents`, controller haptics/light/battery, `CGEvent` keyboard posting, Accessibility permission flow, JavaScriptCore, CoreBluetooth, AppKit windows, and IOKit HID reads are old enough for the narrow DualSense + Anki shortcut use case.

## Audit Procedure

1. Create a temporary build configuration with `MACOSX_DEPLOYMENT_TARGET = 12.0`.
2. Compile without changing product requirements.
3. Categorize each availability failure as:
   - trivial source compatibility shim,
   - UI shell replacement needed,
   - feature cut needed for Legacy Lite,
   - runtime-only validation risk.
4. If compile scope is reasonable, test on Monterey:
   - launch app,
   - grant Accessibility,
   - connect DualSense over USB and Bluetooth,
   - select/import Anki profile,
   - verify Anki shortcut dispatch.

## Decision Gate

- Full Monterey support: only if UI compatibility changes stay small and no major runtime controller regressions appear.
- Legacy Lite: if the main blocker is the modern SwiftUI shell but core input works.
- No Monterey build: if DualSense/background input is unreliable on macOS 12 or compatibility work threatens the main release.
