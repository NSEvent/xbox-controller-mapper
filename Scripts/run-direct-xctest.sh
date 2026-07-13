#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-XboxControllerMapper/XboxControllerMapper.xcodeproj}"
SCHEME="${SCHEME:-XboxControllerMapper}"
DERIVED_DATA="${TEST_DERIVED_DATA:-/tmp/xcm-derived-data}"
DESTINATION="${TEST_DESTINATION:-platform=macOS}"
BUILD_CONFIGURATION="${TEST_CONFIGURATION:-Debug}"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$BUILD_CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/ControllerKeys.app"
XCTEST_BUNDLE="${XCTEST_BUNDLE:-$APP_PATH/Contents/PlugIns/XboxControllerMapperTests.xctest}"
PACKAGE_FRAMEWORKS="$PRODUCTS_DIR/PackageFrameworks"

echo "Building tests with xcodebuild build-for-testing"
xcodebuild build-for-testing \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration "$BUILD_CONFIGURATION" \
	-derivedDataPath "$DERIVED_DATA" \
	-destination "$DESTINATION" \
	CODE_SIGN_IDENTITY=- \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=NO

if [[ ! -d "$APP_PATH" ]]; then
	echo "Missing app bundle: $APP_PATH" >&2
	exit 1
fi

if [[ ! -d "$XCTEST_BUNDLE" ]]; then
	echo "Missing XCTest bundle: $XCTEST_BUNDLE" >&2
	exit 1
fi

mkdir -p "$PACKAGE_FRAMEWORKS"

# Direct `xcrun xctest` bypasses Xcode's app-host launcher, so it needs the
# host app's debug dylib and Sparkle in the test bundle rpath search directory.
DEBUG_DYLIB="$PRODUCTS_DIR/ControllerKeys.debug.dylib"
APP_DEBUG_DYLIB="$APP_PATH/Contents/MacOS/ControllerKeys.debug.dylib"
if [[ -f "$DEBUG_DYLIB" ]]; then
	cp "$DEBUG_DYLIB" "$PACKAGE_FRAMEWORKS/ControllerKeys.debug.dylib"
elif [[ -f "$APP_DEBUG_DYLIB" ]]; then
	cp "$APP_DEBUG_DYLIB" "$PACKAGE_FRAMEWORKS/ControllerKeys.debug.dylib"
else
	echo "Missing ControllerKeys.debug.dylib in $PRODUCTS_DIR or $APP_PATH/Contents/MacOS" >&2
	exit 1
fi

if [[ -d "$PRODUCTS_DIR/Sparkle.framework" ]]; then
	rm -rf "$PACKAGE_FRAMEWORKS/Sparkle.framework"
	/usr/bin/ditto "$PRODUCTS_DIR/Sparkle.framework" "$PACKAGE_FRAMEWORKS/Sparkle.framework"
elif [[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]]; then
	rm -rf "$PACKAGE_FRAMEWORKS/Sparkle.framework"
	/usr/bin/ditto "$APP_PATH/Contents/Frameworks/Sparkle.framework" "$PACKAGE_FRAMEWORKS/Sparkle.framework"
else
	echo "Missing Sparkle.framework in $PRODUCTS_DIR or $APP_PATH/Contents/Frameworks" >&2
	exit 1
fi

if [[ -n "${CONTROLLERKEYS_RENDER_SNAPSHOT_DIR:-}" ]]; then
	mkdir -p "$CONTROLLERKEYS_RENDER_SNAPSHOT_DIR"
fi

echo "Running direct XCTest bundle"
xcrun xctest "$XCTEST_BUNDLE"
