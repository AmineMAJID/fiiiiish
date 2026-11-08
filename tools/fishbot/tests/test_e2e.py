"""End-to-end test: the bot against a fake game, through the real vision layer.

    python -m tests.test_e2e

Nothing is handed to the bot here.  It gets a rendered frame, it reads the HUD
with its own pixel code, and it drives the fake client with mouse and keyboard
events the way it would drive GTA.  The fake client knows nothing about the bot
except what a real client would see, including an unknown camera sign.
"""

from __future__ import annotations

import sys
from typing import List

try:
    import numpy as np
    HAVE_NUMPY = True
except Exception:
    HAVE_NUMPY = False

from fishbot.bot import (BITE_WAIT, DECISION, FIGHT, PAUSED, WAITING, BotConfig,
                         FishingBot)
from fishbot.controller import BotParams, FightController
from tests.fakegame import FakeGame, FakeInjector

failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
    if not ok:
        failures.append(f"{name} {detail}")


class Loop:
    """Runs the bot and the fake game in lockstep."""

    def __init__(self, game: FakeGame, config: BotConfig | None = None,
                 bot_params: BotParams | None = None):
        self.game = game
        self.injector = FakeInjector(game=game)
        game.injector = self.injector
        self.config = config or BotConfig(loop_hz=20.0, fight_timeout=60.0)
        # The bot sleeps on the *game's* clock: every "wait for the animation"
        # advances the fake world instead of stalling the test.
        self.bot = FishingBot(source=game, injector=self.injector, config=self.config,
                              controller=FightController(params=bot_params or BotParams()),
                              sleep=game.advance)
        self.events: List[str] = []

    def run(self, seconds: float, until=None) -> None:
        dt = 1.0 / self.config.loop_hz
        steps = int(seconds / dt)
        for _ in range(steps):
            if until and until():
                return
            if self.bot.stopped:
                return
            self.bot.step()
            self.game.advance(dt)

    def run_until_fish(self, seconds: float = 200.0, target: int = 1) -> None:
        dt = 1.0 / self.config.loop_hz
        for _ in range(int(seconds / dt)):
            if self.bot.stopped:
                return
            self.bot.step()
            self.game.advance(dt)
            if len(self.game.decisions) >= target:
                # let the modal click land
                for _ in range(4):
                    self.bot.step()
                    self.game.advance(dt)
                return


def test_happy_path() -> None:
    print("\n[full loop: cast -> bite -> strike -> reel -> keep, three fish]")
    game = FakeGame(seed=7)
    loop = Loop(game)
    loop.run_until_fish(seconds=240, target=3)
    st = loop.bot.status
    check("three catches decided", len(game.decisions) >= 3,
          f"decisions={len(game.decisions)} landed={game.landed}")
    check("every decision was KEEP", all(game.decisions), f"{game.decisions}")
    check("no line snapped", game.snapped == 0, f"snaps={game.snapped}")
    check("no stray input mistakes", not game.mistakes, f"{game.mistakes[:3]}")
    check("kept counter tracks the decisions", st.fish_kept == len(game.decisions),
          f"kept={st.fish_kept} decisions={len(game.decisions)}")
    check("cast power was never refused", game.casts >= 3, f"casts={game.casts}")
    check("casts were near full power", game.power >= 0.9, f"power={game.power:.2f}")
    print("     " + st.summary())


def test_inverted_mouse() -> None:
    print("\n[inverted mouse: the bot must discover the sign itself]")
    game = FakeGame(seed=11, inverted=True)
    loop = Loop(game)
    loop.run_until_fish(seconds=240, target=2)
    check("caught fish with an inverted camera", len(game.decisions) >= 2,
          f"decisions={len(game.decisions)}")
    check("no line snapped with an inverted camera", game.snapped == 0, f"{game.snapped}")


def test_wrong_sensitivity() -> None:
    print("\n[the player's DPI is nothing like the guess]")
    for counts in (0.4, 5.0, 12.0):
        game = FakeGame(seed=23, counts_per_pct=counts)
        loop = Loop(game)
        loop.run_until_fish(seconds=260, target=2)
        check(f"caught fish at {counts} counts/%", len(game.decisions) >= 2,
              f"decisions={len(game.decisions)} snaps={game.snapped}")


