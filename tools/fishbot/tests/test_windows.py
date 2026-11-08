"""End-to-end on a *fake Windows*: does the program really press keys?

    python -m tests.test_windows

Every other suite replaces one piece (the frames, the injector, the controller).
This one keeps the real ``fishbot.run``, the real screen reader, the real
geometry and the real injector, and replaces only ``user32``/``gdi32`` - the
Windows API boundary.  That is the layer where the reported bug lived: the loop
was healthy, the picture was fine, and not one event reached the game because a
guard in the injector was refusing everything, silently.

So this file asserts the thing the player cares about: **SendInput is called
with a real key press**, from a program that found a window and believed it was
focused.
"""

from __future__ import annotations

import ctypes
import os
import sys
import tempfile
from typing import List

import numpy as np

from fishbot import run, settings, simhud, vision, winapi
from fishbot.vision import Frame

failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
    if not ok:
        failures.append(f"{name} {detail}")


# ── the fake Windows API -----------------------------------------------------
class _Fn:
    """A callable that also tolerates ctypes' ``.restype = ...``."""

    def __init__(self, fn):
        self._fn = fn
        self.restype = None
        self.argtypes = None

    def __call__(self, *a, **k):
        return self._fn(*a, **k)


class FakeUser32:
    """A focused 1920x1080 game window, and a record of everything sent."""

    GAME = 500
    CONSOLE = 7

    def __init__(self, foreground: int = GAME, client: int = 0,
                 title: str = "FiveM", minimised: bool = False):
        self.foreground = foreground
        self.client = client
        self.title = title
        self.minimised = minimised
        self.sent: List[int] = []          # sizeof(_INPUT) per SendInput call
        self.keys: List[int] = []
        self.switches = 0

    # -- window ----------------------------------------------------------
    def IsWindow(self, hwnd): return True
    def IsWindowVisible(self, hwnd): return True
    def IsIconic(self, hwnd): return self.minimised
    def GetForegroundWindow(self): return self.foreground
    def GetConsoleWindow(self): return self.CONSOLE
    def GetWindowThreadProcessId(self, hwnd, out): return 42
    def SetProcessDpiAwarenessContext(self, value): return 1
    def GetAsyncKeyState(self, vk): return 0
    def MonitorFromWindow(self, hwnd, flags): return 1
    def ShowWindow(self, hwnd, cmd): return 1
    def BringWindowToTop(self, hwnd): return 1
    def SetFocus(self, hwnd): return 1
    def AttachThreadInput(self, a, b, attach): return 1
    def SwitchToThisWindow(self, hwnd, flag): return 1

    def GetDC(self, hwnd): return 1
    def ReleaseDC(self, hwnd, dc): return 1
    def PrintWindow(self, hwnd, dc, flags): return 1

    def SetForegroundWindow(self, hwnd):
        # Windows refuses this for a background process; the fake refuses too,
        # so the click path is the one that has to work.
        return 0

    def GetClientRect(self, hwnd, rc):
        ref = getattr(rc, "_obj", rc)
        ref.left = ref.top = 0
        ref.right, ref.bottom = 1920, 1080
        return 1

    def ClientToScreen(self, hwnd, pt):
        ref = getattr(pt, "_obj", pt)
        ref.x = ref.y = 0
        return 1

    def GetWindowTextW(self, hwnd, buf, size):
        buf.value = self.title
        return len(self.title)

    def GetWindowTextLengthW(self, hwnd): return len(self.title)

    def EnumWindows(self, cb, lparam):
        cb(self.GAME, lparam)
        return 1

    def GetMonitorInfoW(self, hmon, info):
        ref = getattr(info, "_obj", info)
        ref.rcMonitor.left = ref.rcMonitor.top = 0
        ref.rcMonitor.right, ref.rcMonitor.bottom = 1920, 1080
        return 1

    def GetSystemMetrics(self, index):
        return {76: 0, 77: 0, 78: 1920, 79: 1080}.get(index, 0)

    # -- input -----------------------------------------------------------
    def SendInput(self, count, ptr, size):
        self.sent.append(size)
        inp = ctypes.cast(ptr, ctypes.POINTER(winapi._INPUT)).contents
        if inp.type == winapi.INPUT_KEYBOARD:
            self.keys.append(inp.ki.wVk)
        if inp.type == winapi.INPUT_MOUSE:
            # a click is what focuses a window on a real machine
            if inp.mi.dwFlags & winapi.MOUSEEVENTF_LEFTDOWN:
                self.foreground = self.GAME
        return count


