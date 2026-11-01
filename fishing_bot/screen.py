"""Capture d'écran rapide (mss) et utilitaires de debug.

mss renvoie du BGRA ; on convertit en BGR pour OpenCV. L'import est différé
afin que ``vision.py`` et les tests fonctionnent sans serveur d'affichage.
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from .config import Config


class ScreenCapture:
    def __init__(self, cfg: Config, monitor: Optional[int] = None):
        self.cfg = cfg
        self.monitor = cfg.ui.monitor if monitor is None else monitor
        self._sct: object | None = None

    def _ensure(self) -> object:
        if self._sct is None:
            try:
                import mss  # type: ignore
            except Exception as exc:  # pragma: no cover
                raise RuntimeError("mss est requis pour la capture d'écran (pip install mss)") from exc
            self._sct = mss.mss()
        return self._sct

    def grab(self) -> np.ndarray:
        sct = self._ensure()
        monitors = sct.monitors  # type: ignore[attr-defined]
        index = self.monitor if 0 <= self.monitor < len(monitors) else 1
        raw = sct.grab(monitors[index])  # type: ignore[attr-defined]
        bgra = np.asarray(raw, dtype=np.uint8)
        return cv2.cvtColor(bgra, cv2.COLOR_BGRA2BGR)

    @property
    def size(self) -> tuple[int, int]:
        frame = self.grab()
        return frame.shape[1], frame.shape[0]

    def save(self, path: str | Path) -> Path:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(p), self.grab())
        return p


def load_image(path: str | Path) -> np.ndarray:
    """Charge une capture PNG/JPG pour le diagnostic hors-jeu."""
    frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if frame is None:
        raise FileNotFoundError(f"image illisible: {path}")
    return frame


def save_image(path: str | Path, frame: np.ndarray) -> Path:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(p), frame)
    return p
