# Input Pipeline Architecture Review

> Living document for iterating on the ControllerKeys input pipeline design.
> Generated from deep codebase analysis. Both human and AI will refine this.

---

## Current Pipeline Overview

```
HARDWARE INPUT
    |
    v
+---------------------------+     Thread: GameController callback
| ControllerService         |     (dispatches to controllerQueue)
| - Button state tracking   |
| - Chord detection window  |
| - Touchpad delta capture  |
| - Motion rate capture     |
+---------------------------+
    |
    |  Callbacks: onButtonPressed, onChordDetected,
    |             onTouchpadMoved, onMotionGesture
    v
+---------------------------+     Thread: inputQueue (buttons)
| MappingEngine             |              pollingQueue (analog 120Hz)
| - Sequence tracking       |
| - Layer activation        |
| - Long-hold timers        |
| - Double-tap windows      |
| - Policy delegation       |
+---------------------------+
    |
    |  Delegates to policies:
    |    ButtonPressOrchestrationPolicy
    |    ButtonInteractionFlowPolicy
    |    ButtonMappingResolutionPolicy
    |    MouseClickLocationPolicy
    v
+---------------------------+     Thread: inputQueue
| MappingActionExecutor     |
| - Priority dispatch:      |
|   1. SystemCommand        |
|   2. Macro                |
|   3. Script               |
|   4. KeyPress/Modifier    |
+---------------------------+
    |
    v
+---------------------------+     Thread: keyboardQueue (keys)
| InputSimulator            |              mouseQueue (mouse/scroll)
| - CGEvent posting         |
| - Modifier ref counting   |
| - Sub-pixel mouse track   |
| - Macro step execution    |
+---------------------------+
    |
    v
  macOS HID Event Tap (.cghidEventTap)
```

---

## What's Working Well

### 1. Policy Pattern (Excellent)
Four pure-function policy structs handle all mapping decisions:
- `ButtonPressOrchestrationPolicy` — UI interceptions (on-screen keyboard, laser pointer, directory navigator)
- `ButtonInteractionFlowPolicy` — hold-path vs press-path, release behavior
- `ButtonMappingResolutionPolicy` — which mapping applies given active layers
- `MouseClickLocationPolicy` — zoom-aware click positioning

These are stateless, testable, and composable. **This is the best pattern in the codebase.**

### 2. ExecutableAction Consistency
All mapping types (KeyMapping, ChordMapping, SequenceMapping, GestureMapping) share identical action fields via the `ExecutableAction` protocol. MappingActionExecutor treats them uniformly. No special-casing.

### 3. Queue Separation for Latency
Keyboard and mouse events use separate serial queues. Key simulation uses `usleep()` for timing — if this ran on the mouse queue, cursor movement would stutter. Good design choice.

### 4. Modifier Reference Counting
Multiple buttons can independently hold the same modifier key. The ref-counting system correctly posts key-down only on 0→1 and key-up only on 1→0.

---

## What's Not Clean

### Issue 1: Two-Phase Button Processing Splits State

A button press flows through **two separate state machines** in **two services**:

**Phase 1 — ControllerService** (chord detection):
```
buttonPressed() → add to capturedButtonsInWindow → start chordWindow timer
                  → if another button arrives before timer, detect chord
                  → processChordOrSinglePress() fires callbacks
```

**Phase 2 — MappingEngine** (mapping resolution):
```
handleButtonPressed() → sequence tracking → layer check → policy resolution → execute
```

**The problem:** State for a single button press is split across `ControllerStorage` (timestamps, captured buttons, chord state) and `EngineState` (active mappings, held buttons, timers). Understanding the full lifecycle of one button press requires reading two files, two state containers, and tracing callbacks between them.

**Where to look:**
- `ControllerService.swift:854-963` — chord state machine
- `MappingEngine.swift:419-593` — button press handling
- `MappingEngineState.swift` — held buttons, timers, sequence state

### Issue 2: Analog Inputs Have Inconsistent Flow Patterns

| Input Type | Event Source | Processing Queue | Movement Dispatch |
|-----------|-------------|-----------------|-------------------|
| **Buttons** | GameController callback → controllerQueue | inputQueue | keyboardQueue |
| **Left Stick** | GameController callback → cached in storage | pollingQueue (120Hz timer reads cache) | mouseQueue |
| **Right Stick** | Same as left stick | pollingQueue | mouseQueue |
| **Touchpad (1-finger)** | GameController callback → controllerQueue | Callback fires directly (no queue hop) | mouseQueue |
| **Touchpad (2-finger)** | Same, computed delta | pollingQueue callback | mouseQueue |
| **Motion/Gyro** | GameController callback → cached in storage | pollingQueue (120Hz reads cache) | mouseQueue |
| **Motion Gestures** | Peak-detection state machine in ControllerService | inputQueue | keyboardQueue |

