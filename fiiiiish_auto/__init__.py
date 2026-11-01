"""fiiiiish_auto -- deterministic automation for the fiiiiish reel-in minigame.

The package has two halves:

* a faithful, headless port of the Lua fight loop plus a closed-loop
  controller (``simulate`` / ``fight`` / ``replay``), and
* a live adapter that reads the real FiveM NUI over CDP and sends relative
  mouse input (``live``).

See ANALYSE.md for the player-process breakdown and README.md for usage.
"""

from .config import (
    FISHING_CONFIG,
    FightParams,
    build_fight_params,
    distance_for_power,
    fight_difficulty,
)
from .controller import FightController
from .fight import CameraModel, FightEngine, FightState, NuiModel, NuiView
from .fishing import CastResult, Scenario, Simulator
from .loop import FightResult, FightSession

__all__ = [
    "FISHING_CONFIG",
    "FightParams",
    "build_fight_params",
    "distance_for_power",
    "fight_difficulty",
    "FightController",
    "CameraModel",
    "FightEngine",
    "FightState",
    "NuiModel",
    "NuiView",
    "CastResult",
    "Scenario",
    "Simulator",
    "FightResult",
    "FightSession",
]

__version__ = "1.0.0"
