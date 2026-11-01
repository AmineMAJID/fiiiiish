"""Tests for the fight engine and the NUI model."""

from __future__ import annotations

import math
import unittest

from fiiiiish_auto.config import (
    FIGHT_DIFFICULTY_TIERS,
    build_fight_params,
    distance_for_power,
    fight_difficulty,
)
from fiiiiish_auto.fight import CameraModel, FightEngine, NuiModel
from fiiiiish_auto.rng import Rng


def make_engine(difficulty: float = 0.35, distance: float = 16.0, seed: int = 1):
    params = build_fight_params(difficulty, 0.0)
    return FightEngine(params, distance, Rng(seed))


class TestConfigPort(unittest.TestCase):
    def test_distance_endpoints(self):
        self.assertAlmostEqual(distance_for_power(0.0), 6.0)
        self.assertAlmostEqual(distance_for_power(1.0), 26.0)
        self.assertAlmostEqual(distance_for_power(0.5), 16.0)

    def test_build_fight_params_matches_lua(self):
        p = build_fight_params(0.0, 0.0)
        self.assertAlmostEqual(p.max_angle, 70.0)
        self.assertAlmostEqual(p.pull_speed, 0.025)
        self.assertAlmostEqual(p.slip_speed, 0.005)
        self.assertAlmostEqual(p.turn_rate, 1.0)

        p = build_fight_params(1.0, 0.0)
        self.assertAlmostEqual(p.max_angle, 70.0 * (1.0 - 0.35))
        self.assertAlmostEqual(p.pull_speed, 0.025 * (1.0 - 0.45))
        self.assertAlmostEqual(p.slip_speed, 0.005 * 2.2)
        self.assertAlmostEqual(p.turn_rate, 1.5)

    def test_line_strength_increases_angle(self):
        base = build_fight_params(0.5, 0.0)
        boosted = build_fight_params(0.5, 12.0)
        self.assertAlmostEqual(boosted.max_angle, base.max_angle * 1.12)

    def test_difficulty_tiers(self):
        self.assertAlmostEqual(fight_difficulty("shallow", 0.5, 0.0), 0.10 + 0.5 * 0.15)
        self.assertAlmostEqual(fight_difficulty("abyss", 0.5, 0.0), 0.90 + 0.5 * 0.15)
        self.assertAlmostEqual(fight_difficulty("abyss", 0.5, 40.0), (0.90 + 0.5 * 0.15) * 0.6)
        self.assertLess(fight_difficulty("abyss", 0.5, 100.0), fight_difficulty("abyss", 0.5, 0.0))

    def test_tiers_are_ordered(self):
        values = [FIGHT_DIFFICULTY_TIERS[k] for k in ("shallow", "mid", "deep", "abyss")]
        self.assertEqual(values, sorted(values))


class TestFightEngine(unittest.TestCase):
    def test_first_side_sets_opposite_target(self):
        engine = make_engine()
        engine.set_angle(20.0)
        engine.step(1 / 60)
        self.assertEqual(engine.state.side, "right")
        self.assertEqual(engine.state.target_side, "left")

    def test_dead_zone_is_center(self):
        engine = make_engine()
        engine.set_angle(5.0)
        engine.step(1 / 60)
        self.assertEqual(engine.state.side, "center")
        self.assertIsNone(engine.state.target_side)

    def test_line_snaps_beyond_max_angle(self):
        engine = make_engine(difficulty=0.0)
        engine.set_angle(engine.max_angle + 0.1)
        engine.step(1 / 60)
        self.assertEqual(engine.state.outcome, "line_snapped")
        self.assertFalse(engine.state.active)

    def test_correct_side_pulls_and_progresses(self):
        engine = make_engine()
        engine.set_angle(20.0)
        engine.step(1 / 60)
        target = engine.state.target_side
        # Move to the requested side and hold it.
        sign = 1.0 if target == "right" else -1.0
        start = engine.state.distance
        for _ in range(60):
            engine.set_angle(sign * 40.0)
            engine.step(1 / 60)
        self.assertLess(engine.state.distance, start)
        self.assertGreater(engine.state.progress, 0.0)

    def test_wrong_side_slips(self):
        engine = make_engine()
        engine.set_angle(20.0)
        engine.step(1 / 60)
        target = engine.state.target_side
        correct = 1.0 if target == "right" else -1.0
        # Pull correctly first so the bobber is closer than the cast point.
        for _ in range(60):
            engine.set_angle(correct * 40.0)
            engine.step(1 / 60)
        start = engine.state.distance
        # Now pull the wrong way: the bobber must slip back out.
        for _ in range(60):
            engine.set_angle(-correct * 40.0)
            engine.step(1 / 60)
        self.assertGreater(engine.state.distance, start)

    def test_success_at_full_progress(self):
        engine = make_engine(difficulty=0.0, distance=6.0)
        # Force the distance close to the minimum, then pull correctly.
        engine.state.distance = engine.min_distance + 0.001
        engine.state.initial_distance = 6.0
        engine.set_angle(20.0)
        engine.step(1 / 60)
        target = engine.state.target_side
        sign = 1.0 if target == "right" else -1.0
        for _ in range(120):
            if not engine.state.active:
                break
            engine.set_angle(sign * 40.0)
            engine.step(1 / 60)
        self.assertEqual(engine.state.outcome, "success")
        self.assertAlmostEqual(engine.state.progress, 1.0)

    def test_deterministic(self):
        def run():
            engine = make_engine(seed=7)
            for i in range(600):
                engine.set_angle(math.sin(i / 20) * 50)
                engine.step(1 / 60)
            return engine.state.as_dict()

        self.assertEqual(run(), run())


class TestNuiModel(unittest.TestCase):
    def test_smoothing_lags_raw_danger(self):
        engine = make_engine()
        engine.set_angle(30.0)
        engine.step(1 / 60)
        nui = NuiModel()
        nui.update(engine, 1 / 60)
        # One frame of easing cannot reach the raw value.
        self.assertLess(nui.smooth_danger, engine.state.danger)
        for _ in range(120):
            nui.update(engine, 1 / 60)
        self.assertAlmostEqual(nui.smooth_danger, engine.state.danger, delta=1.0)

    def test_view_is_active_while_fighting(self):
        engine = make_engine()
        nui = NuiModel()
        nui.update(engine, 0.0)
        view = nui.read()
        self.assertTrue(view.active)
        self.assertEqual(view.danger, 0)
        self.assertEqual(view.progress, 0)

    def test_view_reports_verdict(self):
        engine = make_engine()
        engine.set_angle(engine.max_angle + 1)
        engine.step(1 / 60)
        nui = NuiModel()
        nui.update(engine, 0.0)
        nui.update(engine, 0.05)
        view = nui.read()
        self.assertEqual(view.verdict, "fail")
        self.assertFalse(view.active)


class TestCameraModel(unittestersection if False else unittest.TestCase):
    def test_apply(self):
        cam = CameraModel()
        cam.apply(10.0, 1 / 30)
        self.assertAlmostEqual(cam.angle, 10.0)
        cam.apply(-4.0, 1 / 30)
        self.assertAlmostEqual(cam.angle, 6.0)

    def test_invert(self):
        cam = CameraModel(invert=True)
        cam.apply(10.0, 1 / 30)
        self.assertAlmostEqual(cam.angle, -10.0)


if __name__ == "__main__":
    unittest.main()
