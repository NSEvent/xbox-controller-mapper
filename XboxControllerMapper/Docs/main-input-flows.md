# Main Input Logic Flows

Focused map of the primary runtime pathways:
- Button press/release to keyboard/mouse/system action
- Touchpad tap/long-tap to click/action
- Touchpad movement to mouse movement
- Two-finger touchpad gesture to pan/zoom
- Joystick polling to mouse/scroll/direction keys

## 1) Button Press / Release Pipeline

```mermaid
flowchart TD
  A["ControllerService callback<br/>onButtonPressed(button)"] --> B["MappingEngine.handleButtonPressed(button)"]
  B --> C{"Engine enabled<br/>+ active profile?"}
  C -- "No" --> Z1["Drop input"]
  C -- "Yes" --> D{"Layer activator button?"}
  D -- "Yes" --> D1["Activate layer<br/>log feedback"] --> Z2["Done"]
  D -- "No" --> E{"On-screen keyboard<br/>D-pad intercept?"}
  E -- "Yes" --> E1["Drive keyboard nav<br/>start repeat"] --> Z2
  E -- "No" --> F["Resolve effective mapping<br/>(layers/base fallthrough)"]
  F --> G{"Mapping exists?"}
  G -- "No" --> G1["Log unmapped input"] --> Z2
  G -- "Yes" --> H{"Hold-style path?<br/>hold modifier OR mouse-hold"}
  H -- "Yes" --> H1["handleHoldMapping<br/>double-tap check + start hold"] --> Z2
  H -- "No" --> I["Set long-hold timer (optional)<br/>set repeat timer (optional)"] --> Z2

  R["ControllerService callback<br/>onButtonReleased(button,duration)"] --> R1["MappingEngine.handleButtonReleased(...)"]
  R1 --> R2["Stop repeat timer"]
  R2 --> R3{"Layer activator?"}
  R3 -- "Yes" --> R4["Deactivate layer"] --> Z3["Done"]
  R3 -- "No" --> R5["Cleanup long-hold/held-state/chord-state"]
  R5 --> R6{"Held mapping or active chord?"}
  R6 -- "Yes" --> R7["Stop hold / skip normal release"] --> Z3
  R6 -- "No" --> R8["Resolve mapping + release context"]
  R8 --> R9{"Skip release?<br/>hold/repeat/already long-hold"}
  R9 -- "Yes" --> Z3
  R9 -- "No" --> R10{"Long-hold threshold met?"}
  R10 -- "Yes" --> R11["Execute long-hold mapping"] --> Z3
  R10 -- "No" --> R12{"Double-tap mapping?"}
  R12 -- "Yes" --> R13["handleDoubleTapIfReady<br/>or schedule single fallback"] --> Z3
  R12 -- "No" --> R14["Execute single tap action"] --> Z3
```

## 2) Touchpad Tap / Long-Tap Pipeline

```mermaid
flowchart TD
  T0["ControllerService touch callbacks"] --> T1{"Tap type"}
  T1 -- "Single tap" --> T2["processTapGesture(.touchpadTap)"]
  T1 -- "Two-finger tap" --> T3["processTapGesture(.touchpadTwoFingerTap)"]
  T1 -- "Long tap" --> T4["processLongTapGesture(.touchpadTap)"]
  T1 -- "Two-finger long tap" --> T5["processLongTapGesture(.touchpadTwoFingerTap)"]

  T2 --> T6["Resolve effective mapping"]
  T3 --> T6
  T6 --> T7{"Double-tap mapping configured?"}
  T7 -- "No" --> T8["Execute mapping immediately"]
  T7 -- "Yes" --> T9["Shared double-tap handler<br/>exec alt or schedule single fallback"]

  T4 --> T10["Cancel pending single tap + clear tap state"]
  T5 --> T10
  T10 --> T11{"Long-hold mapping exists?"}
  T11 -- "No" --> T12["No-op"]
  T11 -- "Yes" --> T13["Execute long-hold mapping"]
```

## 3) Touchpad Movement vs Two-Finger Gesture

```mermaid
flowchart TD
  M0["onTouchpadMoved(delta)"] --> M1["processTouchpadMovement(delta)"]
  M1 --> M2{"Gesture active OR movement blocked?"}
  M2 -- "Yes" --> M3["Reset movement smoothing state"] --> M9["Done"]
  M2 -- "No" --> M4["Apply smoothing + deadzone + acceleration"]
  M4 --> M5["Scale by touchpad + mouse sensitivity"]
  M5 --> M6["Apply Y inversion rules"]
  M6 --> M7["InputSimulator.moveMouse(dx,dy)"]
  M7 --> M8["Record touchpad mouse distance"] --> M9

  G0["onTouchpadGesture(gesture)"] --> G1["processTouchpadGesture(gesture)"]
  G1 --> G2{"Two fingers active?"}
  G2 -- "No" --> G3["End gesture + flush phases + reset gesture state"] --> G9["Done"]
  G2 -- "Yes" --> G4["Smooth center/distance deltas"]
  G4 --> G5{"Pinch dominant over pan?"}
  G5 -- "Yes" --> G6{"Native zoom?"}
  G6 -- "Yes" --> G7["Post magnify gesture events"]
  G6 -- "No" --> G8["Emit Cmd+= / Cmd-- zoom steps"]
  G5 -- "No" --> G10["Pan path -> scroll deltas + momentum state"]
  G7 --> G9
  G8 --> G9
  G10 --> G9
```

## 4) Joystick Polling Loop (120Hz)

```mermaid
flowchart TD
  J0["Connected controller"] --> J1["startJoystickPolling()"]
  J1 --> J2["Timer tick @ Config.joystickPollInterval"]
  J2 --> J3["processJoysticks(now)"]
  J2 --> J4["processTouchpadMomentumTick(now)"]

  J3 --> J5["Read settings snapshot + stick positions"]
  J5 --> J6{"Left stick mode"}
  J6 -- "mouse" --> J6A["processMouseMovement"]
  J6 -- "scroll" --> J6B["processScrolling"]
  J6 -- "wasd/arrow" --> J6C["processDirectionKeys"]
  J6 -- "none" --> J6D["No-op"]

  J5 --> J7{"Command wheel active?"}
  J7 -- "Yes" --> J7A["Route right stick to wheel selection"]
  J7 -- "No" --> J8{"Right stick mode"}
  J8 -- "mouse" --> J8A["processMouseMovement"]
  J8 -- "scroll" --> J8B["processScrolling + boost state"]
  J8 -- "wasd/arrow" --> J8C["processDirectionKeys"]
  J8 -- "none" --> J8D["No-op"]
```

## Notes

- Mapping resolution is centralized through `ButtonMappingResolutionPolicy`.
- Action execution funnels through `MappingExecutor` for key/macro/system-command dispatch.
- Input synthesis is centralized in `InputSimulator` (`pressKey`, `moveMouse`, `scroll`, hold/release modifier paths).