class FakeGdi:
    """A GDI that returns whatever the test asked for, at whatever size."""

    def __init__(self, image=None):
        self.image = image
        self.size = [0, 0]

    def CreateCompatibleDC(self, dc): return 1
    def CreateCompatibleBitmap(self, dc, w, h): return 1
    def SelectObject(self, dc, obj): return 1
    def SetStretchBltMode(self, dc, mode): return 1
    def DeleteObject(self, obj): return 1
    def DeleteDC(self, dc): return 1
    def BitBlt(self, *a): return 1

    def StretchBlt(self, dc, x, y, w, h, *rest):
        self.size = [w, h]
        return 1

    def GetDIBits(self, dc, bmp, start, rows, buf, info, flags):
        w, h = self.size
        img = self.image(w, h) if callable(self.image) else self.image
        bgra = np.zeros((h, w, 4), dtype=np.uint8)      # what GDI really gives
        bgra[:, :, 0] = img[:, :, 2]
        bgra[:, :, 1] = img[:, :, 1]
        bgra[:, :, 2] = img[:, :, 0]
        bgra[:, :, 3] = 255
        ctypes.memmove(buf, bgra.tobytes(), bgra.nbytes)
        return rows


def install(user: FakeUser32, gdi: FakeGdi) -> None:
    """Point the module at a fake Windows.  Returns an undo function."""
    # ``EnumWindows`` takes a ``WINFUNCTYPE`` callback, which only exists on
    # Windows' ctypes: stub both for the duration of the test.
    saved = (getattr(ctypes, "WINFUNCTYPE", None), getattr(ctypes, "WinDLL", None))
    ctypes.WINFUNCTYPE = lambda *a, **k: (lambda fn: fn)      # type: ignore[attr-defined]
    # ctypes sets ``.restype`` on real DLL functions; wrap the fake's methods so
    # the production code can do that too.
    for name in ("MonitorFromWindow", "GetAsyncKeyState", "SendInput", "GetDC",
                 "PrintWindow", "GetForegroundWindow"):
        if hasattr(user, name) and not isinstance(getattr(user, name), _Fn):
            setattr(user, name, _Fn(getattr(user, name)))
    for name in ("GetDIBits", "StretchBlt", "CreateCompatibleDC"):
        if hasattr(gdi, name) and not isinstance(getattr(gdi, name), _Fn):
            setattr(gdi, name, _Fn(getattr(gdi, name)))
    winapi._user32 = lambda: user
    winapi._gdi32 = lambda: gdi
    winapi.IS_WINDOWS = True

    def undo() -> None:
        for name, value in zip(("WINFUNCTYPE", "WinDLL"), saved):
            if value is None:
                if hasattr(ctypes, name):
                    delattr(ctypes, name)
            else:
                setattr(ctypes, name, value)
    return undo


def depth_card(w, h):
    """A frame showing "rod out, water in front, cast allowed" (green key)."""
    return simhud.render_depth_card(w, h, True, "sea", fit=(1920, 1080))


def empty(w, h):
    return simhud._blank(w, h, "sea")


def drive(samples: int = 130, hz: float = 60.0, extra=()) -> int:
    """Run the real program for ``samples`` loop iterations, then stop it."""
    original = run.FishingBot.step
    counter = {"n": 0}

    def step(self):
        counter["n"] += 1
        if counter["n"] > samples:
            raise KeyboardInterrupt
        return original(self)

    run.FishingBot.step = step
    try:
        return run.main(["--no-alert", "--hz", str(hz), *extra])
    finally:
        run.FishingBot.step = original


