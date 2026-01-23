# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2026-01-22

### Changed

- Removed touchpad scroll momentum for DualSense two-finger gestures

## [1.2.1] - 2026-01-21

### Fixed

- Website links and app bar lists cutting off last item
- Favicon not loading for websites with favicons in subdirectories

## [1.2.0] - 2026-01-21

### Added

- Custom profile icons
  - Choose from 35 SF Symbol icons organized in 7 categories
  - Right-click profile → Set Icon to customize
  - Icons display in sidebar and menu bar

### Changed

- App name changed from Xbox Controller Mapper to ControllerKeys
- Distribution format changed from ZIP to DMG with drag-to-Applications install

## [1.1.2] - 2026-01-21

### Added

- Website links feature in on-screen keyboard settings
  - Add URLs that display with favicon and title
  - Click to open in default browser
- Media key controls in on-screen keyboard
  - Playback: Previous, Rewind, Play/Pause, Fast Forward, Next
  - Volume: Mute, Down, Up
  - Brightness: Down, Up
- Media keys available in visual keyboard picker for button and chord mapping

### Changed

- Swap order of Commands and Text sections in on-screen keyboard
- Increase app bar and website bar to 12 items per row
- Move media controls above extended function keys in keyboard picker
- Increase spacing between media control groups

### Fixed

- App activation in app bar not working for most apps
- Apps not launching focused when opened from app bar

## [1.1.0] - 2026-01-20

### Added

#### DualSense Touchpad
- Touchpad support for mouse control with configurable sensitivity
- Tap-to-click gesture (defaults to left click)
- Two-finger tap gesture for right-click
- Double-tap gesture support
- Long tap gesture support
- Pinch-to-zoom with native macOS magnify gestures or Cmd+Plus/Minus
- Two-finger scroll with momentum and Chrome compatibility
- Dedicated Touchpad settings tab
- Live touch point visualization for one and two fingers in controller preview in Buttons tab

#### DualSense LEDs
- LED control tab for lightbar color and brightness
- Player LED patterns (symmetric patterns only)
- Party mode for animated LED effects
- Bluetooth LED control support (with limitations notice)

#### DualSense Microphone
- Microphone tab with mute control and audio level meter
- Auto-enable microphone on USB connect

#### On-Screen Keyboard
- Full on-screen keyboard accessible via button mapping
- Quick text snippets with configurable typing speed
- Terminal command shortcuts that open a new terminal window
- App bar for quick app switching
- Variable expansion system with date/time, clipboard, app context, and file path variables
- Extended function keys toggle (F13-F20)
- Caps lock toggle
- Keyboard navigation for app picker and variable suggestions

#### UI Improvements
- Accurate DualSense controller visualization with touchpad display
- Controller-specific UI styling for DualSense vs Xbox
- Visual keyboard in chord mapping sheet
- Remember last connected controller type

### Fixed

- DualSense PS button not triggering over Bluetooth
- Improve chords tab to match app style
- Improve chords tab reordering
- Magnify gestures triggering button taps on Buttons tab
- Touchpad causing unintended mouse movement on tap
- Touchpad scroll not working in Chrome
- Touchpad click causing cursor jump
- Various LED control issues over Bluetooth

## [1.0.0] - 2026-01-16

### Added

- Button mapping with support for modifier-only, key-only, and modifier+key combinations
- Long-hold actions for alternate button behavior
- Double click actions for alternate button behavior
- Chord mappings (multiple buttons trigger a single action)
- Left joystick to mouse movement with configurable sensitivity and deadzone
- Right joystick to scroll with configurable sensitivity and deadzone
- Modifier key (RT by default) for sensitive mouse movement mode
- Profile system for multiple mapping configurations (saved in ~/.controllerkeys/config.json)
- Interactive controller visualization UI for easy configuration
- Menu bar icon for quick enable/disable and profile switching
- Default mappings optimized for general macOS navigation

[1.0.0]: https://github.com/NSEvent/xbox-controller-mapper/releases/tag/v1.0.0
