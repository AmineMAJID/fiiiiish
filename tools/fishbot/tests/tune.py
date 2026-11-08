"""Parameter search for the fight controller (development aid).

    python -m tests.tune

Objective: minimise the median time to land a fish across every depth band,
subject to zero snapped lines and a high win rate.  A snap is treated as a
1000-second penalty because it is the one outcome that costs the player real
progress (bait, time, and often the fish).
"""

from __future__ import annotations

import itertools
import statistics
import sys

from fishbot.controller import BotParams
from tests.test_fight import run_fight
from fishbot.gamemodel import FightParams

BANDS = ("shallow", "mid", "deep", "abyss")


def score(params: dict, seeds: int = 12) -> tuple:
    bot = BotParams(**params)
    times = []
    wins = 0
    snaps = 0
    n = 0
    for band in BANDS:
        p = FightParams.for_band(band)
        for seed in range(seeds):
            r = run_fight(p, seed=seed, bot=bot)
            n += 1
            wins += r.won
            snaps += r.snaps
            times.append(r.elapsed if r.won else 90.0)
    snap_penalty = 1000.0 * snaps
    return (snap_penalty + statistics.median(times), 100.0 * wins / n, snaps,
            round(statistics.median(times), 2))


def main() -> int:
    grid = {
        "target_pct": [86.0, 89.0, 92.0, 95.0],
        "reverse_margin_pct": [28.0, 36.0, 46.0, 60.0],
        "guard_pct": [96.0, 98.0, 99.5],
        "step_up_pct": [18.0, 22.0, 26.0],
        "probe_pct": [26.0],
        "stall_ticks": [2],
        "deadband_pct": [4.0],
    }
    keys = list(grid)
    results = []
    combos = list(itertools.product(*(grid[k] for k in keys)))
    print(f"evaluating {len(combos)} combinations...")
    for combo in combos:
        params = dict(zip(keys, combo))
        if params["guard_pct"] <= params["target_pct"]:
            continue
        cost, win, snaps, med = score(params)
        results.append((cost, win, snaps, med, params))
    results.sort(key=lambda r: r[0])
    print(f"\n{'cost':>9}{'win %':>7}{'snaps':>7}{'med s':>7}  params")
    for cost, win, snaps, med, params in results[:12]:
        print(f"{cost:9.1f}{win:7.1f}{snaps:7d}{med:7.2f}  {params}")
    print("\nworst 3:")
    for cost, win, snaps, med, params in results[-3:]:
        print(f"{cost:9.1f}{win:7.1f}{snaps:7d}{med:7.2f}  {params}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
