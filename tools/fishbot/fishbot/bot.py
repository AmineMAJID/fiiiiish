"""The full fishing loop: cast, strike, reel, keep, repeat.

The resource's own flow, and where each step is triggered
--------------------------------------------------------
============================  ==============================================
step                          trigger in ``client/fishing.lua``
============================  ==============================================
cast (charge + release)       press E while the depth meter says ``canCast``;
                              charge is the *left mouse button*, held and
                              released, and ``power`` is the only thing that
                              decides distance
wait for a bite               the buoy HUD appears; the ``E`` prompt and the
                              countdown ring show the ~3 s strike window
strike                        press E inside the window (``IsControlJustPressed(38)``)
reel                          camera only - see ``controller.py``
keep / release                click KEEP or RELEASE in the catch modal
============================  ==============================================

The bot is a state machine over those five steps.  It is deliberately
conservative: if a step's evidence does not appear within its timeout, it goes
back to WAITING and tries again rather than firing blind, because a stray E in
the middle of a reel aborts the cast and a stray click is a wasted bait.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Callable, Optional

from . import vision
from .controller import FightController
from .geometry import cast_layout, catch_modal_layout

# ── states ──────────────────────────────────────────────────────────────────
WAITING = "waiting"        # rod is out, looking for the depth card / water
CASTING = "casting"        # holding and releasing the left button
BITE_WAIT = "bite_wait"    # line is out, waiting for the buoy HUD
BITE_READY = "bite_ready"  # the bite is live: strike now
FIGHT = "fight"            # reeling
SETTLE = "settle"          # fish landed, waiting for the catch modal / showcase
DECISION = "decision"      # the KEEP / RELEASE modal is up
PAUSED = "paused"          # bag full / user paused: waiting for the user
STOPPED = "stopped"


@dataclass
class BotConfig:
    # ── timing (seconds) ───────────────────────────────────────────────────
    loop_hz: float = 20.0
    """Samples per second.  The HUD itself only publishes every 50 ms, so
    anything above ~20 Hz is wasted CPU with no extra information."""

    equip_delay: float = 0.12
    """Pause between pressing E and starting to charge, so the resource's charge
    animation (and its ``BeginCast`` event) has started before the button goes
    down."""

    cast_hold: float = 0.62
    """How long to hold the left button while charging.

    The meter sweeps 0->100 % over 1.1 s and back, so this lands near the top of
    the first sweep.  Power decides both distance and the size of the fish, and
    anything below 5 % is refused by the server (``MIN_CAST_POWER``).
    """

    cast_settle: float = 0.9
    """Give the cast animation and line flight time before looking for a bite."""

    bite_timeout: float = 25.0
    strike_delay: float = 0.10
    """A small human-like delay after the bite appears, well inside the 3 s
    window (``FishingConfig.BiteWindow``)."""

    fight_grace: float = 1.2
    """Seconds at the start of a fight during which an empty HUD is ignored.

    The reel HUD is only *evidence* once it has something to say: for the first
    frames the tension bar is at zero, progress has not moved, and the game has
    not picked a side yet, so a reader that answers "no HUD" is telling the
    truth about a fight that has certainly started.
    """

    fight_lost_ticks: int = 3
    """Consecutive empty samples before a *known-running* fight is called over.
    Three at 20 Hz is 150 ms: long enough not to trip on a dropped frame, short
    enough that the fish is not re-cast for."""

    fight_timeout: float = 75.0
    """A fight that runs longer than this is stuck; abort by re-casting."""

    settle_timeout: float = 4.0
    """How long to wait for the catch modal after the reel completes."""

    post_decision_delay: float = 0.8
    """After clicking KEEP the catch is resolved; only the card's fade-out is
    left.  Waiting the full ``settle_timeout`` there would add seconds of idle
    time to every single fish."""

    decision_timeout: float = 8.0
    """The modal itself expires after 9 s (``Config.CatchDecision.Timeout``)."""

    # ── behaviour ──────────────────────────────────────────────────────────
    keep: bool = True
    """KEEP fills the bag, which is what a seller wants; RELEASE pays more XP
    and never fills it.  Either way the tool reacts to an "inventory full" toast
    by pausing and calling the user back."""

    pause_on_error_toast: bool = True
    """A red toast during a keep means the bag refused the fish.  Rather than
    guessing, the tool stops, beeps, and waits for the user to sell and resume."""

    keep_click_delay: float = 0.35
    """Let the modal render (and the user see it) before clicking."""

    idle_before_cast: float = 0.6
    """Seconds of "nothing on screen" tolerated before casting.

    Every friendly HUD (bite buoy, power card, catch modal, error toast) shows
    up within a few hundred ms of the key press that starts it, so a screen
    that stays empty for this long means the loop really is idle.  Waiting the
    edge out prevents double-casting straight through a HUD that has not been
    drawn yet.
    """

    idle_ticks: int = 6
    """Idle *samples* required as well, so a capture that reports the same
    timestamp twice never fires a second cast."""

    # ── safety ─────────────────────────────────────────────────────────────
    max_cycles: int = 0
    """0 = unlimited."""

    stop_on_fight_stuck: bool = True


@dataclass
class BotStatus:
    state: str = WAITING
    cycles: int = 0
    fish_kept: int = 0
    fish_released: int = 0
    fights_won: int = 0
    fights_lost: int = 0
    casts: int = 0
    started_at: float = 0.0
    last_event: str = ""
    last_note: str = ""
    paused_reason: str = ""

    @property
    def uptime(self) -> float:
        return max(0.0, time.time() - self.started_at) if self.started_at else 0.0

    def summary(self) -> str:
        fish = self.fish_kept + self.fish_released
        rate = (fish / self.uptime * 3600.0) if self.uptime > 30 else 0.0
        return (f"{self.state:<11} casts={self.casts:<3} landed={fish:<3} "
                f"(kept {self.fish_kept}, released {self.fish_released}) "
                f"fights {self.fights_won}W/{self.fights_lost}L "
                f"rate={rate:.0f}/h")


class FishingBot:
    """Drives one fishing session.

    ``source`` supplies frames, ``injector`` sends input, ``notify`` is called
    with human-readable events.  The three are injected so the whole state
    machine can be exercised headlessly with the synthetic HUD.
    """

    def __init__(self, source, injector, config: Optional[BotConfig] = None,
                 controller: Optional[FightController] = None,
                 notify: Optional[Callable[[str, str], None]] = None,
                 clock: Optional[Callable[[], float]] = None,
                 sleep: Optional[Callable[[float], None]] = None):
        self.source = source
        self.injector = injector
        self.config = config or BotConfig()
        self.controller = controller or FightController()
        self.notify = notify or (lambda level, msg: None)

        # Both clocks are injectable: the end-to-end tests run the whole loop
        # against a simulated one, so nothing may sleep in real time.  The
        # source's own clock wins when it has one (a capture reports the time
        # the frame was taken, which is what every timeout should be measured
        # against).
        if clock is not None:
            self.clock: Callable[[], float] = clock
        else:
            # A capture source knows when its frames were taken; anything else
            # falls back to the wall clock.
            source_now = getattr(source, "now", None)
            self.clock = source_now if callable(source_now) else time.time
        self.sleep: Callable[[float], None] = sleep or time.sleep

        self.status = BotStatus()
        self._state_since = 0.0
        self._stop = False
        self._pause = False
        self._state = WAITING
        self._frame = None
        self._last_reading = None
        self._events = []
        self._idle_since: Optional[float] = None
        self._idle_ticks = 0
        self._awaiting_fight = False
        self._fight_ticks = 0
        self._missing_ticks = 0
        self._fight_seen = False
        self._settle_limit = 0.0
        self._decided_for: Optional[float] = None

    # ── control ------------------------------------------------------------
    def stop(self) -> None:
        self._stop = True

    def pause(self, reason: str = "user") -> None:
        self._pause = True
        self.status.paused_reason = reason

    def resume(self) -> None:
        self._pause = False
        self.status.paused_reason = ""

    @property
    def stopped(self) -> bool:
        return self._stop

    @property
    def last_frame(self):
        """The most recent captured frame, or None before the first sample."""
        return self._frame

    @property
    def paused(self) -> bool:
        return self._pause

    # ── state helpers ------------------------------------------------------
    def _go(self, state: str, note: str = "") -> None:
        if state != self._state:
            self._events.append((self.clock(), self._state, state))
            self._state = state
            self.status.state = state
            self._state_since = self.clock()
            if note:
                self.status.last_note = note

    def _elapsed(self) -> float:
        return self.clock() - self._state_since

    def _sleep(self, seconds: float) -> None:
        """Sleep in whatever clock the bot is running on.

        Nothing here may call ``time.sleep`` directly: the end-to-end tests run
        the whole loop against a simulated clock, and a real sleep would both
        stall the test and desynchronise the state timeouts from the game.
        """
        if seconds <= 0:
            return
        before = self.clock()
        self.sleep(seconds)
        if self.clock() - before < seconds * 0.5:
            # The injected sleep did not move the clock.  Move it for it, and
            # keep the state timestamps consistent with that jump.
            self._state_since += seconds
            if self._idle_since is not None:
                self._idle_since += seconds

    def _event(self, level: str, msg: str) -> None:
        self.status.last_event = msg
        self.notify(level, msg)

    # ── the main step ------------------------------------------------------
    def step(self) -> None:
        """Acquire one frame and advance the state machine by one sample."""
        if self._stop:
            self._go(STOPPED)
            return

        if self._pause:
            if self._state != PAUSED:
                self._go(PAUSED, self.status.paused_reason)
            return

        if self._state == PAUSED:
            # Only the capture is trusted while paused: drop the frame in hand
            # so the resume does not act on a screen from before the break.
            self._frame = None
            self._last_reading = None
            self._go(WAITING, "resumed")
            return

        try:
            frame = self.source.grab()
        except Exception as exc:  # capture failures must not kill the loop
            self._event("error", f"capture failed: {exc}")
            self._sleep(0.5)
            return
        self._frame = frame
        self.check_toasts(frame)

        handler = getattr(self, f"_on_{self._state}", None)
        if handler is None:
            self._go(WAITING)
            return
        handler(frame)

        if self.config.max_cycles and self.status.cycles >= self.config.max_cycles:
            self._event("info", "cycle limit reached")
            self.stop()
            self._go(STOPPED)

    # ── states -------------------------------------------------------------
    def _on_waiting(self, frame) -> None:
        """Rod is out; cast as soon as the screen says nothing else is happening.

        "Nothing is happening" has to be established positively.  The HUD's
        elements (power card, bite buoy, catch modal, toast) appear as soon as
        the action that draws them starts, so anything on screen means some
        part of the loop is still in flight and pressing E would either cancel
        a cast or fire into a reel.  Only after the screen has been empty for
        ``idle_before_cast`` does the bot commit.
        """
        cast = vision.read_cast(frame)
        if cast.present:
            # The power card is only drawn while a cast is being held charged,
            # so if it is up a cast is already in progress: wait it out.
            self._idle_since = None
            self._idle_ticks = 0
            if self._elapsed() > 2.0:
                self._go(CASTING)
            return

        # `read_bite(...).present` is only "the buoy floats somewhere" - the
        # water itself carries enough colour to trip it - so the honest "the
        # line is in the water" signal here is the countdown ring, which is
        # painted across the strike window and nowhere else.
        busy = (vision.read_bite(frame).biting
                or vision.read_catch_modal(frame).present
                or vision.read_fight(frame).present
                or vision.read_error_toast(frame))
        if busy:
            self._idle_since = None
            self._idle_ticks = 0
            # A reel HUD that simply stays there - the bot was started in the
            # middle of a fight, or a previous one was abandoned - is a fish the
            # user already hooked.  Pick it up rather than leaving the loop
            # parked on it forever.
            if vision.read_fight(frame).present:
                self._fight_ticks += 1
                if self._fight_ticks >= self.config.idle_ticks:
                    self._enter_fight(vision.read_fight(frame))
            else:
                self._fight_ticks = 0
            return
        self._fight_ticks = 0

        now = self.clock()
        if self._idle_since is None:
            self._idle_since = now
            self._idle_ticks = 0
            return
        self._idle_ticks += 1
        if (now - self._idle_since >= self.config.idle_before_cast
                and self._idle_ticks >= self.config.idle_ticks):
            self._idle_since = None
            self._idle_ticks = 0
            self._cast()

    def _cast(self) -> None:
        cfg = self.config
        self.injector.key("e")
        self.status.casts += 1
        self._sleep(cfg.equip_delay)  # let the script arm the charge
        self.injector.mouse_down("left")
        self._sleep(cfg.cast_hold)   # charge: the meter is only live while held
        self.injector.mouse_up("left")
        self._go(BITE_WAIT, "cast sent")
        self._event("info", f"cast #{self.status.casts}")

    def _on_casting(self, frame) -> None:
        cast = vision.read_cast(frame)
        if not cast.present or cast.power <= 0.0:
            # the card closed: the cast happened (or was refused)
            self._go(BITE_WAIT)
            return
        if self._elapsed() > 6.0:
            self._go(WAITING, "cast card would not clear")

    def _on_bite_wait(self, frame) -> None:
        if self._elapsed() > self.config.bite_timeout:
            self._go(WAITING, "no bite, re-casting")
            self._event("warn", "no bite within timeout - re-casting")
            return
        bite = vision.read_bite(frame)
        if bite.biting:
            self._go(BITE_READY, "bite!")
            self._event("info", "bite - striking")

    def _on_bite_ready(self, frame) -> None:
        bite = vision.read_bite(frame)
        if not bite.biting:
            # the window closed before we struck: re-cast
            self._go(WAITING, "missed the strike window")
            self._event("warn", "strike window missed")
            return
        self._sleep(self.config.strike_delay)
        self.injector.key("e")
        # The frame in hand was captured *before* the strike, so it cannot show
        # the reel HUD yet: hand over to SETTLE, which waits for that HUD (or
        # for the catch modal, if the fish was landed in one pull).
        self._awaiting_fight = True
        self._settle_limit = self.config.settle_timeout
        self._go(SETTLE, "struck")

    def _enter_fight(self, reading) -> None:
        self.controller.reset(max_angle=70.0)
        self._awaiting_fight = False
        self._fight_ticks = 0
        self._missing_ticks = 0
        self._fight_seen = False
        self._settle_limit = 0.0
        self._go(FIGHT, "reeling")
        self._last_reading = reading
        self._event("info", "hooked - reeling")

    def _on_fight(self, frame) -> None:
        reading = vision.read_fight(frame)
        if not reading.present:
            # An empty screen is not evidence that a fight *ended* - it is the
            # normal state of a fight that has just *started*: the tension bar
            # is at zero, the reel has not moved and the game has not picked a
            # side yet.  Only the loss of a HUD we had already seen means over.
            self._missing_ticks += 1
            if not self._fight_seen:
                if self._elapsed() < self.config.fight_grace:
                    # Nothing to read yet, but the fish is on: nudge the camera
                    # so the fight has something to show.  This is what turns an
                    # unreadable first frame into the very next readable one.
                    self._drive(0.0, None, 0.0)
                    return
                self._event("warn", "no reeling HUD after the strike")
                self._settle_limit = min(1.5, self.config.settle_timeout)
                self._go(SETTLE, "strike did not connect")
                return
            if self._missing_ticks < self.config.fight_lost_ticks:
                return
            won = self._last_reading is not None and self._last_reading.progress > 0.97
            if won:
                self.status.fights_won += 1
                self._event("success", "fish landed")
            else:
                self.status.fights_lost += 1
                self._event("warn", "the fish got away")
            self._settle_limit = self.config.settle_timeout
            self._go(SETTLE)
            return
        self._missing_ticks = 0
        self._fight_seen = True
        if self._elapsed() > self.config.fight_timeout:
            self.status.fights_lost += 1
            self._event("error", "fight timed out - aborting the cast")
            self._go(WAITING, "fight stuck")
            if self.config.stop_on_fight_stuck:
                self.stop()
            return

        self._drive(reading.tension, reading.side, reading.progress)
        self._last_reading = reading

    def _drive(self, tension: float, side, progress: float) -> None:
        """One controller sample -> one relative mouse move."""
        decision = self.controller.tick(tension=tension, side=side, progress=progress)
        if not decision.counts:
            return
        try:
            self.injector.move_relative(decision.counts, 0)
        except RuntimeError as exc:
            self.pause(f"input refused: {exc}")

    def _on_settle(self, frame) -> None:
        """Between the strike and the catch modal.

        Two different things are being waited for here: right after the strike
        the reel HUD appears (the fish is on), and right after the reel the
        showcase camera plays and the catch modal appears
        (``StartCatchShowcase`` + ``OpenCatchDecisionModal``).
        """
        if self._awaiting_fight:
            reading = vision.read_fight(frame)
            if reading.present:
                self._enter_fight(reading)
                return
        modal = vision.read_catch_modal(frame)
        if modal.present:
            self._decided_for = None
            self._go(DECISION)
            return
        if self._elapsed() > (self._settle_limit or self.config.settle_timeout):
            # No modal: either the catch was auto-kept (decision disabled) or
            # the showcase is still running.  Either way, fish again.
            self._awaiting_fight = False
            self.status.cycles += 1
            self._go(WAITING, "no modal")
            self._event("info", "catch settled")

    def _on_decision(self, frame) -> None:
        modal = vision.read_catch_modal(frame)
        if not modal.present:
            self._decided_for = None
            if self._elapsed() > 1.0:
                self._go(WAITING, "modal closed")
            return
        if self._decided_for is not None and self._decided_for == self._state_since:
            # Already clicked this modal: the frame in hand predates the click
            # (a capture is a snapshot, not the live screen), so re-reading it
            # would spend a second bait on the same fish.
            return
        if self._elapsed() < self.config.keep_click_delay:
            return
        target = modal.keep_rect if self.config.keep else modal.release_rect
        if target is None:
            self._go(WAITING)
            return
        try:
            self.injector.click(*self.source.to_screen(target.cx, target.cy))
        except RuntimeError as exc:
            self.pause(f"click refused: {exc}")
            return
        if self.config.keep:
            self.status.fish_kept += 1
        else:
            self.status.fish_released += 1
        self.status.cycles += 1
        self._decided_for = self._state_since
        self._event("success", "kept the fish" if self.config.keep else "released the fish")
        self._awaiting_fight = False
        self._settle_limit = self.config.post_decision_delay
        self._go(SETTLE, "decided")

    # ── pause on a full bag ------------------------------------------------
    def check_toasts(self, frame) -> None:
        """Called by the runner in every state: a red toast usually means the
        inventory refused the last fish (``NOTIFY_INVENTORY_FULL``), which is the
        one thing the tool must not try to work around by itself."""
        if not self.config.pause_on_error_toast:
            return
        if vision.read_error_toast(frame):
            if not self._pause:
                self.pause("error toast: bag full or action refused")
                self._event("error", "paused - clear your inventory, then resume")


