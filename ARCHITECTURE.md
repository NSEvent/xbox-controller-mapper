# ControllerKeys Architecture

Technical reference for developers and AI agents working on this codebase.

---

## Controller Input Pipeline

The app supports three controller types through different input backends, all normalizing to the same `ControllerButton` enum and callback interface:

| Controller Type | Backend | Detection |
|----------------|---------|-----------|
| Xbox (One/Series/360) | GameController framework | Automatic via `GCController` |
| DualSense (PS5) | GameController framework + IOKit HID (for mic/LEDs/touchpad) | Automatic via `GCController` |
| Third-party (8BitDo, Logitech, etc.) | IOKit HID + SDL gamecontrollerdb | 1-second fallback if GameController doesn't claim |

All controller types feed into the same `MappingEngine` which handles button→action mapping, chords, long hold, double tap, macros, and system commands.

---

## Generic HID Controller Fallback (Third-Party Controller Support)

### Overview

Controllers not recognized by Apple's GameController framework are supported via IOKit HID + SDL's community-maintained `gamecontrollerdb.txt` database. This maps raw HID inputs to the Xbox-standard button layout, requiring zero manual configuration from users. Supports ~313 macOS controllers.

### Detection Flow

```
Controller plugged in (USB/Bluetooth)
    |
    +-- IOKit HID manager fires genericDeviceAppeared()
    |       |
    |       +-- Start 1-second fallback timer
    |
    +-- GameController framework claims device within 1s
    |       +-- controllerConnected() cancels timer -> normal path (Xbox/DualSense)
    |
    +-- Timer fires (unclaimed) -> attemptGenericFallback()
            |
            +-- Construct GUID from vendor/product/version/transport
            +-- Look up in GameControllerDatabase (tries exact version, then version=0)
            |
            +-- Found -> Create GenericHIDController -> wire callbacks -> activate
            +-- Not found -> log GUID, ignore device
```

### Key Files

| File | Purpose |
|------|---------|
| `Services/GameControllerDatabase.swift` | Parses SDL database, GUID construction, lookup, GitHub refresh |
| `Services/GenericHIDController.swift` | IOKit HID element enumeration, input translation to ControllerButton |
| `Resources/gamecontrollerdb.txt` | Bundled SDL database (~313 macOS controller mappings) |
| `Services/ControllerService.swift` | Integration: HID manager setup, fallback timer, callback wiring |

### SDL gamecontrollerdb.txt Format

Each line: `GUID,Name,button:ref,button:ref,...,platform:Mac OS X,`

**GUID construction** (little-endian 16-bit fields):
```
[bus][0000][vendor][0000][product][0000][version][0000]
```
- Bus: USB = `0300`, Bluetooth = `0500`
- Values from IOKit: `kIOHIDVendorIDKey`, `kIOHIDProductIDKey`, `kIOHIDVersionNumberKey`, `kIOHIDTransportKey`

**Element references:**
- `b0`, `b1`, ... -- Button by index (sorted by HID Button page usage)
- `a0`, `a1`, ... -- Axis by index (sorted by GenericDesktop usage: X->a0, Y->a1, Z->a2, Rx->a3, Ry->a4, Rz->a5)
- `h0.1`, `h0.2`, `h0.4`, `h0.8` -- Hat switch directions (up/right/down/left bitmask)
- `~a2` -- Inverted axis
- `+a1`, `-a1` -- Half-axis (positive/negative direction only)

### SDL to ControllerButton Mapping

| SDL Name | ControllerButton | SDL Name | ControllerButton |
|----------|-----------------|----------|-----------------|
| a | .a | leftshoulder | .leftBumper |
| b | .b | rightshoulder | .rightBumper |
| x | .x | dpup | .dpadUp |
| y | .y | dpdown | .dpadDown |
| start | .menu | dpleft | .dpadLeft |
| back | .view | dpright | .dpadRight |
| guide | .xbox | leftstick | .leftThumbstick |
| misc1 | .share | rightstick | .rightThumbstick |

