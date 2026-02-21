Show a heat map of finger fatigue based on button usage data.


Add chords to sequences so users can use a sequence of chords to activate an action


Expose controller haptic as an API to give something else to notify you on controller
Something like AI agent can ping you via haptic when it's done.
It can even do it however it wants, can do it in morse code or give you some unique signature like a unique ringtone to let you know which one it is.


Dualsense Gyro feature:  - Shake to undo — like iPhone but on macOS
  - Twist for volume — rotate controller clockwise/counterclockwise like a knob

  - Presence-based lock: When the controller disconnects (user walks away with it), auto-lock the screen. Reconnection + pattern =
  unlock.


Trigger Zones

  Triggers aren't buttons. They're not even axes. They're regions.

  Divide each trigger into 4 pressure zones: rest (0-25%), light (25-50%), medium (50-75%), full (75-100%). Each zone is a separate
  binding. Light pull of left trigger does one thing. Squeeze past half and it becomes something else. Full crush is a third action.

  Combined with the other trigger, that's 16 unique pressure combinations from two fingers. No extra buttons needed. Nobody does
  this. Every mapper treats triggers as either a button or a mouse axis.

  The transition between zones gets a distinct haptic click — like the detents on a physical dial. Your fingers learn the zones.


  Input Recording & Replay with Editable Timelines

  Record everything you do — every button press, stick movement, trigger squeeze — as a timestamped stream. Then open it in a
  timeline editor like a video editor. Trim, loop, adjust timing, remap individual events, then save it as a macro.

  The difference from current macros: you perform the macro naturally, then edit it. Instead of hand-authoring "press W, wait 200ms,
   press A, wait 100ms..." you just do the thing, and the recording captures the nuance — the exact analog curves, the pressure
  ramps, the timing that feels right.

  Replay can be slowed down, sped up, or quantized to a grid. Export recordings as shareable files.



  Ghost Profiles

  Load two profiles simultaneously. The "ghost" profile runs underneath your active profile and handles everything the active
  profile doesn't define.

  Active profile maps A, B, X, Y for Photoshop. Ghost profile handles all your universal stuff — media controls on chords, app
  switching on sequences, scroll on right stick. Switch active profiles freely; the ghost stays constant.

  This eliminates the "I have to duplicate my universal mappings into every profile" problem. Layers solve part of this but ghost
  profiles are compositional — stack them, swap the ghost independently, share ghosts between profiles.



  Cursor Magnetism

  When in mouse mode, the cursor feels the gravitational pull of interactive elements. Buttons, links, text fields, sliders —
  anything with an accessibility role — exerts a subtle attraction force.

  Not snap-to-target. Not grid-based. Actual physics simulation where elements have mass proportional to their size, and the cursor
  experiences gentle acceleration toward them. You still control the cursor, but navigating a toolbar becomes effortless because the
   cursor wants to land on buttons.

  The force field is visualized as a subtle distortion — nearby elements glow faintly or the cursor trail bends. Toggle it off for
  pixel-precise work.

  Combine with focus mode: normal mode has magnetism, focus mode disables it for precision.




  Stick Sentences

  Left stick selects a category. Right stick selects an item within that category. Release both to execute.

  Map it to anything: Left stick up = "Window", right stick left = "Left Half" → snaps window to left half of screen. Left stick
  right = "Media", right stick up = "Volume Up". Left stick down = "Nav", right stick right = "Next Tab".

  This creates a 2D selection matrix — 8 directions × 8 directions = 64 actions from two thumb movements, zero button presses. Each
  category and item gets a label rendered in a HUD.

  The HUD appears as a crosshair with the category ring on the left and the item ring on the right. As you move the left stick, the
  right ring updates to show available items.



  Analog Stick as Dial

  When hovering over a slider, number field, or any adjustable value in the UI (detected via accessibility), the right stick becomes
   a precision dial. Push right to increase, left to decrease, with the rate proportional to deflection.

  The value changes live in the app as you move the stick. No clicking, no dragging, no typing numbers. You feel the value with your
   thumb.

  Works on: volume sliders, opacity controls, font size fields, Xcode's constraint constant fields, color component sliders, video
  scrubbing, anything with AXRole: AXSlider or AXRole: AXIncrementor.



  Velocity Actions

  Not what button you pressed, but how fast you pressed it.

  A gentle press of A does one thing. A sharp, aggressive slam of A does another. The DualSense face buttons don't have analog
  pressure, but they do have measurable press-to-release timing. A slam is <30ms press-to-full-travel. A deliberate press is >80ms.

  Map gentle-A to "paste" and slam-A to "paste and submit". Gentle-B to "close tab" and slam-B to "close all tabs". The interaction
  mirrors real-world physicality — careful action for careful operation, forceful action for forceful operation.



  Dead Man's Switch Mappings

  A mapping that activates when you let go of everything. All buttons released, both sticks centered, triggers at rest. The
  controller is idle. After a configurable interval of total inactivity (2 seconds, 5 seconds), an action fires.

  Use cases: auto-pause media when you set the controller down. Auto-lock screen after 30 seconds of controller inactivity. Send a
  "going AFK" status message to Discord. Dim the DualSense lightbar to save battery.

  The inverse of every other mapping — action from absence of input.



???
  Profile Diffing

  Select two profiles and see exactly what's different between them — side by side, color-coded, like a git diff. Red for removed
  mappings, green for added, yellow for changed values.

  Then selectively merge: "take the chord mappings from Profile A but the joystick settings from Profile B." Cherry-pick across
  profiles.

  This becomes essential once someone has 5+ profiles with subtle variations. Right now there's no way to answer "what did I change
  between my Photoshop and Blender profiles?"




  Workspace Snapshots

  One button press captures the entire state of your desktop — which apps are open, where their windows are positioned, which tabs
  are active — as a named snapshot. Another button press restores it.

  Morning snapshot: Mail on left, Calendar on right, Slack in corner. Coding snapshot: VS Code full screen, Terminal below, browser
  on second monitor. Streaming snapshot: OBS, chat, alerts dashboard.

  This already exists in fragments (Stage Manager, Mission Control), but none of them capture the full cross-app state including
  window positions and sizes, and none are controller-triggered with instant restore. The controller becomes a workspace teleporter.

  Implementation: CGWindowListCopyWindowInfo for positions, NSWorkspace for apps, AppleScript/accessibility for window manipulation
  on restore.
