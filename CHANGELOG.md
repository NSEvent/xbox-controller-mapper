# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-02-18

### Added

- **PS4 DualShock 4 Controller Support**: Full support for DualShock 4 (v1 and v2) controllers
  - Touchpad mouse control and gestures (same as DualSense)
  - PlayStation-style button labels and icons throughout the UI
  - PS button works via HID monitoring (report IDs `0x01` USB, `0x11` Bluetooth)
  - DualShock 4's Share button correctly maps to Options/View
- **Controller Wrapped**: Usage stats with shareable personality-typed cards
  - Track every button press, macro, webhook, app launch, and more
  - Streak tracking and personality typing based on usage patterns
  - Copy shareable card to clipboard for social media
  - Detailed breakdown: input types, output actions, mouse/scroll distance, automation stats
- **HTTP Webhook Support**: Send HTTP requests from controller buttons and chords
  - Supports GET, POST, PUT, DELETE, and PATCH methods
  - Configurable headers and request body
  - Visual feedback above cursor showing response status (e.g., "Webhook 200")
  - Haptic feedback on success (crisp pulse) or failure (double pulse)
- **OBS WebSocket Commands**: Control OBS Studio directly from controller buttons
- **System Command Macro Steps**: Macros can now include shell commands, webhooks, and OBS WebSocket requests as steps

### Changed

- Extracted shared touchpad handler to eliminate code duplication between DualSense and DualShock
- Renamed HID monitoring from DualSense-specific to general PlayStation monitoring
- Button display throughout the app (stats, wrapped card, input log, chord sheets) now uses `isPlayStation` for correct labels on both PS4 and PS5 controllers
- Major ProfileManager refactor: extracted 15+ single-responsibility services for better testability
- Comprehensive test suite expansion across mapping engine, profile manager, command wheel, on-screen keyboard, and system commands

### Fixed

- Zoom-aware mouse click coordinates not resolving correctly
- System command hints not displaying when user sets a custom hint
- Macros without a name blocking save (now auto-generates timestamped name)
- Macro system command handler wiring broken by protocol extraction
- Keyboard and command wheel transient state not clearing on reset
- Webhook request body incorrectly sent for GET/DELETE methods
- Usage stats publishing not throttled on input hot path

## [1.4.3] - 2026-02-16

### Added

- **Favicon Caching**: Website link favicons now persist across app restarts
  - Cached in `~/.controllerkeys/favicons/`
  - Missing favicons automatically refetched in background
- **Press Enter Option**: Type Text macro step can optionally press Enter after typing
- **Edit Sheets**: App bar items and website links can be edited after creation
  - App search in edit sheet for quick app selection
- **Hover Highlighting**: Visual feedback across all interactive elements
  - Toolbar buttons, mapping toggle, settings rows
  - Consistent cursor behavior with reusable modifiers

### Fixed

- DualSense Edge layout (paddles, function buttons) persists when controller disconnects
- Drag-to-reorder in all settings lists (chords, macros, text snippets, apps, websites)
- Inconsistent row heights in active chords display
- App bar and website list not updating immediately after changes
- App bar list height cutting off last item
- Hover modifiers blocking clicks and not showing highlight
- Number key 5 mapped to wrong key code on visual keyboard
- Macro labels showing generic "Macro" for long hold and double tap actions

## [1.4.2] - 2026-02-16

### Added

- **Accessibility Zoom Support**: Controller input now works correctly when macOS Accessibility Zoom is active
  - Cursor movement, clicks, and scroll positions are properly scaled to zoomed coordinates
  - Focus mode ring and action hints position correctly within the zoomed viewport
  - Automatic detection with warning dialog if Zoom keyboard shortcuts aren't enabled
- **Chord Duplicate Prevention**: Visual feedback when creating chords that would conflict
  - Gray out buttons that would create duplicate chord combinations
  - Show conflicting chord name on grayed out buttons
- **Clickable Active Chords**: Click any active chord to open its edit sheet directly

### Fixed

- Focus mode ring positioning during Accessibility Zoom
- Action hint positioning during Accessibility Zoom with touchpad
- Action hint flashing when Accessibility Zoom is active
- Click position offset when Accessibility Zoom is active
- Cursor position reset when Accessibility Zoom is active
- Zoom warning dialog blocking input and repeated sounds
- Held modifier flags not forwarded to scroll events
- Long words overflowing in button mapping labels
- Non-deterministic JSON ordering in config.json

