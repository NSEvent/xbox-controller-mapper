# Developer / Power User—Setup Guide

ControllerKeys creator Kevin Tang's daily macOS profile, sanitized for sharing. It turns a controller into a dense coding and desktop-control surface: mouse and scrolling, text editing, window management, terminal controls, screenshots, macros, and ControllerKeys utilities.

The profile is most complete on a **DualSense Edge** because several shortcuts use its paddles and function buttons. The standard buttons, sticks, triggers, bumpers, and D-pad still work on other supported controllers.

## Import

1. Open **ControllerKeys → Profiles → Community Profiles**.
2. Find **Developer - Power User** and choose **Import**.
3. Review the code warning, then import if you're comfortable with the included commands described below.
4. Select the new profile. It is intentionally not linked to any controller or app, so it will not take over automatically.

## Optional apps

- **Rectangle**—required only for the window-position chords. The profile sends Rectangle's default `Control+Option` shortcuts. Install Rectangle or remap those chords to your preferred window manager.
- **iTerm2**—required only for the app-bar item, the launch sequence, and horizontal/vertical split shortcuts. Everything else works without it.
- **Claude Code**—two chords send its terminal shortcuts for detailed transcript and show-all. They are harmless in other apps but may perform a different action there.
- **Voice transcription**—the Xbox / PS (Guide) button sends `F13`, which Kevin uses as VoiceInk's global start/stop shortcut. Configure any transcription app to use `F13`, or remap the button; without one, the shortcut is inert. Pressing **Guide**, then **Right Trigger**, runs the included **Voice and Enter** macro.

No Hammerspoon setup is required. Personal home-theater controls—including AirPlay—were deliberately omitted from this public version.

## Everyday controls

| Input | Action |
| --- | --- |
| Left stick | Move the pointer |
| Right stick | Scroll |
| D-pad | Arrow keys |
| **Menu + Xbox** | Center the pointer on the main screen |
| **Xbox / PS (Guide)** | Send F13 for an optional voice-transcription shortcut |
| **Guide**, then **Right Trigger** | Toggle voice transcription, wait, then press Return |
| **Menu + Right Bumper** | Zoom in |
| **Left Bumper + View** | Zoom out |
| **Menu + D-pad Left / Right** | Undo / redo |
| **Right Bumper + X** | Select all and delete |
| **Right Bumper + D-pad Left / Right** | Jump to the start / end of a line |

## Window and terminal controls

Hold **A** and press a D-pad direction—or a diagonal—to move the current window to that half or corner with Rectangle.

| Input | Action |
| --- | --- |
| **Left Stick Click + Right Stick Click** | Rectangle almost fullscreen |
| **Menu + View** | Rectangle fullscreen |
| **X + D-pad Right** | iTerm horizontal split |
| **X + D-pad Down** | iTerm vertical split |
| **Right Bumper + B** | Claude Code detailed transcript |
| **Right Bumper + Y** | Claude Code show all |

## DualSense Edge extras

| Input | Action |
| --- | --- |
| **Left Paddle + Right Paddle** | Open ControllerKeys Directory Navigator |
| **Right Function + Right Paddle** | Save a screenshot of the focused window to the Desktop |
| **Left Function + Right Function** | Open the macOS screenshot tool |
| Double-tap **Right Paddle** | Open ControllerKeys |

## Included code and permissions

ControllerKeys shows a confirmation before importing profiles that contain executable code. This one contains two small, local automations:

- **Center Mouse** runs an embedded JavaScript for Automation command to move the pointer to the center of the main display.
- **Screenshot Window to Desktop** uses ControllerKeys' JavaScript API to capture the focused window and save a timestamped PNG to `~/Desktop`.

The screenshot action needs **Screen Recording** permission for ControllerKeys. If it fails, enable ControllerKeys in **System Settings → Privacy & Security → Screen & System Audio Recording**, then try again.

Both code snippets are visible in the import warning and remain editable after import. The profile sends no webhooks and contains no credentials, controller identifiers, or prefilled quick text. Its website list contains only ordinary, visible command-wheel shortcuts.

## Good first customizations

- Replace iTerm2 with your terminal in the on-screen keyboard app bar and launch sequence.
- Change or remove the Rectangle chords if you use another window manager.
- Add your own quick text—the public profile intentionally leaves it empty.
- Remap the DualSense Edge-only actions if your controller lacks paddles or function buttons.
