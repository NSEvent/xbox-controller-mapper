# Button Sequences / Combo Inputs

Trigger actions by pressing buttons in a specific order within a time window (e.g., Down, Down, A).

## Motivation

The app supports **chords** (simultaneous presses) and **double-tap** (same button twice), but has no way to express **ordered multi-button sequences**. Fighting games, emulators, and power-user workflows rely on muscle-memory combos — sequential inputs that feel natural on a controller. Sequences fill the gap between "press one button" and "hold two buttons at the same time."

Use cases:
- Productivity combos: Down+Down+A to open a specific app
- Text shortcuts: Left+Right+Left to paste a frequently-used snippet
- Easter eggs / fun bindings
- Game-style directional inputs for macros (quarter-circle motions approximated as D-pad sequences)

## Scope

- New `SequenceMapping` data type: ordered list of buttons + time window + action
- Sequence matching engine integrated into `MappingEngine`
- UI for creating, editing, and reordering sequences (new tab or section in Chords tab)
- Conflict detection with existing chords and double-taps
- Sequences support the same action types as chords: key+modifiers, macro, system command

Out of scope (v1):
- Analog stick directions as sequence inputs (only digital `ControllerButton` presses)
- Sequence "cancellation" inputs (pressing a wrong button mid-sequence resets it silently)
- Nested/overlapping sequences (first match wins)

## Data Model

### SequenceMapping

```swift
struct SequenceMapping: Codable, Identifiable, Equatable, ExecutableAction {
    var id: UUID = UUID()
    var steps: [ControllerButton]           // Ordered — [.dpadDown, .dpadDown, .a]
    var timeWindow: TimeInterval = 0.8      // Max time from first to last input
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags = ModifierFlags()
    var macroId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?
}
```

**Constraints:**
- `steps.count >= 2` (single-step sequences are just button mappings)
- `steps.count <= 8` (practical limit for memorizable combos)
- `timeWindow` range: 0.3s – 3.0s (default 0.8s)

### Profile Integration

```swift
struct Profile {
    // ... existing fields ...
    var sequenceMappings: [SequenceMapping]  // decodeIfPresent ?? []
}
```

Standard `decodeIfPresent` pattern — fully backward compatible.

### JSON Example

```json
{
  "sequenceMappings": [
    {
      "id": "...",
      "steps": ["dpadDown", "dpadDown", "a"],
      "timeWindow": 0.8,
      "keyCode": 0,
      "modifiers": { "command": true },
      "hint": "Open Terminal"
    }
  ]
}
```

## Sequence Detection Engine

### Input History Buffer

Add to `EngineState`:

```swift
struct ButtonEvent {
    let button: ControllerButton
    let timestamp: Date
}

// Ring buffer of recent presses, capped at longest sequence length across all active sequences
var inputHistory: [ButtonEvent] = []
var maxSequenceLength: Int = 0   // Recomputed on profile switch
```

### Matching Algorithm

On every `handleButtonPressed`, after the existing chord/double-tap/single-press classification, run the sequence matcher:

```
sequenceCheck(pressedButton):
    1. Append ButtonEvent(button, now) to inputHistory
    2. Prune events older than the longest timeWindow in active sequences
    3. For each SequenceMapping in profile.sequenceMappings (sorted longest-first):
        a. Extract the last N events from inputHistory where N = sequence.steps.count
        b. Check if the buttons match in order: events[i].button == sequence.steps[i]
        c. Check if (events[last].timestamp - events[first].timestamp) <= sequence.timeWindow
        d. If match:
            - Clear inputHistory (prevent re-triggering)
            - Cancel any pending single-tap or chord actions for involved buttons
            - Execute the sequence's action
            - Return (first match wins)
    4. No match: proceed with normal press handling
```

**Longest-first matching** ensures that if sequences `[A, B]` and `[A, B, C]` both exist, pressing A-B-C triggers the longer one, not the shorter one at step B.

### Integration Point in MappingEngine

The sequence check runs in `handleButtonPressed` on `inputQueue`, after the press is classified but **before** the single-tap action fires:

```
handleButtonPressed(button):
    1. beginButtonPress (layer check, profile check)
    2. resolveButtonPressOutcome (existing classification)
    3. >>> sequenceCheck(button) <<<    // NEW — if match, execute and return early
    4. Existing logic (hold mapping, long-hold timer, repeat timer, etc.)
```

This ordering means:
- Layer activators still take priority (checked in step 1)
- Sequences take priority over single-press actions
- Chords still take priority over sequences (chords fire from `handleChord`, a separate callback that runs before individual `handleButtonPressed` calls)

### Priority Order (Full)

```
1. Layer activator (always wins)
2. Chord (detected in ControllerService's chord window, fires handleChord)
3. Sequence (checked on each press in handleButtonPressed)
4. Double-tap (checked on release)
5. Long-hold (timer-based, fires after threshold)
6. Single-press (default fallback)
```

### Interaction with Existing Systems

**Chords vs. Sequences:**
Chords require simultaneous presses within 150ms. Sequences require ordered presses that may be spread over up to 3 seconds. They don't conflict temporally — if two buttons arrive within the chord window, it's a chord; if they arrive sequentially, the sequence matcher evaluates them.

Edge case: If a sequence starts with two buttons that also form a chord (e.g., sequence `[A, B, X]` and chord `{A, B}`), pressing A and B simultaneously triggers the chord. Pressing A, waiting, then pressing B, then X triggers the sequence. This is the correct behavior — the chord window (150ms) acts as the disambiguator.

