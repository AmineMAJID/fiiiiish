"""Command line interface.

    python -m fiiiiish_auto simulate     # grid test, no game needed
    python -m fiiiiish_auto fight        # one fight, optional trace
    python -m fiiiiish_auto replay       # verify a recorded trace
    python -m fiiiiish_auto doctor       # check the live prerequisites
    python -m fiiiiish_auto live         # the real bot (Windows)

The simulator is the default because it is the only mode that can be tested
without a running FiveM client.  The live mode reuses the exact controller.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import platform
import sys
import time
from dataclasses import replace
from pathlib import Path

from .config import FIGHT_DIFFICULTY_TIERS
from .controller import FightController
from .fight import CameraModel, NuiModel, NuiView
from .fishing import Aggregate, Scenario, Simulator
from .live import LiveBot, LiveBotConfig
from .loop import FightSession
from .nui import CdpClient, NuiError, NuiUnavailable

log = logging.getLogger("fiiiiish_auto")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _parse_floats(value: str | None) -> list[float]:
    if not value:
        return []
    return [float(x) for x in value.replace(" ", "").split(",") if x]


def _parse_tiers(value: str | None) -> list[str]:
    if not value or value.lower() == "all":
        return list(FIGHT_DIFFICULTY_TIERS.keys())
    return [x.strip() for x in value.split(",") if x.strip()]


def _print_aggregate(label: str, agg: Aggregate) -> None:
    d = agg.as_dict()
    print(
        f"{label:<34} "
        f"ok={d['successes']:>4}/{d['runs']:<4} "
        f"rate={d['success_rate']*100:6.2f}% "
        f"fight={d['avg_fight']:6.2f}s "
        f"total={d['avg_time']:6.2f}s "
        f"danger<={d['max_danger']:3d} "
        f"snaps={d['line_snaps']} "
        f"timeouts={d['timeouts']} "
        f"rods={d['rod_breaks']}"
    )


# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------
def cmd_simulate(args: argparse.Namespace) -> int:
    tiers = _parse_tiers(args.tier)
    powers = _parse_floats(args.power) or [0.2, 0.5, 0.8]
    qualities = _parse_floats(args.quality) or [0.5]
    rows: list[dict] = []

    print(
        "fiiiiish_auto simulator -- deterministic, fixed-step, no game required\n"
        f"runs={args.runs} seed={args.seed} control={args.control_hz} Hz "
        f"fight={args.fight_hz} Hz setpoint={args.setpoint}\n"
    )
    header = (
        f"{'scenario':<34} {'ok':>9} {'rate':>8} {'fight':>8} "
        f"{'total':>8} {'danger':>7} {'snaps':>6} {'timeouts':>8} {'rods':>5}"
    )
    print(header)
    print("-" * len(header))

    for tier in tiers:
        for quality in qualities:
            for power in powers:
                scenario = Scenario(
                    tier=tier,
                    specimen_quality=quality,
                    cast_power=power,
                    fight_ease_percent=args.ease,
                    line_strength_percent=args.line,
                    seed=args.seed,
                )
                sim = Simulator(
                    scenario,
                    runs=args.runs,
                    seed=args.seed,
                    controller=FightController(setpoint=args.setpoint),
                    fight_hz=args.fight_hz,
                    control_hz=args.control_hz,
                )
                agg = sim.run()
                label = f"{tier} q={quality:.2f} p={power:.2f}"
                _print_aggregate(label, agg)
                rows.append({"scenario": label, **agg.as_dict()})

    if args.json:
        print("\n" + json.dumps(rows, indent=2))
    return 0


def cmd_fight(args: argparse.Namespace) -> int:
    scenario = Scenario(
        tier=args.tier,
        specimen_quality=args.quality,
        cast_power=args.power,
        fight_ease_percent=args.ease,
        line_strength_percent=args.line,
        seed=args.seed,
    )
    params = scenario.fight_params()
    distance = scenario.distance()
    controller = FightController(setpoint=args.setpoint)
    result = FightSession(
        params,
        distance,
        seed=args.seed,
        controller=controller,
        fight_hz=args.fight_hz,
        control_hz=args.control_hz,
        record=True,
    ).run()

    print(
        f"tier={args.tier} quality={args.quality:.2f} power={args.power:.2f} "
        f"distance={distance:.1f}m difficulty={scenario.difficulty():.3f}\n"
        f"params: max_angle={params.max_angle:.2f} pull={params.pull_speed:.5f} "
        f"slip={params.slip_speed:.5f} turn={params.turn_rate:.3f}\n"
        f"outcome={result.outcome} duration={result.duration:.2f}s "
        f"progress={result.progress} max_danger={result.max_danger} "
        f"flips={result.flips} decisions={result.decisions}\n"
        f"modes={result.modes}"
    )
    if args.trace:
        path = Path(args.trace)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as fh:
            for row in result.trace:
                fh.write(json.dumps(row) + "\n")
        print(f"trace written to {path} ({len(result.trace)} control ticks)")
    if args.json:
        print(json.dumps(result.final_state, indent=2))
    return 0


def cmd_replay(args: argparse.Namespace) -> int:
    path = Path(args.trace)
    if not path.exists():
        print(f"trace not found: {path}", file=sys.stderr)
        return 2
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows:
        print("trace is empty", file=sys.stderr)
        return 2

    controller = FightController(setpoint=args.setpoint)
    matches = 0
    mismatches = 0
    last = rows[0]["t"]
    verdict = None
    for i, row in enumerate(rows):
        view = NuiView(
            danger=int(row["view"].get("danger", 0)),
            progress=int(row["view"].get("progress", 0)),
            side=row["view"].get("side"),
            active=bool(row["view"].get("active")),
            verdict=row["view"].get("verdict"),
        )
        now = float(row["t"])
        dt = max(0.001, now - last) if i else 1.0 / args.control_hz
        last = now
        decision = controller.tick(view, dt, now)
        if abs(decision.step - float(row.get("step", 0.0))) < 1e-6 and decision.mode == row.get("mode"):
            matches += 1
        else:
            mismatches += 1
            if mismatches <= 5:
                print(
                    f"tick {i}: expected step={row.get('step')} mode={row.get('mode')} "
                    f"got step={decision.step:.3f} mode={decision.mode}"
                )
        if view.verdict:
            verdict = view.verdict

    print(
        f"replay {path}: {matches} matching ticks, {mismatches} mismatches, "
        f"verdict={verdict}"
    )
    return 0 if mismatches == 0 else 1


def cmd_doctor(args: argparse.Namespace) -> int:
    print("fiiiiish_auto doctor")
    print(f"  python      : {sys.version.split()[0]} ({platform.platform()})")
    print(f"  os          : {platform.system()} {platform.release()}")
    try:
        import websocket  # noqa: F401

        print("  websocket   : ok (websocket-client)")
    except Exception:
        print("  websocket   : MISSING (pip install websocket-client)")
    if sys.platform == "win32":
        print("  input       : Win32 SendInput available")
    else:
        print("  input       : live mode needs Windows; simulator works here")

    client = CdpClient(args.endpoint, timeout=2.0)
    try:
        pages = client.list_pages()
        print(f"  CEF         : reachable at {args.endpoint} ({len(pages)} page targets)")
        for page in pages:
            print(f"    - {page.get('title', '?')!r}  {page.get('url', '')}")
        if pages:
            try:
                client.connect(args.page_match)
                print(f"  NUI probe   : attached to {client.page_url}")
                probe = (
                    '!!document.querySelector('
                    '\'[class*="cueRow"], [class*="depthValue"], '
                    '[class*="cardLive"], [class*="floatBiting"]\''
                    ')'
                )
                hud = "visible" if client.evaluate(probe) else "not visible right now"
                print(f"  fishing HUD : {hud}")
                client.close()
            except NuiUnavailable as exc:
                print(f"  NUI probe   : {exc}")
    except NuiUnavailable as exc:
        print(f"  CEF         : unreachable ({exc})")
        print("                Start FiveM, join the server, then retry.")
    return 0


def cmd_live(args: argparse.Namespace) -> int:
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    config = LiveBotConfig(
        endpoint=args.endpoint,
        page_match=args.page_match,
        control_hz=args.control_hz,
        setpoint=args.setpoint,
        deadband=args.deadband,
        max_step=args.max_step,
        hold_step=args.hold_step,
        hold_gain=args.hold_gain,
        reaction_delay=args.reaction_delay,
        emergency=args.emergency,
        max_fight_duration=args.max_fight_duration,
        cast_power=args.cast_power,
        decision=args.decision,
        sensitivity=args.sensitivity,
        invert_x=args.invert_x,
        game_title=args.game_title,
        dry_run=args.dry_run,
        record_path=args.record,
    )

    if args.list_pages:
        client = CdpClient(args.endpoint)
        try:
            for page in client.list_pages():
                print(f"{page.get('title', '?')!r}  {page.get('url', '')}")
        except NuiUnavailable as exc:
            print(f"cannot reach CEF: {exc}", file=sys.stderr)
            return 2
        return 0

    bot = LiveBot(config)
    try:
        if args.calibrate:
            bot.calibrate()
            return 0
        stats = bot.run()
    except (NuiUnavailable, NuiError) as exc:
        print(f"live: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\ninterrupted")
        stats = dict(bot.stats)
    print("live stats:", json.dumps(stats, indent=2))
    return 0


# ---------------------------------------------------------------------------
# parser
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fiiiiish_auto",
        description="Deterministic auto-player for the fiiiiish / qs-fisher reel-in minigame.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_sim = sub.add_parser("simulate", help="run the headless grid test")
    p_sim.add_argument("--runs", type=int, default=100)
    p_sim.add_argument("--seed", type=int, default=42)
    p_sim.add_argument("--tier", default="all")
    p_sim.add_argument("--power", default="0.2,0.5,0.8")
    p_sim.add_argument("--quality", default="0.5")
    p_sim.add_argument("--ease", type=float, default=0.0)
    p_sim.add_argument("--line", type=float, default=0.0)
    p_sim.add_argument("--control-hz", type=float, default=30.0)
    p_sim.add_argument("--fight-hz", type=float, default=60.0)
    p_sim.add_argument("--setpoint", type=float, default=75.0)
    p_sim.add_argument("--json", action="store_true")
    p_sim.set_defaults(func=cmd_simulate)

    p_fight = sub.add_parser("fight", help="run one fight and optionally record the trace")
    p_fight.add_argument("--tier", default="mid")
    p_fight.add_argument("--quality", type=float, default=0.5)
    p_fight.add_argument("--power", type=float, default=0.5)
    p_fight.add_argument("--ease", type=float, default=0.0)
    p_fight.add_argument("--line", type=float, default=0.0)
    p_fight.add_argument("--seed", type=int, default=42)
    p_fight.add_argument("--control-hz", type=float, default=30.0)
    p_fight.add_argument("--fight-hz", type=float, default=60.0)
    p_fight.add_argument("--setpoint", type=float, default=75.0)
    p_fight.add_argument("--trace", default=None)
    p_fight.add_argument("--json", action="store_true")
    p_fight.set_defaults(func=cmd_fight)

    p_replay = sub.add_parser("replay", help="re-run a recorded trace through the controller")
    p_replay.add_argument("trace")
    p_replay.add_argument("--setpoint", type=float, default=75.0)
    p_replay.add_argument("--control-hz", type=float, default=30.0)
    p_replay.set_defaults(func=cmd_replay)

    p_doc = sub.add_parser("doctor", help="check live prerequisites")
    p_doc.add_argument("--endpoint", default="http://127.0.0.1:13172")
    p_doc.add_argument("--page-match", default=None)
    p_doc.set_defaults(func=cmd_doctor)

    p_live = sub.add_parser("live", help="run the bot against the real game (Windows)")
    p_live.add_argument("--endpoint", default="http://127.0.0.1:13172")
    p_live.add_argument("--page-match", default=None)
    p_live.add_argument("--control-hz", type=float, default=30.0)
    p_live.add_argument("--setpoint", type=float, default=75.0)
    p_live.add_argument("--deadband", type=float, default=3.0)
    p_live.add_argument("--max-step", type=float, default=6.0)
    p_live.add_argument("--hold-step", type=float, default=2.5)
    p_live.add_argument("--hold-gain", type=float, default=0.08)
    p_live.add_argument("--reaction-delay", type=float, default=0.05)
    p_live.add_argument("--emergency", type=float, default=92.0)
    p_live.add_argument("--max-fight-duration", type=float, default=180.0)
    p_live.add_argument("--cast-power", type=float, default=0.5)
    p_live.add_argument("--decision", choices=("keep", "release"), default="keep")
    p_live.add_argument("--sensitivity", type=float, default=0.10)
    p_live.add_argument("--invert-x", action="store_true")
    p_live.add_argument("--game-title", default="FiveM")
    p_live.add_argument("--dry-run", action="store_true")
    p_live.add_argument("--record", default=None)
    p_live.add_argument("--calibrate", action="store_true")
    p_live.add_argument("--list-pages", action="store_true")
    p_live.add_argument("--log-level", default="INFO")
    p_live.set_defaults(func=cmd_live)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
