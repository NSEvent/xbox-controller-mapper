# ControllerKeys Feature Checklist

This document lists all features for verification after refactoring.

## Core Mapping

- [ ] Map controller buttons to keyboard keys (CGKeyCode)
- [ ] Map controller buttons to modifier keys (Cmd, Opt, Shift, Ctrl)
- [ ] Map controller buttons to key + modifier combinations
- [ ] Hold modifier mode (modifier stays held while button is held)
- [ ] Mouse button mappings (left click, right click, middle click)
- [ ] Special action mappings (Mission Control, App Expose, etc.)
- [ ] Long hold action (alternate action after holding button for threshold)
- [ ] Double tap action (alternate action on quick double press)
- [ ] Repeat while held (repeats key at configurable rate)
- [ ] Optional hint/description on any mapping

## Chord Mappings

- [ ] Map 2+ simultaneous button presses to a single action
- [ ] Chord detection with configurable window
- [ ] Chord mappings support key, macro, and system command actions
- [ ] Chord list reordering (drag to reorder)
- [ ] Add/edit/delete chord mappings

## Macros

- [ ] Create named macro sequences
- [ ] Macro step: Key press (with modifiers)
- [ ] Macro step: Key hold (with duration)
- [ ] Macro step: Delay (configurable milliseconds)
- [ ] Macro step: Type text (with speed control, 0 = instant paste)
- [ ] Assign macros to primary, long hold, or double tap actions
- [ ] Assign macros to chord mappings
- [ ] Macro list reordering
- [ ] Delete macro cleans up all button/chord references

## System Commands

- [ ] Shell Command (silent background execution)
- [ ] Shell Command (run in terminal window)
- [ ] Launch App (by bundle identifier, with Browse button)
- [ ] Open Link (URL in default browser, auto-prepends https://)
- [ ] System commands on primary, long hold, or double tap actions
- [ ] System commands on chord mappings
- [ ] Terminal app selection (Terminal, iTerm, Warp, Alacritty, Kitty, Hyper)

## Profiles

- [ ] Multiple profiles with names and icons
- [ ] Create/rename/delete profiles
- [ ] Default profile designation
- [ ] Active profile switching
- [ ] App-specific profile auto-switching (linked apps)
- [ ] Profile sidebar in main window
- [ ] Persistent storage (~/.controllerkeys/config.json)
- [ ] Backup system (last 5 backups)
- [ ] Safe loading (won't overwrite on decode failure)
- [ ] Backward-compatible Codable (decodeIfPresent everywhere)

## Joystick Settings

- [ ] Left stick → Mouse cursor movement
- [ ] Right stick → Scroll wheel
- [ ] Mouse sensitivity slider
- [ ] Scroll sensitivity slider
- [ ] Mouse deadzone configuration
- [ ] Scroll deadzone configuration
- [ ] Invert mouse Y axis
- [ ] Invert scroll Y axis
- [ ] Mouse acceleration curve
- [ ] Scroll acceleration
- [ ] Scroll boost multiplier
- [ ] Focus mode (precision control with modifier key)

## DualSense (PS5) Features

- [ ] DualSense controller detection and support
- [ ] PlayStation-style button labels (Cross, Circle, Square, Triangle)
- [ ] Light bar color configuration (RGB)
- [ ] Light bar brightness (dim, medium, bright)
- [ ] Light bar enable/disable
- [ ] Mute button LED mode (off, on, pulse)
- [ ] Player LEDs (5 individual LEDs)
- [ ] Touchpad button press mapping
- [ ] Touchpad two-finger press mapping
- [ ] Touchpad tap mapping
- [ ] Touchpad two-finger tap mapping
- [ ] Touchpad → Mouse cursor (with sensitivity/acceleration/deadzone/smoothing)
- [ ] Touchpad → Scroll (pan sensitivity)
- [ ] Touchpad pinch → Zoom (native or Cmd+Plus/Minus)
- [ ] Touchpad pan interpolation for smooth low-rate input
- [ ] Pinch snap-back prevention for short gestures
- [ ] Mic mute button mapping
- [ ] USB and Bluetooth HID communication

## On-Screen Keyboard

- [ ] Floating keyboard overlay window
- [ ] Quick text snippets (typed on press)
- [ ] Terminal commands (executed on press)
- [ ] Variable expansion ({username}, {date}, {time}, {datetime}, {hostname})
- [ ] App bar (quick launch apps)
- [ ] Website links (with cached favicons)
- [ ] Extended function keys toggle
- [ ] Keyboard toggle shortcut (configurable)
- [ ] Position remembered per-screen within session
- [ ] Activate all windows option for app switching
- [ ] Typing delay configuration

## Command Wheel

- [ ] Radial menu activated by button hold
- [ ] App switching via joystick direction
- [ ] Website links in wheel
- [ ] Haptic feedback on segment transitions
- [ ] Force quit option (hold in center)
- [ ] Alternate content via modifier key
- [ ] GTA 5-inspired visual design
- [ ] Incognito mode for website links (long hold)

## Battery & Connectivity

- [ ] Controller connection status display
- [ ] Battery level monitoring (Bluetooth)
- [ ] Battery percentage in toolbar
- [ ] Green color when charging
- [ ] Low battery notifications

## Third-Party Controller Support

- [ ] IOKit HID fallback for controllers not recognized by GameController framework
- [ ] SDL gamecontrollerdb.txt parsing (~313 macOS controller mappings)
- [ ] GUID construction from vendor/product/version/transport
- [ ] 1-second fallback timer (GameController framework gets priority)
- [ ] Automatic button/axis/hat translation to Xbox-standard layout
- [ ] Bundled database with manual refresh from GitHub
- [ ] Database refresh UI in Settings (Third-Party Controllers section)
- [ ] Version fallback lookup (exact version, then version 0)

## UI / UX

- [ ] Modern dark glass aesthetic
- [ ] Tab-based interface (Buttons, Chords, Macros, Joysticks, Keyboard, etc.)
- [ ] DualSense-specific tabs (Touchpad, LEDs, Microphone)
- [ ] Interactive controller visualization (clickable buttons)
- [ ] Active chord display with flow layout
- [ ] Menu bar icon with quick profile switching
- [ ] UI scale configuration
- [ ] Button icon view (Xbox 360 jewel-style, adapts to controller type)
- [ ] Tooltip support for hints
- [ ] Key capture field for recording keyboard input

## Technical

- [ ] Accessibility permission handling
- [ ] App Nap prevention
- [ ] CGEvent-based input simulation
- [ ] GameController framework for Xbox controllers
- [ ] IOKit HID for DualSense
- [ ] IOKit HID for generic third-party controllers (SDL database-driven)
- [ ] CoreHaptics integration
- [ ] Thread-safe controller state (NSLock)
- [ ] Dedicated dispatch queues for keyboard/mouse/controller events
- [ ] 120Hz joystick polling with throttled UI updates
- [ ] Input log for debugging
- [ ] Legacy config path migration (~/.xbox-controller-mapper → ~/.controllerkeys)
- [ ] Profile import/export via JSON
- [ ] Pinch-to-zoom UI scaling (0.5x-2.0x) with keyboard shortcuts (Cmd+/Cmd-/Cmd+0)
- [ ] Unit tests for mapping engine (modifier combos, chords, long hold, double tap)
