# Plugin / Scripting System

Embed a lightweight scripting engine so users can write conditional logic and custom actions triggered by controller input.

## Motivation

The current action model is declarative: button → key/macro/system-command. This works well for static mappings but breaks down when the desired behavior depends on runtime context:

- "If Spotify is playing, send media pause; otherwise send spacebar"
- "Cycle through a list of URLs on each press"
- "Send a different Slack emoji based on which app is focused"
- "Toggle a boolean state and send different keys on odd/even presses"
- "Read clipboard contents, transform them, and type the result"

Macros handle linear sequences. Shell commands handle arbitrary computation but are heavy (process spawn per invocation, no state, no access to app context). A scripting system fills the gap: lightweight, stateful, context-aware, and fast enough for 120Hz input loops.

## Language Choice: JavaScript (JavaScriptCore)

**Why JavaScriptCore:**
- Ships with macOS — no bundled runtime, no binary size increase
- `JavaScriptCore` framework is a first-party Apple API, stable since macOS 10.5
- Most users who would write scripts already know JavaScript
- Fast startup (< 1ms to create a context), low memory overhead
- Sandboxed by default — no filesystem/network access unless explicitly bridged
- Supports `async/await` in modern macOS versions

**Alternatives considered:**

| Language | Pros | Cons |
|----------|------|------|
| Lua | Tiny, designed for embedding, fast | Less known by target users, no macOS framework |
| Python | Very popular | Heavy runtime, slow startup, not bundleable |
| AppleScript | Native macOS | Verbose syntax, poor developer experience |
| Custom DSL | Tailored to use case | Maintenance burden, no ecosystem, learning curve |

## Data Model

### Script

```swift
struct Script: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var source: String = ""             // JavaScript source code
    var description: String?            // Optional user notes
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
}
```

### Profile Integration

```swift
struct Profile {
    // ... existing fields ...
    var scripts: [Script]               // decodeIfPresent ?? []
}
```

Scripts are stored at the profile level (same as macros). A script is referenced by UUID from any `ExecutableAction`:

```swift
protocol ExecutableAction {
    var macroId: UUID? { get }
    var scriptId: UUID? { get }         // NEW
    var systemCommand: SystemCommand? { get }
    var hint: String? { get }
}
```

### JSON Example

```json
{
  "scripts": [
    {
      "id": "...",
      "name": "Smart Spacebar",
      "source": "if (app.bundleId === 'com.spotify.client') { press('space'); } else { press('space', { command: true }); }",
      "description": "Media pause in Spotify, Cmd+Space elsewhere"
    }
  ],
  "buttonMappings": {
    "a": { "scriptId": "..." }
  }
}
```

## Script Runtime

### ScriptEngine

```
Location: new file — Services/Scripting/ScriptEngine.swift
```

```swift
class ScriptEngine {
    private let context: JSContext
    private var scriptState: [UUID: JSValue]  // Per-script persistent state

    init() {
        context = JSContext()
        installAPI()
    }

    func execute(script: Script, trigger: ScriptTrigger) -> ScriptResult {
        // Set trigger context (which button, press type, etc.)
        // Evaluate script source
        // Return result (success/error)
    }
}
```

**Lifecycle:**
- One `ScriptEngine` per `MappingEngine` instance (created at startup, destroyed on shutdown)
- The `JSContext` persists across invocations — scripts can store state in global variables
- Each script gets its own namespace via `scriptState[script.id]` to prevent cross-script pollution
- Scripts execute synchronously on `inputQueue` (same queue as button handling) to avoid race conditions
- Execution timeout: 100ms hard cap per invocation to prevent blocking the input pipeline

### ScriptTrigger (Context Passed to Scripts)

```swift
struct ScriptTrigger {
    let button: ControllerButton
    let pressType: PressType        // .press, .release, .longHold, .doubleTap
    let holdDuration: TimeInterval?
    let timestamp: Date
}
```

Exposed to JS as a `trigger` global object.

## JavaScript API

### Core Input Simulation