**The problem:** Three different patterns for getting data from controller to output:
1. **Event-driven** (buttons): callback → queue → process → execute
2. **Poll-cached** (joystick, gyro): callback stores value → timer reads it → process → execute
3. **Hybrid** (touchpad): callback computes delta → sometimes polled, sometimes direct callback

There's no unified `InputSource` abstraction. Each input type is wired up ad-hoc in `MappingEngine.setupBindings()`, which is a 130-line method of heterogeneous callback registration.

**Where to look:**
- `MappingEngine.swift:159-291` — setupBindings()
- `JoystickHandler.swift:36-65` — processJoysticks() polls cached values
- `TouchpadInputHandler.swift:12-74` — touchpad processes callback directly
- `ControllerService+Motion.swift:71-138` — motion gesture state machine

### Issue 3: Action Dispatch is Priority-Hardcoded, Not Polymorphic

```swift
// MappingActionExecutor.swift:160-176
func executeAction(_ action: any ExecutableAction, ...) -> String {
    if let feedback = systemCommandHandler.executeIfPossible(action) { return feedback }
    if let feedback = macroHandler.executeIfPossible(action) { return feedback }
    if let feedback = scriptHandler.executeIfPossible(action) { return feedback }
    return keyOrModifierHandler.execute(action)
}
```

