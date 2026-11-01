"""CLI smoke tests: the commands must work without a game."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "fiiiiish_auto", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=120,
    )


class TestCliSmoke(unittest.TestCase):
    def test_fight(self):
        r = run_cli("fight", "--tier", "shallow", "--quality", "0", "--power", "0.2", "--seed", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("outcome=success", r.stdout)

    def test_fight_trace_and_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            trace = Path(tmp) / "trace.jsonl"
            r = run_cli(
                "fight", "--tier", "mid", "--power", "0.5", "--seed", "3", "--trace", str(trace)
            )
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(trace.exists())
            r = run_cli("replay", str(trace))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("0 mismatches", r.stdout)

    def test_simulate(self):
        r = run_cli(
            "simulate", "--runs", "3", "--tier", "shallow", "--power", "0.2", "--seed", "1"
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rate=100.00%", r.stdout)

    def test_doctor(self):
        r = run_cli("doctor")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("fiiiiish_auto doctor", r.stdout)


if __name__ == "__main__":
    unittest.main()
