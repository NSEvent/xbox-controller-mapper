# PROPHECY.md — The Liberation Plan

## The Mission

We are building the most important human-computer interface since the keyboard.

A $40 game controller will replace $5,000 assistive devices. Writers will draft novels from recliners. Workers will escape their desks. A generation of kids will never assume computing requires sitting upright at a flat surface.

The code already exists for 80% of this. What follows is the remaining 20% — the features that turn a controller mapper into a liberation device.

Every agent working on this plan is building a piece of the future. Your code will be used by people who cannot type, by workers chained to desks, by anyone who has ever wanted to use their computer from the couch. Treat it accordingly. Write tests. Review your own work. Ship code that changes lives.

---

## Architecture Principles

All new code must follow the existing patterns in the codebase:

1. **Services are `@MainActor` classes**, often singletons (see `CommandWheelManager`, `OnScreenKeyboardManager`)
2. **Config constants** go in `Config.swift` under a new `// MARK:` section
3. **Models** use custom `init(from decoder:)` with `decodeIfPresent` and sensible defaults
4. **Tests** use XCTest, `@testable import ControllerKeys`, and `@MainActor` when testing `@MainActor` types
5. **New Swift files** are auto-discovered by the Xcode project (objectVersion 77) — just place them in the correct directory
6. **Thread safety** uses `NSLock` (not actors) for hot paths (see `ControllerStorage`, `LockedStorage`)
7. **Haptic feedback** goes through `ControllerService.playHaptic()` with intensity/sharpness/duration constants in `Config.swift`
8. **Published state** uses `@Published` on `ObservableObject` classes for SwiftUI binding

**Source directory**: `XboxControllerMapper/XboxControllerMapper/`
**Test directory**: `XboxControllerMapper/XboxControllerMapperTests/`

---

## Git Workflow for Agents

Each agent operates on an **independent git worktree** branched from `main`:

```bash
# Agent creates their worktree
git worktree add ../ck-<feature-name> -b feature/<feature-name> main

# Agent works in ../ck-<feature-name>/
# Agent commits, writes tests, self-reviews
# Agent requests merge to orchestrator

# Orchestrator reviews, runs tests, merges
git checkout main
git merge --no-ff feature/<feature-name> -m "feat: <description>"
git worktree remove ../ck-<feature-name>
```

**Test command** (each agent must run before requesting merge):
```bash
cd <worktree>/
make test-full BUILD_FROM_SOURCE=1
```

**Self-review checklist** (each agent verifies before requesting merge):
- [ ] All new code has corresponding tests
- [ ] Tests pass locally (`make test-full BUILD_FROM_SOURCE=1`)
- [ ] No force-unwraps (`!`) on optionals — use `guard let` or `??`
- [ ] Config constants added to `Config.swift` with descriptive comments
- [ ] New files placed in correct directory (Services/, Models/, Views/, Tests/)
- [ ] `@MainActor` used consistently on classes that touch UI state
- [ ] Thread-safe access patterns used for any shared mutable state
- [ ] Code follows existing naming conventions (see similar services)

---

## Phase 1: The Liberation Foundation

These features are the building blocks. They enable everything that follows — accessibility, couch computing, semantic input. They are independent of each other and can be built in parallel.

---

### Task 1: Trigger Zone Service

**Why you are building this**: Every controller mapper in existence treats triggers as binary buttons or single axes. But a trigger is a *region* — it has depth, zones, and pressure. By dividing each trigger into discrete pressure zones with haptic detents, you multiply the input vocabulary without adding any hardware. A user who could only map 2 actions to triggers can now map 8. For someone with limited hand mobility, this means 4x more actions from the same two fingers. This is the difference between "I can do some things" and "I can do everything."

**What to build**: A service that monitors analog trigger values and maps them to discrete pressure zones, firing haptic feedback at zone boundaries like the click of a physical dial.

**New files**:
- `Services/Input/TriggerZoneService.swift`
- `Models/TriggerZoneMapping.swift`
- `XboxControllerMapperTests/TriggerZoneServiceTests.swift`

**Config constants** (add to `Config.swift`):
```swift
// MARK: - Trigger Zones
/// Number of pressure zones per trigger (2-4)
static let triggerZoneCount: Int = 4
/// Zone boundaries as fractions (0.0-1.0), auto-computed from zone count
/// For 4 zones: [0.0, 0.25, 0.5, 0.75, 1.0]
/// Hysteresis band: 5% on each side of boundary to prevent flicker
static let triggerZoneHysteresis: Double = 0.05
/// Haptic feedback for zone transitions (crisp detent click)
static let triggerZoneHapticIntensity: Float = 0.18
static let triggerZoneHapticSharpness: Float = 1.0
static let triggerZoneHapticDuration: TimeInterval = 0.04
```

**TriggerZoneService** spec:
```swift
@MainActor
class TriggerZoneService: ObservableObject {
    /// Current zone index for left trigger (0 = released, 1-N = pressure zones)
    @Published private(set) var leftTriggerZone: Int = 0
    /// Current zone index for right trigger
    @Published private(set) var rightTriggerZone: Int = 0

    /// Configure zone count (2-4) and zone-to-action mappings
    func configure(zoneCount: Int, leftMappings: [Int: KeyMapping], rightMappings: [Int: KeyMapping])

    /// Called by MappingEngine with raw trigger value (0.0-1.0)
    /// Returns the zone index. Fires haptic + action on zone transitions.
    func updateLeftTrigger(_ value: Double) -> Int
    func updateRightTrigger(_ value: Double) -> Int
}
```

**TriggerZoneMapping** model:
```swift
struct TriggerZoneMapping: Codable {
    var zoneCount: Int = 4
    var leftZoneMappings: [Int: KeyMapping] = [:]  // zone index → action
    var rightZoneMappings: [Int: KeyMapping] = [:]
    // Custom decoder with decodeIfPresent, following project pattern
}
```

**Tests** (minimum):
- `testZoneTransitionFromRestToZone1` — verify zone 1 detected at 25%+ pressure
- `testZoneTransitionWithHysteresis` — verify no flicker at zone boundaries (24.9% stays in zone 0, 25.1% enters zone 1, 24.4% stays in zone 1 due to hysteresis, 19.9% exits to zone 0)
- `testAllZonesReachable` — sweep from 0.0 to 1.0, verify all zones are entered
- `testReleaseResetsToZone0` — trigger released → zone 0
- `testZoneChangeFiredOnce` — verify zone change callback fires exactly once per transition
- `testConfigurableZoneCount` — verify 2-zone and 3-zone modes work

**Integration point**: `MappingEngine` calls `triggerZoneService.updateLeftTrigger(value)` in the existing trigger callback, alongside the current trigger-as-button logic. The zone service is additive — it doesn't replace existing trigger behavior.

---

### Task 2: Cursor Magnetism Service

