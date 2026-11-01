"""Calibration interactive (à faire une fois par résolution / zoom NUI).

Sous-commandes :
  cast      : mesure la piste de puissance et en déduit ``ui.scale``
  decision  : vérifie/fige le rectangle de la modale Garder / Relâcher
  observe   : affiche l'état détecté en continu, sans rien envoyer au jeu
"""

from __future__ import annotations

import time
from pathlib import Path

import cv2
import numpy as np

from .config import Config
from .screen import ScreenCapture, load_image, save_image
from .vision import Vision


def _find_track_bbox(frame: np.ndarray, v: Vision) -> tuple[int, int, int, int] | None:
    """Repère la piste colorée (remplissage + aiguille) dans une frame de charge."""
    h, w = frame.shape[:2]
    tx1, ty1, tx2, ty2 = v.track_rect(w, h)
    s = max(0.5, v.cfg.ui.scale)
    x1 = max(0, int(tx1 - 16 * s))
    x2 = min(w, int(tx2 + 16 * s))
    y1 = max(0, int(0.28 * h))
    y2 = min(h, int(0.72 * h))
    if x2 <= x1 or y2 <= y1:
        return None
    roi = frame[y1:y2, x1:x2]
    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
    mask = ((hsv[:, :, 2] > 85) & (hsv[:, :, 1] > 32)).astype(np.uint8)
    rows = v._run_rows(mask, 0.45)
    if len(rows) < 10:
        return None
    top, bottom = int(rows[0]), int(rows[-1])
    band = mask[top : min(top + 5, mask.shape[0]), :]
    cols = np.where(band.any(axis=0))[0]
    if len(cols) < 8:
        return None
    return (x1 + int(cols.min()), y1 + top, x1 + int(cols.max()) + 1, y1 + bottom + 1)


def calibrate_cast(cfg: Config, path: str | Path, seconds: float = 4.0) -> bool:
    screen = ScreenCapture(cfg)
    v = Vision(cfg)
    print("=== Calibration du lancer ===")
    print("Dans FiveM : maintiens E, puis maintiens le clic gauche jusqu'au PIC de la")
    print("barre (~1,1 s), relâche le clic, puis relâche E. Je capture pendant "
          f"{seconds:.0f} s...")
    print("(Le script n'envoie AUCUNE entrée pendant la calibration.)\n")

    best_power = -1.0
    best_bbox: tuple[int, int, int, int] | None = None
    size = (0, 0)
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        frame = screen.grab()
        size = (frame.shape[1], frame.shape[0])
        st = v.analyze(frame)
        if st.cast_card and st.cast_power is not None:
            bbox = _find_track_bbox(frame, v)
            if bbox and st.cast_power > best_power:
                best_power, best_bbox = st.cast_power, bbox
        time.sleep(0.02)

    if best_bbox is None:
        print("KO : piste non détectée. Vérifie que la carte 'Cast power' est bien")
        print("     visible, que FiveM est au premier plan et lance `--observe`.")
        return False

    x1, y1, x2, y2 = best_bbox
    detected_scale = (y2 - y1) / 200.0
    detected_scale = max(0.5, min(2.5, detected_scale))
    cfg.cast.track = [x1, y1, x2, y2]
    cfg.cast.reference_size = [size[0], size[1]]
    cfg.ui.scale = detected_scale
    cfg.save(path)
    print(f"OK : piste = [{x1}, {y1}, {x2}, {y2}] sur {size[0]}x{size[1]}")
    print(f"     puissance max vue = {best_power:.2f}, ui.scale = {detected_scale:.3f}")
    print(f"     Configuration sauvegardée dans {path}")
    return True


def calibrate_decision(cfg: Config, path: str | Path, seconds: float = 9.0) -> bool:
    screen = ScreenCapture(cfg)
    v = Vision(cfg)
    print("=== Calibration de la modale ===")
    print("Attrape un poisson et laisse la modale Garder / Relâcher ouverte.")
    print(f"Je cherche la modale pendant {seconds:.0f} s (aucune entrée envoyée).\n")

    found = None
    size = (0, 0)
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        frame = screen.grab()
        size = (frame.shape[1], frame.shape[0])
        st = v.analyze(frame)
        if st.decision:
            found = (frame, st)
            break
        time.sleep(0.05)

    if found is None:
        frame = screen.grab()
        p = save_image(Path(cfg.debug.screenshot_dir) / "calibration_decision_ko.png", frame)
        print(f"KO : modale non détectée. Capture sauvegardée : {p}")
        print("     Ajuste ui.scale, ou renseigne decision.bbox manuellement.")
        return False

    frame, st = found
    rect = v.decision_rect(size[0], size[1])
    cfg.decision.bbox = list(rect)
    cfg.cast.reference_size = [size[0], size[1]]
    cfg.save(path)
    save_image(Path(cfg.debug.screenshot_dir) / "calibration_decision_ok.png", frame)
    print(f"OK : modale = {rect} sur {size[0]}x{size[1]}")
    print(f"     Garder={st.keep_button}  Relâcher={st.release_button}")
    print(f"     Configuration sauvegardée dans {path}")
    return True


def observe(cfg: Config, seconds: float = 12.0) -> None:
    screen = ScreenCapture(cfg)
    v = Vision(cfg)
    print(f"=== Observation {seconds:.0f} s (lecture seule) ===")
    end = time.monotonic() + seconds
    last = 0.0
    while time.monotonic() < end:
        now = time.monotonic()
        if now - last >= 0.20:
            last = now
            frame = screen.grab()
            st = v.analyze(frame)
            print(f"{time.strftime('%H:%M:%S')}  {st.summary()}")
        time.sleep(0.02)
    print("Fin de l'observation.")


def calibrate_from_image(image: str | Path, cfg: Config, path: str | Path) -> None:
    """Calibre la piste depuis une capture PNG déjà prise en pleine charge."""
    frame = load_image(image)
    h, w = frame.shape[:2]
    v = Vision(cfg)
    st = v.analyze(frame)
    bbox = _find_track_bbox(frame, v)
    print(f"Image {w}x{h} : {st.summary()}")
    if bbox is None:
        print("KO : piste introuvable sur cette image.")
        return
    x1, y1, x2, y2 = bbox
    cfg.cast.track = [x1, y1, x2, y2]
    cfg.cast.reference_size = [w, h]
    cfg.ui.scale = max(0.5, min(2.5, (y2 - y1) / 200.0))
    cfg.save(path)
    print(f"OK : piste={bbox} ui.scale={cfg.ui.scale:.3f} -> {path}")