## [1.4.1] - 2026-02-14

### Added

- **Stick Mode Settings**: Configure left/right stick behavior independently
  - WASD keys mode for left stick (gaming-style movement)
  - Arrow keys mode for right stick (navigation)
  - Disable option to turn off stick input entirely
- **Held Modifier Feedback**: Purple "hold" badge in cursor hints when modifier buttons are held
  - Shows combined hint when multiple modifiers are held simultaneously
  - Badge also appears in Buttons tab mapping labels

### Fixed

- Typed text in macros being affected by held controller modifiers (e.g., Shift held while typing)
- Cursor hint text truncation now shows ellipsis instead of clipping
- Community profile preview showing Xbox button icons for DualSense controllers
- ChordMappingSheet now scrollable when content exceeds window height (DualSense Edge + keyboard)

### Changed

- Favicon data no longer persisted to config file (fetched on demand, reduces file size)

### Removed

- Keep Alive feature removed (was causing issues and determined unnecessary)

## [1.4.0] - 2026-02-12

### Added

- **Cursor Hints**: Visual feedback showing executed actions above the cursor
  - Shows action name, keyboard shortcut, or macro name when buttons are pressed
  - Type badges for double-tap (2×), long-press (⏱), and chord (⌘) actions
  - Held actions stay visible until button released with minimum display time
  - Toggle button in the Buttons tab to enable/disable
- **Focus Mode Cursor Highlight**: Purple ring around cursor when focus mode is active
  - Toggle setting in Joysticks > Focus Mode > "Highlight Focused Cursor"
- **Button Mapping Swap**: Quickly swap all mappings between two buttons
  - Click "Swap" button, select first button, select second button
  - Swaps primary action, double-tap, long-hold, repeat settings, and hints
  - Works within layers; does not affect chords
- **Layers Feature**: Create alternate button mapping sets activated by holding a designated button
  - Up to 2 additional layers beyond the base layer
  - Momentary activation - layer active while activator button is held
  - Fallthrough behavior - unmapped buttons use base layer mappings
  - User-named layers (e.g., "Combat Mode", "Navigation")
  - Visual layer tabs in the UI with activator button badges
- **DualSense Edge (Pro) Controller Support**
  - Full support for Edge-specific controls: function buttons and paddles
  - USB HID fallback for Edge controllers not recognized by GameController framework
  - Edge buttons available as layer activators when Edge controller is detected
- **Auto-Scaling UI**: Controller view and window content scale automatically when resized
  - Scales both up and down based on window size
  - Combines with manual zoom setting for full control

### Fixed

- Macro feedback now shows macro name instead of generic "Macro" text in cursor hints
- Chord macro feedback also displays actual macro name
- Accidental horizontal panning when scrolling vertically with right stick (now requires deliberate horizontal input)
- Deadlock in button release handler that caused mappings to stop working
- Command Wheel hint centering on on-screen keyboard
- Mapping label alignment across different button sizes (shoulder buttons vs others)

### Changed

- Edge controller row order: function buttons on top, paddles on bottom
- Layer activator labels now use consistent chip styling matching other mapping labels
- Re-applied CPU optimization for joystick callbacks (reduces idle CPU usage)

## [1.3.0] - 2026-02-09

### Added

- **Community Profiles**: Browse and import pre-made controller profiles from the community
  - New "Import Community Profile..." option in the profile menu
  - Preview profiles before importing (see all button mappings and chords)
  - Multi-select to import multiple profiles at once
  - Already-imported profiles are marked and cannot be re-imported
  - Profiles are fetched from the GitHub repository

## [1.2.3] - 2026-02-08

### Fixed

- F13-F20 keys not triggering hotkeys in terminals using CSI u / Kitty keyboard protocol (was outputting escape sequences like `[57376u` instead)

## [1.2.2] - 2026-02-03

### Added

- **D-pad Navigation for On-Screen Keyboard**
  - Navigate the entire keyboard using D-pad when on-screen keyboard is visible
  - Floating overlay highlight shows current selection
  - Special handling for arrow key cluster layout
  - Optimized responsiveness with navigation bounds on all keys
