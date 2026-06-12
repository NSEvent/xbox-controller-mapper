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

# Keep in sync with zoom_for in capture-screenshots.sh — the recordings use
# the same per-variant magnification as the stills.
zoom_for() {
    case "$1" in
        xbox|nintendo|dualshock) echo "1.15" ;;
        dualsense)               echo "1.05" ;;
        dualsense-edge)          echo "1.0" ;;
        xbox-elite)              echo "1.0" ;;
        steam)                   echo "1.0" ;;
        appletv)                 echo "1.05" ;;
        *)                       echo "1.0" ;;
    esac
}

# Screen region (x,y,w,h in points) holding the Buttons-tab minimap when the
# window sits at WIN_X/WIN_Y with size WIN_W/WIN_H, the staged config, and
# the zoom_for magnification. Derived from the battery indicator's position
# in the corresponding still captures; re-derive if layouts or zooms change.
region_for() {
    case "$1" in
        xbox)           echo "789,469,470,307" ;;
        nintendo)       echo "789,467,470,312" ;;
        dualshock)      echo "789,575,470,281" ;;
        dualsense)      echo "807,583,437,278" ;;
        dualsense-edge) echo "816,484,420,268" ;;
        xbox-elite)     echo "816,390,420,271" ;;
        steam)          echo "816,448,420,275" ;;
        appletv)        echo "916,402,224,696" ;;
        *)              echo "789,469,470,307" ;;
    esac
}

quit_app() {
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
}

position_window() {
    # Position/size the main window and VERIFY it took — window restoration
    # can race the first set right after launch, which silently leaves the
    # window at its restored frame (and every fixed-region capture wrong).
    local attempt
    for attempt in 1 2 3 4 5; do
        osascript \
            -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set position of (first window whose name is \"$APP_NAME\") to {$WIN_X, $WIN_Y}" \
            -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set size of (first window whose name is \"$APP_NAME\") to {$WIN_W, $WIN_H}" >/dev/null 2>&1 || true
        sleep 0.6
        local frame
        frame="$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to get {position, size} of (first window whose name is \"$APP_NAME\")" 2>/dev/null | tr -d ' ')"
        if [[ "$frame" == "$WIN_X,$WIN_Y,$WIN_W,$WIN_H" ]]; then
            return 0
        fi
    done
    echo "ERROR: could not position the $APP_NAME window (frame: ${frame:-unknown})" >&2
    return 1
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

# Crop a full-screen clip down to a point-region and assemble the GIF.
# screencapture's video mode mis-maps -R regions on scaled (non-2x) displays,
# so we always record the whole screen and crop here, converting points to
# video pixels via the actual recorded-width / display-width ratio.
make_gif() {
    local clip="$1" out="$2" region="$3"
    local rx ry rw rh vidw dispw
    IFS=, read -r rx ry rw rh <<< "$region"
    vidw=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$clip")
    dispw=$(python3 -c 'import Quartz; print(int(Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()).size.width))')
    read -r cx cy cw ch <<< "$(python3 -c "
s = $vidw / $dispw
print(int($rx*s), int($ry*s), int($rw*s)//2*2, int($rh*s)//2*2)")"
    ffmpeg -y -loglevel error -i "$clip" \
        -vf "crop=${cw}:${ch}:${cx}:${cy},fps=$FPS,scale=$GIF_WIDTH:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
        -loop 0 "$out"
    echo "   $(basename "$out") ($(du -h "$out" | cut -f1 | tr -d ' '))"
}

record_variant() {
    local variant="$1"
    local clip="$TMP_DIR/$variant.mov"

    echo "── GIF: $variant"
    quit_app
    open -a "$APP_NAME" --args --screenshot-variant "$variant" --screenshot-animate --screenshot-zoom "$(zoom_for "$variant")"
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null
    sleep 0.5
    position_window
    park_pointer
    sleep 1

    screencapture -v -V "$DURATION" "$clip" 2>/dev/null
    make_gif "$clip" "$OUT_DIR/$variant.gif" "$(region_for "$variant")"
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
        screencapture -v -V "$DURATION" "$clip" 2>/dev/null
        make_gif "$clip" "$OUT_DIR/stream-overlay.gif" "$frame"
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
