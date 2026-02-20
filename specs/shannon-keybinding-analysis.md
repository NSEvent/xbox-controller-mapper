# Applying Information Theory to Controller Keybindings

Inspired by [ShannonMax](https://github.com/sstraust/shannonmax) — a tool that uses Shannon's source coding theorem to evaluate Emacs keybinding efficiency.

## The Core Insight

Shannon's source coding theorem says: **in an optimal code, more frequent symbols should have shorter codewords**. A keybinding is a "codeword" for a command. If you use `Cmd+C` 200 times a day but `LB+RB+Y` only twice, and those bindings were swapped, you'd be wasting effort on every copy.

ShannonMax quantifies this. For each command with probability `p`:

```
optimal_length = -log2(p) / log2(alphabet_size)
```

The difference between the optimal length and the actual keybinding cost tells you exactly how "wrong" each binding is — and in which direction.

## Mapping This to ControllerKeys

### The Controller "Alphabet"

A keyboard has ~52 usable single keys. A controller's alphabet is fundamentally different — it's smaller in raw button count but richer in interaction types per button.

Available buttons vary by controller (18 Xbox, up to 28 DualSense Edge), but the total action space is much larger because each button supports multiple interaction types:

| Input Type | Example | Buttons That Support It |
|-----------|---------|------------------------|
| Single press | Press A | All 28 |
| Long hold (500ms) | Hold A | All 28 |
| Double tap (300ms) | Tap A twice quickly | All 28 |
| 2-button chord | LB + A simultaneously | C(28,2) = 378 combinations |
| 3-button chord | LB + RB + A | C(28,3) = 3,276 combinations |
| Hold modifier + press | Hold LB, press A | 28 × 27 = 756 |
| Layer switch + press | Activate layer, press A | layers × 28 |

The theoretical action space is enormous. But only a fraction is practically usable — your thumbs can only do so much.

### Defining "Cost" for Controller Inputs

On a keyboard, ShannonMax counts keypresses: `C-x` = 2, `C-x C-s` = 4. For a controller, "cost" maps to a combination of **time**, **physical effort**, and **cognitive load**:

| Input Type | Estimated Cost | Rationale |
|-----------|---------------|-----------|
| Single press (face/bumper) | 1.0 | Instant, zero thought |
| Single press (d-pad) | 1.1 | Thumb must leave stick |
| Single press (triggers) | 1.0 | Index finger, natural |
| Single press (stick click) | 1.3 | Awkward, imprecise |
| Single press (share/menu/view) | 1.4 | Small, harder to reach |
| Double tap | 1.5 | Speed-dependent, 300ms window, error-prone |
| Long hold | 2.0 | 500ms latency floor — unusable for rapid actions |
| 2-button chord (same hand) | 1.8 | Thumb contortion (e.g., A+B) |
| 2-button chord (cross hand) | 1.3 | Easy (e.g., LB+A, one finger each) |
| 3-button chord | 2.2 | Coordination overhead |
| Hold modifier + press | 1.5 | Natural if modifier is bumper/trigger |
| Layer + press | 2.0 | Requires context switch |

These costs are rough and subjective — but that's fine. The point is to establish a relative ordering so we can compare actual bindings against information-theoretic ideals.

### The Effective Alphabet Size

To use Shannon's formula, we need an effective alphabet size `A`. This isn't just the button count — it's the number of **distinct actions at a given cost level**.

For ControllerKeys with an Xbox controller (~18 usable buttons):

| Cost Level | Available Actions | Count |
|-----------|------------------|-------|
| 1.0 | Face buttons (A, B, X, Y) + triggers + bumpers | ~8 |
| 1.0–1.4 | + D-pad, stick clicks, special buttons | ~18 |
| 1.3–1.5 | + cross-hand chords, hold modifiers | ~40 |
| 1.5–2.0 | + double taps, same-hand chords, long holds | ~80+ |
| 2.0+ | + 3-button chords, layer actions | ~200+ |

If we count everything up to cost 2.0 as "usable," the effective alphabet is roughly **80–100 actions**. This is actually larger than a keyboard's 52 single keys — but the cost distribution is much less uniform. A keyboard's keys are mostly equivalent cost; a controller's actions span a wide range.

Using Shannon's characteristic equation to solve for the true effective alphabet size (accounting for the non-uniform costs) would be the rigorous approach, but `A ≈ 80` is a reasonable starting estimate.

## What a ControllerKeys Analyzer Would Do

### Step 1: Log Usage

Track every action the user performs through the controller:
- Which button/chord/interaction was used
- Timestamp
- Which profile was active
- What command it mapped to (key code, macro name, app launch, etc.)

This is the equivalent of ShannonMax's Emacs keylogger.

### Step 2: Compute Probabilities

After a week of usage:
```
action_probability = times_action_used / total_actions
```

### Step 3: Compute Optimal vs. Actual Cost

For each action:
```
optimal_cost = -log2(probability) / log2(effective_alphabet_size)
waste = optimal_cost - actual_cost
```

- **Negative waste** → "This binding costs more than it should." The action is frequent but mapped to something expensive (long hold, obscure chord). Candidate for promotion to a single press.
- **Positive waste** → "This binding is too cheap for how rarely you use it." A single press on `A` is wasted on something used once a day. Candidate for demotion to a chord or long hold.

### Step 4: Generate Recommendations

Present ranked lists:

**Bindings that cost too much (promote these):**
| Action | Current Binding | Cost | Optimal Cost | Waste |
|--------|----------------|------|-------------|-------|
| Volume Up | LB + D-pad Up | 1.3 | 0.4 | -0.9 |
| Play/Pause | Long hold Y | 2.0 | 0.6 | -1.4 |

**Bindings that are too cheap (demote these):**
| Action | Current Binding | Cost | Optimal Cost | Waste |
|--------|----------------|------|-------------|-------|
| Screenshot | A | 1.0 | 1.8 | +0.8 |
| Toggle OBS | X | 1.0 | 2.1 | +1.1 |

## Why This Is Interesting for Controllers Specifically

### 1. The Cost Spectrum Is Wider

On a keyboard, most bindings cost 1–4 keypresses. On a controller, costs range from 1.0 (instant face button) to 2.5+ (3-button chord after a layer switch). This means there's more room for optimization — and more pain from getting it wrong.

### 2. Interaction Types Are Qualitatively Different

A keyboard's "long sequence" is just more of the same keypresses. A controller's long hold is a fundamentally different physical action than a single press. This matters because:
- Long holds have a **latency floor** — 500ms minimum. They are physically incapable of being rapid. Shannon's theory would never assign a frequent action here.
- Double taps have an **error rate** — mis-triggers when you didn't mean to double tap. The "cost" should factor in error probability.
- Chords have a **learning curve** — but once learned, they're fast. The cost decreases with practice.

An analyzer could track these separately: "You're using long hold for an action you trigger 50 times/hour. That's 25 seconds of dead waiting time per hour. Move it to a single press."

### 3. Profile-Aware Analysis

Users switch profiles for different apps. The analyzer could show per-profile efficiency:
- "Your Gaming profile is 85% optimal"
- "Your Productivity profile is 60% optimal — your most-used media controls are buried in chords"

### 4. Chord Utilization

Most users probably under-utilize chords. Cross-hand chords (LB+face button) are nearly as fast as single presses but quadruple the action space. The analyzer could surface: "You have 8 unused LB+[button] slots. Your 3 most common long-hold actions would be faster as LB+chords."

## What We Have Today

### Existing Stats Infrastructure

`UsageStatsService` (`Services/Utilities/UsageStatsService.swift`) already tracks controller usage in real time, persisted to `~/.controllerkeys/stats.json`. It's called from `MappingActionExecutor.executeAction()` on every action fired.

**Tracked data:**

| Field | Type | What It Captures |
|-------|------|-----------------|
| `buttonCounts` | `[String: Int]` | Per-button totals (`"a" → 500`, `"leftBumper" → 120`) |
| `actionTypeCounts` | `[String: Int]` | Per-interaction-type totals (`"Press" → 800`, `"Long Press" → 40`) |
| `actionDetailCounts` | `[String: Int]` | **Joint distribution** — button × interaction type (see below) |
| `keyPresses` | `Int` | Output key events simulated |
| `mouseClicks` | `Int` | Output mouse clicks simulated |
| `macrosExecuted` | `Int` | Macros triggered |
| `macroStepsAutomated` | `Int` | Total macro steps run |
| `webhooksFired` | `Int` | HTTP requests sent |
| `appsLaunched` | `Int` | Apps opened |
| `textSnippetsRun` | `Int` | Quick text snippets typed |
| `terminalCommandsRun` | `Int` | Terminal commands executed |
| `linksOpened` | `Int` | URLs opened |
| `joystickMousePixels` | `Double` | Cursor distance from joystick |
| `touchpadMousePixels` | `Double` | Cursor distance from touchpad |
| `scrollPixels` | `Double` | Scroll distance |
| `totalSessions` | `Int` | App session count |
| `totalSessionSeconds` | `Double` | Cumulative session time |
| `currentStreakDays` | `Int` | Current daily streak |

### The Key Field: `actionDetailCounts`

This is the joint distribution the Shannon analysis needs. Every action records a composite key of `"button:interactionType"` or `"button1+button2:interactionType"`:

```json
"actionDetailCounts": {
  "a:Press": 450,
  "a:Long Press": 30,
  "a:Double Tap": 20,
  "leftBumper+a:Chord": 15,
  "y:Press": 300,
  "y:Long Press": 5,
  "leftBumper+rightBumper+x:Chord": 8
}
```

**Key format:**
- Single button: `"{button.rawValue}:{type.rawValue}"` — e.g. `"a:Press"`, `"dpadUp:Long Press"`
- Chord: `"{sorted buttons joined by +}:{type.rawValue}"` — e.g. `"a+leftBumper:Chord"`
  - Buttons are sorted alphabetically by rawValue so press order doesn't matter

**Recording happens in `UsageStatsService`:**
- `record(button:type:)` — bumps `buttonCounts`, `actionTypeCounts`, and `actionDetailCounts`
- `recordChord(buttons:type:)` — bumps per-button `buttonCounts`, `actionTypeCounts`, and the composite chord key in `actionDetailCounts`

### What's Already Surfaced in the UI

`StatsView` shows:
- Controller personality (Strategist, Brawler, Navigator, etc.) derived from usage patterns
- Top 5 most-pressed buttons with bar chart
- Input type breakdown (single press %, chord %, double tap %, long hold %)
- Output action counters (key presses, macros, webhooks, etc.)
- Distance traveled (joystick, touchpad, scroll)
- Share-able "Wrapped" card

### What's Missing for Shannon Analysis

The stats infrastructure gives us the frequency data. To run the full analysis, we still need:

1. **Cost function** — map each `actionDetailCounts` key to a cost value (see cost table above)
2. **Profile awareness** — `actionDetailCounts` is global, not per-profile. For per-profile analysis, we'd need to either split the counter by profile ID or cross-reference with the active profile's mappings.
3. **Mapping lookup** — to generate recommendations like "swap Play/Pause from Long Hold Y to Single Press B", we need to join the frequency data with the current profile's `buttonMappings` and `chordMappings` to know what each action actually does.
4. **Analysis engine** — pure function: `(actionDetailCounts, Profile, costFunction) → [Recommendation]`
5. **UI surface** — new section in StatsView or dedicated tab

## Implementation: Next Steps

### Step 1: Cost Function

A function that takes an `actionDetailCounts` key and returns a cost:

```swift
func inputCost(for key: String) -> Double {
    let parts = key.split(separator: ":")
    guard parts.count == 2 else { return 1.0 }
    let buttons = parts[0].split(separator: "+")
    let type = String(parts[1])

    // Base cost by interaction type
    var cost: Double
    switch type {
    case "Press":       cost = 1.0
    case "Double Tap":  cost = 1.5
    case "Long Press":  cost = 2.0
    case "Chord":       cost = buttons.count == 2 ? 1.3 : 2.2
    default:            cost = 1.0
    }

    // Adjust for button ergonomics (single-button actions only)
    if buttons.count == 1, let button = ControllerButton(rawValue: String(buttons[0])) {
        switch button.category {
        case .face, .trigger, .bumper: break           // no penalty
        case .dpad:                    cost += 0.1     // thumb leaves stick
        case .thumbstick:              cost += 0.3     // awkward click
        case .special:                 cost += 0.4     // small, hard to reach
        case .touchpad, .paddle:       break
        }
    }

    return cost
}
```

### Step 2: Shannon Analysis Function

```swift
struct BindingAnalysis {
    let key: String           // actionDetailCounts key
    let count: Int
    let probability: Double
    let actualCost: Double
    let optimalCost: Double
    let waste: Double         // optimal - actual (negative = too expensive)
    let hint: String?         // mapped action description from profile
}

func analyzeBindings(
    actionDetailCounts: [String: Int],
    effectiveAlphabetSize: Double = 80
) -> [BindingAnalysis] {
    let total = actionDetailCounts.values.reduce(0, +)
    guard total > 0 else { return [] }

    return actionDetailCounts.map { key, count in
        let p = Double(count) / Double(total)
        let optimalCost = -log2(p) / log2(effectiveAlphabetSize)
        let actualCost = inputCost(for: key)
        return BindingAnalysis(
            key: key,
            count: count,
            probability: p,
            actualCost: actualCost,
            optimalCost: optimalCost,
            waste: optimalCost - actualCost,
            hint: nil  // TODO: look up from profile
        )
    }
    .sorted { $0.waste < $1.waste }  // most negative (most wasted effort) first
}
```

### Step 3: UI — Optimization Suggestions

Add a section to StatsView (or a new tab) that shows:

**"Bindings costing you time" (waste < -0.3):**
> You use **Long Hold Y** (Play/Pause) 200×/day. That's 100s of waiting.
> Move it to **Single Press B** (Screenshot, used 3×/day)?
> [Swap]

**"Underused prime buttons" (waste > +0.5):**
> **Single Press X** is mapped to Toggle OBS (used 2×/day).
> Consider moving it to a chord to free up X for something frequent.

**Profile efficiency score:**
> Weighted average of |waste| across all bindings, normalized to 0–100%.
> "Your bindings are 72% optimal"

## Open Questions

1. **Per-profile tracking.** `actionDetailCounts` is currently global across all profiles. If users switch profiles for different apps, the frequency distribution is a blend. Options: (a) split `actionDetailCounts` by profile ID, (b) ignore — most users have one primary profile, (c) cross-reference at analysis time by checking which buttons have mappings in the active profile.

2. **How to model cost for macros and system commands?** A macro that types 50 characters has a "value" much higher than a single keypress. Should the analyzer weight by output complexity? Probably not for v1 — just treat every action as equal and optimize for frequency.

3. **How do layers interact with cost?** Layers aren't tracked in `actionDetailCounts` yet. A layer-activated button press looks identical to a base-layer press in the stats. To track this, `record()` would need to know the active layer. Worth deferring until layers are more widely used.

4. **Error rates as cost multipliers?** Double taps mis-fire sometimes. If a double tap has a 5% error rate, the effective cost should be higher than the base physical cost. Could track error rates from the usage data (e.g., single presses that are immediately followed by an undo). Nice-to-have for v2.

5. **Minimum data threshold.** How much usage data before recommendations are meaningful? ShannonMax filters commands with <5 occurrences. We should probably require ≥50 total actions and ≥3 occurrences per action before showing analysis. The UI should show a "keep using your controller — need more data" state.

6. **Swap UX.** The dream is one-click "swap these two bindings." This requires modifying the profile's `buttonMappings` — moving mapping A to slot B and vice versa. The mechanics exist (ProfileManager can save), but the UX for confirming a swap needs thought. Start with read-only recommendations.

## References

- [ShannonMax](https://github.com/sstraust/shannonmax) — Shannon entropy analysis for Emacs keybindings
- Shannon, C.E. (1948). "A Mathematical Theory of Communication" — the source coding theorem
- Kraft's inequality — `Σ A^(-l_i) ≤ 1` — the constraint on prefix-free code lengths
