"""Envoi d'entrées clavier/souris au niveau OS (SendInput via pydirectinput).

Aucune injection dans le processus FiveM, aucun appel d'export Lua, aucun
événement réseau : le bot appuie sur les mêmes touches que le joueur.

pydirectinput est Windows uniquement (FiveM l'est aussi). L'import est différé
pour que la vision et les tests restent exécutables sur Linux/macOS.
"""

from __future__ import annotations

import ctypes
import sys
import time
from typing import Any, Iterable

from .config import Config

_IS_WINDOWS = sys.platform == "win32"

# Codes de touches virtuelles pour le coupe-circuit polling.
_VK = {
    "f12": 0x7B,
    "f11": 0x7A,
    "f10": 0x79,
    "esc": 0x1B,
    "pause": 0x13,
}


class InputController:
    """Wrapper fin, avec suivi des touches enfoncées et coupe-circuit."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._pdi: Any = None
        self._held: set[str] = set()
        self._mouse_held = False

    # ------------------------------------------------------------- pydirectinput
    @property
    def pdi(self) -> Any:
        if self._pdi is None:
            try:
                import pydirectinput  # type: ignore
            except Exception as exc:  # pragma: no cover - dépend de l'OS
                raise RuntimeError(
                    "pydirectinput est requis et ne fonctionne que sous Windows "
                    "(FiveM tourne sous Windows). Installez-le avec pip."
                ) from exc
            pydirectinput.PAUSE = 0
            # Le failsafe pyautogui (coin 0,0) n'a pas de sens ici : GTA verrouille
            # déjà le curseur, et notre propre F12 sert de coupe-circuit.
            if hasattr(pydirectinput, "FAILSAFE"):
                pydirectinput.FAILSAFE = False
            self._pdi = pydirectinput
        return self._pdi

    # ------------------------------------------------------------------ clavier
    def key_down(self, key: str) -> None:
        self.pdi.keyDown(key)
        self._held.add(key)

    def key_up(self, key: str) -> None:
        if key in self._held:
            self.pdi.keyUp(key)
            self._held.discard(key)

    def press(self, key: str, duration_ms: int | None = None) -> None:
        ms = self.cfg.timing.key_press_ms if duration_ms is None else duration_ms
        self.key_down(key)
        time.sleep(max(0.005, ms / 1000.0))
        self.key_up(key)

    # ------------------------------------------------------------------- souris
    def mouse_down(self, button: str = "left") -> None:
        self.pdi.mouseDown(button=button)
        self._mouse_held = True

    def mouse_up(self, button: str = "left") -> None:
        if self._mouse_held:
            self.pdi.mouseUp(button=button)
            self._mouse_held = False

    def move_rel(self, dx: int, dy: int = 0) -> None:
        if dx == 0 and dy == 0:
            return
        # ``relative=True`` envoie un vrai MOUSEEVENTF_MOVE (SendInput), celui
        # que GTA V consomme en raw input. Sans ce flag, pydirectinput fait un
        # moveTo absolu et le curseur finit par buter sur le bord de l'écran.
        try:
            self.pdi.moveRel(int(dx), int(dy), relative=True)
        except TypeError:  # très vieilles versions de pydirectinput
            self.pdi.moveRel(int(dx), int(dy))

    def move_to(self, x: int, y: int) -> None:
        self.pdi.moveTo(int(x), int(y))

    def click(self, x: int, y: int, clicks: int = 1, interval_ms: int = 90) -> None:
        self.move_to(x, y)
        time.sleep(0.04)
        for _ in range(max(1, clicks)):
            self.pdi.click()
            time.sleep(max(0.01, interval_ms / 1000.0))

    # -------------------------------------------------------------- sécurité
    def release_all(self) -> None:
        """Remet le clavier et la souris dans un état propre (panic / arrêt)."""
        for key in list(self._held):
            try:
                self.pdi.keyUp(key)
            except Exception:
                pass
        self._held.clear()
        if self._mouse_held:
            try:
                self.pdi.mouseUp(button="left")
            except Exception:
                pass
            self._mouse_held = False

    def focus_ok(self) -> bool:
        """Vérifie que la fenêtre FiveM est au premier plan."""
        if not self.cfg.ui.require_focus or not _IS_WINDOWS:
            return True
        user32 = ctypes.windll.user32  # type: ignore[attr-defined]
        hwnd = user32.GetForegroundWindow()
        if not hwnd:
            return False
        buf = ctypes.create_unicode_buffer(256)
        user32.GetWindowTextW(hwnd, buf, 256)
        title = buf.value or ""
        return any(t.lower() in title.lower() for t in self.cfg.ui.window_titles)

    def stop_requested(self) -> bool:
        """Coupe-circuit matériel : touche configurée (F12 par défaut)."""
        if not _IS_WINDOWS:
            return False
        vk = _VK.get(self.cfg.keys.stop.lower())
        if vk is None:
            return False
        return bool(ctypes.windll.user32.GetAsyncKeyState(vk) & 0x8000)  # type: ignore[attr-defined]

    # ------------------------------------------------------------- actions UI
    def run_actions(self, actions: Iterable[dict[str, Any]], screenshot_dir: str = "debug") -> None:
        """Exécute une séquence d'actions générique (inventaire / kit / boutique)."""
        import logging
        from pathlib import Path

        log = logging.getLogger("fishing_bot.actions")
        for act in actions:
            kind = str(act.get("type", "")).lower()
            if kind == "sleep":
                time.sleep(float(act.get("ms", 200)) / 1000.0)
            elif kind == "key":
                self.press(str(act["key"]), int(act.get("ms", self.cfg.timing.key_press_ms)))
            elif kind == "keydown":
                self.key_down(str(act["key"]))
            elif kind == "keyup":
                self.key_up(str(act["key"]))
            elif kind == "move":
                self.move_to(int(act["x"]), int(act["y"]))
            elif kind == "click":
                self.click(
                    int(act["x"]),
                    int(act["y"]),
                    clicks=int(act.get("clicks", 1)),
                    interval_ms=int(act.get("interval_ms", 90)),
                )
            elif kind == "screenshot":
                try:
                    from .screen import ScreenCapture
                    Path(screenshot_dir).mkdir(parents=True, exist_ok=True)
                    ScreenCapture(self.cfg).save(
                        str(Path(screenshot_dir) / f"{act.get('name', 'action')}.png")
                    )
                except Exception as exc:  # pragma: no cover
                    log.warning("capture impossible: %s", exc)
            else:
                log.warning("action inconnue ignorée: %r", act)


class DirectionalActuator:
    """Transforme une consigne -1/0/+1 en rotation caméra ou en strafe."""

    def __init__(self, inputs: InputController, cfg: Config):
        self.inputs = inputs
        self.cfg = cfg
        self.mode = cfg.fight.actuator.lower()
        self._strafe_key: str | None = None

    def drive(self, direction: int, boost: float = 1.0) -> None:
        if self.mode == "strafe":
            key = None
            if direction > 0:
                key = self.cfg.fight.strafe_key_right
            elif direction < 0:
                key = self.cfg.fight.strafe_key_left
            if key != self._strafe_key:
                if self._strafe_key:
                    self.inputs.key_up(self._strafe_key)
                if key:
                    self.inputs.key_down(key)
                self._strafe_key = key
            return

        # Mode souris (par défaut) : déplacement RELATIF, pas de curseur absolu.
        if direction == 0:
            return
        step = int(self.cfg.fight.mouse_step_px * max(1.0, boost))
        step = min(step, self.cfg.fight.max_step_px)
        self.inputs.move_rel(step if direction > 0 else -step, 0)

    def stop(self) -> None:
        if self._strafe_key:
            self.inputs.key_up(self._strafe_key)
            self._strafe_key = None
