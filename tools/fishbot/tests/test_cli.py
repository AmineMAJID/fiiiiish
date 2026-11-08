"""Tests for the parts of the program around the fishing loop.

    python -m tests.test_cli

The loop itself is covered by ``tests.test_e2e``; what is checked here is the
plumbing that only exists in ``fishbot.run``: the settings file that remembers
the learned mouse sensitivity, the calibration snapshot, and the fact that the
whole program starts, runs and shuts down cleanly against a synthetic HUD (so
``--simulate`` is a usable smoke test on any machine).
"""

from __future__ import annotations

import os
import tempfile
from typing import List

from fishbot import report, run, settings, vision
from fishbot.vision import Frame
from fishbot import simhud

failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
    if not ok:
        failures.append(f"{name} {detail}")


def test_settings_roundtrip() -> None:
    print("\n[settings file: the learned sensitivity survives a restart]")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "settings.json")
        fresh = settings.load(path)
        check("defaults when there is no file", fresh["counts_per_pct"] == 1.6,
              f"{fresh['counts_per_pct']}")
        fresh["counts_per_pct"] = 3.75
        fresh["fish_kept"] = 12
        fresh["sessions"] = 2
        check("save succeeds", settings.save(fresh, path))
        again = settings.load(path)
        check("sensitivity remembered", abs(again["counts_per_pct"] - 3.75) < 1e-9,
              f"{again['counts_per_pct']}")
        check("counters remembered", again["fish_kept"] == 12 and again["sessions"] == 2,
              f"{again['fish_kept']}/{again['sessions']}")

        with open(path, "w", encoding="utf-8") as fh:
            fh.write("{ this is not json")
        check("corrupt file falls back to defaults",
              settings.load(path)["counts_per_pct"] == 1.6)

        with open(path, "w", encoding="utf-8") as fh:
            fh.write('{"counts_per_pct": 9999, "hz": -3, "keep": "yes"}')
        broken = settings.load(path)
        check("out-of-range numbers are ignored", broken["counts_per_pct"] == 1.6,
              f"{broken['counts_per_pct']}")
        check("wrong types are ignored", broken["hz"] == 20.0 and broken["keep"] is True,
              f"{broken['hz']}/{broken['keep']}")


def test_reporter() -> None:
    print("\n[reporter: events print, and only the ones that need a human beep]")
    import io
    buf = io.StringIO()
    rep = report.Reporter(alert=True, stream=buf)
    rep("info", "cast #1")
    rep("success", "kept the fish")
    check("nothing beeped for normal events", rep.beeps == 0, f"{rep.beeps}")
    rep("error", "paused - clear your inventory")
    check("an error beeps", rep.beeps == 1, f"{rep.beeps}")
    rep("warn", "no bite within timeout")
    check("a warning beeps too", rep.beeps == 2, f"{rep.beeps}")
    text = buf.getvalue()
    check("the message reached the console", "paused - clear your inventory" in text)
    # Three of the four levels are coloured: each opens once and resets once.
    check("coloured lines are opened and reset",
          text.count("\033[0m") == 3 and text.count("\033[") == 6,
          f"{text.count(chr(27))} escape chars")


def test_snapshot() -> None:
    print("\n[calibration snapshot: a real PNG, with the regions outlined]")
    from fishbot.geometry import all_regions
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "snap.png")
        img = simhud.render_fight(640, 360, 0.4, 0.5, "left", "sea",
                                  fit=(1280, 720)).copy()
        regions = all_regions(1280, 720)
        for i, box in enumerate(regions.values()):
            report.outline(img, box, (255, 64, 64) if i % 2 else (64, 200, 255))
        report.write_png(path, img)
        with open(path, "rb") as fh:
            data = fh.read()
        check("PNG signature", data[:8] == b"\x89PNG\r\n\x1a\n", f"{data[:4]!r}")
        # signature(8) length(4) "IHDR"(4) width(4) height(4)
        check("IHDR carries 640x360",
              data[12:16] == b"IHDR"
              and int.from_bytes(data[16:20], "big") == 640
              and int.from_bytes(data[20:24], "big") == 360,
              f"{int.from_bytes(data[16:20], 'big')}x{int.from_bytes(data[20:24], 'big')}")
        check("IEND present", data.rstrip().endswith(b"IEND\xaeB`\x82"))
        check("every region was listed", len(regions) > 10, f"{len(regions)}")


def test_program_runs() -> None:
    print("\n[the program itself: starts, reads, casts, and shuts down]")
    with tempfile.TemporaryDirectory() as tmp:
        os.environ[settings.SETTINGS_ENV] = tmp
        calls = {"n": 0}
        original = run.FishingBot.step

        def step_once(self):
            calls["n"] += 1
            if calls["n"] > 30:
                raise KeyboardInterrupt  # what the panic key / Ctrl-C does
            return original(self)

        run.FishingBot.step = step_once
        try:
            rc = run.main(["--simulate", "--scale", "0.25", "--no-alert"])
        finally:
            run.FishingBot.step = original
        check("main returned cleanly", rc == 0, f"rc={rc}")
        check("the loop actually ran", calls["n"] > 5, f"{calls['n']} samples")
        stored = settings.load()
        check("the session was written to the settings file", stored["sessions"] == 1,
              f"{stored['sessions']}")
        os.environ.pop(settings.SETTINGS_ENV, None)


def test_armed_until_start() -> None:
    print("\n[it does not fish until told to: F9 is the trigger]")
    with tempfile.TemporaryDirectory() as tmp:
        os.environ[settings.SETTINGS_ENV] = tmp
        calls = {"n": 0}
        original = run.FishingBot.step

        def step_once(self):
            calls["n"] += 1
            if calls["n"] > 12:
                raise KeyboardInterrupt
            return original(self)

        run.FishingBot.step = step_once
        try:
            rc = run.main(["--simulate", "--no-alert", "--scale", "0.25"])
        finally:
            run.FishingBot.step = original
        check("simulation starts already running", rc == 0 and calls["n"] > 5,
              f"rc={rc} samples={calls['n']}")
        # `--simulate` implies start-now, so the armed path is checked directly
        from fishbot.bot import FishingBot as B
        import inspect
        text = inspect.getsource(run.main)
        check("the live path arms instead of fishing",
              'bot.pause("waiting for F9")' in text and "--start-now" in text, "")
        os.environ.pop(settings.SETTINGS_ENV, None)


def test_ask_for_numpy() -> None:
    print("\n[no numpy: it says so instead of running blind]")
    original = vision.HAVE_NUMPY
    vision.HAVE_NUMPY = False
    try:
        rc = run.main(["--simulate"])
    finally:
        vision.HAVE_NUMPY = original
    check("refuses to start without numpy", rc == 2, f"rc={rc}")


def main() -> int:
    test_settings_roundtrip()
    test_reporter()
    test_snapshot()
    test_program_runs()
    test_armed_until_start()
    test_ask_for_numpy()
    print()
    if failures:
        print(f"{len(failures)} FAILURES")
        for f in failures:
            print("  -", f)
        return 1
    print("all CLI checks passed")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