```javascript
// Key press (tap)
press(keyCode)                          // e.g., press(49) for spacebar
press(keyCode, { command, option, shift, control })

// Key hold
hold(keyCode, durationSeconds)
hold(keyCode, durationSeconds, { command: true })

// Mouse click
click()                                 // left click
click("right")
click("middle")

// Type text
type("hello world")                     // character-by-character
paste("hello world")                    // via clipboard

// Key by name (convenience)
pressKey("space")
pressKey("return")
pressKey("tab")
pressKey("escape")
pressKey("f5")
// ... all named keys
```

Implementation: these functions call back into `InputSimulatorProtocol` methods via `JSContext` block bindings.

### Application Context

```javascript
// Frontmost application
app.name          // "Safari"
app.bundleId      // "com.apple.Safari"

// Check specific app
app.is("com.spotify.client")   // boolean
```

Implementation: reads from `AppMonitor.frontmostBundleId` / `frontmostAppName` (already tracked, synced to `EngineState`).

### System Integration

```javascript
// Clipboard
clipboard.get()               // returns string
clipboard.set("new content")

// Shell command (async, returns stdout)
let result = shell("date +%H")

// Open URL
openURL("https://example.com")

// Launch app
openApp("com.apple.Safari")
openApp("com.apple.Safari", { newWindow: true })

// Variable expansion (reuses existing VariableExpander)
let expanded = expand("{date} {time} - {app}")
```

### Persistent State

```javascript
// Per-script persistent state (survives across invocations, cleared on profile switch)
state.get("counter")              // returns value or undefined
state.set("counter", 42)
state.toggle("isActive")          // boolean toggle, returns new value

// Example: cycle through values on each press
let urls = ["https://a.com", "https://b.com", "https://c.com"]
let i = (state.get("index") || 0) % urls.length
openURL(urls[i])
state.set("index", i + 1)
```

Implementation: `scriptState[scriptId]` dictionary in `ScriptEngine`, exposed as a `state` JS object with get/set methods.

### Feedback

```javascript
// Haptic feedback
haptic()                          // default tap
haptic("light")
haptic("heavy")

// Visual feedback (ActionFeedbackIndicator)
notify("Switched to mode B")     // brief floating HUD text

// Delay (use sparingly — blocks input queue)
delay(0.1)                        // seconds
```

### Trigger Context

```javascript
// Available in every script invocation
trigger.button      // "a", "leftBumper", "dpadDown", etc.
trigger.pressType   // "press", "release", "longHold", "doubleTap"
trigger.holdDuration // seconds (only for longHold/release)
```

### Logging

```javascript
log("debug message")              // Writes to InputLogService for debugging
log("value is:", someVariable)
```

Visible in the app's input log view (existing UI).

## Execution Pipeline

### Integration with MappingExecutor

Add a new handler in the `MappingExecutor` strategy chain:

```
executeAction(action):
    1. SystemCommandActionHandler.executeIfPossible()   // systemCommand != nil
    2. MacroActionHandler.executeIfPossible()            // macroId != nil
    3. >>> ScriptActionHandler.executeIfPossible() <<<   // scriptId != nil  — NEW
    4. KeyOrModifierActionHandler.execute()              // fallback
```

```swift
private struct ScriptActionHandler {
    let scriptEngine: ScriptEngine

    func executeIfPossible(_ action: any ExecutableAction, profile: Profile?,
                           button: ControllerButton, pressType: PressType) -> String? {
        guard let scriptId = action.scriptId, let profile,
              let script = profile.scripts.first(where: { $0.id == scriptId }) else { return nil }

        let trigger = ScriptTrigger(button: button, pressType: pressType, ...)
        let result = scriptEngine.execute(script: script, trigger: trigger)

        switch result {
        case .success(let hintOverride):
            return hintOverride ?? action.hint ?? script.name
        case .error(let message):
            log("Script error: \(message)")
            return "Script Error"
        }
    }
}
```

### Threading

Scripts run on `inputQueue` (same serial queue as all button handling). This guarantees:
- No concurrent script executions
- Script state mutations are safe without locks
- Scripts see consistent `app.bundleId` state

The 100ms timeout prevents a bad script from blocking input indefinitely. If a script times out, the engine cancels it and logs an error.

### Timeout Enforcement

