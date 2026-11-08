# fishbot

A standalone Python tool that plays the `qs-fisher` fishing loop for you, by
looking at the screen.

It is **client-side only**: nothing in this resource is modified, no Lua bridge,
no `fxmanifest` change, no server-side anything. The tool reads the HUD pixels
the resource already draws and moves the mouse and keyboard the way a player
would.

```
cast at full power -> wait for the bite -> strike -> fight the fish -> KEEP -> repeat
```

* **Full loop, unattended.** Equip the rod, face the water, start it, walk away.
* **Always KEEPs** (sell at the shop later). `--release` if you want the XP.
* **Full bag → it stops and beeps.** Clear the bag, press `F9`, it carries on.
* **Any resolution, any display mode** that a normal desktop window can be read
  in (windowed, borderless). Exclusive fullscreen cannot be read by a desktop
  tool — the tool detects that case and tells you instead of pretending.

---

## Install

Windows, Python 3.9+.

```
pip install -r tools/fishbot/requirements.txt
```

`numpy` is the only dependency, and the only thing that touches Windows is
`ctypes` from the standard library: no pywin32, no pydirectinput, no OpenCV, no
Pillow.

## Run

Put the rod in your hand and face the water (the same preconditions the resource
itself wants: near water, rod equipped, not in a vehicle), then:

```
cd tools/fishbot
python -m fishbot.run
```

| key | what it does |
| --- | --- |
| `F9` | start, or resume after a pause |
| `F10` | stop |
| `F11` | pause (also fires on a full bag / refused action) |

It starts **armed but idle**: it finds the window, reports what it found, and
waits. `F9` starts the fishing (`--start-now` skips the wait). Keeping the game
window focused is on you: the tool refuses to send input to an unfocused window,
on purpose.

If the window disappears mid-session (minimised, closed, moved between monitors)
the loop waits for it and picks up where it left off; the window rect is re-read
every sample, so a resolution or display-mode change is followed automatically.

### First run

```
python -m fishbot.run --probe        # which window was found, and what the reader sees
python -m fishbot.run --snapshot     # writes fishbot-snapshot.png with every HUD box outlined
python -m fishbot.run --dry-run      # reads and decides, presses nothing
```

`--probe` is the fastest way to confirm the window was found and the HUD is
legible. `--snapshot` draws every region the reader uses on top of the captured
frame — if a box is not where the resource draws that element, that picture says
so immediately. `--dry-run` is safe to run while actually fishing: it logs the
whole loop and sends no input at all.

`--simulate` runs the whole program against a synthetic HUD instead of the game:
no window is looked for and nothing is pressed. It is the smoke test — if
`python -m fishbot.run --simulate` starts, reads, casts and shuts down cleanly on
a machine with no game installed, the plumbing is fine.

Useful flags: `--scale 0.5` (capture size, default half), `--capture bitblt`
(if the default `printwindow` comes back black), `--window-title "FiveM"`,
`--once 50` (stop after N fish), `--no-alert` (no beeps), `--start-now` (skip
F9), `--interact-key e` (if your server rebinds the interaction key).

### What it remembers

The learned sensitivity (`counts_per_pct`) and a fish counter are kept in
`~/.fishbot/settings.json` (override the folder with `FISHBOT_HOME`). That is the
same file the flags above default from, so a second session starts already
calibrated instead of making the blind first swing again. Delete the file to
start from scratch.

---

## How it sees

The resource draws its HUD in a browser layer at a handful of known places, all
sized in `rem` units. The stylesheet clamps `rem` to the viewport:

```
rem = clamp(8, min(width / 120, height / 67.5), 32)
```

so every HUD box is a fixed *fraction* of the window, and the same geometry code
works at 1280x720, 1080p, 1440p and 4K without calibration. That is also the
answer to "can it detect the resolution?": it does not need to — it reads the
window's real client size and derives every box from it, so it adapts to
whatever the window is, including after you resize it mid-session (the capture
source re-reads the window rect and re-derives everything).

What is read, and how:

| question | where | how |
| --- | --- | --- |
| **may I cast at all?** | the depth card's action key | green plate vs slate plate |
| is the reel HUD up? | the mini-game panel | bar-track contrast + the card itself |
| which way to pull | the lit chevron | left-vs-right brightness ratio |
| line tension (danger) | the tension bar | saturated fill width |
| reel progress | the progress bar | saturated fill width |
| has a fish bitten? | the countdown ring | ring circumference coverage |
| cast power | the power card | vertical fill height |
| KEEP or RELEASE? | the catch card | two dark plates with bright text |
| is the bag full? | the toast stack | red pixels |

Every detector compares a region against itself or its neighbours rather than
against an absolute colour, so night, weather, brightness and PostFX settings do
not matter. Verified at 8 resolutions x 4 backgrounds (plus a 55 %-brightness
frame): 187 checks, worst tension error 0.004.

## How it fishes

