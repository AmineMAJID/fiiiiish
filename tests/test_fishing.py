"""Tests for the full cast -> bite -> fight -> decide loop."""

from __future__ import annotations

import unittest

from fiiiiish_auto.controller import FightController
from fiiiiish_auto.fight import CameraModel, NuiModel
from fiiiiish_auto.fishing import Aggregate, CastResult, FishingLoop, Scenario, Simulator
from fiiiiish_auto.loop import FightResult
from fiiiiish_auto.rng import Rng


class FailingController:
    """A controller that deliberately steers past the line limit."""

    decisions = 0

    def reset(self):
        self.decisions = 0

    def tick(self, view, dt, now):
        self.decisions += 1
        from fiiiiish_auto.controller import ControlDecision

        return ControlDecision(6.0, "hold", "test failure")


class TestFishingLoop(unittestersection if False else unittest.TestCase):
    pass


class TestFishingLoopReal(TestFishingLoop):
    def runTest(self):
        pass


class TestLoop(unittest.TestCase):
    def test_success(self):
        sc = Scenario(tier="shallow", specimen_quality=0.0, cast_power=0.2, seed=1)
        result = FishingLoop(sc, rng=Rng(1)).run()
        self.assertEqual(result.outcome, "success")
        self.assertTrue(result.kept)
        self.assertEqual(result.decision, "keep")
        self.assertGreater(result.fight.duration, 0)
        self.assertLess(result.fight.max_danger, 100)

    def test_missed_bite(self):
        sc = Scenario(strike_delay_min=4.0, strike_delay_max=4.0, seed=1)
        result = FishingLoop(sc, rng=Rng(1)).run()
        self.assertEqual(result.outcome, "missed_bite")
        self.assertIsNone(result.fight)

    def test_release(self):
        sc = Scenario(tier="shallow", cast_power=0.2, decision="release", seed=1)
        result = FishingLoop(sc, rng=Rng(1)).run()
        self.assertEqual(result.outcome, "success")
        self.assertFalse(result.kept)

    def test_timeout_decision(self):
        sc = Scenario(tier="shallow", cast_power=0.2, decision="timeout", seed=1)
        result = FishingLoop(sc, rng=Rng(1)).run()
        self.assertEqual(result.decision, "timeout")
        self.assertAlmostEqual(result.decision_time, 9.0)

    def test_rod_breaks_on_failure(self):
        sc = Scenario(
            tier="abyss",
            specimen_quality=1.0,
            cast_power=0.95,
            rod_break_chance=100.0,
            seed=1,
        )
        result = FishingLoop(sc, rng=Rng(1), controller=FailingController()).run()
        self.assertNotEqual(result.outcome, "success")
        self.assertTrue(result.rod_broke)

    def test_deterministic(self):
        sc = Scenario(tier="deep", cast_power=0.5, seed=99)
        a = FishingLoop(sc, rng=Rng(99)).run().as_dict()
        b = FishingLoop(sc, rng=Rng(99)).run().as_dict()
        self.assertEqual(a, b)


class TestAggregateAndSimulator(unittest.TestCase):
    def _result(self, outcome="success", kept=True, duration=10.0):
        fight = FightResult(
            outcome=outcome,
            duration=duration,
            progress=100 if outcome == "success" else 0,
            max_danger=70,
            flips=5,
            time_on_target=duration,
            time_off_target=0.0,
            decisions=100,
            modes={"hold": 100},
        )
        return CastResult(
            scenario=Scenario(),
            fight_params=Scenario().fight_params(),
            distance=16.0,
            wait_time=7.0,
            strike_delay=0.2,
            fight=fight,
            outcome=outcome,
            kept=kept,
            decision="keep" if kept else "release",
            decision_time=0.6,
            total_time=7.0 + 0.2 + duration + 0.6,
        )

    def test_aggregate_counts(self):
        agg = Aggregate()
        agg.add(self._result("success", True))
        agg.add(self._result("success", False))
        agg.add(self._result("line_snapped", False))
        self.assertEqual(agg.runs, 3)
        self.assertEqual(agg.successes, 2)
        self.assertEqual(agg.kept, 1)
        self.assertEqual(agg.released, 1)
        self.assertEqual(agg.line_snaps, 1)
        self.assertAlmostEqual(agg.success_rate, 2 / 3)

    def test_simulator_deterministic(self):
        sc = Scenario(tier="mid", cast_power=0.5, seed=7)
        a = Simulator(sc, runs=5, seed=7).run().as_dict()
        b = Simulator(sc, runs=5, seed=7).run().as_dict()
        self.assertEqual(a, b)
        self.assertGreater(a["success_rate"], 0.9)


if __name__ == "__main__":
    unittest.main()
