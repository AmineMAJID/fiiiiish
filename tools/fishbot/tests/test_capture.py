"""The capture path, driven through a fake user32/gdi32.

    python -m tests.test_capture

Screen capture is the one part of the tool that cannot be tested on a machine
without Windows - unless the two DLLs are stood in for.  They are simple enough
to fake faithfully (create a bitmap, select it into a DC, ask GDI to fill it)
that doing so exercises everything except the Win32 calls themselves: the
sequence, the sizes, the BGRA -> RGB conversion, the black-frame fallback, and
the handle bookkeeping.  That bookkeeping is the point: a leaked DC or bitmap is
invisible until the tool has been running for an hour, and then the capture
simply stops working.
"""

from __future__ import annotations

import ctypes
import sys
from typing import List

import numpy as np

from fishbot import winapi

failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
    if not ok:
        failures.append(f"{name} {detail}")


def make_area(width: int = 1920, height: int = 1080, left: int = 0) -> winapi.ClientArea:
    return winapi.ClientArea(hwnd=1, title="FiveM", left=left, top=0,
                             width=width, height=height,
                             monitor_left=0, monitor_top=0,
                             monitor_width=width, monitor_height=height)


class FakeGdi:
    """Records what the capture path asks GDI to do, and keeps score of handles."""

    def __init__(self, fill: int = 40, printwindow_ok: bool = True,
                 bitblt_ok: bool = True):
        self.calls: List[object] = []
        self.fill = fill
        self.printwindow_ok = printwindow_ok
        self.bitblt_ok = bitblt_ok
        self.bitmaps_created = 0
        self.bitmaps_deleted = 0
        self.dcs = 0

    # devices and objects
    def CreateCompatibleDC(self, hdc):
        self.dcs += 1
        self.calls.append("CreateCompatibleDC")
        return 1000 + self.dcs

    def CreateCompatibleBitmap(self, hdc, w, h):
        self.bitmaps_created += 1
        self.calls.append(("Bitmap", w, h))
        return 5000 + self.bitmaps_created

    def SelectObject(self, dc, obj):
        self.calls.append("SelectObject")
        return 1

    def DeleteObject(self, obj):
        self.bitmaps_deleted += 1
        self.calls.append("DeleteObject")
        return 1

    def DeleteDC(self, dc):
        self.dcs -= 1
        self.calls.append("DeleteDC")
        return 1

    # drawing
    def BitBlt(self, *args):
        self.calls.append(("BitBlt", args[2], args[3], args[4], args[5]))
        return 1 if self.bitblt_ok else 0

    def PrintWindow(self, *args):
        self.calls.append("PrintWindow")
        return 1 if self.printwindow_ok else 0

    def SetStretchBltMode(self, dc, mode):
        self.calls.append(("StretchMode", mode))
        return 1

    def StretchBlt(self, dst, x, y, w, h, src, sx, sy, sw, sh, rop):
        self.calls.append(("Stretch", w, h, sw, sh))
        return 1

    def GetDIBits(self, dc, bmp, start, rows, buf, info, flags):
        self.calls.append(("GetDIBits", rows))
        ctypes.memset(buf, self.fill, rows * 4 * 2 * 3)
        return rows


class FakeUser:
    def __init__(self, printwindow_ok: bool = True):
        self.released = False
        self.printwindow_ok = printwindow_ok

    def GetDC(self, hwnd):
        return 42

    def ReleaseDC(self, hwnd, hdc):
        self.released = True
        return 1

    def PrintWindow(self, *args):
        return 1 if self.printwindow_ok else 0


def install(gdi: FakeGdi, user: FakeUser) -> None:
    winapi._gdi32 = lambda: gdi
    winapi._user32 = lambda: user


def test_printwindow_capture() -> None:
    print("\n[PrintWindow: full-size render, scaled down, nothing leaked]")
    gdi, user = FakeGdi(fill=40), FakeUser()
    install(gdi, user)
    area = make_area()
    arr = winapi._capture_region(area, area.width, area.height, 960, 540, "printwindow")

    check("the frame is the capture size", arr.shape == (540, 960, 3), f"{arr.shape}")
    check("it is RGB uint8", arr.dtype == np.uint8 and arr.ndim == 3, f"{arr.dtype}")
    # `windows.PrintWindow` is a user32 call, so the ask lands on the fake user32
    check("PrintWindow is asked through user32, not GDI",
          gdi.calls.count("PrintWindow") == 0 and gdi.calls.count("BitBlt") == 0,
          f"{gdi.calls[:5]}")
    sizes = [c for c in gdi.calls if isinstance(c, tuple) and c[0] == "Bitmap"]
    check("the render target is the window's size", sizes[0][1:] == (1920, 1080), f"{sizes[0]}")
    check("the capture target is the scaled size", sizes[-1][1:] == (960, 540), f"{sizes[-1]}")
    stretch = [c for c in gdi.calls if isinstance(c, tuple) and c[0] == "Stretch"][0]
    check("the stretch goes from the full render to the capture",
          stretch[1:] == (960, 540, 1920, 1080), f"{stretch}")
    check("HALFTONE is set before stretching",
          ("StretchMode", 3) in gdi.calls, "")
    check("every bitmap was released", gdi.bitmaps_created == gdi.bitmaps_deleted,
          f"{gdi.bitmaps_created}/{gdi.bitmaps_deleted}")
    check("every DC was released", gdi.dcs == 0, f"{gdi.dcs} left")
    check("the window DC was released", user.released, "")


