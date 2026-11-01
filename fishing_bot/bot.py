"""Machine à états : lance -> attente -> ferrage -> combat -> décision -> boucle.

Chaque transition est déclenchée par ce que le joueur **voit** (Vision) et par
des garde-fous temporels. Les seules sorties sont des entrées clavier/souris.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Callable

import numpy as np

from .config import Config
from .controller import FightController
from .inputs import DirectionalActuator, InputController
from .screen import ScreenCapture, save_image
from .vision import Vision, ScreenState


class StopBot(Exception):
    """Arrêt volontaire et propre."""


@dataclass
class Stats:
    started_at: float = field(default_factory=time.time)
    cycles: int = 0
    casts: int = 0
    bites: int = 0
    hooks: int = 0
    fights_won: int = 0
    fights_lost: int = 0
    decisions: int = 0
    missed_bites: int = 0
    equips: int = 0
    resupplies: int = 0
    sales: int = 0
    last_error: str = ""

    def save(self, path: str | Path) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(asdict(self), indent=2) + "\n", encoding="utf-8")


class FishingBot:
    def __init__(
        self,
        cfg: Config,
        config_path: str | Path,
        screen: ScreenCapture,
        vision: Vision,
        inputs: InputController,
        actuator: DirectionalActuator,
        logger: logging.Logger | None = None,
    ):
        self.cfg = cfg
        self.config_path = Path(config_path)
        self.screen = screen
        self.vision = vision
        self.inputs = inputs
        self.actuator = actuator
        self.fight_ctrl = FightController(cfg.fight)
        self.log = logger or logging.getLogger("fishing_bot")
        self.stats = Stats()

        self.state = "READY"
        self.state_enter = time.monotonic()
        self.cast_time = 0.0
        self.recover_enter = 0.0
        self.bite_hits = 0
        self.fight_absent = 0
        self.consecutive_failures = 0
        self.equip_attempts = 0
        self.cycle = 0
        self._last_logged_state = ""
        self._handlers: dict[str, Callable[[ScreenState, float, np.ndarray], str]] = {
            "READY": self._on_ready,
            "WAIT_BITE": self._on_wait_bite,
            "FIGHT": self._on_fight,
            "POST_FIGHT": self._on_post_fight,
            "DECISION": self._on_decision,
            "RECOVER": self._on_recover,
        }

    # ------------------------------------------------------------------ utils
    def _goto(self, state: str, now: float, frame: np.ndarray | None = None, reason: str = "") -> str:
        if state != self.state:
            self.log.info("[%s -> %s] %s", self.state, state, reason)
            self.state = state
            self.state_enter = now
            if frame is not None and self.cfg.debug.save_frames:
                self._save_debug(frame, f"enter_{state.lower()}")
        return state

    def _elapsed(self, now: float) -> float:
        return now - self.state_enter

    def _save_debug(self, frame: np.ndarray, label: str) -> None:
        try:
            stamp = time.strftime("%Y%m%d-%H%M%S")
            save_image(Path(self.cfg.debug.screenshot_dir) / f"{stamp}_{label}.png", frame)
        except Exception as exc:  # pragma: no cover
            self.log.debug("debug screenshot: %s", exc)

    def _recover(self, reason: str, frame: np.ndarray, hard_failure: bool) -> str:
        if hard_failure:
            self.consecutive_failures += 1
            self.stats.last_error = reason
            self.log.warning("Échec: %s (consécutifs=%d)", reason, self.consecutive_failures)
            self._save_debug(frame, "failure")
        else:
            self.log.info("Issue indéterminée: %s (pas d'échec compté)", reason)
            self._save_debug(frame, "ambiguous")
        self.inputs.release_all()
        self.actuator.stop()
        now = time.monotonic()
        self.recover_enter = now
        return self._goto("RECOVER", now, frame, reason)

    def _fail(self, reason: str, frame: np.ndarray) -> str:
        return self._recover(reason, frame, hard_failure=True)

    def _success(self, reason: str) -> None:
        self.consecutive_failures = 0
        self.stats.fights_won += 1
        self.log.info("Succès: %s", reason)

    # ------------------------------------------------------------------ READY
    def _on_ready(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        if st.decision:
            return self._goto("DECISION", now, frame, "modale résiduelle")
        if st.fight:
            self.fight_ctrl.reset()
            return self._goto("FIGHT", now, frame, "combat déjà actif")
        if st.cast_card:
            return self._goto("WAIT_BITE", now, frame, "carte de lancer résiduelle")

        if st.ready:
            self.equip_attempts = 0
            try:
                self._do_cast(now, frame)
            except Exception as exc:
                self.log.exception("Erreur pendant le lancer: %s", exc)
                self.inputs.release_all()
                return self._fail("exception lancer", frame)
            self.cast_time = time.monotonic()
            self.bite_hits = 0
            return self._goto("WAIT_BITE", now, frame, "lancer effectué")

        # Pas de jauge de profondeur : canne rangée / cassée / mal placée.
        if self._elapsed(now) > 5.0:
            actions = self.cfg.actions.equip
            if not actions or self.equip_attempts >= self.cfg.limits.equip_retries:
                raise StopBot(
                    "Jauge de profondeur absente : place le personnage face à l'eau, "
                    "équipe une canne (actions.equip) ou vérifie la calibration."
                )
            self.equip_attempts += 1
            self.stats.equips += 1
            self.log.info("Tentative d'équipement de la canne (%d)", self.equip_attempts)
            self.inputs.run_actions(actions, self.cfg.debug.screenshot_dir)
            self.state_enter = now
        return "READY"

    def _do_cast(self, now: float, frame: np.ndarray) -> None:
        """Séquence exacte : E maintenu, clic gauche maintenu, relâcher, E relâché."""
        cfg, t = self.cfg, self.cfg.timing
        target = cfg.cast.target_power
        hold_ms = cfg.hold_ms_for(target)

        self.inputs.key_up(cfg.keys.interact)
        self.inputs.mouse_up()
        self.inputs.key_down(cfg.keys.interact)
        time.sleep(t.charge_ready_delay_ms / 1000.0)

        # Auto-détection : si la carte "Cast power" est là, le serveur a bien
        # Config.Cast.Enabled=true, même si le fichier JSON dit le contraire.
        pre = self.vision.analyze(self.screen.grab())
        charge_needed = cfg.cast.enabled or pre.cast_card
        measured: float | None = None
        if charge_needed:
            self.inputs.mouse_down()
            t0 = time.monotonic()
            released = False
            while True:
                elapsed_ms = (time.monotonic() - t0) * 1000.0
                fr = self.screen.grab()
                st = self.vision.analyze(fr)
                # Sécurité : si la carte n'apparaît pas, on ne reste pas bloqué.
                if not st.cast_card and elapsed_ms > 700:
                    self.log.warning("Carte de lancer non détectée, repli sur le timing")
                    break
                power = st.cast_power
                if (
                    cfg.cast.auto_calibrate
                    and power is not None
                    and power >= target - cfg.cast.power_tolerance
                    and elapsed_ms >= 0.45 * hold_ms
                ):
                    break
                if elapsed_ms >= hold_ms:
                    break
                time.sleep(0.012)
            hold_actual_ms = (time.monotonic() - t0) * 1000.0
            self.inputs.mouse_up()
            self.log.info(
                "Lancer: cible=%.2f appui=%.0f ms (prévu %.0f ms)",
                target, hold_actual_ms, hold_ms,
            )
            # La carte reste 700 ms en état "locked" : on lit la puissance réelle.
            # Médiane des lectures pour neutraliser un halo / une frame de transition.
            import statistics

            readings: list[float] = []
            deadline = time.monotonic() + 0.55
            while time.monotonic() < deadline:
                fr = self.screen.grab()
                st = self.vision.analyze(fr)
                if st.cast_power is not None and st.cast_card:
                    readings.append(st.cast_power)
                time.sleep(0.05)
            if readings:
                measured = float(statistics.median(readings))
            if measured is not None:
                error = target - measured
                self.log.info("Puissance lue=%.2f (écart=%+.2f)", measured, error)
                if cfg.cast.auto_calibrate:
                    delta = int(max(-120, min(120, error * t.charge_cycle_ms)))
                    cfg.cast.hold_offset_ms = int(
                        max(-150, min(150, cfg.cast.hold_offset_ms + delta))
                    )
                    try:
                        cfg.save(self.config_path)
                    except Exception as exc:  # pragma: no cover
                        self.log.debug("sauvegarde config: %s", exc)
        else:
            self.log.info("Aucune carte de charge détectée : Config.Cast.Enabled=false, puissance 1.0")
            time.sleep(t.charge_ready_delay_ms / 1000.0)

        self.inputs.key_up(cfg.keys.interact)
        self.stats.casts += 1
        if self.cfg.debug.save_frames:
            self._save_debug(self.screen.grab(), "after_cast")

    # -------------------------------------------------------------- WAIT_BITE
    def _on_wait_bite(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        elapsed = now - self.cast_time
        if st.fight:
            self.fight_ctrl.reset()
            return self._goto("FIGHT", now, frame, "combat détecté directement")
        if st.decision:
            return self._goto("DECISION", now, frame, "modale détectée")

        if st.bite and elapsed >= self.cfg.timing.bite_min_s:
            self.bite_hits += 1
        else:
            self.bite_hits = 0

        if self.bite_hits >= 2 and elapsed < self.cfg.timing.bite_timeout_s:
            self.stats.bites += 1
            self.inputs.press(self.cfg.keys.interact)
            self.stats.hooks += 1
            self.fight_ctrl.reset()
            self.fight_absent = 0
            self.log.info("Ferrage après %.2fs (ring=%d prompt=%d)", elapsed, st.bite_ring, st.bite_prompt)
            time.sleep(0.30)  # le client attend 300 ms avant StartFishingFight
            return self._goto("FIGHT", now, frame, "E envoyé")

        if elapsed > self.cfg.timing.bite_timeout_s:
            self.stats.missed_bites += 1
            return self._fail("fenêtre de ferrage manquée", frame)
        return "WAIT_BITE"

    # ------------------------------------------------------------------ FIGHT
    def _on_fight(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        if not st.fight:
            self.fight_absent += 1
            if self.fight_absent >= 3:
                self.actuator.stop()
                return self._goto("POST_FIGHT", now, frame, "UI de combat disparue")
            return "FIGHT"
        self.fight_absent = 0

        step = self.fight_ctrl.step(st, now)
        self.actuator.drive(step.direction, step.boost)
        if self.cycle % 10 == 0 and int(now * 2) % 2 == 0:
            self.log.debug(
                "combat cue=%s edge=%s danger=%d dir=%d boost=%.1f (%s)",
                st.cue_side, st.progress_edge, int(st.danger_high),
                step.direction, step.boost, step.reason,
            )

        if self._elapsed(now) > self.cfg.timing.fight_timeout_s:
            self.stats.fights_lost += 1
            self.inputs.press(self.cfg.keys.cancel)  # ESC annule proprement
            return self._fail("timeout combat (ESC envoyé)", frame)
        return "FIGHT"

    # ------------------------------------------------------------- POST_FIGHT
    def _on_post_fight(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        if st.decision:
            return self._goto("DECISION", now, frame, "modale de décision")
        if st.fight:
            self.fight_ctrl.reset()
            return self._goto("FIGHT", now, frame, "UI de combat réapparue")
        if self._elapsed(now) > self.cfg.timing.decision_timeout_s:
            # Pas de modale : soit la ligne a cassé, soit le tirage a donné une
            # botte, soit CatchDecision.Enabled=false. On ne pénalise pas la
            # série d'échecs : une botte est une prise réussie côté serveur.
            self.stats.fights_lost += 1
            return self._recover(
                "pas de modale (botte / ligne cassée / décision désactivée)",
                frame,
                hard_failure=False,
            )
        return "POST_FIGHT"

    # --------------------------------------------------------------- DECISION
    def _on_decision(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        if st.decision:
            choice = self.cfg.decision.choice.lower()
            point = st.keep_button if choice != "release" else st.release_button
            if point is None:
                return self._fail("coordonnées du bouton indisponibles", frame)
            self.inputs.click(point[0], point[1])
            self.stats.decisions += 1
            self._success(f"décision '{choice}'")
            self.log.info("Clic décision %s @ (%d,%d)", choice, point[0], point[1])
            time.sleep(self.cfg.timing.action_delay_ms / 1000.0)
            self.recover_enter = time.monotonic()
            return self._goto("RECOVER", now, frame, "poisson traité")

        if self._elapsed(now) > self.cfg.timing.decision_timeout_s:
            # TimeoutKeeps=true côté serveur : le poisson est gardé automatiquement.
            self._success("timeout décision (serveur garde le poisson)")
            self.stats.decisions += 1
            self.recover_enter = time.monotonic()
            return self._goto("RECOVER", now, frame, "timeout modale")
        return "DECISION"

    # ---------------------------------------------------------------- RECOVER
    def _on_recover(self, st: ScreenState, now: float, frame: np.ndarray) -> str:
        min_wait = self.cfg.timing.between_casts_ms / 1000.0
        busy = st.decision or st.fight or st.cast_card or st.bite
        if now - self.recover_enter < min_wait or busy:
            return "RECOVER"

        self.cycle += 1
        self.stats.cycles = self.cycle
        self.log.info(
            "Cycle %d terminé | casts=%d hooks=%d gagnés=%d perdus=%d décisions=%d",
            self.cycle, self.stats.casts, self.stats.hooks,
            self.stats.fights_won, self.stats.fights_lost, self.stats.decisions,
        )

        if self.cfg.actions.resupply_every and self.cycle % self.cfg.actions.resupply_every == 0:
            self.log.info("Réapprovisionnement (actions.resupply)")
            self.inputs.run_actions(self.cfg.actions.resupply, self.cfg.debug.screenshot_dir)
            self.stats.resupplies += 1
            time.sleep(self.cfg.timing.action_delay_ms / 1000.0)
        if self.cfg.actions.sell_every and self.cycle % self.cfg.actions.sell_every == 0:
            self.log.info("Vente (actions.sell)")
            self.inputs.run_actions(self.cfg.actions.sell, self.cfg.debug.screenshot_dir)
            self.stats.sales += 1
            time.sleep(self.cfg.timing.action_delay_ms / 1000.0)

        if (
            self.cfg.limits.max_consecutive_failures
            and self.consecutive_failures >= self.cfg.limits.max_consecutive_failures
        ):
            raise StopBot(
                f"{self.consecutive_failures} échecs consécutifs : arrêt de sécurité. "
                "Vérifie la calibration (debug/*.png) et la position du personnage."
            )
        if self.cfg.limits.max_cycles and self.cycle >= self.cfg.limits.max_cycles:
            raise StopBot(f"{self.cycle} cycles atteints (limits.max_cycles)")
        return self._goto("READY", now, frame, "cycle suivant")

    # -------------------------------------------------------------------- run
    def run(self) -> Stats:
        self.log.info("Démarrage | %s", self.config_path.resolve())
        self.log.info(
            "Cible puissance=%.2f | actionneur=%s | décision=%s | arrêt=%s",
            self.cfg.cast.target_power, self.cfg.fight.actuator,
            self.cfg.decision.choice, self.cfg.keys.stop.upper(),
        )
        stats_path = Path(self.cfg.debug.log_dir) / "stats.json"
        self.state = "READY"
        self.state_enter = time.monotonic()
        try:
            while True:
                if self.inputs.stop_requested():
                    raise StopBot("coupe-circuit clavier demandé")
                if not self.inputs.focus_ok():
                    self.inputs.release_all()
                    self.actuator.stop()
                    if self._last_logged_state != "PAUSE":
                        self.log.warning("FiveM n'est pas au premier plan : pause")
                        self._last_logged_state = "PAUSE"
                    time.sleep(0.40)
                    continue
                if self._last_logged_state == "PAUSE":
                    self.log.info("Reprise")
                    self._last_logged_state = ""

                frame = self.screen.grab()
                st = self.vision.analyze(frame)
                now = time.monotonic()
                if self.cfg.debug.save_every_state:
                    self._save_debug(frame, f"state_{self.state.lower()}_{int(now * 1000) % 100000}")

                handler = self._handlers.get(self.state)
                if handler is None:  # pragma: no cover
                    raise StopBot(f"état inconnu: {self.state}")
                handler(st, now, frame)
                time.sleep(self.cfg.timing.poll_interval_ms / 1000.0)
        except (StopBot, KeyboardInterrupt) as exc:
            self.log.info("Arrêt: %s", exc or "interrompu")
        except Exception as exc:
            self.log.exception("Erreur fatale: %s", exc)
            self.stats.last_error = str(exc)
        finally:
            self.inputs.release_all()
            self.actuator.stop()
            self.stats.cycles = self.cycle
            try:
                self.stats.save(stats_path)
                self.cfg.save(self.config_path)
            except Exception as exc:  # pragma: no cover
                self.log.debug("sauvegarde finale: %s", exc)
            self.log.info(
                "Fin | cycles=%d casts=%d ferrages=%d gagnés=%d perdus=%d",
                self.cycle, self.stats.casts, self.stats.hooks,
                self.stats.fights_won, self.stats.fights_lost,
            )
        return self.stats
