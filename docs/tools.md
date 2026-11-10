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
| `bin/ltcore Tool/econrun [--galaxy N] [--days N] [--out DIR] [--detail 1]` | Runs the galaxy's economy (400 systems, 30 game days by default) and prints a verdict on each of `Tool/EconProbe`'s measures. `--detail 1` adds every class's price level, every step's use and how people fare by security. `--goods 1` and `--atlas 1` print the goods table and who has what. Options such as `--haul`, `--jump`, `--slack`, `--source` override the atlas's settings for one run. |
| `script/econsweep [--seeds N] [--days N]` | `econrun` on 16 seeds at once, with a scorecard of every measure by seed. The exit test of roadmap stage S2; part of `script/check --soak`. |
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

`test/scenario/flight.txt` (the M1 flight loop), `test/scenario/combat.txt` (the M2 loop: fit, fight, loot, lose the ship, get home) and `test/scenario/economy.txt` (the M3 loop: mine, refine, build, sell by order, buy a hull, train, board) are harness scripts; `script/check` runs all three.

A script works the station screens by pressing buttons by name, which runs the same code a click does. A button's name is its label (`UNDOCK`, `Market`, `Skills`) or, where several look alike, an id: `Fit:<type>`, `Unfit:<rack><slot>`, `ToHangar:<type>`, `Refine:<type>`, `Train:<skill>`, `Learn:<skill>`, `Board:<n>`, `Assemble:<type>`, `BuyNow`, `SellNow`, `PlaceSell`, `PlaceBuy`, `StartJob`, `Runs:most`, `Quantity:100`. The screen is a frame behind the game, so wait for the button rather than asserting it: `until GameDebug.Press('Fit:miner.small')`. `GameDebug.CanPress(name)` and `WhyNot(name)` say whether a button is live; `Enter(field, n)` types into a number field (`Quantity`, `SellPrice`, `BuyPrice`, `Runs`); `Market(type)` and `Blueprint(type)` open the market or industry tab at a row. For the economy there are also `Hangar(type)`, `Skill(id)`, `Training()`, `Jobs()`, `Orders()`, `Ships()`, `HoldFull()`, `Mine()`, `Running()` and the cheat `Grant(credits)`, which is entered in the wallet journal as a cheat. `Order(kind, 'home')` means the pilot's home station. For fights, `GameDebug` also has `Lock(what)`, `Locked()`, `Fire()`, `Count(kind)`, `Hold(type)`, `Fitted(type)`, `Condition()`, `Wallet()`, `Hull()`, `Peaceful(on)` and `SelfDestruct()`.

## Looking at the game

| Command | What it does |
|---|---|
| `bin/launch APP --console` | A Luau prompt in the terminal that started the app: type a line, it runs in the app's VM. The harness command `lua CODE` does the same from a script. |
| `script/goldens [NAME ...]` | Runs the golden-screenshot scenarios and compares each with its stored image. |
| `script/goldens --update [NAME ...]` | Stores this run's screenshots as the golden images. |

`bin/launch APP --do "COMMANDS" --out DIR` drives an app with scripted input and saves screenshots; see `docs/harness.md`.
