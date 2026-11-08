"""HUD geometry, derived from the resource's own stylesheet.

Every number here was measured from ``web/build/assets/index.css``, so the tool
finds the resource's HUD at any resolution and in any window mode without any
per-resolution tuning.  Positions are normalised (0..1) except the ``rem``
helper, which converts the HUD's own CSS unit to pixels.

How the HUD sizes itself
------------------------
``html { font-size: clamp(8px, min(100vw / 120, 100vh / 67.5), 32px) }``

so the whole interface scales with the *smaller* of the two axes.  Describing a
box in rem makes it resolution independent by construction; that is the whole
trick behind supporting windowed, borderless and fullscreen without asking.

The reel mini-game, in its own units (rem)
------------------------------------------
wrap   : fixed, left 50 %, bottom 8 %, translate(-50 %), width 38.75, max 92vw
cueRow : flex row, gap 1; chevrons 2.5, centre label min-width 11.875
panel  : grid 3.75 | 1fr | 4.875, gaps .875, padding 1
meters : two tracks .5 tall, heads .75 tall with .25 bottom margin
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, List, Tuple

# ── the HUD's own unit ───────────────────────────────────────────────────────
FONT_CLAMP_MIN = 8.0
FONT_CLAMP_MAX = 32.0
FONT_VW_DIV = 120.0
FONT_VH_DIV = 67.5


def rem(fw: int, fh: int) -> float:
    """Pixel size of one ``rem`` for a viewport of ``fw`` x ``fh``."""
    return max(FONT_CLAMP_MIN, min(min(fw / FONT_VW_DIV, fh / FONT_VH_DIV), FONT_CLAMP_MAX))


# ── rectangles ───────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Rect:
    x: float
    y: float
    w: float
    h: float

    @property
    def x2(self) -> float:
        return self.x + self.w

    @property
    def y2(self) -> float:
        return self.y + self.h

    @property
    def cx(self) -> float:
        return self.x + self.w / 2.0

    @property
    def cy(self) -> float:
        return self.y + self.h / 2.0

    def contains(self, nx: float, ny: float) -> bool:
        """True when a *normalised* point falls inside the box."""
        return self.x <= nx <= self.x2 and self.y <= ny <= self.y2

    def to_px(self, fw: int, fh: int) -> Tuple[int, int, int, int]:
        """``left, top, width, height`` in pixels, clamped to the screen."""
        left = int(round(self.x * fw))
        top = int(round(self.y * fh))
        right = int(round(self.x2 * fw))
        bottom = int(round(self.y2 * fh))
        left = max(0, min(left, fw - 2))
        top = max(0, min(top, fh - 2))
        right = max(left + 1, min(right, fw))
        bottom = max(top + 1, min(bottom, fh))
        return left, top, right - left, bottom - top

    def inset(self, fx: float, fy: float) -> "Rect":
        return Rect(self.x + self.w * fx, self.y + self.h * fy,
                    self.w * (1 - 2 * fx), self.h * (1 - 2 * fy))

    def grow(self, fx: float, fy: float) -> "Rect":
        return Rect(self.x - self.w * fx, self.y - self.h * fy,
                    self.w * (1 + 2 * fx), self.h * (1 + 2 * fy))

    def union(self, other: "Rect") -> "Rect":
        x = min(self.x, other.x)
        y = min(self.y, other.y)
        return Rect(x, y, max(self.x2, other.x2) - x, max(self.y2, other.y2) - y)


def rect(x: float, y: float, w: float, h: float) -> Rect:
    return Rect(x, y, w, h)


def centered(w: float, h: float, cx: float, cy: float, fw: int, fh: int) -> Rect:
    return Rect((cx - w / 2.0) / fw, (cy - h / 2.0) / fh, w / fw, h / fh)


# ── the reel mini-game ───────────────────────────────────────────────────────
@dataclass(frozen=True)
class FightLayout:
    """Screen boxes of the reel mini-game, all as fractions of the viewport."""

    hud: Rect
    cue_row: Rect
    cue_left: Rect
    cue_right: Rect
    panel: Rect
    tension_track: Rect
    progress_track: Rect
    lure: Rect

    def describe(self) -> str:
        return (f"hud x={self.hud.x:.3f} y={self.hud.y:.3f} "
                f"w={self.hud.w:.3f} h={self.hud.h:.3f}; "
                f"tension bar {self.tension_track.w * 100:.1f}% wide")


# panel internals, in rem
_PAD = 1.0
_LURE = 3.5
_DISTANCE = 4.875
_GAP = 0.875
_BAR_H = 0.5
_HEAD_H = 0.75
_HEAD_MARGIN = 0.25
_METER_GAP = 0.5625
_CUE = 2.5
_CUE_GAP = 1.0
_CUE_LABEL = 11.875
_WRAP_W = 38.75
_WRAP_BOTTOM = 0.08
_WRAP_GAP = 0.625


def _panel_height(u: float) -> float:
    meter = _HEAD_H + _HEAD_MARGIN + _BAR_H
    return 2 * _PAD * u + 2 * meter * u + _METER_GAP * u


def _hud_height(u: float) -> float:
    return _CUE * u + _WRAP_GAP * u + _panel_height(u)


def fight_layout(fw: int, fh: int) -> FightLayout:
    u = rem(fw, fh)
    width = min(_WRAP_W * u, 0.92 * fw)
    hud_h = _hud_height(u)
    hud_left = fw / 2.0 - width / 2.0
    hud_top = fh - _WRAP_BOTTOM * fh - hud_h

    hud = rect(hud_left / fw, hud_top / fh, width / fw, hud_h / fh)

    # cue row: chevron | label | chevron, centred as a block
    cue_w = 3 * _CUE * u
    cue_block = 2 * cue_w + 2 * _CUE_GAP * u + _CUE_LABEL * u
    block_left = fw / 2.0 - cue_block / 2.0
    left_cx = block_left + cue_w / 2.0
    right_cx = block_left + cue_block - cue_w / 2.0
    cue_cy = hud_top + _CUE * u / 2.0
    cue_left = centered(cue_w, _CUE * u, left_cx, cue_cy, fw, fh)
    cue_right = centered(cue_w, _CUE * u, right_cx, cue_cy, fw, fh)
    cue_row = rect(hud.x, hud.y, hud.w, (_CUE * u) / fh)

    # panel and its meter column
    panel_top = hud_top + _CUE * u + _WRAP_GAP * u
    panel = rect(hud_left / fw, panel_top / fh, width / fw, _panel_height(u) / fh)
    meters_w = width - 2 * _PAD * u - _LURE * u - _DISTANCE * u - 2 * _GAP * u
    meters_x = hud_left + _PAD * u + _LURE * u + _GAP * u

    progress_top = panel_top + _PAD * u
    progress_bar_y = progress_top + (_HEAD_H + _HEAD_MARGIN) * u + _BAR_H * u / 2.0
    tension_top = progress_top + (_HEAD_H + _HEAD_MARGIN + _BAR_H) * u + _METER_GAP * u
    tension_bar_y = tension_top + (_HEAD_H + _HEAD_MARGIN) * u + _BAR_H * u / 2.0

    progress_track = rect(meters_x / fw, (progress_bar_y - _BAR_H * u / 2.0) / fh,
                          meters_w / fw, _BAR_H * u / fh)
    tension_track = rect(meters_x / fw, (tension_bar_y - _BAR_H * u / 2.0) / fh,
                         meters_w / fw, _BAR_H * u / fh)
    lure = centered(_LURE * u, _LURE * u, hud_left + _PAD * u + _LURE * u / 2.0,
                    panel_top + _PAD * u + _LURE * u / 2.0, fw, fh)

    return FightLayout(hud=hud, cue_row=cue_row, cue_left=cue_left, cue_right=cue_right,
                       panel=panel, tension_track=tension_track,
                       progress_track=progress_track, lure=lure)


# ── the bite HUD (waiting buoy / countdown ring) ─────────────────────────────
_BITE_FLOAT = 8.25
_BITE_BOTTOM = 0.025


def bite_layout(fw: int, fh: int) -> Dict[str, Rect]:
    """``_wrap_1k7mm``: fixed, left 50 %, bottom 2.5vh, translate(-50 %).

    The float is an 8.25rem square holding the buoy, the glow and the two
    ripples; the SVG countdown ring is the full square, rotated -90deg.
    """
    u = rem(fw, fh)
    side = _BITE_FLOAT * u
    top = fh - _BITE_BOTTOM * fh - side
    float_box = rect((fw - side) / 2.0 / fw, top / fh, side / fw, side / fh)
    ring = float_box
    return {
        "float": float_box,
        "ring": ring,
        "buoy": ring.inset(0.30, 0.30),
        "glow": ring.inset(0.06, 0.06),
    }


# ── the cast power card ──────────────────────────────────────────────────────
_CAST_W = 9.875
_CAST_PAD = 0.8125
_CAST_HEAD = 0.6875
_CAST_COLUMN = 12.5
_CAST_TICKS = 1.25
_CAST_TRACK_W = 1.75


def _cast_card_height(u: float) -> float:
    prompt = 0.75 * u + 0.4375 * 2 * u + 1.0 * u
    return _CAST_PAD * 2 * u + _CAST_HEAD * u + _CAST_COLUMN * u + prompt


def cast_layout(fw: int, fh: int) -> Dict[str, Rect]:
    """``_wrap_owrb0``: fixed, left 60 %, top 50 %, translateY(-50 %)."""
    u = rem(fw, fh)
    card_w = _CAST_W * u
    card_h = _cast_card_height(u)
    card_left = 0.60 * fw
    card_top = 0.50 * fh - card_h / 2.0
    column_top = card_top + _CAST_PAD * u + _CAST_HEAD * u
    col_x = card_left + _CAST_PAD * u
    track_x = col_x + _CAST_TICKS * u + 0.5 * u
    track = rect(track_x / fw, column_top / fh, _CAST_TRACK_W * u / fw, _CAST_COLUMN * u / fh)
    readout = rect((track_x + _CAST_TRACK_W * u) / fw, column_top / fh,
                   max(0.02, (card_left + card_w - _CAST_PAD * u - track_x
                              - _CAST_TRACK_W * u) / fw),
                   _CAST_COLUMN * u / fh)
    return {"card": rect(card_left / fw, card_top / fh, card_w / fw, card_h / fh),
            "track": track, "readout": readout}


# ── the KEEP / RELEASE catch modal ───────────────────────────────────────────
_CATCH_W = 28.75
_CATCH_ZOOM = 1.4
_CATCH_PAD = 1.0


def catch_modal_layout(fw: int, fh: int) -> Dict[str, Rect]:
    """``_overlay_dxhav`` (flex, justify flex-end, padding-right 2vw) wrapping
    ``_modal_dxhav`` (zoom 1.4, width 28.75rem, max-width 62vw).

    The choice buttons are a 1fr 1fr grid.  The modal's height is derived from
    its stacked sections (header, body, quality, choices, timer), measured from
    the same stylesheet; because ``zoom`` scales uniformly, everything below is
    expressed as a fraction of the modal rectangle and stays exact.
    """
    u = rem(fw, fh)
    modal_w = min(_CATCH_W * u * _CATCH_ZOOM, 0.62 * fw)
    modal_h = min(20.5 * u * _CATCH_ZOOM, 0.92 * fh)
    right_pad = 0.02 * fw
    modal = rect((fw - right_pad - modal_w) / fw, ((fh - modal_h) / 2.0) / fh,
                 modal_w / fw, modal_h / fh)
    pad = _CATCH_PAD * u * _CATCH_ZOOM
    choices = rect(modal.x + pad / fw, modal.y + modal.h * 0.655,
                   modal.w - 2 * pad / fw, modal.h * 0.175)
    half = (choices.w - 0.5625 * u * _CATCH_ZOOM / fw) / 2.0
    keep = rect(choices.x, choices.y, half, choices.h)
    release = rect(choices.x + choices.w - half, choices.y, half, choices.h)
    return {"modal": modal, "choices": choices, "keep": keep, "release": release}


# ── notifications (used to spot "inventory full" style toasts) ───────────────
#: A notification card, in rem, from ``_box_1kes5``.  The stack is only in the
#: bottom-left corner of the viewport, so a tall window (which makes ``rem``
#: large) starts clipping the cards: the column is ``min(21.25rem, ...)`` wide
#: and ``5 * 3.4rem`` tall out of a height that is already ``67.5 * rem``.
_NOTIFY_W = 21.25
_NOTIFY_BOX_H = 3.4375
_NOTIFY_GAP = 0.5


def notify_layout(fw: int, fh: int, slots: int = 5) -> Dict[str, object]:
    """``_container_167sm``: fixed, left 1rem, top 50 %, translateY(-50 %).

    Each ``_box_1kes5`` is ``_NOTIFY_BOX_H`` rem tall (progress bar + the padded
    row: a 2.25rem icon plate, or an 0.6875 + 0.75rem pair of text lines),
    ``_NOTIFY_GAP`` rem apart.  Getting this wrong does not just misplace the
    boxes - it makes the *bottom* of the stack overlap a fish, and every red
    pixel in that overlap reads as "error toast".
    """
    u = rem(fw, fh)
    box_w = min(_NOTIFY_W * u, 0.42 * fw)
    box_h = _NOTIFY_BOX_H * u
    gap = _NOTIFY_GAP * u
    total = slots * box_h + (slots - 1) * gap
    top = fh / 2.0 - total / 2.0
    boxes = [rect(1.0 * u / fw, (top + i * (box_h + gap)) / fh, box_w / fw, box_h / fh)
             for i in range(slots)]
    return {"stack": boxes[0].union(boxes[-1]), "boxes": boxes}


# ── the depth / action card (bottom right) ──────────────────────────────────
#: The depth card and the action row under it, in rem, from the stylesheet.
_DEPTH_RIGHT = 1.25
_DEPTH_W = 16.75
_DEPTH_GAP = 0.4375
_DEPTH_PAD = 0.5
_DEPTH_ICON = 1.875
_DEPTH_BODY_GAP = 0.375
_DEPTH_LADDER = 0.25
_ACTION_PAD = 0.4375
_ACTION_KEY = 1.3125
_ACTION_KEY_PAD = 0.5625


def depth_layout(fw: int, fh: int) -> Dict[str, Rect]:
    """``_column_xtsyz``: fixed, right 1.25rem, width 16.75rem.

    The column is placed in script, not in CSS: ``top = max(innerHeight * 0.5,
    trackerBottom + 12)``.  The tracker is not usually on screen, so the top of
    the column sits at half the viewport, and the cards stack downwards: the
    depth card, then the action row ("[E] Start fishing / <blocked reason>").
    """
    u = rem(fw, fh)
    w = _DEPTH_W * u
    x = fw - _DEPTH_RIGHT * u - w
    top = fh * 0.5

    card_h = 2 * _DEPTH_PAD * u + max(_DEPTH_ICON * u, 2.0 * u) + _DEPTH_BODY_GAP * u + _DEPTH_LADDER * u
    card = rect(x / fw, top / fh, w / fw, card_h / fh)

    action_top = top + card_h + _DEPTH_GAP * u
    action_h = 2 * _ACTION_PAD * u + _ACTION_KEY * u
    action = rect(x / fw, action_top / fh, w / fw, action_h / fh)
    key = rect((x + _ACTION_KEY_PAD * u) / fw,
               (action_top + _ACTION_PAD * u) / fh,
               _ACTION_KEY * u / fw, _ACTION_KEY * u / fh)
    return {
        "card": card,
        "head": rect(card.x, card.y, card.w, (max(_DEPTH_ICON * u, 2.0 * u) + 2 * _DEPTH_PAD * u) / fh),
        "ladder": rect(card.x + _DEPTH_PAD * u / fw, (card.y2 - _DEPTH_PAD * u / fh) - _DEPTH_LADDER * u / fh,
                       (w - 2 * _DEPTH_PAD * u) / fw, _DEPTH_LADDER * u / fh),
        "action": action,
        "key": key,
    }


# ── the "hold E to cast" helper bar (bottom centre) ─────────────────────────
def help_layout(fw: int, fh: int) -> Dict[str, Rect]:
    u = rem(fw, fh)
    h = 3.0 * u
    w = min(26.0 * u, 0.7 * fw)
    return {"bar": rect((fw - w) / 2.0 / fw, (fh - 0.09 * fh - h) / fh, w / fw, h / fh)}


def all_regions(fw: int, fh: int) -> Dict[str, Rect]:
    """Flat name -> Rect map, handy for the debug overlay."""
    out: Dict[str, Rect] = {}
    fight = fight_layout(fw, fh)
    out["fight.hud"] = fight.hud
    out["fight.cue_left"] = fight.cue_left
    out["fight.cue_right"] = fight.cue_right
    out["fight.tension"] = fight.tension_track
    out["fight.progress"] = fight.progress_track
    for k, v in bite_layout(fw, fh).items():
        out[f"bite.{k}"] = v
    for k, v in cast_layout(fw, fh).items():
        out[f"cast.{k}"] = v
    for k, v in catch_modal_layout(fw, fh).items():
        out[f"catch.{k}"] = v
    for k, v in depth_layout(fw, fh).items():
        out[f"depth.{k}"] = v
    for k, v in help_layout(fw, fh).items():
        out[f"help.{k}"] = v
    out["notify.stack"] = notify_layout(fw, fh)["stack"]
    return out