**Double-tap vs. Sequences:**
A sequence `[A, A]` would look like a double-tap of A. Resolution: double-tap is checked on **release** and sequences are checked on **press**. The sequence `[A, A]` would match first (on the second A press), preempting the double-tap. If this is undesirable, sequences could be restricted to require at least 2 distinct buttons.

Recommendation: **disallow sequences where all steps are the same button** — these are better expressed as double-tap or long-hold. Enforce in the UI and model validation.

**Repeat-while-held vs. Sequences:**
No conflict. Repeat fires on hold; sequences fire on press.

### Cancellation / Reset

The input history is a passive buffer — there's no "sequence in progress" state that blocks other actions. Every button press still triggers its normal action (with a possible delay if it's a chord-participant button). The sequence matcher just checks if the recent history happens to match a sequence.

This means pressing Down, Down, A fires:
1. Down press action (if mapped)
2. Down press action (if mapped)
3. Sequence match → sequence action fires
4. A press action is **suppressed** (the sequence consumed it)

To suppress the individual press actions for sequence-participating buttons, add a brief delay similar to `chordReleaseProcessingDelay` (0.18s). If a sequence completes within that window, cancel the pending individual actions.

**Alternative approach (simpler):** Don't suppress individual actions. Each button press fires its own action AND the sequence fires when complete. This is how fighting games work — you see the individual moves AND the special move triggers. Less elegant but avoids timing complexity. Configurable via a `suppressIndividualActions: Bool` flag on `SequenceMapping`.

## UI Design

### Placement

Add a "Sequences" section below chords in the existing **Chords** tab, or create a dedicated **Sequences** tab. Given the similarity to chords (multi-button → action), colocating under the Chords tab with a section header is cleaner.

### Sequence List

```
┌─────────────────────────────────────────────┐
│ Sequences                                   │
│                                             │
│  ↓ ↓ A     →  ⌘T  "Open Terminal"  [edit]  │
│  ← → ← →   →  Macro: "Konami"     [edit]  │
│  X Y B      →  Launch: Safari      [edit]  │
│                                             │
│  ┌────────────────────────────────────┐     │
│  │ + Add Sequence                     │     │
│  └────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

Each row shows:
- Button icons in order (using existing `ControllerButton` SF Symbol mapping)
- Arrow separator
- Action summary (key combo, macro name, or system command)
- Optional hint text
- Edit/delete buttons

### Sequence Editor Sheet

```
┌─────────────────────────────────────────────┐
│ Edit Sequence                               │
│                                             │
│ Steps:                                      │
│  ┌─────────────────────────────────────┐    │
│  │ 1. [↓ Down]  2. [↓ Down]  3. [A]   │    │
│  │                          [+ Add] [×]│    │
│  └─────────────────────────────────────┘    │
│                                             │
│ Time Window:  [━━━━━━●━━━] 0.8s            │
│               0.3s              3.0s        │
│                                             │
│ Action:  ● Key  ○ Macro  ○ System Command   │
│ Key: [Click to record]   Modifiers: ☐⌘ ☐⌥  │
│                                             │
│ Hint: [________________________________]    │
│                                             │
│           [Cancel]     [Save]               │
└─────────────────────────────────────────────┘
```

**Adding steps:** Click "+ Add" then press a controller button. The button is appended to the sequence. Steps can be reordered via drag or deleted individually.

**Time window slider:** Visual feedback showing "you have this long to complete the sequence from first to last input."

**Action picker:** Reuses the same segmented control and sub-views from `ButtonMappingSheet` (key capture, macro picker, system command picker).

### Conflict Detection

When adding/editing a sequence:
- Warn if the sequence is a prefix of another sequence (e.g., `[A, B]` is a prefix of `[A, B, C]`) — the shorter one would always fire first
- Warn if a sequence duplicates an existing one (same steps in same order)
- Warn if all steps are the same button (suggest double-tap instead)
- Show info note if step buttons also participate in a chord

## File Changes

| File | Change |
|------|--------|
| **New:** `Models/SequenceMapping.swift` | `SequenceMapping` struct, `Codable`, `ExecutableAction` conformance |
| **New:** `Views/Sequences/SequenceListSection.swift` | Sequence list UI (embedded in Chords tab or standalone tab) |
| **New:** `Views/Sequences/SequenceEditorSheet.swift` | Sequence creation/editing sheet |
| `Models/Profile.swift` | Add `var sequenceMappings: [SequenceMapping]`, CodingKeys, decode/encode |
| `Services/Mapping/MappingEngineState.swift` | Add `inputHistory: [ButtonEvent]`, `maxSequenceLength` |
| `Services/Mapping/MappingEngine.swift` | Add `sequenceCheck()` in `handleButtonPressed`, history management |
| `Services/Mapping/MappingActionExecutor.swift` | Handle `SequenceMapping` as `ExecutableAction` (already covered by protocol) |
| `Models/ProfileManager.swift` | Add CRUD methods for sequences (`addSequence`, `updateSequence`, `deleteSequence`, `moveSequences`) |
| `Config.swift` | Add `defaultSequenceTimeWindow`, `maxSequenceSteps` constants |

## Edge Cases

- **Empty profile / no sequences**: `sequenceCheck` returns immediately if `profile.sequenceMappings.isEmpty` — zero overhead for users who don't use this feature
- **Profile switch during sequence**: `inputHistory` is cleared on profile switch (same as `lastTapTime` and other per-session state)
- **Layer change during sequence**: Sequences are profile-level, not layer-level (same as chords). Layer activation mid-sequence doesn't affect matching
- **Rapid repeated sequences**: After a sequence fires and clears the history, pressing the same sequence again should work immediately. No cooldown needed — the cleared history ensures a fresh match
- **Controller disconnect**: `inputHistory` is cleared on disconnect (cleanup handler in MappingEngine)
