# Developer tools

Everything here runs from the repository root after `python3 configure.py build`.

## Is the tree healthy?

| Command | What it does |
|---|---|
| `script/check` | Type check, engine-free specs, and the launcher's exit codes, each paired with a planted failure that must be caught. Exits 0 only if every step did what it should. |
| `script/check --fast` | The same without the steps that open a window. |
| `script/check --soak` | Adds the determinism soak: eight seeds of the 400-system sim, each run in memory and again with a save and load every 97 ticks. About two minutes. |

`bin/launch APP` exits 0 only when the app started, no script raised an error and every harness command worked. A crash or failed assertion exits with 128 + the signal number.

## Engine-free code

`bin/ltcore MODULE [ARG ...]` runs a Luau module with no window, no GL and no engine. Only the built-ins and `Host` (files, directories, clock, arguments, exit) exist there. Code under `resource/script/Core`, `Sim` and `Tool` must run in it; the type checker enforces that. The rules for such code are in `docs/design/core.md`.

| Command | What it does |
|---|---|
| `bin/ltcore Tool/specs [FILTER]` | Runs every `*.spec.luau` under `Core`, `Sim` and `Tool`. |
| `bin/ltcore Tool/simrun [--galaxy N] [--history N] [--systems N] [--ticks N]` | Runs the universe sim and prints the final state hash and the time per tick. `--reload-every N` saves and loads the state every N ticks; the hash must not change. `--out DIR` records time series and judges the run against thresholds. |
| `bin/ltcore Tool/simdiverge [--galaxy N] [--history N]` | Finds the first tick and the first fields where a reloaded run differs from one kept in memory. |

## Judging the simulation

| Command | What it does |
|---|---|
| `script/simsweep [--seeds N] [--ticks N]` | Runs seeds in parallel into `cache/sim/sweep-<time>/` and prints a scorecard: one row per check, one column per seed. Exits 1 if any check failed. |
| `script/simsweep --rescore DIR` | Prints the scorecard of an earlier sweep. |
| `script/simreport DIR` | Writes `DIR/report.html`: the scorecard, and for each seed the time series behind it. Add `#dark` or `#light` to the address to force a theme. |

The current prototype fails the sweep on every seed (credits and fleets trend to zero, station maintenance about 45% met). That is the known result the economy redesign in `docs/roadmap.md` §6 exists to fix; the sweep is how the new economy will be judged.

## The game

`bin/launch game` runs the game: the Core shown by the engine (`resource/script/App/game.luau`, `resource/script/Game/`). Left-drag turns the camera and the wheel zooms; click a bracket or an overview row to select, then use the orders on the selected-item panel. P pauses, F9 saves to `save/quick/`, F10 loads it.

`GameDebug` is a global table for the console and for scripted runs: `Order(kind, what, range)`, `Select(what)`, `Docked()`, `InSpace()`, `InWarp()`, `Idle()`, `System()`, `Distance(what)`, `TargetGap()`, `Doing()`, `TimeScale(n)`, `Zoom(radii, yaw, pitch)`, `Save(slot)`, `Load(slot)`, `Hash()`, `Mark(name)` and `Same(a, b)`, `Jumps(n)` and `JumpsLeft()`, `Memory()`, `Vram()`. `what` is a kind (`"belt"`, `"station"`, `"gate"`, `"asteroid"`, `"planet"`) or part of a name, and means the nearest match.

```sh
bin/launch game --console                    # then type: GameDebug.Order("Undock")
bin/launch game --no-present --fixed-step 60 --script test/scenario/flight.txt
```

`test/scenario/flight.txt` is the M1 flight loop as a harness script; `script/check` runs it.

## Looking at the game

| Command | What it does |
|---|---|
| `bin/launch APP --console` | A Luau prompt in the terminal that started the app: type a line, it runs in the app's VM. The harness command `lua CODE` does the same from a script. |
| `script/goldens [NAME ...]` | Runs the golden-screenshot scenarios and compares each with its stored image. |
| `script/goldens --update [NAME ...]` | Stores this run's screenshots as the golden images. |

`bin/launch APP --do "COMMANDS" --out DIR` drives an app with scripted input and saves screenshots; see `docs/harness.md`.
