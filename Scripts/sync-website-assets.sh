#!/bin/bash
# sync-website-assets.sh — push the canonical marketing assets to every
# consumer that can't reference the repo directly.
#
# The repo's screenshots/ tree is the single source of truth (regenerate
# with `make screenshots` / `make demo-gifs`). Consumers:
#
#   1. README.md            — references screenshots/... directly; nothing to
#                             do, it updates with the repo.
#   2. screenshots/gumroad-gallery/ — curated picks for the Gumroad listing,
#                             refreshed here from their canonical sources.
#   3. The marketing site   — kevintang.xyz/apps/controller-keys mirrors the
#                             variant folders by identical filenames, so a
#                             straight copy refreshes every <img> in place.
#                             GIFs land in gifs/ for embedding.
#
# Usage:
#   ./Scripts/sync-website-assets.sh [path-to-site-dir]
#   (default: ~/projects/kevintang.xyz/apps/controller-keys)
#
# Publishing the site afterwards:
#   cd ~/projects/kevintang.xyz && git add apps/controller-keys && \
#   git commit -m "Refresh ControllerKeys screenshots" && git push

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/screenshots"
SITE_DIR="${1:-$HOME/projects/kevintang.xyz/apps/controller-keys}"

# ── Gumroad gallery (curated picks) ──
GALLERY="$SRC/gumroad-gallery"
mkdir -p "$GALLERY"
cp "$SRC/dualsense/01-buttons.png"        "$GALLERY/01-dualsense-buttons.png"
cp "$SRC/apple-tv-remote/01-buttons.png"  "$GALLERY/02-apple-tv-remote-buttons.png"
cp "$SRC/steam-controller/01-buttons.png" "$GALLERY/03-steam-controller-buttons.png"
cp "$SRC/dualsense/06-scripts.png"        "$GALLERY/04-scripts.png"
cp "$SRC/dualsense/05-macros.png"         "$GALLERY/05-macros.png"
cp "$SRC/dualsense/14-stats.png"          "$GALLERY/06-stats-wrapped.png"
cp "$SRC/xbox-elite/01-buttons.png"       "$GALLERY/07-xbox-elite-buttons.png"
cp "$SRC/stream-overlay/dualsense.png"    "$GALLERY/08-stream-overlay.png"
echo "Refreshed gumroad-gallery (8 images)"

# ── Marketing site ──
if [[ ! -d "$SITE_DIR" ]]; then
    echo "Site dir not found: $SITE_DIR — skipping site sync." >&2
    exit 0
fi

# Variant folders mirror by filename; copy all variants so the site can
# adopt new controllers without re-plumbing.
for dir in dualsense xbox-series-xs steam-controller apple-tv-remote \
           dualsense-edge dualshock-4 nintendo xbox-elite \
           8bitdo-zero2 8bitdo-micro gifs stream-overlay; do
    if [[ -d "$SRC/$dir" ]]; then
        mkdir -p "$SITE_DIR/$dir"
        cp "$SRC/$dir/"*.{png,gif} "$SITE_DIR/$dir/" 2>/dev/null || \
            cp "$SRC/$dir/"*.png "$SITE_DIR/$dir/" 2>/dev/null || \
            cp "$SRC/$dir/"*.gif "$SITE_DIR/$dir/" 2>/dev/null || true
    fi
done
cp "$SRC/on-screen-keyboard.png" "$SITE_DIR/on-screen-keyboard.png"

echo "Synced screenshots + GIFs to $SITE_DIR"
echo "Publish with:"
echo "  cd $(dirname "$(dirname "$SITE_DIR")") && git add apps/controller-keys && git commit -m 'Refresh ControllerKeys screenshots' && git push"
