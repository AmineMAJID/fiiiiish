"""Lecture de l'état du jeu **uniquement par capture d'écran**.

Aucune lecture mémoire, aucun hook NUI, aucun événement réseau. Les détecteurs
sont calibrés sur les couleurs et la géométrie réelles de la NUI du dépôt :
``web/build/assets/index.js`` et ``web/build/assets/index.css``.

Toutes les zones sont exprimées en fractions de l'écran, puis converties en
pixels ; ``Config.ui.scale`` (ou la calibration) compense le zoom NUI.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np

from .config import Config

# ---------------------------------------------------------------------------
# Plages de couleurs (HSV OpenCV : H 0..179, S 0..255, V 0..255)
# Valeurs relevées sur les couleurs exactes du CSS :
#   #38bdf8 -> (99,197,248)   #7dd3fc -> (100,129,252)  #5cbaf0 -> (103,157,240)
#   #2563eb -> (111,215,235)  #60a5fa -> (107,157,250)
#   #4ade80 -> (71,170,222)   #f59e0b -> (19,244,245)   #ef4444 -> (0,182,239)
# ---------------------------------------------------------------------------
CYAN = ((90, 75, 140), (113, 255, 255))
CYAN_BRIGHT = ((90, 75, 175), (113, 255, 255))
BLUE = ((103, 85, 110), (123, 255, 255))
GREEN = ((58, 85, 105), (92, 255, 255))
WARM_A = ((0, 105, 135), (27, 255, 255))
WARM_B = ((170, 105, 135), (179, 255, 255))
# Marine sombre de la NUI, en BGR : #0f172b=(43,23,15) -> #1d293d=(61,41,29)
NAVY_LOW = (8, 8, 5)
NAVY_HIGH = (82, 68, 100)


@dataclass
class ScreenState:
    """Instantané de ce que le joueur voit."""

    w: int
    h: int
    ready: bool = False                 # jauge de profondeur + touche E verte
    cast_card: bool = False             # carte "Cast power" visible
    cast_power: Optional[float] = None  # 0..1 lu sur la barre (si calibrée)
    cast_fill_top: Optional[int] = None
    bite: bool = False
    bite_ring: int = 0
    bite_prompt: int = 0
    fight: bool = False
    cue_side: Optional[str] = None      # "left" / "right" / None
    cue_score: int = 0
    progress_edge: Optional[int] = None  # x du bord droit de la barre bleue
    progress_pixels: int = 0
    danger_high: bool = False
    decision: bool = False
    keep_button: Optional[tuple[int, int]] = None
    release_button: Optional[tuple[int, int]] = None
    dark_ratio: float = 0.0

    def summary(self) -> str:
        return (
            f"ready={int(self.ready)} cast={int(self.cast_card)}"
            f"/{self.cast_power if self.cast_power is not None else '-':>4} "
            f"bite={int(self.bite)}({self.bite_ring}/{self.bite_prompt}) "
            f"fight={int(self.fight)} cue={self.cue_side or '-'} "
            f"edge={self.progress_edge} danger={int(self.danger_high)} "
            f"decision={int(self.decision)}"
        )


class Vision:
    """Détecteurs d'état. Les méthodes sont pures (aucun effet de bord)."""

    def __init__(self, cfg: Config):
        self.cfg = cfg

    # ------------------------------------------------------------------ utils
    @staticmethod
    def _rect(w: int, h: int, fx1: float, fy1: float, fx2: float, fy2: float) -> tuple[int, int, int, int]:
        x1, y1 = max(0, int(fx1 * w)), max(0, int(fy1 * h))
        x2, y2 = min(w, int(fx2 * w)), min(h, int(fy2 * h))
        if x2 <= x1:
            x2 = min(w, x1 + 1)
        if y2 <= y1:
            y2 = min(h, y1 + 1)
        return x1, y1, x2, y2

    @staticmethod
    def _hsv(frame: np.ndarray) -> np.ndarray:
        return cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

    @staticmethod
    def _hsv_mask(hsv: np.ndarray, low: tuple[int, int, int], high: tuple[int, int, int]) -> np.ndarray:
        return cv2.inRange(hsv, np.array(low, np.uint8), np.array(high, np.uint8)) > 0

    @staticmethod
    def _navy(frame: np.ndarray) -> np.ndarray:
        return cv2.inRange(frame, np.array(NAVY_LOW, np.uint8), np.array(NAVY_HIGH, np.uint8)) > 0

    @staticmethod
    def _run_rows(mask: np.ndarray, min_fraction: float = 0.5) -> np.ndarray:
        """Lignes contenant une raie horizontale continue de pixels actifs."""
        height, width = mask.shape[:2]
        k = max(3, min(width - 1, int(width * min_fraction)))
        kernel = np.ones((1, k), np.uint8)
        opened = cv2.morphologyEx(mask.astype(np.uint8), cv2.MORPH_OPEN, kernel)
        return np.where(opened.any(axis=1))[0]

    def track_rect(self, w: int, h: int) -> tuple[int, int, int, int]:
        """Rectangle de la barre de puissance de lancer, en pixels absolus.

        Géométrie CSS : carte à left:60%, top:50%, padding 13px, ticks 20px,
        gap 8px, piste 28px de large et 200px de haut (12.5rem).
        """
        override = self.cfg.cast.track
        ref = self.cfg.cast.reference_size
        s = self.cfg.ui.scale
        if override and len(override) == 4:
            x1, y1, x2, y2 = [float(v) for v in override]
            if ref and len(ref) == 2 and ref[0] > 0 and ref[1] > 0:
                x1 *= w / ref[0]
                x2 *= w / ref[0]
                y1 *= h / ref[1]
                y2 *= h / ref[1]
        else:
            x1 = 0.60 * w + 41.0 * s
            y1 = 0.50 * h - 117.0 * s
            x2 = x1 + 28.0 * s
            y2 = y1 + 200.0 * s
        return (
            max(0, min(w - 1, int(x1))),
            max(0, min(h - 1, int(y1))),
            max(1, min(w, int(x2))),
            max(1, min(h, int(y2))),
        )

    def decision_rect(self, w: int, h: int) -> tuple[int, int, int, int]:
        """Rectangle de la modale Garder / Relâcher (ancrée à droite)."""
        ref = self.cfg.cast.reference_size
        override = self.cfg.decision.bbox
        s = self.cfg.ui.scale
        if override and len(override) == 4:
            x1, y1, x2, y2 = [float(v) for v in override]
            if ref and len(ref) == 2 and ref[0] > 0 and ref[1] > 0:
                x1 *= w / ref[0]
                x2 *= w / ref[0]
                y1 *= h / ref[1]
                y2 *= h / ref[1]
        else:
            mw = self.cfg.decision.modal_width_px * s
            mh = self.cfg.decision.modal_height_px * s
            x2 = w - self.cfg.decision.right_margin_ratio * w
            x1 = x2 - mw
            y1 = h / 2.0 - mh / 2.0
            y2 = y1 + mh
        return (
            max(0, min(w - 1, int(x1))),
            max(0, min(h - 1, int(y1))),
            max(1, min(w, int(x2))),
            max(1, min(h, int(y2))),
        )

    # -------------------------------------------------------------- détecteurs
    def analyze(self, frame: np.ndarray) -> ScreenState:
        h, w = frame.shape[:2]
        s = self.cfg.ui.scale
        st = ScreenState(w=w, h=h)
        hsv = self._hsv(frame)
        cyan = self._hsv_mask(hsv, *CYAN)
        cyan_bright = self._hsv_mask(hsv, *CYAN_BRIGHT)
        blue = self._hsv_mask(hsv, *BLUE)
        green = self._hsv_mask(hsv, *GREEN)
        warm = self._hsv_mask(hsv, *WARM_A) | self._hsv_mask(hsv, *WARM_B)
        navy = self._navy(frame)

        # ---- Jauge de profondeur / prêt à lancer -------------------------
        dx1, dy1, dx2, dy2 = self._rect(w, h, 0.80, 0.42, 0.995, 0.68)
        d_roi = frame[dy1:dy2, dx1:dx2]
        d_green = int(green[dy1:dy2, dx1:dx2].sum())
        d_dark = float(navy[dy1:dy2, dx1:dx2].mean())
        st.dark_ratio = d_dark

        # ---- Carte de puissance de lancer --------------------------------
        cx1, cy1, cx2, cy2 = self._rect(w, h, 0.55, 0.30, 0.71, 0.70)
        c_cyan = int(cyan[cy1:cy2, cx1:cx2].sum())
        c_blue = int(blue[cy1:cy2, cx1:cx2].sum())
        c_dark = float(navy[cy1:cy2, cx1:cx2].mean())
        st.cast_card = (c_cyan + c_blue >= int(110 * s * s)) and c_dark > 0.07

        tx1, ty1, tx2, ty2 = self.track_rect(w, h)
        track = frame[ty1:ty2, tx1:tx2]
        if track.size and st.cast_card:
            t_hsv = hsv[ty1:ty2, tx1:tx2]
            # Remplissage coloré : gris/bleu/vert/cyan, jamais le fond quasi noir.
            fill = ((t_hsv[:, :, 2] > 85) & (t_hsv[:, :, 1] > 32)).astype(np.uint8)
            rows = self._run_rows(fill, 0.5)
            if len(rows):
                top = int(rows[0])
                st.cast_fill_top = ty1 + top
                st.cast_power = max(0.0, min(1.0, (ty2 - st.cast_fill_top) / max(1, ty2 - ty1)))
            else:
                st.cast_power = 0.0
        # Hors carte, une puissance de 0.0 serait trompeuse dans les logs.

        # ---- Bouchon / fenêtre de ferrage ---------------------------------
        float_cx = w // 2
        float_cy = int(h - 0.025 * h - 124.0 * s)
        r_in, r_out = 48.0 * s, 72.0 * s
        bx1 = max(0, int(float_cx - r_out - 6))
        bx2 = min(w, int(float_cx + r_out + 6))
        by1 = max(0, int(float_cy - r_out - 6))
        by2 = min(h, int(float_cy + r_out + 6))
        if bx2 > bx1 and by2 > by1:
            yy, xx = np.ogrid[by1:by2, bx1:bx2]
            dist = np.sqrt((xx - float_cx) ** 2 + (yy - float_cy) ** 2)
            annulus = (dist >= r_in) & (dist <= r_out)
            ring_cyan = cyan[by1:by2, bx1:bx2] & annulus
            ring_red = warm[by1:by2, bx1:bx2] & annulus
            st.bite_ring = int(ring_cyan.sum() + ring_red.sum())
        px1 = max(0, int(float_cx - 135 * s))
        px2 = min(w, int(float_cx + 135 * s))
        py1 = max(0, int(float_cy + 68 * s))
        py2 = min(h, int(float_cy + 138 * s))
        if px2 > px1 and py2 > py1:
            st.bite_prompt = int(cyan[py1:py2, px1:px2].sum())
        st.bite = (
            st.bite_ring >= int(230 * s * s) or st.bite_prompt >= int(55 * s * s)
        )

        # ---- Combat -------------------------------------------------------
        fx1, fy1, fx2, fy2 = self._rect(w, h, 0.30, 0.815, 0.70, 0.940)
        f_dark = float(navy[fy1:fy2, fx1:fx2].mean())
        f_blue = int(blue[fy1:fy2, fx1:fx2].sum())
        f_cyan = int(cyan[fy1:fy2, fx1:fx2].sum())
        st.fight = f_dark > 0.18 and (f_blue + f_cyan) >= int(70 * s * s)

        # Flèches actives : #7dd3fc + halo, inactives : #1e293b (V=59).
        qx1, qy1, qx2, qy2 = self._rect(w, h, 0.30, 0.725, 0.70, 0.845)
        q = cyan_bright[qy1:qy2, qx1:qx2]
        mid = (qx1 + qx2) // 2
        left = int(q[:, : max(1, mid - qx1)].sum())
        right = int(q[:, max(1, mid - qx1) :].sum())
        st.cue_score = left + right
        if st.cue_score >= int(35 * s * s):
            if left > right * 1.30:
                st.cue_side = "left"
            elif right > left * 1.30:
                st.cue_side = "right"

        # Barre de progression : raie bleue horizontale la plus à droite.
        gx1, gy1, gx2, gy2 = self._rect(w, h, 0.34, 0.850, 0.66, 0.884)
        bmask = blue[gy1:gy2, gx1:gx2]
        row_counts = bmask.sum(axis=1)
        # Seuil volontairement bas : les premiers pourcents de progression
        # doivent déjà être visibles pour que l'asservissement ne « cale » pas.
        good_rows = np.where(row_counts >= max(10, int(0.025 * (gx2 - gx1))))[0]
        if len(good_rows):
            sub = bmask[good_rows.min() : good_rows.max() + 1]
            cols = np.where(sub.any(axis=0))[0]
            if len(cols):
                st.progress_edge = gx1 + int(cols.max())
                st.progress_pixels = int(sub.sum())

        # Tension : texte/icône orange-rouge + dégradé rouge en fin de barre.
        wx1, wy1, wx2, wy2 = self._rect(w, h, 0.34, 0.875, 0.66, 0.922)
        st.danger_high = int(warm[wy1:wy2, wx1:wx2].sum()) >= int(18 * s * s)

        # ---- Modale Garder / Relâcher -------------------------------------
        mx1, my1, mx2, my2 = self.decision_rect(w, h)
        mw, mh = max(1, mx2 - mx1), max(1, my2 - my1)
        keep = (int(mx1 + self.cfg.decision.keep_rel[0] * mw),
                int(my1 + self.cfg.decision.keep_rel[1] * mh))
        release = (int(mx1 + self.cfg.decision.release_rel[0] * mw),
                   int(my1 + self.cfg.decision.release_rel[1] * mh))
        st.keep_button, st.release_button = keep, release
        if mx2 > mx1 and my2 > my1:
            m_dark = float(navy[my1:my2, mx1:mx2].mean())
            top_band = slice(my1, min(my2, my1 + max(3, int(7 * s))))
            top_blue = int((blue[top_band, mx1:mx2] | cyan[top_band, mx1:mx2]).sum())

            def _icon_score(center: tuple[int, int], mask: np.ndarray) -> int:
                ix1 = max(0, int(center[0] - 0.13 * mw))
                ix2 = min(w, int(center[0] + 0.13 * mw))
                iy1 = max(0, int(center[1] - 0.11 * mh))
                iy2 = min(h, int(center[1] + 0.07 * mh))
                if ix2 <= ix1 or iy2 <= iy1:
                    return 0
                return int(mask[iy1:iy2, ix1:ix2].sum())

            cyan_icon = _icon_score(keep, cyan)
            green_icon = _icon_score(release, green)
            st.decision = (
                m_dark > 0.36
                and top_blue >= int(12 * s)
                and cyan_icon >= int(12 * s * s)
                and green_icon >= int(12 * s * s)
            )

        # La touche E verte de la jauge de profondeur n'est visible que prêt.
        st.ready = (d_green >= int(28 * s * s)) and d_dark > 0.06 and not st.decision
        return st


def power_from_hold(hold_ms: float, cycle_ms: float = 1100.0) -> float:
    """Modèle exact de ``ChargeCastPower`` : triangle 0 -> 1 -> 0 sur 2*cycle."""
    t = max(0.0, hold_ms)
    cycle = (t % (2.0 * cycle_ms)) / cycle_ms
    return cycle if cycle <= 1.0 else 2.0 - cycle


def opposite(side: str) -> str:
    return "right" if side == "left" else "left"
