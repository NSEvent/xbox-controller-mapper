# Anki first-session verification

Scope: starter discovery → import → foreground selection → first review →
disconnect/reconnect → configuration reload. Prepared locally on 2026-09-05;
this work does not authorize a release or alter the September 10 measurement hold.

## Reproduced defects and fixes

- **Current Anki was not linked.** Both shipped profiles linked only
  `net.ankiweb.launcher`. The official Anki 26.08.1 arm64 DMG contains
  `net.ankiweb.anki`. Both identities are now supported. Existing imported
  profiles are not silently rewritten; the guide explains manually relinking them.
- **Import order beat explicit selection.** With both Anki variants imported,
  the first app-linked profile replaced the selected one. Their B/X ratings differ.
  Resolution now prefers the active linked variant, then the remembered editing
  variant, then the persisted previous profile, before import-order fallback. App links still outrank
  controller links and the default profile.
  Follow-up 2026-09-06: explicit menu-bar/controller choices now update that bookmark
  even without foregrounding the editor; automatic switches do not overwrite it.
- **Import failure looked like success.** Failed downloads dismissed the picker;
  partial retries could duplicate successful imports. Failures now remain visible,
  successful IDs are tracked immediately, and cancellation prevents post-dismissal
  imports. Safety approval remains mandatory for executable content. Preview
  failures offer retry; stale requests cannot replace the current preview state.
- **Starter discovery:** fresh default-only libraries get a Browse Starter
  Profiles button. The existing gallery and markdown renderer are reused; its
  oversized source file is split into picker, preview, and guide components.

Baseline `c3773bc`: six journey tests produced 22 failed assertions. Adding the
current Anki identity exposed the second-variant selection failure. Tests precede
the relevant fixes; the reconnect/reload/muted-preview cases already worked.
An additional restart-from-Finder fixture reproduced three failed assertions:
the session-only selection was lost. The persisted previous-profile fallback
fixes that case without changing the configuration schema.

## Automated gates

- `AnkiFirstSessionTests`: actual community JSON, production import/config store,
  app monitor, mapping engine and controller events; mocked output boundary.
  Includes current/legacy identities, both variants, explicit choice, reconnect,
  disk reload, and no replay of a press begun during muted preview.
- `CommunityProfileImportBatchTests`: offline error, partial retry, safety decline,
  cancellation during download and approval, success identity, and empty batch.
- `ProfileAutoSwitchPreferenceTests`: selection/remembered-choice precedence,
  removed links, and fallback without an applicable preference.
- `AnkiProfileSelectionTests`: six production-manager cases for background selection,
  controller navigation, main-window selection, explicit reselection of an automatic
  choice, preservation across other linked apps, and relaunch from Default.
- `FirstSessionRenderingTests`: native hosted sidebar at its 200-point minimum
  and Anki guide preview in both color schemes. ImageRenderer alone omits native
  List/ScrollView content; use the hosted-view captures for review. The isolated
  sidebar fixture does not reproduce the main window's translucent dark backdrop.
- `Scripts/verify-anki-session.py`: optional external oracle. Replays **actual
  XCTest-exported keys** through the official Anki reviewer using Qt test input.
  Checks answer reveal, exact review-log increment, and correct Again/Hard/Good/
  Easy rating on nine disposable reviews across both profiles. AnKing's right
  bumper is a layer activator, not the basic profile's Good shortcut.

The app test suite also covers the separately authored onboarding-readiness and
continuous-pointer telemetry changes in `6398313`; this patch does not own them.

2026-09-05 final full gate: **2,163 tests, 37 skipped, zero failures** on kmacstudio.
2026-09-06 follow-up full gate: **2,169 tests, 37 skipped, zero failures**; six new
selection regressions added. The original background-choice reproductions now pass.
The skips include real-input/permission-dependent tests; they are not evidence
that hardware or TCC has been validated. Native screenshots were visually checked.

## Repeat on kmacstudio

Use an isolated copy of the complete candidate source, not the dirty serving
checkout. No tests on Kevin's MacBook. Hold the advisory screen-control lock for
the test run, and release it on success **or** failure. Announce any permission
prompt before running. Do not replace or re-sign the installed app for these gates.

