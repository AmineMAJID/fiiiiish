"""Contrôleur en boucle fermée du combat avec le poisson.

Le client (``client/fishing.lua:1174``) ne lit **aucune touche** pendant le
combat : il compare l'angle entre la caméra et le bouchon à un ``targetSide``
affiché par les chevrons. Le joueur doit donc tourner la caméra (souris) ou
se déplacer latéralement pour placer le bouchon du côté demandé.

Le contrôleur ne suppose pas le sens souris <-> angle : il le déduit du premier
chebron affiché (le code Lua initialise ``targetSide`` au côté *opposé* du
premier côté détecté), puis utilise la progression de la barre bleue comme
retour d'asservissement. Si la progression s'arrête, il inverse le sens.
"""

from __future__ import annotations

from dataclasses import dataclass

from .config import FightConfig
from .vision import ScreenState, opposite


@dataclass
class FightStep:
    action: str                 # "continue" | "ended"
    direction: int              # -1, 0, +1 (0 = pause)
    boost: float = 1.0          # multiplicateur de pas pour traverser la zone morte
    reason: str = ""


class FightController:
    """Asservissement purement réactif, testable sans jeu ni entrées."""

    def __init__(self, cfg: FightConfig):
        self.cfg = cfg
        self.reset()

    def reset(self) -> None:
        self.dir = 1 if self.cfg.initial_dir >= 0 else -1
        self.mapping: dict[str, int] = {}
        self.first_cue_done = False
        self.cue: str | None = None
        self.cue_changed_at = -1e9
        self.last_edge: int | None = None
        self.last_time: float | None = None
        self.ema_rate = 0.0
        self.stall_s = 0.0
        self.samples = 0

    @staticmethod
    def _clamp_rate(rate: float) -> float:
        return max(-250.0, min(250.0, rate))

    def step(self, state: ScreenState, now: float) -> FightStep:
        if not state.fight:
            return FightStep("ended", 0, 1.0, "fight_ui_gone")

        reason = "track"
        if self.last_time is None:
            self.last_time = now
            self.last_edge = state.progress_edge
            return FightStep("continue", self.dir, 1.0, "warmup")

        dt = max(0.001, min(0.5, now - self.last_time))
        rate = 0.0
        if state.progress_edge is not None and self.last_edge is not None:
            rate = self._clamp_rate((state.progress_edge - self.last_edge) / dt)
            self.ema_rate = (
                rate if self.samples == 0 else 0.65 * self.ema_rate + 0.35 * rate
            )
            self.samples += 1
        self.last_edge = state.progress_edge
        self.last_time = now

        # 1) Changement de côté demandé ------------------------------------
        if state.cue_side and state.cue_side != self.cue:
            self.cue = state.cue_side
            self.cue_changed_at = now
            self.stall_s = 0.0
            if not self.first_cue_done:
                # targetSide = opposé du 1er côté réel => inverser immédiatement.
                self.mapping = {
                    state.cue_side: -self.dir,
                    opposite(state.cue_side): self.dir,
                }
                self.dir = -self.dir
                self.first_cue_done = True
                reason = "first_cue_reverse"

        # 2) Apprentissage confirmé par la progression ----------------------
        if state.cue_side and self.ema_rate > self.cfg.min_progress_rate:
            self.mapping.setdefault(state.cue_side, self.dir)
            self.mapping.setdefault(opposite(state.cue_side), -self.dir)

        # 3) Sens à appliquer ----------------------------------------------
        desired = self.dir
        if state.cue_side and state.cue_side in self.mapping:
            desired = self.mapping[state.cue_side]

        # 4) Détection de blocage (traversée de zone morte, mauvais sens) ---
        if self.ema_rate > self.cfg.min_progress_rate:
            self.stall_s = 0.0
        else:
            self.stall_s += dt
        if self.stall_s >= self.cfg.stall_flip_s:
            desired = -desired if desired != 0 else -self.dir
            self.dir = desired
            if self.cue:
                # On ré-amorce l'association avec le nouveau sens essayé ;
                # la progression (ou une nouvelle inversion) la confirmera.
                self.mapping = {self.cue: desired, opposite(self.cue): -desired}
                self.first_cue_done = True
            else:
                self.mapping.clear()
                self.first_cue_done = False
            self.cue_changed_at = now
            self.stall_s = 0.0
            reason = "stall_flip"

        # 5) Accélération pendant la traversée, pause en danger ------------
        boost = 1.0
        if self.ema_rate <= self.cfg.min_progress_rate and (now - self.cue_changed_at) < 2.0:
            boost = self.cfg.crossing_boost
        if (
            self.cfg.danger_pause
            and state.danger_high
            and self.ema_rate > self.cfg.min_progress_rate
        ):
            desired = 0
            boost = 1.0
            reason = "danger_pause"

        if desired != 0:
            self.dir = desired
        return FightStep("continue", desired, boost, reason)
