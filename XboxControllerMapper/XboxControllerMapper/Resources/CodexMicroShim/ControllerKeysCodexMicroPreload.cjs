// Opt-in ChatGPT preload for ControllerKeys' Codex Micro bridge.
// Derived from mpociot/codex-micro-stream-deck-emulator; see the bundled notice.

const { installHook, defaultSocketPath } = require("./ControllerKeysCodexMicroPatch.cjs");

try {
  installHook({ socketPath: defaultSocketPath() });
} catch (error) {
  try {
    process.stderr.write(`[controllerkeys-codex-micro] install failed: ${error?.stack}\n`);
  } catch {
    // Never take ChatGPT down when the optional shim cannot load.
  }
}
