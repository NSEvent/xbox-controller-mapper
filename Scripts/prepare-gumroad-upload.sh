#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

source version.env

VERSION="${1:-$MARKETING_VERSION}"
BUILD="${2:-$BUILD_NUMBER}"
ARTIFACT="${3:-$PROJECT_ROOT/release/ControllerKeys-${VERSION}.dmg}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
    echo "Error: Invalid release version: $VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid build number: $BUILD" >&2
    exit 1
fi

if [[ ! -f "$ARTIFACT" ]]; then
    echo "Error: Gumroad artifact not found: $ARTIFACT" >&2
    exit 1
fi

ARTIFACT_DIR="$(cd "$(dirname "$ARTIFACT")" && pwd)"
ARTIFACT="$ARTIFACT_DIR/$(basename "$ARTIFACT")"
EXPECTED_NAME="ControllerKeys-${VERSION}.dmg"

if [[ "$(basename "$ARTIFACT")" != "$EXPECTED_NAME" ]]; then
    echo "Error: Expected $EXPECTED_NAME, got $(basename "$ARTIFACT")" >&2
    exit 1
fi

RELEASE_DIR="$PROJECT_ROOT/release"
NOTES_FILE="$RELEASE_DIR/gumroad-release-notes.md"
MANIFEST="$RELEASE_DIR/gumroad-upload.json"

NOTES="$(awk -v header="## [${VERSION}] - " '
    index($0, header) == 1 { found = 1 }
    found && printed && /^## \[/ { exit }
    found { print; printed = 1 }
' CHANGELOG.md)"

if [[ -z "$NOTES" ]]; then
    echo "Error: No CHANGELOG.md section found for ${VERSION}" >&2
    exit 1
fi

printf '%s\n' "$NOTES" > "$NOTES_FILE"

SHA256="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
SIZE_BYTES="$(stat -f '%z' "$ARTIFACT")"

python3 - "$MANIFEST" "$VERSION" "$BUILD" "$ARTIFACT" "$NOTES_FILE" "$SHA256" "$SIZE_BYTES" <<'PY'
import json
from pathlib import Path
import sys

manifest_path, version, build, artifact, notes_path, sha256, size_bytes = sys.argv[1:]
description = Path(notes_path).read_text(encoding="utf-8").rstrip()

manifest = {
    "schema_version": 1,
    "product": {
        "name": "ControllerKeys",
        "gumroad_product_id": "apabap",
        "content_url": "https://gumroad.com/products/apabap/edit/content",
    },
    "release": {
        "version": version,
        "build": int(build),
        "display_name": f"ControllerKeys-{version}",
        "artifact_path": artifact,
        "artifact_filename": Path(artifact).name,
        "artifact_size_bytes": int(size_bytes),
        "expected_gumroad_size": f"{int(size_bytes) / (1024 * 1024):.1f} MB",
        "sha256": sha256,
        "description_path": notes_path,
        "description": description,
    },
    "notify_customers": False,
}

Path(manifest_path).write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

echo "Prepared Gumroad upload manifest: $MANIFEST"
echo "  Product: ControllerKeys"
echo "  Version: $VERSION ($BUILD)"
echo "  Artifact: $ARTIFACT"
echo "  SHA-256: $SHA256"
echo "  Release notes: $NOTES_FILE"
