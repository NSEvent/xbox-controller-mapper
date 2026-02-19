# Macro Recording Mode

Record live keyboard and mouse input into macro steps instead of building them manually.

## Motivation

Macros are currently assembled step-by-step through the `MacroStepEditorSheet` — users pick a step type, configure parameters, save, then repeat. For anything beyond a few steps this is tedious and error-prone (wrong key codes, missing delays, incorrect ordering). A recording mode lets users simply perform the actions they want to automate and produces a ready-to-edit `[MacroStep]`.

## Scope

- Record keyboard key presses (down/up) as `.press(KeyMapping)` steps
- Record inter-event delays as `.delay(TimeInterval)` steps
- Record mouse clicks (left/right/middle) as `.press` with mouse key codes
- Present the recorded steps in the existing macro editor for trimming, reordering, and manual editing before saving
- Optionally collapse very short delays or merge adjacent modifier+key presses into a single step

Out of scope (v1):
- Recording mouse movement / cursor position
- Recording scroll events
- Recording application context (which app was focused)
- Recording clipboard content or typed text as `.typeText` steps (can be added later)

## Technical Design

### 1. Event Capture via CGEventTap

The app already uses `CGEvent.post(tap: .cghidEventTap)` for output simulation and has Accessibility permissions. Recording requires a **passive CGEventTap** listening for input events.

```
Location: new file — Services/Input/MacroRecorder.swift
```

```swift
class MacroRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var recordedSteps: [MacroStep] = []

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastEventTime: Date?

    // Configurable
    var minimumDelayThreshold: TimeInterval = 0.02  // Delays below this are collapsed
    var maximumDelay: TimeInterval = 5.0            // Cap long pauses
}
```

**Event tap setup:**

```swift
let eventMask: CGEventMask = (
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.leftMouseUp.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.rightMouseUp.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)
)

eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,        // passive — does NOT block or modify events
    eventsOfInterest: eventMask,
    callback: eventTapCallback,
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)
```

Key: `.listenOnly` ensures the tap is passive. Events pass through unmodified to their destination app. This avoids interfering with normal keyboard use during recording.

**Self-event filtering:**

The recorder must ignore events that ControllerKeys itself generates via `InputSimulator`. Two options:

- **Flag approach**: Set a thread-local or atomic `InputSimulator.isSynthesizing` flag around all `CGEvent.post()` calls. The tap callback checks this flag and skips flagged events.
- **PID approach**: Tag synthetic events with a custom `CGEventField` or check `event.getIntegerValueField(.eventSourceUnixProcessID)` against our own PID. However, `.cghidEventTap` synthetic events may not carry a reliable source PID.

Recommended: flag approach, since all synthesis runs on `keyboardQueue` and the tap fires synchronously.

### 2. Event-to-MacroStep Conversion

The tap callback receives raw `CGEvent` references. Conversion logic:

```
keyDown event:
    1. Compute delay since last event → append .delay(delta) if delta > minimumDelayThreshold
    2. Extract keyCode (CGKeyCode) from event
    3. Extract modifier flags (CGEventFlags) → convert to ModifierFlags
    4. Append .press(KeyMapping(keyCode: keyCode, modifiers: modifiers))
    5. Update lastEventTime

keyUp event:
    - Ignored for .press steps (press = tap, not hold)
    - For hold detection: if hold recording is enabled, track keyDown time and
      convert to .hold(mapping, duration:) if held > holdThreshold (e.g., 0.5s)

flagsChanged event:
    - Track modifier state changes but don't generate steps
    - Modifier state is captured as part of the next keyDown event

mouseDown event:
    - Map to .press with mouse button sentinel key codes
      (same codes used by InputSimulator for mouse click simulation)

mouseUp event:
    - Ignored (same as keyUp — press = click)
```

### 3. Hold Detection (Optional Enhancement)

Track `keyDown` timestamps in a dictionary. On `keyUp`, if the key was held longer than `holdThreshold`:

```swift
if holdDuration > holdThreshold {
    // Replace the last .press step for this keyCode with .hold(mapping, duration: holdDuration)
    replaceLastPressWithHold(keyCode: keyCode, duration: holdDuration)
}
```

This could be a toggle in the recording UI: "Detect held keys".

### 4. Post-Processing / Cleanup

After the user stops recording, apply optional cleanup passes:

