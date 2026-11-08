"""Console output and the debug-image writer.

Kept separate from :mod:`fishbot.run` so that everything here can be imported
(and tested) on any platform: the runner itself only works on Windows, but the
text the player reads and the calibration snapshot are plain Python.
"""

from __future__ import annotations

import struct
import time
import zlib
from typing import Optional

_COLOURS = {"info": "", "warn": "\033[33m", "error": "\033[31m",
            "success": "\033[32m", "debug": "\033[90m"}
_RESET = "\033[0m"


class Reporter:
    """Prints events, and beeps when the tool needs a human."""

    def __init__(self, alert: bool = True, verbose: bool = False, stream=None):
        self.alert = alert
        self.verbose = verbose
        self.stream = stream
        self.beeps = 0

    # `bot` calls this with (level, message)
    def __call__(self, level: str, msg: str) -> None:
        colour = _COLOURS.get(level, "")
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        if colour:
            line = f"{colour}{line}{_RESET}"
        print(line, file=self.stream, flush=True)
        if self.alert and level in ("error", "warn"):
            self.beep()

    def beep(self) -> None:
        self.beeps += 1
        try:
            import winsound
            for freq in (880, 660, 880):
                winsound.Beep(freq, 180)
        except Exception:
            # console bell: no dependency, works everywhere
            print("\a", end="", file=self.stream, flush=True)

    def say(self, msg: str = "") -> None:
        print(msg, file=self.stream, flush=True)


def write_png(path: str, arr) -> None:
    """Write an ``H x W x 3`` uint8 array as a PNG.

    Deliberately dependency-free: the calibration snapshot must work on a
    machine with nothing but Python installed, and a debug image is not worth a
    Pillow requirement.
    """
    h, w = int(arr.shape[0]), int(arr.shape[1])
    raw = bytearray()
    for row in arr:
        raw.append(0)  # filter type 0 (none)
        raw.extend(memoryview(row.astype("uint8")).tobytes())

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def outline(img, rect, rgb, firm: bool = False) -> None:
    """Draw a box on a uint8 RGB array, in place (2 px when ``firm``)."""
    h, w = img.shape[0], img.shape[1]
    left, top, bw, bh = rect.to_px(w, h)
    colour = tuple(int(c) for c in rgb)
    for t in range(2 if firm else 1):
        img[min(h - 1, top + t), left:left + bw] = colour
        img[min(h - 1, top + bh - 1 - t), left:left + bw] = colour
        img[top:top + bh, min(w - 1, left + t)] = colour
        img[top:top + bh, min(w - 1, left + bw - 1 - t)] = colour


def pace(started: float, hz: float, sleep=None) -> None:
    """Sleep out the rest of one sample period (best effort, never negative)."""
    budget = 1.0 / max(1.0, hz)
    spent = time.time() - started
    if spent < budget:
        (sleep or time.sleep)(budget - spent)
