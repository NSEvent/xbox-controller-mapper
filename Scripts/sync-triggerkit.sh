#!/bin/bash
# Syncs the vendored TriggerKit package from its canonical repo.
#
# TriggerKit's canonical source lives at ~/projects/triggerkit (local-only,
# shared by Tardy, Plaque, and TriggerKit.app). ControllerKeys vendors a copy
# under TriggerKit/ so the public repo and CI build without that private
# checkout. Develop TriggerKit changes in the canonical repo (swift test),
# then run this script and commit the result here.
set -euo pipefail

CANONICAL="${TRIGGERKIT_SRC:-$HOME/projects/triggerkit}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -x "$CANONICAL/Scripts/sync-vendor.sh" ]]; then
    echo "error: canonical TriggerKit checkout not found at $CANONICAL" >&2
    exit 1
fi

"$CANONICAL/Scripts/sync-vendor.sh" "$REPO_ROOT/TriggerKit"

echo "Synced TriggerKit from $CANONICAL"
git -C "$REPO_ROOT" status --short TriggerKit/
