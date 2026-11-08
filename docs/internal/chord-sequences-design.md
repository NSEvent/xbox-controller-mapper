# Chord sequences: proposed interaction

2026-11-08. Design proposal; the mixed-step recorder and recognizer are not implemented by the controller-label fix.

**TL;DR:** Extend Sequences. A sequence is an ordered list of steps; a step is one button or several buttons held together. Recording and manual editing produce the same editable steps. Keep Chords for a single simultaneous combination.

## Editor

```text
Edit Sequence                         Controller: DualSense

[● Record Sequence]                  [＋ Add Step]

  1   [ L1 + ✕ ]     [Edit] [↑] [↓] [Delete]
                then
  2   [ ○      ]     [Edit] [↑] [↓] [Delete]
                then
  3   [ R1 + △ ]     [Edit] [↑] [↓] [Delete]

Press buttons within a step together.
Release all buttons before the next step.

Maximum gap between steps:  [ 0.5 seconds ▾ ]

Action: [Key | Macro | Script | System | MIDI]
        [existing action editor]

[Try Sequence]                        [Cancel] [Save]
```

Use vertical numbered rows so long sequences and large chords wrap naturally. A compact summary elsewhere uses `L1 + ✕ → ○ → R1 + △`: plus means together, arrow means then. Never require typing this notation.

### Record

1. Record Sequence opens a temporary draft. Wait for initially held controls to release. Suspend mapped actions while recording; show the device being recorded.
2. First press starts a step. Show held buttons immediately. Collect a chord while its buttons overlap; commit on full release. A single button is simply a one-button step. Holding it never repeats.
3. Use the existing chord timing window to validate overlapping presses. A late addition, or rollover where a new button arrives after an earlier member was released, marks the draft step ambiguous; offer Retry Step rather than silently recording a different gesture.
4. Show completed steps and a live current step. Offer Undo Last Step, Start Over, Cancel, and Use Recording. Require all buttons released and at least 2 valid steps before Use Recording.
5. Do not stop at a short pause or bake recorded delays into the sequence. The maximum gap is a separate setting. At the existing step limit, stop collecting and offer review.
6. Use Recording replaces the editor's steps explicitly. Cancel restores the previous draft. Disconnect/profile changes cancel safely and restore mapping through the existing capture session lifecycle.

If connected hardware differs from the selected preview, name the actual recording device. Continue storing canonical button identities. Kevin additionally requested auto-follow on physical button input: a fresh press selects the active controller’s concrete layout, and review follows that selection. Manual preview selection lasts until the next press; idle connections, releases, held-state repeats, and motion/stick noise do not override it.

### Manual entry

Add Step opens a small step editor using the selected controller's buttons. Click to toggle members: one selected button is a single press; multiple selected buttons are a chord. Show `Press together` above the selection and an explicit Add Step/Done button. No automatic advancement after choosing a button.

Each row supports Edit, Duplicate, Delete, Move Up, and Move Down (keyboard-accessible alternatives to drag reordering). Editing starts with that step's buttons selected. Optionally Capture This Step reuses chord capture with one button permitted. Always allow recording first and correcting manually afterward.

Disable saving empty steps, fewer than 2 steps, impossible combinations, excess steps, or an exact duplicate sequence in the active profile. Show the reason beside the affected row. A single chord belongs in Chords; offer that route rather than adding a second identical concept.

### Try Sequence

An isolated test mode suspends normal actions and never executes the configured action. Highlight completed and expected steps, then show Matched, Wrong Step, or Timed Out. Reset and retry in place. This is especially useful for distinguishing a chord from fast sequential presses.

## Recognition contract

- V1 requires a full release between steps. Holding L1 across `L1 + ✕ → L1 + ○` is not supported; explain this directly in the editor. This makes recording and recognition boundaries consistent.
- Compare canonical button sets within steps (order does not matter), and ordered steps across the sequence (order matters). Repeated steps are allowed, but require release and repress.
- Require simultaneous overlap within the chord window. Fire completion on final release; measure the inter-step timeout from a committed step's release to the next step's first press.
- Share the step-assembly rules between recorder and runtime. Do not infer chords by grouping unrelated sequential presses that never overlapped.
- Preserve today's additive behavior: ordinary button/chord actions still run, and the sequence adds its final action. Say so near Action. Recording and Try Sequence suppress all actions.
- Shared prefixes may both fire, as with additive sequences. Flag `A → B` alongside `A → B → X` with a clear explanation. Exclusive/prefix-deferring behavior needs a separate design because it adds latency.
- On wrong input, reset the candidate and consider that step as a possible new first step. Timeout, disconnect, profile change, and capture transitions clear pending progress.

## Implementation map

`SequenceMapping.steps` currently stores `[ControllerButton]`; `ControllerSequenceCapture` records fresh individual presses and rejects multiple simultaneous fresh presses. `SequenceDetector` consumes individual presses. This needs changes across persistence, capture, recognition, summaries, and editing—not just a new picker.

Introduce a nonempty `SequenceStep` with a canonical set of buttons. Decode existing flat sequences as singleton steps, preserving IDs, actions, timeout, and order. Specify the new encoding and downgrade behavior before shipping; older versions must not silently flatten chords into different triggers. Update import/export, profile validation, copy/paste, overview, minimap/overlays, and accessibility summaries.

Keep action editing shared with existing sequences. Extract the step editor and recorder presentation into small views rather than growing the existing large sheet.

## Acceptance tests for the feature

- Legacy profile migration and mixed-step encode/decode round trips; action/ID preservation; malformed and empty steps rejected.
- Single → chord → single; reversed order within a chord; repeated chord steps; long holds; initial held controls; full-release boundaries.
- Near-simultaneous events arriving separately, same-snapshot chords, late presses, partial release/rollover, unrelated extra buttons, aliases, and step limits.
- Timeout boundaries using an injected clock; wrong-step restart; shared prefixes and overlap; exactly one final action.
- Recorder cancel preserves prior edits; interruption restores mapping; Try Sequence emits no action or synthetic input.
- Manual selection does not advance early; reorder/delete/edit/duplicate preserve correct steps; duplicate detection ignores member order within a chord.
- Selected controller labels and available extra controls remain consistent across create, edit, list, recording review, and profile switching.
