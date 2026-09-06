"""Host-side Anki oracle guards; no Qt, Anki, input, or network required."""

import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "verify-anki-session.py"
SPEC = importlib.util.spec_from_file_location("anki_oracle", SCRIPT)
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


class AnkiOracleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="anki-oracle-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.trace = self.base / "trace.json"
        self.rows = [
            {"profile": name, "button": button, "keyCodes": [code]}
            for name, mappings in [
                ("Anki Flashcards", {"a": 49, "b": 18, "x": 19, "y": 21, "rightBumper": 20}),
                ("Anki - AnKing (USMLE)", {"a": 36, "b": 19, "x": 18, "y": 21}),
            ] for button, code in mappings.items()
        ]

    def test_complete_trace_preserves_actual_codes(self):
        self.trace.write_text(json.dumps(self.rows))
        outputs = oracle.load_trace(self.trace)
        self.assertEqual(len(outputs), 9)
        self.assertEqual(outputs["Anki Flashcards", "b"], [18])
        self.assertEqual(outputs["Anki - AnKing (USMLE)", "b"], [19])

    def test_missing_trace_is_rejected(self):
        with self.assertRaises(FileNotFoundError):
            oracle.load_trace(self.trace)

    def test_malformed_json_is_rejected(self):
        self.trace.write_text("{")
        with self.assertRaises(ValueError):
            oracle.load_trace(self.trace)

    def test_invalid_records_are_rejected(self):
        bad_rows = [None, {}, dict(self.rows[0], profile=[]),
                    dict(self.rows[0], button="unknown")]
        for codes in [None, [], [18, 19], [True], [18.0], ["18"], [999]]:
            bad_rows.append(dict(self.rows[0], keyCodes=codes))
        for bad in bad_rows:
            with self.subTest(record=bad):
                self.trace.write_text(json.dumps([bad] + self.rows[1:]))
                with self.assertRaises(ValueError):
                    oracle.load_trace(self.trace)

    def test_missing_duplicate_and_non_array_traces_are_rejected(self):
        for data in [{}, [], self.rows[:-1], self.rows + [self.rows[0]]]:
            with self.subTest(data=data):
                self.trace.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    oracle.load_trace(self.trace)

    def test_wrong_but_supported_mapping_reaches_the_semantic_oracle(self):
        rows = copy.deepcopy(self.rows)
        rows[1]["keyCodes"] = [19]  # Wrong Again rating; real reviewer must reject it.
        self.trace.write_text(json.dumps(rows))
        self.assertEqual(oracle.load_trace(self.trace)["Anki Flashcards", "b"], [19])

    def test_cli_rejects_bad_trace_before_output_creation_or_anki_import(self):
        app_path = self.base / "Anki.app"
        (app_path / "Contents/Resources/app_packages/aqt").mkdir(parents=True)
        output = self.base / "output"
        argv = [str(SCRIPT), "--anki-app", str(app_path), "--trace", str(self.trace),
                "--output", str(output)]
        for content in [None, "{", "[]", '[{"profile": []}]']:
            with self.subTest(content=content):
                if content is not None:
                    self.trace.write_text(content)
                with patch.object(oracle.sys, "argv", argv), \
                        patch.object(oracle.sys, "version_info", (3, 13)), \
                        patch.object(oracle.sys, "stderr", io.StringIO()) as stderr:
                    with self.assertRaises(SystemExit) as result:
                        oracle.main()
                self.assertEqual(result.exception.code, 2)
                self.assertIn("Invalid trace", stderr.getvalue())
                self.assertFalse(output.exists())

    def session_fixture(self, collection=True):
        app = Mock()
        app.exec.return_value = 0
        aqt = Mock()
        aqt._run.return_value = app
        aqt.mw.col = Mock() if collection else None
        return aqt, app, Mock()

    def test_session_closes_after_success(self):
        aqt, app, timer = self.session_fixture()
        with oracle.anki_session(aqt, self.base, timer) as pair:
            self.assertEqual(pair, (app, aqt.mw))
        aqt.mw.unloadProfileAndExit.assert_called_once_with()
        aqt.mw.cleanupAndExit.assert_not_called()
        app.exec.assert_called_once_with()
        self.assertEqual(timer.singleShot.call_args.args[0], 10000)

    def test_session_closes_and_preserves_verification_failure(self):
        aqt, app, timer = self.session_fixture()
        with self.assertRaisesRegex(AssertionError, "wrong rating"):
            with oracle.anki_session(aqt, self.base, timer):
                raise AssertionError("wrong rating")
        aqt.mw.unloadProfileAndExit.assert_called_once_with()
        app.exec.assert_called_once_with()

    def test_session_closes_before_collection_loaded(self):
        aqt, app, timer = self.session_fixture(collection=False)
        with self.assertRaisesRegex(RuntimeError, "early failure"):
            with oracle.anki_session(aqt, self.base, timer):
                raise RuntimeError("early failure")
        aqt.mw.cleanupAndExit.assert_called_once_with()
        aqt.mw.unloadProfileAndExit.assert_not_called()
        app.exec.assert_called_once_with()

    def test_cleanup_timeout_fails_the_run(self):
        aqt, app, timer = self.session_fixture()
        app.exec.return_value = 2
        with self.assertRaisesRegex(RuntimeError, "Timed out closing"):
            with oracle.anki_session(aqt, self.base, timer):
                pass

    def test_no_new_app_does_not_touch_another_instance(self):
        aqt, _, timer = self.session_fixture()
        aqt._run.return_value = None
        with self.assertRaisesRegex(RuntimeError, "Must create an isolated"):
            with oracle.anki_session(aqt, self.base, timer):
                self.fail("No isolated app was created")
        aqt.mw.unloadProfileAndExit.assert_not_called()
        aqt.mw.cleanupAndExit.assert_not_called()


if __name__ == "__main__":
    unittest.main()
