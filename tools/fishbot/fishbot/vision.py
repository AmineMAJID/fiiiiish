"""Reading the resource's HUD off the screen.

The qs-fisher NUI tells the player everything they need, and it tells the tool
the same thing, because it is all drawn with known, saturated colours on a dark
panel:

===========================  ======================  ==========================
what we need                 where it is drawn       how we read it
===========================  ======================  ==========================
"am I in the reel game?"     `_wrap_1te5d` panel     bar-track contrast
which way to pull            `_cueOn_1te5d` chevron  saturated-cyan pixel count
line tension (the danger)    second `_track` bar     saturated fill width
reel progress                first `_track` bar      saturated fill width
"has a fish bitten?"         `_ringFill_1k7mm`       circumference coverage
cast power                   `_track_owrb0` needle   vertical fill height
"keep or release?"           `_choices_dxhav` grid   two adjacent button fills
"is my bag full?"            `_box_1kes5` toast      red pixels in the stack
===========================  ======================  ==========================

Every detector below is deliberately *relative*: it compares a region against
its own neighbours instead of trusting an absolute colour, so it survives
different game brightness, night-time, weather and the different PostFX the
player might run.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional, Sequence, Tuple

# numpy makes the vision layer fast, but it is not *required*: the pure-Python
# fallbacks below are slow enough to miss frames at 4K and are not what the tool
# is tuned on, so the runner refuses to start without it and says why.  The
# module still imports without numpy so geometry and the controller can be used
# and tested anywhere.
try:
    import numpy as np

    HAVE_NUMPY = True
except Exception:  # pragma: no cover - exercised on machines without numpy
    np = None  # type: ignore[assignment]
    HAVE_NUMPY = False

from .geometry import (
    FightLayout,
    Rect,
    bite_layout,
    cast_layout,
    catch_modal_layout,
    depth_layout,
    fight_layout,
    notify_layout,
)

# ── colours the stylesheet actually uses (RGB) ───────────────────────────────
CUE_ON = (125, 211, 252)        # #7dd3fc  lit chevron
CUE_OFF = (30, 41, 59)          # #1e293b  unlit chevron
RING_HOT = (239, 68, 68)        # #ef4444  countdown about to expire
RING_COOL = (56, 189, 248)      # #38bdf8  countdown running
PROGRESS_FILL = (96, 165, 250)  # #60a5fa  reel progress
ERROR = (239, 68, 68)           # #ef4444  error toast
SUCCESS = (34, 197, 94)         # #22c55e  success toast


# ── small colour helpers ─────────────────────────────────────────────────────
def _f(arr):
    return arr.astype("float32") / 255.0


def saturation(arr) -> "np.ndarray":
    """HSV saturation per pixel, 0..1 (cheap, no colour-space library)."""
    f = _f(arr)
    mx = f.max(axis=2)
    mn = f.min(axis=2)
    return (mx - mn) / np.maximum(mx, 1e-6)


def value(arr) -> "np.ndarray":
    return _f(arr).max(axis=2)


def color_score(arr, rgb: Sequence[float], tol: float = 0.32) -> "np.ndarray":
    """1 where a pixel is within ``tol`` of ``rgb`` (normalised RGB distance)."""
    f = _f(arr)
    d = np.abs(f - (np.asarray(rgb, dtype="float32") / 255.0)).sum(axis=2)
    return d <= tol * 3.0


# ── the frame ────────────────────────────────────────────────────────────────
@dataclass
class Frame:
    """One captured frame, RGB, plus the geometry it was captured with.

    ``width``/``height`` are the *capture* size and ``arr`` is indexed with
    them.  The HUD regions, however, are derived from ``window_width`` /
    ``window_height`` - the size of the game window itself - because the
    stylesheet sizes everything in ``rem``, and ``rem`` is clamped to a minimum
    of 8 px.  Capturing at half resolution therefore does not simply halve the
    fractions: below roughly 960x540 the clamp bites and the HUD takes up a
    slightly larger share of the picture.  Deriving the regions from the window
    keeps them exact at any capture scale.
    """

    arr: "np.ndarray"
    width: int
    height: int
    timestamp: float
    window_width: Optional[int] = None
    window_height: Optional[int] = None

    def __post_init__(self) -> None:
        if self.window_width is None:
            self.window_width = self.width
        if self.window_height is None:
            self.window_height = self.height

    @property
    def viewport(self) -> Tuple[int, int]:
        """The window size the HUD was laid out for."""
        return int(self.window_width or self.width), int(self.window_height or self.height)

    def crop(self, r: Rect):
        left, top, w, h = r.to_px(self.width, self.height)
        return self.arr[top:top + h, left:left + w]

    def mean_brightness(self) -> float:
        return float(value(self.arr).mean())


# ── primitive readings ───────────────────────────────────────────────────────
def saturated_fraction(arr, sat_min: float = 0.30, val_min: float = 0.18) -> float:
    """Share of pixels that are clearly coloured rather than dark grey."""
    if arr.size == 0:
        return 0.0
    sat = saturation(arr)
    val = value(arr)
    return float(((sat > sat_min) & (val > val_min)).mean())


def color_count(arr, rgb, tol: float = 0.32, sat_min: float = 0.25,
                val_min: float = 0.25) -> int:
    if arr.size == 0:
        return 0
    mask = color_score(arr, rgb, tol) & (saturation(arr) > sat_min) & (value(arr) > val_min)
    return int(mask.sum())


def _profile_sat(arr) -> "np.ndarray":
    """Mean saturation per column."""
    if arr.size == 0:
        return np.zeros(0, dtype="float32")
    return saturation(arr).mean(axis=0)


# The HUD is a browser overlay, so its colours are not affected by the game's
# brightness, weather or night cycle.  What still varies is *which* colour a bar
# is painted (green, amber, red or blue), never how bright it is: a fill is
# always a bright pixel on a dark track.  Thresholding on value + saturation
# therefore catches every colour the stylesheet uses, and never the track.
FILL_VAL_MIN = 0.45
FILL_SAT_MIN = 0.20


def _fill_mask(arr, val_min: float = FILL_VAL_MIN, sat_min: float = FILL_SAT_MIN) -> "np.ndarray":
    return (value(arr) > val_min) & (saturation(arr) > sat_min)


def horizontal_fill(arr, sat_min: float = FILL_SAT_MIN, coverage: float = 0.35,
                    val_min: float = FILL_VAL_MIN) -> float:
    """Width of the coloured bar in a horizontal track, 0..1, read as the
    contiguous run that starts at the left edge (the fill always grows from
    the left because the CSS bar does)."""
    if arr.size == 0 or arr.shape[1] < 4:
        return 0.0
    # per column: is the majority of the bar's height painted?
    col = _fill_mask(arr, val_min, sat_min).mean(axis=0)
    filled = col > coverage
    if not filled.any():
        return 0.0
    if not filled[0]:
        # allow a two-pixel rounded corner before the fill really starts
        head = filled[:6]
        if not head.any():
            return 0.0
        start = int(head.argmax())
        filled = filled[start:]
    run = 0
    for v in filled:
        if not v:
            break
        run += 1
    return min(1.0, run / float(arr.shape[1]))


def vertical_fill(arr, sat_min: float = FILL_SAT_MIN, coverage: float = 0.30,
                  val_min: float = FILL_VAL_MIN) -> float:
    """Height of the coloured fill in a vertical track, 0..1 from the bottom."""
    if arr.size == 0 or arr.shape[0] < 4:
        return 0.0
    row = _fill_mask(arr, val_min, sat_min).mean(axis=1)
    filled = row > coverage
    if not filled.any():
        return 0.0
    filled = filled[::-1]  # bottom row first
    if not filled[0]:
        head = filled[:6]
        if not head.any():
            return 0.0
        filled = filled[int(head.argmax()):]
    run = 0
    for v in filled:
        if not v:
            break
        run += 1
    return min(1.0, run / float(arr.shape[0]))


def band_contrast(arr, sat_of_rows: Optional["np.ndarray"] = None) -> float:
    """How much brighter the middle band of a region is than its outer rows.

    The HUD's tracks are a 6 % white overlay on a dark panel, so they are always
    measurably lighter than the panel around them, whatever the game brightness.
    """
    if arr.size == 0 or arr.shape[0] < 6:
        return 0.0
    val = value(arr).mean(axis=1)
    rows = val.shape[0]
    mid = val[rows // 3: rows - rows // 3].mean()
    edge = np.concatenate([val[:2], val[-2:]]).mean()
    return float(mid - edge)


def ring_coverage(arr, sat_min: float = 0.45, val_min: float = 0.55,
                  samples: int = 240) -> float:
    """Fraction of the countdown ring's circumference that is drawn.

    The SVG is a single arc with ``stroke-dasharray`` == the circumference and
    ``stroke-dashoffset`` == circumference * (1 - remaining), rotated -90°, so a
    simple count of coloured samples around the circle gives the remaining
    time directly, no start-angle bookkeeping needed.

    Two other rings share this area and must not be counted: a decorative
    ripple (a 50 %-alpha border, value ~0.35) and the buoy's glow (a soft
    gradient).  The countdown arc is a *solid* stroke (value 0.78-0.97), so the
    brightness gate separates them by a wide margin.
    """
    if arr.size == 0:
        return 0.0
    h, w = arr.shape[:2]
    side = min(h, w)
    if side < 12:
        return 0.0
    cy = h / 2.0
    cx = w / 2.0
    radius = 0.455 * side  # the SVG's r=46 in a 100-unit viewBox
    sat = saturation(arr)
    val = value(arr)
    hit = 0
    total = 0
    for i in range(samples):
        ang = 2.0 * math.pi * i / samples
        # stroke-width is 5 units of a 100-unit viewBox, i.e. ~5 % of the side,
        # so probe across that thickness: a camera-read overlay is resampled
        # and the arc will not always land on the exact nominal radius.
        for dr in (-0.045, -0.03, -0.015, 0.0, 0.015, 0.03, 0.045):
            rr = radius * (1.0 + dr)
            x = int(round(cx + rr * math.cos(ang)))
            y = int(round(cy + rr * math.sin(ang)))
            if 0 <= x < w and 0 <= y < h:
                if sat[y, x] > sat_min and val[y, x] > val_min:
                    hit += 1
                    break
        total += 1
    return (hit / float(total)) if total else 0.0


def _lit_fraction(arr) -> float:
    """Share of a glyph box that is painted in the lit chevron colour.

    The lit glyph is ``#7dd3fc`` (value 0.99, saturation 0.50); the unlit one is
    ``#1e293b`` (value 0.23, saturation 0.35).  A brightness gate separates them
    with a wide margin that no background can close, because the whole glyph box
    sits inside the HUD's own opaque panel.
    """
    if arr.size == 0:
        return 0.0
    return float(((value(arr) > 0.62) & (saturation(arr) > 0.28)).mean())


def bright_text_fraction(arr, val_min: float = 0.62, sat_max: float = 0.30) -> float:
    """Share of near-white, low-saturation pixels: the HUD's label/body text."""
    if arr.size == 0:
        return 0.0
    sat = saturation(arr)
    val = value(arr)
    return float(((val > val_min) & (sat < sat_max)).mean())


