"""Constants extracted from the fiiiiish / qs-fisher resource.

Every value in this module is copied from the shipped Lua so the simulator
behaves like the real minigame.  The comments point at the exact file and
line the value comes from, which makes the port auditable.

Source of truth:
    client/fishing.lua   (FishingConfig, CHARGE_ANIM_DURATION, CAST_MAX_TIME)
    server/fishing.lua   (BuildFightParameters, DistanceForPower, tiers)
    config/config.lua    (Config.Cast, Config.BiteTime, Config.FightDifficulty)
"""

from __future__ import annotations

from dataclasses import dataclass

# ---------------------------------------------------------------------------
# client/fishing.lua -- local FishingConfig = { ... }
# ---------------------------------------------------------------------------
FISHING_CONFIG = {
    "min_bite_time": 1500,   # ms, server also enforces this floor
    "bite_window": 3000,     # ms the player has to strike after the bite
    "cast_distance": 10.0,   # fallback distance when Config.Cast is disabled
    "min_distance": 2.0,     # bobber can never be reeled closer than this
    "max_angle": 70.0,       # base degrees before difficulty/line bonuses
    "dead_zone": 8.0,        # |angle| below this counts as "center"
    "pull_speed": 0.025,     # metres per frame at 60 fps, scaled by angle
    "slip_speed": 0.005,     # metres per frame lost while on the wrong side
    "gain_rate": 0.01,       # tension per frame at full angle
    "update_rate": 50,       # ms between fishingStatus NUI messages
}

CHARGE_ANIM_DURATION = 1100.0   # ms for one sweep of the cast power meter
CAST_MAX_TIME = 6000.0          # ms the player may hold the cast key

# ---------------------------------------------------------------------------
# config/config.lua -- Config.Cast
# ---------------------------------------------------------------------------
CAST_MIN_DISTANCE = 6.0
CAST_MAX_DISTANCE = 26.0

# ---------------------------------------------------------------------------
# config/config.lua -- Config.BiteTime
# ---------------------------------------------------------------------------
BITE_TIME_MIN = 5.0             # seconds
BITE_TIME_MAX = 10.0            # seconds

# ---------------------------------------------------------------------------
# config/config.lua -- Config.CatchDecision
# ---------------------------------------------------------------------------
CATCH_DECISION_TIMEOUT = 9000   # ms before the server keeps the fish for you

# ---------------------------------------------------------------------------
# config/config.lua -- Config.FightDifficulty
# ---------------------------------------------------------------------------
FIGHT_DIFFICULTY_TIERS = {
    "shallow": 0.10,
    "mid": 0.35,
    "deep": 0.65,
    "abyss": 0.90,
}

# server/fishing.lua -- constants used by BuildFightParameters
DEFAULT_MAX_ANGLE = 70.0
BASE_PULL_SPEED = 0.025
BASE_SLIP_SPEED = 0.005
FIGHT_ANGLE_REDUCTION = 0.35
FIGHT_PULL_REDUCTION = 0.45
FIGHT_SLIP_MULTIPLIER = 2.2
FIGHT_TURN_MULTIPLIER = 0.5
FIGHT_SPECIMEN_QUALITY_SCALE = 0.15
MAX_FIGHT_EASE_PERCENT = 40.0


@dataclass(frozen=True)
class FightParams:
    """The four numbers the server hands to the client for one fight."""

    max_angle: float
    pull_speed: float
    slip_speed: float
    turn_rate: float


def build_fight_params(difficulty: float, line_strength_bonus: float = 0.0) -> FightParams:
    """Port of server/fishing.lua:BuildFightParameters.

    ``difficulty`` is 0..1 (tier + specimen quality, reduced by fight ease).
    ``line_strength_bonus`` is the gear/level bonus in percent.
    """
    difficulty = max(0.0, min(1.0, float(difficulty)))
    strength_multiplier = 1.0 + (float(line_strength_bonus) / 100.0)
    return FightParams(
        max_angle=(DEFAULT_MAX_ANGLE * strength_multiplier)
        * (1.0 - FIGHT_ANGLE_REDUCTION * difficulty),
        pull_speed=BASE_PULL_SPEED * (1.0 - FIGHT_PULL_REDUCTION * difficulty),
        slip_speed=BASE_SLIP_SPEED
        * (1.0 + ((FIGHT_SLIP_MULTIPLIER - 1.0) * difficulty)),
        turn_rate=1.0 + FIGHT_TURN_MULTIPLIER * difficulty,
    )


def fight_difficulty(tier: str, specimen_quality: float = 0.5,
                     fight_ease_percent: float = 0.0) -> float:
    """Port of the server's difficulty calculation.

    ``tier`` is one of the Config.Depth band ids.  ``specimen_quality`` is the
    0..1 roll of the individual fish.  ``fight_ease_percent`` is the combined
    gear + level bonus, capped at MAX_FIGHT_EASE_PERCENT.
    """
    tier_base = FIGHT_DIFFICULTY_TIERS.get(tier, 0.5)
    quality_added = max(0.0, min(1.0, float(specimen_quality))) * FIGHT_SPECIMEN_QUALITY_SCALE
    combined = max(0.0, min(tier_base + quality_added, 1.0))
    ease = max(0.0, min(float(fight_ease_percent), MAX_FIGHT_EASE_PERCENT))
    return combined * (1.0 - ease / 100.0)


def distance_for_power(power: float) -> float:
    """Port of server/fishing.lua:DistanceForPower."""
    power = max(0.0, min(1.0, float(power)))
    return CAST_MIN_DISTANCE + (CAST_MAX_DISTANCE - CAST_MIN_DISTANCE) * power


def cast_power_for_distance(distance: float) -> float:
    """Inverse of :func:`distance_for_power`."""
    span = CAST_MAX_DISTANCE - CAST_MIN_DISTANCE
    return max(0.0, min(1.0, (float(distance) - CAST_MIN_DISTANCE) / span))


def bite_wait_seconds(rng, bite_time_reduction_percent: float = 0.0) -> float:
    """Port of the server's waitTime calculation (before the 1.5 s floor)."""
    raw = rng.uniform(BITE_TIME_MIN, BITE_TIME_MAX)
    reduction = max(0.0, min(bite_time_reduction_percent / 100.0, 0.9))
    return max(raw * (1.0 - reduction), FISHING_CONFIG["min_bite_time"] / 1000.0)


# ---------------------------------------------------------------------------
# Bot defaults.  These are *not* game values; they are the automation tuning.
# ---------------------------------------------------------------------------
DEFAULT_SETPOINT = 70.0        # aim for 70 % of the line's angle budget (NUI easing lags the raw angle)
DEFAULT_DEADBAND = 3.0         # don't twitch inside +/-3 danger points
DEFAULT_MAX_STEP = 6.0         # fast cross step, degrees per 30 Hz tick (180 deg/s)
DEFAULT_HOLD_STEP = 2.5       # precise hold step, degrees per 30 Hz tick (75 deg/s)
DEFAULT_MIN_STEP = 0.4
DEFAULT_HOLD_GAIN = 0.08       # degrees per danger point of error
DEFAULT_TRIGGER_STEP = 2.0     # degrees/tick used to reveal the first side
DEFAULT_EMERGENCY = 92.0       # above this, steer back toward centre
DEFAULT_REACTION_DELAY = 0.05  # seconds of bot lag on side flips (NUI easing is modelled separately)
DEFAULT_CONTROL_HZ = 30.0
DEFAULT_FIGHT_HZ = 60.0
