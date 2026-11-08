"""A fake FiveM client that speaks the qs-fisher HUD, for end-to-end tests.

It implements the resource's *observable* behaviour - the cast power meter, the
bite window, the reel mini-game, the catch modal - and it responds to injected
input the way ``client/fishing.lua`` does:

* ``E`` starts a charge; the left mouse button held during it sweeps the power
  meter; releasing it sends the cast.
* During the reel, **nothing but camera movement matters**.  ``move(x, y)``
  calls are turned into a change of the camera offset exactly as the Lua would
  see it, including the sign being unknown to the bot.
* The catch modal is answered by a click on KEEP or RELEASE.

Every frame it renders is produced by ``simhud`` with the current values, so the
bot's vision layer is exercised for real: nothing is handed to it directly.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None

from fishbot import simhud
from fishbot.gamemodel import FISHING_CONFIG, FightParams, FightState

IDLE = "idle"
CHARGING = "charging"
CAST_FLIGHT = "cast_flight"
WAITING = "waiting"
BITING = "biting"
FIGHT = "fight"
MODAL = "modal"
DONE = "done"


@dataclass
class FakeInjector:
    """Records what the bot sends and forwards it to the game.

    ``sleep`` is handed to the bot as well, so the hold on the cast meter moves
    the simulated clock instead of the wall clock.
    """

    game: "FakeGame"
    sleep: Optional[callable] = None
    events: List[Tuple[str, dict]] = field(default_factory=list)
    sent_keys: List[str] = field(default_factory=list)

    def key(self, name: str, hold_ms: int = 40) -> None:
        self.events.append(("key", {"name": name}))
        self.sent_keys.append(name)
        self.game.on_key(name)

    def mouse_down(self, button: str = "left") -> None:
        self.events.append(("down", {"button": button}))
        self.game.on_mouse(button, True)

    def mouse_up(self, button: str = "left") -> None:
        self.events.append(("up", {"button": button}))
        self.game.on_mouse(button, False)

    def click(self, x, y, button: str = "left") -> None:
        self.events.append(("click", {"x": x, "y": y, "button": button}))
        self.game.on_click(x, y)

    def move_relative(self, dx: int, dy: int) -> None:
        self.events.append(("move", {"dx": dx, "dy": dy}))
        self.game.on_mouse_move(dx, dy)

    def move_to(self, x, y) -> None:
        self.events.append(("move_to", {"x": x, "y": y}))

    def key_down(self, name: str) -> None:
        self.events.append(("key_down", {"name": name}))
        self.game.key_down(name)

    def key_up(self, name: str) -> None:
        self.events.append(("key_up", {"name": name}))
        self.game.key_up(name)


class FakeGame:
    def __init__(self, width: int = 1920, height: int = 1080, seed: int = 0,
                 counts_per_pct: float = 1.6, inverted: bool = False,
                 band: str = "mid", bite_seconds: float = 1.2,
                 window_seconds: float = 1.6, world: str = "sea",
                 keep_available: bool = True, mute_toasts: bool = True,
                 capture_scale: float = 0.5):
        self.w = width           # the window, in screen pixels
        self.h = height
        # `fishbot.run` captures at a fraction of the window and the HUD is
        # rem-based, so the fake game is read at the same reduced size.  That
        # keeps the end-to-end tests honest *and* keeps 4K from making them
        # crawl (a full-resolution render per sample costs ~40 ms).
        self.capture_scale = max(0.2, min(1.0, capture_scale))
        self.vw = max(2, int(round(width * self.capture_scale)))
        self.vh = max(2, int(round(height * self.capture_scale)))
        self.rng = random.Random(seed)
        self.counts_per_pct = counts_per_pct
        self.inverted = inverted
        self.world = world
        self.keep_available = keep_available
        self.bite_seconds = bite_seconds
        self.window_seconds = window_seconds
        self.params = FightParams.for_band(band)

        self.time = 0.0
        self.state = IDLE
        self.power = 0.0
        self.charge_start = 0.0
        self.charging = False
        self.held = set()
        self.cast_ready_at = 0.0
        self.bite_at = 0.0
        self.window_ends = 0.0
        self.fight: Optional[FightState] = None
        self.camera_offset = 0.0     # the signed "angle" the Lua would compute
        self.modal_open = False
        self.toast_error = False
        #: What to paint in the notification corner when ``toast_error`` is set:
        #: ``None`` = a real error card, or one of the impostors the reader must
        #: refuse (``"success"``, ``"block"``, ``"fish"``).
        self.toast_kind = None
        #: Where the "keyboard focus" is, as :class:`fishbot.winapi.FocusState`
        #: would report it.  ``None`` = no opinion (the bot does not gate).
        self.focus = None
        self.show_depth = True       # the depth card is up whenever the rod is out
        self.blocked = False         # the game refusing a cast (too deep, in a car)
        self.injector: Optional[FakeInjector] = None

        # results
        self.landed = 0
        self.snapped = 0
        self.casts = 0
        self.decisions: List[bool] = []
        self.mistakes: List[str] = []

    # ── source interface ────────────────────────────────────────────────────
    def now(self) -> float:
        """The bot measures every timeout against the frame's own timestamp."""
        return self.time

    @property
    def viewport(self):
        return self.vw, self.vh

    def to_screen(self, nx: float, ny: float):
        return int(round(nx * self.w)), int(round(ny * self.h))

    def grab(self):
        from fishbot.vision import Frame
        img = self.render()
        return Frame(arr=img, width=self.vw, height=self.vh, timestamp=self.time,
                     window_width=self.w, window_height=self.h)

    # ── rendering ───────────────────────────────────────────────────────────
    def render(self):
        if self.charging:
            # the meter is only drawn while the button is held
            cycle = ((self.time - self.charge_start) % 2.2) / 1.1
            shown = cycle if cycle <= 1.0 else 2.0 - cycle
            img = simhud.render_cast(self.vw, self.vh, shown, self.world, fit=(self.w, self.h))
        elif self.state == FIGHT and self.fight is not None:
            danger = min(1.0, abs(self.camera_offset) / self.fight.max_angle)
            img = simhud.render_fight(self.vw, self.vh, danger, self.fight.progress,
                                      self.fight.target_side, self.world,
                                      fit=(self.w, self.h))
        elif self.state == CHARGING:
            img = simhud.render_cast(self.vw, self.vh, self.power, self.world, fit=(self.w, self.h))
        elif self.state == BITING:
            left = max(0.0, (self.window_ends - self.time) / self.window_seconds)
            img = simhud.render_bite(self.vw, self.vh, left, self.world, buoys=True,
                                      fit=(self.w, self.h))
        elif self.state == WAITING:
            img = simhud.render_bite(self.vw, self.vh, 0.0, self.world, buoys=True,
                                      fit=(self.w, self.h))
        elif self.state == MODAL:
            img = simhud.render_catch_modal(self.vw, self.vh, self.world, fit=(self.w, self.h))
        else:
            img = simhud._blank(self.vw, self.vh, self.world)
        if self.show_depth and self.state == IDLE:
            # rod in hand, water in front: the depth card and its action key
            img = simhud.render_depth_card(self.vw, self.vh, not self.blocked,
                                           self.world, fit=(self.w, self.h))
        if self.toast_error:
            from fishbot.geometry import notify_layout
            box = notify_layout(self.w, self.h)["boxes"][0]
            x1, y1, w, h = box.to_px(self.vw, self.vh)
            if self.toast_kind in (None, "error", "warning", "success", "info"):
                toast = simhud.render_toast(self.vw, self.vh, self.toast_kind or "error",
                                            self.world, fit=(self.w, self.h))
                img[y1:y1 + h, x1:x1 + w] = toast[y1:y1 + h, x1:x1 + w]
            elif self.toast_kind == "block":
                # red where a card would be, but flat: no bar, plate or panel
                img[y1:y1 + h, x1:x1 + w] = (239, 68, 68)
            elif self.toast_kind == "fish":
                # a red blob with a fish's shape crossing the same corner
                cy, cx = y1 + h // 2, x1 + w // 5
                ys, xs = np.ogrid[:img.shape[0], :img.shape[1]]
                blob = ((ys - cy) ** 2) / float(h * h) + ((xs - cx) ** 2) / ((w * 0.6) ** 2) < 0.25
                img[blob] = (255, 120, 90)
        return img

    # ── input from the bot ──────────────────────────────────────────────────
    def key_down(self, name: str) -> None:
        self.held.add(name.lower())
        self.on_key(name)

    def key_up(self, name: str) -> None:
        self.held.discard(name.lower())
        if name.lower() == "e" and self.state == CHARGING and not self.charging:
            # `ChargeCastPower` cancels when E comes up before the button does
            self.mistakes.append("E released before the button: the cast is cancelled")
            self.state = IDLE

    def on_key(self, name: str) -> None:
        if name.lower() != "e":
            return
        if self.state == IDLE:
            self.state = CHARGING
            self.charging = False
            self.power = 0.0
            self.charge_start = self.time
        elif self.state == BITING:
            self._start_fight()
        elif self.state == WAITING:
            pass  # the real script cancels the cast; ignore for the test
        elif self.state == FIGHT:
            self.snapped += 1
            self._abort_fight("stray E during the reel")

    def on_mouse(self, button: str, down: bool) -> None:
        if self.state != CHARGING:
            return
        if down:
            self.charging = True
            self.charge_start = self.time
        elif self.charging:
            # the meter sweeps 0->100 % in 1.1 s and back down again
            cycle = ((self.time - self.charge_start) % 2.2) / 1.1
            self.power = cycle if cycle <= 1.0 else 2.0 - cycle
            self.charging = False
            self._send_cast()

    def on_mouse_move(self, dx: int, dy: int) -> None:
        if self.state != FIGHT or self.fight is None:
            return
        pct = dx / self.counts_per_pct
        delta = pct * self.fight.max_angle / 100.0
        self.camera_offset += -delta if self.inverted else delta

    def on_click(self, x: int, y: int) -> None:
        if self.state != MODAL:
            return
        from fishbot.geometry import catch_modal_layout
        lay = catch_modal_layout(self.w, self.h)
        nx, ny = x / self.w, y / self.h
        if lay["keep"].contains(nx, ny):
            self.decisions.append(True)
            self._close_modal()
        elif lay["release"].contains(nx, ny):
            self.decisions.append(False)
            self._close_modal()
        else:
            self.mistakes.append(f"clicked outside the buttons at ({x},{y})")

    # ── game logic ──────────────────────────────────────────────────────────
    def _send_cast(self) -> None:
        if self.blocked:
            self.mistakes.append("cast while the game was refusing it")
            self.state = IDLE
            return
        if self.power < 0.05:
            self.mistakes.append(f"cast refused: power {self.power:.2f}")
            self.state = IDLE
            return
        self.casts += 1
        self.state = CAST_FLIGHT
        self.cast_ready_at = self.time + 0.45

    def _start_fight(self) -> None:
        self.state = FIGHT
        self.camera_offset = 0.0
        self.fight = FightState(params=self.params, initial_dist=10.0,
                                max_angle=self.params.max_angle, rng=random.Random(self.rng.random()))
        self._fight_tension_target = 0.0
        self._flee_left = 0

    def _abort_fight(self, why: str) -> None:
        self.fight = None
        self.state = IDLE
        self.mistakes.append(why)

    def _close_modal(self) -> None:
        self.modal_open = False
        self.state = IDLE
        self.toast_error = False

    def advance(self, dt: float) -> None:
        """Move the game forward, readying the HUD for the next sample."""
        if dt > 0.2:
            # Long jumps (the bot's "wait for the animation" sleeps) are split
            # too, but coarsely: the HUD only publishes every 50 ms anyway.
            while dt > 0:
                piece = min(0.05, dt)
                self.advance(piece)
                dt -= piece
            return
        if self.charging and self.time - self.charge_start > 3.0:
            self.mistakes.append("left button held for over 3 s")
            self.charging = False
        remaining = dt
        while remaining > 0:
            step = min(0.016, remaining)
            remaining -= step
            self.time += step
            self._advance(step)

    def _advance(self, dt: float) -> None:
        if self.state == CAST_FLIGHT and self.time >= self.cast_ready_at:
            self.state = WAITING
            self.bite_at = self.time + self.bite_seconds
        elif self.state == WAITING and self.time >= self.bite_at:
            self.state = BITING
            self.window_ends = self.time + self.window_seconds
        elif self.state == BITING and self.time > self.window_ends:
            self.state = WAITING
            self.bite_at = self.time + self.bite_seconds
        elif self.state == FIGHT and self.fight is not None:
            self.fight.step(dt, self.camera_offset - getattr(self, "_last_offset", 0.0))
            self._last_offset = self.camera_offset
            if self.fight.outcome == "won":
                self.landed += 1
                self.fight = None
                self.state = MODAL
                self.modal_open = True
                self._last_offset = 0.0
            elif self.fight.outcome == "lost_tension":
                self.snapped += 1
                self.fight = None
                self.state = IDLE
                self._last_offset = 0.0
