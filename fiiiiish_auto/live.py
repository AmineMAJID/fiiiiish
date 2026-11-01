"""The live bot: wires the real NUI, the real mouse and the controller.

The control logic is the same class the simulator validates.  Only the two
adapters change:

    NuiReader  -> reads the real HUD over CDP
    LiveCamera -> turns degrees into relative mouse counts

The bot is deliberately conservative:

* it only sends input while the fight HUD is on screen;
* it stops on F10, on Ctrl+C, or when the game loses focus;
* it never presses E during the bite wait (that would cancel the cast);
* it clicks "keep" in the decision modal instead of waiting 9 s.

The cast is automated too: press E, hold the left button, release at the
configured power.  The depth meter's "START_FISHING" prompt is the trigger,
so the player only has to stand at the water with the rod out.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from .config import BITE_TIME_MAX, FISHING_CONFIG
from .controller import ControlDecision, FightController
from .fight import NuiView
from .input import LiveCamera, MouseInput, make_input
from .nui import NuiError, NuiReader, NuiUnavailable

log = logging.getLogger("fiiiiish_auto.live")


@dataclass
class LiveBotConfig:
    # NUI
    endpoint: str = "http://127.0.0.1:13172"
    page_match: str | None = None
    # controller
    control_hz: float = 30.0
    setpoint: float = 75.0
    deadband: float = 3.0
    max_step: float = 6.0
    hold_step: float = 2.5
    hold_gain: float = 0.08
    reaction_delay: float = 0.05
    emergency: float = 92.0
    max_fight_duration: float = 180.0
    # cast
    cast_power: float = 0.5
    cast_power_margin: float = 2.0
    # decision
    decision: str = "keep"
    # input
    sensitivity: float = 0.10
    invert_x: bool = False
    game_title: str = "FiveM"
    dry_run: bool = False
    # misc
    log_every: float = 0.5
    max_bite_wait: float = BITE_TIME_MAX + FISHING_CONFIG["bite_window"] / 1000.0 + 3.0
    record_path: str | None = None


class LiveBot:
    """Runs the whole loop against the real game."""

    def __init__(
        self,
        config: LiveBotConfig,
        *,
        nui: NuiReader | None = None,
        mouse: MouseInput | None = None,
    ) -> None:
        self.config = config
        self.nui = nui if nui is not None else NuiReader(
            endpoint=config.endpoint, page_match=config.page_match
        )
        self.mouse = mouse if mouse is not None else make_input(
            dry_run=config.dry_run, game_title=config.game_title, log=log.info
        )
        self.camera = LiveCamera(
            self.mouse,
            sensitivity=config.sensitivity,
            invert_x=config.invert_x,
        )
        self.controller = FightController(
            setpoint=config.setpoint,
            deadband=config.deadband,
            max_step=config.max_step,
            hold_step=config.hold_step,
            hold_gain=config.hold_gain,
            reaction_delay=config.reaction_delay,
            emergency=config.emergency,
        )
        self._stop = False
        self._record_file = None
        self.stats = {
            "casts": 0,
            "fight_starts": 0,
            "fight_successes": 0,
            "fight_failures": 0,
            "missed_bites": 0,
            "decisions": 0,
            "pixels": 0,
        }
        self.last_fight_verdict: str | None = None

    # ------------------------------------------------------------------
    def stop(self) -> None:
        self._stop = True

    @property
    def stopped(self) -> bool:
        return self._stop

    # ------------------------------------------------------------------
    def connect(self) -> None:
        self.nui.connect()
        if not self.config.dry_run:
            focused = self.mouse.focus_game()
            if not focused:
                log.warning(
                    "Could not bring the game window to the foreground. "
                    "Click the FiveM window once, then restart the bot."
                )
        log.info("NUI attached to %s", getattr(self.nui.cdp, "page_url", "?"))

    def close(self) -> None:
        self.mouse.close()
        self.nui.close()

    # ------------------------------------------------------------------
    def run(self) -> dict:
        self.connect()
        try:
            while not self._stop:
                if self.mouse.stop_requested():
                    log.info("F10 pressed, stopping.")
                    break
                if not self.mouse.game_focused():
                    log.warning("Game window lost focus; pausing input.")
                    time.sleep(0.5)
                    continue

                try:
                    fight = self.nui.read_fight()
                except (NuiUnavailable, NuiError) as exc:
                    log.error("%s", exc)
                    break

                if fight is not None:
                    self.run_fight()
                    continue

                try:
                    cast = self.nui.read_cast()
                    if cast is not None:
                        self.run_cast()
                        continue
                    bite = self.nui.read_bite()
                    if bite is not None:
                        self.run_bite()
                        continue
                    decision = self.nui.read_decision()
                    if decision is not None:
                        self.run_decision()
                        continue
                    if self.nui.can_cast():
                        self.run_cast()
                        continue
                except (NuiUnavailable, NuiError) as exc:
                    log.error("%s", exc)
                    break

                time.sleep(0.2)
        finally:
            self.close()
        return dict(self.stats)

    # ------------------------------------------------------------------
    def run_cast(self) -> None:
        """Press E, hold the left button, release at the configured power."""
        cfg = self.config
        log.info("cast: starting")
        self.mouse.press_e()
        self.stats["casts"] += 1

        # Wait for the cast UI.
        deadline = time.monotonic() + 3.0
        cast = None
        while time.monotonic() < deadline and not self._stop:
            cast = self.nui.read_cast()
            if cast is not None:
                break
            time.sleep(0.03)
        if cast is None:
            log.warning("cast: UI did not appear (not facing water?)")
            return

        # Hold the left button to charge.
        self.mouse.left_down()
        target = max(0.0, min(1.0, cfg.cast_power)) * 100.0
        release_at = max(1.0, target - cfg.cast_power_margin)
        deadline = time.monotonic() + 8.0
        power = 0
        while time.monotonic() < deadline and not self._stop:
            cast = self.nui.read_cast()
            if cast is None:
                break
            power = cast.power
            if cast.locked:
                break
            if cast.charging and power >= release_at:
                break
            time.sleep(0.015)
        self.mouse.left_up()
        log.info("cast: released at %d%% (target %d%%)", power, int(target))

        # Wait for the cast UI to close and the bite UI to take over.
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline and not self._stop:
            if self.nui.read_bite() is not None:
                return
            if self.nui.read_cast() is None:
                return
            time.sleep(0.05)

    # ------------------------------------------------------------------
    def run_bite(self) -> None:
        """Wait for the bite state, then press E inside the 3 s window."""
        log.info("bite: waiting")
        deadline = time.monotonic() + self.config.max_bite_wait
        while time.monotonic() < deadline and not self._stop:
            bite = self.nui.read_bite()
            if bite is None:
                return
            if bite.state == "bite":
                self.mouse.press_e()
                log.info("bite: struck")
                return
            time.sleep(0.02)
        self.stats["missed_bites"] += 1
        log.warning("bite: window expired")

    # ------------------------------------------------------------------
    def run_fight(self) -> None:
        """The core loop: read the HUD, steer the camera, repeat."""
        cfg = self.config
        self.stats["fight_starts"] += 1
        log.info("fight: start")
        self.controller.reset()
        start = time.monotonic()
        last = start
        next_tick = start
        period = 1.0 / cfg.control_hz
        last_log = 0.0
        verdict: str | None = None
        if cfg.record_path:
            self._record_file = open(cfg.record_path, "w", encoding="utf-8")

        while not self._stop:
            if self.mouse.stop_requested():
                log.info("fight: F10, stopping")
                break
            if not self.mouse.game_focused():
                log.warning("fight: game lost focus, stopping fight loop")
                break

            try:
                view = self.nui.read_fight()
            except (NuiUnavailable, NuiError) as exc:
                log.error("%s", exc)
                break

            if view is None:
                log.info("fight: HUD closed")
                break
            verdict = view.verdict
            if not view.active:
                if verdict:
                    log.info("fight: verdict %s", verdict)
                break

            now = time.monotonic()
            dt = max(0.001, now - last)
            last = now
            decision = self.controller.tick(view, dt, now - start)
            self.camera.apply(decision.step, dt)
            self.stats["pixels"] = self.camera.total_pixels

            if self._record_file is not None:
                import json as _json

                self._record_file.write(
                    _json.dumps(
                        {
                            "t": round(now - start, 4),
                            "view": view.as_dict(),
                            "step": round(decision.step, 3),
                            "mode": decision.mode,
                            "reason": decision.reason,
                        }
                    )
                    + "\n"
                )
                self._record_file.flush()

            if now - start - last_log >= cfg.log_every:
                last_log = now - start
                log.info(
                    "fight: %5.1fs danger=%3d progress=%3d side=%s mode=%-6s step=%+5.2f",
                    now - start,
                    view.danger,
                    view.progress,
                    view.side,
                    decision.mode,
                    decision.step,
                )

            if now - start > cfg.max_fight_duration:
                log.warning("fight: max duration reached")
                break

            # Keep a steady control cadence even if a CDP read is slow.
            next_tick += period
            sleep_for = next_tick - time.monotonic()
            if sleep_for > 0:
                time.sleep(sleep_for)
            else:
                next_tick = time.monotonic()

        if self._record_file is not None:
            self._record_file.close()
            self._record_file = None
        self.last_fight_verdict = verdict
        if verdict == "NICE_CATCH" or verdict == "success":
            self.stats["fight_successes"] += 1
        else:
            self.stats["fight_failures"] += 1

    # ------------------------------------------------------------------
    def run_decision(self) -> None:
        """Click Keep in the decision modal (the timeout would keep anyway)."""
        cfg = self.config
        log.info("decision: modal open")
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline and not self._stop:
            decision = self.nui.read_decision()
            if decision is None:
                return
            if cfg.decision == "release":
                # The release button is the second choice; click it by text.
                clicked = self.nui.cdp.evaluate(
                    "(() => { const b = document.querySelector('[class*=\"release\"]');"
                    " if (!b) return false; b.click(); return true; })()"
                )
            else:
                clicked = self.nui.click_keep()
            if clicked:
                self.stats["decisions"] += 1
                log.info("decision: clicked %s", cfg.decision)
                return
            time.sleep(0.1)
        log.warning("decision: modal did not close")

    # ------------------------------------------------------------------
    def calibrate(self) -> None:
        """Print the danger response to a known mouse delta.

        Run this during a fight (or start a fight with the bot paused) to
        estimate degrees-per-pixel.  The controller is closed-loop, so this is
        optional; it just makes the cross faster/slower.
        """
        self.connect()
        log.info("Waiting for the fight HUD to calibrate...")
        deadline = time.monotonic() + 60.0
        view: NuiView | None = None
        while time.monotonic() < deadline and not self._stop:
            view = self.nui.read_fight()
            if view is not None and view.active:
                break
            time.sleep(0.1)
        if view is None:
            log.error("No fight HUD appeared; start a fight and retry.")
            return
        before = view.danger
        self.mouse.move(20, 0)
        time.sleep(0.4)
        after = self.nui.read_fight()
        if after is None:
            log.error("Fight HUD disappeared during calibration.")
            return
        delta = after.danger - before
        log.info(
            "calibration: danger %d -> %d after 20 px (delta %+d). "
            "If the danger moved the wrong way for the requested side, set invert-x.",
            before,
            after.danger,
            delta,
        )
        self.close()
