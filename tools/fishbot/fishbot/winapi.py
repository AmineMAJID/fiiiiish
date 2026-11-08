"""Windows capture and input injection, straight through ``ctypes``.

No pywin32, no pydirectinput, no OpenCV: the tool ships as a folder you can
copy anywhere and run with a stock Python.  Everything here is used only when
the tool actually drives the game; the rest of the package (geometry, vision,
controller) is platform independent and unit-tested against synthetic frames.

Reading the screen
------------------
FiveM draws with DirectX, so ``BitBlt`` happily returns black on many setups.
``PrintWindow`` with ``PW_RENDERFULLCONTENT`` (0x00000002) asks Windows to have
the window render itself into our bitmap, which works for D3D windows and does
not need the window to be on top.  We try it first and fall back to ``BitBlt``
of the window's client area.

Sending input
-------------
``SendInput`` only: it is what a real mouse and keyboard go through, so it
reaches DirectInput, Raw Input and the game's own control polling alike.
Messages posted with ``PostMessage`` would not move a camera.
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import sys
from dataclasses import dataclass
from typing import Optional, Tuple

IS_WINDOWS = sys.platform.startswith("win")

# ── Win32 constants ─────────────────────────────────────────────────────────
SRCCOPY = 0x00CC0020
PW_RENDERFULLCONTENT = 0x00000002

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_ABSOLUTE = 0x8000
MOUSEEVENTF_VIRTUALDESK = 0x4000

KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
KEYEVENTF_EXTENDEDKEY = 0x0001

SM_XVIRTUALSCREEN = 76
SM_YVIRTUALSCREEN = 77
SM_CXVIRTUALSCREEN = 78
SM_CYVIRTUALSCREEN = 79

MONITOR_DEFAULTTONEAREST = 2


class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wt.DWORD),
        ("biWidth", wt.LONG),
        ("biHeight", wt.LONG),
        ("biPlanes", wt.WORD),
        ("biBitCount", wt.WORD),
        ("biCompression", wt.DWORD),
        ("biSizeImage", wt.DWORD),
        ("biXPelsPerMeter", wt.LONG),
        ("biYPelsPerMeter", wt.LONG),
        ("biClrUsed", wt.DWORD),
        ("biClrImportant", wt.DWORD),
    ]


class _BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", _BITMAPINFOHEADER), ("bmiColors", wt.DWORD * 3)]


class _MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD),
                ("dwFlags", wt.DWORD), ("time", wt.DWORD),
                ("dwExtraInfo", ctypes.POINTER(wt.ULONG))]


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ctypes.POINTER(wt.ULONG))]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("mi", _MOUSEINPUT), ("ki", _KEYBDINPUT)]


class _INPUT(ctypes.Structure):
    _anonymous_ = ("u",)
    _fields_ = [("type", wt.DWORD), ("u", _INPUTUNION)]


def _user32():
    if not IS_WINDOWS:
        raise RuntimeError("the input/capture layer only runs on Windows")
    return ctypes.WinDLL("user32", use_last_error=True)


def _gdi32():
    if not IS_WINDOWS:
        raise RuntimeError("the input/capture layer only runs on Windows")
    return ctypes.WinDLL("gdi32", use_last_error=True)


def set_dpi_awareness() -> None:
    """Make our coordinates the same physical pixels the GPU is drawing.

    Without this, on a scaled display the window rect we read is in logical
    units while the framebuffer is not, and every click lands somewhere else.
    """
    if not IS_WINDOWS:
        return
    try:
        user32 = _user32()
        # PER_MONITOR_AWARE_V2 with a DPI_AWARENESS_CONTEXT of -4
        if user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4)):
            return
    except Exception:
        pass
    try:
        ctypes.WinDLL("shcore").SetProcessDpiAwareness(2)
    except Exception:
        try:
            _user32().SetProcessDPIAware()
        except Exception:
            pass


# ── the game window ─────────────────────────────────────────────────────────
@dataclass
class ClientArea:
    """Where the game's picture actually is, in *screen* physical pixels."""

    hwnd: int
    title: str
    left: int
    top: int
    width: int
    height: int
    monitor_left: int
    monitor_top: int
    monitor_width: int
    monitor_height: int

    @property
    def covers_monitor(self) -> bool:
        return (self.left <= self.monitor_left + 1
                and self.top <= self.monitor_top + 1
                and self.left + self.width >= self.monitor_left + self.monitor_width - 1
                and self.top + self.height >= self.monitor_top + self.monitor_height - 1)

    def describe(self) -> str:
        mode = "exclusive fullscreen" if self.covers_monitor else "windowed / borderless"
        return (f"hwnd={self.hwnd} '{self.title}' client={self.width}x{self.height} "
                f"at ({self.left},{self.top}) monitor={self.monitor_width}x"
                f"{self.monitor_height} -> {mode}")