def test_channel_order() -> None:
    print("\n[BGRA from GDI becomes RGB: a red pixel must not come out blue]")
    gdi, user = FakeGdi(fill=0), FakeUser()
    install(gdi, user)

    # 0x40 is not enough to tell channels apart; make GetDIBits write BGRA.
    def GetDIBits(dc, bmp, start, rows, buf, info, flags):
        raw = bytes([10, 20, 240, 255]) * (rows * 2 * 3)  # B=10, G=20, R=240
        ctypes.memmove(buf, raw, min(len(raw), rows * 4 * 2 * 3))
        return rows

    gdi.GetDIBits = GetDIBits
    area = make_area(320, 200)
    arr = winapi._capture_region(area, 320, 200, 160, 100, "bitblt")
    r, g, b = (int(arr[0, 0, i]) for i in range(3))
    check("channels come out as R,G,B", (r, g, b) == (240, 20, 10), f"{(r, g, b)}")


def test_bitblt_fallback() -> None:
    print("\n[BitBlt: used when PrintWindow refuses, and smaller intermediate]")
    gdi, user = FakeGdi(fill=60), FakeUser(printwindow_ok=False)
    install(gdi, user)
    area = make_area()
    arr = winapi._capture_region(area, area.width, area.height, 480, 270, "bitblt")
    check("the frame is the capture size", arr.shape == (270, 480, 3), f"{arr.shape}")
    check("BitBlt was used", any(isinstance(c, tuple) and c[0] == "BitBlt" for c in gdi.calls), "")
    sizes = [c for c in gdi.calls if isinstance(c, tuple) and c[0] == "Bitmap"]
    check("the intermediate is the whole window (PrintWindow renders all of it)",
          sizes[0][1:] == (1920, 1080), f"{sizes[0]}")
    check("nothing leaked", gdi.bitmaps_created == gdi.bitmaps_deleted and gdi.dcs == 0,
          f"{gdi.bitmaps_created}/{gdi.bitmaps_deleted}, {gdi.dcs} DCs")


def test_failure_path() -> None:
    print("\n[both methods failing raises, and still releases everything]")
    gdi, user = FakeGdi(printwindow_ok=False, bitblt_ok=False), FakeUser()
    install(gdi, user)
    area = make_area()
    raised = False
    try:
        # A black *result* is handled by ScreenSource; here both methods must
        # report failure.  PrintWindow is called through user32, so the fake GDI
        # cannot fail it - fail it on the user32 side.
        user.printwindow_ok = False
        winapi._capture_region(area, area.width, area.height, 320, 180, "printwindow")
    except RuntimeError as exc:
        raised = "both" in str(exc)
    check("it raises rather than returning a black frame", raised, "")
    check("nothing leaked on the way out",
          gdi.bitmaps_created == gdi.bitmaps_deleted and gdi.dcs == 0,
          f"{gdi.bitmaps_created}/{gdi.bitmaps_deleted}, {gdi.dcs} DCs")


def test_screen_source_switch() -> None:
    print("\n[ScreenSource: a black capture switches method and remembers]")
    gdi, user = FakeGdi(fill=0), FakeUser()
    install(gdi, user)
    source = winapi.ScreenSource(scale=0.5, method="printwindow", hwnd=1)
    source._area = make_area()
    frame = source.grab()
    check("the frame is the window's size, half captured",
          frame.width == 960 and frame.height == 540, f"{frame.width}x{frame.height}")
    check("the frame knows the window it came from",
          frame.viewport == (1920, 1080), f"{frame.viewport}")
    check("it swapped to the other method", source.method == "bitblt", source.method)
    check("the readout says how it is captured", "bitblt" in source.describe(),
          source.describe())


def main() -> int:
    if not winapi.IS_WINDOWS:
        print("(no Windows here - the DLLs are faked, which is the point)")
    test_printwindow_capture()
    test_channel_order()
    test_bitblt_fallback()
    test_failure_path()
    test_screen_source_switch()
    print()
    if failures:
        print(f"{len(failures)} FAILURES")
        for f in failures:
            print("  -", f)
        return 1
    print("all capture checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
