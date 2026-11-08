"""Vision tests: recover known values from a rendered HUD.

    python -m tests.test_vision

Every case renders a frame with the synthetic renderer at a known state, then
asserts the detector recovers it.  Resolutions and backgrounds are varied on
purpose: the tool must behave identically at 1080p, 1440p, 4K and on a 768-high
laptop panel, in daylight and at night.
"""

from __future__ import annotations

import sys
from typing import List, Tuple

try:
    import numpy as np
    HAVE_NUMPY = True
except Exception:
    HAVE_NUMPY = False

from fishbot import simhud, vision
from fishbot.geometry import catch_modal_layout, fight_layout, all_regions, rem

RESOLUTIONS = [
    (1920, 1080), (2560, 1440), (3840, 2160), (1280, 720),
    (1600, 900), (1366, 768), (3440, 1440), (1080, 1080),
]
WORLDS = ["sea", "night", "bright", "grey"]

failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name} {detail}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(f"{name} {detail}")


def frame(img, fw, fh, fit=None):
    """Wrap a rendered array.  ``fw``/``fh`` are the canvas, ``fit`` the window
    the HUD was laid out for (they differ for a scaled capture)."""
    kw = {}
    if fit:
        kw = {"window_width": fit[0], "window_height": fit[1]}
    return vision.Frame(arr=img, width=fw, height=fh, timestamp=0.0, **kw)


def test_tension() -> None:
    print("\n[line tension, the signal the whole controller runs on]")
    worst = 0.0
    worst_at = ""
    for fw, fh in RESOLUTIONS:
        for tension in (0.0, 0.05, 0.12, 0.25, 0.5, 0.7, 0.82, 0.9, 0.97):
            for world in WORLDS:
                img = simhud.render_fight(fw, fh, tension, 0.5, "left", world)
                got = vision.read_fight(frame(img, fw, fh)).tension
                err = abs(got - tension)
                if err > worst:
                    worst, worst_at = err, f"{fw}x{fh} {world} want {tension} got {got:.3f}"
    check("tension accuracy over 8 resolutions x 4 backgrounds", worst <= 0.035,
          f"worst error {worst:.3f} at {worst_at}")

    # a very dark frame (night + low brightness) must still work
    img = simhud.render_fight(1920, 1080, 0.6, 0.3, "left", "night", dim=0.55)
    got = vision.read_fight(frame(img, 1920, 1080)).tension
    check("tension at 55 % brightness", abs(got - 0.6) < 0.05, f"got {got:.3f}")


def test_progress() -> None:
    print("\n[reel progress]")
    for fw, fh in ((1920, 1080), (1280, 720)):
        for progress in (0.0, 0.03, 0.2, 0.55, 0.97, 1.0):
            img = simhud.render_fight(fw, fh, 0.4, progress, "left")
            got = vision.read_fight(frame(img, fw, fh)).progress
            check(f"progress {progress} at {fw}x{fh}", abs(got - progress) <= 0.04,
                  f"got {got:.3f}")


def test_side() -> None:
    print("\n[cue chevrons]")
    for fw, fh in RESOLUTIONS:
        for world in WORLDS:
            for side in ("left", "right"):
                img = simhud.render_fight(fw, fh, 0.3, 0.1, side, world)
                got = vision.read_fight(frame(img, fw, fh)).side
                check(f"{side} lit at {fw}x{fh} {world}", got == side, f"got {got}")
            img = simhud.render_fight(fw, fh, 0.3, 0.1, None, world)
            got = vision.read_fight(frame(img, fw, fh)).side
            check(f"no cue at {fw}x{fh} {world}", got is None, f"got {got}")


def test_presence() -> None:
    print("\n[is the fight HUD on screen?]")
    for fw, fh in RESOLUTIONS:
        img = simhud.render_fight(fw, fh, 0.35, 0.2, "right")
        check(f"fight detected at {fw}x{fh}", vision.read_fight(frame(img, fw, fh)).present)
        plain = simhud._blank(fw, fh, "sea")
        absent = vision.read_fight(frame(plain, fw, fh)).present
        check(f"no fight on a plain frame at {fw}x{fh}", not absent, f"got {absent}")


def test_bite_ring() -> None:
    print("\n[bite countdown ring]")
    for fw, fh in ((1920, 1080), (2560, 1440), (1280, 720)):
        for remaining in (1.0, 0.75, 0.5, 0.25, 0.08):
            img = simhud.render_bite(fw, fh, remaining)
            got = vision.read_bite(frame(img, fw, fh))
            check(f"ring {remaining} at {fw}x{fh}",
                  abs(got.remaining - remaining) < 0.10 and got.biting,
                  f"got {got.remaining:.3f} biting={got.biting}")


def test_cast_power() -> None:
    print("\n[cast power meter]")
    for fw, fh in ((1920, 1080), (1280, 720), (3840, 2160)):
        for power in (0.15, 0.4, 0.65, 0.95):
            img = simhud.render_cast(fw, fh, power)
            got = vision.read_cast(frame(img, fw, fh))
            check(f"power {power} at {fw}x{fh}",
                  got.present and abs(got.power - power) < 0.12,
                  f"got {got.power:.3f} present={got.present}")


def test_cast_gate() -> None:
    print("\n[the cast prompt: green key = go, grey key = the game says no]")
    for fw, fh in ((1920, 1080), (1280, 720), (2560, 1440), (3840, 2160), (1080, 1080)):
        for world in WORLDS:
            plain = vision.read_cast_gate(frame(simhud._blank(fw, fh, world), fw, fh))
            check(f"no prompt on a plain {world} frame at {fw}x{fh}", not plain.present,
                  str(plain))
            ready = vision.read_cast_gate(
                frame(simhud.render_depth_card(fw, fh, True, world), fw, fh))
            check(f"green prompt reads ready at {fw}x{fh} ({world})", ready.ready, str(ready))
            blocked = vision.read_cast_gate(
                frame(simhud.render_depth_card(fw, fh, False, world), fw, fh))
            check(f"grey prompt reads blocked at {fw}x{fh} ({world})",
                  blocked.blocked and not blocked.ready, str(blocked))


