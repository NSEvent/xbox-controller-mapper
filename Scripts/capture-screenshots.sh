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
# Normalize the user's pinch-zoom so tall layouts aren't clipped in captures.
config.pop("uiScale", None)

# Populate the command wheel so the Wheel tab shows a representative set
# of actions instead of an empty circle.
def _mods(command=False, option=False, shift=False, control=False):
    return {"command": command, "option": option, "shift": shift, "control": control}

staged[0]["commandWheelActions"] = [
    {"id": "5C0FFEE5-0000-4000-8000-000000000001", "displayName": "Copy",
     "iconName": "doc.on.doc", "keyCode": 8, "modifiers": _mods(command=True)},
    {"id": "5C0FFEE5-0000-4000-8000-000000000002", "displayName": "Paste",
     "iconName": "doc.on.clipboard", "keyCode": 9, "modifiers": _mods(command=True)},
    {"id": "5C0FFEE5-0000-4000-8000-000000000003", "displayName": "Screenshot",
     "iconName": "camera.viewfinder", "keyCode": 21, "modifiers": _mods(command=True, shift=True)},
    {"id": "5C0FFEE5-0000-4000-8000-000000000004", "displayName": "Spotlight",
     "iconName": "magnifyingglass", "keyCode": 49, "modifiers": _mods(command=True)},
    {"id": "5C0FFEE5-0000-4000-8000-000000000005", "displayName": "Safari", "modifiers": _mods(),
     "systemCommand": {"type": "launchApp", "bundleIdentifier": "com.apple.Safari", "newWindow": False}},
    {"id": "5C0FFEE5-0000-4000-8000-000000000006", "displayName": "Terminal", "modifiers": _mods(),
     "systemCommand": {"type": "launchApp", "bundleIdentifier": "com.apple.Terminal", "newWindow": False}},
    {"id": "5C0FFEE5-0000-4000-8000-000000000007", "displayName": "Music", "modifiers": _mods(),
     "systemCommand": {"type": "launchApp", "bundleIdentifier": "com.apple.Music", "newWindow": False}},
    {"id": "5C0FFEE5-0000-4000-8000-000000000008", "displayName": "Undo",
     "iconName": "arrow.uturn.backward", "keyCode": 6, "modifiers": _mods(command=True)},
]

# Round out the Scripts tab with a few of the app's bundled examples so the
# capture shows the breadth of the scripting API (app-aware logic, state,
# clipboard, window management) rather than just the two screenshot scripts.
_now = "2026-06-01T12:00:00Z"
_example_scripts = [
    {"name": "App-Aware Undo",
     "description": "Sends Cmd+Z in most apps, but Cmd+Shift+Z in Photoshop (which uses Cmd+Z for toggle undo/redo).",
     "source": 'if (app.is("com.adobe.Photoshop")) {\n    press(6, {command: true, shift: true});\n} else {\n    press(6, {command: true});\n}'},
    {"name": "Toggle Mute (Zoom/Meet)",
     "description": "Mutes/unmutes in Zoom or Google Meet with the right shortcut for each app.",
     "source": 'if (app.is("us.zoom.xos")) {\n    press(0, {command: true, shift: true});\n    var muted = state.toggle("zoom_muted");\n    notify(muted ? "Muted" : "Unmuted");\n}'},
    {"name": "Window Snap Left/Right",
     "description": "Snaps the current window left on D-pad Left, right on D-pad Right using Rectangle or similar window manager.",
     "source": 'if (trigger.button === "dpadLeft") {\n    press(123, {control: true, option: true});\n} else if (trigger.button === "dpadRight") {\n    press(124, {control: true, option: true});\n}'},
    {"name": "Search Selected Text",
     "description": "Copies the selected text and searches for it in your default browser.",
     "source": 'var before = clipboard.get();\npress(8, {command: true});\ndelay(0.5);\nvar after = clipboard.get();\nif (after !== before) {\n    openURL("https://www.google.com/search?q=" + encodeURIComponent(after));\n}'},
]
existing_script_names = {s.get("name") for s in staged[0].get("scripts", [])}
for i, s in enumerate(_example_scripts):
    if s["name"] not in existing_script_names:
        staged[0].setdefault("scripts", []).append({
            "id": f"5C0FFEE5-1111-4000-8000-00000000000{i+1}",
            "name": s["name"], "description": s["description"], "source": s["source"],
            "createdAt": _now, "modifiedAt": _now,
        })

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
# Audience-neutral names for rows that read as test data in captures.
_sequence_renames = {"bye": "Sleep Display", "iTerm": "Open Terminal"}
for seq in staged[0].get("sequenceMappings", []):
    if seq.get("hint") in _sequence_renames:
        seq["hint"] = _sequence_renames[seq["hint"]]
_macro_renames = {"Check NVDA news": "Morning News Routine", "Rearview Mirror": "Toggle Rear View"}
for macro in staged[0].get("macros", []):
    if macro.get("name") in _macro_renames:
        macro["name"] = _macro_renames[macro["name"]]

# Light the P1 player LED so the LEDs tab doesn't show five empty dots.
staged[0].setdefault("dualSenseLEDSettings", {}).setdefault("playerLEDs", {})["led3"] = True