**Why you are building this**: Moving a cursor with an analog stick is inherently less precise than a mouse. Every controller user fights this. Cursor magnetism solves it by making interactive elements *attract* the cursor — buttons, links, text fields, sliders all exert a gentle gravitational pull. The cursor still responds to your thumb, but it *wants* to land on targets. For someone with tremor or limited fine motor control, this is the difference between "I can almost click things" and "I always click things." It makes controller input feel like magic instead of a compromise.

**What to build**: A service that queries macOS Accessibility APIs for nearby interactive elements and applies a gravitational force vector to the cursor when in controller mouse mode.

**New files**:
- `Services/Input/CursorMagnetismService.swift`
- `XboxControllerMapperTests/CursorMagnetismServiceTests.swift`

**Config constants**:
```swift
// MARK: - Cursor Magnetism
/// Maximum distance (points) at which elements attract the cursor
static let magnetismMaxDistance: CGFloat = 80.0
/// Strength of gravitational pull (0.0-1.0, applied as acceleration toward target)
static let magnetismStrength: CGFloat = 0.3
/// Minimum element size (points) to be considered a target
static let magnetismMinTargetSize: CGFloat = 10.0
/// How often to query accessibility tree (Hz) — expensive operation, keep low
static let magnetismQueryFrequency: Double = 10.0
/// AX roles that are considered interactive targets
static let magnetismTargetRoles: [String] = [
    "AXButton", "AXLink", "AXTextField", "AXTextArea",
    "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton",
    "AXMenuItem", "AXTab", "AXIncrementor"
]
```

**CursorMagnetismService** spec:
```swift
@MainActor
class CursorMagnetismService: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published private(set) var nearestTarget: CGRect?  // for optional visual feedback

    /// Called before applying mouse delta. Returns adjusted (dx, dy) with magnetism applied.
    /// cursorPosition: current cursor position in screen coordinates
    /// delta: raw (dx, dy) from joystick
    /// Returns: adjusted (dx, dy) with gravitational pull toward nearest target
    func applyMagnetism(cursorPosition: CGPoint, delta: (CGFloat, CGFloat)) -> (CGFloat, CGFloat)

    /// Force refresh of nearby targets (called on app switch, scroll, etc.)
    func invalidateCache()
}
```

**Implementation notes**:
- Use `AXUIElementCreateSystemWide()` → `AXUIElementCopyElementAtPosition()` to find elements near cursor
- Cache the result and only re-query at `magnetismQueryFrequency` Hz (AX queries are expensive)
- For each nearby interactive element, compute a force vector: `direction * (1 - distance/maxDistance) * strength`
- Add the force vector to the raw joystick delta
- Disable magnetism when focus mode is active (focus mode = precision, magnetism = assistance)

**Tests** (minimum):
- `testNoMagnetismWhenDisabled` — delta unchanged when `isEnabled = false`
- `testNoMagnetismWhenNoTargets` — delta unchanged with no nearby elements
- `testMagnetismPullsTowardTarget` — delta biased toward a mock target at known position
- `testMagnetismStrengthDecaysWithDistance` — pull weaker at max distance
- `testMagnetismZeroAtMaxDistance` — no pull beyond `magnetismMaxDistance`
- `testMagnetismDisabledDuringFocusMode` — verify magnetism suppressed in focus mode

**Testing strategy**: Create a `MockAccessibilityProvider` protocol so tests don't need real AX access. The service takes an `AccessibilityProvider` in its initializer; production uses `SystemAccessibilityProvider`, tests use `MockAccessibilityProvider` that returns hardcoded element positions.

**Integration point**: `MappingEngine` calls `cursorMagnetismService.applyMagnetism()` after computing joystick delta and before calling `InputSimulator.moveMouse()`. Magnetism is applied only when stick mode is `.mouse`.

---

### Task 3: Dwell Selection Service

**Why you are building this**: Some people can move a joystick but cannot reliably press buttons. Arthritis, spinal cord injury, muscular dystrophy — many conditions preserve gross motor control while destroying fine motor control. Dwell selection means: hold the cursor over a target for a configurable time, and it clicks automatically. No button press required. Combined with cursor magnetism, this creates a complete hands-almost-free computing interface. This single feature makes ControllerKeys usable by an entirely new population of people who were previously locked out of computing.

**What to build**: A service that tracks cursor position stability and triggers a click after a configurable dwell time, with visual countdown feedback.

**New files**:
- `Services/Input/DwellSelectionService.swift`
- `Views/Components/DwellIndicatorView.swift`
- `XboxControllerMapperTests/DwellSelectionServiceTests.swift`

**Config constants**:
```swift
// MARK: - Dwell Selection
/// Default dwell time before click (seconds)
static let dwellDefaultDuration: TimeInterval = 1.0
/// Maximum cursor movement (points) during dwell that resets the timer
static let dwellMovementThreshold: CGFloat = 8.0
/// Minimum dwell duration allowed (seconds)
static let dwellMinDuration: TimeInterval = 0.3
/// Maximum dwell duration allowed (seconds)
static let dwellMaxDuration: TimeInterval = 3.0
/// Cooldown after a dwell click before starting next dwell (seconds)
static let dwellCooldownDuration: TimeInterval = 0.5
/// Haptic feedback for dwell click (confirmation)
static let dwellClickHapticIntensity: Float = 0.25
static let dwellClickHapticSharpness: Float = 0.8
static let dwellClickHapticDuration: TimeInterval = 0.08
```

**DwellSelectionService** spec:
```swift
@MainActor
class DwellSelectionService: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var dwellDuration: TimeInterval = Config.dwellDefaultDuration
    @Published private(set) var dwellProgress: CGFloat = 0  // 0.0-1.0 for UI ring
    @Published private(set) var isDwelling: Bool = false
    @Published private(set) var dwellCenter: CGPoint = .zero  // where the dwell started

    /// Called every frame with current cursor position.
    /// Tracks stability and fires click when dwell completes.
    func updateCursorPosition(_ position: CGPoint)

    /// Temporarily pause dwell (e.g., during button press — user is already interacting)
    func pause()
    func resume()
}
```

**DwellIndicatorView** spec:
- A circular progress ring rendered at `dwellCenter`
- Fills from 0 to 360 degrees as `dwellProgress` goes from 0 to 1
- Subtle, semi-transparent, doesn't obstruct the target
- Disappears on click or movement
- Rendered as an `NSPanel` overlay (same pattern as `ActionFeedbackIndicator`)

**Tests** (minimum):
- `testDwellCompletesAfterDuration` — cursor stays still, dwell fires after configured time
- `testDwellResetsOnMovement` — cursor moves beyond threshold, timer resets
- `testDwellProgressIncrements` — progress goes from 0 to 1 linearly during dwell
- `testDwellCooldownPreventsDoubleFire` — no immediate re-dwell after click
- `testDwellDisabledWhenNotEnabled` — no dwell when `isEnabled = false`
- `testDwellPauseAndResume` — pausing stops timer, resuming continues
- `testSmallMovementDoesNotResetDwell` — movement within threshold is tolerated

