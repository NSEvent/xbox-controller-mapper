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
APP_ZIP="$RELEASE_DIR/XboxControllerMapper-${MARKETING_VERSION}.zip"

if [[ ! -f "$APP_ZIP" ]]; then
    echo "Error: Release artifact not found at $APP_ZIP"
    exit 1
fi

# Create git tag
echo ""
echo "=== Creating Git Tag ==="
git tag -a "$TAG" -m "Release ${MARKETING_VERSION}"
echo "Created tag: $TAG"

# Push tag
echo "Pushing tag to origin..."
git push origin "$TAG"

echo ""
echo "=== Release Complete ==="
echo "Tag created: $TAG"
echo ""
echo "Next step: Upload $APP_ZIP to Gumroad"
echo ""

# Open release folder in Finder for easy Gumroad upload
open "$RELEASE_DIR"
