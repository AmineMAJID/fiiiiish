"""Windows input driver for the live bot.

The bot only needs three primitives:

* a relative mouse move (the camera is the only fight input),
* a left-button press/release (the cast charge),
* an ``E`` press (start the cast / strike).

They are implemented with ``SendInput``, the same Win32 call pydirectinput
uses, so there is no third-party dependency.  Relative mouse deltas are what
a cursor-grabbing game expects; ``SetCursorPos`` would be ignored.

The module is import-safe on Linux: the class raises a clear error only when
it is actually instantiated, which keeps the simulator and tests portable.
"""

from __future__ import annotations

import ctypes
import sys
import time
from ctypes import wintypes
from typing import Protocol

# ---------------------------------------------------------------------------
# Win32 constants
# ---------------------------------------------------------------------------
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008

# VK for E and F10
VK_E = 0x45
VK_F10 = 0x79


class MouseInput(Protocol):
    def move(self, dx: int, dy: int) -> None: ...
    def left_down(self) -> None: ...
    def left_up(self) -> None: ...
    def press_e(self) -> None: ...
    def stop_requested(self) -> bool: ...
    def game_focused(self) -> bool: ...
    def close(self) -> None: ...


# ---------------------------------------------------------------------------
# structures
# ---------------------------------------------------------------------------
if sys.platform == "win32":
    class _MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wintypes.LONG),
            ("dy", wintypes.LONG),
            ("mouseData", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
        ]

    class _KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
        ]

    class _INPUTUNION(ctypes.Union):
        _fields_ = [("mi", _MOUSEINPUT), ("ki", _KEYBDINPUT)]

    class _INPUT(ctypes.Structure):
        _anonymous_ = ("u",)
        _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]

    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _user32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(_INPUT), ctypes.c_int)
    _user32.SendInput.restype = wintypes.UINT
    _user32.GetForegroundWindow.argtypes = ()
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.GetWindowTextW.argtypes = (wintypes.HWND, wintypes.LPWSTR, ctypes.c_int)
    _user32.GetWindowTextW.restype = ctypes.c_int
    _user32.GetAsyncKeyState.argtypes = (ctypes.c_int,)
    _user32.GetAsyncKeyState.restype = ctypes.c_short
    _user32.SetForegroundWindow.argtypes = (wintypes.HWND,)
    _user32.SetForegroundWindow.restype = wintypes.BOOL
    _user32.EnumWindows.argtypes = (ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM), wintypes.LPARAM)
    _user32.EnumWindows.restype = wintypes.BOOL
    _user32.IsWindowVisible.argtypes = (wintypes.HWND,)
    _user32.IsWindowVisible.restype = wintypes.BOOL
    _user32.GetWindowThreadProcessId.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.DWORD))
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.MapVirtualKeyW.argtypes = (wintypes.UINT, wintypes.UINT)
    _user32.MapVirtualKeyW.restype = wintypes.UINT
else:
    _user32 = None


def _send(inputs: list[_INPUT]) -> None:
    if _user32 is None:
        raise RuntimeError("SendInput is only available on Windows")
    _user32.SendInput(len(inputs), (ctypes.POINTER(_INPUT) * len(inputs))(*inputs), ctypes.sizeof(_INPUT))


def _mouse_input(dx: int, dy: int, flags: int) -> _INPUT:
    inp = _INPUT()
    inp.type = INPUT_MOUSE
    inp.mi.dx = int(dx)
    inp.mi.dy = int(dy)
    inp.mi.mouseData = 0
    inp.mi.dwFlags = flags
    inp.mi.time = 0
    inp.mi.dwExtraInfo = None
    return inp


def _key_input(vk: int, up: bool = False) -> _INPUT:
    """Send a keyboard event. Games read scan codes, so use them when possible."""
    inp = _INPUT()
    inp.type = INPUT_KEYBOARD
    scan = 0
    if _user32 is not None:
        scan = _user32.MapVirtualKeyW(vk, 0)
    if scan:
        inp.ki.wVk = 0
        inp.ki.wScan = scan
        inp.ki.dwFlags = KEYEVENTF_SCANCODE | (KEYEVENTF_KEYUP if up else 0)
    else:
        inp.ki.wVk = vk
        inp.ki.wScan = 0
        inp.ki.dwFlags = KEYEVENTF_KEYUP if up else 0
    inp.ki.time = 0
    inp.ki.dwExtraInfo = None
    return inp