**Integration point**: `MappingEngine` calls `dwellSelectionService.updateCursorPosition()` after each mouse move. When dwell fires, it calls `InputSimulator.click()`. Dwell is paused whenever a button is pressed (the user is already interacting).

---

### Task 4: Couch Mode Preset

**Why you are building this**: The person who downloads ControllerKeys for the first time will decide within 60 seconds whether this is for them. If they have to configure 20+ mappings before they can check email from the couch, they'll quit. Couch Mode is a one-tap preset that creates a complete, comfortable computing profile out of the box. Left stick moves the cursor. Right stick scrolls. Triggers click. Face buttons handle common actions. Swipe typing is ready. It just works. This is the front door. Every user who stays and discovers the deeper features will have entered through this door.

**What to build**: A preset profile with optimized settings for couch/recliner computing, and a first-launch prompt offering to activate it.

**New files**:
- `Services/Profile/CouchModePresetBuilder.swift`
- `Views/Onboarding/CouchModePromptView.swift`
- `XboxControllerMapperTests/CouchModePresetBuilderTests.swift`

**CouchModePresetBuilder** spec:
```swift
struct CouchModePresetBuilder {
    /// Creates a complete "Couch Mode" profile optimized for comfortable computing.
    /// This is the first thing a new user experiences. It must be immediately useful.
    static func build() -> Profile
}
```

**Profile mappings** (the result of `build()`):
```
Left Stick:     Mouse (sensitivity 0.6, acceleration 0.4, deadzone 0.12)
Right Stick:    Scroll (sensitivity 0.5, acceleration 0.3)
Left Trigger:   Swipe typing activate (handled by existing swipe system)
Right Trigger:  Left click (mapped to click action)
A:              Return/Enter
B:              Escape
X:              Space
Y:              Tab
LB:             Hold modifier — Command (⌘)
RB:             Hold modifier — Shift (⇧)
D-pad:          Arrow keys
Menu:           Show on-screen keyboard
View:           Show command wheel
Left Thumbstick Click:  Right click
Right Thumbstick Click: Mission Control (Ctrl+Up)

Chord LB+B:    Close window (⌘W)
Chord LB+A:    New tab (⌘T)
Chord LB+X:    Select all (⌘A)
Chord LB+Y:    Find (⌘F)
Chord RB+A:    Undo (⌘Z)
Chord RB+B:    Redo (⌘⇧Z)
Chord LB+RB:   Copy (⌘C) — double-tap for Paste (⌘V)
```

**CouchModePromptView** spec:
- A welcoming sheet shown on first launch (check UserDefaults flag)
- Title: "Use your controller to navigate your Mac"
- Subtitle: "Couch Mode sets up your controller for comfortable computing — browsing, typing, working — all without a desk."
- Two buttons: "Enable Couch Mode" (primary) / "I'll set up manually" (secondary)
- Selecting "Enable Couch Mode" creates the profile and sets it as active
- Shows a simple diagram of the layout (controller silhouette with labeled buttons)

**Tests** (minimum):
- `testCouchModeProfileHasAllRequiredMappings` — verify every button listed above is mapped
- `testCouchModeJoystickSettings` — verify left stick is mouse, right stick is scroll
- `testCouchModeChordMappings` — verify all chords present with correct key codes
- `testCouchModeHoldModifiers` — verify LB and RB are hold modifiers
- `testCouchModeProfileNameAndIcon` — verify profile is named "Couch Mode" with appropriate icon
- `testBuildReturnsValidProfile` — verify the profile passes encoding/decoding roundtrip

**Integration point**: `CouchModePromptView` is shown in `XboxControllerMapperApp` on first launch. `CouchModePresetBuilder.build()` returns a `Profile` that is added via `ProfileManager.addProfile()`. No changes to existing services.

---

## Phase 2: The Accessibility Revolution

These features create the "$40 assistive device" story. They depend on Phase 1 (cursor magnetism and dwell selection), but can be developed in parallel with stubs for those dependencies.

---

### Task 5: Accessibility Onboarding Wizard

**Why you are building this**: An occupational therapist walks into a patient's room. The patient has cerebral palsy. The therapist hands them a DualSense controller. The patient can grip with both hands, move both thumbs, but cannot reliably press small buttons. The therapist opens ControllerKeys, taps "Accessibility Setup", and answers 6 questions about the patient's motor capabilities. The app generates a complete profile — dwell selection on, cursor magnetism on, large deadzone for tremor, reduced button count with the most-used actions on the easiest-to-reach buttons. The patient is browsing the web within 5 minutes. This wizard is the bridge between "cool app" and "life-changing tool."

**What to build**: A multi-step onboarding wizard that assesses motor capabilities and generates an optimized accessibility profile.

**New files**:
- `Views/Onboarding/AccessibilityWizardView.swift`
- `Views/Onboarding/AccessibilityWizardStepView.swift`
- `Services/Profile/AccessibilityProfileBuilder.swift`
- `Models/AccessibilityAssessment.swift`
- `XboxControllerMapperTests/AccessibilityProfileBuilderTests.swift`

**AccessibilityAssessment** model:
```swift
struct AccessibilityAssessment: Codable {
    /// Which hands can grip the controller?
    var gripCapability: GripCapability = .bothHands  // .bothHands, .leftOnly, .rightOnly, .limited
    /// Can the user press face buttons reliably?
    var canPressButtons: Bool = true
    /// Can the user use analog sticks with precision?
    var stickPrecision: StickPrecision = .normal  // .normal, .reduced, .minimal
    /// Does the user experience tremor?
    var hasTremor: Bool = false
    /// Can the user press triggers with variable pressure?
    var triggerControl: TriggerControl = .analog  // .analog, .binaryOnly, .none
    /// Preferred click method
    var preferredClickMethod: ClickMethod = .button  // .button, .dwell, .triggerSqueeze

    enum GripCapability: String, Codable, CaseIterable { case bothHands, leftOnly, rightOnly, limited }
    enum StickPrecision: String, Codable, CaseIterable { case normal, reduced, minimal }
    enum TriggerControl: String, Codable, CaseIterable { case analog, binaryOnly, none }
    enum ClickMethod: String, Codable, CaseIterable { case button, dwell, triggerSqueeze }
}
```

**AccessibilityProfileBuilder** spec:
```swift
struct AccessibilityProfileBuilder {
    /// Generates a profile optimized for the user's motor capabilities
    static func build(from assessment: AccessibilityAssessment) -> Profile
}
```

**Profile generation rules**:
- `hasTremor = true` → large deadzone (0.3), cursor magnetism on, slow sensitivity
- `stickPrecision = .minimal` → enable dwell selection, large targets only
- `canPressButtons = false` → dwell selection mandatory, trigger squeeze for click
- `gripCapability = .leftOnly` → all critical mappings on left side
- `gripCapability = .rightOnly` → all critical mappings on right side
- `triggerControl = .none` → triggers disabled, all actions on buttons/stick
- Always enable on-screen keyboard for text entry
- Always set larger-than-default sensitivity values for reduced precision users

