# iMovie

Cut a movie with a controller: find a frame, split, remove an unwanted clip, undo,
and play back. Requires iMovie for Mac and ControllerKeys with held-key repeat
support. No scripts, external automations, or extra hardware beyond a supported
controller. The profile switches automatically when iMovie is active.

## Setup and first action

1. Import **iMovie** from the community library and open an iMovie movie project.
2. Focus the lower timeline, then move the pointer away from clip thumbnails.
3. Tap **R1 / RB** to advance one frame. Tap **L1 / LB** to go back.

## Controls

| PlayStation / Xbox | Action |
| --- | --- |
| Cross / A | Play or pause |
| Circle / B | Split at the playhead |
| Square / X | Select and delete the whole clip at the playhead |
| Triangle / Y | Undo |
| L1 / LB, R1 / RB | Step backward / forward; hold to repeat at 12.5 steps/sec |
| L2 / LT, R2 / RT | Fast backward / forward; held-key repeat at 30 steps/sec |
| Left stick | Move the pointer |
| Left stick click | Left mouse click |
| Right stick | Scroll |
| Right stick click | Fullscreen playback (Shift+Command+F) |
| Options / Menu | Undo; hold for redo |
| D-pad up / down | Previous / next clip |
| D-pad left / right | Home / End |

Triggers use held-key repeat to avoid queuing separate 50 ms key presses faster
than they can finish. Release ends the hold; actual responsiveness also depends
on iMovie's processing speed.

## Delete at the playhead

Square / X runs a self-contained keyboard macro: **X**, wait **120 ms**, then
**Delete**. It selects the entire clip before removing it, so an earlier selection
does not need to be highlighted again. Triangle / Y undoes the deletion.

Keep the **timeline focused** and the **pointer off thumbnails**: iMovie's skimmer
can take precedence over the playhead. This deletes a whole clip, not an arbitrary
range or a single frame. Try it on a disposable project first.

## Compatibility and verification

Prepared with a DualSense Edge controller on 2026-10-09. iMovie's native Split,
Undo, and Select Entire Clip actions were checked; Select Entire Clip targeted
the playhead's clip even when another clip was selected. Physical trigger-release
timing, the complete delete macro, and Home / End navigation still need end-to-end
confirmation. Xbox labels describe equivalent mappings, not a separate hardware
test.

This revision replaces trigger zoom, Square/X insert, Triangle/Y transition, and
the extra browser shortcuts with the focused editing controls above.

Shortcut reference: [Apple's iMovie keyboard shortcuts](https://support.apple.com/guide/imovie/keyboard-shortcuts-movd9d8f91e8/mac).
