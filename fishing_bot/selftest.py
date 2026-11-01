"""Auto-diagnostic hors-jeu : génère des images synthétiques conformes à la NUI
et vérifie chaque détecteur. Sert aussi de régression pour la calibration.

Utilisation : ``python -m fishing_bot --selftest`` ou ``pytest tests/``.
"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from .config import Config
from .controller import FightController
from .vision import ScreenState, Vision, power_from_hold

# Couleurs BGR exactes du CSS.
B_GREY = (139, 116, 100)     # #64748b
B_CYAN = (248, 189, 56)      # #38bdf8
B_CYAN_LIGHT = (252, 211, 125)  # #7dd3fc
B_BLUE = (235, 99, 37)       # #2563eb
B_BLUE_LIGHT = (250, 165, 96)   # #60a5fa
B_GREEN = (128, 222, 74)     # #4ade80
B_ORANGE = (11, 158, 245)    # #f59e0b
B_RED = (68, 68, 239)        # #ef4444
B_NAVY = (43, 23, 15)        # #0f172b
B_NAVY2 = (61, 41, 29)       # #1d293d
B_TRACK = (18, 8, 2)         # #020812
B_BG = (100, 95, 90)         # fond clair, hors de la plage "navy"


def blank(w: int = 1920, h: int = 1080) -> np.ndarray:
    frame = np.zeros((h, w, 3), np.uint8)
    frame[:] = B_BG
    return frame


def _rect_px(v: Vision, w: int, h: int, fx1: float, fy1: float, fx2: float, fy2: float) -> tuple[int, int, int, int]:
    return v._rect(w, h, fx1, fy1, fx2, fy2)


def draw_cast(frame: np.ndarray, v: Vision, power: float) -> tuple[int, int, int, int]:
    h, w = frame.shape[:2]
    x1, y1, x2, y2 = v.track_rect(w, h)
    # Carte sombre + entête bleu pour le détecteur de présence.
    card = _rect_px(v, w, h, 0.575, 0.36, 0.665, 0.64)
    cv2.rectangle(frame, (card[0], card[1]), (card[2], card[3]), B_NAVY, -1)
    cv2.rectangle(frame, (card[0] + 10, card[1] + 12), (card[2] - 10, card[1] + 24), B_CYAN, -1)
    # Piste + remplissage + aiguille.
    cv2.rectangle(frame, (x1, y1), (x2, y2), B_TRACK, -1)
    color = B_GREY if power < 0.35 else (B_CYAN if power < 0.70 else B_GREEN)
    fill_top = int(y2 - power * (y2 - y1))
    cv2.rectangle(frame, (x1, fill_top), (x2, y2), color, -1)
    cv2.rectangle(frame, (max(0, x1 - 3), max(0, fill_top - 1)), (x2 + 3, fill_top + 2), color, -1)
    return x1, y1, x2, y2


def draw_bite(frame: np.ndarray, v: Vision, active: bool = True) -> None:
    h, w = frame.shape[:2]
    s = v.cfg.ui.scale
    cx, cy = w // 2, int(h - 0.025 * h - 124 * s)
    if active:
        cv2.circle(frame, (cx, cy), int(60 * s), B_CYAN, max(2, int(5 * s)))
        # Encadré "E" sous le bouchon.
        px1, px2 = int(cx - 90 * s), int(cx + 90 * s)
        py1, py2 = int(cy + 78 * s), int(cy + 122 * s)
        cv2.rectangle(frame, (px1, py1), (px2, py2), B_NAVY, -1)
        cv2.rectangle(frame, (px1, py1), (px1 + int(30 * s), py2), B_CYAN_LIGHT, -1)
    else:
        # État "waiting" : simples ondulations faibles, sous le seuil.
        cv2.circle(frame, (cx, cy), int(46 * s), (120, 110, 70), 2)


def draw_fight(
    frame: np.ndarray,
    v: Vision,
    cue: str | None,
    progress: float = 0.0,
    danger_high: bool = False,
) -> int | None:
    h, w = frame.shape[:2]
    s = v.cfg.ui.scale
    panel = _rect_px(v, w, h, 0.305, 0.815, 0.695, 0.938)
    cv2.rectangle(frame, (panel[0], panel[1]), (panel[2], panel[3]), B_NAVY2, -1)

    # Chevrons actifs (3 rectangles lumineux) du côté demandé.
    if cue:
        qx1, qy1, qx2, qy2 = _rect_px(v, w, h, 0.30, 0.725, 0.70, 0.845)
        mid = (qx1 + qx2) // 2
        base = qx1 + int(0.06 * (qx2 - qx1)) if cue == "left" else mid + int(0.06 * (qx2 - qx1))
        for i in range(3):
            x = base + i * int(16 * s)
            cv2.rectangle(frame, (x, qy1 + int(8 * s)), (x + int(10 * s), qy1 + int(34 * s)), B_CYAN_LIGHT, -1)

    # Barre de progression bleue.
    gx1, gy1, gx2, gy2 = _rect_px(v, w, h, 0.34, 0.850, 0.66, 0.884)
    track_y1, track_y2 = gy1 + int(10 * s), gy1 + int(18 * s)
    cv2.rectangle(frame, (gx1, track_y1), (gx2, track_y2), B_TRACK, -1)
    edge = None
    if progress > 0:
        edge = int(gx1 + progress * (gx2 - gx1))
        cv2.rectangle(frame, (gx1, track_y1), (edge, track_y2), B_BLUE_LIGHT, -1)
        # Dégradé approximatif.
        cv2.rectangle(frame, (gx1, track_y1), (min(edge, gx1 + int(0.3 * (gx2 - gx1))), track_y2), B_BLUE, -1)

    # Barre de tension + texte orange/rouge si danger.
    wx1, wy1, wx2, wy2 = _rect_px(v, w, h, 0.34, 0.875, 0.66, 0.922)
    cv2.rectangle(frame, (wx1, wy1 + int(18 * s)), (wx2, wy1 + int(26 * s)), B_TRACK, -1)
    cv2.rectangle(frame, (wx1, wy1 + int(18 * s)), (wx1 + int(0.5 * (wx2 - wx1)), wy1 + int(26 * s)), B_GREEN, -1)
    if danger_high:
        cv2.rectangle(frame, (wx1 + int(0.55 * (wx2 - wx1)), wy1 + int(2 * s)),
                      (wx1 + int(0.72 * (wx2 - wx1)), wy1 + int(14 * s)), B_RED, -1)
        cv2.rectangle(frame, (wx1 + int(0.72 * (wx2 - wx1)), wy1 + int(18 * s)),
                      (wx2, wy1 + int(26 * s)), B_ORANGE, -1)
    return edge


def draw_decision(frame: np.ndarray, v: Vision) -> tuple[tuple[int, int], tuple[int, int]]:
    h, w = frame.shape[:2]
    x1, y1, x2, y2 = v.decision_rect(w, h)
    mw, mh = x2 - x1, y2 - y1
    cv2.rectangle(frame, (x1, y1), (x2, y2), B_NAVY, -1)
    cv2.rectangle(frame, (x1, y1), (x2, y1 + max(2, int(3 * v.cfg.ui.scale))), B_BLUE, -1)
    keep = (int(x1 + v.cfg.decision.keep_rel[0] * mw), int(y1 + v.cfg.decision.keep_rel[1] * mh))
    release = (int(x1 + v.cfg.decision.release_rel[0] * mw), int(y1 + v.cfg.decision.release_rel[1] * mh))
    # Icônes cyan (Garder) et verte (Relâcher), au-dessus du centre des boutons.
    cv2.circle(frame, (keep[0], keep[1] - int(0.035 * mh)), int(0.018 * mw), B_CYAN, -1)
    cv2.circle(frame, (release[0], release[1] - int(0.035 * mh)), int(0.018 * mw), B_GREEN, -1)
    return keep, release


def draw_ready(frame: np.ndarray, v: Vision) -> None:
    h, w = frame.shape[:2]
    dx1, dy1, dx2, dy2 = _rect_px(v, w, h, 0.80, 0.42, 0.995, 0.68)
    cv2.rectangle(frame, (dx1, dy1), (dx2, dy1 + int(0.09 * h)), B_NAVY2, -1)
    cv2.rectangle(frame, (dx1 + 10, dy1 + 12), (dx1 + 34, dy1 + 36), B_GREEN, -1)


def run_selftest(verbose: bool = True) -> bool:
    cfg = Config()
    v = Vision(cfg)
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))

    # 1. Modèle de charge -------------------------------------------------
    check("power(550ms)=0.50", abs(power_from_hold(550) - 0.5) < 1e-9)
    check("power(1100ms)=1.00", abs(power_from_hold(1100) - 1.0) < 1e-9)
    check("power(1650ms)=0.50", abs(power_from_hold(1650) - 0.5) < 1e-9)
    check("power(2200ms)=0.00", abs(power_from_hold(2200) - 0.0) < 1e-9)
    check("hold_ms(0.86)=936", abs(cfg.hold_ms_for(0.86) - 936.0) < 1e-6)

    # 2. Puissance de lancer lue à l'écran --------------------------------
    for p in (0.20, 0.55, 0.86):
        f = blank()
        draw_cast(f, v, p)
        st = v.analyze(f)
        check(f"cast_power({p:.2f})", st.cast_power is not None and abs(st.cast_power - p) < 0.035,
              f"lu={st.cast_power}")
        check(f"cast_card({p:.2f})", st.cast_card)
    plain = v.analyze(blank())
    check("pas de carte sur fond neutre", not plain.cast_card)

    # 3. Ferrage ----------------------------------------------------------
    f = blank()
    draw_bite(f, v, active=True)
    st = v.analyze(f)
    check("bite détectée", st.bite, f"ring={st.bite_ring} prompt={st.bite_prompt}")
    f = blank()
    draw_bite(f, v, active=False)
    st = v.analyze(f)
    check("attente non confondue avec bite", not st.bite, f"ring={st.bite_ring}")

    # 4. Combat -----------------------------------------------------------
    for cue in ("left", "right"):
        f = blank()
        edge = draw_fight(f, v, cue=cue, progress=0.6, danger_high=False)
        st = v.analyze(f)
        check(f"fight visible ({cue})", st.fight)
        check(f"cue={cue}", st.cue_side == cue, f"lu={st.cue_side} score={st.cue_score}")
        check(f"progress_edge ({cue})", st.progress_edge is not None and edge is not None
              and abs(st.progress_edge - edge) < 12, f"lu={st.progress_edge} attendu={edge}")
        check(f"danger bas ({cue})", not st.danger_high)
    f = blank()
    draw_fight(f, v, cue="left", progress=0.8, danger_high=True)
    st = v.analyze(f)
    check("danger élevé détecté", st.danger_high)

    # 5. Modale de décision ----------------------------------------------
    f = blank()
    keep, release = draw_decision(f, v)
    st = v.analyze(f)
    check("modale détectée", st.decision)
    check("bouton Garder", st.keep_button is not None and
          abs(st.keep_button[0] - keep[0]) < 8 and abs(st.keep_button[1] - keep[1]) < 8,
          f"lu={st.keep_button} attendu={keep}")
    check("bouton Relâcher", st.release_button is not None and
          abs(st.release_button[0] - release[0]) < 8, f"lu={st.release_button}")

    # 6. Jauge de profondeur ---------------------------------------------
    f = blank()
    draw_ready(f, v)
    st = v.analyze(f)
    check("prêt à lancer détecté", st.ready and not st.decision)

    # 7. Contrôleur de combat --------------------------------------------
    fc = FightController(cfg.fight)
    fc.reset()
    t = 0.0
    base = ScreenState(w=1920, h=1080, fight=True)
    s0 = ScreenState(w=1920, h=1080, fight=True, progress_edge=None)
    step0 = fc.step(s0, t)
    check("1er tick vers la droite", step0.direction == 1)
    t += 0.05
    s1 = ScreenState(w=1920, h=1080, fight=True, cue_side="left", progress_edge=None)
    step1 = fc.step(s1, t)
    check("1er chevron => inversion immédiate", step1.direction == -1,
          f"dir={step1.direction} reason={step1.reason}")
    check("mapping left=-1", fc.mapping.get("left") == -1, str(fc.mapping))
    t += 0.05
    s2 = ScreenState(w=1920, h=1080, fight=True, cue_side="left", progress_edge=700)
    fc.step(s2, t)
    t += 0.05
    s3 = ScreenState(w=1920, h=1080, fight=True, cue_side="left", progress_edge=720)
    fc.step(s3, t)
    t += 0.05
    s4 = ScreenState(w=1920, h=1080, fight=True, cue_side="right", progress_edge=720)
    step4 = fc.step(s4, t)
    check("changement de côté => sens opposé", step4.direction == 1,
          f"dir={step4.direction} mapping={fc.mapping}")

    ok = all(condition for _, condition, _ in checks)
    if verbose:
        for name, condition, detail in checks:
            print(f"{'OK ' if condition else 'KO '} {name}" + (f"  [{detail}]" if detail and not condition else ""))
        print(f"\n{sum(c for _, c, _ in checks)}/{len(checks)} vérifications réussies")
    return ok


def diagnose(image_path: str | Path, cfg: Config | None = None) -> ScreenState:
    """Analyse une capture réelle et affiche l'état détecté."""
    from .screen import load_image

    cfg = cfg or Config()
    frame = load_image(image_path)
    st = Vision(cfg).analyze(frame)
    print(f"Image: {image_path} ({st.w}x{st.h})")
    print(st.summary())
    print(f"track={Vision(cfg).track_rect(st.w, st.h)} decision={Vision(cfg).decision_rect(st.w, st.h)}")
    return st


if __name__ == "__main__":  # pragma: no cover
    import sys

    if len(sys.argv) > 1:
        diagnose(sys.argv[1])
    else:
        raise SystemExit(0 if run_selftest() else 1)
