# The Core: conventions

The Core is the authoritative game: all state and all rules. It lives in `resource/script/Core/`, is written in strict Luau, calls nothing in the engine, and is deterministic. The engine is its view. `docs/roadmap.md` §3 gives the reasons; this document is the set of rules that code in the Core follows.

The strategic simulation (`Core/Strategic`) follows them too; the prototype it replaced is gone from the tree. `resource/script/Tool/` holds engine-free tools and the test kit; it follows the boundary rule but is not game state.

## The boundary

- Code under `Core/` and `Tool/` sees the Luau built-ins and the `Host` table, nothing else. `bin/luaucheck` checks those directories against `resource/script/host.d.luau` only, so an engine call there is a type error.
- The same code runs in the engine and in `bin/ltcore`, which links only the Luau VM. If it runs in `ltcore`, it cannot depend on a window, the GPU or the engine.
- `Host` is for the edges: reading and writing save files, tools, timing a benchmark. Rules never call it.

## How the scripts are run

Both hosts compile every module the same way, so the same code gives the same result in the engine and in `bin/ltcore`:

- **Built-in and engine globals are never replaced.** The hosts promise the VM this, and in return it resolves `math.sqrt` and the like when a module loads and calls them directly (several times faster). A script may add a global of its own (`GameDebug`), but must not assign to `math`, `string`, `table`, `print`, `require` or anything the engine binds.
- **Small local functions are inlined** (optimisation level 2). Tracebacks still give lines.
- **A module whose first lines include `--!native` is compiled to machine code.** Use it for a hot loop of arithmetic over tables (`Core/Strategic/Economy` is the one so far), not by default: it costs memory and load time. `LT_NATIVE_REPORT=1 bin/ltcore ...` says what became of each such module. Native code gives the same results as the interpreter; the specs and scenarios are the check.
- **Transient scratch is not state.** A module may keep working memory between calls to spare allocation, as the economy keeps its price rows, only if every value is written before it is read on each call.

## State

- **Plain data only.** Booleans, numbers, strings, and tables of those keyed by numbers or strings. No functions, metatables, engine values, vectors or buffers in state.
- **No table is reachable twice.** Things refer to each other by id. `Core/Persist/Codec` refuses a state that breaks either rule and names the path.
- **Ids** are integers from one counter stored in the state. An id is never reused. Content types (a hull, a module, a good) are identified by stable strings, so data can be reordered without breaking saves.
- **Units are SI:** metres, seconds, kilograms, cubic metres. Positions are three doubles in system space with the star at the origin. Do not store a position in a Luau `vector`: it is single precision.
- **Money and quantities are integers.** Time is an integer tick count; durations in data are in seconds and converted once.

## Determinism

The state after a tick is a function of the state before it and the commands applied. Nothing else may leak in.

- **Never let the order of a map decide anything.** The order `for k, v in map` yields its keys depends on how the map was filled, and it changes when a state is saved and loaded. Loop over an array, or over an id list kept in order (`State.EachFleet` is the pattern). Summing or independent per-entry updates are the only safe uses of map order, and they are easy to get wrong, so prefer not to rely on that.
- **Never use a table, function or userdata as a key** in state or in anything that influences state: they hash by address.
- **No `math.random`, no `os.*`, no `Host.Clock` or `Host.Time` in rules.** Randomness comes from `Rng.For(historySeed, tick, entityId, purpose)`: a stream derived from what is being rolled, so one roll never depends on how many rolls came before it.
- **`table.sort` is not stable.** A comparator must be a total order; break ties by id.
- **Transcendental functions** (`exp`, `pow`, `sin`) are deterministic for one build on one machine, which is what this project needs. Do not expect two different machines to agree bit for bit.

Two tools enforce this:
- `script/check --soak` runs the galaxy (`Tool/GalaxyStep`: economy, pirates' pressure, wars) in memory and again with a save and load every 97 ticks; the hashes must match after every load.
- `bin/ltcore Tool/galaxydiverge` is that run, and finds the first tick and the first fields where they do not.

## Commands in, events out

- The view, the UI and NPC AI change the game only by submitting **commands**: plain tables `{ kind, actor, ... }` such as `Approach`, `Orbit`, `WarpTo`, `LockTarget`, `ActivateModule`, `MoveItems`, `PlaceOrder`. Commands are queued, stamped with the tick they apply on, and written to the journal.
- `Validate(command)` answers "ok" or a reason without changing anything. The UI uses it to grey out actions.
- The Core reports what happened as **events** (`BallAdded`, `WarpStarted`, `Shot`, `BallDestroyed`, `OrderFilled`, `News`). Events are transient and never saved. They drive one-shot effects and sounds only: the view must be able to rebuild everything on screen from a state snapshot alone.

## Time

- The tactical tick is one second, held in one named constant. The strategic tick is every tenth tactical tick.
- A tick runs whole. Work is never sliced by wall-clock time, because that would make the order of operations depend on frame timing.
- Pause and time acceleration scale how fast ticks are taken; they never change what a tick does.

## Saving

- A save is the encoded state plus a small header: `saveVersion` (the shape of the state), `dataVersion` (content tables), `genVersion` (generators).
- System descriptions (the layout data of each solar system) are stored in the save. Only visuals are regenerated from seeds, so changing a generator cannot break a save.
- A change to the shape of the state comes with a migration: a pure function from the old decoded table to the new one, tested against a stored save.
- The state hash is the hash of the encoded bytes. Two states are equal exactly when their hashes are.

## Tests

- A spec is a file named `Something.spec.luau` beside the code it tests, returning a `Test.Suite` (`Tool/Test.luau`).
- `bin/ltcore Tool/specs` runs them all in well under a minute; `script/check` runs them with the type check and the planted-failure checks.
- New rule code arrives with a spec. Anything with a formula (align time, hit chance, price curve) is checked against hand-computed numbers.