**Wizard steps** (6 screens):
1. "Welcome" — explains what this does, shows a controller illustration
2. "Grip" — "Which hands can grip the controller?" with illustrations
3. "Buttons" — "Can you press buttons easily?" with a live button test area
4. "Sticks" — "Move the stick to the edges" with a live precision test (measures actual range)
5. "Triggers" — "Squeeze the trigger" with a live pressure test (measures control quality)
6. "Summary" — "Here's your personalized setup" with option to adjust

**Tests** (minimum):
- `testTremorProfile` — assessment with tremor produces large deadzone and magnetism
- `testOneHandedLeftProfile` — left-only grip maps all critical actions to left side
- `testOneHandedRightProfile` — right-only grip maps all critical actions to right side
- `testNoButtonPressProfile` — no button press → dwell selection enabled
- `testFullCapabilityProfile` — normal capabilities produces standard profile with accessibility extras
- `testAssessmentCodable` — roundtrip encode/decode of AccessibilityAssessment
- `testAllGripCapabilitiesProduceValidProfile` — every enum combination produces a valid profile

**Integration point**: Accessible from main menu ("Accessibility Setup...") and from first-launch prompt alongside Couch Mode. The generated profile is added via `ProfileManager.addProfile()`.

---

### Task 6: Switch Scanning Service

**Why you are building this**: Some people can only press one button. One. Maybe it's a foot switch. Maybe it's a head switch. Maybe it's biting down on a controller bumper. Switch scanning is the standard assistive tech pattern: highlight items one at a time, press the single button to select the highlighted item. It's how people with severe motor disabilities interact with *every* piece of technology. Your on-screen keyboard already has D-pad navigation. Switch scanning is the same thing, but automatic — the highlight moves on its own, and any single button press selects it. This costs almost nothing to implement and opens ControllerKeys to the most severely disabled users.

**What to build**: A scanning mode that auto-advances through on-screen keyboard keys and triggers selection on any button press.

**New files**:
- `Services/Input/SwitchScanningService.swift`
- `XboxControllerMapperTests/SwitchScanningServiceTests.swift`

**Config constants**:
```swift
// MARK: - Switch Scanning
/// Default scan speed (seconds per item)
static let scanDefaultInterval: TimeInterval = 1.5
/// Minimum scan interval (seconds)
static let scanMinInterval: TimeInterval = 0.3
/// Maximum scan interval (seconds)
static let scanMaxInterval: TimeInterval = 5.0
/// Scan pattern: row-column (scan rows first, then items within row) or linear (item by item)
/// Row-column is faster for users who can time two presses
static let scanDefaultPattern: ScanPattern = .rowColumn
```

**SwitchScanningService** spec:
```swift
enum ScanPattern: String, Codable { case linear, rowColumn }

@MainActor
class SwitchScanningService: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var scanInterval: TimeInterval = Config.scanDefaultInterval
    @Published var scanPattern: ScanPattern = Config.scanDefaultPattern
    @Published private(set) var highlightedRow: Int?
    @Published private(set) var highlightedColumn: Int?
    @Published private(set) var isScanning: Bool = false

    /// Start auto-scanning the on-screen keyboard
    func startScanning()

    /// Stop scanning
    func stopScanning()

    /// Any button press triggers this — selects the currently highlighted item
    func selectCurrentItem()

    /// Called by the on-screen keyboard to provide the grid dimensions
    func configureGrid(rows: Int, columns: Int)
}
```

**Row-column scanning behavior**:
1. Scanning starts → rows highlight one at a time (top to bottom)
2. Button press → selected row is locked, columns within that row highlight one at a time
3. Button press → selected key is activated
4. Cycle restarts from row scanning

**Linear scanning behavior**:
1. Every key highlights one at a time, left-to-right, top-to-bottom
2. Button press → highlighted key is activated

**Tests** (minimum):
- `testLinearScanAdvancesSequentially` — each tick moves to next item
- `testLinearScanWrapsAround` — after last item, returns to first
- `testRowColumnFirstPresLocksRow` — first press transitions to column scanning
- `testRowColumnSecondPressSelectsKey` — second press activates the key
- `testScanIntervalRespected` — items advance at configured interval
- `testScanStopsWhenDisabled` — disabling stops the timer
- `testSelectCurrentItemFiresAction` — selecting an item triggers the correct key

**Integration point**: `SwitchScanningService` is owned by `OnScreenKeyboardManager`. When scanning is enabled, D-pad navigation is disabled (scanning replaces it). Any button press routes to `selectCurrentItem()` instead of normal mapping when scanning mode is active.

---

### Task 7: Word Prediction Engine

**Why you are building this**: Typing with a controller — even with swipe typing — is slower than a keyboard. Word prediction closes the gap. After you type "I am", the system predicts "going", "not", "happy", "sorry" as next words. One button press completes the word. For someone using switch scanning (one button at a time), word prediction is the difference between 2 words per minute and 12 words per minute. A 6x speedup. That's the difference between "I can send an email in 30 minutes" and "I can have a conversation."

**What to build**: A word prediction engine that suggests next words based on the current input context, displayed as selectable options above the on-screen keyboard.

**New files**:
- `Services/Input/WordPredictionEngine.swift`
- `Models/WordPredictionModel.swift`
- `Views/Components/WordPredictionBarView.swift`
- `XboxControllerMapperTests/WordPredictionEngineTests.swift`

**WordPredictionEngine** spec:
```swift
@MainActor
class WordPredictionEngine: ObservableObject {
    @Published private(set) var predictions: [String] = []
    @Published private(set) var isEnabled: Bool = true

    /// Update predictions based on current text context
    /// context: the text typed so far (e.g., "I am ")
    func updateContext(_ context: String)

    /// User selected a prediction — insert it and update context
    func selectPrediction(at index: Int) -> String

    /// Clear all predictions (e.g., when keyboard dismissed)
    func reset()
}
```

**Implementation approach**:
- Use a **trigram frequency model** built from a bundled English word frequency corpus
- Store as a compact dictionary: `[String: [String: Int]]` mapping bigrams to next-word frequencies
- Top 5000 bigrams covers most conversational English
- Predictions sorted by frequency, top 4 shown
- Supplement with user's recently typed words (recency boost)
- Bundle the frequency data as a JSON resource file (`Resources/word_frequencies.json`)

**WordPredictionBarView** spec:
- Horizontal bar above the on-screen keyboard
- Shows 4 prediction buttons
- D-pad left/right to highlight, A to select (or dedicated button)
- Selected word is inserted via `InputSimulator.paste()`
- Auto-adds space after inserted word

**Tests** (minimum):
- `testCommonBigramPredictions` — "I am" predicts common completions
- `testEmptyContextReturnsCommonWords` — empty string returns most frequent words
- `testSelectionInsertsWord` — selecting prediction returns correct word
- `testRecentWordsBoosted` — recently typed words appear in predictions
- `testResetClearsPredictions` — reset empties the prediction list
- `testMaxFourPredictions` — never more than 4 predictions returned
- `testPunctuationHandled` — context ending with period/comma works correctly

