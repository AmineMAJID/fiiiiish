"""The decision layer: turning two bars into mouse counts.

What the resource actually asks of the player
---------------------------------------------
From ``StartFishingFight``:

* pulling is done with the **camera**, never a button (the only input read is
  ``GetGameplayCamRot().z``), so the tool sends relative mouse motion and never
  clicks during a fight;
* ``side`` is the sign of the camera offset, and ``targetSide`` is set once to
  the **opposite** of the first side observed, then flips every time the
  accumulated tension completes - so the fight is a square wave in the camera
  offset and the player has to keep crossing zero to the other side;
* ``isPullingCorrectly`` (``side == targetSide``) is the only state that shrinks
  the distance, and it shrinks **faster the larger the offset**, which is why a
  tight, high-amplitude square wave is the fastest honest way to land a fish;
* the line snaps the instant ``|offset| > maxAngle``.

Consequences for a bot
----------------------
1. Which physical mouse direction satisfies a given side cannot be assumed: it
   depends on the yaw convention, the player's inverted-axis setting and GTA's
   heading sign.  A bot with that hard-coded loses every fight on half the
   installs, so the mapping is **learned** here and remembered for the session.
2. Crossing zero must be a single fast swing.  Descending gently costs a full
   ramp on the way back - hundreds of milliseconds - and target flips come every
   600-1200 ms, so a gentle descent means never keeping up (this was measured:
   it wins 0 % of fights).
3. The reel bar is the ground truth for "am I correct": it rises only while
   ``side == targetSide`` and is flat or falling otherwise.  It needs no sign
   convention and it self-corrects every sample.

The result is a small state machine: build the offset, watch the reel, and when
the reel stops giving credit, swing hard through zero to the other side.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional

# The bar snaps at 100 % (``absAngle > maxAngle``), turns red at 82 %, and the
# dead zone (|angle| <= 8) is around 10-14 % of the bar for realistic rods.
SNAP_PCT = 100.0
CRITICAL_PCT = 82.0
DEADZONE_PCT = 12.0

PHASE_WARMUP = "warmup"
PHASE_BUILD = "build"
PHASE_PULL = "pull"
PHASE_ESCAPE = "escape"


@dataclass
class BotParams:
    counts_per_pct: float = 1.6
    """Mouse counts per one percent of the line-tension bar.

    The only machine-dependent constant in the tool: a function of the player's
    DPI and in-game sensitivity.  It is *measured* while playing from the
    response to known moves, and cached between sessions; the default is only
    the seed used for the very first swing.
    """

    target_pct: float = 82.0
    """Offset held while pulling.  Right in the upper band: the pull rate is
    proportional to the offset, and 80 leaves 20 points (about a fifth of a
    second of slip) before the snap."""

    probe_pct: float = 26.0
    """How far a first exploratory swing goes.  Past the dead zone, so a correct
    guess is credited immediately, and cheap to undo if it was wrong."""

    reverse_margin_pct: float = 44.0
    """How far past zero a corrective swing lands.  This is what makes a target
    flip cost a single sample instead of a full ramp."""

    deadband_pct: float = 5.0
    """Tension error tolerated before the camera is nudged again."""

    step_up_pct: float = 20.0
    """Largest increase of the bar aimed at in one 50 ms sample."""

    step_down_pct: float = 22.0

    safe_ceil_pct: float = 90.0
    """The bar is never *aimed* above this, in any branch.

    Because the controller knows how many counts it is sending and how many
    counts buy a percent, it can predict the bar's value at the next sample and
    refuse to command a move that would land above this line.  That turns "don't
    snap the line" from a tuning accident into an invariant, even when the
    reading is noisy or the calibration is slightly stale.
    """

    guard_pct: float = 94.0
    """Above this, all that matters is getting the bar down."""

    noise_margin_pct: float = 3.0
    """How much to distrust the bar.

    A pixel reader is accurate to a percent or two, and the bar itself animates,
    so the value we see can be slightly stale.  The cost of the two errors is
    wildly asymmetric - floating a little low only costs a fraction of a second,
    snapping the line costs the fish - so the controller filters the reading
    asymmetrically: it adds this margin before deciding it is *safe to push*, and
    subtracts nothing before deciding to *back off*.
    """

    warmup_ticks: int = 2
    """Samples to ignore at the very start, while the HUD settles on zero."""

    stall_ticks: int = 2
    """Samples without the reel rising before the side is presumed wrong.
    3 x 50 ms = 150 ms, so a flip costs about that much of the fight."""

    stall_epsilon_pct: float = 0.04
    """Reel movement smaller than this is rounding, not progress."""

    credit_pct: float = 0.4
    """The reel must have filled at least this much for us to believe we have
    ever been correct."""

    kp: float = 0.85
    ki: float = 0.10
    integral_limit_pct: float = 14.0

    probe_counts_start: float = 12.0
    """Mouse counts allowed in a single sample *before* the sensitivity is
    known.

    The first move of a session is the only one made blind: ``counts_per_pct``
    could be 0.3 (a very sensitive axis: 12 counts is already 40 % of the bar)
    or 12 (a slow one: 12 counts is 1 %, barely measurable).  Starting small and
    growing the budget when the bar does not move settles both cases without
    ever commanding a swing that a sensitive axis would turn into a snap.
    """

    probe_counts_max: float = 700.0
    """Ceiling for the growing probe budget, so a player whose bar genuinely does
    not move still gets past the dead zone instead of creeping forever."""

    probe_growth: float = 2.5
    """How much the budget grows after a move that was too small to measure."""

    max_reversals_per_second: float = 12.0
    """Safety net against thrashing on a noisy readout."""


@dataclass
class BotDecision:
    counts: int = 0
    reason: str = ""
    phase: str = PHASE_WARMUP
    tension_pct: float = 0.0
    progress_pct: float = 0.0
    direction: int = 1

    def __bool__(self) -> bool:
        return self.counts != 0


@dataclass
class FightController:
    params: BotParams = field(default_factory=BotParams)

    phase: str = PHASE_WARMUP
    direction: int = 1
    """Mouse sign currently used to *increase* the bar."""

    max_angle: float = 70.0
    ticks: int = 0
    reversals: int = 0

    # ── learned state ──────────────────────────────────────────────────────
    side_map: Dict[str, int] = field(default_factory=dict)
    """cue -> mouse sign that satisfies it.  Learned once, kept for the session:
    ``{'left': -1, 'right': 1}`` or its negation on an inverted client."""

    _integral: float = 0.0
    _last_pct: float = 0.0
    _last_progress: float = 0.0
    _stall: int = 0
    _credited_ever: bool = False
    _cue: Optional[str] = None
    _samples: list = field(default_factory=list)
    _sent: int = 0
    _sent_pct: float = 0.0
    _observed: int = 0
    _budget: float = 12.0
    _blind: int = 0
    log: list = field(default_factory=list)

    # ── lifecycle ----------------------------------------------------------
    def reset(self, max_angle: float = 70.0, direction: int = 1,
              keep_calibration: bool = True) -> None:
        self.max_angle = max(max_angle, 1.0)
        self.phase = PHASE_WARMUP
        self.direction = direction or 1
        self.ticks = 0
        self.reversals = 0
        self._integral = 0.0
        self._last_pct = 0.0
        self._last_progress = 0.0
        self._stall = 0
        self._credited_ever = False
        self._cue = None
        self._sent = 0
        if self._observed:
            self._budget = self.params.probe_counts_max
        else:
            self._budget = self.params.probe_counts_start
        if not keep_calibration:
            self.side_map.clear()
            self._samples.clear()
            self._observed = 0

    # ── the loop -----------------------------------------------------------
    def tick(self, tension: float, side: Optional[str], progress: float) -> BotDecision:
        """One HUD sample in, one mouse command out.

        ``tension``  the LINE TENSION bar, 0..1 (the game's ``danger``)
        ``side``     the lit chevron: the side that must be satisfied
        ``progress`` the REEL PROGRESS bar, 0..1
        """
        self.ticks += 1
        pct = max(0.0, min(1.0, tension)) * 100.0
        prog = max(0.0, min(1.0, progress)) * 100.0

        self._observe(pct)

        rising = (prog - self._last_progress) > self.params.stall_epsilon_pct
        self._stall = 0 if rising else self._stall + 1
        if prog >= self.params.credit_pct:
            self._credited_ever = True
        # The HUD publishes the *required* side (``targetSide``) every sample,
        # so a change means the target flipped right now - no need to wait for
        # the reel to stall and infer it.
        cue_flip = side is not None and self._cue is not None and side != self._cue
        if side is not None:
            self._cue = side

        p = self.params
        # pessimistic when pushing, optimistic when retreating
        high = min(100.0, pct + p.noise_margin_pct)
        decision = self._decide(pct, prog, rising, cue_flip, high=high)
        self._last_pct = pct
        self._last_progress = prog
        self._sent = decision.counts
        self._sent_pct = pct
        self.log.append(decision)
        if len(self.log) > 8192:
            del self.log[:4096]
        return decision

    # ── the state machine --------------------------------------------------
    def _decide(self, pct: float, prog: float, rising: bool,
                cue_flip: bool = False, high: float | None = None) -> BotDecision:
        p = self.params
        high = pct if high is None else high

        # (1) guard: the line is about to snap.  Crossing zero is always safe,
        #     because the bar only sees the *magnitude* of the offset.
        if high >= p.guard_pct:
            self.phase = PHASE_ESCAPE
            return self._swing(pct, "guard", prog)

        # (2) let the HUD settle on zero before the first move
        if self.ticks <= p.warmup_ticks and not self._credited_ever:
            return self._emit(0, "warmup", pct, prog)

        # (3) the sweep is complete and the reel still has not moved: we picked
        #     the wrong way round.  This is the game's own rule - the side we
        #     were on cannot be the one it wants.
        swept_and_empty = ((not self._credited_ever) and (not rising)
                           and pct >= p.target_pct * 0.9)

        # (4) the target flipped (the cue changed), or we were earning and the
        #     reel has stopped.  Either way the camera has to change sign.
        stalled = (self._credited_ever and self._stall >= p.stall_ticks
                   and pct > DEADZONE_PCT)
        if swept_and_empty or stalled or (cue_flip and self._credited_ever):
            return self._swing(pct, "flip", prog)

        # (4b) the bar is already close to the ceiling: do not push, let it ease
        if high >= p.safe_ceil_pct - p.noise_margin_pct:
            self.phase = PHASE_PULL
            return self._emit(0, "ceiling", pct, prog)

        # (5) below the dead zone the pull earns nothing: rebuild the offset
        if pct < DEADZONE_PCT:
            self.phase = PHASE_BUILD
            goal = min(p.target_pct, p.probe_pct + DEADZONE_PCT)
            step = max(1.0, min(goal - pct, p.step_up_pct))
            return self._emit(self.direction * self._counts(self._cap(pct, step)),
                              "build", pct, prog)

        # (6) in the band: hold the offset at the target
        self.phase = PHASE_PULL
        error = p.target_pct - pct
        if abs(error) <= p.deadband_pct:
            self._integral *= 0.9
            return self._emit(0, "hold", pct, prog)
        self._integral += error
        limit = p.integral_limit_pct
        self._integral = max(-limit, min(limit, self._integral))
        command = p.kp * error + p.ki * self._integral
        command = max(-p.step_down_pct, min(p.step_up_pct, command))
        counts = self._counts(abs(command) if command < 0 else self._cap(pct, command))
        return self._emit(self.direction * counts * (1 if command > 0 else -1),
                          "track", pct, prog)

    # ── helpers ------------------------------------------------------------
    def _swing(self, pct: float, reason: str, prog: float) -> BotDecision:
        """Cross zero in one go and land just past it on the other side.

        The bar is a magnitude, so subtracting ``pct + margin`` from the signed
        offset takes it down through zero and out to ``margin`` on the far side:
        the next sample already earns credit there.  Doing that in a single
        sample is what makes a target flip cheap - descending gently costs a
        whole rebuild, and flips arrive faster than a rebuild completes.
        """
        delta = self._cap(pct, pct + self.params.reverse_margin_pct)
        self._reverse()
        # after the reversal, `direction` is the sign that builds the bar on the
        # side we are moving *to*, which is exactly the way this swing must go.
        return self._emit(self.direction * self._counts(delta), reason, pct, prog)

    def _reverse(self) -> None:
        self.direction = -self.direction
        self.reversals += 1
        self._stall = 0
        self._integral = 0.0

    def _cap(self, pct: float, delta: float) -> float:
        """Clamp a *signed-offset* change so the bar cannot land above the ceiling.

        ``delta`` is how much of the signed camera offset the move is worth.  The
        bar only shows ``|offset|``, so the magnitude after the move is
        ``|delta - pct|`` when the move crosses zero and ``|pct ± delta|`` when it
        does not; both cases are bounded here.
        """
        ceil = self.params.safe_ceil_pct
        crossing = delta > pct
        if crossing:
            # land on the far side, but not further out than the ceiling
            return max(0.0, min(delta, pct + ceil))
        return max(0.0, min(delta, ceil - pct))

    def _counts(self, pct_delta: float) -> int:
        counts = max(1, int(round(abs(pct_delta) * self.params.counts_per_pct)))
        if not self.calibrated:
            # The estimate is still a seed, so the *counts* are the only thing
            # that can be trusted to be harmless: a blind big swing on a
            # sensitive axis snaps the line before it could ever be learned.
            counts = min(counts, max(1, int(round(self._budget))))
        return counts

    def _emit(self, counts: int, reason: str, pct: float, prog: float) -> BotDecision:
        return BotDecision(counts=int(counts), reason=reason, phase=self.phase,
                           tension_pct=pct, progress_pct=prog, direction=self.direction)

    # ── online calibration --------------------------------------------------
    def _observe(self, pct_now: float) -> None:
        """Learn ``counts_per_pct`` from the previous move.

        The bar is a magnitude, so a given mouse move raises it or lowers it
        depending on which side of the fish we are; only the absolute change is
        used, which makes the estimate independent of sign, of direction and of
        whether the player has an inverted axis.  A median over the session keeps
        one bad frame from moving the gain.
        """
        counts, before = self._sent, self._sent_pct
        self._sent = 0
        if not counts:
            return
        if before > 99.0 or pct_now > 99.0:
            # Censored: the bar was pinned against its end, so the real movement
            # may have been far larger than the reading shows.  Learning from it
            # would inflate ``counts_per_pct`` and make the next swing bigger.
            return
        delta = abs(pct_now - before)
        if delta < 1.2:
            # Nothing measurable happened: either the move was below the bar's
            # resolution or it happened on the far side of a zero crossing.
            # Grow the probe budget so the next blind move is not wasted too.
            if not self.calibrated:
                self._blind += 1
                limit = self.params.probe_counts_max
                self._budget = min(limit, self._budget * self.params.probe_growth)
            return
        sample = abs(counts) / delta
        if not (0.02 <= sample <= 400.0):
            return
        self._samples.append(sample)
        if len(self._samples) > 33:
            self._samples.pop(0)
        ordered = sorted(self._samples)
        self.params.counts_per_pct = ordered[len(ordered) // 2]
        self._observed += 1
        if self.calibrated:
            self._budget = self.params.probe_counts_max

    @property
    def calibrated(self) -> bool:
        return self._observed >= 3

    def force(self, phase: str, direction: int = 1) -> None:
        self.phase = phase
        self.direction = direction
        self._stall = 0
        self._integral = 0.0
