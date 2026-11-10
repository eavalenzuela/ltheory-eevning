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

## Looking at the game

`bin/launch APP --do "COMMANDS" --out DIR` drives an app with scripted input and saves screenshots; see `docs/harness.md`.