```swift
func execute(script: Script, trigger: ScriptTrigger) -> ScriptResult {
    let deadline = DispatchTime.now() + .milliseconds(100)
    var timedOut = false

    // Set a timer that sets an exception on the JSContext
    let timer = DispatchSource.makeTimerSource(queue: inputQueue)
    timer.schedule(deadline: deadline)
    timer.setEventHandler { [weak context] in
        // JSContext doesn't have a clean cancel API; set a flag
        // and check it in long-running bridged functions
        timedOut = true
    }
    timer.resume()

    context.evaluateScript(script.source)

    timer.cancel()

    if timedOut {
        return .error("Script timed out (100ms limit)")
    }
    // ...
}
```

Note: JavaScriptCore doesn't support true preemptive cancellation. The timeout flag is checked in bridged functions (`delay()`, `shell()`, etc.) to bail out early. Pure JS computation that exceeds 100ms will run to completion. This is acceptable because controller scripts should be trivially short.

## UI Design

### Scripts Tab

Add a **Scripts** tab to the main tab bar (after Macros).

```
┌─────────────────────────────────────────────┐
│ Scripts                                     │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ Smart Spacebar              [edit]  │    │
│  │ Media pause in Spotify, else...     │    │
│  ├─────────────────────────────────────┤    │
│  │ URL Cycler                  [edit]  │    │
│  │ Cycles through 5 URLs              │    │
│  ├─────────────────────────────────────┤    │
│  │ Clipboard Transform        [edit]  │    │
│  │ Uppercase clipboard text           │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ + New Script                         │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### Script Editor Sheet

```
┌────────────────────────────────────────────────┐
│ Edit Script                                    │
│                                                │
│ Name: [Smart Spacebar___________________]      │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ // Monospace code editor                   │ │
│ │ if (app.bundleId === 'com.spotify.client') │ │
│ │ {                                          │ │
│ │   press(49); // spacebar                   │ │
│ │ } else {                                   │ │
│ │   press(49, { command: true });            │ │
│ │ }                                          │ │
│ │                                            │ │
│ │                                            │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ Description: [________________________________]│
│                                                │
│  [API Reference]  [▶ Test]  [Cancel]  [Save]   │
└────────────────────────────────────────────────┘
```

**Code editor features:**
- Monospace font (`NSFont.monospacedSystemFont`)
- Basic syntax highlighting via `NSAttributedString` (keywords, strings, numbers, comments) — no need for a full editor framework
- Line numbers in gutter
- Tab key inserts 2 spaces (not focus-change)

**Test button:** Executes the script with a simulated trigger context and shows the result (success + any `log()` output, or error message) in a popover. No actual key simulation during test — `press()` calls are logged instead of executed.

**API Reference button:** Opens a popover or sheet with the full API documentation (all available functions, objects, and examples).

### Assigning Scripts to Buttons

In `ButtonMappingSheet`, extend the mapping type picker:

```
Action Type:  ● Key  ○ Macro  ○ System Command  ○ Script
                                                    ↑ NEW