def test_plain_frames_are_empty() -> None:
    print("\n[nothing on screen is not mistaken for something]")
    for fw, fh in RESOLUTIONS:
        for world in WORLDS:
            plain = frame(simhud._blank(fw, fh, world), fw, fh)
            checks = (("reel", vision.read_fight(plain).present),
                      ("bite", vision.read_bite(plain).present),
                      ("cast", vision.read_cast(plain).present),
                      ("catch", vision.read_catch_modal(plain).present),
                      ("toast", vision.read_error_toast(plain)))
            for name, seen in checks:
                check(f"no {name} HUD on a plain {world} frame at {fw}x{fh}", not seen)


def test_scaled_capture() -> None:
    print("\n[halved capture of the same window reads the same numbers]")
    for fw, fh in ((1280, 720), (1920, 1080), (2560, 1440)):
        cw, ch = fw // 2, fh // 2
        for world in ("sea", "night"):
            img = simhud.render_fight(cw, ch, 0.62, 0.81, "left", world, fit=(fw, fh))
            got = vision.read_fight(frame(img, cw, ch, fit=(fw, fh)))
            check(f"tension survives halving at {fw}x{fh} ({world})",
                  abs(got.tension - 0.62) < 0.02, f"{got.tension:.3f}")
            check(f"progress survives halving at {fw}x{fh} ({world})",
                  abs(got.progress - 0.81) < 0.02, f"{got.progress:.3f}")
            check(f"cue survives halving at {fw}x{fh} ({world})", got.side == "left", got.side)
            modal = simhud.render_catch_modal(cw, ch, world, fit=(fw, fh))
            got_m = vision.read_catch_modal(frame(modal, cw, ch, fit=(fw, fh)))
            check(f"catch card survives halving at {fw}x{fh} ({world})", got_m.present)
            if got_m.keep_rect:
                box = got_m.keep_rect
                check(f"the KEEP button is still on the card at {fw}x{fh}",
                      0.5 < box.cx < 0.95 and 0.3 < box.cy < 0.9,
                      f"({box.cx:.2f},{box.cy:.2f})")


def test_catch_modal() -> None:
    print("\n[KEEP / RELEASE modal]")
    for fw, fh in ((1920, 1080), (2560, 1440), (1280, 720), (3440, 1440)):
        img = simhud.render_catch_modal(fw, fh)
        got = vision.read_catch_modal(frame(img, fw, fh))
        check(f"modal detected at {fw}x{fh}", got.present, f"conf={got.confidence:.2f}")
        if got.keep_rect and got.release_rect:
            lay = catch_modal_layout(fw, fh)
            inside = (lay["keep"].x <= got.keep_rect.cx <= lay["keep"].x2
                      and lay["release"].x <= got.release_rect.cx <= lay["release"].x2)
            check(f"click targets land on the buttons at {fw}x{fh}", inside)
        for world in WORLDS:
            plain = simhud._blank(fw, fh, world)
            check(f"no modal on a plain {world} frame at {fw}x{fh}",
                  not vision.read_catch_modal(frame(plain, fw, fh)).present)
            shown = simhud.render_catch_modal(fw, fh, world)
            check(f"modal still found over a {world} background at {fw}x{fh}",
                  vision.read_catch_modal(frame(shown, fw, fh)).present)


def test_error_toast() -> None:
    print("\n[error toast: 'inventory full' style]")
    for fw, fh in ((1920, 1080), (2560, 1440), (1280, 720)):
        img = simhud.render_error_toast(fw, fh)
        check(f"error toast detected at {fw}x{fh}", vision.read_error_toast(frame(img, fw, fh)))
        plain = simhud._blank(fw, fh, "sea")
        check(f"no false toast at {fw}x{fh}", not vision.read_error_toast(frame(plain, fw, fh)))


def test_geometry_sanity() -> None:
    print("\n[geometry]")
    for fw, fh in RESOLUTIONS:
        u = rem(fw, fh)
        lay = fight_layout(fw, fh)
        ok = (0 < lay.hud.w <= 1 and 0 < lay.hud.h <= 1
              and 0 <= lay.hud.x and lay.hud.y2 <= 1.0001
              and lay.tension_track.w > 0.05 and lay.tension_track.h > 0.0
              and lay.cue_left.x2 <= lay.cue_right.x
              and 8.0 <= u <= 32.0)
        check(f"fight layout sane at {fw}x{fh}", ok, f"rem={u:.2f} {lay.describe()}")
        regions = all_regions(fw, fh)
        inside = all(-0.01 <= r.x and r.x2 <= 1.01 and -0.01 <= r.y and r.y2 <= 1.01
                     for r in regions.values())
        check(f"all regions on screen at {fw}x{fh}", inside)


def main() -> int:
    if not HAVE_NUMPY:
        print("numpy is required for the vision tests")
        return 2
    test_geometry_sanity()
    test_tension()
    test_progress()
    test_side()
    test_presence()
    test_bite_ring()
    test_cast_power()
    test_cast_gate()
    test_plain_frames_are_empty()
    test_scaled_capture()
    test_catch_modal()
    test_error_toast()
    print()
    if failures:
        print(f"{len(failures)} FAILURES")
        for f in failures[:40]:
            print("  -", f)
        return 1
    print("all vision checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
