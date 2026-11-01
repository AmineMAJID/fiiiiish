"""Wire the fight engine, camera, NUI and controller together.

This is the same loop the live bot runs, except the live bot swaps the
``NuiModel`` for a real DOM reader and the ``CameraModel`` for a mouse.
Keeping the wiring in one place means the simulated and live controllers
cannot drift apart.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from .config import DEFAULT_CONTROL_HZ, DEFAULT_FIGHT_HZ, FightParams
from .controller import ControlDecision, FightController
from .fight import CameraModel, FightEngine, FightState, NuiModel, NuiView
from .rng import Rng


class NuiSource(Protocol):
    def read(self) -> NuiView: ...

    def update(self, engine: FightEngine, dt: float) -> None: ...


@dataclass
class FightResult:
    outcome: str
    duration: float
    progress: int
    max_danger: int
    flips: int
    time_on_target: float
    time_off_target: float
    decisions: int
    modes: dict[str, int] = field(default_factory=dict)
    final_state: dict = field(default_factory=dict)
    trace: list[dict] = field(default_factory=list)

    @property
    def success(self) -> bool:
        return self.outcome == "success"


class FightSession:
    """Runs one fight with a fixed simulation step."""

    def __init__(
        self,
        params: FightParams,
        initial_distance: float,
        seed: int | str | None = None,
        *,
        controller: FightController | None = None,
        camera: CameraModel | None = None,
        nui: NuiModel | None = None,
        fight_hz: float = DEFAULT_FIGHT_HZ,
        control_hz: float = DEFAULT_CONTROL_HZ,
        max_duration: float = 180.0,
        record: bool = False,
        rng: Rng | None = None,
    ) -> None:
        self.params = params
        self.initial_distance = float(initial_distance)
        self.rng = rng if rng is not None else Rng(seed)
        self.engine = FightEngine(params, self.initial_distance, self.rng)
        self.controller = controller or FightController()
        self.camera = camera or CameraModel()
        self.nui = nui or NuiModel()
        self.fight_hz = float(fight_hz)
        self.control_hz = float(control_hz)
        self.max_duration = float(max_duration)
        self.record = record
        self.trace: list[dict] = []
        self.modes: dict[str, int] = {}
        self.now = 0.0
        self._frame = 0
        self._control_every = max(1, int(round(self.fight_hz / self.control_hz)))

    # ------------------------------------------------------------------
    def run(self) -> FightResult:
        dt = 1.0 / self.fight_hz
        dt_control = 1.0 / self.control_hz
        self.controller.reset()
        self.nui.reset()
        self.camera.angle = 0.0
        self.now = 0.0
        self._frame = 0

        # Prime the NUI so the first control tick sees an active fight.
        self.nui.update(self.engine, 0.0)

        while self.engine.state.active and self.now < self.max_duration:
            if self._frame % self._control_every == 0:
                view = self.nui.read()
                decision = self.controller.tick(view, dt_control, self.now)
                self.modes[decision.mode] = self.modes.get(decision.mode, 0) + 1
                self.camera.apply(decision.step, dt_control)
                if self.record:
                    self.trace.append(
                        {
                            "t": round(self.now, 4),
                            "view": view.as_dict(),
                            "step": round(decision.step, 3),
                            "mode": decision.mode,
                            "reason": decision.reason,
                        }
                    )

            self.engine.set_angle(self.camera.angle)
            self.engine.step(dt)
            self.nui.update(self.engine, dt)
            self.now += dt
            self._frame += 1

        st = self.engine.state
        if st.active:
            # Ran out of time without a snap or a success.
            st.active = False
            st.outcome = "timeout"

        return FightResult(
            outcome=st.outcome or "timeout",
            duration=self.now,
            progress=int(round(st.progress * 100.0)),
            max_danger=st.max_danger,
            flips=st.flips,
            time_on_target=st.time_on_target,
            time_off_target=st.time_off_target,
            decisions=self.controller.decisions,
            modes=dict(self.modes),
            final_state=st.as_dict(),
            trace=self.trace if self.record else [],
        )


def simulate_fight(
    params: FightParams,
    initial_distance: float,
    seed: int | str | None = None,
    *,
    controller: FightController | None = None,
    camera: CameraModel | None = None,
    nui: NuiModel | None = None,
    fight_hz: float = DEFAULT_FIGHT_HZ,
    control_hz: float = DEFAULT_CONTROL_HZ,
    max_duration: float = 180.0,
    record: bool = False,
    rng: Rng | None = None,
) -> FightResult:
    """Convenience wrapper around :class:`FightSession`."""
    return FightSession(
        params,
        initial_distance,
        seed,
        controller=controller,
        camera=camera,
        nui=nui,
        fight_hz=fight_hz,
        control_hz=control_hz,
        max_duration=max_duration,
        record=record,
        rng=rng,
    ).run()