def find_game_window(titles=("FiveM", "Grand Theft Auto V", "GTAV", "CitizenFX")) -> Optional[int]:
    """First visible top-level window whose title matches one of ``titles``."""
    user32 = _user32()
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def _cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length == 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        name = buf.value
        if any(t.lower() in name.lower() for t in titles):
            found.append((hwnd, name))
        return True

    user32.EnumWindows(_cb, 0)
    if not found:
        return None
    # Prefer a window that has a real client area (skips splash/console windows).
    best = None
    best_area = 0
    for hwnd, name in found:
        rect = _client_rect(hwnd)
        if rect and rect[2] * rect[3] > best_area:
            best, best_area = hwnd, rect[2] * rect[3]
    return best


def _client_rect(hwnd: int) -> Optional[Tuple[int, int, int, int]]:
    user32 = _user32()
    rc = wt.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(rc)):
        return None
    pt = wt.POINT(0, 0)
    if not user32.ClientToScreen(hwnd, ctypes.byref(pt)):
        return None
    return pt.x, pt.y, rc.right - rc.left, rc.bottom - rc.top


def _monitor_rect(hwnd: int) -> Tuple[int, int, int, int]:
    user32 = _user32()

    class _MONITORINFO(ctypes.Structure):
        _fields_ = [("cbSize", wt.DWORD), ("rcMonitor", wt.RECT), ("rcWork", wt.RECT),
                    ("dwFlags", wt.DWORD)]

    user32.MonitorFromWindow.restype = wt.HANDLE
    hmon = user32.MonitorFromWindow(wt.HWND(hwnd), MONITOR_DEFAULTTONEAREST)
    info = _MONITORINFO()
    info.cbSize = ctypes.sizeof(_MONITORINFO)
    if not user32.GetMonitorInfoW(hmon, ctypes.byref(info)):
        return 0, 0, 0, 0
    r = info.rcMonitor
    return r.left, r.top, r.right - r.left, r.bottom - r.top


def client_area(hwnd: Optional[int] = None, titles=("FiveM", "Grand Theft Auto V", "GTAV")) -> ClientArea:
    set_dpi_awareness()
    if hwnd is None:
        hwnd = find_game_window(titles)
    if not hwnd:
        raise RuntimeError("could not find the FiveM window - is the game running? "
                           "Use --window-title in your config if your title differs.")
    rect = _client_rect(hwnd)
    if not rect:
        raise RuntimeError(f"could not read the client area of window {hwnd}")
    left, top, w, h = rect
    if w < 200 or h < 200:
        raise RuntimeError(f"the game window is only {w}x{h}; restore it and try again")
    buf = ctypes.create_unicode_buffer(256)
    _user32().GetWindowTextW(hwnd, buf, 256)
    ml, mt, mw, mh = _monitor_rect(hwnd)
    return ClientArea(hwnd=hwnd, title=buf.value, left=left, top=top, width=w, height=h,
                      monitor_left=ml, monitor_top=mt, monitor_width=mw, monitor_height=mh)


