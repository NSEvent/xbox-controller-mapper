#!/bin/bash
# capture-demo-gifs.sh — looping marketing GIFs of the controller minimaps
# reacting to input.
#
# Launches the app with --screenshot-variant <v> --screenshot-animate, which
# forces the preview to the requested controller and runs a scripted input
# loop (sweeping sticks, breathing triggers, face/d-pad taps, drifting
# touchpad finger — see ControllerService+ScreenshotDemo.swift). Records the
# minimap region with screencapture's video mode, then assembles a
# palette-optimized looping GIF with ffmpeg.
#
# Also records the floating stream overlay panel once (dualsense variant).
#
# Usage:
#   ./Scripts/capture-demo-gifs.sh [variant ...]
#
#   variants:   dualsense xbox steam appletv dualsense-edge dualshock nintendo xbox-elite
#   default:    xbox dualsense steam appletv
#
# Config staging is shared with capture-screenshots.sh (--stage-only /
# --restore-only) so the demo content and zoom level match the screenshots.
#
# Requirements: ffmpeg (brew install ffmpeg), plus the same Accessibility +
# Screen Recording permissions as capture-screenshots.sh.
#
# Output: screenshots/gifs/<variant>.gif (~640px wide, 12 fps, 8 s loop)

set -euo pipefail

APP_NAME="ControllerKeys"
WIN_X=100 WIN_Y=100 WIN_W=1600 WIN_H=1000
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/screenshots/gifs"
LAUNCH_WAIT=4
DURATION=8       # seconds of recording per variant
FPS=12           # GIF frame rate
GIF_WIDTH=640    # output width in pixels

command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg" >&2; exit 1; }

VARIANTS=("$@")
[[ ${#VARIANTS[@]} -gt 0 ]] || VARIANTS=(xbox dualsense steam appletv)

# Screen region (x,y,w,h in points) holding the Buttons-tab minimap when the
# window sits at WIN_X/WIN_Y with size WIN_W/WIN_H and the staged config's
# default zoom. Margins absorb the per-variant frame differences.
region_for() {
    case "$1" in
        appletv) echo "925,445,210,490" ;;
        # PlayStation layouts show the touchpad section above the preview,
        # which pushes the minimap down a bit.
        dualsense|dualsense-edge|dualshock) echo "795,570,365,290" ;;
        *)       echo "820,485,320,250" ;;
    esac
}

quit_app() {
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
}

position_window() {
    osascript \
        -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set position of window 1 to {$WIN_X, $WIN_Y}" \
        -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set size of window 1 to {$WIN_W, $WIN_H}" >/dev/null
}

overlay_frame() {
    osascript <<'EOS'
tell application "System Events"
    tell process "ControllerKeys"
        repeat with w in windows
            if name of w is "ControllerKeys Overlay" then
                set p to position of w
                set s to size of w
                return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
            end if
        end repeat
    end tell
end tell
EOS
}

position_overlay_panel() {
    osascript <<EOS
tell application "System Events"
    tell process "ControllerKeys"
        repeat with w in windows
            if name of w is "ControllerKeys Overlay" then
                set position of w to {$1, $2}
            end if
        end repeat
    end tell
end tell
EOS
}

park_pointer() {
    /usr/bin/python3 -c 'import Quartz; Quartz.CGWarpMouseCursorPosition((1650, 980))' 2>/dev/null || true
}

make_gif() {
    local clip="$1" out="$2"
    ffmpeg -y -loglevel error -i "$clip" \
        -vf "fps=$FPS,scale=$GIF_WIDTH:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
        -loop 0 "$out"
    echo "   $(basename "$out") ($(du -h "$out" | cut -f1 | tr -d ' '))"
}

record_variant() {
    local variant="$1"
    local clip="$TMP_DIR/$variant.mov"

    echo "── GIF: $variant"
    quit_app
    open -a "$APP_NAME" --args --screenshot-variant "$variant" --screenshot-animate
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null
    sleep 0.5
    position_window
    park_pointer
    sleep 1

    screencapture -v -R "$(region_for "$variant")" -V "$DURATION" "$clip"
    make_gif "$clip" "$OUT_DIR/$variant.gif"
}

record_stream_overlay() {
    local variant="dualsense"
    local clip="$TMP_DIR/stream-overlay.mov"

    echo "── GIF: stream overlay ($variant)"
    quit_app
    defaults write KevinTang.XboxControllerMapper streamOverlayEnabled -bool true
    defaults delete KevinTang.XboxControllerMapper streamOverlayPositions 2>/dev/null || true

    open -a "$APP_NAME" --args --screenshot-variant "$variant" --screenshot-animate
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null
    sleep 0.5
    position_window
    park_pointer
    # The sidebar's lower half is uniformly dark in every variant
    position_overlay_panel 115 640
    sleep 1

    local frame
    frame="$(overlay_frame)"
    if [[ -z "$frame" ]]; then
        echo "   WARN: stream overlay panel not found" >&2
    else
        screencapture -v -R "$frame" -V "$DURATION" "$clip"
        make_gif "$clip" "$OUT_DIR/stream-overlay.gif"
    fi

    quit_app
    defaults write KevinTang.XboxControllerMapper streamOverlayEnabled -bool false
}

# ─── Main ───

mkdir -p "$OUT_DIR"
TMP_DIR="$(mktemp -d /tmp/controllerkeys-gifs.XXXXXX)"

"$REPO_ROOT/Scripts/capture-screenshots.sh" --stage-only
trap '"$REPO_ROOT/Scripts/capture-screenshots.sh" --restore-only; rm -rf "$TMP_DIR"' EXIT

for v in "${VARIANTS[@]}"; do
    record_variant "$v"
done

record_stream_overlay

quit_app
open -a "$APP_NAME" 2>/dev/null || true

echo "Done. GIFs in $OUT_DIR/"
