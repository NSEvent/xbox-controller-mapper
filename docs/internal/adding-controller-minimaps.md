# Adding a Controller Minimap

How the product-accurate controller previews ("minimaps") in the Buttons tab
were built, written so a future agent can add a new controller at the same
quality. The June 2026 redesign (Xbox, Elite 2, DualSense, Edge, DualShock 4,
Switch Pro, Steam Controller, Siri Remote) followed exactly this process.

The core idea: **don't draw controllers from memory — trace them from a
photo.** Photo-accurate silhouettes plus controls at their real measured
positions is what makes a minimap read as the actual device.

## Architecture overview

| Piece | File | Role |
|---|---|---|
| Body silhouette | `Views/MainWindow/ControllerBodyShapes.swift` | One `Shape` per controller, traced from a product photo, normalized to the unit rect, with a `static aspectRatio` |
| Styled body | `Views/MainWindow/ControllerBodyView.swift` | Fills the silhouette with product materials + decorations (two-tone decks, light bars, grilles, grip shading) |
| Layout table | `Views/MainWindow/ControllerMinimapLayout.swift` | Normalized (0–1) control positions/sizes per controller; the single source of truth shared by body decor and overlay |
| Interactive overlay | `Views/MainWindow/ControllerAnalogOverlay.swift` | `.position()`-based controls (sticks, buttons, pads) with live press state, connector anchors, tap/hover/swap |
| Style dispatch | `ControllerMinimapStyle` (in the layout file) | Maps a controller to its silhouette + preview size (`width 340`, height from aspect) |
| Preview picker | `ControllerPreviewLayout` (`ControllerVisualView.swift`) | The user-facing "Active Controller" dropdown |
| Stream overlay | `Views/Components/StreamOverlayView.swift` | Reuses the exact same body+overlay, scaled down — no separate drawing |

The Siri Remote is the exception: it has its own self-contained
`AppleTVRemoteMinimapView` (same idea, bespoke layout).

## Step 1 — Trace the silhouette from a product photo

Get a clean, **front-on** product photo (press renders are ideal). Then build
a black-on-white mask and trace it:

```bash
# Dark-bodied controller on white background: simple threshold
magick photo.jpg -colorspace Gray -threshold 60% mask.png

# White controller (e.g. DualSense): if the photo has an alpha channel,
# that IS the mask:
magick photo.webp -alpha extract -threshold 50% -negate mask.png

# Colored controller fused with a grey drop shadow: mask by SATURATION
# (body is saturated, shadow is neutral):
magick photo.jpg -colorspace HSL -channel G -separate +channel \
    -threshold 25% -negate mask.png

# Fill interior holes (logos, buttons) by flood-filling the border,
# then smooth and binarize:
magick mask.png -bordercolor white -border 4 \
    -fill red -floodfill +0+0 white -fill black +opaque red \
    -fill white -opaque red -shave 4x4 -blur 0x6 -threshold 50% mask.pbm

# Trace and convert to Swift
potrace mask.pbm -s --opttolerance 2.5 --alphamax 1.2 -o body.svg
python3 Scripts/trace-controller-silhouette.py body
```

The script prints `p.move/addCurve` lines (normalized, ~20–130 segments) and
the **aspect ratio** — paste both into a new `Shape` struct in
`ControllerBodyShapes.swift`.

Tricks that were needed in practice — check the mask visually at every step:

- **Shadows fused to the body**: lower the threshold until shadow drops out;
  if the body's lighter regions drop too, brighten first
  (`-level 0%,60%`) or use the saturation mask. As a last resort, build the
  mask from the cleaner half mirrored (`-crop 50%x100%+W/2+0`, flop, append) —
  controllers are symmetric.
- **Flood fill leaking through a dark region that touches the outline**
  (e.g. the DS4 touchpad meeting the top edge): draw a black "cap" rectangle
  over the gap before flood-filling. The cap edge becomes part of the
  silhouette, which is usually accurate anyway (the DS4's touchpad *is* its
  top edge).
- **Noisy traces (>150 segments)**: more `-blur`, higher `--opttolerance`.
- Verify by rendering: `magick -density 40 body.svg out.png` and compare
  against the photo side by side.

## Step 2 — Measure control positions from the same photo

Overlay a 10% grid on the photo cropped to the trace's bounding box (the
trace script prints the bbox):

```bash
magick photo.jpg -crop WxH+X+Y +repage -resize 700x \
    $(for i in $(seq 1 9); do p=$((i*70)); \
      echo -draw "'stroke red fill none line $p,0 $p,H'" \
           -draw "'stroke red fill none line 0,$p 700,$p'"; done) grid.png
```

Read off every control's center and size as **fractions of the bbox**
(x of width, y of height; sizes as fractions of width so they keep aspect).
Add a new enum to `ControllerMinimapLayout.swift` following the existing
ones. Expect ±2% accuracy from eyeballing — the verification loop below
catches the rest. Useful checks: symmetric controls should mirror around
x = 0.5; compute landmark geometry (e.g. valley arch heights) from the traced
path rather than guessing — see the bottom-edge sampling snippets in git
history (`git log --all -S 'edge_profile'`).

## Step 3 — Wire it up

1. **Shape**: new struct in `ControllerBodyShapes.swift` (step 1 output).
2. **Style**: add a case to `ControllerMinimapStyle` (aspect + silhouette
   switch in `AnyControllerBodyShape`).