# ── HUD state readings ───────────────────────────────────────────────────────
@dataclass
class FightReading:
    present: bool
    tension: float = 0.0          # 0..1 == |angle| / maxAngle
    progress: float = 0.0         # 0..1 == reel progress
    side: Optional[str] = None    # 'left' | 'right' | None  (where to pull)
    confidence: float = 0.0

    def __str__(self) -> str:
        return (f"fight present={self.present} tension={self.tension:.2f} "
                f"progress={self.progress:.2f} side={self.side}")


def panel_presence(frame: Frame, layout: FightLayout) -> float:
    """How much the reel *card* looks like a card, 0..1.

    The bars alone cannot answer "is the mini-game on screen?" in its first
    frames: the tension bar is at zero, the reel has not moved and the game has
    not picked a side yet, so every fill-based signal is legitimately silent
    while the fight is already running.  The card itself is the evidence, and it
    is a *flat, opaque plate* of a known brightness over the world.
    """
    inner = frame.crop(layout.panel.inset(0.03, 0.12))
    if inner.size == 0:
        return 0.0
    v = value(inner)
    mean = float(v.mean())
    if not (0.13 <= mean <= 0.32):
        return 0.0
    if float(v.std()) > 0.09:
        return 0.0
    ring = frame.crop(layout.hud.grow(0.10, 0.8))
    if ring.size == 0:
        return 0.0
    ring_v = value(ring)
    # A scene that happens to match the card's brightness is still a scene: it
    # is textured, or it is a smooth gradient the card interrupts with an edge.
    if abs(float(ring_v.mean()) - mean) < 0.02 and float(ring_v.std()) < 0.05:
        return 0.0
    return 1.0