**Integration point**: `WordPredictionEngine` is used by `OnScreenKeyboardManager`. When the user types (via keyboard or swipe), the context is sent to `updateContext()`. Predictions are displayed in `WordPredictionBarView` above the keyboard. Selection inserts via `InputSimulator`.

---

## Phase 3: Semantic Input

These features represent the paradigm shift from "map buttons to keys" to "map buttons to intentions." They can be developed independently.

---

### Task 8: Intent Mapping Resolver

**Why you are building this**: Every controller mapper ever built is a key-code translator. Press A, get Return. Press LB+Y, get Cmd+F. But what if the user doesn't know that "Find" is Cmd+F? What if they switch from Safari (Cmd+F) to an Electron app where Find is Ctrl+G? Intent mappings solve this forever. The user maps a button to "Find." The system queries the frontmost app's menu bar and figures out the shortcut. The mapping works in every app, automatically. This is the conceptual leap from "keyboard proxy" to "semantic input layer." No one has built this.

**Critical design principle**: Intent is an *option*, not a replacement. Users can still map buttons to explicit key codes — that remains the default. Intent is a new action type that sits alongside keyPress, macro, script, and systemCommand. The user chooses which method they want per mapping. Power users who know their shortcuts keep using key codes. Users who don't want to memorize shortcuts use intents. Both work on the same button, same UI, same profile.

**What to build**: A new `intent` action type on all `ExecutableAction` types, and a resolver service that translates intent strings to the correct keyboard shortcut in the frontmost app via Accessibility APIs.

**New files**:
- `Services/Mapping/IntentMappingResolver.swift`
- `XboxControllerMapperTests/IntentMappingResolverTests.swift`

**Modified files** (adding `intent` field alongside existing action fields):

1. **`Models/KeyMapping.swift`** — Add to `ActionType` enum, `ExecutableAction` protocol, and all mapping structs:

```swift
// In ActionType enum, add:
case intent  // A semantic intent resolved dynamically per-app

// In ExecutableAction protocol, add:
var intent: String? { get }

// In KeyMapping struct, add field:
var intent: String?  // e.g., "Save", "Find", "Close Window"

// In KeyMapping.CodingKeys, add:
case intent

// In KeyMapping.init(from decoder:), add:
intent = try container.decodeIfPresent(String.self, forKey: .intent)

// In KeyMapping.init(), add intent parameter:
init(..., intent: String? = nil, ...) { self.intent = intent }

// In KeyMapping.displayString, add before the keyCode block:
if let intent = intent {
    return "Intent: \(intent)"
}

// In KeyMapping.isEmpty, add:
... && intent == nil

// In KeyMapping.clearingConflicts(keeping:), add:
if actionType != .intent { copy.intent = nil }

// In effectiveActionType (ExecutableAction extension), add before keyPress:
if intent != nil { return .intent }

// In activeActionCount, add:
if intent != nil { count += 1 }

// In activeActionTypes, add:
if intent != nil { types.insert(.intent) }
```

2. **Apply the same `intent: String?` field to**: `LongHoldMapping`, `DoubleTapMapping`, `ChordMapping`, `SequenceMapping` — same pattern as `macroId`/`scriptId`/`systemCommand`. Each already conforms to `ExecutableAction`, so adding `intent` follows the identical pattern.

3. **Execution priority** becomes: `systemCommand > macro > script > intent > keyPress`. Intent sits just above keyPress because it *resolves to* a key press but through a dynamic lookup. If the intent can't be resolved (app doesn't have that menu item), it falls through silently and logs a warning.

**IntentMappingResolver** spec:
```swift
/// Protocol for menu bar access — enables mock testing without AX permissions
protocol MenuBarProvider {
    /// Returns menu items for the given app as (title, keyEquivalent, modifierMask) tuples
    func menuItems(for pid: pid_t) -> [(title: String, keyEquivalent: String, modifiers: UInt)]
}

/// Production implementation using Accessibility APIs
struct SystemMenuBarProvider: MenuBarProvider { ... }

/// Mock implementation for testing
struct MockMenuBarProvider: MenuBarProvider { ... }

@MainActor
class IntentMappingResolver: ObservableObject {
    private let menuBarProvider: MenuBarProvider

    init(menuBarProvider: MenuBarProvider = SystemMenuBarProvider()) {
        self.menuBarProvider = menuBarProvider
    }

    /// Resolve an intent string to a keyboard shortcut for the given app
    /// Returns nil if the intent cannot be resolved (no matching menu item)
    func resolve(intent: String, bundleId: String, pid: pid_t) -> (keyCode: CGKeyCode, modifiers: ModifierFlags)?

    /// Pre-built common intents for the UI picker
    static let commonIntents: [String] = [
        "Save", "Save As", "Open", "Close", "Close Window", "Close Tab",
        "New", "New Window", "New Tab",
        "Undo", "Redo", "Cut", "Copy", "Paste", "Select All",
        "Find", "Find and Replace", "Find Next",
        "Print", "Preferences", "Settings",
        "Minimize", "Zoom", "Full Screen",
        "Quit",
    ]

    /// Cache of resolved intents per bundle ID
    private var cache: [String: [String: (CGKeyCode, ModifierFlags)]] = [:]

    /// Invalidate cache for a specific app (called on app switch)
    func invalidateCache(for bundleId: String)
}
```

**Implementation approach**:
1. Get the frontmost app's `AXUIElement` via `AXUIElementCreateApplication(pid)`
2. Get `AXMenuBar` attribute
3. Walk menu items recursively looking for a title that fuzzy-matches the intent string
4. When found, extract `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers` from the menu item
5. Convert to `CGKeyCode` and `ModifierFlags`
6. Cache the result per bundle ID (invalidate on app switch)
7. Fuzzy matching: case-insensitive substring match, with common synonyms ("Preferences" = "Settings")
8. If no match found, return nil — the executor logs a warning and does nothing (no crash, no fallback to wrong action)

**UI integration** (in `ButtonMappingSheet` and similar):
- The action type picker (where user currently chooses Key Press / Macro / Script / System Command) gets a new option: "Intent"
- When "Intent" is selected, show a text field with autocomplete from `commonIntents`
- User can type a custom intent or pick from the list
- A small "Test" button resolves the intent against the current frontmost app and shows the result (e.g., "In Safari: ⌘F")