**The problem:** This is a manually-written chain-of-responsibility with:
- Hardcoded priority order (systemCommand > macro > script > keyPress)
- Each handler has its own `executeIfPossible()` signature (inconsistent — script handler takes extra `button` and `pressType` params, others don't)
- The protocol `ExecutableAction` defines WHAT can be executed but not HOW — no `execute()` contract
- Adding a new action type means editing this cascade

**Contrast with the policy pattern**, which IS cleanly separated. The action dispatch layer doesn't match the same quality level.

### Issue 4: InputSimulator Does Too Many Things

InputSimulator (1,444 lines) is a "kitchen sink" for output:
- Keyboard simulation (press, hold, release, modifiers)
- Mouse simulation (move, click, drag, warp)
- Scroll simulation (wheel, zoom shortcuts)
- Macro execution (step-by-step interpretation)
- Media key simulation
- Accessibility zoom handling
- Application launching (via NSWorkspace)
- URL opening

**Macro execution is particularly misplaced** — InputSimulator shouldn't know about shell commands, webhooks, or OBS. It delegates back to SystemCommandExecutor via a closure (`systemCommandHandler`), creating a circular dependency:

```
MappingActionExecutor → InputSimulator.executeMacro()
                           → step is .shellCommand
                           → systemCommandHandler closure
                           → SystemCommandExecutor.execute()
```

**Where to look:**
- `InputSimulator.swift:1249-1376` — macro execution with system command callbacks
- `MappingActionExecutor.swift:116` — closure wiring

### Issue 5: Thread Boundaries Are Implicit

There's no explicit declaration of "this function runs on queue X." Instead:
- Functions dispatch to queues internally
- Callers don't know which queue they'll end up on
- `nonisolated` functions with locked state bypass actor isolation

**Example confusion:**
- `MappingEngine.handleButtonPressed()` is `nonisolated` but accesses `state.lock`
- It's called from `inputQueue` via callback, but nothing enforces this
- If accidentally called from another queue, it would still "work" but violate assumptions

**Where to look:**
- `MappingEngine.swift:458` — `nonisolated func handleButtonPressed()`
- `JoystickHandler.swift:36` — `nonisolated func processJoysticks()`

### Issue 6: Gesture Detection is Fragmented

Three separate gesture detection implementations:
1. **Chord detection** — in ControllerService (button-level, uses timer + captured set)
2. **Sequence detection** — in MappingEngine (button-level, step-matching with timeout)
3. **Motion gestures** — in ControllerService+Motion (gyro-level, peak-detection state machine)
4. **Touchpad gestures** — in ControllerService+Touchpad (tap/long-tap/two-finger, custom state tracking)

Each has its own state machine with different:
- State enums (or no enum at all — chord uses booleans)
- Timeout mechanisms (DispatchWorkItem vs. CFAbsoluteTimeGetCurrent comparison)
- Completion callbacks (closure vs. direct function call)

No shared `GestureDetector` abstraction.

---

## Proposed Design Improvements

### Proposal A: Unified Input Event Type

Replace heterogeneous callbacks with a single event type:

```swift
enum ControllerInputEvent {
    // Discrete events
    case buttonDown(ControllerButton, timestamp: CFAbsoluteTime)
    case buttonUp(ControllerButton, timestamp: CFAbsoluteTime, holdDuration: TimeInterval)
    case chord(Set<ControllerButton>)
    case sequence([ControllerButton])
    case touchpadTap(fingers: Int)
    case touchpadLongTap(fingers: Int)
    case motionGesture(MotionGestureType)

    // Continuous events (polled)
    case joystickUpdate(stick: Stick, x: Float, y: Float)
    case touchpadMove(dx: Float, dy: Float)
    case touchpadGesture(TouchpadGestureEvent) // pan, pinch
    case gyroUpdate(pitchRate: Double, rollRate: Double)
}
```

**Benefit:** MappingEngine receives ONE event type. `setupBindings()` becomes a single event handler instead of 10+ separate callbacks. Testing is trivial — feed events, assert outputs.

**Trade-off:** Adds an enum allocation per event. At 120Hz polling that's ~960 allocs/sec — negligible on modern hardware.

### Proposal B: Command Pattern for Action Execution

Replace the hardcoded priority chain with self-contained action commands:

```swift
protocol ActionCommand {
    var feedbackString: String { get }
    func execute()
}

struct KeyPressCommand: ActionCommand {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let simulator: InputSimulatorProtocol

    func execute() {
        simulator.pressKey(keyCode, modifiers: modifiers)
    }
}

struct MacroCommand: ActionCommand {
    let macro: Macro
    let macroExecutor: MacroExecutor  // NEW: extracted from InputSimulator

    func execute() {
        macroExecutor.execute(macro)
    }
}

// Resolution: action → command
func resolveCommand(for action: ExecutableAction, context: ActionContext) -> ActionCommand {
    if let cmd = action.systemCommand {
        return SystemCommandAction(command: cmd, executor: systemCommandExecutor)
    }
    if let macroId = action.macroId, let macro = context.profile?.macros.first(where: { $0.id == macroId }) {
        return MacroCommand(macro: macro, macroExecutor: macroExecutor)
    }
    if let scriptId = action.scriptId, let script = context.profile?.scripts.first(where: { $0.id == scriptId }) {
        return ScriptCommand(script: script, engine: scriptEngine, trigger: context.trigger)
    }
    return KeyPressCommand(keyCode: action.keyCode!, modifiers: action.modifiers.cgEventFlags, simulator: inputSimulator)
}
```

**Benefit:** Each action is self-contained. New action types add a new struct, not a new `if` branch. Testing is isolated.

### Proposal C: Extract MacroExecutor from InputSimulator

Move macro step interpretation out of InputSimulator:

```swift
class MacroExecutor {
    private let keyboardSimulator: KeyboardSimulating
    private let systemCommandExecutor: SystemCommandExecuting
    private let executionQueue: DispatchQueue

    func execute(_ macro: Macro) {
        executionQueue.async {
            for step in macro.steps {
                switch step {
                case .press(let mapping):
                    self.keyboardSimulator.pressKeyMapping(mapping)
                case .shellCommand(let cmd, let terminal):
                    self.systemCommandExecutor.execute(.shellCommand(command: cmd, inTerminal: terminal))
                // ... etc
                }
            }
        }
    }
}
```

**Benefit:** InputSimulator becomes purely about CGEvent posting. No more circular callback through `systemCommandHandler`. MacroExecutor explicitly depends on both keyboard and system command capabilities.

### Proposal D: Queue Ownership Documentation + Annotations

Add queue contract annotations:

```swift
/// Processes a button press and resolves the appropriate action.
/// - Precondition: Must be called on `inputQueue`
/// - Posts results to: `keyboardQueue` (key actions) or `mouseQueue` (click actions)
@_documentation(visibility: internal)
nonisolated func handleButtonPressed(_ button: ControllerButton, ...) {
    dispatchPrecondition(condition: .onQueue(inputQueue)) // DEBUG assertion
    // ...
}
```

**Benefit:** Makes threading contracts explicit and verifiable. Low cost, high documentation value.

### Proposal E: Unified Gesture State Machine

Create a reusable gesture detector:

```swift
/// Generic time-windowed pattern matcher.
class GestureDetector<Token: Hashable> {
    enum State { case idle, accumulating, cooldown }

    private var state: State = .idle
    private var accumulated: [Token] = []
    private var windowStart: CFAbsoluteTime = 0
    private let windowDuration: TimeInterval
    private let onMatch: ([Token]) -> Void

    func feed(_ token: Token, at time: CFAbsoluteTime) {
        switch state {
        case .idle:
            accumulated = [token]
            windowStart = time
            state = .accumulating
        case .accumulating:
            if time - windowStart > windowDuration {
                flush()
                accumulated = [token]
                windowStart = time
            } else {
                accumulated.append(token)
            }
        case .cooldown:
            break
        }
    }

    func flush() {
        onMatch(accumulated)
        accumulated = []
        state = .cooldown
    }
}
```

Used for chord detection (tokens = buttons), sequence detection (tokens = buttons with ordering), and potentially touchpad tap patterns.

**Benefit:** One tested state machine replaces three hand-rolled ones.

**Trade-off:** Chord detection has nuances (chord window timing, partial release) that may not fit a generic detector cleanly. May need to specialize.

---

## Prioritized Improvement Plan

### Tier 1: High Impact, Low Risk — ALL COMPLETED
| # | Change | Status | Files |
|---|--------|--------|-------|
| 1 | Extract MacroExecutor from InputSimulator | **Done** | MacroExecutor.swift (142 lines), InputSimulator.swift (~140 lines removed) |
| 2 | Add `dispatchPrecondition` assertions on queue-sensitive functions | **Done** | MappingEngine, JoystickHandler, TouchpadInputHandler |
| 3 | Normalize action handler signatures via Command pattern | **Done** | ActionCommand.swift (192 lines), MappingActionExecutor.swift rewritten |

### Tier 2: Medium Impact, Medium Risk — ALL COMPLETED
| # | Change | Status | Files |
|---|--------|--------|-------|
| 4 | Introduce ControllerInputEvent enum | **Done** | ControllerInputEvent.swift + MappingEngine.handleControllerInput() |
| 5 | Command pattern for action execution | **Done** | ActionCommandFactory with 6 concrete commands |
| 6 | Split InputSimulator into KeyboardSimulator + MouseSimulator | **Deferred** | Macro code extracted; keyboard/mouse split not yet needed |

### Tier 3: Aspirational, Higher Risk — PARTIALLY COMPLETED
| # | Change | Status | Files |
|---|--------|--------|-------|
| 7 | Unified GestureDetector protocol | **Done** | GestureDetector.swift (GestureDetecting protocol), SequenceDetector.swift, MotionGestureDetector.swift |
| 8 | Move chord detection from ControllerService to MappingEngine | **Deferred** | Decision: chord detection stays in ControllerService (see Decisions) |
| 9 | Event bus for action side-effects | **Not started** | Future work |

### Test Coverage Added
- **ActionLayerCharacterizationTests** — 10 tests (priority dispatch, macro isolation, OSK notification)
- **PipelineCharacterizationTests** — 9 tests (button press, chord, sequence, motion, touchpad, queue routing)
- **ControllerInputEventTests** — 8 tests (event enum equality, associated values)
- **SequenceDetectorTests** — 7 tests (step matching, timeout, reset, concurrent sequences)
- **MotionGestureDetectorTests** — 7 tests (peak detection, settling, cooldown, axis independence)
- **ModifierRefCountingTests** — 11 tests (overlapping holds, underflow protection, stress)

---

## Decisions Made

1. **Chord detection stays in ControllerService.** It's hardware timing ("were these pressed together?"), not mapping logic ("what do they mean?"). ControllerService emits `ControllerInputEvent.chord` events. MappingEngine interprets them.

2. **120Hz polling for touchpad is fine.** Single-finger is already event-driven (low latency), polling handles momentum smoothing. The inconsistency is in callback registration, not in the actual data flow. The `ControllerInputEvent` enum fixes the registration inconsistency.

3. **No Swift Concurrency adoption.** NSLock + DispatchQueue is the right choice for real-time input (120Hz polling, microsecond latency). Structured concurrency's scheduling overhead isn't suitable here.

4. **Protocols as clean as possible without performance impact.** At 120Hz max (8.33ms per frame), protocol dispatch overhead is negligible. Use protocols for testability and clean boundaries.

---

## Reference: Thread/Queue Map

```
controllerQueue     - GameController callbacks, chord window timer
                      Owner: ControllerService
                      QoS: .userInteractive

inputQueue          - Button press/release handling, sequence tracking
                      Owner: MappingEngine
                      QoS: .userInteractive

pollingQueue        - 120Hz joystick/touchpad/gyro polling
                      Owner: MappingEngine (JoystickHandler)
                      QoS: .userInteractive

keyboardQueue       - Key simulation, macro execution
                      Owner: InputSimulator
                      QoS: .userInteractive

mouseQueue          - Mouse movement, clicks, scroll
                      Owner: InputSimulator
                      QoS: .userInteractive

scriptQueue         - JavaScript execution (serializes JSContext)
                      Owner: ScriptEngine
                      QoS: .userInitiated
```

---

*Last updated: 2026-02-22*
*Status: Tier 1 and Tier 2 implemented. 52 new tests added. All regression tests passing (14/14).*
