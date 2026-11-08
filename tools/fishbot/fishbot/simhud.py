"""A synthetic renderer for the qs-fisher HUD.

This draws the parts of the interface the tool reads, at any resolution, using
the same colours and the same rem-based geometry as the shipped stylesheet.  It
exists so the vision code can be tested against ground truth without launching
GTA: the tests render a frame with a known tension, progress, cue and ring
value, and then assert the vision functions recover those numbers.

It is **test and development code only** - ``fishbot.run`` never imports it, so
none of it needs to run without numpy.

Each renderer takes the *canvas* size (how many pixels to draw) and, optionally,
``fit`` - the size of the game window the HUD was laid out for.  The two differ
when a test captures at half resolution: the stylesheet's ``rem`` has a pixel
floor, so half-resolution capture is not a pure rescale of the HUD boxes, and
the layout has to follow the window while the pixels follow the canvas.
"""

from __future__ import annotations

import math
from typing import Optional, Tuple

import numpy as np  # this module only ever runs where numpy is installed

from .geometry import (bite_layout, cast_layout, catch_modal_layout, depth_layout,
                       fight_layout, notify_layout, rem)

# The HUD font stack never renders these; the renderer uses a cheap box-drawing
# stand-in, which is fine because the detectors only look at colour and coverage.
PANEL = (15, 23, 42)          # #0f172b gradient start
PANEL_2 = (29, 41, 61)        # #1d293d gradient end
TRACK = (33, 43, 62)          # #ffffff12 over the panel
CUE_ON = (125, 211, 252)
CUE_OFF = (30, 41, 59)
PROGRESS = (96, 165, 250)
GREEN = (74, 222, 128)
AMBER = (245, 158, 11)
RED = (239, 68, 68)
TEXT = (226, 232, 240)
DIM = (100, 116, 139)
SLATE = (51, 65, 85)


def _blank(fw: int, fh: int, world: str = "sea") -> "np.ndarray":
    """A dark-ish frame; ``world`` picks a few plausible game backgrounds."""
    img = np.zeros((fh, fw, 3), dtype=np.uint8)
    yy = np.linspace(0, 1, fh, dtype=np.float32)[:, None]
    if world == "sea":
        top = np.array([70, 110, 150], dtype=np.float32)
        bot = np.array([30, 60, 85], dtype=np.float32)
    elif world == "night":
        top = np.array([12, 16, 28], dtype=np.float32)
        bot = np.array([6, 8, 14], dtype=np.float32)
    elif world == "bright":
        top = np.array([190, 205, 215], dtype=np.float32)
        bot = np.array([140, 160, 175], dtype=np.float32)
    else:
        top = np.array([90, 90, 90], dtype=np.float32)
        bot = np.array([40, 40, 40], dtype=np.float32)
    row = (top * (1 - yy) + bot * yy).astype(np.uint8)
    img[:, :, :] = row[:, None, :]
    return img


def _fit(fw: int, fh: int, fit: Optional[Tuple[int, int]]) -> Tuple[int, int]:
    """Layout reference size: the window, when the canvas is a scaled capture."""
    return (fit[0], fit[1]) if fit else (fw, fh)


def _fill(img, r, color) -> None:
    h, w = img.shape[:2]
    x1, y1 = int(r.x * w), int(r.y * h)
    x2, y2 = int(r.x2 * w), int(r.y2 * h)
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(w, x2), min(h, y2)
    if x2 > x1 and y2 > y1:
        img[y1:y2, x1:x2] = color


def _disc(img, r, frac: float, color) -> None:
    """A filled circle of radius ``frac`` of ``r``'s width, centred in it."""
    h, w = img.shape[:2]
    cx, cy = r.cx * w, r.cy * h
    rad = frac * r.w * w
    x1, x2 = max(0, int(cx - rad)), min(w, int(cx + rad) + 1)
    y1, y2 = max(0, int(cy - rad)), min(h, int(cy + rad) + 1)
    if x2 <= x1 or y2 <= y1:
        return
    yy, xx = np.mgrid[y1:y2, x1:x2]
    mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= rad * rad
    img[y1:y2, x1:x2][mask] = color