**Tests** (minimum):
- `testResolveReturnsNilForUnknownIntent` — graceful handling of unresolvable intents
- `testCachingPreventsRedundantQueries` — second call for same intent+app uses cache
- `testCacheInvalidation` — invalidating cache causes re-query
- `testFuzzyMatchingCaseInsensitive` — "save" matches "Save"
- `testFuzzyMatchingSynonyms` — "Settings" matches "Preferences"
- `testAllCommonIntentsAreValid` — every intent in `commonIntents` is a non-empty string
- `testIntentFieldCodable` — KeyMapping with intent roundtrips correctly
- `testIntentActionType` — KeyMapping with only intent has `effectiveActionType == .intent`
- `testIntentPriority` — KeyMapping with both intent and keyCode resolves to intent
- `testClearingConflictsKeepsIntent` — `clearingConflicts(keeping: .intent)` preserves intent, clears others
- `testClearingConflictsRemovesIntent` — `clearingConflicts(keeping: .keyPress)` clears intent
- `testIntentOnChordMapping` — ChordMapping with intent field encodes/decodes correctly
- `testIntentOnSequenceMapping` — SequenceMapping with intent field encodes/decodes correctly
- `testExistingProfilesWithoutIntentLoadFine` — a JSON profile with no `intent` field loads without error (backward compatibility)

**Note on testing**: The `MockMenuBarProvider` returns hardcoded menu structures (e.g., `[("Save", "s", maskCommand), ("Find...", "f", maskCommand)]`). Tests verify resolution logic without needing real AX access or running apps.

**Integration point**: `MappingActionExecutor` adds a new case in its execution priority chain. When it encounters `intent != nil`, it calls `IntentMappingResolver.resolve()` with the intent string, current `AppMonitor.frontmostBundleId`, and the app's PID. If resolved, it executes the resulting shortcut via `InputSimulator.pressKey()`. If not resolved, it logs and skips. All existing key code / macro / script / system command mappings continue to work exactly as before — zero behavioral change for existing users.

---

### Task 9: Analog-to-Analog Mapping Engine

**Why you are building this**: Right now, triggers map to binary actions. But a trigger is an analog input — it produces continuous values from 0.0 to 1.0. And macOS is full of analog parameters: window opacity, volume, playback speed, brush size, zoom level, scroll speed. Mapping analog-to-analog means the trigger *becomes* a physical knob for any continuous parameter. Squeeze the trigger to slowly increase volume. Hold it at 50% for half volume. Full squeeze for max. This makes the controller feel like a physical instrument, not a button board. The physical effort matches the computational magnitude.

**What to build**: A mapping type that connects trigger pressure (0.0-1.0) to continuous system parameters via configurable output methods.

**New files**:
- `Models/AnalogMapping.swift`
- `Services/Input/AnalogMappingService.swift`
- `XboxControllerMapperTests/AnalogMappingServiceTests.swift`

**AnalogMapping** model:
```swift
struct AnalogMapping: Codable, Identifiable {
    var id: UUID = UUID()
    /// Which trigger this mapping applies to
    var trigger: AnalogTrigger = .left  // .left, .right
    /// Output mode
    var outputMode: AnalogOutputMode = .scroll
    /// Key codes for increment/decrement (used in .keyRepeat mode)
    var incrementKeyCode: CGKeyCode?
    var incrementModifiers: ModifierFlags = ModifierFlags()
    var decrementKeyCode: CGKeyCode?
    var decrementModifiers: ModifierFlags = ModifierFlags()
    /// Value range for the output (min..max maps to 0.0..1.0 trigger)
    var outputMin: Double = 0.0
    var outputMax: Double = 1.0
    /// Human-readable label
    var hint: String?

    enum AnalogTrigger: String, Codable { case left, right }
    enum AnalogOutputMode: String, Codable {
        case scroll         // Trigger pressure → scroll speed
        case keyRepeat      // Trigger pressure → key repeat rate (harder = faster repeat)
        case volume         // Trigger pressure → system volume (via media keys)
        case brightness     // Trigger pressure → screen brightness (via media keys)
    }
    // Custom decoder with decodeIfPresent
}
```

**AnalogMappingService** spec:
```swift
@MainActor
class AnalogMappingService: ObservableObject {
    /// Active analog mappings
    @Published var mappings: [AnalogMapping] = []

    /// Called with raw trigger value (0.0-1.0) every polling cycle
    /// Applies the configured output mode at the appropriate rate
    func updateTrigger(_ trigger: AnalogMapping.AnalogTrigger, value: Double)
}
```

**Implementation notes**:
- `.scroll`: Trigger value maps to scroll speed. At 0 = no scroll. At 1.0 = fast scroll. Direction set by last stick direction.
- `.keyRepeat`: Trigger value maps to repeat interval. At 0 = no repeat. At 0.5 = repeat every 200ms. At 1.0 = repeat every 50ms. The key (increment or decrement) is determined by a modifier button.
- `.volume`: Trigger value maps to system volume via `NSSound.systemVolume` or media key simulation. Smooth, continuous control.
- `.brightness`: Trigger value maps to brightness via media key simulation at a rate proportional to pressure.

**Tests** (minimum):
- `testScrollModeProducesOutput` — non-zero trigger value produces scroll events
- `testScrollModeZeroProducesNoOutput` — zero trigger value produces nothing
- `testKeyRepeatRateScalesWithPressure` — harder pressure = faster repeat
- `testVolumeModeClampedToRange` — output stays within 0.0-1.0
- `testAnalogMappingCodable` — roundtrip encode/decode
- `testMappingDisabledWhenEmpty` — no mappings = no processing

**Integration point**: `AnalogMappingService` is called by `MappingEngine` in the trigger polling loop, alongside existing trigger-as-button behavior. If an analog mapping exists for a trigger, the analog service processes it; otherwise, the existing discrete behavior runs.

---

## Phase 4: Physical Intelligence

These features use the DualSense's hardware capabilities (gyroscope, haptic engine) as information channels. They are fully independent.

---

### Task 10: Gyro Gesture Recognizer

**Why you are building this**: The DualSense has a 6-axis gyroscope and accelerometer. Apple's GameController framework exposes this as `GCMotion` data. Right now, it's completely unused. This is like having a touchscreen and only using it for taps — no swipes, no pinches, no gestures. Gyro gestures turn physical movements into input: tilt the controller to scroll a document. Flick your wrist to switch tabs. Raise the controller to show the keyboard. Every motion is an input you don't need a button for. For users with limited button access, this is additional input channels from the same device. For power users, it's speed — faster than any chord or sequence.

**What to build**: A gesture recognition service that detects tilt, flick, shake, and twist from DualSense gyro/accelerometer data.

**New files**:
- `Services/Controller/GyroGestureRecognizer.swift`
- `Models/GyroGestureMapping.swift`
- `XboxControllerMapperTests/GyroGestureRecognizerTests.swift`

**Config constants**:
```swift
// MARK: - Gyro Gestures
/// Minimum tilt angle (degrees) to trigger tilt gesture
static let gyroTiltThreshold: Double = 15.0
/// Minimum angular velocity (rad/s) to detect a flick
static let gyroFlickThreshold: Double = 5.0
/// Minimum acceleration magnitude for shake detection (g-force)
static let gyroShakeThreshold: Double = 2.5
/// Number of direction changes required for shake (within 1 second)
static let gyroShakeCount: Int = 3
/// Minimum rotation rate (rad/s) for twist detection
static let gyroTwistThreshold: Double = 3.0
/// Cooldown between gesture triggers (seconds)
static let gyroGestureCooldown: TimeInterval = 0.5
/// Sampling rate for gyro data (Hz)
static let gyroSampleRate: Double = 60.0
```