class Win32Input:
    """SendInput-based mouse/keyboard driver."""

    def __init__(self, *, game_title: str = "FiveM", failsafe_vk: int = VK_F10) -> None:
        if sys.platform != "win32":
            raise RuntimeError(
                "The live bot needs Windows (SendInput). Use the simulator on "
                "Linux/macOS: python -m fiiiiish_auto simulate"
            )
        self.game_title = game_title
        self.failsafe_vk = failsafe_vk
        self._hwnd: int | None = None
        self._closed = False

    # -- window helpers ---------------------------------------------------
    def find_window(self) -> int | None:
        """Find the first visible window whose title contains ``game_title``."""
        found: list[int] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def _enum(hwnd, _lparam):
            if not _user32.IsWindowVisible(hwnd):
                return True
            length = _user32.GetWindowTextW(hwnd, ctypes.create_unicode_buffer(256), 256)
            if length:
                title = ctypes.create_unicode_buffer(256)
                _user32.GetWindowTextW(hwnd, title, 256)
                if self.game_title.lower() in title.value.lower():
                    found.append(hwnd)
            return True

        _user32.EnumWindows(_enum, 0)
        return found[0] if found else None

    def focus_game(self) -> bool:
        if self._hwnd is None:
            self._hwnd = self.find_window()
        if self._hwnd is None:
            return False
        return bool(_user32.SetForegroundWindow(self._hwnd))

    def game_focused(self) -> bool:
        if _user32 is None:
            return False
        hwnd = _user32.GetForegroundWindow()
        if not hwnd:
            return False
        if self._hwnd is not None and hwnd == self._hwnd:
            return True
        title = ctypes.create_unicode_buffer(256)
        _user32.GetWindowTextW(hwnd, title, 256)
        return self.game_title.lower() in title.value.lower()

    # -- input ------------------------------------------------------------
    def move(self, dx: int, dy: int) -> None:
        if self._closed or (dx == 0 and dy == 0):
            return
        _send([_mouse_input(dx, dy, MOUSEEVENTF_MOVE)])

    def left_down(self) -> None:
        if self._closed:
            return
        _send([_mouse_input(0, 0, MOUSEEVENTF_LEFTDOWN)])

    def left_up(self) -> None:
        if self._closed:
            return
        _send([_mouse_input(0, 0, MOUSEEVENTF_LEFTUP)])

    def press_e(self) -> None:
        if self._closed:
            return
        _send([_key_input(VK_E, up=False), _key_input(VK_E, up=True)])

    def stop_requested(self) -> bool:
        if _user32 is None:
            return False
        # F10 is a hard stop that works even while the game has focus.
        return bool(_user32.GetAsyncKeyState(self.failsafe_vk) & 0x8000)

    def close(self) -> None:
        self._closed = True


class DryRunInput:
    """Logs what would be sent, without touching the OS.

    Used by ``--dry-run`` and by the test-suite on non-Windows machines.
    """

    def __init__(self, *, game_title: str = "FiveM", log=print) -> None:
        self.game_title = game_title
        self.log = log
        self.steps = 0
        self.buttons = 0
        self.keys = 0
        self._closed = False

    def find_window(self) -> int | None:
        return 0

    def focus_game(self) -> bool:
        return True

    def game_focused(self) -> bool:
        return True

    def move(self, dx: int, dy: int) -> None:
        if self._closed or (dx == 0 and dy == 0):
            return
        self.steps += 1
        self.log(f"[dry-run] mouse move {dx:+d},{dy:+d}")

    def left_down(self) -> None:
        if self._closed:
            return
        self.buttons += 1
        self.log("[dry-run] left button down")

    def left_up(self) -> None:
        if self._closed:
            return
        self.buttons += 1
        self.log("[dry-run] left button up")

    def press_e(self) -> None:
        if self._closed:
            return
        self.keys += 1
        self.log("[dry-run] press E")

    def stop_requested(self) -> bool:
        return False

    def close(self) -> None:
        self._closed = True


class LiveCamera:
    """Converts controller degrees into relative mouse pixels.

    ``sensitivity`` is degrees of camera rotation per mouse count.  It depends
    on the player's in-game sensitivity and FOV, so it is configurable and can
    be calibrated with ``--calibrate``.  The controller is closed-loop, so a
    rough value still works; the value mainly changes how fast a cross is.
    """

    def __init__(
        self,
        mouse: MouseInput,
        *,
        sensitivity: float = 0.10,
        invert_x: bool = False,
        max_pixels_per_tick: int = 120,
    ) -> None:
        if sensitivity <= 0.0:
            raise ValueError("sensitivity must be positive")
        self.mouse = mouse
        self.sensitivity = float(sensitivity)
        self.invert_x = bool(invert_x)
        self.max_pixels_per_tick = int(max_pixels_per_tick)
        self._remainder = 0.0
        self.total_pixels = 0

    def apply(self, step_degrees: float, dt: float) -> float:
        pixels = step_degrees / self.sensitivity
        if self.invert_x:
            pixels = -pixels
        pixels = max(-self.max_pixels_per_tick, min(self.max_pixels_per_tick, pixels))
        self._remainder += pixels
        whole = int(round(self._remainder))
        self._remainder -= whole
        if whole != 0:
            self.mouse.move(whole, 0)
            self.total_pixels += whole
        return step_degrees


def make_input(*, dry_run: bool = False, game_title: str = "FiveM", log=print) -> MouseInput:
    if dry_run:
        return DryRunInput(game_title=game_title, log=log)
    return Win32Input(game_title=game_title)