def read_fight(frame: Frame, layout: Optional[FightLayout] = None) -> FightReading:
    layout = layout or fight_layout(*frame.viewport)

    tension_roi = frame.crop(layout.tension_track.grow(0.0, 0.6))
    progress_roi = frame.crop(layout.progress_track.grow(0.0, 0.6))
    contrast = band_contrast(tension_roi)
    tension = horizontal_fill(tension_roi)
    progress = horizontal_fill(progress_roi)

    # The lit chevron is #7dd3fc on a #1e293b glyph: the same shape, five times
    # brighter.  Comparing the two boxes against each other (rather than against
    # an absolute colour) survives any background and any HUD recolour.
    left_roi = frame.crop(layout.cue_left.grow(0.15, 0.15))
    right_roi = frame.crop(layout.cue_right.grow(0.15, 0.15))
    left_hot = _lit_fraction(left_roi)
    right_hot = _lit_fraction(right_roi)

    side: Optional[str] = None
    cue_strength = 0.0
    if max(left_hot, right_hot) > 0.012:
        if left_hot > 1.6 * max(1e-4, right_hot):
            side = "left"
            cue_strength = min(1.0, left_hot / 0.05)
        elif right_hot > 1.6 * max(1e-4, left_hot):
            side = "right"
            cue_strength = min(1.0, right_hot / 0.05)

    # `contrast` is the two lightest stripes in the box: the meter tracks.  It is
    # the cheapest "the reel HUD is on screen" signal, but on its own it is
    # silent during a fight's first frames, so the card itself is checked too.
    card = panel_presence(frame, layout)
    present = (contrast > 0.012 or tension > 0.02 or progress > 0.02
               or side is not None or card > 0.5)
    conf = max(min(1.0, contrast / 0.03), cue_strength, min(1.0, tension * 3), card)
    return FightReading(present=present, tension=tension, progress=progress,
                        side=side, confidence=conf)


