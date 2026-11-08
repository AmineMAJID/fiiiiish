"""Closed-loop fight tests: the controller against the resource's real physics.

    python -m tests.test_fight

The number that matters is not only "does it win" but "does it win without ever
crossing the snap threshold", because that is what decides whether the tool
loses fish the player would have landed.
"""

from __future__ import annotations

import statistics
import sys
from dataclasses import dataclass
from typing import Optional

from fishbot.controller import BotParams, FightController
from fishbot.gamemodel import FightParams, FightSimulator


@dataclass
class Outcome:
    won: bool
    snaps: int
    max_pct: float
    ticks: int
    elapsed: float
    calibrated: bool


def run_fight(params: FightParams, seed: int, bot: Optional[BotParams] = None,
              initial_dist: float = 10.0, sample_dt: float = 0.05,
              max_seconds: float = 90.0, noise_pct: float = 0.0,
              start_direction: int = 1, inverted: bool = False,
              counts_guess: Optional[float] = None) -> Outcome:
    """Play one fight with the controller reading the HUD at 5 Hz.

    ``inverted=True`` flips the sign of the camera response, which is exactly
    what an inverted-mouse client looks like to the controller: it must discover
    the direction itself, and this proves it does.
    """
    import random

    bot = bot or BotParams()
    if counts_guess is not None:
        bot.counts_per_pct = counts_guess
    sim = FightSimulator(params, initial_dist=initial_dist, seed=seed)
    ctrl = FightController(params=bot)
    ctrl.reset(max_angle=params.max_angle, direction=start_direction)
    rng = random.Random(seed + 9999)

    max_pct = 0.0
    ticks = 0
    snaps = 0
    percent_per_danger = 100.0 / params.max_angle

    while sim.state.outcome is None and sim.state.elapsed < max_seconds:
        tension, progress, side, _ = sim.observe()
        pct = tension * 100.0
        if noise_pct:
            pct = max(0.0, min(100.0, pct + rng.uniform(-noise_pct, noise_pct)))
        max_pct = max(max_pct, pct)

        decision = ctrl.tick(tension=pct / 100.0, side=side, progress=progress)
        if decision.counts:
            danger_delta = (decision.counts / ctrl.params.counts_per_pct) / percent_per_danger
            sim.apply_camera(-danger_delta if inverted else danger_delta)
        sim.tick(sample_dt)
        ticks += 1
        if sim.state.outcome == "lost_tension":
            snaps += 1

    return Outcome(won=sim.state.outcome == "won", snaps=snaps, max_pct=max_pct,
                   ticks=ticks, elapsed=sim.state.elapsed, calibrated=ctrl.calibrated)


def sweep(seeds: int = 120, noise_pct: float = 0.0, start_direction: int = 1,
          inverted: bool = False, counts_guess: Optional[float] = None):
    rows = []
    for band in ("shallow", "mid", "deep", "abyss"):
        for label, params in ((band, FightParams.for_band(band)),
                              (band + "+gear", FightParams.for_band(band, fight_ease=40,
                                                                    line_strength=15))):
            results = [run_fight(params, seed=s, noise_pct=noise_pct,
                                 start_direction=start_direction, inverted=inverted,
                                 counts_guess=counts_guess) for s in range(seeds)]
            wins = sum(r.won for r in results)
            rows.append({
                "band": label,
                "maxAngle": round(params.max_angle, 1),
                "pull": round(params.pull_speed, 4),
                "win%": round(100.0 * wins / seeds, 1),
                "snapped": sum(1 for r in results if r.snaps),
                "p95max": round(sorted(r.max_pct for r in results)[int(0.95 * seeds)], 1),
                "median": round(statistics.median(r.elapsed for r in results), 1),
            })
    return rows


def print_rows(rows, title: str) -> float:
    print(f"\n{title}")
    head = f"{'band':<14}{'maxAng':>8}{'pull':>8}{'win %':>8}{'snaps':>7}{'p95max':>8}{'med s':>8}"
    print(head)
    print("-" * len(head))
    worst = 100.0
    for r in rows:
        print(f"{r['band']:<14}{r['maxAngle']:>8}{r['pull']:>8}{r['win%']:>8}"
              f"{r['snapped']:>7}{r['p95max']:>8}{r['median']:>8}")
        worst = min(worst, r["win%"])
    return worst


def main() -> int:
    print("=" * 70)
    print("FIGHT SWEEP - controller vs. the resource's physics")
    print("=" * 70)
    worst = 100.0
    worst = min(worst, print_rows(sweep(160), "Baseline (120+ fights per row)"))
    worst = min(worst, print_rows(sweep(80, noise_pct=3.0),
                                  "HUD reading noise +/-3 % (pixel reader worst case)"))
    worst = min(worst, print_rows(sweep(80, start_direction=-1),
                                  "Starting in the wrong direction"))
    worst = min(worst, print_rows(sweep(80, inverted=True),
                                  "Inverted mouse (controller must discover the sign)"))
    worst = min(worst, print_rows(sweep(80, counts_guess=0.6),
                                  "Bad sensitivity guess (0.6 counts/%)"))
    worst = min(worst, print_rows(sweep(80, counts_guess=9.0),
                                  "Bad sensitivity guess (9 counts/%)"))
    print(f"\nWORST ROW: {worst:.1f} %")
    return 0 if worst >= 90.0 else 1


if __name__ == "__main__":
    sys.exit(main())