| Pass | Description |
|------|-------------|
| **Collapse short delays** | Remove `.delay` steps below `minimumDelayThreshold` |
| **Cap long delays** | Clamp `.delay` values to `maximumDelay` |
| **Merge modifier+key** | If a `flagsChanged` is immediately followed by a `keyDown`, merge modifier state into the `KeyMapping` (this happens naturally since modifiers are read from the keyDown event flags) |
| **Deduplicate** | Remove duplicate consecutive identical `.press` steps (accidental double-taps during recording) |

Post-processing is applied automatically but the user can undo it via the editor.

### 5. UI Integration

#### Recording Button

Add a "Record" button to `MacroEditorSheet`, next to the existing "Add Step" row.

```
┌─────────────────────────────────────────┐
│ Macro Editor: "My Macro"                │
│                                         │
│  1. ⌘C           [edit] [×]            │
│  2. Delay 0.3s   [edit] [×]            │
│  3. ⌘V           [edit] [×]            │
│                                         │
│  ┌──────────┐  ┌────────────────────┐   │
│  │ + Add    │  │ ⏺ Record Steps    │   │
│  └──────────┘  └────────────────────┘   │
│                                         │
│          [Cancel]    [Save]             │
└─────────────────────────────────────────┘
```

#### Recording State

When recording is active:

```
┌─────────────────────────────────────────┐
│ ⏺ Recording...  (14 steps captured)    │
│                                         │
│  Perform your actions now.              │
│  Press ⏹ Stop or Esc to finish.        │
│                                         │
│  ☐ Detect held keys                     │
│  ☐ Include mouse clicks                 │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ ⏹ Stop Recording                │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

- The recording overlay replaces the step list while recording
- Live step count updates as events arrive
- A pulsing red dot indicator (consistent with the app's existing `ActionFeedbackIndicator` pattern)
- Stop via button click, Esc key, or a configurable controller button (e.g., Xbox/Guide)

#### Post-Recording Review

After stopping, the recorded steps appear in the normal step list. The user can:
- Delete unwanted steps
- Edit individual steps (opens `MacroStepEditorSheet`)
- Drag to reorder
- Add additional manual steps
- Re-record (clears current steps and starts fresh, with confirmation)

### 6. Controller Button to Stop Recording

Since the user's hands are on the controller, allow a controller button press to stop recording. The `MappingEngine` would check a `MacroRecorder.isRecording` flag and, if a designated stop button is pressed (e.g., Xbox/Guide or a chord), call `macroRecorder.stopRecording()` instead of processing the button normally.

### 7. File Changes

| File | Change |
|------|--------|
| **New:** `Services/Input/MacroRecorder.swift` | Event tap setup, recording state machine, event-to-step conversion, post-processing |
| `Views/Macros/MacroEditorSheet.swift` | Add Record/Stop button, recording overlay UI, wire to MacroRecorder |
| `Services/Mapping/MappingEngine.swift` | Check `isRecording` flag to intercept stop-recording button |
| `Services/ServiceContainer.swift` | Add `MacroRecorder` to container (or create as local to the sheet) |

### 8. Edge Cases

- **Recording own controller output**: If the user presses a mapped controller button during recording, `InputSimulator` fires synthetic key events. The self-event filter (Section 2) must reliably suppress these to avoid recording the controller's own output.
- **Accessibility permission**: Already required for the app to function. The same TCC entitlement covers `CGEventTap` creation with `.listenOnly`.
- **Secure input fields**: macOS blocks event taps when secure text entry is active (e.g., password fields). The recorder should detect this (`CGEventTapIsEnabled` returns false) and show a warning.
- **Very long recordings**: Cap at a reasonable step limit (e.g., 500 steps) to prevent memory issues and unwieldy macros.
- **App not frontmost during recording**: The tap is session-wide, so it captures events in any app. This is the desired behavior — recording a workflow in another app.

### 9. Privacy Considerations

The event tap captures all keyboard input system-wide, including in password fields (except secure input). Mitigations:

- Recording requires explicit user action (pressing Record)
- Clear visual indicator that recording is active (pulsing red dot, changed window state)
- Recorded steps are only stored locally in the profile config
- Auto-stop after a configurable timeout (e.g., 5 minutes) to prevent accidental indefinite recording
- Secure input fields are automatically excluded by macOS