From the isolated repository root on kmacstudio:

```bash
CONTROLLERKEYS_FIRST_SESSION_SNAPSHOTS="$PWD/journey-snapshots" \
CONTROLLERKEYS_ANKI_KEY_TRACE="$PWD/anki-key-trace.json" \
TEST_DERIVED_DATA="$PWD/derived" ./Scripts/run-direct-xctest.sh
```

The existing runner builds with signing disabled and uses direct XCTest; this
does not validate a signed installed app's Accessibility grant or real input path.
Optional snapshot/trace output is not required for ordinary CI.

For the external oracle, mount the official Anki 26.08.1 arm64 DMG read-only and
use Python 3.13 with its bundled packages. No pip dependencies or Anki add-ons:

```bash
/opt/homebrew/bin/python3.13 -m venv anki-venv
anki-venv/bin/python Scripts/verify-anki-session.py \
  --anki-app /absolute/read-only/mount/Anki.app \
  --trace "$PWD/anki-key-trace.json" \
  --output "$PWD/anki-oracle-run-1"
```

Output must be a **new directory**. The harness creates its own Anki base/profile,
disables sync/update checks, uses a unique instance key and the offscreen Qt
backend, and shuts down through Anki's normal cleanup path. `result.json` records
the actual Anki version and ratings; `revealed-practice-card.png` is a Qt-rendered
fixture screenshot. It never sends system-wide keystrokes. Detach the DMG afterward.

### Failure-path gate (2026-09-06)

Trace shape/completeness is validated before creating an output directory or loading
Anki. Missing/malformed input exits 2 without launching Qt. Once Anki returns its
isolated app, all verification runs inside a cleanup context, including import/setup
errors in the reviewer check. A wrong-but-valid rating trace must fail with exit 1,
without a success receipt or WebEngine teardown warnings; nine correct reviews exit 0.

The normal direct-XCTest runner now runs the 12 dependency-free Python guards after
XCTest. Three additional real-Anki tests opt in with the app and generated trace:

```bash
CONTROLLERKEYS_ANKI_APP=/absolute/read-only/mount/Anki.app \
CONTROLLERKEYS_ANKI_KEY_TRACE="$PWD/anki-key-trace.json" \
anki-venv/bin/python -m unittest discover -s Scripts/tests -v
```

These 15 tests passed on kmacstudio with Anki 26.08.1, including missing/malformed
input and a deliberately incorrect rating. For a combined direct-XCTest/oracle run,
also set `TEST_PYTHON="$PWD/anki-venv/bin/python"`; XCTest exports the trace before
the Python tests consume it. No new dependencies or installed-app changes.

## Remaining release gate

Automated success does **not** prove Bluetooth pairing, macOS Accessibility,
keyboard-layout translation, or real CGEvent delivery to a foreground Anki window.
Those require a signed installed candidate and a real controller, at a time when
Kevin is not using the target machine. Do not change TCC or the installed app
without coordinating that final check.

If multiple variants link the same app and none is active, remembered, or the
persisted previous profile, import order remains the fallback. For an unambiguous
permanent association across arbitrary intervening profiles, use Linked Apps to
assign Anki to one variant; that existing UI removes conflicting links.

1. Fresh test configuration: finish permission/controller setup; verify safe
   preview cannot grade a card. Import Anki Flashcards using the starter button.
2. In a disposable Anki deck, A reveals; A again grades Good. B/X/Y and right
   bumper grade Again/Hard/Easy/Good respectively, exactly once per tap.
3. Disconnect/reconnect, then quit/reopen ControllerKeys. Return to Anki and
   repeat one card; imported mappings and the selected variant remain intact.
4. Disconnect networking during an uncached import. Confirm visible error and
   retry without duplicate successful imports. Close an in-flight import and
   confirm no later library mutation. Reject executable-profile safety approval.

Sources: [official release](https://github.com/ankitects/anki/releases/tag/26.08.1),
[official studying/shortcut guide](https://docs.ankiweb.net/studying.html).
