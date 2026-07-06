# OuraGestureModel

Per-event gesture classifier for the Oura ring input source: given a 0.64s
window of raw motion around an impulse candidate, classify it as `tap`,
`flick-up/down/left/right`, or `noise`. The deterministic tap-sequence
counter stays; the classifier replaces the geometric flick recognizer (which
ground truth showed unfixable: the "snap + return to start" model doesn't
match gravity-projection data) and filters tap ghosts.

## Pipeline

```
Tools/oura-calibration session (gestures.html + motion trace)
  → analyze_gestures.py           # trial join + gesture-dataset.ndjson
  → build_dataset.py              # trial labels → per-event windows (events.ndjson)
  → train.py                      # grouped 8-fold CV + final train → checkpoints/oura_gesture.pt
  → export.py                     # → exported/OuraGestureClassifier.mlpackage
  → verify_coreml.py              # torch vs Core ML parity
  → copy .mlpackage into XboxControllerMapper/Resources/   # synced group, no pbxproj edit
```

## Window format

32 timesteps × 5 channels (`x, y, z` in g, `px, py` projected input),
uniformly resampled over [peak−0.26s, peak+0.38s]. Values are RAW —
normalization constants are baked into the model. Class order lives in
`model.CLASSES` and is mirrored by the Swift wrapper.

## Retraining with more data

Run another labeling session (Tools/oura-calibration/serve.py →
/gestures.html), analyze it, build its events, then pass every session's
events file to train.py:

```
python3 train.py capA/events.ndjson capB/events.ndjson
```

More sessions is the main quality lever — v0 trained on one 82-trial session
(137 events; flick directions have only 7-10 examples each).