Script: [ Smart Spacebar          ▼ ]
```

Same pattern as macro assignment — picker lists `profile.scripts` by name, stores `scriptId: UUID` in the mapping.

## Bundled Example Scripts

Ship 3-5 example scripts that demonstrate the API and common patterns:

### 1. Smart Media Key

```javascript
// Play/pause in media apps, spacebar elsewhere
const mediaApps = [
    "com.spotify.client",
    "com.apple.Music",
    "com.apple.TV"
];
if (mediaApps.includes(app.bundleId)) {
    pressKey("space");  // media apps use space for play/pause
} else {
    press(49, { command: true });  // Cmd+Space (Spotlight)
}
```

### 2. Clipboard Transformer

```javascript
// Uppercase clipboard contents and paste
let text = clipboard.get();
if (text) {
    clipboard.set(text.toUpperCase());
    press(9, { command: true });  // Cmd+V
    // Restore original after a brief delay
    delay(0.1);
    clipboard.set(text);
}
```

### 3. Press Counter with Feedback

```javascript
// Count presses and show every 10th
let count = (state.get("count") || 0) + 1;
state.set("count", count);
if (count % 10 === 0) {
    notify(`${count} presses!`);
    haptic("heavy");
} else {
    haptic("light");
}
```

### 4. App-Aware Arrow Keys

```javascript
// In Terminal: send Ctrl+N/P (history navigation)
// Elsewhere: send regular Up/Down arrows
if (app.bundleId === "com.apple.Terminal") {
    if (trigger.button === "dpadUp") {
        press(35, { control: true });  // Ctrl+P
    } else {
        press(45, { control: true });  // Ctrl+N
    }
} else {
    if (trigger.button === "dpadUp") {
        pressKey("up");
    } else {
        pressKey("down");
    }
}
```

### 5. Window Tiling Toggle

```javascript
// Toggle between left-half and right-half window tiling
let isLeft = state.toggle("leftTile");
if (isLeft) {
    // macOS Sequoia tiling: Ctrl+Globe+Left
    press(123, { control: true, globe: true });
    notify("← Left half");
} else {
    press(124, { control: true, globe: true });
    notify("→ Right half");
}
```

## Security Model

### Sandboxing

The `JSContext` has **no default access** to:
- Filesystem (no `require()`, no `import`, no `fs`)
- Network (no `fetch()`, no `XMLHttpRequest`)
- Process spawning (no `child_process`)
- Other apps' memory or state

Access is granted only through the explicitly bridged API functions listed above.

### shell() Safety

The `shell()` function is the most powerful bridge. Safeguards:
- Runs via `Process()` with `/bin/sh -c` (same as existing shell command system)
- Output is captured and returned as a string (stdout only, max 10KB)
- Execution timeout: 5 seconds (separate from the 100ms script timeout)
- `stderr` is discarded
- No stdin support

Consider adding a preference to disable `shell()` entirely for users who want a locked-down scripting environment.

### State Isolation

- Scripts in different profiles have completely separate state
- Profile switch clears all script state
- Scripts within the same profile share the `JSContext` but have per-script `state` namespaces
- One script cannot access another script's `state` object

## File Changes

| File | Change |
|------|--------|
| **New:** `Models/Script.swift` | `Script` struct |
| **New:** `Services/Scripting/ScriptEngine.swift` | JSContext management, API bridging, execution, timeout |
| **New:** `Services/Scripting/ScriptAPI.swift` | All bridged JS functions (`press`, `app`, `clipboard`, `state`, etc.) |
| **New:** `Views/Scripts/ScriptListView.swift` | Scripts tab, list of scripts with add/edit/delete |
| **New:** `Views/Scripts/ScriptEditorSheet.swift` | Code editor, test runner, API reference popover |
| **New:** `Resources/example-scripts/` | Bundled example `.js` files |
| `Models/Profile.swift` | Add `var scripts: [Script]`, CodingKeys, decode/encode |
| `Models/KeyMapping.swift` | Add `var scriptId: UUID?` to `ExecutableAction` protocol and all conforming types |
| `Services/Mapping/MappingActionExecutor.swift` | Add `ScriptActionHandler` to strategy chain |
| `Services/Mapping/MappingEngine.swift` | Create `ScriptEngine`, pass to `MappingExecutor` |
| `Services/ServiceContainer.swift` | Add `ScriptEngine` to container |
| `Views/Buttons/ButtonMappingSheet.swift` | Add "Script" option to mapping type picker |
| `Views/Chords/ChordMappingSheet.swift` | Add "Script" option |
| `Models/ProfileManager.swift` | Add CRUD methods for scripts |
| `Config.swift` | Add `scriptExecutionTimeout`, `shellCommandTimeout` constants |

## Future Extensions (v2+)

- **Script marketplace**: Community-contributed scripts via GitHub (same infrastructure as community profiles)
- **Event hooks**: Scripts that run on events beyond button presses — controller connect/disconnect, profile switch, app focus change, timer-based (cron-like)
- **Inter-script communication**: Shared state namespace for scripts that need to coordinate
- **Async execution**: Allow scripts to run off `inputQueue` for long-running operations (network requests, complex computation) without blocking input
- **Script debugging**: Breakpoints, step-through execution, variable inspector
- **TypeScript support**: Type definitions for the API, enabling autocomplete in external editors
