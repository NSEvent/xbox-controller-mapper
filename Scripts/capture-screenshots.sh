#!/bin/bash
# capture-screenshots.sh — repeatable marketing/README screenshot capture.
#
# Launches the app in screenshot mode (--screenshot-variant, see AppRuntime in
# XboxControllerMapperApp.swift) which disables hardware monitoring and forces
# the controller preview to the requested variant — so captures are
# deterministic even with controllers paired. Then walks every visible
# main-window tab with Cmd+Right, capturing each one.
#
# Usage:
#   ./Scripts/capture-screenshots.sh [--build] [--no-stage] [variant ...]
#
#   variants:   dualsense xbox steam appletv dualsense-edge dualshock nintendo xbox-elite
#   default:    dualsense xbox steam appletv
#   --build:    run `make install BUILD_FROM_SOURCE=1` first
#   --no-stage: skip config staging (capture with your live profile sidebar as-is)
#
# Config staging: by default the script derives a clean temporary config from
# your live one — keeping only the profiles in KEEP_PROFILES below and
# activating the first — so the sidebar looks curated and identical across
# runs. Your real config is moved aside and restored afterwards (trap on exit).
#
# Requirements (one-time, for the terminal running this script):
#   - Accessibility permission (System Settings > Privacy & Security > Accessibility)
#   - Screen Recording permission (Privacy & Security > Screen & System Audio Recording)
#
# Output: screenshots/<variant-dir>/NN-<tab>.png at a fixed 1600x1000pt window
# (3200x2000px on Retina), captured without the window shadow so dimensions
# are exact and consistent across runs.

set -euo pipefail

APP_NAME="ControllerKeys"
WIN_X=100 WIN_Y=100 WIN_W=1600 WIN_H=1000
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="$REPO_ROOT/screenshots"
LAUNCH_WAIT=4      # seconds to wait for app launch before first capture
TAB_WAIT=0.8       # seconds to wait after each tab switch

CONFIG_PATH="$HOME/.config/controllerkeys/config.json"
CONFIG_BACKUP="$HOME/.config/controllerkeys/config.json.pre-screenshots"
# Profiles to keep in the staged sidebar, in this order. First one is activated.
KEEP_PROFILES=("Default" "Doom" "Factorio" "Anki - AnKing (USMLE)" "Anki Flashcards" "Apple TV Remote")

# Tab lists must match MainWindowSection.displayOrder filtered by
# MainWindowSection.isAvailable() in ContentView.swift:
#   touchpad: PlayStation || Steam || AppleTV
#   leds: PlayStation, microphone: DualSense
#   gestures: hasMotion (DualSense || DualShock || Steam)
tabs_for() {
    case "$1" in
        dualsense|dualsense-edge|dualshock)
                   echo "buttons chords sequences gestures macros scripts wheel input joysticks touchpad leds microphone keyboard stats history" ;;
        xbox|xbox-elite|nintendo)
                   echo "buttons chords sequences macros scripts wheel input joysticks keyboard stats history" ;;
        steam)     echo "buttons chords sequences gestures macros scripts wheel input joysticks touchpad keyboard stats history" ;;
        appletv)   echo "buttons chords sequences macros scripts wheel input joysticks touchpad keyboard stats history" ;;
        *) echo "" ;;
    esac
}

# DualShock has no microphone tab (microphone is DualSense-only).
tabs_for_exact() {
    local tabs; tabs="$(tabs_for "$1")"
    if [[ "$1" == "dualshock" ]]; then
        tabs="${tabs/ microphone/}"
    fi
    echo "$tabs"
}

dir_for() {
    case "$1" in
        dualsense)      echo "dualsense" ;;
        dualsense-edge) echo "dualsense-edge" ;;
        dualshock)      echo "dualshock-4" ;;
        xbox)           echo "xbox-series-xs" ;;
        xbox-elite)     echo "xbox-elite" ;;
        nintendo)       echo "nintendo" ;;
        steam)          echo "steam-controller" ;;
        appletv)        echo "apple-tv-remote" ;;
    esac
}

quit_app() {
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
}

stage_config() {
    [[ -f "$CONFIG_PATH" ]] || { echo "No config at $CONFIG_PATH — skipping staging."; return 0; }
    if [[ -e "$CONFIG_BACKUP" ]]; then
        echo "ERROR: $CONFIG_BACKUP already exists (previous run crashed?)." >&2
        echo "Restore it with: mv '$CONFIG_BACKUP' '$CONFIG_PATH'" >&2
        exit 1
    fi
    mv "$CONFIG_PATH" "$CONFIG_BACKUP"
    KEEP_JSON="$(printf '%s\n' "${KEEP_PROFILES[@]}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')"
    python3 - "$CONFIG_BACKUP" "$CONFIG_PATH" "$KEEP_JSON" <<'PY'
import json
import sys

src, dst, keep_json = sys.argv[1], sys.argv[2], sys.argv[3]
keep = json.loads(keep_json)
with open(src) as f:
    config = json.load(f)

by_name = {}
for profile in config["profiles"]:
    # First occurrence wins (the live config may contain duplicate names)
    by_name.setdefault(profile["name"], profile)

staged = [by_name[name] for name in keep if name in by_name]
if not staged:
    sys.exit("None of KEEP_PROFILES matched — aborting instead of writing an empty config.")
config["profiles"] = staged
config["activeProfileId"] = staged[0]["id"]

# Replace personal quick texts / terminal commands with demo content so the
# on-screen keyboard captures are safe to publish.
staged[0].setdefault("onScreenKeyboardSettings", {})["quickTexts"] = [
    {"text": "Hello from my controller!", "isTerminalCommand": False},
    {"text": "On my way", "isTerminalCommand": False},
    {"text": "Thanks!", "isTerminalCommand": False},
    {"text": "kevintang.xyz", "isTerminalCommand": False},
    {"text": "claude", "isTerminalCommand": True},
    {"text": "git status", "isTerminalCommand": True},
    {"text": "make install", "isTerminalCommand": True},
    {"text": "npm run dev", "isTerminalCommand": True},
]
with open(dst, "w") as f:
    json.dump(config, f, indent=2)
print(f"Staged config with {len(staged)} profiles (active: {staged[0]['name']})")
PY
}

