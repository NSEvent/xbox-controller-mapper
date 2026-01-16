#!/bin/bash
set -euo pipefail

# Xbox Controller Mapper - Sign and Notarize Script
# Builds a universal binary, signs with Developer ID, and notarizes with Apple.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Load version
source version.env

# Configuration
SCHEME="XboxControllerMapper"
PROJECT="XboxControllerMapper/XboxControllerMapper.xcodeproj"
TEAM_ID="542GXYT5Z2"
SIGNING_IDENTITY="Developer ID Application: Kevin Tang ($TEAM_ID)"
BUNDLE_ID="KevinTang.XboxControllerMapper"

# Output directories
RELEASE_DIR="$PROJECT_ROOT/release"
BUILD_DIR="$PROJECT_ROOT/build"

echo "=== Sign and Notarize: Xbox Controller Mapper ${MARKETING_VERSION} ==="
echo ""

# Check for required environment variables for notarization
if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" ]] || \
   [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" ]] || \
   [[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    echo "Warning: App Store Connect API credentials not set."
    echo "Notarization will be skipped. Set these environment variables for notarization:"
    echo "  - APP_STORE_CONNECT_API_KEY (path to .p8 file or base64-encoded key)"
    echo "  - APP_STORE_CONNECT_KEY_ID"
    echo "  - APP_STORE_CONNECT_ISSUER_ID"
    echo ""
    SKIP_NOTARIZATION=1
else
    SKIP_NOTARIZATION=0
fi

# Clean previous build artifacts
echo "Cleaning previous builds..."
rm -rf "$RELEASE_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"
mkdir -p "$BUILD_DIR"

# Build universal binary (ARM64 + x86_64)
echo ""
echo "=== Building Universal Binary ==="
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH="NO" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE="Manual" \
    ENABLE_HARDENED_RUNTIME="YES" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS="NO" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -allowProvisioningUpdates \
    build

# Find the built app
APP_PATH=$(find "$BUILD_DIR" -name "XboxControllerMapper.app" -type d | head -1)
if [[ -z "$APP_PATH" ]]; then
    echo "Error: Built app not found"
    exit 1
fi
echo "Built app: $APP_PATH"

# Verify the app is universal
echo ""
echo "=== Verifying Universal Binary ==="
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/XboxControllerMapper")
echo "Architectures: $ARCHS"
if [[ "$ARCHS" != *"arm64"* ]] || [[ "$ARCHS" != *"x86_64"* ]]; then
    echo "Warning: App is not universal. Found: $ARCHS"
fi

# Verify code signature
echo ""
echo "=== Verifying Code Signature ==="
codesign -vvv --deep --strict "$APP_PATH"
echo "Code signature valid."

# Create zip for notarization
NOTARIZE_ZIP="$RELEASE_DIR/XboxControllerMapper-notarize.zip"
echo ""
echo "=== Creating ZIP for Notarization ==="
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
echo "Created: $NOTARIZE_ZIP"

if [[ "$SKIP_NOTARIZATION" == "0" ]]; then
    # Submit for notarization
    echo ""
    echo "=== Submitting for Notarization ==="

    # Write API key to temp file if it's base64-encoded
    if [[ -f "$APP_STORE_CONNECT_API_KEY" ]]; then
        API_KEY_PATH="$APP_STORE_CONNECT_API_KEY"
    else
        API_KEY_PATH="$RELEASE_DIR/AuthKey.p8"
        echo "$APP_STORE_CONNECT_API_KEY" | base64 -d > "$API_KEY_PATH"
    fi

    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --key "$API_KEY_PATH" \
        --key-id "$APP_STORE_CONNECT_KEY_ID" \
        --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
        --wait

    # Clean up temp key if we created it
    if [[ ! -f "$APP_STORE_CONNECT_API_KEY" ]]; then
        rm -f "$API_KEY_PATH"
    fi

    # Staple the notarization ticket
    echo ""
    echo "=== Stapling Notarization Ticket ==="
    xcrun stapler staple "$APP_PATH"

    # Verify notarization
    echo ""
    echo "=== Verifying Notarization ==="
    spctl --assess --type execute --verbose=2 "$APP_PATH"
    echo "Notarization verified."
else
    echo ""
    echo "=== Skipping Notarization ==="
    echo "The app is signed but not notarized."
    echo "Users may see Gatekeeper warnings on first launch."
fi

# Create final distribution zip
FINAL_ZIP="$RELEASE_DIR/XboxControllerMapper-${MARKETING_VERSION}.zip"
echo ""
echo "=== Creating Distribution ZIP ==="
rm -f "$NOTARIZE_ZIP"  # Remove the notarization zip
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"
echo "Created: $FINAL_ZIP"

# Calculate checksum
CHECKSUM=$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')
echo "SHA-256: $CHECKSUM"
echo "$CHECKSUM  XboxControllerMapper-${MARKETING_VERSION}.zip" > "$RELEASE_DIR/SHA256SUMS.txt"

echo ""
echo "=== Sign and Notarize Complete ==="
echo "Release artifact: $FINAL_ZIP"
echo "SHA-256: $CHECKSUM"
