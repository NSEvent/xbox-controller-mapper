# ControllerKeys - Support

## Getting Started

### System Requirements

- **macOS 14.6 (Sonoma)** or later
- A supported controller. ControllerKeys supports Xbox, PlayStation, Steam Controller, Nintendo, Apple TV Remote, 8BitDo, and hundreds of SDL-database-compatible models; features vary by hardware.
- Accessibility permissions (required for input simulation)

### Installation

1. Install with `brew install --cask nsevent/tap/controllerkeys`, or download the latest DMG from [GitHub Releases](https://github.com/NSEvent/xbox-controller-mapper/releases/latest)
2. For a DMG install, drag `ControllerKeys.app` to `/Applications`
3. Launch the app and follow the guided permission setup
4. ControllerKeys includes a free 14-day trial. To continue afterward, [buy a license on Gumroad](https://thekevintang.gumroad.com/l/xbox-controller-mapper) and enter it in **Settings → General**

### Granting Accessibility Permissions

The app requires Accessibility permissions to simulate keyboard and mouse input. When you first launch the app:

1. macOS will prompt you to grant Accessibility access
2. Click "Open System Settings" (or go to System Settings > Privacy & Security > Accessibility)
3. Find "ControllerKeys" in the list
4. Toggle it ON
5. You may need to restart the app for permissions to take effect

**Why is this needed?** The app uses Apple's CGEvent API to generate keyboard and mouse events when you press controller buttons. This is the same API used by accessibility tools and other input remapping utilities.

### Connecting Your Controller

1. Put the controller in its Bluetooth pairing mode, or connect it by USB
2. For Bluetooth, open System Settings > Bluetooth and select the controller
3. Once macOS shows it as connected, launch ControllerKeys
4. See the [controller-specific guides](https://www.kevintang.xyz/apps/controller-keys/guides/) for Xbox, PlayStation, Steam Controller, and other hardware notes

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

- **Left Joystick**: Defaults to mouse movement
- **Right Joystick**: Defaults to scrolling

Each stick can instead be disabled or configured for mouse, scroll, custom direction mappings, or D-pad behavior. Stick behavior can vary by profile and layer.

### Layer activation

Each layer can use **Hold** or **Toggle** activation:

- **Hold** keeps the layer active only while its activator button is held.
- **Toggle** latches the layer on after one press. Press the same activator again to turn it off, or press another toggle layer's activator to switch layers.

Held layers temporarily take priority over a toggled layer. Releasing the held activator returns to the toggled layer.

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
- Profiles are saved to `~/.config/controllerkeys/config.json`

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

1. **Check macOS version**: Requires macOS 14.6 or later
2. **Reset configuration**: Delete `~/.config/controllerkeys/config.json` and relaunch
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

A: The app source is public for inspection under the PolyForm Noncommercial 1.0.0 license. Official releases are signed with Kevin Tang's Apple Developer ID, notarized by Apple, and verified by Gatekeeper.

ControllerKeys uses pseudonymous, opt-out usage analytics: a random install ID, app/build and Mac details, locale, install channel, and trial/license events. License activation includes its Gumroad sale ID, which makes that installation linkable to a purchase record; the analytics database does not store buyer names or email addresses. Approximate country and a salted IP hash are stored, not the raw IP. Turn this off in **Settings → General → Privacy**; that also disables Sparkle system profiling. Update and license checks still connect.

Raw HID reports, typed text, mappings, scripts, quick text, and configuration are never sent as analytics. Aggregate button/action counts, movement distances, and session totals are stored locally for recommendations and Controller Wrapped. Other network activity occurs for updates, license verification, community profiles/controller-database refreshes, favicon downloads, Mac-to-Mac relay, and destinations you configure through webhooks, OBS, scripts, or links. See the [Privacy Policy](https://www.kevintang.xyz/apps/controller-keys/privacy-policy.html).

**Q: Does the app work with third-party Xbox controllers?**

A: ControllerKeys uses Apple's GameController framework plus direct HID support and the SDL controller database. Hundreds of third-party models are recognized, but available buttons, touchpads, motion sensors, and advanced features vary by controller.

**Q: Can I use multiple controllers at once?**

A: ControllerKeys detects multiple connected controllers but routes mappings from one active controller at a time. After the active controller is idle, meaningful input from another connected controller can take over automatically.

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

A: Mouse and scroll are the defaults. Click a stick in the controller view to choose its mode and tune it independently; profiles and layers can use different stick behavior.

**Q: Why is scrolling jerky in some apps?**

A: Some apps handle scroll events differently. Try adjusting scroll sensitivity and acceleration. Apps that use custom scroll implementations may not respond smoothly.

### Profile Questions

**Q: Where are my profiles stored?**

A: Profiles are saved to `~/.config/controllerkeys/config.json`. This is a human-readable JSON file.

**Q: Can I share profiles with others?**

A: Yes. You can copy the config.json file or use the export feature to share individual profiles.

**Q: I lost my settings. Can I recover them?**

A: If you have Time Machine backups, you can restore `~/.config/controllerkeys/config.json` from a backup.

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
- **Website & Guides**: [ControllerKeys](https://www.kevintang.xyz/apps/controller-keys/)
- **Privacy Policy**: [Data and network activity](https://www.kevintang.xyz/apps/controller-keys/privacy-policy.html)
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
