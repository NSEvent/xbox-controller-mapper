# ControllerKeys - Support

## Getting Started

### System Requirements

- **macOS 14.0 (Sonoma)** or later
- Xbox controller with Bluetooth support (Xbox One S/X, Xbox Series S/X controllers)
- Accessibility permissions (required for input simulation)

### Installation

1. Download the app from [Gumroad](https://thekevintang.gumroad.com/l/xbox-controller-mapper)
2. Unzip and move `ControllerKeys.app` to `/Applications`
3. Launch the app
4. Grant Accessibility permissions when prompted (see below)

### Granting Accessibility Permissions

The app requires Accessibility permissions to simulate keyboard and mouse input. When you first launch the app:

1. macOS will prompt you to grant Accessibility access
2. Click "Open System Settings" (or go to System Settings > Privacy & Security > Accessibility)
3. Find "ControllerKeys" in the list
4. Toggle it ON
5. You may need to restart the app for permissions to take effect

**Why is this needed?** The app uses Apple's CGEvent API to generate keyboard and mouse events when you press controller buttons. This is the same API used by accessibility tools and other input remapping utilities.

### Connecting Your Controller

1. Put your Xbox controller in pairing mode (hold the pairing button until the Xbox logo flashes rapidly)
2. Open System Settings > Bluetooth
3. Select your controller from the available devices
4. Once connected, launch ControllerKeys

---

## Features Guide

### Button Mapping

Click any button on the controller visualization to configure its mapping. Each button supports:

- **Simple Key**: Press a controller button to send a single keystroke
- **Modifier + Key**: Send key combinations like ⌘+C, ⌥+Tab, etc.
- **Hold Modifier**: Hold a controller button to hold down a modifier key (⌘, ⌥, ⇧, ⌃)
- **Long Hold**: Different action when you hold the button longer (configurable threshold)
- **Double Tap**: Different action when you tap the button twice quickly
- **Repeat**: Continuously repeat the keystroke while holding the button

### Chord Mappings

Chords let you press multiple controller buttons simultaneously to trigger a single action. For example:

- RB + X → ⌘+Delete (forward delete)
- LB + View → ⌘+- (zoom out)

Configure chords in the "Chords" tab.

### Joystick Settings

- **Left Joystick**: Controls mouse movement
- **Right Joystick**: Controls scroll wheel

Adjustable settings include:

| Setting | Description |
|---------|-------------|
| Sensitivity | How fast the mouse/scroll moves (0-100%) |
| Deadzone | How far you must push before input registers (prevents drift) |
| Acceleration | How much speed increases as you push further |
| Invert Y | Flip vertical axis direction |
| Focus Mode | Hold a modifier for precise, slower mouse movement |

### Profiles

Create multiple profiles for different use cases:

- Click the profile dropdown in the menu bar to switch
- Create new profiles in Settings
- Each profile stores its own button mappings, chords, and joystick settings
- Profiles are saved to `~/.xbox-controller-mapper/config.json`

---

## Troubleshooting

### Controller Not Detected

1. **Check Bluetooth connection**: Ensure your controller is connected in System Settings > Bluetooth
2. **Re-pair the controller**: Forget the device in Bluetooth settings and pair again
3. **Restart the app**: Quit and relaunch ControllerKeys
4. **Check battery**: Low battery can cause connection issues

### Button Presses Not Working

1. **Check Accessibility permissions**: System Settings > Privacy & Security > Accessibility
2. **Remove and re-add the app**: Select the app in the list, click the minus button to remove it, then re-add it
3. **Restart the app** after granting permissions
4. **Check if mapping is enabled**: Look for the enable/disable toggle in the menu bar

### Mouse/Scroll Not Working

1. **Adjust deadzone**: If your joystick has drift, increase the deadzone setting
2. **Check sensitivity**: Very low sensitivity might make movement imperceptible
3. **Verify mapping is enabled**: Check the menu bar toggle

### App Won't Launch / Crashes

1. **Check macOS version**: Requires macOS 14.0 or later
2. **Reset configuration**: Delete `~/.xbox-controller-mapper/config.json` and relaunch
3. **Check Console.app**: Look for crash logs under "Crash Reports"

### Stuck Modifier Keys

If a modifier key (⌘, ⌥, etc.) gets stuck after disconnecting the controller:

1. Press the physical modifier key on your keyboard to release it
2. Or restart the app to clear all held modifiers

The app uses reference counting to prevent stuck keys, but rapid disconnection can occasionally cause issues.

---

## Frequently Asked Questions

### General

**Q: Is my data safe? This app requires Accessibility permissions.**

A: Yes. The app is fully open source so you can verify exactly what it does. It does not connect to the internet, collect data, or log your inputs. Controller inputs are translated to keyboard/mouse events in real-time and immediately discarded. The app is signed with an Apple Developer ID and notarized by Apple.

**Q: Does the app work with third-party Xbox controllers?**

A: The app uses Apple's GameController framework, which supports official Xbox controllers. Third-party controllers may work if they're recognized by macOS as Xbox controllers, but compatibility varies.

**Q: Can I use multiple controllers at once?**

A: Currently, the app supports one controller at a time. The first connected Xbox controller will be used.

**Q: Does this work with games?**

A: The app is designed for productivity use (coding, browsing, general computer use). Most games have native controller support and don't need this app. Using the app with games may cause conflicts or double inputs.

### Mapping Questions

**Q: How do I make a button act as a held modifier?**

A: When configuring a button, select only the modifier (⌘, ⌥, ⇧, or ⌃) without a key, and enable "Hold Modifier". The modifier will be held while the button is pressed and released when you let go.

**Q: Can I map a button to mouse clicks?**

A: Yes. In the key capture field, you can select "Mouse Left Click" or "Mouse Right Click" as the action.

**Q: How do long hold and double tap work together?**

A: They're independent. A quick tap triggers the normal action. A quick double-tap triggers the double-tap action. Holding past the threshold triggers the long-hold action.

**Q: What's the difference between a chord and a long hold?**

A: A chord requires pressing multiple buttons simultaneously. A long hold requires holding a single button for a longer duration.

**Q: Can I disable a button completely?**

A: Yes. Clear the mapping by removing the key code and all modifiers. The button will do nothing when pressed.

### Joystick Questions

**Q: My joystick drifts when I'm not touching it.**

A: Increase the deadzone setting. A deadzone of 15-20% usually eliminates drift while maintaining responsiveness.

**Q: How do I get precise mouse control?**

A: Use Focus Mode. Configure a modifier key as the focus mode trigger, then hold that modifier while using the joystick for slower, more precise movement.

**Q: Can I swap the left and right joystick functions?**

A: Currently, left joystick is always mouse and right joystick is always scroll. This is not configurable.

**Q: Why is scrolling jerky in some apps?**

A: Some apps handle scroll events differently. Try adjusting scroll sensitivity and acceleration. Apps that use custom scroll implementations may not respond smoothly.

### Profile Questions

**Q: Where are my profiles stored?**

A: Profiles are saved to `~/.xbox-controller-mapper/config.json`. This is a human-readable JSON file.

**Q: Can I share profiles with others?**

A: Yes. You can copy the config.json file or use the export feature to share individual profiles.

**Q: I lost my settings. Can I recover them?**

A: If you have Time Machine backups, you can restore `~/.xbox-controller-mapper/config.json` from a backup.

### Technical Questions

**Q: What key codes does the app use?**

A: The app uses Carbon virtual key codes, which are standard macOS key codes. These are documented in Apple's Events.h header file.

**Q: Does the app work with Karabiner-Elements or Hammerspoon?**

A: Generally yes. They operate at different levels — this app handles controller input, while Karabiner and Hammerspoon handle keyboard input and automation. They typically don't conflict.

**Q: Can I run the app at login?**

A: Yes. Add ControllerKeys to System Settings > General > Login Items.

**Q: Why does the app need to stay running?**

A: The app continuously monitors controller input and translates it to keyboard/mouse events in real-time. Quitting the app stops all controller-to-keyboard mapping.

---

## Contact & Feedback

- **Issues & Bug Reports**: [GitHub Issues](https://github.com/NSEvent/xbox-controller-mapper/issues)
- **Source Code**: [GitHub Repository](https://github.com/NSEvent/xbox-controller-mapper)
- **Purchase**: [Gumroad](https://thekevintang.gumroad.com/l/xbox-controller-mapper)

---

## Version History

### 1.0.0

- Initial release
- Full button mapping with modifiers, long hold, double tap, and repeat
- Chord mappings for multi-button combinations
- Joystick-to-mouse and joystick-to-scroll
- Profile system for multiple configurations
- Menu bar integration
- Universal binary (Intel + Apple Silicon)
