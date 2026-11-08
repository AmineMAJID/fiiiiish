"""Small JSON settings file, so the tool learns once instead of every session.

The one number worth remembering is ``counts_per_pct``: how many mouse counts
buy one percent of the line-tension bar.  It is a property of the player's DPI
and in-game sensitivity, so it never changes on a given machine, and re-learning
it means making the blind first swing of a session all over again.  Everything
else here is just a convenience default for the command line.

The file is deliberately boring: one flat JSON object, written atomically, in
``%USERPROFILE%\\.fishbot\\settings.json`` (override with ``FISHBOT_HOME``).  If it
is missing, unreadable or nonsense, the defaults are used and the tool carries
on - a settings file must never be the reason fishing does not start.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict

SETTINGS_ENV = "FISHBOT_HOME"
SETTINGS_NAME = "settings.json"

DEFAULTS: Dict[str, Any] = {
    "counts_per_pct": 1.6,
    "scale": 0.5,
    "capture": "printwindow",
    "hz": 20.0,
    "keep": True,
    "window_title": "",
    "fish_kept": 0,
    "sessions": 0,
}

#: Values outside these ranges are treated as corruption rather than settings.
_LIMITS = {
    "counts_per_pct": (0.05, 400.0),
    "scale": (0.2, 1.0),
    "hz": (2.0, 60.0),
}


def settings_path(path: "str | os.PathLike | None" = None) -> Path:
    if path is not None:
        return Path(path)
    home = os.environ.get(SETTINGS_ENV)
    base = Path(home) if home else (Path.home() / ".fishbot")
    return base / SETTINGS_NAME


def load(path: "str | os.PathLike | None" = None) -> Dict[str, Any]:
    """Everything in :data:`DEFAULTS`, with whatever the file validly overrides."""
    data = dict(DEFAULTS)
    target = settings_path(path)
    try:
        with open(target, "r", encoding="utf-8") as fh:
            stored = json.load(fh)
    except (OSError, ValueError):
        return data
    if not isinstance(stored, dict):
        return data
    for key, default in DEFAULTS.items():
        if key not in stored:
            continue
        value = stored[key]
        if isinstance(default, bool):
            if isinstance(value, bool):
                data[key] = value
        elif isinstance(default, float):
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                value = float(value)
                lo, hi = _LIMITS.get(key, (float("-inf"), float("inf")))
                if lo <= value <= hi:
                    data[key] = value
        elif isinstance(default, int):
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
                data[key] = value
        elif isinstance(default, str):
            if isinstance(value, str):
                data[key] = value
    return data


def save(data: Dict[str, Any], path: "str | os.PathLike | None" = None) -> bool:
    """Write the settings atomically.  Returns False if it could not be saved."""
    target = settings_path(path)
    merged = dict(DEFAULTS)
    merged.update({k: v for k, v in data.items() if k in DEFAULTS})
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, target)
        return True
    except OSError:
        return False
