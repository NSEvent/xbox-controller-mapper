# Chord sequences

2026-11-08. Implemented in the existing Sequences editor for local physical controller input. The interaction and recognition contract below is the design reference.

**TL;DR:** Extend Sequences. A sequence is an ordered list of steps; a step is one button or several buttons held together. Recording and manual editing produce the same editable steps. Keep Chords for a single simultaneous combination.

## Placement and organization

Keep **Map → Sequences**. Single-button sequences and mixed button/chord sequences share the same ordering, timing, recording, action, and compatibility rules; a separate tab would duplicate those controls and make a single-step edit move an item between tabs. Keep **Map → Chords** for a single simultaneous combination.

The existing compatible-first sections also apply to mixed sequences: **For [controller]** contains a sequence only when that controller supports every button in every step. Cross-device sequences remain in **Other mappings**. Grouping is a view of one saved list: preserve relative order within each section; drag changes only the saved slots belonging to that section. Changing controllers never sorts or rewrites the list.

Do not silently convert existing single-button sequences to release-based timing. Preserve legacy recognition semantics for existing sequences, and define a versioned mixed-step representation before implementation. Migration tests must compare the old and new recognition traces, including a button held while the next button is pressed.

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

If connected hardware differs from the selected preview, name the actual recording device. Continue storing canonical button identities. Kevin additionally requested auto-follow on physical button input: a fresh press selects the active controller’s concrete layout, and review follows that selection. Manual selection lasts until the next genuine connection or fresh press. Duplicate connection notifications, releases, held-state repeats, and motion/stick noise do not override it. The selection survives profile changes and is shared by editors, review, capture, and the stream overlay.

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

`SequenceMapping.inputSteps` stores canonical `SequenceStep` values. `SequenceStepAssembler` shares physical overlap rules between `SequenceRecording` and `ReleasedSequenceDetector`. The legacy `SequenceDetector.process` path continues to consume individual resolved presses. Timed physical snapshots are captured before chord resolution and queued in transition order; UI scheduling delays cannot change chord membership.

Legacy sequences retain flat `steps` JSON and press timing. Release-based sequences encode `stepFormat: 2` with `steps: [{"buttons": [...]}, ...]`. Decoding rejects malformed steps and unknown formats. The reused `steps` key deliberately causes old decoders to reject a mixed profile instead of flattening it into a different trigger. Do not downgrade a profile containing format 2 sequences. IDs, actions, timing, ordering, and step boundaries survive profile save/export/import. Summaries, compatibility grouping, overview, participant indexing, trigger conflicts, and the input timeline use the full step representation.

`SequenceStepsEditor` owns the step UI, `SequenceEditorDraft` implements explicit manual edits, and `SequenceInputSession` holds the scoped input-preview lease. Cancel never mutates the editor draft; only Use Recording replaces it. Controller disconnect ends the capture and keeps the draft; profile changes close the editor through its existing scope guard. The existing action editor is reused.

Current boundaries: mixed-step recognition uses local physical controller transitions. Universal Control’s existing peer protocol only sends resolved buttons/chords and cannot preserve physical overlap timestamps; mixed input routed to a peer must not execute a local sequence. A future protocol extension is needed for mixed-step recognition on the receiving Mac. Dragging individual steps and capturing a single step are optional future affordances; keyboard-accessible move buttons and whole-sequence recording are implemented.

## Acceptance tests for the feature

- Legacy profile migration and mixed-step encode/decode round trips; action/ID preservation; malformed and empty steps rejected.
- Single → chord → single; reversed order within a chord; repeated chord steps; long holds; initial held controls; full-release boundaries.
- Near-simultaneous events arriving separately, same-snapshot chords, late presses, partial release/rollover, unrelated extra buttons, aliases, and step limits.
- Timeout boundaries using an injected clock; wrong-step restart; shared prefixes and overlap; exactly one final action.
- Recorder cancel preserves prior edits; interruption restores mapping; Try Sequence emits no action or synthetic input.
- Manual selection does not advance early; reorder/delete/edit/duplicate preserve correct steps; duplicate detection ignores member order within a chord.
- Selected controller labels and available extra controls remain consistent across create, edit, list, recording review, and profile switching.
