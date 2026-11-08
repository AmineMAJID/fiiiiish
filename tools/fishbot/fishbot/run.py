"""The program the player actually runs.

    python -m fishbot.run

Put the rod in your hand, face the water, start this.  It finds the game window
on its own, reads the HUD out of the screen, and plays the loop until you stop
it:

    cast (full power) -> wait -> strike -> reel -> KEEP -> repeat

Keys (polled globally, so they work whatever has focus):

    F9   start / resume after a pause
    F10  stop
    F11  pause

Useful first runs
-----------------
    python -m fishbot.run --probe      what window was found, and what the HUD
                                       reader currently sees
    python -m fishbot.run --snapshot   write a PNG of the captured frame with
                                       every HUD region outlined (calibration)
    python -m fishbot.run --dry-run    read the screen, decide, but never touch
                                       the mouse or keyboard
"""

from __future__ import annotations

import argparse
import sys
import time
from typing import Optional

from . import settings, vision
from .bot import FishingBot, BotConfig
from .controller import BotParams, FightController
from .geometry import all_regions
from .report import Reporter, outline, pace, write_png

try:
    from .winapi import (FakeSource, HotkeyWatcher, Injector, ScreenSource,
                         client_area, set_dpi_awareness)
except Exception as exc:  # pragma: no cover - only on non-Windows
    print(f"fishbot needs Windows: {exc}", file=sys.stderr)
    raise SystemExit(2)


# ── the loop ────────────────────────────────────────────────────────────────
def _frame_report(source) -> None:
    """Human-readable readout of what the reader can currently see."""
    frame = source.grab()
    print(f"  frame      {frame.width}x{frame.height}  brightness {frame.mean_brightness():.2f}")
    print(f"  cast card  {vision.read_cast(frame)}")
    print(f"  cast gate  {vision.read_cast_gate(frame)}")
    print(f"  bite       {vision.read_bite(frame)}")
    print(f"  reel       {vision.read_fight(frame)}")
    print(f"  catch      {vision.read_catch_modal(frame)}")
    print(f"  red toast  {vision.read_error_toast(frame)}")