restore_config() {
    if [[ -e "$CONFIG_BACKUP" ]]; then
        mv -f "$CONFIG_BACKUP" "$CONFIG_PATH"
        echo "Restored original config."
    fi
}

window_id() {
    python3 - "$APP_NAME" <<'PY'
import sys
import Quartz
name = sys.argv[1]
opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID) or []:
    if w.get("kCGWindowOwnerName") == name and w.get("kCGWindowLayer", 1) == 0:
        if w.get("kCGWindowBounds", {}).get("Width", 0) > 400:
            print(int(w["kCGWindowNumber"]))
            break
PY
}

position_window() {
    osascript \
        -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set position of window 1 to {$WIN_X, $WIN_Y}" \
        -e "tell application \"System Events\" to tell process \"$APP_NAME\" to set size of window 1 to {$WIN_W, $WIN_H}"
}

# Prints "id width" for every on-screen window owned by the app (any layer,
# including panels like the on-screen keyboard).
list_windows() {
    python3 - "$APP_NAME" <<'PY'
import sys
import Quartz
name = sys.argv[1]
opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID) or []:
    if w.get("kCGWindowOwnerName") == name:
        bounds = w.get("kCGWindowBounds", {})
        print(int(w["kCGWindowNumber"]), int(bounds.get("Width", 0)))
PY
}

# Toggles the on-screen keyboard via its global shortcut (Cmd+Shift+K in the
# staged Default profile) and captures the keyboard panel window by itself —
# a clean widget shot with no background dependency.
capture_keyboard_overlay() {
    local main_wid="$1" out="$2"
    osascript -e 'tell application "System Events" to keystroke "k" using {command down, shift down}'
    sleep 2
    local kb_wid
    kb_wid="$(list_windows | awk -v main="$main_wid" '$1 != main && $2 > 300 { print $1; exit }')"
    if [[ -z "$kb_wid" ]]; then
        echo "   WARN: on-screen keyboard window not found — is Cmd+Shift+K bound in the active profile?" >&2
    else
        screencapture -o -x -l "$kb_wid" "$out"
        echo "   $(basename "$out") (overlay)"
    fi
    osascript -e 'tell application "System Events" to keystroke "k" using {command down, shift down}'
    sleep 1
}

next_tab() {
    # Cmd+Right (key code 124) — bound to "Next Tab" in ContentView
    osascript -e 'tell application "System Events" to key code 124 using {command down}'
}

capture_variant() {
    local variant="$1"
    local dir tabs wid n=1
    dir="$OUT_ROOT/$(dir_for "$variant")"
    tabs="$(tabs_for_exact "$variant")"
    [[ -n "$tabs" ]] || { echo "Unknown variant: $variant" >&2; return 1; }
    mkdir -p "$dir"

    echo "── Variant: $variant -> $dir"
    quit_app
    open -a "$APP_NAME" --args --screenshot-variant "$variant"
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate"
    sleep 1
    position_window
    sleep 1

    wid="$(window_id)"
    if [[ -z "$wid" ]]; then
        echo "ERROR: could not find $APP_NAME window. Is the app running and visible?" >&2
        return 1
    fi

    for tab in $tabs; do
        local file
        file="$dir/$(printf '%02d' "$n")-$tab.png"
        screencapture -o -x -l "$wid" "$file"
        echo "   $(basename "$file")"
        next_tab
        sleep "$TAB_WAIT"
        n=$((n + 1))
    done

    # The keyboard widget is controller-independent; capture it once, during
    # the dualsense pass.
    if [[ "$variant" == "dualsense" ]]; then
        capture_keyboard_overlay "$wid" "$OUT_ROOT/on-screen-keyboard.png"
    fi
}

# ─── Main ───

BUILD=0
STAGE=1
VARIANTS=()
for arg in "$@"; do
    case "$arg" in
        --build) BUILD=1 ;;
        --no-stage) STAGE=0 ;;
        *) VARIANTS+=("$arg") ;;
    esac
done
[[ ${#VARIANTS[@]} -gt 0 ]] || VARIANTS=(dualsense xbox steam appletv)

if [[ "$BUILD" == "1" ]]; then
    echo "Building and installing $APP_NAME..."
    make -C "$REPO_ROOT" install BUILD_FROM_SOURCE=1
fi

if [[ "$STAGE" == "1" ]]; then
    quit_app
    stage_config
    trap 'quit_app; restore_config' EXIT
fi

for v in "${VARIANTS[@]}"; do
    capture_variant "$v"
done

quit_app
if [[ "$STAGE" == "1" ]]; then
    restore_config
    trap - EXIT
fi

# Relaunch the app normally (without screenshot mode)
open -a "$APP_NAME" 2>/dev/null || true

echo "Done. Output in $OUT_ROOT/"
