# Screenshot and input harness

`bin/launch` can run an app under a scripted harness. The harness waits, sends mouse and keyboard input, saves screenshots, and quits, so an app can be checked by looking at its output instead of playing it. Claude uses it to check UI and rendering changes. It is also handy for before/after comparisons.

```sh
bin/launch ltheory --out shots --scale 2 \
  --do "wait 10; shot start; move 1484 484; mousedown Right; wait 1; shot radial; mouseup Right; quit"
```

Each screenshot is written as `<out>/<name>.png`, and the launcher prints `SCREENSHOT <path>` for each one. Screenshots are taken after the frame has finished drawing and before it is shown, so they never catch a half-drawn frame.

## Options

| Option | Meaning |
| --- | --- |
| `--do COMMANDS` | Harness commands, separated by `;` |
| `--script FILE` | Harness commands from a file, one per line; `#` starts a comment |
| `--out DIR` | Screenshot directory (default `cache/screenshot/`, where F1 also saves) |
| `--scale N` | Shrink screenshots by an integer factor (2 gives 960x540 from 1080p) |
| `--size WxH` | Window size (default 1920x1080) |
| `--timeout S` | Quit a harness run after S seconds (default 300) |

## Commands

| Command | Effect |
| --- | --- |
| `wait S` | Wait S seconds of real time |
| `frames N` | Wait N frames |
| `shot NAME` | Save `NAME.png` at the end of this frame |
| `move X Y` | Put the cursor at window pixel (X, Y) |
| `click [BUTTON] [X Y]` | Press and release a mouse button (Left, Right, Middle, X1, X2; default Left); takes two frames |
| `mousedown [BUTTON]` / `mouseup [BUTTON]` | Hold or release a button, e.g. to drag or to use radial menus |
| `scroll D` | Scroll the wheel D notches |
| `key NAME` | Press and release a key; takes two frames |
| `keydown NAME` / `keyup NAME` | Hold or release a key |
| `type TEXT` | Enter TEXT as typed characters |
| `find NAME` | Move the cursor onto the visible widget named NAME (exact match first, then substring, ignoring case), choosing the one nearest the cursor; waits up to 10 s for it to appear. World markers are named after their object, radial options by action (`Dock`, `Mine`) |
| `widgets [TEXT]` | Print the visible named widgets (containing TEXT) with their centres |
| `echo TEXT` | Print `HARNESS TEXT` |
| `quit` | Exit after the current frame (and its screenshots) |

Key names are the engine's `Key_*` names without the prefix, matched without regard to case: `A`–`Z`, `N0`–`N9` (digit row), `NP0`–`NP9`, `F1`–`F15`, `Space`, `Return`, `Escape`, `Tab`, `BackSpace`, `LShift`, `LControl`, `LAlt`, `Up`, `Down`, `Left`, `Right`, and so on (see `KEY_X` in `src/liblt/LTE/Common.h`).

## Behaviour

- **Real input:** while the harness runs, real mouse and keyboard input to the window is ignored, so using the desktop does not disturb the run. If the commands end without `quit`, the harness prints `HARNESS done, real input restored` and hands control back.
- **Cursor:** the harness moves the app's cursor, not the OS pointer. Screenshots therefore mark the app's cursor with a small magenta crosshair.
- **Errors:** a bad command prints `HARNESS ERROR: ...` and the run continues.

## From scripts

LTSL code can request a screenshot at a meaningful moment with `Screenshot "name"`, for example right after a test script docks. It uses the same directory and timing as `shot`.

## Notes

- **Coordinates** are window pixels at the window size. They don't change with `--scale`, so a point at (x, y) in a `--scale 2` image is `move 2x 2y`.
- **Repeatability:** `ltheory` starts in the same place every run (fixed seeds), so screen positions taken from one run's screenshot hold in the next if the timing is similar.
- **GPU:** on hybrid-GPU laptops, `DRI_PRIME=1` runs the game on the discrete GPU.