**GyroGestureRecognizer** spec:
```swift
enum GyroGesture: String, Codable, CaseIterable {
    case tiltForward    // Tilt controller toward screen
    case tiltBack       // Tilt controller toward user
    case tiltLeft       // Tilt controller left
    case tiltRight      // Tilt controller right
    case flickLeft      // Quick wrist flick left
    case flickRight     // Quick wrist flick right
    case flickUp        // Quick wrist flick up
    case flickDown      // Quick wrist flick down
    case shake          // Shake controller
    case twistClockwise     // Rotate controller clockwise (like turning a knob)
    case twistCounterclockwise  // Rotate counter-clockwise
    case raise          // Lift controller (accelerometer detects upward movement)
    case setDown        // Set controller down (accelerometer detects rest)
}

@MainActor
class GyroGestureRecognizer: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published private(set) var lastGesture: GyroGesture?

    /// Callback when a gesture is detected
    var onGestureDetected: ((GyroGesture) -> Void)?

    /// Feed raw motion data from GCMotion
    /// gravity: gravity vector (x, y, z) in g
    /// rotationRate: rotation rate (x, y, z) in rad/s
    /// userAcceleration: user acceleration minus gravity (x, y, z) in g
    func processMotionData(gravity: (Double, Double, Double),
                           rotationRate: (Double, Double, Double),
                           userAcceleration: (Double, Double, Double))
}
```

