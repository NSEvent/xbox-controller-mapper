#!/usr/bin/env python3
"""Replay XCTest's mapped keys through Anki's real reviewer in an isolated Qt app.

Requires Python 3.13 and the official Anki 26.08.1 macOS app. No package install,
global keyboard events, existing decks, accounts, or installed-app changes.
Run on kmacstudio; see docs/internal/anki-first-session-verification.md.
"""

import argparse
import json
import os
from pathlib import Path
import sys
import time
import uuid


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
    from aqt.qt import Qt, QTimer
    from PyQt6.QtTest import QTest

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

    app = aqt._run(["controllerkeys-anki-oracle", "-b", str(base),
                    "-p", "ControllerKeys Fixture", "-l", "en_US", "--safemode"], exec=False)
    assert app is not None, "Must create an isolated Anki instance"
    mw = aqt.mw

    def wait_for(condition, label: str, seconds: float = 20) -> None:
        deadline = time.monotonic() + seconds
        while not condition():
            app.processEvents()
            if time.monotonic() >= deadline:
                raise AssertionError(f"Timeout: {label}; app={mw.state}, reviewer={mw.reviewer.state}")
            QTest.qWait(20)
        QTest.qWait(100)

    trace = json.loads(args.trace.read_text())
    outputs = {(row["profile"], row["button"]): row["keyCodes"] for row in trace}
    qt_keys = {49: Qt.Key.Key_Space, 36: Qt.Key.Key_Return,
               18: Qt.Key.Key_1, 19: Qt.Key.Key_2, 20: Qt.Key.Key_3, 21: Qt.Key.Key_4}
    results = []
    try:
        wait_for(lambda: mw.col is not None and mw.state == "deckBrowser", "open fixture")
        mw.moveToState("review")
        wait_for(lambda: mw.reviewer.state == "question", "first practice question")
        mw.web.setFocus()

        def tap(profile: str, button: str) -> None:
            codes = outputs[profile, button]
            assert len(codes) == 1, f"One controller tap must emit exactly one key: {codes}"
            QTest.keyClick(mw, qt_keys[codes[0]])

        for profile, ratings in [
            ("Anki Flashcards", {"a": 3, "b": 1, "x": 2, "y": 4, "rightBumper": 3}),
            ("Anki - AnKing (USMLE)", {"a": 3, "b": 2, "x": 1, "y": 4}),
        ]:
            for button, expected in ratings.items():
                wait_for(lambda: mw.reviewer.state == "question", "next question")
                card_id = mw.reviewer.card.id
                count_before = mw.col.db.scalar("select count(*) from revlog")
                tap(profile, "a")
                wait_for(lambda: mw.reviewer.state == "answer", f"{profile}: reveal with A")
                assert mw.col.db.scalar("select count(*) from revlog") == count_before
                if not results:
                    assert mw.grab().save(str(args.output / "revealed-practice-card.png"))
                tap(profile, button)
                wait_for(lambda: mw.reviewer.state == "question", f"{profile}: grade with {button}")
                rows = mw.col.db.all("select ease from revlog where cid = ? order by id desc", card_id)
                assert rows and rows[0][0] == expected, (profile, button, expected, rows)
                assert mw.col.db.scalar("select count(*) from revlog") == count_before + 1
                results.append({"profile": profile, "button": button, "rating": expected})
                print(f"PASS {profile}: A reveals, {button} grades {expected} exactly once", flush=True)
        (args.output / "result.json").write_text(json.dumps({
            "anki_version": aqt.appVersion, "platform": app.platformName(),
            "verified_reviews": results,
            "boundary": "Real Anki reviewer and DB via Qt test input; not Bluetooth/TCC/global CGEvent delivery",
        }, indent=2) + "\n")
    finally:
        # Use Anki's cleanup order: collection, audio, server, then WebEngine.
        # Direct app.quit() leaves Chromium pages alive and exits with code 255.
        if mw.col is not None:
            mw.unloadProfileAndExit()
        else:
            mw.cleanupAndExit()
        QTimer.singleShot(10000, lambda: app.exit(2))
        assert app.exec() == 0, "Timed out closing the isolated Anki fixture"


if __name__ == "__main__":
    main()
