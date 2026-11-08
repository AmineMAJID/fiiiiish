"""A faithful simulation of qs-fisher's reel mini-game.

This mirrors ``client/fishing.lua :: StartFishingFight`` line for line, because
the controller is tuned and regression-tested against it.  Two details are worth
stating plainly, since the whole approach rests on them:

1. **The mini-game has no mouse button to press.**  The only inputs it reads are
   the camera's yaw (through ``GetGameplayCamRot``) and the escape key.  You win
   by *turning the camera*, which is why the tool injects relative mouse motion
   and never clicks during a fight.

2. **The angle math cancels.**  The resource computes::

       camRot = GetGameplayCamRot(2).z              -- degrees
       atDeb  = math.deg(atan2(dy, dx))             -- degrees
       angle  = atDeb - math.rad(camRot)            -- WRONG by design
       diff   = math.deg(angle) - 90                -- so this *1/57.3 again

   ``rad`` then ``deg`` cancel inside the first line, so ``angle`` is in
   degrees, and the second ``math.deg`` divides it by 57.3 once.  The result is
   that a camera yaw of ``1/57.3`` degrees moves the danger by ``1`` unit: the
   response is 1:1 in the (already divided) units the game uses, and the
   controller gains below are measured in those units.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import Optional, Tuple

# ── constants copied from client/fishing.lua ────────────────────────────────
FISHING_CONFIG = {
    "MinBiteTime": 1500,
    "BiteWindow": 3000,
    "CastDistance": 10.0,
    "MinDistance": 2.0,
    "MaxAngle": 70.0,
    "DeadZone": 8.0,
    "PullSpeed": 0.025,
    "SlipSpeed": 0.005,
    "GainRate": 0.01,
    "UpdateRate": 50,
}

# ── constants copied from server/fishing.lua :: BuildFightParameters ────────
DEFAULT_MAX_ANGLE = 70.0
BASE_PULL_SPEED = 0.025
BASE_SLIP_SPEED = 0.005
MAX_FIGHT_EASE_PERCENT = 40
FIGHT_ANGLE_REDUCTION = 0.35
FIGHT_PULL_REDUCTION = 0.45
FIGHT_SLIP_MULTIPLIER = 2.2
FIGHT_TURN_MULTIPLIER = 0.5
FIGHT_SPECIMEN_QUALITY_SCALE = 0.15

# depth band -> base difficulty (Config.FightDifficulty.Tiers defaults)
TIER_BASE = {"shallow": 0.30, "mid": 0.50, "deep": 0.70, "abyss": 0.85}

CAM_RADIANS_TO_DANGER = 57.29577951308232  # 1 rad in degrees


@dataclass
class FightParams:
    max_angle: float = 70.0
    pull_speed: float = 0.025
    slip_speed: float = 0.005
    turn_rate: float = 1.0

    @staticmethod
    def from_difficulty(difficulty: float, line_strength: float = 0.0) -> "FightParams":
        d = max(0.0, min(1.0, difficulty))
        strength = 1.0 + line_strength / 100.0
        return FightParams(
            max_angle=DEFAULT_MAX_ANGLE * strength * (1.0 - FIGHT_ANGLE_REDUCTION * d),
            pull_speed=BASE_PULL_SPEED * (1.0 - FIGHT_PULL_REDUCTION * d),
            slip_speed=BASE_SLIP_SPEED * (1.0 + (FIGHT_SLIP_MULTIPLIER - 1.0) * d),
            turn_rate=1.0 + FIGHT_TURN_MULTIPLIER * d,
        )

    @staticmethod
    def for_band(band: str, quality: float = 0.5, fight_ease: float = 0.0,
                 line_strength: float = 0.0) -> "FightParams":
        base = TIER_BASE.get(band, 0.5)
        combined = max(0.0, min(base + quality * FIGHT_SPECIMEN_QUALITY_SCALE, 1.0))
        ease = max(0.0, min(fight_ease, MAX_FIGHT_EASE_PERCENT))
        return FightParams.from_difficulty(combined * (1.0 - ease / 100.0), line_strength)


@dataclass
class FightState:
    """Every variable ``StartFishingFight`` keeps in its closure."""

    params: FightParams
    initial_dist: float
    max_angle: float
    dead_zone: float = FISHING_CONFIG["DeadZone"]
    min_distance: float = FISHING_CONFIG["MinDistance"]
    gain_rate: float = FISHING_CONFIG["GainRate"]

    # camera state, in the game's own units
    danger: float = 0.0           # signed "angle", + means target is right
    target_side: Optional[str] = None
    tension: float = 0.0
    progress: float = 0.0
    current_dist: float = 0.0
    outcome: Optional[str] = None  # 'won' | 'lost_tension' | 'timeout'
    elapsed: float = 0.0

    rng: random.Random = field(default_factory=random.Random)

    def __post_init__(self) -> None:
        self.current_dist = self.initial_dist
        self._reroll(self.params.turn_rate)

    # ── the resource's internals ────────────────────────────────────────────
    def _reroll(self, turn_rate: float) -> None:
        self.random_duration = (self.rng.randint(50, 100) / 100.0) / turn_rate
        self.tension_decay = (self.rng.randint(10, 20) / 1000.0) * turn_rate

    @property
    def abs_angle(self) -> float:
        return abs(self.danger)

    @property
    def danger_pct(self) -> int:
        return int(math.floor((self.abs_angle / self.max_angle) * 100))

    def side_now(self) -> str:
        if self.danger > self.dead_zone:
            return "right"
        if self.danger < -self.dead_zone:
            return "left"
        return "center"

    # ── one iteration of the resource's loop ────────────────────────────────
    def step(self, dt: float, camera_delta_danger: float = 0.0) -> None:
        """Advance ``dt`` seconds.

        ``camera_delta_danger`` is how far the *player* turned the camera,
        expressed in the same units as ``danger`` (i.e. the number of danger
        points that turn is worth).  Turning the camera does not change the
        fish's position, it changes the player's aim, so it subtracts from the
        angle: positive delta = turn right = danger goes down.
        """
        if self.outcome is not None:
            return
        self.elapsed += dt
        self.danger -= camera_delta_danger

        if self.abs_angle > self.max_angle:
            self.outcome = "lost_tension"
            return

        side = self.side_now()
        if self.target_side is None and side != "center":
            self.target_side = "right" if side == "left" else "left"

        pulling = (side == self.target_side)
        if pulling:
            self.tension += (self.abs_angle / self.max_angle) * self.gain_rate
            if self.tension >= self.random_duration:
                self.target_side = "left" if self.target_side == "right" else "right"
                self.tension = 0.0
                self._reroll(self.params.turn_rate)
        else:
            self.tension = max(self.tension - self.tension_decay, 0.0)

        if pulling:
            self.current_dist -= (self.abs_angle / self.max_angle) * self.params.pull_speed
        else:
            self.current_dist += self.params.slip_speed
        self.current_dist = max(min(self.current_dist, self.initial_dist), self.min_distance)

        self.progress = max(0.0, min(
            (self.initial_dist - self.current_dist) / (self.initial_dist - self.min_distance), 1.0))
        if self.progress >= 1.0:
            self.outcome = "won"


class FightSimulator:
    """Runs a fight under a controller, at the game's 50 ms cadence.

    The real game runs its loop every frame (~16 ms) and only *publishes* the
    HUD every 50 ms, so 50 ms is the honest sampling rate for a vision-driven
    controller: it can never see more than five readings a second.
    """

    def __init__(self, params: FightParams, initial_dist: float = 10.0,
                 seed: Optional[int] = None, latency_ms: float = 45.0):
        self.state = FightState(params=params, initial_dist=initial_dist,
                                max_angle=params.max_angle,
                                rng=random.Random(seed))
        self.latency = latency_ms / 1000.0
        self._pending_camera = 0.0
        self.history = []

    def observe(self) -> Tuple[float, float, Optional[str], int]:
        """Exactly what the HUD would show this frame.

        The HUD's ``LINE_TENSION`` bar is ``danger`` (``|angle| / maxAngle``),
        **not** the internal ``tension`` accumulator that decides when the target
        flips - the two share a name in the Lua but are unrelated numbers.  The
        ``REEL_PROGRESS`` bar is ``progress``.  The lit chevron is the required
        ``side`` (``targetSide``).  Nothing else is published.

        Returns ``(line_tension 0..1, reel_progress 0..1, side or None,
        danger_pct for logging)``.
        """
        danger = max(0.0, min(1.0, self.state.abs_angle / self.state.max_angle))
        return (danger, self.state.progress, self.state.target_side,
                self.state.danger_pct)

    def apply_camera(self, delta_danger: float) -> None:
        """Queue a camera movement that will take effect after the latency."""
        self._pending_camera += delta_danger

    def tick(self, dt: float = 0.05) -> None:
        # camera motion that happened long enough ago is felt now
        felt = self._pending_camera
        self._pending_camera = 0.0
        # split the movement across the interval so a big swing does not
        # teleport the angle past the snap threshold
        steps = max(1, int(abs(felt) / 6.0) + 1)
        for _ in range(steps):
            self.state.step(dt / steps, felt / steps)
            if self.state.outcome:
                return


def cameras_per_degree(dpi: float = 800.0, sensitivity: float = 0.5,
                       degrees_per_180_counts: float = 6.096) -> float:
    """FiveM mouse units needed to swing the camera by one degree.

    FiveM reads raw mouse counts; at the in-game default the camera covers 180°
    in ``degrees_per_180_counts`` counts, scaled by DPI and (inverted)
    sensitivity.  The value is only a starting point: the tool calibrates the
    real number on the first fight by watching the tension bar, so a wrong guess
    costs one fight, not the session.
    """
    if dpi <= 0 or sensitivity <= 0:
        return 20.0
    return degrees_per_180_counts * dpi * sensitivity / 180.0