**Implementation notes**:
- **Tilt**: Use `gravity` vector angles. Atan2 of gravity components gives tilt angle. Threshold at 15 degrees.
- **Flick**: High angular velocity spike in `rotationRate` followed by deceleration. Detect peak > threshold.
- **Shake**: Count direction reversals in `userAcceleration` within 1-second window. 3+ reversals = shake.
- **Twist**: `rotationRate.z` exceeds threshold = twist (z-axis is the controller's long axis when held normally).
- **Raise/set down**: `userAcceleration.y` sustained positive = raising, near-zero for extended period = set down.
- All gestures have cooldown timers to prevent multi-firing.

**GyroGestureMapping** model:
```swift
struct GyroGestureMapping: Codable, Identifiable {
    var id: UUID = UUID()
    var gesture: GyroGesture = .shake
    var keyCode: CGKeyCode?
    var modifiers: ModifierFlags = ModifierFlags()
    var macroId: UUID?
    var systemCommand: SystemCommand?
    var hint: String?
    // Custom decoder with decodeIfPresent
}
```

**Tests** (minimum):
- `testTiltForwardDetected` — gravity vector indicating forward tilt triggers gesture
- `testTiltBelowThresholdIgnored` — small tilt does not trigger
- `testFlickRightDetected` — high rotationRate.y spike triggers flick right
- `testShakeRequiresMultipleReversals` — single acceleration spike is not a shake
- `testShakeWithThreeReversals` — three direction changes within window triggers shake
- `testCooldownPreventsDoubleFire` — rapid gestures within cooldown are ignored
- `testTwistClockwiseDetected` — positive rotationRate.z above threshold triggers twist
- `testGyroGestureMappingCodable` — roundtrip encode/decode

**Integration point**: `ControllerService` sets up `GCMotion` handler when a DualSense is connected. Motion data is forwarded to `GyroGestureRecognizer.processMotionData()`. Detected gestures are resolved by `MappingEngine` using `GyroGestureMapping` from the active profile.

---

### Task 11: Haptic Notification Encoder

**Why you are building this**: Right now, notifications interrupt you visually — banners, badges, sounds. You have to look at the screen. But you're holding a controller that can vibrate with extraordinary precision. What if you could *feel* your notifications without looking? A Slack message is a quick double-tap. An email is a slow roll. A calendar alert is a pulsing rhythm. After a week of use, you'd read your notifications through your hands. This is a new sense — a sixth channel of information that doesn't compete with sight or hearing. For someone who is deaf, this is notifications they can actually perceive while looking at their work. For someone in a meeting, it's awareness without pulling out a phone.

**What to build**: A service that monitors macOS notifications and encodes them as distinct haptic patterns on the connected controller.

**New files**:
- `Services/UI/HapticNotificationEncoder.swift`
- `Models/HapticPattern.swift`
- `XboxControllerMapperTests/HapticNotificationEncoderTests.swift`

**Config constants**:
```swift
// MARK: - Haptic Notifications
/// Whether haptic notifications are enabled
static let hapticNotificationsDefaultEnabled: Bool = false
/// Maximum notifications per minute (prevents haptic spam)
static let hapticNotificationsMaxPerMinute: Int = 10
/// Duration of a single haptic pulse (seconds)
static let hapticPulseDuration: TimeInterval = 0.06
/// Gap between pulses in a pattern (seconds)
static let hapticPulseGap: TimeInterval = 0.08
```

**HapticPattern** model:
```swift
struct HapticPattern: Codable, Identifiable {
    var id: UUID = UUID()
    /// App bundle ID this pattern matches (e.g., "com.tinyspeck.slackmacgap")
    var bundleIdentifier: String = ""
    /// Display name for the app
    var appName: String = ""
    /// Pulse sequence: array of (intensity, sharpness, duration) tuples
    /// Example: [(0.3, 0.8, 0.06), (0.3, 0.8, 0.06)] = two quick taps
    var pulses: [(intensity: Float, sharpness: Float, duration: TimeInterval)] = []
    /// Gap between pulses
    var gapDuration: TimeInterval = 0.08

    // For Codable, store pulses as array of HapticPulse structs
    struct HapticPulse: Codable {
        var intensity: Float = 0.3
        var sharpness: Float = 0.8
        var duration: TimeInterval = 0.06
    }
    var pulseSequence: [HapticPulse] = []
    // Custom decoder with decodeIfPresent
}
```

**HapticNotificationEncoder** spec:
```swift
@MainActor
class HapticNotificationEncoder: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var patterns: [HapticPattern] = []

    /// Start monitoring for notifications
    func startMonitoring()

    /// Stop monitoring
    func stopMonitoring()

    /// Manually trigger a pattern (for testing/preview in settings UI)
    func previewPattern(_ pattern: HapticPattern)

    /// Pre-built default patterns for common apps
    static let defaultPatterns: [HapticPattern]  // Slack, Mail, Calendar, Messages
}
```

**Pre-built patterns**:
- **Slack/Messages**: Two quick taps (conversational)
- **Mail**: One slow, firm pulse (importance)
- **Calendar**: Three rhythmic pulses, like a heartbeat (urgency)
- **Default/unknown**: Single light tap

**Implementation notes**:
- Monitor notifications via `NSWorkspace.shared.notificationCenter` for `NSWorkspace.didActivateApplicationNotification` combined with `DistributedNotificationCenter` for app-specific events
- Alternatively, use `UNUserNotificationCenter` delegate or observe notification banners via AX
- Rate-limit to prevent haptic spam (max 10/minute)
- Queue patterns if multiple notifications arrive simultaneously (play sequentially with gap)

**Tests** (minimum):
- `testDefaultPatternsExist` — Slack, Mail, Calendar, Messages have default patterns
- `testRateLimitingPreventsSpam` — more than max notifications/minute are dropped
- `testPatternSequenceTiming` — pulses play with correct gaps
- `testUnknownAppUsesDefaultPattern` — unregistered app gets single tap
- `testDisabledProducesNoHaptics` — no haptics when disabled
- `testHapticPatternCodable` — roundtrip encode/decode
- `testPreviewPlaysSameAsLive` — preview and live trigger the same haptic sequence

**Integration point**: `HapticNotificationEncoder` is initialized in `ServiceContainer` and given a reference to `ControllerService` for haptic playback. It runs independently of the mapping engine. Settings UI (new tab or section in Settings) lets users configure patterns per app.

---

### Task 12: Workspace Snapshot Service

**Why you are building this**: Knowledge workers have multiple "modes" — email mode, coding mode, meeting mode, creative mode. Each mode has a different set of apps, window positions, and layouts. Right now, reconstructing a workspace takes 2-5 minutes of opening apps, resizing windows, arranging monitors. One controller button press should teleport you between workspaces instantly. This is Stage Manager done right — triggered by the device that's always in your hands, saving and restoring the *complete* state including window positions. Combined with profiles, this means one button switches your controller mappings AND your desktop layout simultaneously.

**What to build**: A service that captures and restores desktop workspace state — which apps are open, their window positions and sizes.

**New files**:
- `Services/UI/WorkspaceSnapshotService.swift`
- `Models/WorkspaceSnapshot.swift`
- `XboxControllerMapperTests/WorkspaceSnapshotServiceTests.swift`

**WorkspaceSnapshot** model:
```swift
struct WorkspaceSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var windows: [WindowState] = []

    struct WindowState: Codable {
        var bundleIdentifier: String = ""
        var appName: String = ""
        var windowTitle: String = ""
        var frame: CodableRect = CodableRect()  // position and size
        var isMinimized: Bool = false
        var screenIndex: Int = 0  // which display
    }

    struct CodableRect: Codable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var width: CGFloat = 400
        var height: CGFloat = 300
    }
    // Custom decoder with decodeIfPresent
}
```

**WorkspaceSnapshotService** spec:
```swift
@MainActor
class WorkspaceSnapshotService: ObservableObject {
    @Published var snapshots: [WorkspaceSnapshot] = []

    /// Capture the current workspace state
    func captureSnapshot(name: String) -> WorkspaceSnapshot

    /// Restore a saved workspace snapshot
    /// Opens missing apps, moves/resizes windows to saved positions
    func restoreSnapshot(_ snapshot: WorkspaceSnapshot)

    /// Save snapshots to disk (alongside config)
    func save()

    /// Load snapshots from disk
    func load()
}
```

**Implementation notes**:
- **Capture**: Use `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` to get all visible windows with their bounds, owner names, and PIDs. Map PIDs to bundle IDs via `NSRunningApplication`.
- **Restore**: For each saved window:
  1. If app is not running, launch it via `NSWorkspace.shared.openApplication(at:)`
  2. Use Accessibility API to find the app's windows and set position/size: `AXUIElementSetAttributeValue(window, kAXPositionAttribute, ...)` and `AXUIElementSetAttributeValue(window, kAXSizeAttribute, ...)`
- **Storage**: Save as JSON in `~/.controllerkeys/snapshots.json`
- **Profile integration**: Optionally link a snapshot to a profile — when the profile activates, the snapshot auto-restores

**Tests** (minimum):
- `testCaptureCreatesSnapshot` — capturing produces a snapshot with window entries
- `testSnapshotHasBundleIdentifiers` — captured windows have valid bundle IDs
- `testSnapshotCodable` — roundtrip encode/decode
- `testSnapshotListPersistence` — save and load preserves snapshots
- `testEmptyDesktopCapturesEmptySnapshot` — graceful handling when nothing is open
- `testSnapshotNameAndTimestamp` — captured snapshot has correct name and current time

**Integration point**: `WorkspaceSnapshotService` is initialized in `ServiceContainer`. Snapshots can be triggered from: a system command (`SystemCommand.workspaceSnapshot(id: UUID)`), a macro step, or the command wheel. Settings UI lists saved snapshots with capture/restore/delete actions.

---

## Execution Order & Dependencies

```
Phase 1 (all parallel — no dependencies):
├── Task 1: Trigger Zones          ──┐
├── Task 2: Cursor Magnetism       ──┤
├── Task 3: Dwell Selection        ──┤── Foundation complete
└── Task 4: Couch Mode Preset      ──┘

Phase 2 (parallel, can start during Phase 1):
├── Task 5: Accessibility Wizard   ── uses Cursor Magnetism + Dwell (can stub)
├── Task 6: Switch Scanning        ── independent
└── Task 7: Word Prediction        ── independent

Phase 3 (parallel, independent):
├── Task 8: Intent Mappings        ── independent
└── Task 9: Analog-to-Analog       ── independent

Phase 4 (parallel, independent):
├── Task 10: Gyro Gestures         ── independent
├── Task 11: Haptic Notifications  ── independent
└── Task 12: Workspace Snapshots   ── independent
```

**All 12 tasks can be developed simultaneously** on separate worktrees. The only soft dependency is that Task 5 (Accessibility Wizard) references cursor magnetism and dwell selection from Tasks 2-3, but the wizard only needs to *set configuration flags* for those features — it doesn't need their implementation to compile.

---

## Integration Merge Order

After individual merges, the orchestrator performs integration in this order:

1. **Merge Phase 1 tasks** (foundation services)
2. **Wire Phase 1 into MappingEngine** — add trigger zone, magnetism, and dwell calls to the polling loop
3. **Merge Phase 2 tasks** (accessibility features)
4. **Wire Phase 2 into OnScreenKeyboardManager** — add scanning and word prediction
5. **Merge Phase 3 tasks** (semantic input)
6. **Wire Phase 3 into MappingActionExecutor** — add intent resolution and analog output
7. **Merge Phase 4 tasks** (physical intelligence)
8. **Wire Phase 4 into ControllerService + ServiceContainer** — add gyro, haptic notifications, workspace snapshots
9. **Add new settings UI tabs** — Accessibility, Trigger Zones, Gyro Gestures, Haptic Notifications, Workspace Snapshots
10. **Run `make refactor-gate BUILD_FROM_SOURCE=1`** — full test suite must pass
11. **Manual testing with physical controller** — verify haptics, magnetism, dwell

---

## The Standard

Every feature in this plan exists to serve one thesis: **a game controller is not a lesser input device. It is a different input device. And for millions of people, it is the better one.**

The code you write will be used by people who have never been able to use a computer comfortably. By people who were told their disability meant slow, painful input forever. By people who just want to answer an email without sitting at a desk.

Write tests. Review your code. Ship something worthy of them.
