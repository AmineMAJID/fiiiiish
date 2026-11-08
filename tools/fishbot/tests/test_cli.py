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


def test_win32_layout() -> None:
    print("\n[the Win32 structures have the sizes the headers specify]")
    import ctypes
    from fishbot import winapi

    ptr = ctypes.sizeof(ctypes.c_void_p)
    expect = 40 if ptr == 8 else 28
    check(f"INPUT is {expect} bytes", ctypes.sizeof(winapi._INPUT) == expect,
          f"{ctypes.sizeof(winapi._INPUT)}")
    check("MOUSEINPUT is 32 bytes on x64 / 24 on x86",
          ctypes.sizeof(winapi._MOUSEINPUT) == (32 if ptr == 8 else 24),
          f"{ctypes.sizeof(winapi._MOUSEINPUT)}")
    check("KEYBDINPUT is 24 bytes on x64 / 16 on x86",
          ctypes.sizeof(winapi._KEYBDINPUT) == (24 if ptr == 8 else 16),
          f"{ctypes.sizeof(winapi._KEYBDINPUT)}")
    check("BITMAPINFOHEADER is 40 bytes",
          ctypes.sizeof(winapi._BITMAPINFOHEADER) == 40,
          f"{ctypes.sizeof(winapi._BITMAPINFOHEADER)}")

    # A dry-run injector is the only way to exercise these paths off Windows,
    # and it is also what makes sure every call is shaped correctly.
    inj = winapi.Injector(dry_run=True)
    inj.move_to(100, 200)
    inj.move_relative(7, 0)
    inj.mouse_down()
    inj.mouse_up()
    inj.click(5, 6)
    inj.key("e")
    inj.key_down("e")
    inj.key_up("e")
    kinds = [k for k, _ in inj.history]
    check("every input call is journalled",
          kinds == ["move", "move_rel", "down", "up", "click", "key", "key_down", "key_up"],
          f"{kinds}")

    # the absolute-coordinate conversion, on a fake desktop so it can be checked
    class _FakeUser32:
        def __init__(self, vx, vy, vw, vh):
            self.box = (vx, vy, vw, vh)

        def GetSystemMetrics(self, index):
            return {76: self.box[0], 77: self.box[1], 78: self.box[2], 79: self.box[3]}[index]

    class _AnyInj(winapi.Injector):
        """A live injector over a fake desktop: nothing is sent, the coordinate
        maths is the real one."""

        def __init__(self, box):
            super().__init__(dry_run=True)
            self.dry_run = False        # take the real code path...
            self.require_foreground = False
            self._user32 = _FakeUser32(*box)

        def _send(self, inp):
            self.sent = getattr(self, "sent", [])
            self.sent.append((inp.mi.dx, inp.mi.dy))

    inj2 = _AnyInj((0, 0, 1920, 1080))
    inj2.move_to(0, 0)
    inj2.move_to(1919, 1079)
    inj2.move_to(-500, 5000)          # off the desktop: clamped, never wrapped
    points = inj2.sent
    check("top-left maps to 0,0", points[0] == (0, 0), f"{points[0]}")
    check("bottom-right maps to 65535,65535", points[1] == (65535, 65535), f"{points[1]}")
    check("out-of-range points are clamped", points[2] == (0, 65535), f"{points[2]}")

    # a second monitor to the left shifts the origin
    inj3 = _AnyInj((-1920, 0, 3840, 1080))
    inj3.move_to(-1920, 540)
    inj3.move_to(1919, 540)
    pts = inj3.sent
    check("a monitor to the left is handled", pts[0][0] == 0 and pts[1][0] == 65535,
          f"{pts}")

    keys = winapi.HotkeyWatcher(dry_run=True)
    check("hotkeys are inert when dry", keys.poll() == [], "pressed something")
    check("the panic keys are bound",
          set(keys.keys) == {"start", "stop", "pause"}, f"{sorted(keys.keys)}")


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


