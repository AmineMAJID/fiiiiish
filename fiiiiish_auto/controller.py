"""The auto-player: a closed-loop controller that only sees the NUI.

The controller never reads the game's internal angle.  It gets the same three
numbers a player sees on screen:

    danger   0..100  (how close the line is to snapping)
    progress 0..100
    side     "left" / "right" / None  (the side the NUI tells you to pull)

and returns a camera step in degrees.  That is enough to play the fight,
because the danger is a symmetric function of the angle: rotating toward the
requested side makes the danger fall to zero and then rise again.  The
controller uses that shape to find the requested side without ever knowing
the sign of the angle.

Design goals (the "precise, stable, reliable" part):

* no overshoot past the line limit: the setpoint is 80 % and an emergency
  lane steers back toward centre above 95 %;
* deterministic: same inputs -> same outputs, no timers or randomness;
* robust to the NUI's 20 Hz updates and its easing filter;
* robust to the target side flipping every 0.3-2 s;
* a reaction delay is modelled so a slow bot cannot pretend to be faster
  than it is.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass
from typing import Literal

from .config import (
    DEFAULT_DEADBAND,
    DEFAULT_EMERGENCY,
    DEFAULT_HOLD_GAIN,
    DEFAULT_HOLD_STEP,
    DEFAULT_MAX_STEP,
    DEFAULT_MIN_STEP,
    DEFAULT_REACTION_DELAY,
    DEFAULT_SETPOINT,
    DEFAULT_TRIGGER_STEP,
)
from .fight import NuiView, TargetSide

Mode = Literal["idle", "trigger", "cross", "hold", "safety"]


@dataclass
class ControlDecision:
    """One controller output."""

    step: float          # degrees, positive = right
    mode: Mode
    reason: str = ""


class FightController:
    """Steers the camera from the NUI view alone."""

    def __init__(
        self,
        *,
        setpoint: float = DEFAULT_SETPOINT,
        deadband: float = DEFAULT_DEADBAND,
        max_step: float = DEFAULT_MAX_STEP,
        hold_step: float = DEFAULT_HOLD_STEP,
        min_step: float = DEFAULT_MIN_STEP,
        hold_gain: float = DEFAULT_HOLD_GAIN,
        trigger_step: float = DEFAULT_TRIGGER_STEP,
        emergency: float = DEFAULT_EMERGENCY,
        reaction_delay: float = DEFAULT_REACTION_DELAY,
        trigger_direction: TargetSide = "right",
        cross_timeout: float = 1.2,
    ) -> None:
        if not 0.0 < setpoint < 100.0:
            raise ValueError("setpoint must be in (0, 100)")
        if not 0.0 < deadband < setpoint:
            raise ValueError("deadband must be in (0, setpoint)")
        if emergency <= setpoint:
            raise ValueError("emergency must be above setpoint")
        self.setpoint = float(setpoint)
        self.deadband = float(deadband)
        self.max_step = float(max_step)
        self.hold_step = float(hold_step)
        self.min_step = float(min_step)
        self.hold_gain = float(hold_gain)
        self.trigger_step = float(trigger_step)
        self.emergency = float(emergency)
        self.reaction_delay = max(0.0, float(reaction_delay))
        self.trigger_direction = trigger_direction
        self.cross_timeout = float(cross_timeout)

        self.mode: Mode = "idle"
        self.last_side: TargetSide | None = None
        self.cross_min = 0.0
        self.cross_start = 0.0
        self.side_history: deque[tuple[float, TargetSide | None]] = deque()
        self.decisions = 0
        self.side_flips_seen = 0
        self.last_reason = ""

    # ------------------------------------------------------------------
    def reset(self) -> None:
        self.mode = "idle"
        self.last_side = None
        self.cross_min = 0.0
        self.cross_start = 0.0
        self.side_history.clear()
        self.decisions = 0
        self.side_flips_seen = 0
        self.last_reason = ""

    # ------------------------------------------------------------------
    def _delayed_side(self, now: float) -> TargetSide | None:
        """Return the side as it was ``reaction_delay`` seconds ago."""
        if self.reaction_delay <= 0.0:
            return self.side_history[-1][1] if self.side_history else None
        cutoff = now - self.reaction_delay
        while len(self.side_history) > 1 and self.side_history[0][0] <= cutoff:
            self.side_history.popleft()
        return self.side_history[0][1] if self.side_history else None

    def _note_side(self, now: float, side: TargetSide | None) -> None:
        # Keep a short history; the delayed read is what the controller acts on.
        self.side_history.append((now, side))
        if len(self.side_history) > 64:
            self.side_history.popleft()

    # ------------------------------------------------------------------
    def tick(self, view: NuiView, dt: float, now: float) -> ControlDecision:
        """Compute one camera step.  ``dt`` is the control period in seconds."""
        self.decisions += 1

        if not view.active:
            self.mode = "idle"
            self.last_side = None
            self.side_history.clear()
            return ControlDecision(0.0, "idle", "fight not active")

        # The NUI's side is the *target* side.  It is only produced once the
        # player has pulled outside the dead zone, so the first move has to be
        # a blind trigger.  A small step is enough and cannot snap the line.
        if view.side is None:
            self._note_side(now, None)
            if self.mode != "trigger":
                self.mode = "trigger"
                self.last_reason = "waiting for the first side"
            if view.danger >= 30.0:
                return ControlDecision(0.0, "trigger", "trigger cap")
            direction = 1.0 if self.trigger_direction == "right" else -1.0
            return ControlDecision(direction * self.trigger_step, "trigger", self.last_reason)

        # React to a side change only after the configured delay.
        self._note_side(now, view.side)
        delayed = self._delayed_side(now)
        if delayed != self.last_side:
            if self.last_side is not None:
                self.side_flips_seen += 1
            self.last_side = delayed
            self.mode = "cross"
            self.cross_min = view.danger
            self.cross_start = now
            self.last_reason = f"side -> {delayed}"

        side = delayed
        if side is None:
            return ControlDecision(0.0, self.mode, "side not resolved")

        sign = 1.0 if side == "right" else -1.0

        # Emergency lane first: never let the line reach the snap point.
        if view.danger >= self.emergency:
            self.mode = "safety"
            step = -sign * self.hold_step
            self.last_reason = f"emergency {view.danger}%"
            return ControlDecision(step, "safety", self.last_reason)

        if self.mode == "safety" and view.danger < self.setpoint + self.deadband:
            self.mode = "hold"

        if self.mode == "cross":
            return self._cross(view, sign, now)

        return self._hold(view, sign)

    # ------------------------------------------------------------------
    def _cross(self, view: NuiView, sign: float, now: float) -> ControlDecision:
        """Cross the centre toward the newly requested side.

        The danger falls while the camera travels from the old side to the
        centre, reaches a minimum, then rises again on the new side.  We
        detect that minimum and hand over to the hold loop just before the
        setpoint.
        """
        self.cross_min = min(self.cross_min, view.danger)
        step = sign * self.max_step
        self.last_reason = f"crossing to {self.last_side} (min {self.cross_min:.0f}%)"

        if view.danger >= self.emergency:
            self.mode = "safety"
            return ControlDecision(-sign * self.hold_step, "safety", "emergency during cross")

        # The NUI eases the danger, so the displayed value trails the raw
        # angle.  As soon as the eased danger starts rising again we have
        # crossed the centre; hand over to the slow hold loop immediately.
        rising = view.danger > self.cross_min + 2.0
        if rising:
            self.mode = "hold"
            self.last_reason = "crossed, holding"
            return self._hold(view, sign)

        if now - self.cross_start > self.cross_timeout:
            self.mode = "hold"
            self.last_reason = "cross timeout"
            return self._hold(view, sign)

        return ControlDecision(step, "cross", self.last_reason)

    def _hold(self, view: NuiView, sign: float) -> ControlDecision:
        """Proportional hold around the setpoint on the requested side."""
        error = self.setpoint - view.danger

        if view.danger >= self.emergency:
            self.mode = "safety"
            return ControlDecision(-sign * self.hold_step, "safety", "emergency")

        if view.danger < 20.0:
            # We are near the centre; get back out to the requested side.
            step = sign * self.hold_step
            self.last_reason = "recovering from centre"
            return ControlDecision(step, "hold", self.last_reason)

        if abs(error) <= self.deadband:
            self.last_reason = f"holding {view.danger}%"
            return ControlDecision(0.0, "hold", self.last_reason)

        magnitude = min(self.hold_step, self.hold_gain * abs(error) + self.min_step)
        step = sign * (1.0 if error > 0 else -1.0) * magnitude
        self.last_reason = f"hold {view.danger}% -> {self.setpoint:.0f}%"
        return ControlDecision(step, "hold", self.last_reason)


class SideDelayBuffer:
    """Utility used by the live bot to emulate the controller's reaction lag."""

    def __init__(self, delay: float) -> None:
        self.delay = max(0.0, float(delay))
        self._buf: deque[tuple[float, TargetSide | None]] = deque()

    def push(self, now: float, side: TargetSide | None) -> None:
        self._buf.append((now, side))
        cutoff = now - self.delay
        while len(self._buf) > 1 and self._buf[0][0] <= cutoff:
            self._buf.popleft()

    def read(self, now: float) -> TargetSide | None:
        cutoff = now - self.delay
        while len(self._buf) > 1 and self._buf[0][0] <= cutoff:
            self._buf.popleft()
        return self._buf[0][1] if self._buf else None
