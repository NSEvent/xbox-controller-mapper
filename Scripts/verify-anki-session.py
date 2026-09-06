#!/usr/bin/env python3
"""Replay XCTest's mapped keys through Anki's real reviewer in an isolated Qt app.

Requires Python 3.13 and the official Anki 26.08.1 macOS app. No package install,
global keyboard events, existing decks, accounts, or installed-app changes.
Run on kmacstudio; see docs/internal/anki-first-session-verification.md.
"""

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sys
import time
import uuid


REVIEW_CASES = [
    ("Anki Flashcards", {"a": 3, "b": 1, "x": 2, "y": 4, "rightBumper": 3}),
    ("Anki - AnKing (USMLE)", {"a": 3, "b": 2, "x": 1, "y": 4}),
]
SUPPORTED_KEYS = {49, 36, 18, 19, 20, 21}


def load_trace(path: Path) -> dict:
    """Reject missing/malformed/incomplete input before creating any Anki state."""
    trace = json.loads(path.read_text())
    if not isinstance(trace, list):
        raise ValueError("trace must be an array of mapped-key records")
    expected = {(profile, button) for profile, ratings in REVIEW_CASES for button in ratings}
    outputs = {}
    for row in trace:
        if not isinstance(row, dict):
            raise ValueError("each trace record must be an object")
        profile, button, codes = row.get("profile"), row.get("button"), row.get("keyCodes")
        if not isinstance(profile, str) or not isinstance(button, str):
            raise ValueError("profile and button must be strings")
        key = (profile, button)
        if key not in expected or key in outputs:
            raise ValueError(f"unexpected or duplicate trace record: {key}")
        if (not isinstance(codes, list) or len(codes) != 1
                or type(codes[0]) is not int or codes[0] not in SUPPORTED_KEYS):
            raise ValueError(f"{key} must emit exactly one supported key")
        outputs[key] = codes
    if missing := expected - outputs.keys():
        raise ValueError(f"missing trace records: {sorted(missing)}")
    return outputs


@contextmanager
def anki_session(aqt, base: Path, timer):
    """Protect every verification operation after Anki returns its isolated app."""
    app = aqt._run(["controllerkeys-anki-oracle", "-b", str(base),
                    "-p", "ControllerKeys Fixture", "-l", "en_US", "--safemode"], exec=False)
    try:
        if app is None:
            raise RuntimeError("Must create an isolated Anki instance")
        yield app, aqt.mw
    finally:
        if app is not None:
            # Anki's order: collection, audio, server, then WebEngine.
            # Direct app.quit() leaves Chromium pages alive (exit 255).
            if aqt.mw.col is not None:
                aqt.mw.unloadProfileAndExit()
            else:
                aqt.mw.cleanupAndExit()
            timer.singleShot(10000, lambda: app.exit(2))
            if app.exec() != 0:
                raise RuntimeError("Timed out closing the isolated Anki fixture")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--anki-app", type=Path, required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="New directory; refuses existing paths to protect real decks")
    args = parser.parse_args()
    if sys.version_info[:2] != (3, 13):
        parser.error("The pinned Anki runtime requires Python 3.13")
    packages = args.anki_app.resolve() / "Contents/Resources/app_packages"
    if not (packages / "aqt").is_dir():
        parser.error("--anki-app must contain the official bundled aqt runtime")
    try:
        outputs = load_trace(args.trace)
    except (OSError, ValueError) as error:
        parser.error(f"Invalid trace: {error}")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ["ANKI_SINGLE_INSTANCE_KEY"] = f"controllerkeys-test-{uuid.uuid4()}"
    os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = "--disable-gpu"
    sys.path.insert(0, str(packages))

    import anki.lang
    import aqt
    from anki.collection import Collection
    from aqt.profiles import ProfileManager, VideoDriver
    from aqt.qt import QTimer

    anki.lang.set_lang("en_US")
    base = args.output / "isolated-anki"
    base.mkdir()
    pm = ProfileManager(base)
    pm.setupMeta()
    pm.create("ControllerKeys Fixture")
    pm.load("ControllerKeys Fixture")
    pm.meta.update(defaultLang="en_US", firstRun=False, updates=False)
    pm.profile.update(autoSync=False, syncMedia=False)
    pm.set_video_driver(VideoDriver.Software)
    pm.save()
    col = Collection(pm.collectionPath())
    model = col.models.by_name("Basic")
    assert model is not None
    for number in range(20):
        note = col.new_note(model)
        note["Front"] = f"ControllerKeys practice card {number}"
        note["Back"] = f"Disposable answer {number}"
        col.add_note(note, 1)
    col.close()
    pm.db.close()

    with anki_session(aqt, base, QTimer) as (app, mw):
        verify_reviews(app, mw, outputs, args.output, aqt.appVersion)


def verify_reviews(app, mw, outputs: dict, output: Path, version: str) -> None:
    from aqt.qt import Qt
    from PyQt6.QtTest import QTest

    def wait_for(condition, label: str, seconds: float = 20) -> None:
        deadline = time.monotonic() + seconds
        while not condition():
            app.processEvents()
            if time.monotonic() >= deadline:
                raise AssertionError(f"Timeout: {label}; app={mw.state}, reviewer={mw.reviewer.state}")
            QTest.qWait(20)
        QTest.qWait(100)

    qt_keys = {49: Qt.Key.Key_Space, 36: Qt.Key.Key_Return,
               18: Qt.Key.Key_1, 19: Qt.Key.Key_2, 20: Qt.Key.Key_3, 21: Qt.Key.Key_4}
    results = []
    wait_for(lambda: mw.col is not None and mw.state == "deckBrowser", "open fixture")
    mw.moveToState("review")
    wait_for(lambda: mw.reviewer.state == "question", "first practice question")
    mw.web.setFocus()

    def tap(profile: str, button: str) -> None:
        codes = outputs[profile, button]
        QTest.keyClick(mw, qt_keys[codes[0]])

    for profile, ratings in REVIEW_CASES:
        for button, expected in ratings.items():
            wait_for(lambda: mw.reviewer.state == "question", "next question")
            card_id = mw.reviewer.card.id
            count_before = mw.col.db.scalar("select count(*) from revlog")
            tap(profile, "a")
            wait_for(lambda: mw.reviewer.state == "answer", f"{profile}: reveal with A")
            assert mw.col.db.scalar("select count(*) from revlog") == count_before
            if not results:
                assert mw.grab().save(str(output / "revealed-practice-card.png"))
            tap(profile, button)
            wait_for(lambda: mw.reviewer.state == "question", f"{profile}: grade with {button}")
            rows = mw.col.db.all("select ease from revlog where cid = ? order by id desc", card_id)
            assert rows and rows[0][0] == expected, (profile, button, expected, rows)
            assert mw.col.db.scalar("select count(*) from revlog") == count_before + 1
            results.append({"profile": profile, "button": button, "rating": expected})
            print(f"PASS {profile}: A reveals, {button} grades {expected} exactly once", flush=True)
    (output / "result.json").write_text(json.dumps({
        "anki_version": version, "platform": app.platformName(),
        "verified_reviews": results,
        "boundary": "Real Anki reviewer and DB via Qt test input; not Bluetooth/TCC/global CGEvent delivery",
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