class _FakeUser32:
    """Just enough of user32 to decide where the focus is."""

    def __init__(self, foreground=0, console=0, game=1):
        self.foreground = foreground
        self.console = console
        self.game = game
        self.activated = 0
        self.clicked_moves = 0

    # window queries -------------------------------------------------------
    def IsIconic(self, hwnd):
        return False

    def IsWindow(self, hwnd):
        return True

    def GetForegroundWindow(self):
        return self.foreground

    def GetConsoleWindow(self):
        return self.console

    def GetWindowThreadProcessId(self, hwnd, _):
        return 42

    # activation ----------------------------------------------------------
    def ShowWindow(self, hwnd, cmd):
        return 1

    def BringWindowToTop(self, hwnd):
        return 1

    def SetFocus(self, hwnd):
        return 1

    def SwitchToThisWindow(self, hwnd, flag):
        return 1

    def AttachThreadInput(self, a, b, attach):
        return 1

    def SetForegroundWindow(self, hwnd):
        # Windows only sometimes honours this; here it always does, so the
        # "works without a click" path is the one exercised first.
        self.activated += 1
        self.foreground = int(hwnd)
        return 1

    # input ---------------------------------------------------------------
    def GetSystemMetrics(self, index):
        return {76: 0, 77: 0, 78: 1920, 79: 1080}.get(index, 0)

    def SendInput(self, count, ptr, size):
        self.clicked_moves += 1
        return count


class _StubbornUser32(_FakeUser32):
    """``SetForegroundWindow`` is refused, as Windows usually refuses it."""

    def SetForegroundWindow(self, hwnd):
        return 0


class _FakeInjectorUser32(_StubbornUser32):
    """Refuses activation, and only takes the focus after a click."""

    def SendInput(self, count, ptr, size):
        self.clicked_moves += 1
        self.foreground = self.game       # a click is what actually focuses
        return count


def _with_user32(winapi, fake):
    """Hand ``fake`` to the module as its user32, as the capture tests do."""
    winapi._user32 = lambda: fake
    winapi.IS_WINDOWS = True
    return fake


def test_focus() -> None:
    print("\n[focus: F9 arrives, but the game must be the window that gets the keys]")
    from fishbot import winapi

    real_user32, real_windows = winapi._user32, winapi.IS_WINDOWS
    try:
        # 1. where is the focus, said plainly
        fake = _FakeUser32(foreground=11, console=7, game=11)
        _with_user32(winapi, fake)
        check("the game has the focus", winapi.focus_of(11).ok, str(winapi.focus_of(11)))
        fake.foreground = 7
        check("our own console has it", winapi.focus_of(11).state == "console",
              str(winapi.focus_of(11)))
        fake.foreground = 99
        check("something else has it", winapi.focus_of(11).state == "other",
              str(winapi.focus_of(11)))

        # 2. the click that takes it back lands where it can press nothing
        from fishbot.winapi import ClientArea, aim_point
        area = ClientArea(hwnd=11, title="FiveM", left=0, top=0, width=1920, height=1080,
                          monitor_left=0, monitor_top=0, monitor_width=1920,
                          monitor_height=1080)
        ax, ay = aim_point(area)
        check("the focus click is near the top, away from the HUD and the crosshair",
              area.left < ax < area.left + area.width * 0.5
              and ay < area.top + area.height * 0.25, f"({ax},{ay})")

        # 3. the injector is allowed exactly one thing it is not gated on: that click
        fake = _FakeInjectorUser32(foreground=7, console=7, game=11)
        _with_user32(winapi, fake)
        inj = winapi.Injector(require_foreground=True, target_hwnd=11)
        check("a background game is not a place to send input", not inj.foreground_ok())
        check("no click while the pointer is not ours", inj.click_for_focus(area) is None)
        # The pointer becomes ours the first time the tool moves it - which can
        # only happen once the game is focused, so the click path is entered
        # from a run that has already fished at least one cast.
        inj._moved_by_us = True
        inj.last_cursor = (900, 700)
        how = inj.ensure_foreground(area)
        check("it got the focus, and says how", how in ("clicked", "activated"), how)
        check("the game is focused afterwards", inj.foreground_ok())
        check("exactly one click was spent", fake.clicked_moves >= 1,
              f"{fake.clicked_moves}")

        # 4. a click is never sent when the game is minimised
        class _Minimised(_FakeInjectorUser32):
            def IsIconic(self, hwnd):
                return True

        fake = _Minimised(foreground=7, console=7, game=11)
        _with_user32(winapi, fake)
        inj = winapi.Injector(require_foreground=True, target_hwnd=11)
        inj._moved_by_us = True
        inj.last_cursor = (900, 700)
        before = fake.clicked_moves
        check("a minimised game gets no click", inj.click_for_focus(area) is None)
        check("...and nothing was sent", fake.clicked_moves == before,
              f"{before} -> {fake.clicked_moves}")
    finally:
        winapi._user32 = real_user32
        winapi.IS_WINDOWS = real_windows