def _round_panel(img, r, c1=PANEL, c2=PANEL_2, border=(51, 65, 85)) -> None:
    h, w = img.shape[:2]
    x1, y1 = int(r.x * w), int(r.y * h)
    x2, y2 = int(r.x2 * w), int(r.y2 * h)
    if x2 <= x1 or y2 <= y1:
        return
    grad = np.linspace(0, 1, x2 - x1, dtype=np.float32)[None, :, None]
    block = (np.array(c1, dtype=np.float32) * (1 - grad)
             + np.array(c2, dtype=np.float32) * grad).astype(np.uint8)
    img[y1:y2, x1:x2] = block
    # The real card has a 0.0625rem border in a translucent slate; at half
    # capture resolution of a 720p window that border is barely one pixel, so it
    # is drawn *only* when there is room for it.  A bright every-other-card
    # outline was enough to make the band detectors fire on an otherwise plain
    # scene at small sizes, which is a rendering artefact, not HUD behaviour.
    edge = max(1, (y2 - y1) // 40)
    if edge < 2:
        return
    img[y1:y1 + edge, x1:x2] = (59, 130, 246)


def render_fight(fw: int, fh: int, tension: float, progress: float,
                 side: Optional[str], world: str = "sea", dim: float = 1.0,
                 ring: Optional[float] = None,
                 fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    """Draw the reel mini-game as the NUI would, with known values."""
    img = _blank(fw, fh, world)
    lay = fight_layout(*_fit(fw, fh, fit))

    _round_panel(img, lay.hud.union(lay.panel) if lay.hud.y < lay.panel.y else lay.panel)

    # cue chevrons
    for name, box in (("left", lay.cue_left), ("right", lay.cue_right)):
        lit = (side == name)
        if lit:  # glow goes behind the glyph, like the drop-shadow in the CSS
            _fill(img, box.grow(0.12, 0.35), tuple(int(c * 0.45) for c in CUE_ON))
        _fill(img, box, CUE_ON if lit else CUE_OFF)
        # the chevrons themselves: three bars with gaps, as the icon renders
        bars = 3
        for i in range(bars):
            bh = box.h * 0.55
            by = box.y + (box.h - bh) / 2.0
            bw = box.w / (bars * 1.6)
            bx = box.x + box.w * (0.12 + 0.31 * i)
            _fill(img, type(box)(bx, by, bw, bh), CUE_ON if lit else CUE_OFF)

    # the two meter tracks
    _fill(img, lay.tension_track.grow(0.0, 0.15), TRACK)
    _fill(img, lay.progress_track.grow(0.0, 0.15), TRACK)

    def bar(track, value, color):
        v = max(0.0, min(1.0, value))
        _fill(img, type(track)(track.x, track.y, track.w * v, track.h), color)

    bar(lay.progress_track, progress, PROGRESS)
    colour = RED if tension >= 0.82 else (AMBER if tension >= 0.60 else GREEN)
    bar(lay.tension_track, tension, colour)

    if ring is not None:
        _draw_ring(img, *_fit(fw, fh, fit), ring)
    if dim < 1.0:
        img = (img.astype(np.float32) * dim).astype(np.uint8)
    return img


def _draw_ring(img, fw: int, fh: int, remaining: float) -> None:
    """The bite HUD's SVG countdown: a stroke of 5 units on a 100-unit viewBox."""
    bh, bw = img.shape[:2]
    lay = bite_layout(fw, fh)
    r = lay["ring"]
    x1, y1 = int(r.x * bw), int(r.y * bh)
    x2, y2 = int(r.x2 * bw), int(r.y2 * bh)
    side = min(x2 - x1, y2 - y1)
    if side < 8:
        return
    cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0
    radius = 0.46 * side
    thickness = max(1, int(round(0.05 * side)))
    colour = RED if remaining < 0.35 else (56, 189, 248)
    steps = max(120, int(4 * math.pi * radius))
    # The SVG dash is drawn along the *circle*; if it stops at a pixel boundary
    # the stroke's round cap still reaches across the gap, so a rendered arc
    # always covers a little more than its nominal fraction.  Leaving one step
    # clear models that, and lets the reader land inside its tolerance.
    span = int(steps * remaining)
    if remaining < 0.995:
        span = max(0, span - 1)
    for i in range(span):
        ang = -math.pi / 2 + 2 * math.pi * i / steps
        for t in range(thickness):
            rr = radius - thickness / 2.0 + t
            x = int(cx + rr * math.cos(ang))
            y = int(cy + rr * math.sin(ang))
            if x1 <= x < x2 and y1 <= y < y2:
                img[y, x] = colour


def render_bite(fw: int, fh: int, remaining: float, world: str = "sea",
                buoys: bool = True,
                fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    img = _blank(fw, fh, world)
    lw, lh = _fit(fw, fh, fit)
    if buoys:
        lay = bite_layout(lw, lh)
        _disc(img, lay["float"], 0.30, (26, 74, 108))   # the soft radial glow
        _disc(img, lay["float"], 0.20, (240, 240, 245))  # the buoy
    _draw_ring(img, lw, lh, remaining)
    return img


def render_cast(fw: int, fh: int, power: float, world: str = "sea",
                fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    img = _blank(fw, fh, world)
    lay = cast_layout(*_fit(fw, fh, fit))
    _round_panel(img, lay["card"])
    # the tick gutter and the labels are text, drawn as dim blocks
    track = lay["track"]
    _fill(img, track.grow(0.6, 0.0), (2, 8, 18))
    colour = (56, 189, 248) if 0.35 <= power < 0.7 else (
        (74, 222, 128) if power >= 0.7 else (100, 116, 139))
    # `_fill` truncates, so for thin bars draw one pixel wider and use pixel
    # bounds directly; otherwise a 28 px track can land off by a pixel at 4K.
    h = track.h * max(0.0, min(1.0, power))
    top = min(1.0, track.y2 - h)
    _fill(img, type(track)(track.x, top, track.w, max(track.h / 400.0, track.y2 - top)),
          colour)
    for i in range(5):  # the 0/25/50/75/100 ticks
        y = track.y + track.h * (1 - i / 4.0) - 0.004
        _fill(img, type(track)(track.x - 0.02, y, 0.015, 0.006), DIM)
    return img


def render_catch_modal(fw: int, fh: int, world: str = "sea",
                       fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    img = _blank(fw, fh, world)
    lay = catch_modal_layout(*_fit(fw, fh, fit))
    _round_panel(img, lay["modal"], c1=(15, 23, 43), c2=(29, 41, 61))
    for key in ("keep", "release"):
        _fill(img, lay[key], (29, 41, 61))
        # icon + upper-case label + note, as three blocks of bright text
        box = lay[key]
        _fill(img, type(box)(box.x + box.w * 0.30, box.y + box.h * 0.18,
                             box.w * 0.40, box.h * 0.18), (92, 186, 240))
        _fill(img, type(box)(box.x + box.w * 0.16, box.y + box.h * 0.45,
                             box.w * 0.68, box.h * 0.16), TEXT)
        _fill(img, type(box)(box.x + box.w * 0.22, box.y + box.h * 0.70,
                             box.w * 0.56, box.h * 0.10), DIM)
    return img


def render_depth_card(fw: int, fh: int, can_cast: bool, world: str = "sea",
                      fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    """The bottom-right depth card and its action row.

    ``can_cast`` draws the action key green ("Start fishing"); otherwise the row
    is what a blocked player sees - a slate key and the reason.
    """
    img = _blank(fw, fh, world)
    lay = depth_layout(*_fit(fw, fh, fit))
    card = lay["card"]
    _fill(img, card, (15, 23, 43))
    _fill(img, type(card)(card.x, card.y, card.w, max(0.004, card.h * 0.04)), SLATE)
    head = lay["head"]
    # icon plate + the depth number, then the band label underneath: text, not
    # a filled panel.  (How much of the card is bright is what tells a reader the
    # card is there at all, so the renderer must not flood it.)
    _fill(img, type(head)(head.x + head.w * 0.03, head.y + head.h * 0.2,
                          head.w * 0.11, head.h * 0.5), (56, 189, 248))
    _fill(img, type(head)(head.x + head.w * 0.18, head.y + head.h * 0.22,
                          head.w * 0.22, head.h * 0.24), (241, 245, 249))
    _fill(img, type(head)(head.x + head.w * 0.18, head.y + head.h * 0.58,
                          head.w * 0.34, head.h * 0.14), (100, 116, 139))
    _fill(img, lay["ladder"], (51, 65, 85))                      # the depth ladder
    action = lay["action"]
    _fill(img, action, (15, 23, 43))
    _fill(img, type(action)(action.x, action.y, action.w, max(0.004, action.h * 0.06)),
          GREEN if can_cast else (71, 85, 105))
    _fill(img, lay["key"], GREEN if can_cast else SLATE)
    text = (203, 213, 225)
    _fill(img, type(action)(action.x + action.w * 0.22, action.y + action.h * 0.34,
                            action.w * (0.5 if can_cast else 0.66), action.h * 0.3), text)
    return img


def render_error_toast(fw: int, fh: int, world: str = "sea",
                       fit: Optional[Tuple[int, int]] = None) -> "np.ndarray":
    img = _blank(fw, fh, world)
    lay = notify_layout(*_fit(fw, fh, fit))
    box = lay["boxes"][0]  # type: ignore[index]
    _round_panel(img, box, c1=(15, 23, 43), c2=(29, 41, 61))
    _fill(img, type(box)(box.x, box.y, box.w, box.h * 0.05), RED)
    _fill(img, type(box)(box.x + box.w * 0.06, box.y + box.h * 0.3,
                         box.w * 0.12, box.h * 0.4), RED)
    _fill(img, type(box)(box.x + box.w * 0.24, box.y + box.h * 0.4,
                         box.w * 0.6, box.h * 0.16), TEXT)
    return img
