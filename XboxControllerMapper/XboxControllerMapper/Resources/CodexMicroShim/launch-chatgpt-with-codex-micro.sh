#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHATGPT_APP="${CHATGPT_APP:-/Applications/ChatGPT.app}"
SOCKET_PATH="${CODEX_MICRO_SOCKET:-/tmp/controllerkeys-codex-micro.sock}"
PRELOAD="$SCRIPT_DIR/ControllerKeysCodexMicroPreload.cjs"

if [ ! -d "$CHATGPT_APP" ]; then
  echo "ChatGPT not found at $CHATGPT_APP (set CHATGPT_APP to override)." >&2
  exit 1
fi

if [ ! -f "$PRELOAD" ]; then
  echo "ControllerKeys Codex Micro preload not found at $PRELOAD." >&2
  exit 1
fi

if pgrep -x "ChatGPT" >/dev/null 2>&1; then
  echo "ChatGPT is already running. Quit it normally, then run this launcher again." >&2
  exit 2
fi

if [ ! -S "$SOCKET_PATH" ]; then
  open -a ControllerKeys >/dev/null 2>&1 || true
  attempts=0
  while [ ! -S "$SOCKET_PATH" ] && [ "$attempts" -lt 40 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
  done
fi

if [ ! -S "$SOCKET_PATH" ]; then
  echo "ControllerKeys Codex Micro bridge is not available at $SOCKET_PATH." >&2
  echo "Start ControllerKeys, then try again." >&2
  exit 3
fi

binary_name="$(defaults read "$CHATGPT_APP/Contents/Info" CFBundleExecutable 2>/dev/null || true)"
if [ -z "$binary_name" ] || [ ! -x "$CHATGPT_APP/Contents/MacOS/$binary_name" ]; then
  binary_name="$(find "$CHATGPT_APP/Contents/MacOS" -maxdepth 1 -type f -perm +111 -print | head -1 | xargs basename)"
fi

export CODEX_MICRO_SOCKET="$SOCKET_PATH"
export CODEX_MICRO_SHIM_LOG="${CODEX_MICRO_SHIM_LOG:-/tmp/controllerkeys-codex-micro-shim.log}"
export NODE_OPTIONS="--require=$PRELOAD${NODE_OPTIONS:+ $NODE_OPTIONS}"

echo "Launching ChatGPT with ControllerKeys Codex Micro support"
echo "Socket: $CODEX_MICRO_SOCKET"
exec "$CHATGPT_APP/Contents/MacOS/$binary_name"