- **Third-Party Controller Support**: Fallback for controllers not recognized by GameController framework
  - IOKit HID + SDL gamecontrollerdb.txt maps raw inputs to Xbox-standard layout
  - ~313 macOS controllers supported (8BitDo, Logitech, PowerA, Hori, etc.)
  - 1-second fallback timer gives GameController framework priority
  - Bundled database with manual refresh from GitHub in Settings
  - No manual configuration needed; detected controllers use Xbox button labels
- **Macros System**: Full macro recording and playback with multi-step sequences
  - Macro steps: Key Press, Type Text, Delay, Paste
  - Type Text supports configurable speed settings
  - Macros assignable to buttons, chords, long hold, and double tap actions
  - Dedicated Macros tab for management
- **System Commands**: Automate actions beyond key presses
  - Launch App: open any application by bundle identifier with browse dialog
  - Shell Command: run terminal commands silently or in a terminal window
  - Open Link: open URLs in default browser
  - Assignable to buttons, chords, long hold, and double tap actions
- **Battery Notifications**: alerts at low (20%), critical (10%), and fully charged (100%)
- **Command Wheel**: GTA 5-inspired radial menu for quick app/website switching
  - Right stick navigates segments; releasing activates the selected item
  - Full-range stick actions (push all the way for force quit / new window)
  - Haptic feedback during navigation
  - Modifier key to toggle alternate content (apps vs websites)
  - Incognito long-hold action for websites
  - Three-tier icon positioning for varying item counts
- **App-Specific Profile Auto-Switching**
  - Link profiles to specific applications
  - Automatic profile switching when apps gain focus
  - Falls back to default profile for unlinked apps
- **On-Screen Keyboard Improvements**
  - Keyboard position remembered per screen within session
  - Global keyboard shortcut toggle (configurable in Keyboard tab)
  - "Activate All Windows" setting for app switching (on by default)
- **Mapping Enhancements**
  - Long hold and double tap now support macros and system commands (not just keys)
  - Optional hint field for button and chord mappings (primary, long hold, double tap)
  - Hints display instead of raw shortcuts; hover shows actual shortcut in tooltip
  - Caps Lock key properly shows display name in key picker
  - FN key disabled from being mapped as a regular key
- **Comprehensive Test Suite**
  - Tests for InputLogService and ProfileManager
  - Edge case tests for mapping engine
  - Chord fallback and modifier handling tests

### Changed

- Modern dark glass aesthetic for main window, on-screen keyboard, and command wheel
- Wrapping flow layout for active chords display (replaces horizontal scroll)
- Green battery indicator when controller is charging
- All config structs use resilient custom decoders (missing/new fields won't break configs)
- Schema version tracking for future migrations
- Repeat action rate defaults to 5/s (previously 20/s)
- Chord creation shows gray outlines when button combination already exists
- Center column buttons match side column width in Buttons tab
- Code refactored: unified mapping execution, extracted helpers, thread-safe screen cache
- Touchpad two-finger pan speed slightly reduced
- Touchpad momentum tuned for shorter, lighter glide
- Default pan-to-zoom ratio increased to 1.95
- Touchpad smoothing description clarified to "Reduce mouse jitter"

### Fixed

- System commands now show in green in Active Chords section
- Macro hints, trailing whitespace visibility, and button backgrounds
- Chord fallback bug when releasing buttons
- Event flags now always set to prevent inherited modifiers
- Smooth diagonal touchpad panning
- Touchpad pan scrolling
- On-screen keyboard appears on screen where mouse cursor is (not always primary display)
- Key capture field no longer intercepts clicks outside its bounds
- Long hold/double tap settings not loading when re-opening configure button page
- DualSense button icons displaying as Xbox style in configure button page header
- Save button properly handles empty system command/macro state
- Chord reordering preserved correctly
- Deadlock risk in InputSimulator removed (replaced DispatchQueue.main.sync with CoreGraphics API)
- Short pinch-to-zoom snap-back (direction lock on quick releases)
- Choppy two-finger scrolling from low touchpad sample rate (120Hz interpolation)

### Removed

- Touchpad scroll momentum for DualSense two-finger gestures (caused inconsistent behavior)

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