def test_release_mode() -> None:
    print("\n[RELEASE mode clicks the other button]")
    game = FakeGame(seed=5)
    loop = Loop(game, config=BotConfig(loop_hz=20.0, keep=False))
    loop.run_until_fish(seconds=240, target=2)
    check("decisions are RELEASE", game.decisions and not any(game.decisions),
          f"{game.decisions}")
    check("released counter", loop.bot.status.fish_released >= 1,
          f"{loop.bot.status.fish_released}")


def test_pause_on_full_bag() -> None:
    print("\n[an error toast pauses the bot instead of guessing]")
    game = FakeGame(seed=3)
    loop = Loop(game)
    loop.run_until_fish(seconds=240, target=1)
    game.toast_error = True
    loop.run(seconds=1.0)
    check("paused on the red toast", loop.bot.status.state == PAUSED,
          f"state={loop.bot.status.state} reason={loop.bot.status.paused_reason!r}")
    before = loop.bot.status.casts
    loop.run(seconds=3.0)
    check("no input while paused", loop.bot.status.casts == before,
          f"casts moved {before} -> {loop.bot.status.casts}")
    check("the pause is sticky until the user says resume", loop.bot.paused, "still paused")
    loop.bot.resume()
    game.toast_error = False
    loop.run(seconds=1.0)
    check("resumed cleanly", loop.bot.status.state != PAUSED and not loop.bot.paused,
          f"state={loop.bot.status.state}")

    # and the loop actually continues afterwards
    before = len(game.decisions)
    loop.run_until_fish(seconds=180, target=before + 1)
    check("fishing continues after the resume", len(game.decisions) > before,
          f"decisions {before} -> {len(game.decisions)}")


def test_resolutions() -> None:
    print("\n[same behaviour at other resolutions, worlds and brightness]")
    for (w, h, world) in ((1280, 720, "sea"), (2560, 1440, "night"), (3840, 2160, "bright")):
        game = FakeGame(width=w, height=h, seed=31, world=world)
        loop = Loop(game)
        loop.run_until_fish(seconds=240, target=1)
        check(f"caught a fish at {w}x{h} ({world})", len(game.decisions) >= 1,
              f"decisions={len(game.decisions)} snaps={game.snapped}")


def test_start_mid_fight() -> None:
    print("\n[started while a fish is already hooked]")
    game = FakeGame(seed=17)
    inj = FakeInjector(game=game)
    game.injector = inj
    # get the game into a reel before the bot ever looks at the screen
    game.on_key("e")
    game.on_mouse("left", True)
    game.advance(0.62)
    game.on_mouse("left", False)
    game.advance(2.0)
    game.on_key("e")
    check("fake game is reeling", game.state == "fight", game.state)
    loop = Loop(game)
    loop.run_until_fish(seconds=120, target=1)
    check("picked up the fight that was already running", len(game.decisions) >= 1,
          f"decisions={len(game.decisions)} state={loop.bot.status.state}")


def test_cast_card_blocks_second_cast() -> None:
    print("\n[the power card on screen prevents a second cast]")
    game = FakeGame(seed=19)
    loop = Loop(game)
    loop.run(seconds=6.0)
    check("exactly one cast was sent", game.casts == 1, f"casts={game.casts}")


def test_no_click_during_fight() -> None:
    print("\n[the reel is keyboard/mouse-free: only camera motion]")
    game = FakeGame(seed=13)
    loop = Loop(game)
    loop.run_until_fish(seconds=200, target=1)
    states_seen = {e[2] for e in loop.bot._events}
    clicks = [e for e in loop.injector.events if e[0] == "click"]
    keys = [e for e in loop.injector.events if e[0] == "key"]
    # every key press must belong to a cast or a strike, never to a reel
    check("clicks only happen for the catch decision", len(clicks) <= len(game.decisions) + 1,
          f"clicks={len(clicks)} decisions={len(game.decisions)}")
    check("key presses are bounded by casts + strikes",
          len(keys) <= 2 * (game.casts + 1) + 2, f"keys={len(keys)} casts={game.casts}")
    check("the fight state was exercised", FIGHT in states_seen, f"{sorted(states_seen)}")


