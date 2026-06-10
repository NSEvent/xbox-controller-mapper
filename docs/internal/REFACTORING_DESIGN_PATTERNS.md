# Design Pattern Refactoring Plan

Three Gang of Four refactors identified during a codebase survey. Ordered by ROI: each is independently shippable, low-risk, and addresses a real smell rather than adding pattern ceremony.

## 1. Template Method — collapse the custom decoder boilerplate

**Effort:** A few hours. **Risk:** None (pure code reduction).

### The smell

~29 structs implement the same `init(from decoder:)` skeleton: open a keyed container, `decodeIfPresent` each field with a fallback default, assign. The pattern is documented as deliberate in `.claude/CLAUDE.md` (graceful degradation on schema drift), but the mechanical repetition is ~200 lines of noise.

Affected files (non-exhaustive):

- `XboxControllerMapper/XboxControllerMapper/Models/KeyMapping.swift:214-229`
- `XboxControllerMapper/XboxControllerMapper/Models/ChordMapping.swift:58-72`
- `XboxControllerMapper/XboxControllerMapper/Models/SequenceMapping.swift:68-81`
- `XboxControllerMapper/XboxControllerMapper/Models/GestureMapping.swift:89-107`
- `XboxControllerMapper/XboxControllerMapper/Models/JoystickSettings.swift:271-350`
- `XboxControllerMapper/XboxControllerMapper/Models/DualSenseLEDSettings.swift`
- `XboxControllerMapper/XboxControllerMapper/Models/QuickText.swift` (QuickText, AppBarItem, WebsiteLink, OnScreenKeyboardSettings)
- Plus the nested types: `LongHoldMapping`, `DoubleTapMapping`, `RepeatMapping`, `ModifierFlags`, `CodableColor`, `PlayerLEDs`

### The refactor

Introduce a `DefaultableCodable` protocol extension with a helper that wraps the `decodeIfPresent ?? default` pattern. Each struct's decoder collapses to one line per field.

```swift
protocol DefaultableCodable: Codable {
    associatedtype CodingKeys: CodingKey
}

extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ key: K, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
```

Per-struct decoder before/after:

```swift
// Before (KeyMapping)
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try c.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
    modifiers = try c.decodeIfPresent(ModifierFlags.self, forKey: .modifiers) ?? ModifierFlags()
    longHoldMapping = try c.decodeIfPresent(LongHoldMapping.self, forKey: .longHoldMapping)
    // ... 6 more
}

// After
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try c.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
    modifiers = try c.decode(.modifiers, default: ModifierFlags())
    longHoldMapping = try c.decodeIfPresent(LongHoldMapping.self, forKey: .longHoldMapping)
    // ... 6 more (optionals stay decodeIfPresent; defaulted fields use the new helper)
}
```

### Acceptance criteria

- All existing config files load identically (round-trip a real `~/.controllerkeys/config.json` through the new code; diff the resulting `Configuration` struct).
- No new `decode(_:forKey:)` strict calls introduced (those would break backward compat — only `Profile.id` may stay strict).
- Line count in the affected files drops by ≥150.

### Out of scope

- Don't touch `Profile.swift`'s custom encoder (still needs explicit `encode` calls for forward compat).
- Don't introduce a macro — Swift macros add build complexity not warranted here.

---

## 2. Memento — profile snapshots and undo