def main(argv: Optional[list] = None) -> int:
    ap = argparse.ArgumentParser(prog="fishbot", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    stored = settings.load()
    ap.add_argument("--scale", type=float, default=stored["scale"],
                    help="capture at this fraction of the window (default 0.5; the HUD is rem-based)")
    ap.add_argument("--capture", choices=("printwindow", "bitblt"), default=stored["capture"],
                    help="how to grab the game picture (auto-falls back to the other one)")
    ap.add_argument("--window-title", default=stored["window_title"] or None,
                    help="part of the game window title, if autodetection picks the wrong window")
    ap.add_argument("--hz", type=float, default=stored["hz"],
                    help="samples per second (default 20)")
    ap.add_argument("--keep", dest="keep", action="store_true", default=stored["keep"],
                    help="take every fish (default)")
    ap.add_argument("--release", dest="keep", action="store_false",
                    help="release every fish instead")
    ap.add_argument("--once", type=int, default=0, help="stop after this many fish")
    ap.add_argument("--interact-key", default="e",
                    help="the resource's interaction key, if your server rebinds it")
    ap.add_argument("--start-now", action="store_true",
                    help="begin fishing immediately instead of waiting for F9")
    ap.add_argument("--no-alert", dest="alert", action="store_false", default=True,
                    help="no beep when the tool needs you")
    ap.add_argument("--simulate", action="store_true",
                    help="use a synthetic HUD instead of the game window (smoke test)")
    ap.add_argument("--dry-run", action="store_true",
                    help="read the screen and make decisions, but send no input")
    ap.add_argument("--probe", action="store_true", help="print the window and a HUD readout, then exit")
    ap.add_argument("--snapshot", metavar="PNG", nargs="?", const="fishbot-snapshot.png",
                    help="write the captured frame with the HUD regions outlined, then exit")
    ap.add_argument("--sensitivity", type=float, default=stored["counts_per_pct"],
                    help="initial mouse counts per percent of tension "
                         "(remembered from the last session, then self-calibrated)")
    args = ap.parse_args(argv)

    from .vision import HAVE_NUMPY
    if not HAVE_NUMPY:
        print("\nnumpy is required (it is what makes the HUD readable in time):\n"
              "    pip install -r tools/fishbot/requirements.txt\n", file=sys.stderr)
        return 2

    titles = (args.window_title,) if args.window_title else ("FiveM", "Grand Theft Auto V",
                                                            "GTAV", "CitizenFX")
    if args.simulate:
        source = FakeSource(scale=args.scale)
        hwnd = None
        area_text = source.describe()
    else:
        set_dpi_awareness()
        try:
            area = client_area(titles=titles)
        except RuntimeError as exc:
            print(f"\n{exc}\n", file=sys.stderr)
            return 2
        hwnd = area.hwnd
        area_text = area.describe()
        source = ScreenSource(scale=args.scale, method=args.capture, hwnd=hwnd,
                              titles=tuple(titles))

    print("fishbot")
    print(f"  window     {area_text}")
    if stored["sessions"]:
        print(f"  memory     {stored['sessions']} session(s), "
              f"{stored['fish_kept']} fish kept, "
              f"sensitivity {stored['counts_per_pct']:.2f} counts/% (learned)")
    print(f"  HUD scale  every box is rem-based, so this resolution is handled by construction")

    try:
        source.refresh()
    except RuntimeError as exc:
        print(f"\n{exc}\n", file=sys.stderr)
        return 2

    if args.probe:
        print("\ncurrent HUD readout:")
        _frame_report(source)
        return 0

    if args.snapshot:
        frame = source.grab()
        if frame.mean_brightness() < 0.02:
            print("\nthe capture came back black - the game is not drawing where the "
                  "window says it is.\nTry --capture bitblt, and if the game is in "
                  "exclusive fullscreen switch it to borderless.", file=sys.stderr)
        img = frame.arr.astype("uint8").copy()
        # The regions are laid out for the *window*; drawing the ones derived
        # from the (possibly halved) capture would outline the wrong boxes.
        regions = all_regions(*frame.viewport)
        idx = 0
        for name, box in regions.items():
            outline(img, box, (255, 64, 64) if idx % 2 else (64, 200, 255),
                    firm=(frame.viewport != (frame.width, frame.height)))
            idx += 1
        write_png(args.snapshot, img)
        print(f"\nwrote {args.snapshot} ({frame.width}x{frame.height}) with {len(regions)} regions outlined")
        return 0

    reporter = Reporter(alert=args.alert)
    # `--dry-run` keeps the *real* injector, with its foreground guard, but
    # sends nothing: every call is still checked and journalled, so a dry run
    # exercises the same code path the live one does.
    injector = Injector(dry_run=args.dry_run or args.simulate,
                        require_foreground=not (args.dry_run or args.simulate),
                        target_hwnd=hwnd)
    config = BotConfig(loop_hz=args.hz, keep=args.keep, max_cycles=args.once,
                       interact_key=args.interact_key)
    controller = FightController(params=BotParams(counts_per_pct=args.sensitivity))
    bot = FishingBot(source=source, injector=injector, config=config,
                     controller=controller, notify=reporter)
    hotkeys = HotkeyWatcher(dry_run=args.dry_run or args.simulate)

    if args.simulate:
        reporter.say("\nSIMULATION: synthetic HUD, nothing is pressed.  "
                     "F10 / Ctrl-C to stop.\n")
    elif args.dry_run:
        reporter.say("\nDRY RUN: nothing will be pressed.  Ctrl-C to stop.\n")
    else:
        reporter.say("\nF9 start/resume   F10 stop   F11 pause.  "
                     "Keep the game window focused.\n")
    reporter.say("cast -> wait -> strike -> reel -> keep, forever.  Ctrl-C also works.\n")

    # It starts *armed but idle*, not fishing: the tool has just taken over the
    # mouse, and the player still has to get back into the game window.  One F9
    # (which is polled globally, so it works from anywhere) starts the loop.
    if not (args.start_now or args.simulate or args.dry_run):
        bot.pause("waiting for F9")
        reporter.say("\narmed.  Press F9 to start fishing.\n")

    black_frames = 0
    warned_fullscreen = False
    warned_window = False
    last_status = 0.0
    try:
        while not bot.stopped:
            for name in hotkeys.poll():
                if name == "stop":
                    bot.stop()
                elif name == "pause":
                    if not bot.paused:
                        bot.pause("user")
                        reporter("warn", "paused - F9 to resume")
                elif name == "start":
                    if bot.paused:
                        bot.resume()
                        reporter("info", "fishing")

            started = time.time()
            try:
                source.refresh()
            except RuntimeError as exc:
                # The game was minimised, closed, or the window handle moved.
                # Keep the session alive; the loop resumes when it comes back.
                if not warned_window:
                    warned_window = True
                    # Minimised is the common case (the player alt-tabbed) and
                    # it is not a failure: say what to do and keep waiting.
                    msg = str(exc)
                    if "minimised" in msg:
                        reporter("warn", "the game window is minimised - it will resume "
                                         "when you restore it")
                    else:
                        reporter("error", f"lost the game window ({msg}); waiting for it")
                time.sleep(0.5)
                continue
            else:
                if warned_window:
                    warned_window = False
                    reporter("info", "game window is back")
            bot.step()

            # Exclusive fullscreen is the one mode DWM can refuse to hand over:
            # the window is found, but every frame is black.  Say so plainly
            # instead of looping silently.
            frame = bot.last_frame
            if frame is not None and frame.mean_brightness() < 0.02:
                black_frames += 1
                if black_frames == 8 and not warned_fullscreen:
                    warned_fullscreen = True
                    reporter("error",
                             "the capture is black.  If the game is in exclusive "
                             "fullscreen, switch it to borderless (or windowed) - "
                             "a desktop tool cannot read a fullscreen D3D swap chain.")
            else:
                black_frames = 0

            now = time.time()
            if now - last_status > 3.0:
                last_status = now
                reporter.say("  " + bot.status.summary())
            pace(started, args.hz)
    except KeyboardInterrupt:
        reporter.say("\ninterrupted")
    finally:
        bot.stop()
        try:
            injector.mouse_up("left")
        except Exception:
            pass
        st = bot.status
        reporter.say(f"\n{st.summary()}")
        reporter.say(f"session: {st.casts} casts, {st.fish_kept} kept, "
                     f"{st.fish_released} released, "
                     f"{st.fights_won} fights won / {st.fights_lost} lost, "
                     f"counts/% learned = {controller.params.counts_per_pct:.2f}")
        # Remember the calibration (and the running total) so the next session
        # does not have to make its blind first swing all over again.
        stored["counts_per_pct"] = round(float(controller.params.counts_per_pct), 4)
        stored["sessions"] = int(stored.get("sessions", 0)) + 1
        stored["fish_kept"] = int(stored.get("fish_kept", 0)) + st.fish_kept
        stored["keep"] = bool(args.keep)
        if settings.save(stored):
            reporter.say(f"remembered: {stored['counts_per_pct']:.2f} counts/% "
                         f"({stored['fish_kept']} fish kept so far)")
        reporter.say(f"settings in {settings.settings_path()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