# ── capture ─────────────────────────────────────────────────────────────────
def _capture_region(area: ClientArea, src_w: int, src_h: int,
                    dst_w: int, dst_h: int, method: str):
    """Grab ``src_w`` x ``src_h`` of the client area and scale to ``dst_w`` x
    ``dst_h`` with GDI (cheap: no full-size intermediate in Python)."""
    import numpy as np

    user32 = _user32()
    gdi32 = _gdi32()

    hdc_window = user32.GetDC(area.hwnd)
    if not hdc_window:
        raise RuntimeError("GetDC failed")
    hdc_mem = gdi32.CreateCompatibleDC(hdc_window)
    hdc_dst = gdi32.CreateCompatibleDC(hdc_window)
    bmp = None
    bmp_dst = None
    try:
        bmp = gdi32.CreateCompatibleBitmap(hdc_window, max(1, src_w), max(1, src_h))
        gdi32.SelectObject(hdc_mem, bmp)
        ok = False
        if method == "printwindow":
            ok = bool(user32.PrintWindow(wt.HWND(area.hwnd), hdc_mem, PW_RENDERFULLCONTENT))
        if not ok:
            ok = bool(gdi32.BitBlt(hdc_mem, 0, 0, src_w, src_h, hdc_window, 0, 0, SRCCOPY))
        if not ok:
            raise RuntimeError("both PrintWindow and BitBlt failed")

        bmp_dst = gdi32.CreateCompatibleBitmap(hdc_window, dst_w, dst_h)
        gdi32.SelectObject(hdc_dst, bmp_dst)
        gdi32.SetStretchBltMode(hdc_dst, 3)  # HALFTONE
        gdi32.StretchBlt(hdc_dst, 0, 0, dst_w, dst_h, hdc_mem, 0, 0, src_w, src_h, SRCCOPY)

        info = _BITMAPINFO()
        info.bmiHeader.biSize = ctypes.sizeof(_BITMAPINFOHEADER)
        info.bmiHeader.biWidth = dst_w
        info.bmiHeader.biHeight = -dst_h  # top-down
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = 0  # BI_RGB

        buf = ctypes.create_string_buffer(dst_w * dst_h * 4)
        got = gdi32.GetDIBits(hdc_dst, bmp_dst, 0, dst_h, buf, ctypes.byref(info), 0)
        if not got:
            raise RuntimeError("GetDIBits returned nothing")
        arr = np.frombuffer(buf.raw, dtype=np.uint8).reshape(dst_h, dst_w, 4)
        return arr[:, :, [2, 1, 0]].copy()  # BGRA -> RGB
    finally:
        if bmp:
            gdi32.DeleteObject(bmp)
        if bmp_dst:
            gdi32.DeleteObject(bmp_dst)
        gdi32.DeleteDC(hdc_mem)
        gdi32.DeleteDC(hdc_dst)
        user32.ReleaseDC(area.hwnd, hdc_window)


