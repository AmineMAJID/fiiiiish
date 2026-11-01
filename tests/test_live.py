"""Tests for the live adapters (no Windows, no game required)."""

from __future__ import annotations

import unittest
from unittest import mock

from fiiiiish_auto import nui as nui_module
from fiiiiish_auto.fight import NuiView
from fiiiiish_auto.input import DryRunInput, LiveCamera
from fiiiiish_auto.live import LiveBot, LiveBotConfig
from fiiiiish_auto.nui import BiteView, CastView, DecisionView


class MockNui:
    def __init__(
        self,
        *,
        fight_views=None,
        cast_views=None,
        bite_views=None,
        decision_views=None,
        can_cast=False,
        click_keep_result=True,
    ):
        self.fight_views = list(fight_views or [])
        self.cast_views = list(cast_views or [])
        self.bite_views = list(bite_views or [])
        self.decision_views = list(decision_views or [])
        self.can_cast_result = can_cast
        self.click_keep_result = click_keep_result

    def read_fight(self):
        return self.fight_views.pop(0) if self.fight_views else None

    def read_cast(self):
        return self.cast_views.pop(0) if self.cast_views else None

    def read_bite(self):
        return self.bite_views.pop(0) if self.bite_views else None

    def read_decision(self):
        return self.decision_views.pop(0) if self.decision_views else None

    def can_cast(self):
        return self.can_cast_result

    def click_keep(self):
        return self.click_keep_result

    def close(self):
        pass


class TestInputAdapters(unittest.TestCase):
    def test_dry_run_input(self):
        logs = []
        mouse = DryRunInput(log=logs.append)
        mouse.move(10, 0)
        mouse.left_down()
        mouse.left_up()
        mouse.press_e()
        self.assertEqual(mouse.steps, 1)
        self.assertEqual(mouse.buttons, 2)
        self.assertEqual(mouse.keys, 1)
        self.assertEqual(len(logs), 4)

    def test_live_camera_accumulates_fractional_pixels(self):
        logs = []
        mouse = DryRunInput(log=logs.append)
        cam = LiveCamera(mouse, sensitivity=0.1)
        cam.apply(1.0, 1 / 30)  # 10 px
        self.assertEqual(mouse.steps, 1)
        cam.apply(0.01, 1 / 30)  # 0.1 px, rounds to zero
        self.assertEqual(mouse.steps, 1)
        cam.apply(0.06, 1 / 30)  # 0.6 px + remainder -> 1 px
        self.assertEqual(mouse.steps, 2)

    def test_live_camera_inverts(self):
        logs = []
        mouse = DryRunInput(log=logs.append)
        cam = LiveCamera(mouse, sensitivity=0.1, invert_x=True)
        cam.apply(1.0, 1 / 30)
        self.assertEqual(mouse.steps, 1)
        self.assertIn("-10", logs[-1])


class TestNuiReaderParsing(unittestrection if False else unittest.TestCase):
    pass


class TestNuiReaderParsingReal(TestNuiReaderParsing):
    def runTest(self):
        pass


class TestNuiReaderParsingActual(unittest.TestCase):
    def test_parsing(self):
        class MockCdp:
            def __init__(self, *args, **kwargs):
                pass

            def evaluate(self, expression):
                if expression == nui_module.JS_FIGHT:
                    return {
                        "side": "left",
                        "danger": 42,
                        "progress": 17,
                        "active": True,
                        "verdict": None,
                    }
                if expression == nui_module.JS_CAST:
                    return {"power": 50, "charging": True, "locked": False}
                if expression == nui_module.JS_BITE:
                    return {"state": "bite"}
                if expression == nui_module.JS_DECISION:
                    return {"open": True}
                if expression == nui_module.JS_CAN_CAST:
                    return True
                if expression == nui_module.JS_CLICK_KEEP:
                    return True
                return None

            def close(self):
                pass

        with mock.patch.object(nui_module, "CdpClient", MockCdp):
            reader = nui_module.NuiReader()
            view = reader.read_fight()
            self.assertEqual(view.danger, 42)
            self.assertEqual(view.progress, 17)
            self.assertEqual(view.side, "left")
            self.assertTrue(view.active)
            self.assertEqual(reader.read_cast().power, 50)
            self.assertTrue(reader.read_cast().charging)
            self.assertEqual(reader.read_bite().state, "bite")
            self.assertTrue(reader.read_decision().open)
            self.assertTrue(reader.can_cast())
            self.assertTrue(reader.click_keep())


class TestLiveBotSteps(unittest.TestCase):
    def test_run_fight(self):
        views = [NuiView(danger=0, progress=0, side=None, active=True) for _ in range(5)]
        views.append(
            NuiView(danger=0, progress=100, side=None, active=False, verdict="NICE_CATCH")
        )
        nui = MockNui(fight_views=views)
        mouse = DryRunInput(log=lambda msg: None)
        bot = LiveBot(LiveBotConfig(), nui=nui, mouse=mouse)
        bot.run_fight()
        self.assertEqual(bot.stats["fight_starts"], 1)
        self.assertEqual(bot.stats["fight_successes"], 1)
        self.assertGreater(mouse.steps, 0)

    def test_run_cast(self):
        cast_views = [
            CastView(0, False, False),
            CastView(50, True, False),
            CastView(50, False, True),
            None,
        ]
        nui = MockNui(cast_views=cast_views, bite_views=[BiteView("waiting")])
        mouse = DryRunInput(log=lambda msg: None)
        bot = LiveBot(LiveBotConfig(cast_power=0.5), nui=nui, mouse=mouse)
        bot.run_cast()
        self.assertEqual(bot.stats["casts"], 1)
        self.assertEqual(mouse.keys, 1)
        self.assertEqual(mouse.buttons, 2)

    def test_run_bite(self):
        nui = MockNui(bite_views=[BiteView("waiting"), BiteView("bite")])
        mouse = DryRunInput(log=lambda msg: None)
        bot = LiveBot(LiveBotConfig(), nui=nui, mouse=mouse)
        bot.run_bite()
        self.assertEqual(mouse.keys, 1)

    def test_run_decision(self):
        nui = MockNui(decision_views=[DecisionView(open=True)])
        mouse = DryRunInput(log=lambda msg: None)
        bot = LiveBot(LiveBotConfig(), nui=nui, mouse=mouse)
        bot.run_decision()
        self.assertEqual(bot.stats["decisions"], 1)


if __name__ == "__main__":
    unittest.main()
