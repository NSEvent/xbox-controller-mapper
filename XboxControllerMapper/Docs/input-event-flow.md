# Input Event Flow

Primary flow for controller inputs through mapping to synthesized macOS events.

```mermaid
flowchart TD
  subgraph Controller_Input
    GC[GameController.framework<br/>GCController + GCExtendedGamepad]
    Guide[IOKit HID<br/>XboxGuideMonitor Guide button]
  end

  GC --> CS[ControllerService<br/>button/axis handlers + chord window]
  Guide --> CS

  CS -->|onButtonPressed/onButtonReleased| ME[MappingEngine<br/>press/hold/long/double/chord logic]
  CS -->|onChordDetected| ME
  CS -->|threadSafeLeftStick/rightStick| ME

  ME -->|profile + mappings| PM[ProfileManager<br/>Profile + JoystickSettings]
  ME -->|frontmost bundle id| AM[AppMonitor]
  ME -->|log entries| LS[InputLogService]

  ME -->|keyboard/mouse/scroll| IS[InputSimulator<br/>CGEvent synthesis]
  IS --> OS[macOS input system<br/>CGEvent tap]
```

<details>
<summary>ASCII fallback</summary>

```text
[GCController/GameController]     [XboxGuideMonitor (IOKit HID)]
              \                       /
               \                     /
              [ControllerService]
                      |
                      | button/chord callbacks + stick state
                      v
                [MappingEngine]
                 /     |      \
   [ProfileManager] [AppMonitor] [InputLogService]
                      |
                      v
                [InputSimulator]
                      |
                      v
                 [macOS CGEvent]
```
</details>

Notes:
- ControllerService performs early chord detection and publishes button callbacks.
- MappingEngine polls joystick state for mouse/scroll, using ProfileManager settings and AppMonitor overrides.
- InputSimulator posts CGEvent input events once Accessibility permissions are granted.
- Detailed pathway diagrams: see `main-input-flows.md`.
