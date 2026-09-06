"""Optional real-Anki gate. Run on kmacstudio with both ANKI env paths set."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ANKI_APP = os.environ.get("CONTROLLERKEYS_ANKI_APP")
ANKI_TRACE = os.environ.get("CONTROLLERKEYS_ANKI_KEY_TRACE")
SCRIPT = Path(__file__).resolve().parents[1] / "verify-anki-session.py"


@unittest.skipUnless(ANKI_APP and ANKI_TRACE, "requires official Anki app and XCTest key trace")
class AnkiOracleIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="anki-oracle-integration-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def run_oracle(self, trace, output):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--anki-app", ANKI_APP,
             "--trace", str(trace), "--output", str(output)],
            capture_output=True, text=True, timeout=120,
        )
        log = result.stdout + result.stderr
        self.assertNotIn("WebEnginePage still not deleted", log, log)
        self.assertNotIn("Timed out closing", log, log)
        return result, log

    def test_missing_and_malformed_input_never_start_anki(self):
        trace = self.base / "trace.json"
        for number, content in enumerate([None, "{", "[]"]):
            with self.subTest(content=content):
                if content is not None:
                    trace.write_text(content)
                output = self.base / f"invalid-{number}"
                result, log = self.run_oracle(trace, output)
                self.assertEqual(result.returncode, 2, log)
                self.assertIn("Invalid trace", log)
                self.assertNotIn("Serving on", log)
                self.assertFalse(output.exists())

    def test_wrong_rating_fails_and_closes_the_real_reviewer(self):
        rows = json.loads(Path(ANKI_TRACE).read_text())
        for row in rows:
            if row["profile"] == "Anki Flashcards" and row["button"] == "b":
                row["keyCodes"] = [19]  # Valid key, wrong rating: Hard instead of Again.
        trace = self.base / "wrong-rating.json"
        trace.write_text(json.dumps(rows))
        output = self.base / "wrong-rating"
        result, log = self.run_oracle(trace, output)
        self.assertEqual(result.returncode, 1, log)
        self.assertIn("AssertionError", log)
        self.assertIn("Anki Flashcards", log)
        self.assertFalse((output / "result.json").exists())

    def test_all_nine_reviews_pass_and_close(self):
        output = self.base / "success"
        result, log = self.run_oracle(ANKI_TRACE, output)
        self.assertEqual(result.returncode, 0, log)
        receipt = json.loads((output / "result.json").read_text())
        self.assertEqual(receipt["anki_version"], "26.08.1")
        self.assertEqual(len(receipt["verified_reviews"]), 9)
        self.assertTrue((output / "revealed-practice-card.png").is_file())


if __name__ == "__main__":
    unittest.main()