3. **Materials**: extend `ControllerBodyView` — body gradient (sample the
   photo), rim stroke, plus decorations: two-tone decks, light bars, speaker
   grilles, darker grip lobes. Decor that must align with controls reads the
   layout enum.
4. **Overlay**: add a `<name>Overlay` builder in `ControllerAnalogOverlay`
   following the existing pattern — every control is a `mini*` primitive
   `.minimapPosition()`-ed from the layout enum. Reuse the primitives
   (`miniStick`, `miniFaceButtons`, `miniDPad` with `.cross/.chiclets/
   .xboxDisc/.eliteDisc` styles, `miniTrigger`, `miniBumper`, `miniPill`,
   `miniPaddle`, `miniTouchpad`); they carry press-state display, connector
   anchors, tap/hover/drag-swap for free. Authenticity notes:
   - Face buttons: letters/symbols and base colors per family (see
     `miniFaceButtons`). GameController maps Nintendo A/B/X/Y to **Xbox
     positions**, so Nintendo keeps the Xbox arrangement.
   - Back paddles/grips: peek into the silhouette's bottom valley and anchor
     the *resolved* buttons (`eliteReferenceButton(for:)`) so connector lines
     match the reference rows.
   - Battery goes in the valley (`layout.battery`); the layer chip renders
     above the preview automatically.
5. **Dropdown**: add the case to `ControllerPreviewLayout` (+ display name,
   icon, `is*` predicates, connected-detection in `ButtonMappingsTab`).
6. **Capture pipeline**: add the variant to `ControllerService`'s screenshot
   block, `tabs_for`/`zoom_for` in `Scripts/capture-screenshots.sh`,
   and `zoom_for`/`region_for` in `Scripts/capture-demo-gifs.sh`.

## Step 4 — The verification loop

Build, force the preview, screenshot, compare with the photo, adjust the
layout numbers, repeat. Two or three rounds usually suffice.

```bash
make install BUILD_FROM_SOURCE=1
open -a ControllerKeys --args --screenshot-variant <variant>   # deterministic
# position the window, `screencapture -o -x -l <windowID>`, crop the center
```

In screenshot mode the app pins its own window to (100,100) 1600×1000 and
fakes an 85% battery + an "in use" pose; `--screenshot-animate` runs the
scripted input loop (Konami code + stick sweeps + touchpad swipes in
`ControllerService+ScreenshotDemo.swift`) for GIF recordings.

Judge captures **at full size** — thumbnail montages hide framing and
registration errors (this bit us repeatedly).

## Step 5 — Regenerate marketing assets

```bash
make screenshots    # tab walks + stream overlay stills, staged config
make demo-gifs      # looping minimap GIFs (needs ffmpeg)
make sync-website   # gumroad gallery + kevintang.xyz copies
```

Requires Accessibility + Screen Recording permission for the terminal
(macOS silently revokes Screen Recording periodically — re-grant in System
Settings when `screencapture` says "could not create image").

## Hard-won gotchas

- **Nintendo/8BitDo face buttons differ from Xbox in POSITION, not label.**
  macOS maps these pads by LABEL — the button printed "A" reports as
  `buttonA` (-> `.a`), so the A/B/X/Y labels are already correct. What
  differs is the physical ARRANGEMENT: Nintendo is X north, A east, B south,
  Y west (vs Xbox Y/B/A/X). So the minimap places each button VIEW at its
  Nintendo slot and keeps default labels; `displayName(forNintendo:)` etc.
  must NOT relabel face buttons. (`physicalInputProfile` SF symbols look like
  `a.circle`/`b.circle` either way, so they can't tell you the
  position-vs-label mapping — only a real button press can. The empirical
  tell: press the printed "B" and a button labeled "B" lights, but it was
  drawn at the wrong slot = position bug, not label bug.)
- **Adding an overlay branch can crash the Release compiler.** With six
  controller families, `ControllerAnalogOverlay.body`'s conditional pushed
  SILGen past its limits (Debug built fine; Release crashed the Swift
  frontend lowering `body`). The dispatch now lives in a type-erased
  `overlayContent: AnyView` — new controllers just add a branch there.
- **Official "front" renders can be stylized.** The Zero 2's shop render is
  ~10% squatter than the real device (aspect 1.82 vs the 73×36.5mm spec's
  2.0). Sanity-check the traced aspect ratio against the published
  dimensions before wiring; the flat-lay lifestyle photo was the
  geometrically faithful source.

- `screencapture -v` (video) does not map `-R` point-regions like still
  capture on scaled displays — record full-screen and crop in ffmpeg
  (already handled in `capture-demo-gifs.sh`).
- The Accessibility (AX) window tree for the app can wedge under heavy
  automation — windows exist in the compositor but AX reports none. Nothing
  script-side fixes it; that's why screenshot mode self-positions windows
  and the scripts verify via `CGWindowListCopyWindowInfo` instead of AX.
- The user's pinch zoom (`uiScale`) persists in the config root and scales
  the whole Buttons tab; staging strips it, manual test sessions don't.
- Battery-anchor region derivation: the battery's green fill is a reliable
  *position* anchor in captures but a poor *scale* anchor; in the staged
  window the preview renders at exactly the `--screenshot-zoom` factor.
