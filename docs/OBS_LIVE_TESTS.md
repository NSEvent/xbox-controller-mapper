# OBS Live Integration Tests

This project includes live OBS websocket integration tests in:

- `XboxControllerMapper/XboxControllerMapperTests/OBSWebSocketLiveIntegrationTests.swift`

These tests hit a real OBS instance and can mutate output state (start/stop record/stream/replay/virtual cam).

## Prerequisites

- OBS Studio installed
- `obs-websocket` enabled (OBS 28+ includes it)
- `jq` installed (`brew install jq`)
- `mediamtx` installed for local RTMP sink (`brew install mediamtx`)

## Required OBS/Test Settings

Hard requirements (tests skip/fail without these):

- OBS websocket server enabled
- Websocket auth enabled with a password
- Websocket port set (default: `4455`)
- Live test sentinel enabled:
  - `~/.controllerkeys/obs_live_tests_enabled`

Output lifecycle tests require:

- Output mutation sentinel enabled:
  - `~/.controllerkeys/obs_live_tests_allow_output_mutations`

Settings that reduce skips:

- Replay buffer enabled in OBS profile output settings
- Recording split configured (for `SplitRecordFile`)
- At least one source filter configured on an input (for filter enable/disable roundtrip)

## Helper Script (Apply/Restore)

Use:

```bash
# Show readiness
Scripts/setup-obs-live-tests.sh status

# Backup current OBS test-related config + apply live-test settings
Scripts/setup-obs-live-tests.sh apply

# Restore from latest backup
Scripts/setup-obs-live-tests.sh restore

# Or restore from a specific backup folder
Scripts/setup-obs-live-tests.sh restore ~/.controllerkeys/obs-live-test-backups/<timestamp>
```

Environment overrides:

- `OBS_WS_PORT` (default `4455`)
- `OBS_WS_PASSWORD` (default `controllerkeys-live-tests`)

What `apply` changes:

- `~/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json`
  - Enables websocket server/auth, sets port/password
- `~/.controllerkeys/obs_live_tests_enabled`
- `~/.controllerkeys/obs_live_tests_allow_output_mutations`
- Each OBS profile `basic.ini` under:
  - `~/Library/Application Support/obs-studio/basic/profiles/*/basic.ini`
  - Sets output mode + replay buffer/split-record keys used by tests

Important:

- Restart OBS after `apply` and after `restore`.

## Running the Live OBS Tests

From repo root:

```bash
xcodebuild \
  -project XboxControllerMapper/XboxControllerMapper.xcodeproj \
  -scheme XboxControllerMapper \
  -destination 'platform=macOS' \
  -only-testing:XboxControllerMapperTests/OBSWebSocketLiveIntegrationTests \
  test
```

## Expected Skips and Meaning

You may still see skips depending on OBS scene/profile setup:

- No compatible source filter found:
  - Add any filter to an OBS input (example: mic noise suppression)
- `SplitRecordFile` unavailable:
  - Ensure split recording is enabled in OBS recording output settings
- Replay buffer unavailable (`code 604`):
  - Enable replay buffer in OBS output settings
