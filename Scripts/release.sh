#!/bin/bash
set -euo pipefail

# ControllerKeys Release Script
# This script orchestrates the full release workflow:
# 1. Validates git state
# 2. Builds, signs, and notarizes the app
# 3. Creates a GitHub release with artifacts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Load version
source version.env

echo "=== ControllerKeys Release v${MARKETING_VERSION} (${BUILD_NUMBER}) ==="
echo ""

# Check for required tools
command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI (gh) is required. Install with: brew install gh"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "Error: Xcode command line tools are required."; exit 1; }

# Locate Sparkle's generate_appcast (ships with the Sparkle SPM artifact). It
# EdDSA-signs the DMG using the private key in your login keychain.
GENERATE_APPCAST="$(command -v generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
    GENERATE_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)"
fi
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "Error: generate_appcast not found. Build the app once (so SPM fetches Sparkle) or install the Sparkle tools."
    exit 1
fi

# Validate git state
echo "Checking git state..."
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: Working directory is not clean. Commit or stash changes first."
    git status --short
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Warning: Not on main branch (currently on $BRANCH)"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Check if tag already exists
TAG="v${MARKETING_VERSION}"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: Tag $TAG already exists. Bump version in version.env first."
    exit 1
fi

echo ""
echo "Pre-release checklist:"
echo "  - Version: ${MARKETING_VERSION}"
echo "  - Build: ${BUILD_NUMBER}"
echo "  - Tag: ${TAG}"
echo "  - Branch: ${BRANCH}"
echo ""
read -p "Proceed with release? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 1

# Build, sign, and notarize
echo ""
echo "=== Building and Notarizing ==="
"$SCRIPT_DIR/sign-and-notarize.sh"

# Find the built artifacts
RELEASE_DIR="$PROJECT_ROOT/release"
APP_DMG="$RELEASE_DIR/ControllerKeys-${MARKETING_VERSION}.dmg"

if [[ ! -f "$APP_DMG" ]]; then
    echo "Error: Release artifact not found at $APP_DMG"
    exit 1
fi

# Generate the Sparkle appcast. Run it against a clean staging dir holding only
# this release's DMG so the feed lists just the latest version with the correct
# per-tag download URL (the DMG is attached to this release below).
echo ""
echo "=== Generating Sparkle appcast ==="
DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPO:-NSEvent/xbox-controller-mapper}/releases/download/${TAG}/"
APPCAST_STAGE="$(mktemp -d)"
cp "$APP_DMG" "$APPCAST_STAGE/"
"$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_PREFIX" "$APPCAST_STAGE"
cp "$APPCAST_STAGE/appcast.xml" "$PROJECT_ROOT/appcast.xml"
rm -rf "$APPCAST_STAGE"
echo "Wrote appcast.xml (enclosure: ${DOWNLOAD_PREFIX}$(basename "$APP_DMG"))"

# Create git tag
echo ""
echo "=== Creating Git Tag ==="
git tag -a "$TAG" -m "Release ${MARKETING_VERSION}"
echo "Created tag: $TAG"

# Push tag
echo "Pushing tag to origin..."
git push origin "$TAG"

# Extract release notes from CHANGELOG.md for this version
echo ""
echo "=== Creating GitHub Release ==="
RELEASE_NOTES=$(awk "/^## \\[${MARKETING_VERSION}\\]/{found=1; next} /^## \\[/{if(found) exit} found" CHANGELOG.md)

if [[ -z "$RELEASE_NOTES" ]]; then
    RELEASE_NOTES="Release ${MARKETING_VERSION}"
    echo "Warning: No changelog entry found for ${MARKETING_VERSION}, using default notes"
fi

GUMROAD_LINK="---

**[Download on Gumroad](https://thekevintang.gumroad.com/l/xbox-controller-mapper)**"

gh release create "$TAG" \
    --title "ControllerKeys ${MARKETING_VERSION}" \
    --notes "${RELEASE_NOTES}
${GUMROAD_LINK}" \
    "$APP_DMG"

echo "GitHub release created: $TAG (DMG attached for Sparkle auto-update)"

# Publish the appcast so Sparkle clients see the new version. SUFeedURL points
# at raw.githubusercontent .../main/appcast.xml, so this commit must land on the
# feed branch.
echo ""
echo "=== Publishing appcast ==="
git add appcast.xml
git commit -m "chore: update Sparkle appcast for ${MARKETING_VERSION}"
git push origin "$BRANCH"
echo "Pushed appcast.xml to $BRANCH"

echo ""
echo "=== Release Complete ==="
echo "Tag created: $TAG"
echo "GitHub release: https://github.com/${GITHUB_REPO:-NSEvent/xbox-controller-mapper}/releases/tag/$TAG"
echo ""
echo "Next step: Upload $APP_DMG to Gumroad"
echo ""

# Open release folder in Finder for easy Gumroad upload
open "$RELEASE_DIR"