@dataclass
class BiteReading:
    present: bool
    biting: bool
    remaining: float = 1.0

    def __str__(self) -> str:
        return f"bite present={self.present} biting={self.biting} left={self.remaining:.2f}"


def read_bite(frame: Frame) -> BiteReading:
    lay = bite_layout(*frame.viewport)
    ring_roi = frame.crop(lay["ring"])
    ring = ring_coverage(ring_roi)
    float_roi = frame.crop(lay["float"])
    # The bobber is painted near-white, so it is the one thing in this region
    # that is bright *and* unsaturated.  Testing for "colourful" instead fires
    # on the sea itself, which is exactly what the water behind it looks like.
    buoy = 0.0
    if float_roi.size:
        v = value(float_roi)
        sat = saturation(float_roi)
        buoy = float(((v > 0.75) & (sat < 0.25)).mean())
    biting = ring > 0.05
    present = biting or buoy > 0.004
    return BiteReading(present=present, biting=biting, remaining=ring)


@dataclass
class CastReading:
    present: bool
    power: float = 0.0
    charging: bool = False

    def __str__(self) -> str:
        return f"cast present={self.present} power={self.power:.2f} charging={self.charging}"


def read_cast(frame: Frame) -> CastReading:
    lay = cast_layout(*frame.viewport)
    track_roi = frame.crop(lay["track"])
    power = vertical_fill(track_roi, sat_min=0.20, coverage=0.28)
    # The card's tick gutter (0, 25, 50, 75, 100) is text, so "the card is up"
    # is best read from the empty track itself: a 1.75rem dark trough that is
    # clearly darker than the card around it.
    if track_roi.size:
        v = value(track_roi)
        trough = float(v.mean())
        card_roi = frame.crop(lay["card"])
        card_v = float(value(card_roi).mean()) if card_roi.size else 0.0
        present = (card_v - trough) > 0.012 or power > 0.02
    else:
        present = False
    charging = power > 0.02
    return CastReading(present=present, power=power, charging=charging)


@dataclass
class CatchReading:
    present: bool
    keep_rect: Optional[Rect] = None
    release_rect: Optional[Rect] = None
    confidence: float = 0.0

    def __str__(self) -> str:
        return f"catch-modal present={self.present} conf={self.confidence:.2f}"


#: How much of the two choice buttons must be dark card.  The modal is a dark
#: panel whatever is behind it, so this is what separates "the KEEP / RELEASE
#: card is up" from "the HUD is closed and the screen is showing the world":
#: a night scene is almost entirely dark (0.99), a bright one almost none (0.0),
#: and the card itself always lands near 0.75.
CHOICE_DARK_MIN = 0.45
CHOICE_DARK_MAX = 0.95


