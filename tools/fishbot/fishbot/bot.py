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

    interact_key: str = "e"
    """The key the resource listens for (``Config.Keys.InteractKey``, control 38:
    E by default).  Change it if your server rebinds the interaction key."""

    equip_delay: float = 0.12
    """Pause between pressing E and starting to charge, so the resource's charge
    animation (and its ``BeginCast`` event) has started before the button goes
    down."""

    cast_hold: float = 1.05
    """How long to hold the left button while charging.

    ``ChargeCastPower`` sweeps the meter 0->100 % over ``CHARGE_ANIM_DURATION``
    (1.1 s) and back, and breaks the moment the button is released.  Stopping a
    hair before the peak (~95 %) rather than exactly on it keeps a slow frame
    from sampling the *descending* half, which would throw the cast short.  Full power casts furthest and hooks
    the biggest fish; anything under 5 % is refused by the server
    (``MIN_CAST_POWER``), and the charge itself expires after
    ``CAST_MAX_TIME`` (6 s).
    """

    power_sweep: float = 1.1
    """``CHARGE_ANIM_DURATION`` / 1000: the meter's 0->100 % sweep time."""

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
    """A red notification card means an action was refused.  Rather than
    guessing which one, the tool stops, beeps, and lets the player read the
    message and decide - fixing a full bag, a broken rod or a bad spot are all
    the same "you, not me" situation."""

    toast_grace: float = 1.5
    """How long a red card must stay faded-in before it counts (seconds).

    The card slides in from the left over ~350 ms, so during the first frames
    only part of it is where the reader looks.  Requiring it to still be there
    a moment later costs nothing - the card lives 5 s - and rejects the one-frame
    red flash of a screen-space effect caught mid-transition."""

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

    require_cast_gate: bool = True
    """Only press E when the depth card's action key is green.

    The resource refuses a cast when the water probe fails, when the player is
    in a vehicle or near the job ped, or when the water is deeper than the rod
    allows - and in all of those cases the action key is drawn slate grey with
    the reason beside it instead of green.  Casting on grey spends an E and
    gains nothing, so the green key is the trigger.
    """

    gate_grace: float = 2.5
    """After the previous catch, how long the gate is given to come back before
    the bot falls back to "the screen looks idle, cast anyway".  The depth card
    is only redrawn when its contents change, so it can lag the catch card."""

    gate_wait_log: float = 12.0
    """Kept for compatibility: the wait is now reported by :meth:`gripes` from
    the first second, in the status line and once as an event."""
    """How long to wait on a blocked/absent gate before telling the user why."""

    idle_ticks: int = 6
    """Idle *samples* required as well, so a capture that reports the same
    timestamp twice never fires a second cast."""

    # ── safety ─────────────────────────────────────────────────────────────
    max_cycles: int = 0
    """0 = unlimited."""

    stop_on_fight_stuck: bool = True

    stop_if_unfocused: bool = False
    """Spend the sample waiting when the injector refuses to send?  Off.

    Off because "the focus is not where I think it is" must never turn into a
    bot that reads a frozen screen and presses nothing: that is indistinguishable
    from a broken tool, and it is exactly the report this default answers.  The
    refusal is printed and the readings continue, so the log says *why* nothing
    happens instead of showing a silent, healthy-looking loop."""


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
    now: Optional[Callable[[], float]] = None
    """The clock to measure uptime with; the bot points this at its own, so a
    simulated session reports simulated seconds."""

    @property
    def uptime(self) -> float:
        clock = self.now or time.time
        return max(0.0, clock() - self.started_at)

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
        self.status.now = self.clock          # uptime is measured on our clock
        self.status.started_at = self.clock()
        self._state_since = self.clock()
        self._stop = False
        self._pause = False
        self._state = WAITING
        self._frame = None
        self._last_reading = None
        self._events = []
        self._idle_since: Optional[float] = None
        self._gate_since: Optional[float] = None
        self._gate_warned = False
        self._idle_ticks = 0
        self._awaiting_fight = False
        self._fight_ticks = 0
        self._missing_ticks = 0
        self._fight_seen = False
        self._settle_limit = 0.0
        self._decided_for: Optional[float] = None
        self._toast_since: Optional[float] = None
        self._toast_slot: Optional[int] = None
        self._toast_reason: str = ""
        self._toast_mute = False
        self._last_gate = None
        self._bad_frames = 0
        self._last_note = ""
        self._last_error = ""

    # ── control ------------------------------------------------------------
    def stop(self) -> None:
        self._stop = True

    def pause(self, reason: str = "user") -> None:
        self._pause = True
        self.status.paused_reason = reason

    def resume(self) -> None:
        self._pause = False
        self.status.paused_reason = ""
        # A card stays on screen for 5 s.  Resuming while the one that stopped
        # the bot is still fading out must not bounce straight back into a
        # pause: the player has read it and said "go", so that card is spent.
        # A *new* card (one drawn after the card leaves the screen) still stops
        # it, which is what matters.
        self._toast_mute = self._toast_since is not None
        # ...and the same for the cast gate: the player may have fixed the depth
        # or moved out of the vehicle while it was paused, so start the wait
        # fresh instead of reporting "waiting 47 s" the moment it resumes.
        self._gate_since = None

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

        # The injector refuses to send input to a window that is not focused -
        # that guard is the reason a keystroke cannot land in somebody's chat
        # window, and it is worth keeping.  What is *not* acceptable is going
        # quiet because of it: if the tool is looking at the wrong window (a
        # false match on the title, a launcher, a splash screen), "nothing
        # happens at all" is the one answer that cannot be debugged.  So the
        # refusal is reported as an event and the loop keeps reading the screen:
        # the readings are still informative, and the moment the focus comes
        # back the next press works.
        if not self._can_send():
            note = self._injector_error()
            self._last_note = note
            if note and note != self._last_error:
                self._last_error = note
                self._event("error", f"input refused: {note}")
            if self.config.stop_if_unfocused:
                return

        # Everything else is a reading, and a reading is untrustworthy when the
        # picture is not the game: a black frame, or a shrunk window, turns a
        # missing HUD into "the screen is empty", which casts, strikes and gets
        # the loop out of step with the game.
        if self._capture_unusable(frame):
            return

        handler = getattr(self, f"_on_{self._state}", None)
        if handler is None:
            self._go(WAITING)
            return
        try:
            handler(frame)
        except RuntimeError as exc:
            # The injector refuses to send into an unfocused window, and it is
            # right to: the event would land in whatever the player is looking
            # at.  What must not happen is the exception escaping and killing
            # the loop - that turns "the game lost the focus" into "the program
            # crashed", which is indistinguishable from a broken tool.
            # One line about one situation: the guard above already reports
            # *why* the focus is wrong, once.  Here it only has to stop.
            self.pause("input refused - the game lost the focus")
            self._last_note = "the game lost the focus mid-action; click it once"

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

        # The green action key is the game saying "go"; anything else is it
        # saying no, and no amount of E will change that.
        if self.config.require_cast_gate:
            gate = vision.read_cast_gate(frame)
            self._last_gate = gate
            if not gate.ready:
                if self._gate_since is None:
                    self._gate_since = now
                    self._gate_warned = False
                waited = now - self._gate_since
                # The card lags a couple of seconds behind the end of a catch,
                # so the first cast after a fish may not see it yet; after that,
                # insist - and if it never comes, say why instead of casting at
                # nothing for ever.
                if waited < self.config.gate_grace:
                    return
                # The reason is reported by ``gripes()`` (once, from the runner):
                # repeating it here as well was two messages for one wait.
                return
            self._gate_since = None

        if (now - self._idle_since >= self.config.idle_before_cast
                and self._idle_ticks >= self.config.idle_ticks):
            self._idle_since = None
            self._idle_ticks = 0
            self._cast()

    def _cast(self) -> None:
        """Press E, hold the button, let go.

        ``ChargeCastPower`` starts the charge on E and cancels the whole cast if
        E comes back up before the button does, so E is held down for the charge
        rather than tapped - a tap would work only by accident, and would fail
        the moment the charge lasted longer than the tap.
        """
        cfg = self.config
        self.injector.key_down(cfg.interact_key)
        self.status.casts += 1
        try:
            self._sleep(cfg.equip_delay)  # let the script arm the charge
            self.injector.mouse_down("left")
            self._sleep(cfg.cast_hold)    # the meter is only live while held
            self.injector.mouse_up("left")
        finally:
            self.injector.key_up(cfg.interact_key)
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
        self.injector.key(self.config.interact_key)
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

    def _injector_error(self) -> str:
        """Why would the next event be refused?  '' when it would not be."""
        explain = getattr(self.injector, "explain", None)
        if callable(explain):
            try:
                return str(explain())
            except Exception as exc:
                return f"{exc}"
        return "" if self._can_send() else "the game window does not have the focus"

    def _can_send(self) -> bool:
        """Would an event sent right now reach the game?"""
        gate = getattr(self.injector, "foreground_ok", None)
        if gate is not None:
            try:
                return bool(gate())
            except Exception:
                return True
        # No gate on the injector (a stand-in): ask the *source*, which is what
        # knows which window the picture came from.
        focus = getattr(self.source, "focus", None)
        state = getattr(focus, "state", None)
        return state in (None, "game", "unknown")

    def _capture_unusable(self, frame) -> bool:
        """Is this frame clearly *not* the game's picture?"""
        import numpy as _np
        if float(frame.arr.max()) < 8:
            self._bad_frames += 1
            if self._bad_frames == 40:
                self._event("warn", "the capture is black - the game is not drawing "
                                    "where its window is (switch it to borderless)")
            return True
        if _np.asarray(frame.viewport)[0] < 320 or _np.asarray(frame.viewport)[1] < 200:
            self._bad_frames += 1
            return True
        self._bad_frames = 0
        return False

    def diagnose(self) -> str:
        """The one thing standing in the way, for the status line.  '' = nothing.

        The status line is printed every three seconds whether or not anything
        is happening, so it is the right place for "why nothing is happening":
        the player reads one line per interval, not a wall of messages.
        """
        gripes = self.gripes()
        return gripes[0][1] if gripes else ""

    def gripes(self) -> list:
        """``(key, text)`` for everything currently standing in the way.

        Empty means "if nothing is happening, it is the game, not me".  The
        runner prints these while the bot sits idle, because "nothing happens"
        is the least debuggable state a tool has, and the honest answer is
        almost always one of these.

        The key is stable while the situation is (``gate-missing``, ``paused``),
        so the caller can say the same thing once instead of every few seconds -
        and so a beep only happens when something *new* is wrong.
        """
        out = []
        if self._last_note:
            out.append(("focus", f"input refused: {self._last_note}"
                         if self._last_note else self._last_note))
        if self._pause:
            reason = self.status.paused_reason or "paused"
            out.append(("paused", f"paused ({reason}) - F9 resumes"))
        if not self._gate_since:
            return out
        waited = self.clock() - self._gate_since
        if waited < 1.0:
            return out
        gate = self._last_gate
        if gate is None or not gate.present:
            out.append(("gate-missing",
                        f"waiting {waited:.0f} s: the depth card is not on screen - the "
                        "rod must be out, and there must be water in front of you"))
        elif gate.blocked:
            out.append(("gate-blocked",
                        f"waiting {waited:.0f} s: the cast prompt is greyed out - the game "
                        "refuses the cast (too deep, in a vehicle, or no water?)"))
        else:
            out.append(("gate-notready",
                        f"waiting {waited:.0f} s for the cast prompt to turn green "
                        f"(card {gate.card:.2f}, no green key yet)"))
        return out

    # ── pause on a refusal ------------------------------------------------
    def check_toasts(self, frame) -> None:
        """Stop when the resource puts a red card on screen.

        Called in every state.  What it reacts to is the *card*, not a guess
        about the bag: the resource paints exactly one red card for ``BAG_FULL``
        and for a refused cast, a broken rod, water the player is not facing -
        and the card's own message text is what tells them apart.  The tool does
        not read that text, so it does not pretend to know which one it was: it
        stops, says which slot the card was in and how it looked, and lets the
        player read it.  Nothing is lost by stopping - the fish is already
        landed, and a refused cast costs an E - whereas working through a red
        card is exactly how a fish gets thrown away.
        """
        if not self.config.pause_on_error_toast:
            self._toast_since = None
            self._toast_slot = None
            self._toast_mute = False
            return

        reading = vision.read_toasts(frame)
        if not (reading.present and reading.kind == "error"):
            self._toast_since = None
            self._toast_slot = None
            self._toast_mute = False       # the stack is clear again
            return
        if self._toast_mute:
            return                        # the card we were already told about

        now = self.clock()
        if self._toast_since is None:
            self._toast_since = now
            self._toast_slot = reading.slot
            # How it looked, in the tool's own words: enough for the user (and
            # for me, if they paste it) to tell a real card apart from a HUD
            # change, without claiming to know what the text said.
            self._toast_reason = (f"slot {reading.slot + 1}, "
                                  f"bar {reading.strip * 100:.0f} %, "
                                  f"icon {reading.accent * 100:.0f} %")
        # Let the slide-in finish before believing it.
        if now - self._toast_since < self.config.toast_grace:
            return
        if self._pause:
            return

        self.pause(f"error card on screen ({self._toast_reason})")
        self._event("error",
                    f"paused - the game showed a red error card ({self._toast_reason}). "
                    "Read it in game: if the bag is full, empty it and press F9.")


