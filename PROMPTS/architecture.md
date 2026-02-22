# Architecture Patterns

Constraints for the service layer, threading, and controller pipeline.

---

## Controller input normalization

Three different input backends (GameController framework, IOKit HID, Generic HID fallback) all normalize to the same `ControllerButton` enum and callback interface. Any new input source must follow this pattern: normalize to `ControllerButton`, feed into `MappingEngine`. The mapping engine never knows which backend produced the input.

**Why tests can't catch this:** The normalization contract is an architectural boundary. You can test each backend independently, but the constraint "all backends must normalize to the same interface" is a design rule that applies to backends that don't exist yet.

---

## MappingEngine is the single point of action dispatch

All button-to-action mapping flows through `MappingEngine`. This includes single press, long hold, double tap, chords, sequences, layers, macros, scripts, and system commands. No other component should directly call `InputSimulator` in response to controller input.

---

## Threading: controller callbacks arrive on arbitrary threads

`ControllerService` receives callbacks from GameController/IOKit on arbitrary threads. All state mutations and UI updates must be dispatched to the main thread. The `MappingEngine` processes inputs and dispatches actions, but any state it reads (active profile, layer state) must be thread-safe.

---

## Layers are hold-to-activate

Layers use a hold-to-activate model: while the activator button is held, the layer's alternate mappings are active. When released, mappings revert to the base layer. Buttons not mapped in a layer fall through to the base layer. A button assigned as a layer activator cannot have any other mapping (in any layer).

---

## Script execution is sandboxed

Scripts run in a JavaScriptCore context with a controlled API surface. The API is defined in `ScriptEngine` and exposed via `ScriptContext`. Scripts cannot access the file system, network, or any system resource not explicitly provided through the API. The `MockInputSimulator` is used for test execution so scripts can be tested without side effects.

---

## Profile auto-switching via linked apps

Profiles can be linked to application bundle identifiers. When the frontmost app changes, `AppMonitor` notifies `ProfileManager`, which switches to the profile linked to that app (if any). When the linked app loses focus, the profile reverts to the previous one. This is a stack, not a simple swap — nested app switches restore correctly.
