"""Tests de régression des détecteurs (images synthétiques conformes à la NUI)."""

from __future__ import annotations

import pytest

from fishing_bot.config import Config
from fishing_bot.selftest import (
    blank,
    draw_bite,
    draw_cast,
    draw_decision,
    draw_fight,
    draw_ready,
    run_selftest,
)
from fishing_bot.vision import Vision, power_from_hold


@pytest.fixture(scope="module")
def vision() -> Vision:
    return Vision(Config())


def test_batterie_complete():
    assert run_selftest(verbose=False) is True


@pytest.mark.parametrize("power", [0.10, 0.35, 0.55, 0.86, 0.95])
def test_cast_power(vision: Vision, power: float):
    frame = blank()
    draw_cast(frame, vision, power)
    st = vision.analyze(frame)
    assert st.cast_card is True
    assert st.cast_power is not None
    assert abs(st.cast_power - power) < 0.035, f"lu={st.cast_power} attendu={power}"


def test_cast_absent(vision: Vision):
    st = vision.analyze(blank())
    assert st.cast_card is False
    assert st.bite is False
    assert st.fight is False
    assert st.decision is False


def test_bite_vs_attente(vision: Vision):
    active = blank()
    draw_bite(active, vision, active=True)
    assert vision.analyze(active).bite is True
    waiting = blank()
    draw_bite(waiting, vision, active=False)
    assert vision.analyze(waiting).bite is False


@pytest.mark.parametrize("cue", ["left", "right"])
def test_fight(vision: Vision, cue: str):
    frame = blank()
    edge = draw_fight(frame, vision, cue=cue, progress=0.62)
    st = vision.analyze(frame)
    assert st.fight is True
    assert st.cue_side == cue
    assert st.progress_edge is not None and edge is not None
    assert abs(st.progress_edge - edge) < 12
    assert st.danger_high is False


def test_danger(vision: Vision):
    frame = blank()
    draw_fight(frame, vision, cue="left", progress=0.8, danger_high=True)
    assert vision.analyze(frame).danger_high is True


def test_decision_et_boutons(vision: Vision):
    frame = blank()
    keep, release = draw_decision(frame, vision)
    st = vision.analyze(frame)
    assert st.decision is True
    assert st.keep_button is not None and abs(st.keep_button[0] - keep[0]) < 8
    assert st.release_button is not None and abs(st.release_button[0] - release[0]) < 8


def test_ready(vision: Vision):
    frame = blank()
    draw_ready(frame, vision)
    st = vision.analyze(frame)
    assert st.ready is True
    assert st.decision is False


@pytest.mark.parametrize(
    "hold,expected",
    [(0, 0.0), (550, 0.5), (1100, 1.0), (1650, 0.5), (2200, 0.0), (2750, 0.5), (3300, 1.0)],
)
def test_modele_charge(hold: int, expected: float):
    assert abs(power_from_hold(hold) - expected) < 1e-9
