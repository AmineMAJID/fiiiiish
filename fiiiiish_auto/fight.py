"""Faithful port of the reel-in fight from ``client/fishing.lua``.

The real loop (StartFishingFight) does this every game frame:

    angle   = signed angle between the camera and the bobber, in degrees
    danger  = floor(|angle| / maxAngle * 100)
    if |angle| > maxAngle -> the line snaps
    side    = right / left / center, with an 8 degree dead zone
    target  = the side the player must pull toward; it flips when the
              accumulated tension reaches a random threshold
    pulling on target -> tension grows, bobber comes closer
    pulling elsewhere -> tension decays, bobber slips away
    progress = (initialDist - dist) / (initialDist - minDistance)

Only the angle is controlled by the player (the camera).  Everything else is
derived, which is why a bot that can steer the camera can play the fight.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Literal

from .config import FISHING_CONFIG, FightParams
from .rng import Rng

Side = Literal["left", "right", "center"]
TargetSide = Literal["left", "right"]
Outcome = Literal["success", "line_snapped", "cancelled", "timeout"]


@dataclass
class FightState:
    """Mutable state of one fight."""

    angle: float = 0.0                 # signed degrees, + = right
    target_side: TargetSide | None = None
    tension: float = 0.0
    random_duration: float = 0.75
    tension_decay: float = 0.015
    distance: float = 10.0
    initial_distance: float = 10.0
    progress: float = 0.0
    danger: int = 0
    side: Side = "center"
    elapsed: float = 0.0
    active: bool = True
    outcome: Outcome | None = None
    flips: int = 0
    max_danger: int = 0
    time_on_target: float = 0.0
    time_off_target: float = 0.0

    def as_dict(self) -> dict:
        return {
            "angle": round(self.angle, 3),
            "target_side": self.target_side,
            "tension": round(self.tension, 4),
            "distance": round(self.distance, 4),
            "progress": round(self.progress, 4),
            "danger": self.danger,
            "side": self.side,
            "elapsed": round(self.elapsed, 3),
            "active": self.active,
            "outcome": self.outcome,
            "flips": self.flips,
            "max_danger": self.max_danger,
        }


class FightEngine:
    """Deterministic, fixed-step simulation of the Lua fight loop."""

    def __init__(
        self,
        params: FightParams,
        initial_distance: float,
        rng: Rng,
        *,
        dead_zone: float = FISHING_CONFIG["dead_zone"],
        min_distance: float = FISHING_CONFIG["min_distance"],
        gain_rate: float = FISHING_CONFIG["gain_rate"],
        max_angle_override: float | None = None,
    ) -> None:
        self.params = params
        self.max_angle = max_angle_override if max_angle_override is not None else params.max_angle
        self.dead_zone = dead_zone
        self.min_distance = min_distance
        self.gain_rate = gain_rate
        self.rng = rng
        self.initial_distance = max(float(initial_distance), min_distance + 0.1)
        self.state = FightState(
            distance=self.initial_distance,
            initial_distance=self.initial_distance,
            random_duration=self._roll_duration(),
            tension_decay=self._roll_decay(),
        )

    # -- helpers -----------------------------------------------------------
    def _roll_duration(self) -> float:
        return self.rng.uniform(50, 100) / 100.0 / self.params.turn_rate

    def _roll_decay(self) -> float:
        return self.rng.uniform(10, 20) / 1000.0 * self.params.turn_rate

    def set_angle(self, angle: float) -> None:
        self.state.angle = float(angle)

    def get_angle(self) -> float:
        return self.state.angle

    # -- one frame ---------------------------------------------------------
    def step(self, dt: float) -> FightState:
        """Advance the fight by ``dt`` seconds.

        The Lua loop runs on ``Wait(0)`` and uses per-frame constants.  We
        scale them by ``dt * 60`` so the simulation is frame-rate independent
        while remaining identical at 60 fps.
        """
        st = self.state
        if not st.active:
            return st

        frame = max(dt, 0.0) * 60.0
        angle = st.angle
        abs_angle = abs(angle)
        st.elapsed += dt
        st.danger = int(abs_angle / self.max_angle * 100.0)
        st.max_danger = max(st.max_danger, st.danger)

        if abs_angle > self.max_angle:
            self._finish("line_snapped")
            return st

        if angle > self.dead_zone:
            st.side = "right"
        elif angle < -self.dead_zone:
            st.side = "left"
        else:
            st.side = "center"

        # The first time the player pulls outside the dead zone, the game
        # assigns the OPPOSITE side as the target.  This is the quirk that
        # makes the NUI say "pull left" right after you moved right.
        if st.target_side is None and st.side != "center":
            st.target_side = "right" if st.side == "left" else "left"

        correct = st.target_side is not None and st.side == st.target_side
        if correct:
            st.time_on_target += dt
            st.tension += (abs_angle / self.max_angle) * self.gain_rate * frame
            if st.tension >= st.random_duration * frame:
                st.target_side = "right" if st.target_side == "left" else "left"
                st.tension = 0.0
                st.random_duration = self._roll_duration()
                st.tension_decay = self._roll_decay()
                st.flips += 1
        else:
            st.time_off_target += dt
            st.tension = max(st.tension - st.tension_decay * frame, 0.0)

        if correct:
            st.distance -= (abs_angle / self.max_angle) * self.params.pull_speed * frame
        else:
            st.distance += self.params.slip_speed * frame

        st.distance = max(min(st.distance, st.initial_distance), self.min_distance)
        st.progress = (st.initial_distance - st.distance) / (self.initial_distance - self.min_distance)
        st.progress = max(0.0, min(1.0, st.progress))

        if st.progress >= 1.0:
            st.progress = 1.0
            self._finish("success")
        return st

    def _finish(self, outcome: Outcome) -> None:
        st = self.state
        st.active = False
        st.outcome = outcome
        if outcome == "success":
            st.progress = 1.0

    # -- convenience -------------------------------------------------------
    @property
    def state_dict(self) -> dict:
        return self.state.as_dict()


class CameraModel:
    """The player's camera: the only input the fight actually reads.

    ``step`` is the angle change the controller asks for, in degrees.  A real
    mouse gives a relative delta; the game converts it to degrees using the
    player's sensitivity.  The model applies the delta directly, which is what
    a mouse does, and optionally smooths it to emulate a low in-game
    sensitivity or a laggy frame.
    """

    def __init__(self, *, invert: bool = False, smoothing: float = 0.0) -> None:
        self.angle = 0.0
        self.invert = invert
        self.smoothing = max(0.0, min(1.0, smoothing))

    def apply(self, step_degrees: float, dt: float) -> float:
        if self.invert:
            step_degrees = -step_degrees
        if self.smoothing > 0.0:
            alpha = 1.0 - math.exp(-self.smoothing * dt)
            self.angle += step_degrees * alpha
        else:
            self.angle += step_degrees
        # The angle is a relative bearing; keep it in a sane range.
        if self.angle > 180.0:
            self.angle -= 360.0
        elif self.angle < -180.0:
            self.angle += 360.0
        return self.angle


@dataclass
class NuiView:
    """Exactly what the player sees in the NUI, nothing more."""

    danger: int = 0
    progress: int = 0
    side: str | None = None
    active: bool = False
    verdict: str | None = None

    def as_dict(self) -> dict:
        return {
            "danger": self.danger,
            "progress": self.progress,
            "side": self.side,
            "active": self.active,
            "verdict": self.verdict,
        }


class NuiModel:
    """Reproduces the NUI's two-stage filter.

    The Lua sends ``fishingStatus`` every 50 ms.  React then eases the raw
    values toward their targets at 9/s (progress) and 16/s (danger) on every
    animation frame.  A bot reading the DOM sees the eased integers, not the
    raw ones, so the controller must be designed against this lag.
    """

    def __init__(self, *, danger_rate: float = 16.0, progress_rate: float = 9.0,
                 raw_interval: float = FISHING_CONFIG["update_rate"] / 1000.0) -> None:
        self.danger_rate = danger_rate
        self.progress_rate = progress_rate
        self.raw_interval = raw_interval
        self.raw_danger = 0
        self.raw_progress = 0
        self.raw_side: str | None = None
        self.smooth_danger = 0.0
        self.smooth_progress = 0.0
        self._since_raw = 0.0
        self.verdict: str | None = None
        self.fight_active = False

    def reset(self) -> None:
        self.raw_danger = 0
        self.raw_progress = 0
        self.raw_side = None
        self.smooth_danger = 0.0
        self.smooth_progress = 0.0
        self._since_raw = 0.0
        self.verdict = None
        self.fight_active = False

    def update(self, engine: FightEngine, dt: float) -> None:
        st = engine.state
        self.fight_active = st.active
        self._since_raw += dt
        if self._since_raw >= self.raw_interval:
            self._since_raw = 0.0
            self.raw_danger = st.danger
            self.raw_progress = int(math.floor(st.progress * 100.0))
            self.raw_side = st.target_side
            if not st.active and st.outcome is not None:
                self.verdict = "success" if st.outcome == "success" else "fail"

        alpha_d = 1.0 - math.exp(-self.danger_rate * dt)
        alpha_p = 1.0 - math.exp(-self.progress_rate * dt)
        self.smooth_danger += (self.raw_danger - self.smooth_danger) * alpha_d
        self.smooth_progress += (self.raw_progress - self.smooth_progress) * alpha_p

    def read(self) -> NuiView:
        return NuiView(
            danger=int(round(self.smooth_danger)),
            progress=int(round(self.smooth_progress)),
            side=self.raw_side,
            active=self.fight_active,
            verdict=self.verdict,
        )
