"""The complete player loop: cast -> wait -> strike -> fight -> decide.

The live bot performs the same steps through the NUI and the mouse.  The
simulator uses this class to measure how reliable the automation is before a
single input is sent to the real game.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

from .config import (
    BITE_TIME_MAX,
    BITE_TIME_MIN,
    CATCH_DECISION_TIMEOUT,
    FISHING_CONFIG,
    FightParams,
    bite_wait_seconds,
    build_fight_params,
    distance_for_power,
    fight_difficulty,
)
from .controller import FightController
from .fight import CameraModel, NuiModel
from .loop import FightResult, FightSession
from .rng import Rng

Decision = Literal["keep", "release", "timeout"]
Tier = Literal["shallow", "mid", "deep", "abyss"]


@dataclass
class Scenario:
    """One cast, fully described.

    The defaults are a mid-depth fish with no gear bonuses: the "average"
    player.  The simulator sweeps the fields to find the worst case.
    """

    tier: Tier = "mid"
    specimen_quality: float = 0.5
    fight_ease_percent: float = 0.0
    line_strength_percent: float = 0.0
    cast_power: float = 0.5
    bite_time_reduction_percent: float = 0.0
    strike_delay_min: float = 0.15
    strike_delay_max: float = 0.35
    decision: Decision = "keep"
    rod_break_chance: float = 10.0
    rod_durability_bonus: float = 0.0
    seed: int | None = None

    def fight_params(self) -> FightParams:
        difficulty = fight_difficulty(
            self.tier, self.specimen_quality, self.fight_ease_percent
        )
        return build_fight_params(difficulty, self.line_strength_percent)

    def distance(self) -> float:
        return distance_for_power(self.cast_power)

    def difficulty(self) -> float:
        return fight_difficulty(
            self.tier, self.specimen_quality, self.fight_ease_percent
        )


@dataclass
class CastResult:
    """Everything that happened during one cast."""

    scenario: Scenario
    fight_params: FightParams
    distance: float
    wait_time: float
    strike_delay: float
    fight: FightResult | None
    outcome: str
    kept: bool = False
    decision: Decision | None = None
    decision_time: float = 0.0
    rod_broke: bool = False
    total_time: float = 0.0

    @property
    def success(self) -> bool:
        return self.outcome == "success"

    @property
    def caught(self) -> bool:
        return self.outcome == "success"

    def as_dict(self) -> dict:
        return {
            "tier": self.scenario.tier,
            "quality": round(self.scenario.specimen_quality, 3),
            "difficulty": round(self.scenario.difficulty(), 3),
            "power": round(self.scenario.cast_power, 3),
            "distance": round(self.distance, 2),
            "wait_time": round(self.wait_time, 2),
            "strike_delay": round(self.strike_delay, 3),
            "outcome": self.outcome,
            "kept": self.kept,
            "decision": self.decision,
            "decision_time": round(self.decision_time, 2),
            "fight_duration": round(self.fight.duration, 2) if self.fight else None,
            "progress": self.fight.progress if self.fight else 0,
            "max_danger": self.fight.max_danger if self.fight else 0,
            "flips": self.fight.flips if self.fight else 0,
            "rod_broke": self.rod_broke,
            "total_time": round(self.total_time, 2),
        }


class FishingLoop:
    """Runs the whole player process for one scenario."""

    def __init__(
        self,
        scenario: Scenario,
        *,
        rng: Rng | None = None,
        controller: FightController | None = None,
        camera: CameraModel | None = None,
        nui: NuiModel | None = None,
        fight_hz: float = 60.0,
        control_hz: float = 30.0,
        max_fight_duration: float = 180.0,
    ) -> None:
        self.scenario = scenario
        self.rng = rng if rng is not None else Rng(scenario.seed)
        self.controller = controller if controller is not None else FightController()
        self.camera = camera if camera is not None else CameraModel()
        self.nui = nui if nui is not None else NuiModel()
        self.fight_hz = fight_hz
        self.control_hz = control_hz
        self.max_fight_duration = max_fight_duration

    # ------------------------------------------------------------------
    def run(self) -> CastResult:
        sc = self.scenario
        params = sc.fight_params()
        distance = sc.distance()

        # --- cast -------------------------------------------------------
        # The power meter is a triangle wave; the bot releases on the first
        # ramp at the requested power.  A small timing error is modelled so
        # the simulation does not assume a perfect machine.
        power_error = self.rng.uniform(-0.015, 0.015)
        power = max(0.0, min(1.0, sc.cast_power + power_error))
        distance = distance_for_power(power)

        # --- bite wait --------------------------------------------------
        wait_time = bite_wait_seconds(self.rng, sc.bite_time_reduction_percent)

        # --- strike -----------------------------------------------------
        strike_delay = self.rng.uniform(sc.strike_delay_min, sc.strike_delay_max)
        window = FISHING_CONFIG["bite_window"] / 1000.0
        if strike_delay > window:
            return CastResult(
                scenario=sc,
                fight_params=params,
                distance=distance,
                wait_time=wait_time,
                strike_delay=strike_delay,
                fight=None,
                outcome="missed_bite",
                total_time=wait_time + window,
            )

        # --- fight ------------------------------------------------------
        fight = FightSession(
            params,
            distance,
            rng=self.rng,
            controller=self.controller,
            camera=self.camera,
            nui=self.nui,
            fight_hz=self.fight_hz,
            control_hz=self.control_hz,
            max_duration=self.max_fight_duration,
        ).run()

        if fight.outcome != "success":
            rod_broke = self._roll_rod_break()
            return CastResult(
                scenario=sc,
                fight_params=params,
                distance=distance,
                wait_time=wait_time,
                strike_delay=strike_delay,
                fight=fight,
                outcome=fight.outcome,
                rod_broke=rod_broke,
                total_time=wait_time + strike_delay + fight.duration,
            )

        # --- keep / release --------------------------------------------
        decision = sc.decision
        if decision == "timeout":
            decision_time = CATCH_DECISION_TIMEOUT / 1000.0
            kept = True
        else:
            decision_time = 0.6
            kept = decision == "keep"

        return CastResult(
            scenario=sc,
            fight_params=params,
            distance=distance,
            wait_time=wait_time,
            strike_delay=strike_delay,
            fight=fight,
            outcome="success",
            kept=kept,
            decision=decision,
            decision_time=decision_time,
            total_time=wait_time + strike_delay + fight.duration + decision_time,
        )

    # ------------------------------------------------------------------
    def _roll_rod_break(self) -> bool:
        chance = self.scenario.rod_break_chance
        durability = max(1.0 - self.scenario.rod_durability_bonus / 100.0, 0.15)
        chance *= durability
        return self.rng.random() * 100.0 < chance


@dataclass
class Aggregate:
    runs: int = 0
    successes: int = 0
    missed_bites: int = 0
    line_snaps: int = 0
    timeouts: int = 0
    rod_breaks: int = 0
    kept: int = 0
    released: int = 0
    total_wait: float = 0.0
    total_fight: float = 0.0
    total_time: float = 0.0
    total_strike: float = 0.0
    max_danger: int = 0
    total_flips: int = 0
    worst_fight: float = 0.0
    modes: dict[str, int] = field(default_factory=dict)

    @property
    def success_rate(self) -> float:
        return self.successes / self.runs if self.runs else 0.0

    @property
    def avg_wait(self) -> float:
        return self.total_wait / self.runs if self.runs else 0.0

    @property
    def avg_fight(self) -> float:
        return self.total_fight / self.successes if self.successes else 0.0

    @property
    def avg_time(self) -> float:
        return self.total_time / self.runs if self.runs else 0.0

    @property
    def avg_strike(self) -> float:
        return self.total_strike / self.runs if self.runs else 0.0

    @property
    def avg_flips(self) -> float:
        return self.total_flips / self.successes if self.successes else 0.0

    def add(self, result: CastResult) -> None:
        self.runs += 1
        self.total_wait += result.wait_time
        self.total_strike += result.strike_delay
        self.total_time += result.total_time
        if result.outcome == "success":
            self.successes += 1
            self.kept += 1 if result.kept else 0
            self.released += 0 if result.kept else 1
            if result.fight:
                self.total_fight += result.fight.duration
                self.worst_fight = max(self.worst_fight, result.fight.duration)
                self.max_danger = max(self.max_danger, result.fight.max_danger)
                self.total_flips += result.fight.flips
                for mode, count in result.fight.modes.items():
                    self.modes[mode] = self.modes.get(mode, 0) + count
        elif result.outcome == "missed_bite":
            self.missed_bites += 1
        elif result.outcome == "line_snapped":
            self.line_snaps += 1
            if result.fight:
                self.max_danger = max(self.max_danger, result.fight.max_danger)
        elif result.outcome == "timeout":
            self.timeouts += 1
        if result.rod_broke:
            self.rod_breaks += 1

    def as_dict(self) -> dict:
        return {
            "runs": self.runs,
            "successes": self.successes,
            "success_rate": round(self.success_rate, 4),
            "missed_bites": self.missed_bites,
            "line_snaps": self.line_snaps,
            "timeouts": self.timeouts,
            "rod_breaks": self.rod_breaks,
            "kept": self.kept,
            "released": self.released,
            "avg_wait": round(self.avg_wait, 2),
            "avg_fight": round(self.avg_fight, 2),
            "avg_time": round(self.avg_time, 2),
            "avg_strike": round(self.avg_strike, 3),
            "max_danger": self.max_danger,
            "avg_flips": round(self.avg_flips, 2),
            "worst_fight": round(self.worst_fight, 2),
            "modes": dict(self.modes),
        }


class Simulator:
    """Runs a scenario many times and aggregates the results."""

    def __init__(
        self,
        scenario: Scenario,
        runs: int = 200,
        *,
        seed: int | None = None,
        controller: FightController | None = None,
        fight_hz: float = 60.0,
        control_hz: float = 30.0,
        max_fight_duration: float = 180.0,
    ) -> None:
        self.scenario = scenario
        self.runs = int(runs)
        self.seed = scenario.seed if seed is None else seed
        if self.seed is None:
            self.seed = 42
        self.controller = controller
        self.fight_hz = fight_hz
        self.control_hz = control_hz
        self.max_fight_duration = max_fight_duration

    def run(self) -> Aggregate:
        agg = Aggregate()
        for i in range(self.runs):
            # One RNG per run, derived from the master seed, so a run can be
            # replayed in isolation.
            scenario = Scenario(**{**self.scenario.__dict__, "seed": self.seed + i})
            loop = FishingLoop(
                scenario,
                rng=Rng(scenario.seed),
                controller=self.controller,
                fight_hz=self.fight_hz,
                control_hz=self.control_hz,
                max_fight_duration=self.max_fight_duration,
            )
            agg.add(loop.run())
        return agg