Axes: `leftx`, `lefty`, `rightx`, `righty` (sticks), `lefttrigger`, `righttrigger` (triggers)

### GenericHIDController Internals

**Element enumeration (SDL-compatible sorting):**
- Buttons: `kHIDPage_Button` elements sorted by usage number -> b0, b1, b2...
- Axes: `kHIDPage_GenericDesktop` elements with usages X(0x30)->a0, Y(0x31)->a1, Z(0x32)->a2, Rx(0x33)->a3, Ry(0x34)->a4, Rz(0x35)->a5, sorted by usage
- Hat: usage `kHIDUsage_GD_Hatswitch` (0x39)

**Axis normalization:**
- Sticks: `(value - center) / (range/2)` -> -1.0..1.0
- Triggers: `(value - logicalMin) / range` -> 0.0..1.0
- Calibration from `IOHIDElementGetLogicalMin/Max`

**Hat switch:** 8-position value (0-7) -> bitmask (1=up, 2=right, 4=down, 8=left). Value >= 8 = neutral.

**Callbacks** match ControllerService's existing interface:
- `onButtonAction: ((ControllerButton, Bool) -> Void)?`
- `onLeftStickMoved: ((Float, Float) -> Void)?`
- `onRightStickMoved: ((Float, Float) -> Void)?`
- `onLeftTriggerChanged: ((Float, Bool) -> Void)?`
- `onRightTriggerChanged: ((Float, Bool) -> Void)?`

### ControllerService Integration

**Properties added to ControllerService:**
- `genericHIDManager: IOHIDManager?` -- Monitors gamepad/joystick device connections
- `genericHIDController: GenericHIDController?` -- Active generic controller instance
- `genericHIDFallbackTimer: DispatchWorkItem?` -- 1-second delay before fallback activation
- `isGenericController: Bool` -- Published; true when active controller is generic HID

**Key behaviors:**
- `setupGenericHIDMonitoring()` -- Called in `init()`, sets up IOKit HID manager matching GamePad (0x05) and Joystick (0x04) usage pages
- `controllerConnected()` -- Cancels fallback timer and stops any active generic controller (GameController takes priority)
- `genericDeviceRemoved()` -- Calls `controllerDisconnected()` for cleanup
- Generic controllers show Xbox layout in UI (no DualSense-specific features)

### Database Storage

- Bundled: `Bundle.main.path(forResource: "gamecontrollerdb", ofType: "txt")`
- User-downloaded: `~/.controllerkeys/gamecontrollerdb.txt`
- Priority: user copy > bundled copy
- Refresh: Settings -> Third-Party Controllers -> Refresh (downloads from GitHub SDL_GameControllerDB)

### Swift 6 / Concurrency Notes

- Free-standing C callback functions (`genericHIDDeviceMatched`, `genericHIDDeviceRemoved`) must be marked `nonisolated` due to the project's `-default-isolation=MainActor` build setting
- GenericHIDController uses `Unmanaged` pointers for IOKit callback context (same pattern as XboxGuideMonitor)
- Callbacks dispatch to `controllerQueue` or main actor as appropriate

---

## Known Workarounds

### Accessibility Zoom (Control+Scroll)

**Problem:** macOS Accessibility Zoom ("Use scroll gesture with modifier keys to zoom") doesn't respond to synthetic `CGEvent` scroll events with Control modifier. This is because Accessibility Zoom specifically requires real trackpad gesture events containing undocumented IOKit HID touch data structures.

**Research findings:**
- Real trackpad gestures contain proprietary touch data appended to CGEvent structures
- These touch data structures are undocumented by Apple
- Even Hammerspoon developers couldn't figure out how to synthesize them (see [issue #1434](https://github.com/Hammerspoon/hammerspoon/issues/1434))
- The only known workaround using private APIs (`tl_CGEventCreateFromGesture`) would require reverse-engineering undocumented IOKit structures

