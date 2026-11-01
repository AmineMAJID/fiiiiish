"""Configuration typée, sérialisable en JSON, avec fusion récursive des valeurs.

Toutes les valeurs sont modifiables dans ``fishing_bot_config.json``. Les
valeurs par défaut correspondent à la configuration livrée dans le dépôt
(``config/config.lua``, ``client/fishing.lua``, ``web/build/assets/*.css``).
"""

from __future__ import annotations

import copy
import json
from dataclasses import asdict, dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any, get_type_hints


def _merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Fusion récursive : les clés absentes de ``override`` gardent leur défaut."""
    out = copy.deepcopy(base)
    for key, value in override.items():
        if key in out and isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def _from_dict(cls: type, data: dict[str, Any]) -> Any:
    """Construit un dataclass imbriqué depuis un dictionnaire partiel."""
    hints = get_type_hints(cls)
    kwargs: dict[str, Any] = {}
    for f in fields(cls):
        value = data.get(f.name, None)
        if value is None:
            continue
        ftype = hints.get(f.name, f.type)
        # list[int] | None -> on ne veut construire que les vrais dataclasses.
        if isinstance(ftype, type) and is_dataclass(ftype) and isinstance(value, dict):
            kwargs[f.name] = _from_dict(ftype, value)
        else:
            kwargs[f.name] = value
    return cls(**kwargs)


@dataclass
class Keys:
    interact: str = "e"          # control 38 : E
    inventory: str = "tab"       # à adapter : ox=tab, qb=f2, esx=f2/i ...
    cancel: str = "esc"          # control 200
    stop: str = "f12"            # coupe-circuit global


@dataclass
class Timing:
    # Charge : 1100 ms de montée, 1100 ms de descente (client/fishing.lua).
    charge_cycle_ms: int = 1100
    charge_latency_ms: int = 10       # compensation de la latence SendInput
    charge_ready_delay_ms: int = 120  # E -> appui du clic gauche
    key_press_ms: int = 60
    between_casts_ms: int = 1700      # > cooldown serveur de 1500 ms
    poll_interval_ms: int = 45
    bite_min_s: float = 1.0           # garde-fou : jamais de E avant ça
    bite_timeout_s: float = 15.0      # 10 s d'attente + 3 s de fenêtre + marge
    fight_timeout_s: float = 90.0
    decision_timeout_s: float = 3.5
    action_delay_ms: int = 300        # délai après une séquence d'actions UI


@dataclass
class CastConfig:
    enabled: bool = True              # Config.Cast.Enabled
    target_power: float = 0.86        # 0.05 mini côté serveur, 1.0 = 26 m
    power_tolerance: float = 0.04
    min_power: float = 0.05           # MIN_CAST_POWER (server/fishing.lua)
    hold_offset_ms: int = 0           # calibré automatiquement si auto_calibrate
    auto_calibrate: bool = True       # corrige le timing avec la puissance lue
    track: list[int] | None = None    # [x1,y1,x2,y2] pixels, override manuel
    reference_size: list[int] | None = None  # [W,H] lors de la calibration


@dataclass
class FightConfig:
    actuator: str = "mouse"           # "mouse" (rotation caméra) ou "strafe"
    mouse_step_px: int = 10           # déplacement relatif par tick
    strafe_key_right: str = "d"
    strafe_key_left: str = "a"
    initial_dir: int = 1              # +1 = souris vers la droite / touche D
    min_progress_rate: float = 3.0    # px/s : seuil "ça avance"
    stall_flip_s: float = 1.5         # inversion si aucun progrès
    danger_pause: bool = True         # pause quand la ligne est en danger
    crossing_boost: float = 1.8       # accélère la traversée de la zone morte
    max_step_px: int = 26


@dataclass
class DecisionConfig:
    choice: str = "keep"              # "keep" ou "release"
    # Position relative des boutons dans la modale (voir ANALYSE.md).
    keep_rel: list[float] = field(default_factory=lambda: [0.26, 0.78])
    release_rel: list[float] = field(default_factory=lambda: [0.74, 0.78])
    bbox: list[int] | None = None     # [x1,y1,x2,y2] override manuel
    # Dimensions CSS de la modale : 28.75rem * zoom(1.4), hauteur mesurée.
    modal_width_px: float = 644.0
    modal_height_px: float = 503.0
    right_margin_ratio: float = 0.02  # padding-right: 2vw


@dataclass
class UIConfig:
    scale: float = 1.0                # zoom NUI (1.0 en 1920x1080 standard)
    window_titles: list[str] = field(default_factory=lambda: ["FiveM", "Grand Theft Auto V"])
    monitor: int = 1                  # index mss (1 = écran principal)
    require_focus: bool = True


@dataclass
class Actions:
    """Séquences d'actions UI génériques (inventaire, kit, boutique).

    Chaque action est un dict : {"type": "...", ...}. Types acceptés :
    sleep(ms), key(key), keydown(key), keyup(key), move(x,y),
    click(x,y,clicks,interval_ms), screenshot(name).
    """

    equip: list[dict[str, Any]] = field(default_factory=list)
    resupply: list[dict[str, Any]] = field(default_factory=list)
    sell: list[dict[str, Any]] = field(default_factory=list)
    resupply_every: int = 0           # 0 = désactivé (ex. 25 cycles)
    sell_every: int = 0               # 0 = désactivé


@dataclass
class Limits:
    max_cycles: int = 0               # 0 = infini
    max_consecutive_failures: int = 4
    equip_retries: int = 2


@dataclass
class DebugConfig:
    save_frames: bool = False
    save_every_state: bool = False
    screenshot_dir: str = "debug"
    log_dir: str = "logs"
    log_level: str = "INFO"


@dataclass
class Config:
    keys: Keys = field(default_factory=Keys)
    timing: Timing = field(default_factory=Timing)
    cast: CastConfig = field(default_factory=CastConfig)
    fight: FightConfig = field(default_factory=FightConfig)
    decision: DecisionConfig = field(default_factory=DecisionConfig)
    ui: UIConfig = field(default_factory=UIConfig)
    actions: Actions = field(default_factory=Actions)
    limits: Limits = field(default_factory=Limits)
    debug: DebugConfig = field(default_factory=DebugConfig)

    # ------------------------------------------------------------------ I/O
    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Config":
        return _from_dict(cls, _merge(asdict(cls()), data))

    @classmethod
    def load(cls, path: str | Path) -> "Config":
        p = Path(path)
        if not p.exists():
            return cls()
        return cls.from_dict(json.loads(p.read_text(encoding="utf-8")))

    def save(self, path: str | Path) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(self.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # --------------------------------------------------------------- helpers
    def scale(self, width: int, height: int) -> float:
        """Facteur d'échelle si la résolution a changé depuis la calibration."""
        ref = self.cast.reference_size
        if not ref or len(ref) != 2:
            return self.ui.scale
        rw, rh = float(ref[0]), float(ref[1])
        if rw <= 0 or rh <= 0:
            return self.ui.scale
        return self.ui.scale * min(width / rw, height / rh)

    def hold_ms_for(self, power: float) -> float:
        """Durée d'appui du clic gauche pour obtenir ``power`` (phase montante)."""
        power = max(0.0, min(1.0, power))
        return power * self.timing.charge_cycle_ms - self.timing.charge_latency_ms + self.cast.hold_offset_ms
