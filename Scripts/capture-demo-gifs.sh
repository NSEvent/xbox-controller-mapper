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
        xbox|nintendo|dualshock) echo "0.92" ;;
        dualsense)               echo "0.88" ;;
        dualsense-edge)          echo "0.83" ;;
        xbox-elite)              echo "0.83" ;;
        steam)                   echo "0.83" ;;
        appletv)                 echo "0.88" ;;
        *)                       echo "0.83" ;;
    esac
}

# Screen region (x,y,w,h in points) holding the Buttons-tab minimap when the
# window sits at WIN_X/WIN_Y with size WIN_W/WIN_H, the staged config, and
# the zoom_for magnification. Derived from the battery indicator's position
# in the corresponding still captures; re-derive if layouts or zooms change.
region_for() {
    case "$1" in
        xbox)           echo "766,480,520,325" ;;
        nintendo)       echo "766,479,520,329" ;;
        dualshock)      echo "766,573,520,302" ;;
        dualsense)      echo "774,575,503,307" ;;
        dualsense-edge) echo "783,486,486,297" ;;
        xbox-elite)     echo "783,402,486,299" ;;
        steam)          echo "783,455,486,303" ;;
        appletv)        echo "914,408,232,687" ;;
        *)              echo "766,480,520,325" ;;
    esac
}

quit_app() {
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
}

position_window() {
    # In screenshot mode the app pins its own window to the capture frame
    # (see AppRuntime.positionMainWindowForScreenshots) - just wait for the
    # frame to land and verify via the window server. No Accessibility API:
    # its per-process trees can wedge under heavy automation.
    local attempt
    for attempt in 1 2 3 4 5 6 7 8; do
        if python3 - "$APP_NAME" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H" <<'PY'
import sys
import Quartz
name, x, y, w, h = sys.argv[1], *map(int, sys.argv[2:6])
opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
for win in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID) or []:
    if win.get("kCGWindowOwnerName") == name:
        b = win.get("kCGWindowBounds", {})
        if (int(b.get("X", -1)), int(b.get("Y", -1)), int(b.get("Width", 0)), int(b.get("Height", 0))) == (x, y, w, h):
            sys.exit(0)
sys.exit(1)
PY
        then
            return 0
        fi
        sleep 1
    done
    echo "ERROR: $APP_NAME window never reached ${WIN_X},${WIN_Y} ${WIN_W}x${WIN_H}" >&2
    return 1
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
    open -a "$APP_NAME" --args --screenshot-variant "$variant" --screenshot-animate --screenshot-zoom "$(zoom_for "$variant")" --screenshot-overlay
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null
    park_pointer
    position_window
    sleep 1

    # Fixed panel placement in screenshot mode (see AppRuntime)
    screencapture -v -V "$DURATION" "$clip" 2>/dev/null
    make_gif "$clip" "$OUT_DIR/stream-overlay.gif" "105,630,240,230"

    quit_app
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