def test_status_downlink() -> None:
    print("\n[the numbers the player reads are the numbers that happened]")
    game = FakeGame(seed=5)
    loop = Loop(game)
    loop.run_until_fish(seconds=240, target=3)
    st = loop.bot.status
    check("kept count equals catches", st.fish_kept == len(game.decisions) == 3,
          f"kept={st.fish_kept} decisions={len(game.decisions)}")
    check("cast count equals the game's casts", st.casts == game.casts,
          f"casts={st.casts}/{game.casts}")
    check("fights won equals fish landed", st.fights_won == game.landed,
          f"won={st.fights_won} landed={game.landed}")
    check("no fight was reported lost", st.fights_lost == 0, f"{st.fights_lost}")
    check("uptime follows the game's clock", abs(st.uptime - game.time) < 1.0,
          f"uptime={st.uptime:.1f} game={game.time:.1f}")
    line = st.summary()
    check("the summary line is populated", "casts=3" in line and "landed=3" in line, line)
    print("     " + line)


def test_cast_gate() -> None:
    print("\n[the game decides: no cast while its prompt is grey]")
    game = FakeGame(seed=41)
    loop = Loop(game)
    loop.run_until_fish(seconds=200, target=1)
    check("cast while the prompt was green", game.casts >= 1, f"casts={game.casts}")

    game.blocked = True
    casts_before = game.casts
    loop.run(seconds=15.0)
    check("no cast while the game refuses", game.casts == casts_before,
          f"casts {casts_before} -> {game.casts}")
    check("it says why", "cannot cast" in loop.bot.status.last_event,
          f"{loop.bot.status.last_event!r}")

    game.blocked = False
    loop.run_until_fish(seconds=200, target=2)
    check("casts again once the prompt is green", game.casts > casts_before,
          f"casts {casts_before} -> {game.casts}")
    check("no refused casts overall", "cast while the game was refusing it" not in game.mistakes,
          f"{game.mistakes[:2]}")


def test_mixed_conditions() -> None:
    print("\n[randomised clients: sensitivity, band, mouse sign, bite timing]")
    import random
    rng = random.Random(2026)
    for i in range(4):
        counts = rng.choice([0.5, 0.9, 1.6, 3.0, 6.0])
        band = rng.choice(["shallow", "mid", "deep", "abyss"])
        inverted = bool(i % 2)
        game = FakeGame(seed=900 + i, counts_per_pct=counts, band=band,
                        inverted=inverted,
                        bite_seconds=rng.choice([0.8, 1.6, 2.4]),
                        window_seconds=rng.choice([1.2, 1.6, 2.0]))
        loop = Loop(game, config=BotConfig(loop_hz=20.0, fight_timeout=90.0))
        loop.run_until_fish(seconds=300, target=2)
        ok = len(game.decisions) >= 2 and game.snapped == 0 and not game.mistakes
        check(f"two fish from a {band} client at {counts} counts/%"
              f"{' (inverted)' if inverted else ''}", ok,
              f"decisions={len(game.decisions)} snaps={game.snapped} "
              f"mistakes={game.mistakes[:1]}")


def main() -> int:
    if not HAVE_NUMPY:
        print("numpy is required for the end-to-end tests")
        return 2
    test_happy_path()
    test_inverted_mouse()
    test_wrong_sensitivity()
    test_release_mode()
    test_pause_on_full_bag()
    test_resolutions()
    test_start_mid_fight()
    test_cast_card_blocks_second_cast()
    test_no_click_during_fight()
    test_cast_gate()
    test_status_downlink()
    test_mixed_conditions()
    print()
    if failures:
        print(f"{len(failures)} FAILURES")
        for f in failures:
            print("  -", f)
        return 1
    print("all end-to-end checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
