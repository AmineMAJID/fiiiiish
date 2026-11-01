"""Tests du contrôleur de combat (souris/strafe, sans jeu)."""

from __future__ import annotations

from fishing_bot.config import Config, FightConfig
from fishing_bot.controller import FightController
from fishing_bot.vision import ScreenState


def _s(cue=None, edge=None, danger=False, fight=True) -> ScreenState:
    return ScreenState(
        w=1920, h=1080, fight=fight, cue_side=cue,
        progress_edge=edge, danger_high=danger,
    )


def test_premier_chevron_inverse_le_sens():
    fc = FightController(FightConfig(initial_dir=1))
    assert fc.step(_s(), 0.0).direction == 1
    step = fc.step(_s(cue="left"), 0.05)
    # targetSide est l'opposé du premier côté réel (client/fishing.lua).
    assert step.direction == -1
    assert fc.mapping["left"] == -1
    assert fc.mapping["right"] == 1


def test_changement_de_cote():
    fc = FightController(FightConfig())
    fc.step(_s(), 0.0)
    fc.step(_s(cue="left"), 0.05)
    fc.step(_s(cue="left", edge=700), 0.10)
    fc.step(_s(cue="left", edge=720), 0.15)
    step = fc.step(_s(cue="right", edge=720), 0.20)
    assert step.direction == 1


def test_pause_en_danger_uniquement_si_progression():
    cfg = FightConfig(danger_pause=True)
    fc = FightController(cfg)
    fc.step(_s(), 0.0)
    fc.step(_s(cue="left"), 0.05)
    fc.step(_s(cue="left", edge=700), 0.10)
    fc.step(_s(cue="left", edge=720), 0.15)
    step = fc.step(_s(cue="left", edge=740, danger=True), 0.20)
    assert step.direction == 0
    assert step.reason == "danger_pause"


def test_inversion_sur_blocage():
    cfg = FightConfig(stall_flip_s=0.2)
    fc = FightController(cfg)
    fc.reset()
    fc.step(_s(), 0.0)
    t = 0.05
    reasons = []
    for _ in range(5):
        reasons.append(fc.step(_s(cue="left", edge=500), t).reason)
        t += 0.05
    assert "stall_flip" in reasons
    assert fc.mapping["left"] == 1


def test_fin_de_combat():
    fc = FightController(Config().fight)
    assert fc.step(_s(fight=False), 1.0).action == "ended"