**Our solution:** Convert Control+scroll to Accessibility Zoom keyboard shortcuts:
- Scroll up → **Option+Command+=** (zoom in)
- Scroll down → **Option+Command+-** (zoom out)

**Implementation** (`InputSimulator.swift`):
- Accumulates scroll delta with 10px threshold to prevent flooding
- Rate limited to max 20 zoom actions/second (50ms interval)
- Requires user to enable "Use keyboard shortcuts to zoom" in System Settings → Accessibility → Zoom

**Why not private APIs?**
- The gesture synthesis requires undocumented touch data structures, not just a simple private function call
- Keyboard shortcuts provide the same functionality reliably

---

## Service Layer Overview

| Service | File | Responsibility |
|---------|------|---------------|
| `ControllerService` | Services/ControllerService.swift | Controller connection, raw input handling, haptics, battery, DualSense HID |
| `MappingEngine` | Services/MappingEngine.swift | Button->action mapping, chords, long hold, double tap, macros, system commands |
| `InputSimulator` | Services/InputSimulator.swift | CGEvent-based keyboard/mouse output |
| `ProfileManager` | Services/ProfileManager.swift | Profile CRUD, persistence, backup |
| `AppMonitor` | Services/AppMonitor.swift | Active app detection for profile auto-switching |
| `XboxGuideMonitor` | Services/XboxGuideMonitor.swift | IOKit HID for Xbox Guide button (swallowed by GameController) |
| `GameControllerDatabase` | Services/GameControllerDatabase.swift | SDL database parsing and lookup |
| `GenericHIDController` | Services/GenericHIDController.swift | Raw HID input for third-party controllers |
| `OnScreenKeyboardManager` | Services/OnScreenKeyboardManager.swift | Floating keyboard overlay window |
| `CommandWheelManager` | Services/CommandWheelManager.swift | Radial menu for app/website switching |
| `InputLogService` | Services/InputLogService.swift | Debug input logging |
| `SystemCommandExecutor` | Services/SystemCommandExecutor.swift | Shell commands, app launch, URL open |

---

## Threading Model

- **controllerQueue** (`DispatchQueue`, `.userInteractive`): All button press/release logic, chord detection, mapping execution
- **Main thread**: UI updates, IOKit HID manager run loop, GameController callbacks
- **ControllerStorage** (`NSLock`): Thread-safe joystick/trigger/touchpad state shared between polling timer and input callbacks
- **Display update timer**: 15Hz UI refresh for stick/trigger positions (vs ~120Hz internal polling)

---

## Project Structure

```
XboxControllerMapper/
  XboxControllerMapper/
    Config.swift                    -- Constants, paths, keys
    XboxControllerMapperApp.swift   -- App entry point
    Models/                         -- Data types (ControllerButton, KeyMapping, Profile, etc.)
    Services/                       -- Business logic (see table above)
    Utilities/                      -- KeyCodeMapping, VariableExpander, HIDPropertyScanner
    Views/
      MainWindow/                   -- ContentView, ButtonMappingSheet, ControllerVisualView
      Components/                   -- Reusable views (KeyCaptureField, FlowLayout, etc.)
      Macros/                       -- MacroListView, MacroEditorSheet
      MenuBar/                      -- MenuBarView
    Resources/                      -- gamecontrollerdb.txt, Assets
```

---

## Build Configuration

- **Xcode project** (not workspace): `XboxControllerMapper/XboxControllerMapper.xcodeproj`
- **Scheme**: `XboxControllerMapper`
- **Bundle ID**: Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) -- files in the project directory are auto-discovered, no manual "Add Files" needed
- **Deployment target**: macOS 14.6
- **Swift version**: 5 with upcoming features (`NonisolatedNonsendingByDefault`, `MemberImportVisibility`, `InferSendableFromCaptures`, `DefaultIsolation=MainActor`)
- **Team ID**: 542GXYT5Z2
- **Build command**: `make install BUILD_FROM_SOURCE=1` (kills running app, builds Release, copies to /Applications, launches)
