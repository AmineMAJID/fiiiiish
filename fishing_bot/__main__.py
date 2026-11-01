"""Point d'entrée CLI : ``python -m fishing_bot [options]``."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .config import Config
from .selftest import diagnose, run_selftest


def setup_logging(cfg: Config) -> logging.Logger:
    Path(cfg.debug.log_dir).mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("fishing_bot")
    logger.setLevel(getattr(logging, cfg.debug.log_level.upper(), logging.INFO))
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%H:%M:%S")
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    fh = logging.FileHandler(Path(cfg.debug.log_dir) / "fishing_bot.log", encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(sh)
    logger.addHandler(fh)
    logging.getLogger("fishing_bot.actions").setLevel(logger.level)
    return logger


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fishing_bot",
        description="Automatisation par simulation d'entrées du cycle de pêche qs-fishingjob (FiveM).",
    )
    p.add_argument("--config", default="fishing_bot_config.json", help="fichier JSON de configuration")
    p.add_argument("--init-config", action="store_true", help="écrit la configuration par défaut et quitte")
    p.add_argument("--selftest", action="store_true", help="vérifie les détecteurs sur images synthétiques")
    p.add_argument("--diagnose", metavar="IMAGE", help="analyse une capture PNG et affiche l'état détecté")
    p.add_argument("--observe", nargs="?", const=12.0, type=float, metavar="SECONDES",
                   help="lecture seule de l'écran (aucune entrée envoyée)")
    p.add_argument("--calibrate", choices=["cast", "decision"], help="calibration interactive")
    p.add_argument("--calibrate-image", metavar="IMAGE", help="calibre la piste depuis une capture de charge")
    p.add_argument("--target-power", type=float, help="puissance de lancer cible (0.05..1.0)")
    p.add_argument("--choice", choices=["keep", "release"], help="décision après prise")
    p.add_argument("--actuator", choices=["mouse", "strafe"], help="actionneur du combat")
    p.add_argument("--max-cycles", type=int, help="nombre maximum de cycles (0 = infini)")
    p.add_argument("--debug-frames", action="store_true", help="sauvegarde les captures de debug")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = Config.load(args.config)

    # Surcharges CLI (non persistées sauf --init-config / calibration).
    if args.target_power is not None:
        cfg.cast.target_power = max(0.05, min(1.0, args.target_power))
    if args.choice:
        cfg.decision.choice = args.choice
    if args.actuator:
        cfg.fight.actuator = args.actuator
    if args.max_cycles is not None:
        cfg.limits.max_cycles = max(0, args.max_cycles)
    if args.debug_frames:
        cfg.debug.save_frames = True

    if args.init_config:
        cfg.save(args.config)
        print(f"Configuration écrite : {args.config}")
        print("Éditez notamment actions.equip / actions.resupply / ui.window_titles.")
        return 0

    if args.selftest:
        return 0 if run_selftest() else 1

    if args.diagnose:
        diagnose(args.diagnose, cfg)
        return 0

    if args.calibrate_image:
        from .calibrate import calibrate_from_image
        calibrate_from_image(args.calibrate_image, cfg, args.config)
        return 0

    if args.observe is not None:
        from .calibrate import observe
        observe(cfg, args.observe)
        return 0

    if args.calibrate:
        from .calibrate import calibrate_cast, calibrate_decision
        ok = (
            calibrate_cast(cfg, args.config)
            if args.calibrate == "cast"
            else calibrate_decision(cfg, args.config)
        )
        return 0 if ok else 1

    logger = setup_logging(cfg)
    try:
        from .bot import FishingBot
        from .inputs import DirectionalActuator, InputController
        from .screen import ScreenCapture
        from .vision import Vision

        screen = ScreenCapture(cfg)
        vision = Vision(cfg)
        inputs = InputController(cfg)
        actuator = DirectionalActuator(inputs, cfg)
        bot = FishingBot(cfg, args.config, screen, vision, inputs, actuator, logger)
        bot.run()
        return 0
    except RuntimeError as exc:
        logger.error("%s", exc)
        return 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
