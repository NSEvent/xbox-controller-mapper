# Xbox Controller Mapper for macOS

A native macOS application that maps Xbox controller inputs to keyboard shortcuts, mouse movements, and scroll actions.

## Features

- **Button Mapping**: Map any Xbox controller button to keyboard shortcuts
  - Modifier-only mappings (⌘, ⌥, ⇧, ⌃)
  - Key-only mappings
  - Modifier + Key combinations
  - Long-hold for alternate actions
  - Chording (multiple buttons → single action)

- **Joystick Control**:
  - Left joystick → Mouse movement
  - Right joystick → Scrolling
  - Configurable sensitivity and deadzone

- **Per-App Overrides**: Configure different mappings for specific applications

- **Profile System**: Create and switch between multiple mapping profiles

- **Visual Interface**: Interactive controller-shaped UI for easy configuration

## Requirements

- macOS 13.0 or later
- Xbox controller with Bluetooth support
- Accessibility permissions (for input simulation)

## Setup

### Creating the Xcode Project

1. Open Xcode and create a new macOS App project
2. Choose "SwiftUI" for interface and "Swift" for language
3. Name it "XboxControllerMapper"
4. Copy all the source files from this directory into the project

### Project Configuration

1. **Add Frameworks**: Add the following frameworks to your target:
   - GameController.framework
   - Carbon.framework (for key codes)

2. **Info.plist**: Ensure these keys are present:
   - `NSBluetoothAlwaysUsageDescription` - For controller connection
   - `LSUIElement` - Set to `NO` for menu bar + window mode

3. **Entitlements**: Disable App Sandbox for CGEvent simulation to work
   - Set `com.apple.security.app-sandbox` to `NO`
   - Add `com.apple.security.device.bluetooth`

4. **Accessibility Permissions**: The app will prompt for Accessibility access on first launch. This is required for keyboard/mouse simulation.

### Building

1. Select your development team in Signing & Capabilities
2. Build and run (⌘R)
3. Grant Accessibility permissions when prompted

## Project Structure

```
XboxControllerMapper/
├── XboxControllerMapperApp.swift      # App entry point
├── Info.plist                          # App configuration
├── XboxControllerMapper.entitlements   # Sandbox/permissions
│
├── Models/
│   ├── ControllerButton.swift          # Xbox button enum
│   ├── KeyMapping.swift                # Mapping configuration
│   ├── Profile.swift                   # Profile with overrides
│   ├── ChordMapping.swift              # Multi-button chords
│   └── JoystickSettings.swift          # Joystick configuration
│
├── Services/
│   ├── ControllerService.swift         # Controller connection
│   ├── InputSimulator.swift            # Key/mouse simulation
│   ├── ProfileManager.swift            # Profile persistence
│   ├── AppMonitor.swift                # Frontmost app detection
│   └── MappingEngine.swift             # Mapping coordination
│
├── Views/
│   ├── MainWindow/
│   │   ├── ContentView.swift           # Main window
│   │   ├── ControllerVisualView.swift  # Controller visualization
│   │   └── ButtonMappingSheet.swift    # Button configuration
│   ├── MenuBar/
│   │   └── MenuBarView.swift           # Menu bar popover
│   └── Components/
│       └── KeyCaptureField.swift       # Shortcut capture
│
└── Utilities/
    └── KeyCodeMapping.swift            # Key code constants
```

## Default Mappings

| Button | Default Action |
|--------|---------------|
| A | Return/Enter |
| B | Escape |
| X | Space |
| Y | Tab |
| LB | ⌘ (hold) |
| RB | ⌥ (hold) |
| LT | ⇧ (hold) |
| RT | ⌃ (hold) |
| D-pad | Arrow keys |
| Menu | ⌘ + Tab |
| View | Mission Control |
| Xbox | Launchpad |
| L-Stick Click | Left Click |
| R-Stick Click | Right Click |
| Left Joystick | Mouse |
| Right Joystick | Scroll |

## Usage

1. Connect your Xbox controller via Bluetooth (System Preferences → Bluetooth)
2. Launch Xbox Controller Mapper
3. Grant Accessibility permissions when prompted
4. Click any button on the controller visualization to configure its mapping
5. Use the menu bar icon for quick access to enable/disable and profile switching

## License

MIT License