# The on-screen keyboard's app bar and website links are personal; swap in
# stock apps and well-known sites (favicons resolve at runtime).
osk = staged[0].setdefault("onScreenKeyboardSettings", {})
osk["appBarItems"] = [
    {"id": f"5C0FFEE5-2222-4000-8000-00000000000{i}", "bundleIdentifier": b, "displayName": n}
    for i, (b, n) in enumerate([
        ("com.apple.Safari", "Safari"),
        ("com.apple.Notes", "Notes"),
        ("com.apple.Music", "Music"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.apple.Terminal", "Terminal"),
        ("com.apple.Photos", "Photos"),
    ], start=1)
]
osk["websiteLinks"] = [
    {"id": f"5C0FFEE5-3333-4000-8000-00000000000{i}", "url": u, "displayName": n}
    for i, (u, n) in enumerate([
        ("https://github.com", "GitHub"),
        ("https://news.ycombinator.com", "Hacker News"),
        ("https://www.youtube.com", "YouTube"),
        ("https://en.wikipedia.org", "Wikipedia"),
    ], start=1)
]

with open(dst, "w") as f:
    json.dump(config, f, indent=2)
print(f"Staged config with {len(staged)} profiles (active: {staged[0]['name']})")

# Seed a few history snapshots so the History tab isn't an empty state.
# Cleaned up by restore_config (they all carry the staged- filename marker).
import os
snap_dir = os.path.join(os.path.dirname(dst), "snapshots")
os.makedirs(snap_dir, exist_ok=True)
seeds = [
    ("snapshot_2026-06-02_09-14-05-000-staged", "2026-06-02T09:14:05Z", "Before deleting profile “Old Setup”"),
    ("snapshot_2026-06-05_18-40-22-000-staged", "2026-06-05T18:40:22Z", "Before importing “Racing.controllerkeys”"),
    ("snapshot_2026-06-09_21-03-47-000-staged", "2026-06-09T21:03:47Z", "Before restoring snapshot from Jun 5, 2026"),
]
for stem, created, reason in seeds:
    with open(os.path.join(snap_dir, f"{stem}.json"), "w") as f:
        json.dump({"reason": reason, "createdAt": created, "configuration": config}, f)
print(f"Seeded {len(seeds)} history snapshots")
PY
}

restore_config() {
    if [[ -e "$CONFIG_BACKUP" ]]; then
        mv -f "$CONFIG_BACKUP" "$CONFIG_PATH"
        echo "Restored original config."
    fi
    # Remove the seeded history snapshots (marked with -staged in the stem).
    rm -f "$HOME/.config/controllerkeys/snapshots/"snapshot_*-staged.json
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

# Prints "x,y,w,h" of the floating stream overlay panel (found via the
# accessibility API — borderless panels don't show up in CGWindowList).
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

# Variants worth a standalone stream-overlay capture (the panel renders the
# same minimap as the Buttons tab, scaled down).
overlay_wanted() {
    case "$1" in
        xbox|dualsense|steam|appletv) return 0 ;;
        *) return 1 ;;
    esac
}

# Park the panel over the main window's uniform dark canvas so the
# semi-transparent backdrop reads clean, and keep the pointer away so the
# hover close button stays hidden.
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

capture_stream_overlay() {
    local variant="$1"
    local out_dir="$OUT_ROOT/stream-overlay"
    mkdir -p "$out_dir"

    quit_app
    defaults write KevinTang.XboxControllerMapper streamOverlayEnabled -bool true
    defaults delete KevinTang.XboxControllerMapper streamOverlayPositions 2>/dev/null || true

    open -a "$APP_NAME" --args --screenshot-variant "$variant"
    sleep "$LAUNCH_WAIT"
    osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null
    sleep 0.5
    position_window
    # Pointer well away from the panel so the close button stays hidden
    /usr/bin/python3 -c 'import Quartz; Quartz.CGWarpMouseCursorPosition((1650, 980))' 2>/dev/null || true
    # The sidebar's lower half is uniformly dark in every variant
    position_overlay_panel 115 640
    sleep 1

    local frame
    frame="$(overlay_frame)"
    if [[ -z "$frame" ]]; then
        echo "   WARN: stream overlay panel not found for $variant" >&2
    else
        screencapture -x -R "$frame" "$out_dir/$variant.png"
        echo "   stream-overlay/$variant.png"
    fi

    quit_app
    defaults write KevinTang.XboxControllerMapper streamOverlayEnabled -bool false
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
TABS=1
VARIANTS=()
for arg in "$@"; do
    case "$arg" in
        --build) BUILD=1 ;;
        --no-stage) STAGE=0 ;;
        # Skip the per-tab walks and only capture the stream overlay panels.
        --overlays-only) TABS=0 ;;
        # Stage/restore the config and exit — used by capture-demo-gifs.sh
        # to share the same curated sidebar and demo content.
        --stage-only) quit_app; stage_config; exit 0 ;;
        --restore-only) quit_app; restore_config; exit 0 ;;
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

if [[ "$TABS" == "1" ]]; then
    for v in "${VARIANTS[@]}"; do
        capture_variant "$v"
    done
fi

# Standalone captures of the floating stream overlay panel for the
# representative variants.
echo "── Stream overlay captures"
for v in "${VARIANTS[@]}"; do
    if overlay_wanted "$v"; then
        capture_stream_overlay "$v"
    fi
done

quit_app
if [[ "$STAGE" == "1" ]]; then
    restore_config
    trap - EXIT
fi

# Relaunch the app normally (without screenshot mode)
open -a "$APP_NAME" 2>/dev/null || true

echo "Done. Output in $OUT_ROOT/"
