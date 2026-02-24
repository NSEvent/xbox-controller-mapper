A native macOS application that maps Xbox, PS5 DualSense, PS4 DualShock 4, and 300+ third-party controller inputs to keyboard shortcuts, mouse movements, scroll/magnify/pan actions, macros, scripts, webhooks, and system commands. Features an on-screen keyboard with swipe typing, DualSense touchpad and gyroscope support, and a JavaScript scripting engine. (Previously Xbox Controller Mapper)

I created this app because I wanted to vibe code with a controller and use all my regular shortcuts.

I found other existing apps to be lacking or not configurable enough.

With the rise of Whisper-driven voice transcription, just hook up any button to your favorite voice transcription program (mine is the open-source VoiceInk) and you now have full typing abilities with only the controller.

ControllerKeys now supports DualSense, DualSense Edge, DualShock 4, Xbox Series X|S, and 300+ third-party controllers.

## Features

- **Button Mapping**: Map any controller button to keyboard shortcuts
  - Modifier-only mappings (⌘, ⌥, ⇧, ⌃)
  - Key-only mappings
  - Modifier + Key combinations
  - Long-hold for alternate actions
  - Double-tap for additional actions
  - Chording (multiple buttons → single action)
  - Button sequences (ordered combos, e.g., Up-Up-Down-Down)
  - Custom hints to label your mappings

- **Layers**: Create alternate button mapping sets activated by holding a designated button
  - Up to 3 layers total (base + 2 additional)
  - Momentary activation while holding the activator button
  - Fallthrough behavior for unmapped buttons
  - Name your layers (e.g., "Combat Mode", "Navigation")

- **JavaScript Scripting**: Write custom automation scripts powered by JavaScriptCore
  - Full API: press(), hold(), click(), type(), paste(), delay(), shell(), openURL(), openApp(), notify(), haptic(), and more
  - App-aware scripting with app.name, app.bundleId, app.is() for context-sensitive actions
  - Trigger context (trigger.button, trigger.pressType, trigger.holdDuration)
  - screenshotWindow() API for capturing the focused window
  - Per-script persistent state that survives across invocations
  - Built-in example gallery with ready-to-use scripts
  - Script editor with syntax reference and AI prompt assistant

- **Macros**: Multi-step action sequences
  - Key Press, Type Text, Delay, Paste, Shell Command, Webhook, and OBS steps
  - Configurable typing speed
  - Assignable to buttons, chords, long-hold, and double-tap

- **System Commands**: Automate actions beyond key presses
  - Launch App: Open any application
  - Shell Command: Run terminal commands silently or in a terminal window
  - Open Link: Open URLs in your default browser

- **HTTP Webhooks**: Send HTTP requests from controller buttons and chords
  - Supports GET, POST, PUT, DELETE, and PATCH methods
  - Configurable headers and request body
  - Visual feedback showing response status above cursor
  - Haptic feedback on success or failure

- **OBS WebSocket Commands**: Control OBS Studio directly from controller buttons

- **Joystick Control**:
  - Left joystick → Mouse movement (or WASD keys)
  - Right joystick → Scrolling (or Arrow keys)
  - Configurable sensitivity and deadzone
  - Hold modifier (RT by default) for precise mouse movement with cursor highlight
  - Disable option to turn off stick input entirely

- **Gyroscope Aiming & Gestures** (DualSense/DualShock 4):
  - Gyro aiming: Use the gyroscope for precise mouse control in focus mode
  - 1-Euro filter for jitter-free smoothing with responsive tracking
  - Gesture mappings: Tilt forward/back and steer left/right to trigger actions
  - Per-profile gesture sensitivity and cooldown sliders

- **Touchpad Control** (DualSense/DualShock 4):
  - Single-finger tap or click → Left click
  - Two-finger tap or click → Right click
  - Two finger swipe → Scrolling
  - Two finger pinch → Zoom in/out

- **On-Screen Keyboard, Commands, and Apps**: Use the on-screen keyboard widget to quickly select apps, commands, or keyboard keys
  - Swipe typing: Slide across letters to type words (SHARK2 algorithm)
  - D-pad navigation with floating highlight
  - Easily enter configurable text strings and commands in Terminal with a single click
  - Use built-in variables to customize text output
  - Show and hide apps in customizable app bar
  - Website links with favicons
  - Media key controls (playback, volume, brightness)
  - Global keyboard shortcut to toggle visibility
  - Auto-scaling to fit smaller displays

- **Command Wheel**: GTA 5-inspired radial menu for quick app/website switching
  - Navigate with right stick, release to activate
  - Haptic feedback during navigation
  - Modifier key to toggle between apps and websites
  - Force quit and new window actions at full stick deflection

- **Stream Overlay for OBS**: Floating overlay showing active button presses for stream capture

- **Cursor Hints**: Visual feedback showing executed actions above the cursor
  - Shows action name or macro name when buttons are pressed
  - Badges for double-tap (2×), long-press (⏱), and chord (⌘) actions
  - Held modifier feedback with purple "hold" badge

- **Controller Wrapped**: Usage stats with shareable personality-typed cards
  - Track every button press, macro, webhook, app launch, and more
  - Streak tracking and personality typing based on usage patterns
  - Copy shareable card to clipboard for social media

- **Profile System**: Create and switch between multiple mapping profiles
  - Community profiles: Browse and import pre-made profiles
  - App-specific auto-switching: Link profiles to applications
  - Stream Deck V2 profile import
  - Custom profile icons

- **Visual Interface**: Interactive controller-shaped UI for easy configuration
  - Auto-scaling UI based on window size
  - Button mapping swap to quickly exchange mappings between two buttons
  - VoiceOver accessibility support

- **DualSense Support**: Full PlayStation 5 DualSense controller support
  - Full touchpad support with multi-touch gestures
  - Gyroscope aiming and gesture detection
  - Customizable LED colors in USB connection mode
  - DualSense built-in microphone support in USB connection mode
  - Microphone mute button mapping
  - Battery notifications at low (20%), critical (10%), and fully charged (100%)

- **DualSense Edge (Pro) Support**: Full support for Edge-specific controls
  - Function buttons and paddles
  - Edge buttons available as layer activators

- **DualShock 4 (PS4) Support**: Full PlayStation 4 DualShock 4 support
  - Touchpad mouse control and gestures (same as DualSense)
  - PlayStation-style button labels and icons throughout the UI
  - PS button support via HID monitoring (USB and Bluetooth)

- **Third-Party Controller Support**: ~313 controllers supported via SDL database
  - 8BitDo, Logitech, PowerA, Hori, and more
  - No manual configuration needed

- **Accessibility Zoom Support**: Controller input works correctly when macOS Accessibility Zoom is active

- **Controller Lock Toggle**: Lock/unlock all controller input with haptic feedback

## Requirements

- macOS 14.0 or later
- Xbox Series X|S, DualSense, DualSense Edge, DualShock 4, or compatible third-party controller
- Accessibility permissions (for input simulation)