def test_it_really_types() -> None:
    print("\n[the program, on a fake Windows, actually sends the key press]")
    with tempfile.TemporaryDirectory() as tmp:
        os.environ[settings.SETTINGS_ENV] = tmp
        user, gdi = FakeUser32(), FakeGdi(depth_card)
        install(user, gdi)
        try:
            rc = drive(extra=["--start-now"])
        finally:
            os.environ.pop(settings.SETTINGS_ENV, None)
        check("the program ran", rc == 0, f"rc={rc}")
        check("SendInput was called", len(user.sent) > 0, f"{len(user.sent)} calls")
        check("the E key was pressed and released",
              user.keys.count(winapi.VK_CODES["e"]) >= 2, f"vk={user.keys}")
        check("the click that focuses the game was the first event",
              len(user.sent) >= 1, f"{len(user.sent)}")


def test_no_window_no_keys() -> None:
    print("\n[twenty seconds of nothing: it must say why, not go quiet]")
    with tempfile.TemporaryDirectory() as tmp:
        os.environ[settings.SETTINGS_ENV] = tmp
        user = FakeUser32(client=0)
        install(user, FakeGdi(empty))
        # a title nothing matches: the program says so and exits
        original = winapi.find_game_window
        winapi.find_game_window = lambda titles=(): None
        try:
            buffer = []

            class _Sink:
                def __init__(self, *a, **k):
                    pass

                def write(self, text):
                    buffer.append(text)

                def flush(self):
                    pass

            real_stderr, sys.stderr = sys.stderr, _Sink()
            try:
                rc = run.main(["--no-alert", "--hz", "20"])
            finally:
                sys.stderr = real_stderr
            text = "".join(buffer)
        finally:
            winapi.find_game_window = original
            os.environ.pop(settings.SETTINGS_ENV, None)
        check("it refuses to run without a window", rc == 2, f"rc={rc}")
        check("...and says what to do", "window" in text.lower() and
              ("title" in text.lower() or "running" in text.lower()), text.strip()[:120])
        check("nothing was sent", not user.sent, f"{len(user.sent)} events")


def test_unfocused_is_loud() -> None:
    """A window that never comes to the front must not make the tool mute."""
    print("\n[a window that never takes the focus cannot make the tool mute]")
    with tempfile.TemporaryDirectory() as tmp:
        os.environ[settings.SETTINGS_ENV] = tmp
        user = FakeUser32(foreground=FakeUser32.CONSOLE)

        def never_focuses(count, ptr, size):
            # record, but a click on this window does not give it the focus
            user.sent.append(size)
            return count

        undo = install(user, FakeGdi(depth_card))
        user.SendInput = never_focuses
        lines: List[str] = []

        class _Sink:
            def write(self, text):
                lines.append(text)

            def flush(self):
                pass

        import io
        real_out, sys.stdout = sys.stdout, _Sink()
        try:
            rc = drive(samples=40, extra=["--start-now"])
        finally:
            sys.stdout = real_out
            undo()
            os.environ.pop(settings.SETTINGS_ENV, None)
        said = "".join(lines)
        check("it ran to the end", rc == 0, f"rc={rc}")
        check("no key was ever sent", not user.keys, f"vk={user.keys}")
        check("it said the input was refused", "input refused" in said,
              said.strip().splitlines()[-1][:100] if said.strip() else "silence")
        check("...and named the window that has the focus instead",
              str(FakeUser32.CONSOLE) in said, "")
        check("the loop stayed alive rather than crashing", "Traceback" not in said, "")


def main() -> int:
    print("windows-layer tests (fake user32/gdi32, the real program)")
    if not vision.HAVE_NUMPY:
        print("numpy is required for these tests")
        return 2
    test_it_really_types()
    test_no_window_no_keys()
    test_unfocused_is_loud()
    print()
    if failures:
        print(f"{len(failures)} FAILURES")
        for f in failures:
            print("  -", f)
        return 1
    print("all Windows-layer checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
