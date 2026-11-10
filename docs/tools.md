# Developer tools

Everything here runs from the repository root after `python3 configure.py build`.

## Is the tree healthy?

| Command | What it does |
|---|---|
| `script/check` | Type check, engine-free specs, and the launcher's exit codes, each paired with a planted failure that must be caught. Exits 0 only if every step did what it should. |
| `script/check --fast` | The same without the steps that open a window. |
| `script/check --soak` | Adds the soaks: eight seeds of the 400-system strategic sim, each run in memory and again with a save and load every 97 ticks, for four and a half game days; the economy sweep (16 seeds); the faction sweep (32 seeds). About 25 minutes. |

`bin/launch APP` exits 0 only when the app started, no script raised an error and every harness command worked. A crash or failed assertion exits with 128 + the signal number.

## Engine-free code

`bin/ltcore MODULE [ARG ...]` runs a Luau module with no window, no GL and no engine. Only the built-ins and `Host` (files, directories, clock, arguments, exit) exist there. Code under `resource/script/Core` and `Tool` must run in it; the type checker enforces that. The rules for such code are in `docs/design/core.md`.

| Command | What it does |
|---|---|
| `bin/ltcore Tool/specs [FILTER]` | Runs every `*.spec.luau` under `Core` and `Tool`. |
| `bin/ltcore Tool/econrun [--galaxy N] [--days N] [--out DIR] [--detail 1]` | Runs the galaxy's economy (400 systems, 30 game days by default) and prints a verdict on each of `Tool/EconProbe`'s measures. `--detail 1` adds every class's price level, every step's use and how people fare by security. `--goods 1` and `--atlas 1` print the goods table and who has what. Options such as `--haul`, `--jump`, `--slack`, `--source` override the atlas's settings for one run. |
| `script/econsweep [--seeds N] [--days N]` | `econrun` on 16 seeds at once, with a scorecard of every measure by seed. The exit test of roadmap stage S2; part of `script/check --soak`. |
| `bin/ltcore Tool/factionrun [--galaxy N] [--history N] [--days N] [--out DIR]` | Runs the strategic simulation (the powers, their wars and the pirates on the galaxy's economy; 400 systems, 30 game days by default) and prints a verdict on each of `Tool/FactionProbe`'s measures. `--news 1` prints wars, peaces and the like as they happen (`--news 2`: sieges, claims and raids too); `--every H` prints a line on the galaxy every H hours; `--detail 1` adds a table of the powers, their relations, where every credit came from and went, and the counters. `--out DIR` writes the hourly series, the news and the verdicts. |
| `script/factionsweep [--seeds N] [--days N]` | `factionrun` on 32 seeds at once, with a scorecard. The exit test of roadmap stage S3; part of `script/check --soak`. |
| `script/sweep TOOL NAME ...` | What the two sweeps are made of: runs a tool over seeds in parallel into `cache/NAME/sweep-<time>/` and prints one row per check, one column per seed. `--rescore DIR` prints the scorecard of an earlier sweep. Exits 1 if any check failed. |
| `bin/ltcore Tool/simdiverge [--galaxy N] [--history N] [--ticks N]` | Runs the strategic simulation twice, once with a save and load every 97 ticks, and finds the first tick and the first fields where the two differ. |

To change how the powers behave, edit `resource/script/Core/Data/Powers.luau` (every number of the faction layer, each with what it does), run `factionrun --detail 1 --news 1` on a seed or two to see the effect, then the sweep. A sweep measure that misses is a reason to look at a seed with `--detail`, not to move the limit.

## The game

`bin/launch game` runs the game: the Core shown by the engine (`resource/script/App/game.luau`, `resource/script/Game/`). Left-drag turns the camera and the wheel zooms; click a bracket or an overview row to select, then use the orders on the selected-item panel. P pauses, F9 saves to `save/quick/`, F10 loads it.

`GameDebug` is a global table for the console and for scripted runs: `Order(kind, what, range)`, `Select(what)`, `Docked()`, `InSpace()`, `InWarp()`, `Idle()`, `System()`, `Distance(what)`, `TargetGap()`, `Doing()`, `TimeScale(n)`, `Zoom(radii, yaw, pitch)`, `Save(slot)`, `Load(slot)`, `Hash()`, `Mark(name)` and `Same(a, b)`, `Jumps(n)` and `JumpsLeft()`, `Memory()`, `Vram()`. `what` is a kind (`"belt"`, `"station"`, `"gate"`, `"asteroid"`, `"planet"`) or part of a name, and means the nearest match.

```sh
bin/launch game --console                    # then type: GameDebug.Order("Undock")
bin/launch game --no-present --fixed-step 60 --script test/scenario/flight.txt
```

`test/scenario/flight.txt` (the M1 flight loop), `test/scenario/combat.txt` (the M2 loop: fit, fight, loot, lose the ship, get home) and `test/scenario/economy.txt` (the M3 loop: mine, refine, build, sell by order, buy a hull, train, board) are harness scripts; `script/check` runs all three, and `test/scenario/pace.txt`, which fails if the game draws under thirty frames a second just outside the home station (a picture cannot show a slow frame: time one whenever something is added to the scene).

In the game, `GameDebug.LookAt('sun')` (or any name the overview knows) swings the camera to look just past the ship at it.

`script/viewer` runs the viewer: one window that goes through a list of views of a body (in `App/viewer.luau`) and saves a picture of each to `cache/viewer/shots`. It is meant to be started once and left, minimised if wanted, so that no window is opened per picture. `script/viewer start [FILTER]` opens it and takes the views; `script/viewer again [FILTER]` reloads every shader and takes them again (a few seconds); `script/viewer sheet PREFIX` puts the pictures named `PREFIX*` side by side in `cache/viewer/sheet-PREFIX.png`; `script/viewer stop` closes it. With a FILTER only the views with that word in their names are taken (`moon`, `gas`, `star-red`, ...). While it waits it sleeps, but close it before timing the game: two programs share the graphics card. `cache/viewer/params.txt` overrides the settings of the kind of body being looked at, one a line: a name and a number (`seaLevel 0.5`), or three for a colour (`rockPale 0.6 0.5 0.4`). Shaders and settings are reloaded on every pass; a change to a script needs `stop` and `start`.

A scripted run opens a window that stays black: `--no-present` means frames are drawn and saved but never shown. To watch an app, run it without the harness flags.

A script works the station screens by pressing buttons by name, which runs the same code a click does. A button's name is its label (`UNDOCK`, `Market`, `Skills`) or, where several look alike, an id: `Fit:<type>`, `Unfit:<rack><slot>`, `ToHangar:<type>`, `Refine:<type>`, `Train:<skill>`, `Learn:<skill>`, `Board:<n>`, `Assemble:<type>`, `BuyNow`, `SellNow`, `PlaceSell`, `PlaceBuy`, `StartJob`, `Runs:most`, `Quantity:100`. The screen is a frame behind the game, so wait for the button rather than asserting it: `until GameDebug.Press('Fit:miner.small')`. `GameDebug.CanPress(name)` and `WhyNot(name)` say whether a button is live; `Enter(field, n)` types into a number field (`Quantity`, `SellPrice`, `BuyPrice`, `Runs`); `Market(type)` and `Blueprint(type)` open the market or industry tab at a row. For the economy there are also `Hangar(type)`, `Skill(id)`, `Training()`, `Jobs()`, `Orders()`, `Ships()`, `HoldFull()`, `Mine()`, `Running()` and the cheat `Grant(credits)`, which is entered in the wallet journal as a cheat. `Order(kind, 'home')` means the pilot's home station. For fights, `GameDebug` also has `Lock(what)`, `Locked()`, `Fire()`, `Count(kind)`, `Hold(type)`, `Fitted(type)`, `Condition()`, `Wallet()`, `Hull()`, `Peaceful(on)` and `SelfDestruct()`.

## Looking at the game

| Command | What it does |
|---|---|
| `bin/launch APP --console` | A Luau prompt in the terminal that started the app: type a line, it runs in the app's VM. The harness command `lua CODE` does the same from a script. |
| `script/goldens [NAME ...]` | Runs the golden-screenshot scenarios and compares each with its stored image. |
| `script/goldens --update [NAME ...]` | Stores this run's screenshots as the golden images. |

`bin/launch APP --do "COMMANDS" --out DIR` drives an app with scripted input and saves screenshots; see `docs/harness.md`.