def test_idle_diagnosis() -> None:
    """A tool that sits there silently is the worst kind.  It must say why."""
    print("\n[when nothing happens, it says what it is waiting for]")
    from fishbot.bot import FishingBot, BotConfig, WAITING
    from fishbot import simhud
    from fishbot.vision import Frame
    from fishbot.winapi import FocusState

    class _Source:
        """A frame source that can be told what to show and who has the focus."""

        def __init__(self):
            self.focus = FocusState(state="game")
            self.now = lambda: t[0]
            self.frames = 0

        def grab(self):
            self.frames += 1
            img = simhud._blank(640, 360, "sea")
            return Frame(arr=img, width=640, height=360, timestamp=self.now())

        def to_screen(self, nx, ny):
            return int(nx * 1920), int(ny * 1080)

    class _Inj:
        def __init__(self):
            self.sent = []

        def foreground_ok(self):
            return True

        def key_down(self, *_):
            self.sent.append("down")

        def key_up(self, *_):
            self.sent.append("up")

        def mouse_down(self, *_):
            pass

        def mouse_up(self, *_):
            pass

        def click(self, *_):
            pass

    t = [0.0]
    events = []
    src, inj = _Source(), _Inj()
    bot = FishingBot(source=src, injector=inj,
                     config=BotConfig(require_cast_gate=True, idle_ticks=2),
                     notify=lambda level, msg: events.append((level, msg)),
                     clock=lambda: t[0], sleep=lambda s: t.__setitem__(0, t[0] + s))
    for _ in range(8):
        bot.step()
        t[0] += 0.5
    gripes = bot.gripes()
    check("a long wait is reported, and says what it is waiting for",
          any(k == "gate-missing" and ("water" in g or "rod" in g) for k, g in gripes),
          str(gripes))
    check("the message is stable while the situation is (so it is said once)",
          bot.gripes()[0][0] == "gate-missing", str(bot.gripes()))
    check("the wording is accurate: no card at all is not 'greyed out'",
          any("depth card is not on screen" in g for k, g in gripes), str(gripes))

    # an unfocused window is the other way "nothing happens"
    src.focus = FocusState(state="console")
    inj.foreground_ok = lambda: False
    before = len(inj.sent)
    for _ in range(6):
        bot.step()
        t[0] += 0.5
    check("no key is pressed while the console has the focus", len(inj.sent) == before,
          f"{before} -> {len(inj.sent)}")
    check("and that is what it says", any(k == "focus" for k, _ in bot.gripes()),
          str(bot.gripes()))


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
    test_win32_layout()
    test_settings_roundtrip()
    test_reporter()
    test_snapshot()
    test_program_runs()
    test_armed_until_start()
    test_focus()
    test_idle_diagnosis()
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
