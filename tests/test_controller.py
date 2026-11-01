"""Tests for the closed-loop controller."""

from __future__ import annotations

import unittest

from fiiiiish_auto.controller import FightController
from fiiiiish_auto.fight import NuiView


def view(danger=0, progress=0, side=None, active=True, verdict=None):
    return NuiView(danger=danger, progress=progress, side=side, active=active, verdict=verdict)


class TestTriggerAndCross(unittest.TestCase):
    def test_trigger_moves_right(self):
        c = FightController()
        d = c.tick(view(), 1 / 30, 0.0)
        self.assertEqual(d.mode, "trigger")
        self.assertGreater(d.step, 0)

    def test_trigger_caps_at_30(self):
        c = FightController()
        d = c.tick(view(danger=30), 1 / 30, 0.0)
        self.assertEqual(d.step, 0)

    def test_first_side_enters_cross(self):
        c = FightController()
        d = c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        self.assertEqual(d.mode, "cross")
        self.assertLess(d.step, 0)

    def test_cross_hands_over_to_hold(self):
        c = FightController()
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        for i, danger in enumerate((60, 40, 20, 10, 12, 20, 30, 45, 60, 70)):
            d = c.tick(view(danger=danger, side="left"), 1 / 30, 0.033 * (i + 1))
            if d.mode == "hold":
                break
        self.assertEqual(d.mode, "hold")

    def test_hold_deadband(self):
        c = FightController(setpoint=75.0, deadband=3.0, reaction_delay=0.0)
        # First tick reveals the side and enters cross; a rising danger hands
        # over to hold; at the setpoint the hold loop does nothing.
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        d = c.tick(view(danger=75, side="left"), 1 / 30, 0.033)
        self.assertEqual(d.mode, "hold")
        self.assertEqual(d.step, 0)

    def test_hold_corrects_below(self):
        c = FightController(setpoint=75.0, deadband=3.0, reaction_delay=0.0)
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        c.tick(view(danger=75, side="left"), 1 / 30, 0.033)
        d = c.tick(view(danger=60, side="left"), 1 / 30, 0.066)
        self.assertLess(d.step, 0)

    def test_hold_corrects_above(self):
        c = FightController(setpoint=75.0, deadband=3.0, reaction_delay=0.0)
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        c.tick(view(danger=75, side="left"), 1 / 30, 0.033)
        d = c.tick(view(danger=90, side="left"), 1 / 30, 0.066)
        self.assertGreater(d.step, 0)

    def test_emergency_steers_back(self):
        c = FightController(setpoint=75.0, emergency=92.0)
        d = c.tick(view(danger=95, side="left"), 1 / 30, 0.0)
        self.assertEqual(d.mode, "safety")
        self.assertGreater(d.step, 0)

    def test_step_is_capped(self):
        c = FightController(max_step=6.0, hold_step=2.5)
        c.tick(view(danger=75, side="left"), 1 / 30, 0.0)
        for danger in (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95):
            d = c.tick(view(danger=danger, side="left"), 1 / 30, 0.033)
            self.assertLessEqual(abs(d.step), 6.0 + 1e-9)

    def test_reaction_delay_holds_old_side(self):
        c = FightController(reaction_delay=0.2, setpoint=75.0)
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        # Side flips to right, but the bot must not react for 200 ms.
        for i in range(1, 6):
            d = c.tick(view(danger=70, side="right"), 1 / 30, i / 30)
            self.assertLess(d.step, 0)
        d = c.tick(view(danger=70, side="right"), 1 / 30, 0.25)
        self.assertGreater(d.step, 0)

    def test_inactive_resets(self):
        c = FightController()
        c.tick(view(danger=70, side="left"), 1 / 30, 0.0)
        d = c.tick(view(active=False), 1 / 30, 0.1)
        self.assertEqual(d.mode, "idle")
        self.assertEqual(d.step, 0)


if __name__ == "__main__":
    unittest.main()
