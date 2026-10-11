# Photo Mechanic Culling

Review a shoot from a controller: keep, skip, inspect focus, tag, and reset ratings.
Requires Photo Mechanic for Mac and ControllerKeys with macro support. The profile
switches automatically when Photo Mechanic is active. The keep macro is included;
no scripts, external automations, or personal files are required.

## Setup and first action

1. Import **Photo Mechanic Culling** from the community library.
2. Open a folder in Photo Mechanic's Contact Sheet, select one photo, and press
   **Create / View** to open Preview.
3. Turn off Photo Mechanic's automatic advance after rating or tagging. Keep
   already advances explicitly; enabling both can skip an extra photo.
4. Give the image focus, then press **Cross / A**. It should receive five stars
   and advance exactly once. Use a practice copy of your photos for the first check.

## Controls

| PlayStation / Xbox | Action |
| --- | --- |
| Cross / A | Five stars, then next photo |
| Circle / B | Next photo without changing its rating |
| Square / X | Zoom / fit for checking detail |
| Triangle / Y | Toggle tag |
| L1 / LB, R1 / RB | Previous / next photo |
| L2 / LT | Reset rating to zero stars; stay on this photo |
| R2 / RT | Five stars; stay on this photo |
| D-pad left / right | Previous / next photo |
| D-pad up / down | Four / three stars |
| Options / Menu | Close Preview; return to Contact Sheet |
| Create / View | Open the selected Contact Sheet photo in Preview |
| Touchpad | Pointer movement with calibrated Default tuning |
| Touchpad tap / press | Left click; hold a press to drag |

Sticks are disabled to avoid accidental pointer movement. Keep sends Control+5,
waits 150 ms, then sends Right Arrow. Use it in **Preview with image focus**, not
inside a text field. Skip preserves an existing rating; L2 / LT clears it.
Tags are separate from stars. On the Contact Sheet, rating shortcuts affect the
selection. There are no file-deletion bindings.

## Compatibility and verification

Prepared with Photo Mechanic build 9175 on 2026-10-11. Five stars, clearing stars,
previous/next, tagging, and zoom/fit were verified through keyboard actions.
Physical controller feel and the complete keep-macro timing still need a check
on your setup. Labels cover PlayStation and Xbox equivalents; touchpad controls
require a controller with a supported touchpad.

Shortcut reference: [Camera Bits macOS keyboard shortcuts](https://docs.camerabits.com/support/solutions/articles/48000317772-keyboard-shortcuts-macos).