class FakeSource:
    """A frame source that draws the HUD synthetically instead of capturing.

    ``--simulate`` uses it, so the whole program - capture loop, hotkeys, the
    reporter, the settings file, the shutdown path - can be exercised on any
    machine, without Windows and without a game.  The frames it returns are the
    same arrays the vision tests are built on, so what runs here is the real
    reader and the real controller; only the pixel source is different.
    """

    def __init__(self, width: int = 1280, height: int = 720, scale: float = 0.5,
                 speed: float = 1.0):
        self.window = (width, height)
        self.scale = max(0.2, min(1.0, scale))
        self.speed = max(0.05, speed)
        self._t0 = None

    # -- the source interface ------------------------------------------------
    def now(self) -> float:
        import time
        return time.time()

    @property
    def viewport(self) -> Tuple[int, int]:
        w, h = self.window
        return max(2, int(round(w * self.scale))), max(2, int(round(h * self.scale)))

    def to_screen(self, nx: float, ny: float) -> Tuple[int, int]:
        w, h = self.window
        return int(round(nx * w)), int(round(ny * h))

    def describe(self) -> str:
        w, h = self.window
        vw, vh = self.viewport
        return f"synthetic {w}x{h} window, captured at {vw}x{vh}"

    def refresh(self):
        return self

    def grab(self):
        from . import simhud
        from .vision import Frame
        import time

        vw, vh = self.viewport
        # A slowly turning scene: the reader is exercised on every background,
        # which is a better smoke test than one fixed picture.
        worlds = ("sea", "night", "bright", "grey")
        world = worlds[int(time.time() / 3.0) % 4]
        img = simhud._blank(vw, vh, world)
        return Frame(arr=img, width=vw, height=vh, timestamp=time.time(),
                     window_width=self.window[0], window_height=self.window[1])


class ScreenSource:
    """A frame source backed by the real game window.

    ``scale`` shrinks the capture before analysis: the HUD is drawn in rem, so
    half resolution still resolves every bar and saves a lot of CPU.  The
    geometry is always computed from the *scaled* size, which keeps the tool
    resolution independent.
    """

    def __init__(self, scale: float = 0.5, method: str = "printwindow", hwnd: Optional[int] = None,
                 titles=("FiveM", "Grand Theft Auto V", "GTAV")):
        self.scale = max(0.2, min(1.0, scale))
        self.method = method
        self._area = None
        self._hwnd = hwnd
        self._titles = titles
        self._black_retries = 0

    # -- window handling ----------------------------------------------------
    def refresh(self) -> ClientArea:
        self._area = client_area(self._hwnd, self._titles)
        self._hwnd = self._area.hwnd
        return self._area

    @property
    def area(self) -> ClientArea:
        return self._area or self.refresh()

    @property
    def viewport(self) -> Tuple[int, int]:
        a = self.area
        return max(2, int(round(a.width * self.scale))), max(2, int(round(a.height * self.scale)))

    def to_screen(self, nx: float, ny: float) -> Tuple[int, int]:
        """Normalised frame coordinate -> absolute screen pixel."""
        a = self.area
        return int(round(a.left + nx * a.width)), int(round(a.top + ny * a.height))

    # -- frames -------------------------------------------------------------
    def grab(self):
        from .vision import Frame
        import time

        a = self.area
        w, h = self.viewport
        arr = _capture_region(a, a.width, a.height, w, h, self.method)
        # A genuinely black frame means the capture method cannot see the D3D
        # surface; switch to the other one and remember that for next time.
        if arr.max() < 8:
            other = "bitblt" if self.method == "printwindow" else "printwindow"
            self._black_retries += 1
            if self._black_retries <= 2:
                self.method = other
                arr = _capture_region(a, a.width, a.height, w, h, other)
        else:
            self._black_retries = 0
        # The HUD is laid out for the *window*, and its rem formula has a
        # floor, so the frame carries the window size alongside the (possibly
        # halved) pixels we actually captured.
        return Frame(arr=arr, width=w, height=h, timestamp=time.time(),
                     window_width=a.width, window_height=a.height)


# ── input injection ─────────────────────────────────────────────────────────
VK_CODES = {
    "e": 0x45, "g": 0x47, "h": 0x48, "f": 0x46, "x": 0x58, "z": 0x5A,
    "w": 0x57, "a": 0x41, "s": 0x53, "d": 0x44, "space": 0x20,
    "lshift": 0xA0, "lctrl": 0xA2, "tab": 0x09, "esc": 0x1B, "enter": 0x0D,
}