The reel mini-game has no button to press: it is steered with the **camera**,
and the line snaps the moment the angle exceeds the rod's maximum. The tool
sends relative mouse motion and never clicks during a fight.

Three problems make that harder than it looks, and each one is solved by
measurement rather than a guess:

1. **The mouse direction is unknown.** Which physical direction satisfies a
   given chevron depends on the yaw convention, the inverted-axis setting and
   the player's heading. The controller learns it from the first swing and keeps
   it for the session.
2. **The sensitivity is unknown.** `counts_per_pct` (mouse counts per percent of
   the tension bar) is a function of DPI and in-game sensitivity. The first move
   of a session is made blind, so it starts *small* and grows the budget when the
   bar does not respond; it then refines the value online from every measurable
   move. Tested end to end from 0.4 to 12 counts/percent: no snaps, no failed
   fights.
3. **Snapping must be impossible, not unlikely.** The controller knows how many
   counts it just sent and how many counts buy a percent, so it predicts the
   bar's value at the next sample and refuses to command a move that would land
   above a ceiling (90 %). Above a guard (94 %) all it does is get the bar down.
   The bar is unbounded only in the wrong direction, so crossing zero is always
   safe.

Fight simulation results (`python -m tests.test_fight`): **100 % wins, 0 snaps**
across all four depth bands, including inverted mouse, a wrong starting
direction, and a wild sensitivity guess.

## What it refuses to do

The tool only acts on evidence the resource itself publishes:

* **It does not cast unless the game's prompt is green.** `StartFishing` runs on
  `E` only when the water probe succeeded and nothing blocks it — in a vehicle,
  near the job ped, or water deeper than your rod allows. In all of those cases
  the prompt is drawn slate grey with the reason beside it, and `E` would be
  spent for nothing. The bot reads the prompt and waits; after twelve seconds it
  tells you what it is waiting for.
* **It does not press `E` twice.** E cancels a cast that is already waiting for a
  bite, and E during a reel snaps the line, so the state machine only strikes
  when the bite HUD is on screen and never touches the keyboard during a fight.
* **It does not click a catch card twice**, even though a capture is a snapshot
  and the card is still visible in the frame after the click.
* **It does not guess at a full bag.** A red toast stops it and calls you.

## When it stops

* **Red toast on screen** (what the resource shows when the inventory refuses a
  fish): pause + beep. It does not guess, does not try to sell for you, does not
  switch to RELEASE behind your back. Clear the bag, press `F9`.
* **A fight that will not end** (75 s): stop, so it cannot sit there reeling
  forever.
* **Black capture**: it says so and explains what to change, rather than looping
  silently.

## Layout

```
tools/fishbot/
  fishbot/
    geometry.py     every HUD box, derived from the window size
    vision.py       frame -> numbers (bars, ring, chevrons, modal, toasts)
    gamemodel.py    a line-for-line simulation of the resource's reeling loop
    controller.py   tension bar -> mouse counts (learning, prediction, guard)
    bot.py          the state machine: cast, bite, strike, reel, keep
    winapi.py       window finding, screen capture, SendInput, hotkeys (ctypes)
    settings.py     the remembered calibration (~/.fishbot/settings.json)
    report.py       console output + the dependency-free PNG writer
    run.py          the program you run
    simhud.py       renders synthetic HUD frames - tests only
  tests/
    test_vision.py  every reader against ground truth, 8 resolutions x 4 worlds
    test_fight.py   the controller against the simulated mini-game
    test_e2e.py     the whole bot against a fake game, through the real vision
    test_cli.py     settings, reporter, snapshot writer, and the program itself
    test_capture.py the capture path over a fake user32/gdi32 (handles, RGB order)
    fakegame.py     that fake game (renders frames, reacts to injected input)
    tune.py         sweep helper for controller parameters
```

Run the suites from `tools/fishbot`:

```
python -m tests.test_vision
python -m tests.test_fight
python -m tests.test_e2e
python -m tests.test_cli
python -m tests.test_capture
```

`tests.test_e2e` is the honest one: the bot is given nothing but a rendered frame
and a mouse, and it has to land fish against a fake client that behaves like the
Lua — including a camera sign the bot does not know.

## Notes and limits

* **Exclusive fullscreen** cannot be captured by a desktop tool (the picture
  never reaches a surface Windows will hand over). Use borderless; the tool
  detects the black frame and tells you.
* **Resolution changes** are handled: the window rect is re-read every sample and
  the HUD boxes are re-derived from it, so resizing, moving monitors or switching
  between windowed and borderless needs no restart.
* **Anticheat**: `SendInput` is what a real mouse does, so this is invisible to
  anything that only inspects input. It is still automation, and whether that is
  allowed is a question for your server's rules, not for this README.
* The tool assumes the resource's default key bindings (`E` to cast and strike)
  and the stock HUD; if those are rebound, `key` names live in `winapi.VK_CODES`.
