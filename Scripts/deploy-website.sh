#!/bin/bash
set -euo pipefail

# Deploy Xbox Controller Mapper website to kevintang.xyz
# Usage: ./Scripts/deploy-website.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$PROJECT_ROOT/docs"
TARGET_DIR="$HOME/projects/kevintang.xyz/apps/xbox-controller-mapper"

echo "=== Deploying Xbox Controller Mapper Website ==="
echo ""

# Check source exists
if [[ ! -d "$DOCS_DIR" ]]; then
    echo "Error: docs directory not found at $DOCS_DIR"
    exit 1
fi

# Check og-image exists
if [[ ! -f "$DOCS_DIR/og-image.png" ]]; then
    echo "Warning: og-image.png not found in docs/"
    echo "Add a screenshot: cp /path/to/screenshot.png $DOCS_DIR/og-image.png"
    echo ""
fi

# Create target directory
echo "Creating target directory..."
mkdir -p "$TARGET_DIR"

# Copy files
echo "Copying files..."
cp "$DOCS_DIR/index.html" "$TARGET_DIR/"
cp "$DOCS_DIR/styles.css" "$TARGET_DIR/"
cp "$DOCS_DIR/favicon.png" "$TARGET_DIR/" 2>/dev/null || true
cp "$DOCS_DIR/apple-touch-icon.png" "$TARGET_DIR/" 2>/dev/null || true
cp "$DOCS_DIR/app-icon.png" "$TARGET_DIR/" 2>/dev/null || true
cp "$DOCS_DIR/og-image.png" "$TARGET_DIR/" 2>/dev/null || true

# Copy guides directory
echo "Copying guides..."
mkdir -p "$TARGET_DIR/guides"
cp "$DOCS_DIR/guides/"*.html "$TARGET_DIR/guides/"

echo ""
echo "=== Deployment Complete ==="
echo "Files copied to: $TARGET_DIR"
echo ""
echo "Contents:"
ls -la "$TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. cd $HOME/projects/kevintang.xyz"
echo "  2. git add apps/xbox-controller-mapper"
echo "  3. git commit -m 'Add Xbox Controller Mapper support page'"
echo "  4. git push (or deploy however your site is hosted)"