class Injector:
    """Absolute mouse movement and key presses, with an off switch.

    ``dry_run`` turns every call into a no-op that still records what *would*
    have happened, which is how the test suite exercises the controller without
    Windows or GTA.
    """

    def __init__(self, dry_run: bool = False, require_foreground: bool = True,
                 target_hwnd: Optional[int] = None):
        self.dry_run = dry_run
        self.require_foreground = require_foreground
        self.target_hwnd = target_hwnd
        self.history = []
        self._sent = 0
        if not dry_run:
            set_dpi_awareness()
            self._user32 = _user32()
            vs = self._user32.GetSystemMetrics
            self._vx = vs(SM_XVIRTUALSCREEN)
            self._vy = vs(SM_YVIRTUALSCREEN)
            self._vw = max(2, vs(SM_CXVIRTUALSCREEN))
            self._vh = max(2, vs(SM_CYVIRTUALSCREEN))
        self.last_cursor: Optional[Tuple[int, int]] = None

    # -- guards -------------------------------------------------------------
    def foreground_ok(self) -> bool:
        if self.dry_run or not self.require_foreground or not self.target_hwnd:
            return True
        fg = self._user32.GetForegroundWindow()
        return int(fg) == int(self.target_hwnd)

    def _record(self, kind: str, **kw) -> None:
        self.history.append((kind, kw))
        if len(self.history) > 4096:
            del self.history[:2048]

    # -- mouse --------------------------------------------------------------
    def move_to(self, x: int, y: int) -> None:
        self._record("move", x=x, y=y)
        if self.dry_run:
            self.last_cursor = (x, y)
            return
        if not self.foreground_ok():
            raise RuntimeError("the game window is not focused; refusing to move the mouse")
        nx = int(round((x - self._vx) * 65535.0 / (self._vw - 1)))
        ny = int(round((y - self._vy) * 65535.0 / (self._vh - 1)))
        dx = self._user32.GetSystemMetrics(75)  # SM_CXICON, unused placeholder
        inp = _INPUT(type=INPUT_MOUSE)
        inp.mi = _MOUSEINPUT(dx=nx, dy=ny, mouseData=0,
                             dwFlags=MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                             time=0, dwExtraInfo=None)
        self._send(inp)
        self.last_cursor = (x, y)

    def move_relative(self, dx: int, dy: int) -> None:
        """Relative motion, in raw mouse units (what the camera reacts to)."""
        self._record("move_rel", dx=dx, dy=dy)
        if self.dry_run:
            if self.last_cursor:
                self.last_cursor = (self.last_cursor[0] + dx, self.last_cursor[1] + dy)
            return
        if not self.foreground_ok():
            raise RuntimeError("the game window is not focused; refusing to move the mouse")
        inp = _INPUT(type=INPUT_MOUSE)
        inp.mi = _MOUSEINPUT(dx=int(dx), dy=int(dy), mouseData=0,
                             dwFlags=MOUSEEVENTF_MOVE, time=0, dwExtraInfo=None)
        self._send(inp)

    def mouse_down(self, button: str = "left") -> None:
        """Press and *hold* a button - the cast power meter charges while the
        left button is held down, so this cannot be a click."""
        self._record("down", button=button)
        if self.dry_run:
            return
        flags = MOUSEEVENTF_LEFTDOWN if button == "left" else MOUSEEVENTF_RIGHTDOWN
        inp = _INPUT(type=INPUT_MOUSE)
        inp.mi = _MOUSEINPUT(dx=0, dy=0, mouseData=0, dwFlags=flags, time=0, dwExtraInfo=None)
        self._send(inp)

    def mouse_up(self, button: str = "left") -> None:
        self._record("up", button=button)
        if self.dry_run:
            return
        flags = MOUSEEVENTF_LEFTUP if button == "left" else MOUSEEVENTF_RIGHTUP
        inp = _INPUT(type=INPUT_MOUSE)
        inp.mi = _MOUSEINPUT(dx=0, dy=0, mouseData=0, dwFlags=flags, time=0, dwExtraInfo=None)
        self._send(inp)

    def click(self, x: Optional[int] = None, y: Optional[int] = None,
              button: str = "left") -> None:
        self._record("click", x=x, y=y, button=button)
        if self.dry_run:
            return
        if x is not None and y is not None:
            self.move_to(x, y)
        down = MOUSEEVENTF_LEFTDOWN if button == "left" else MOUSEEVENTF_RIGHTDOWN
        up = MOUSEEVENTF_LEFTUP if button == "left" else MOUSEEVENTF_RIGHTUP
        for flags in (down, up):
            inp = _INPUT(type=INPUT_MOUSE)
            inp.mi = _MOUSEINPUT(dx=0, dy=0, mouseData=0, dwFlags=flags, time=0, dwExtraInfo=None)
            self._send(inp)

    # -- keyboard -----------------------------------------------------------
    def key(self, name: str, hold_ms: int = 40) -> None:
        import time

        self._record("key", name=name, hold_ms=hold_ms)
        if self.dry_run:
            return
        vk = VK_CODES.get(name.lower())
        if vk is None:
            raise ValueError(f"unknown key {name!r}; add it to VK_CODES")
        for flags in (0, KEYEVENTF_KEYUP):
            inp = _INPUT(type=INPUT_KEYBOARD)
            inp.ki = _KEYBDINPUT(wVk=vk, wScan=0, dwFlags=flags, time=0, dwExtraInfo=None)
            self._send(inp)
            time.sleep(hold_ms / 1000.0)

    def key_down(self, name: str) -> None:
        self._record("key_down", name=name)
        if self.dry_run:
            return
        vk = VK_CODES[name.lower()]
        inp = _INPUT(type=INPUT_KEYBOARD)
        inp.ki = _KEYBDINPUT(wVk=vk, wScan=0, dwFlags=0, time=0, dwExtraInfo=None)
        self._send(inp)

    def key_up(self, name: str) -> None:
        self._record("key_up", name=name)
        if self.dry_run:
            return
        vk = VK_CODES[name.lower()]
        inp = _INPUT(type=INPUT_KEYBOARD)
        inp.ki = _KEYBDINPUT(wVk=vk, wScan=0, dwFlags=KEYEVENTF_KEYUP, time=0, dwExtraInfo=None)
        self._send(inp)

    def _send(self, inp: "_INPUT") -> None:
        if not self.foreground_ok():
            raise RuntimeError("the game window is not focused; refusing to send input")
        self._user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(_INPUT))
        self._sent += 1