**Effort:** Half a day for the model + manager; another half for UI. **Risk:** Low (adds a new system; doesn't change save/load semantics).

### The smell

`ProfileManager.swift:368-402` already protects against config corruption via the `loadSucceeded` flag and keeps the last 5 backups on disk at `~/.controllerkeys/backups/`. But the backup system is invisible to users:

- No in-memory snapshot stack
- No "restore to checkpoint" API
- No way to undo a destructive edit (e.g., accidentally deleting a profile or wiping mappings)

The infrastructure exists; the UX gap is real. Users on Discord have asked for undo.

### The refactor

Wrap the existing backup logic in a proper Memento. Snapshot is created automatically before destructive operations and on a debounced timer. UI surfaces the snapshot list in Settings.

```swift
struct ProfileSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let reason: String              // "before delete profile 'Gaming'", "auto-backup", "before import"
    let configuration: Configuration
}

extension ProfileManager {
    func createSnapshot(reason: String) { /* push to stack, evict if > maxSnapshots */ }
    func availableSnapshots() -> [ProfileSnapshot]
    func restoreSnapshot(_ snapshot: ProfileSnapshot) {
        createSnapshot(reason: "before restore to \(snapshot.timestamp)")
        applyConfiguration(snapshot.configuration)
        saveConfiguration()
    }
}
```

Snapshot triggers (call sites):

- Before `deleteProfile(_:)`
- Before `importProfile(from:)`
- Before bulk mapping edits (community profile apply)
- Auto-snapshot every N minutes if config changed (debounced)

Persistence: keep the existing on-disk backup directory; promote each backup file to a `ProfileSnapshot` on load.

### Acceptance criteria

- Settings has a "History" tab listing snapshots with timestamp + reason.
- Restoring a snapshot creates a new "before restore" snapshot first (so restore is itself undoable).
- Snapshot count capped (default 20 in-memory, 5 on disk — match existing backup retention).
- No regression in `loadSucceeded` safety check.

### Out of scope

- Per-field undo (Cmd-Z in the mapping editor) — that's a different scope; build that as a separate feature on top of this if desired.
- Cloud sync of snapshots.

---

## 3. Strategy — joystick output modes

**Effort:** A day. **Risk:** Medium (touches hot input path; needs careful regression testing).

### The smell

`JoystickSettings.StickMode` has 5 variants (`none`, `mouse`, `scroll`, `wasdKeys`, `arrowKeys`), each with distinct math: deadzone shape, sensitivity multiplier, acceleration curve exponent, output kind (mouse delta vs. scroll delta vs. key event). Today the dispatch lives in `MappingEngine+JoystickHandler.swift` as branching logic on the mode enum, with curve math inlined.

Adding a new mode (gyro aiming, PS5 adaptive trigger as analog input, joystick-as-touchpad-pan) means editing the handler and remembering all the curve/deadzone/output knobs.

### The refactor

Each mode becomes a `JoystickOutputStrategy`. The handler picks the strategy once per tick and delegates.

```swift
protocol JoystickOutputStrategy {
    func process(raw: CGPoint, dt: TimeInterval, settings: JoystickSettings) -> JoystickOutput
}

enum JoystickOutput {
    case moveMouse(CGPoint)
    case scroll(CGPoint)
    case keyEvents([(CGKeyCode, Bool)])  // (keyCode, pressed)
    case none
}

struct MouseMovementStrategy: JoystickOutputStrategy { /* deadzone → multiplier → curve → moveMouse */ }
struct ScrollStrategy: JoystickOutputStrategy { /* same shape, different knobs */ }
struct KeyEmissionStrategy: JoystickOutputStrategy { let keys: DirectionalKeySet }
struct NoOpStrategy: JoystickOutputStrategy { func process(...) -> .none }

extension JoystickSettings.StickMode {
    func strategy() -> JoystickOutputStrategy {
        switch self {
        case .none:       return NoOpStrategy()
        case .mouse:      return MouseMovementStrategy()
        case .scroll:     return ScrollStrategy()
        case .wasdKeys:   return KeyEmissionStrategy(keys: .wasd)
        case .arrowKeys:  return KeyEmissionStrategy(keys: .arrows)
        }
    }
}
```

Handler becomes:

```swift
let output = settings.leftStickMode.strategy().process(raw: leftStick, dt: dt, settings: settings)
applyOutput(output)
```

### Acceptance criteria

- All existing stick modes behave identically (manual: mouse drift at rest, accel curve at full deflection, scroll boost on long pulls).
- Each strategy has unit tests for its curve math (input → expected output table).
- Adding a hypothetical `gyroAim` strategy requires zero changes outside the new file + the enum case.

### Out of scope

- Don't refactor the touchpad input path in this pass — touchpad has its own settings cluster (`touchpadSensitivity`, `touchpadPanSensitivity`, etc.) and distinct call sites. Separate task.
- Don't unify with trigger handling.

---

## Skipped (considered, not worth it)

- **Command pattern for action dispatch** — already implemented well in `Services/Mapping/ActionCommand.swift` via `ActionCommand` protocol + `ActionCommandFactory`. Don't re-pattern.
- **Builder for `Profile.init`** — 18 parameters looks scary, but ~all have defaults; the common call is `Profile(name: "Unnamed")`. Builder would add ceremony without solving real pain.
- **Adapter for the three controller backends** — real opportunity, but `ControllerService` is 1736 lines and the refactor is invasive. Park this until a fourth backend (Xbox GDK, PS5 native) actually arrives.
- **Facade split of `OnScreenKeyboardManager`** (1640 lines) — would help testability, but big lift with no immediate user-facing payoff. Revisit if/when that file becomes a maintenance pain.
