A native macOS application that maps Xbox and PS5 DualSense controller inputs to keyboard shortcuts, mouse movements, and scroll, magnify, pan actions. (Previously Xbox Controller Mapper)

I created this app because I wanted to vibe code with an Xbox/DualSense controller and use all my regular shortcuts.

I found other existing apps to be lacking or not configurable enough.

With the rise of Whisper-driven voice transcription, just hook up any button to your favorite voice transcription program (mine is the open-source VoiceInk) and you now have full typing abilities with only the controller.

Later on, I realized a PS5 DualSense controller that has a built in touchpad to control the mouse is an excellent solution for this kind of program. As of v1.1.0, there is now full support for DualSense controllers in addition to Xbox Series X|S controllers.

## Features

- **Button Mapping**: Map any Xbox/DualSense controller button to keyboard shortcuts
  - Modifier-only mappings (⌘, ⌥, ⇧, ⌃)
  - Key-only mappings
  - Modifier + Key combinations
  - Long-hold for alternate actions
  - Double-tap for additional actions
  - Chording (multiple buttons → single action)
  - Custom hints to label your mappings

- **Layers**: Create alternate button mapping sets activated by holding a designated button
  - Up to 3 layers total (base + 2 additional)
  - Momentary activation while holding the activator button
  - Fallthrough behavior for unmapped buttons
  - Name your layers (e.g., "Combat Mode", "Navigation")

- **Macros**: Multi-step action sequences
  - Key Press, Type Text, Delay, and Paste steps
  - Configurable typing speed
  - Assignable to buttons, chords, long-hold, and double-tap

- **System Commands**: Automate actions beyond key presses
  - Launch App: Open any application
  - Shell Command: Run terminal commands silently or in a terminal window
  - Open Link: Open URLs in your default browser

- **Joystick Control**:
  - Left joystick → Mouse movement (or WASD keys)
  - Right joystick → Scrolling (or Arrow keys)
  - Configurable sensitivity and deadzone
  - Hold modifier (RT by default) for precise mouse movement with cursor highlight
  - Disable option to turn off stick input entirely

- **Touchpad Control**: Use the touchpad from a DualSense controller with taps and multitouch gestures
  - Single finger tap → Left click
  - Two finger tap → Right click
  - Two finger swipe → Scrolling
  - Two finger pinch → Zoom in/out

- **On-Screen Keyboard, Commands, and Apps**: Use the on-screen keyboard widget to quickly select apps, commands, or keyboard keys
  - Use the controller without a keyboard with the on-screen keyboard
  - D-pad navigation with floating highlight
  - Easily enter configurable text strings and commands in Terminal with a single click
  - Use built-in variables to customize text output
  - Show and hide apps in customizable app bar
  - Website links with favicons
  - Media key controls (playback, volume, brightness)
  - Global keyboard shortcut to toggle visibility

- **Command Wheel**: GTA 5-inspired radial menu for quick app/website switching
  - Navigate with right stick, release to activate
  - Haptic feedback during navigation
  - Modifier key to toggle between apps and websites
  - Force quit and new window actions at full stick deflection

- **Cursor Hints**: Visual feedback showing executed actions above the cursor
  - Shows action name or macro name when buttons are pressed
  - Badges for double-tap (2×), long-press (⏱), and chord (⌘) actions
  - Held modifier feedback with purple "hold" badge

- **Profile System**: Create and switch between multiple mapping profiles
  - Community profiles: Browse and import pre-made profiles
  - App-specific auto-switching: Link profiles to applications
  - Custom profile icons

- **Visual Interface**: Interactive controller-shaped UI for easy configuration
  - Auto-scaling UI based on window size
  - Button mapping swap to quickly exchange mappings between two buttons

- **DualSense Support**: Full PlayStation 5 DualSense controller support
  - Touchpad as trackpad or button zones
  - Multi-touch gesture support
  - Customizable LED colors in USB connection mode
  - DualSense built-in microphone support in USB connection mode
  - Microphone mute button mapping
  - Battery notifications at low (20%), critical (10%), and fully charged (100%)

- **DualSense Edge (Pro) Support**: Full support for Edge-specific controls
  - Function buttons and paddles
  - Edge buttons available as layer activators

- **Third-Party Controller Support**: ~313 controllers supported via SDL database
  - 8BitDo, Logitech, PowerA, Hori, and more
  - No manual configuration needed

## Requirements

- macOS 14.0 or later
- Xbox Series X|S, DualSense, DualSense Edge, or compatible third-party controller
- Accessibility permissions (for input simulation)