class NullInjector(Injector):
    """Injector that records and does nothing - used by the simulator."""

    def __init__(self):
        super().__init__(dry_run=True)


# Virtual-key codes for the global hotkeys, polled from the main loop so no
# message pump is needed.
VK_F7 = 0x76
VK_F8 = 0x77
VK_F9 = 0x78
VK_F10 = 0x79
VK_F11 = 0x7A
VK_F12 = 0x7B
VK_END = 0x23


class HotkeyWatcher:
    """Edge-triggered key polling.

    ``GetAsyncKeyState`` returns the current state for every key regardless of
    which window has focus, which is what a panic button needs.  Each call is
    edge-detected so one press is one event.
    """

    def __init__(self, keys: Optional[dict] = None, dry_run: bool = False):
        self.keys = keys or {"start": VK_F9, "stop": VK_F10, "pause": VK_F11}
        self.dry_run = dry_run
        self._down = {name: False for name in self.keys}
        if not dry_run:
            self._user32 = _user32()
            self._user32.GetAsyncKeyState.restype = ctypes.c_short

    def poll(self) -> list:
        """Return the names of keys that were pressed since the last poll."""
        if self.dry_run:
            return []
        pressed = []
        for name, vk in self.keys.items():
            state = self._user32.GetAsyncKeyState(vk) & 0x8000
            is_down = bool(state)
            if is_down and not self._down[name]:
                pressed.append(name)
            self._down[name] = is_down
        return pressed