def read_catch_modal(frame: Frame) -> CatchReading:
    lay = catch_modal_layout(*frame.viewport)
    choices = frame.crop(lay["choices"])
    if choices.size == 0:
        return CatchReading(False)
    # Two side-by-side buttons, each a dark plate carrying bright centred
    # content (icon, upper-case label, note).  Both halves must look like that:
    # text without a dark plate is a bright game world, and a dark plate without
    # text is a night scene.
    left_half = choices[:, : choices.shape[1] // 2]
    right_half = choices[:, choices.shape[1] // 2:]
    left_txt = bright_text_fraction(left_half, val_min=0.55, sat_max=0.35)
    right_txt = bright_text_fraction(right_half, val_min=0.55, sat_max=0.35)
    dark = float((value(choices) < 0.35).mean())
    ok = (left_txt > 0.02 and right_txt > 0.02
          and CHOICE_DARK_MIN < dark < CHOICE_DARK_MAX)
    return CatchReading(present=ok, keep_rect=lay["keep"], release_rect=lay["release"],
                        confidence=min(left_txt, right_txt) * 20.0 if ok else 0.0)


def read_error_toast(frame: Frame) -> bool:
    """True when a red (error) toast is showing in the notification stack."""
    lay = notify_layout(*frame.viewport)
    for box in lay["boxes"]:  # type: ignore[index]
        roi = frame.crop(box)
        if roi.size == 0:
            continue
        red = color_count(roi, ERROR, tol=0.26, sat_min=0.35, val_min=0.25)
        if red > 40:
            return True
    return False


#: The action key's green plate: #4ade80 when the cast is allowed, #334155 when
#: the game is refusing it (too deep, in a vehicle, near the job ped...).  The
#: player sees one colour or the other, and so does the tool.
ACTION_READY = (74, 222, 128)
ACTION_BLOCKED = (51, 65, 85)


@dataclass
class CastGateReading:
    """Whether the game will let a cast happen right now.

    ``card``  the depth card is on screen (the player has a rod out and there is
              water in front of them), 0..1 confidence
    ``ready`` the action key is green: the cast would be accepted
    ``blocked`` the action row is on screen but greyed: the game is refusing
    """

    card: float = 0.0
    ready: bool = False
    blocked: bool = False
    present: bool = False

    def __str__(self) -> str:
        if self.ready:
            state = "ready"
        elif self.blocked:
            state = "blocked"
        elif self.present:
            state = "unknown"
        else:
            state = "no card"
        return (f"cast-gate {state} card={self.card:.2f} "
                f"ready={self.ready} blocked={self.blocked}")


def read_cast_gate(frame: Frame) -> CastGateReading:
    """Read the depth card's action key.

    This is the only honest answer to "can I cast?" that the resource publishes.
    ``StartFishing`` runs on E only when the water probe succeeded and nothing
    blocks it, and the HUD says so: the key badge is green (#4ade80) with
    "Start fishing" when a cast would be accepted, and slate grey with the
    reason when it would not.  Casting while it is grey spends an E on nothing.
    """
    lay = depth_layout(*frame.viewport)
    key_roi = frame.crop(lay["key"])
    card_roi = frame.crop(lay["card"])
    if key_roi.size == 0 or card_roi.size == 0:
        return CastGateReading()

    key = key_roi.astype("float32") / 255.0
    green = float(((key[:, :, 1] > 0.55) & (key[:, :, 0] < 0.55) & (key[:, :, 2] < 0.55)).mean())

    # The card carries a cyan depth icon (#38bdf8) and a cyan top border.  A
    # saturated cyan that is *not* the sea - the sea is desaturated by
    # comparison and darker - is the card's signature, and unlike "the card is
    # dark" it does not fire on a night sky or on a bright snowfield.
    pixels = card_roi.shape[0] * card_roi.shape[1]
    cyan = color_count(card_roi, (56, 189, 248), tol=0.30, sat_min=0.5, val_min=0.5)
    card = 1.0 if pixels and (cyan / pixels) > 0.012 else 0.0
    ready = green > 0.35
    blocked = bool(card) and not ready
    return CastGateReading(card=card, ready=ready, blocked=blocked,
                           present=bool(card) or ready)


def read_depth_card(frame: Frame) -> float:
    """0..1 confidence that the bottom-right depth/action card is on screen."""
    lay = depth_layout(*frame.viewport)
    roi = frame.crop(lay["card"])
    if roi.size == 0:
        return 0.0
    return min(1.0, saturated_fraction(roi) * 12.0)
