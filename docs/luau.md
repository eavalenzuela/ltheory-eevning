# Luau scripting

Luau (typed Lua, `ext/luau`, pinned to 0.742) is the game's scripting language. Every script in `resource/script` is Luau; the last LTSL scripts were ported or retired in 2026-10. The engine still contains the LTSL compiler, and loads an `.lts` app or engine hook when no `.luau` one exists (see [LTSL interop](#ltsl-interop)).

## Running

- An app is `resource/script/App/<name>.luau`, run with `bin/launch <name>`.
  - It returns a table. `Initialize` runs once and `Update` every frame, each called as a method.
  - An app without `Update` ends after `Initialize`, for run-once tools such as `prime` and `font`.
  - A script error prints a traceback and ends the app.
- Modules load with `require("@lt/Path/Name")`, which resolves to `resource/script/Path/Name.luau`. The result is cached.

`App/test_gameplay.luau` (mine, dock, trade, refit, with no input needed) is the reference example.

### Shared modules for apps

| Module | Use |
| --- | --- |
| `AppShell` | `return AppShell.Create(function() return rootWidget end)` makes an app around one root widget: Ctrl+Tab toggles the developer panel, T recompiles shaders. Most demos use it. |
| `SceneView` | The space demos' game view (camera, SMAA, dither, UI composited in), plus the shared time step (H for 20x) and P to pause. |
| `Widget/Desktop` | A full-screen root over a random screenshot that opens windows and context menus sent up to it. |
| `Widget/DevPanel` | The developer panel (`DevPanel.Toggle(ui, shown)`). |
| `Texture/Filters` | GPU image filters (blur, levels, color grade, ...). |
| `Int` | 32-bit wraparound helpers for reproducing LTSL's numbers (see below). |

`File_Read(path)` and `File_Write(path, contents)` read and write text files relative to the working directory; `App/life.luau` saves and loads with them.

## The engine API

Every engine function registered through the reflection system is available with no hand-written bindings. That covers `FreeFunction`, `DefineFunction` and member functions, about 740 in all.

| In C++ | In Luau |
| --- | --- |
| `Object_Universe(39, 0)` and other `Type_Name` functions | Globals with the same name |
| Aliased methods (`GetPos`, `Plug`, ...) | Methods: `ship:GetPos()`, `ship:Plug(item)` |
| Reflected fields | Fields: `data.bids`, `order.price`, `widget.pos`; also through references and pointers |
| Operator functions (`+`, `-`, `*`, `/`, `<`, `<=`, `==`) | Operators on engine values |
| `bool`, numbers, `String` | `boolean`, `number`, `string` |
| `V3` / `V3D` | Luau `vector` (`vector.create(x, y, z)`) |
| A null `Object`, `Item`, `Widget`, ... | `nil` |
| `Data` (the engine's "any") | Whatever it holds; Luau tables pass through and come back as the same table |
| Other engine values | Userdata holding a copy, e.g. `Vec2`, `MarketData`, iterators |

**Rules that catch mistakes at runtime:**
- **Integers:** an engine integer parameter accepts only a whole number in range. `Item_ShipType(20000, 55.5, ...)` fails with the parameter name and signature instead of truncating.
- **Large 64-bit results:** an engine integer beyond 2^53 raises an error instead of rounding.
- **Missing members:** calling a method or reading a field that doesn't exist is an error with file and line.

**Creating engine values:**
- `New.<Class>()` creates a default-constructed engine value: `New.Vec2()`, `New.MessageTargetPosition()`, `New.Vector_Reference_RenderPassT()`.
- `lt.typeof(x)` gives an engine value's type name.

## Type checking: `bin/luaucheck`

```sh
bin/luaucheck                     # every .luau under resource/script
bin/luaucheck resource/script/App/test_gameplay.luau
```

It does three things:
1. Generates type definitions for the whole engine API from the same reflection data the bindings use, so they cannot drift. It writes them to `resource/script/engine.d.luau`, which is generated and git-ignored.
2. Checks the scripts in strict mode, resolving `@lt/` requires as the runtime does.
3. Exits non-zero on any error.

It catches misspelled methods, wrong argument types, wrong argument counts and unknown globals before the game runs. Run it before committing script changes.

**Notes on the definitions:**
- **Integer parameters** are typed `int`, an alias of `number`. Whether a value is whole is checked at runtime.
- **Reference parameters** are optional (`Object?`). Engine results are declared non-optional because most getters never return null. A call on a nil result still fails loudly at runtime, so check with `if x then` where null is a real possibility.
- **Overloads** are listed as separate signatures.

**Editors:** `.luaurc` sets strict mode and the `@lt` alias. For luau-lsp, add `resource/script/engine.d.luau` as a definitions file. Also raise its `LuauTarjanChildLimit` FInt (`luaucheck` uses 1000000), because the engine API is larger than the analyzer's default budget.

## LTSL interop

No LTSL scripts ship, but the bridges remain for loading old `.lts` code (for example from the original repository):

| Call | Effect |
| --- | --- |
| `ltsl("Path:Function")` | An LTSL function as a callable. Its arguments are checked against the LTSL parameter types at runtime. |
| `ltsl_new("Path:Type")` | An LTSL type instance, with fields zeroed; LTSL default values are not applied. |
| `Luau_CreateWidget "@lt/Path" arg` (in LTSL) | Calls the Luau module's `Create(arg)` and returns the widget. |

The Luau-side values are untyped for the checker.

## Widgets

`Widget_Luau(widget, object)` makes a Luau object a component of `widget`, the counterpart of LTSL's `Custom Widget`.
- Its methods receive the widget's events, each with the widget as the first argument: `PreUpdate`, `PostUpdate`, `PreDraw`, `PostDraw`, `PrePosition`, `PostPosition`, `Create`, `Destroy`, `CaptureFocus`, `CreateChildren` (returns `{ Widget }`), `Receive(widget, message)`, `GetName`, `GetHash`.
- Messages sent with `widget:SendUp(...)` can be plain Luau tables.

Give a widget a `GetName` that returns its label so the screenshot harness can `find` it (buttons, toggles and windows do).

## Object scripts

`object:AddScript(script)` attaches a Luau table to an object.
- `script:Update(object)` runs every frame; returning `false` removes the script.
- `script:Receive(object, message)` gets the object's messages.

`Widget/Handling.luau` uses this for the ship's flight controls and chase camera.

## Scripts the engine calls

The engine calls a few script functions by path. Examples: `Icons:Person`, `Item/ShipType/Generate:Main` (hull generation), `Object/WarpNode:Init` and `Object/System:Init`.
- These calls go through `Script_Call<R>("Path:Function", args...)` (`src/liblt/Luau/ScriptCall.h`).
- It calls the module's function if `Path.luau` exists, and otherwise the LTSL function in `Path.lts`. The choice is cached per path.
- All of these hooks now have Luau versions. To move another one, write the `.luau` module; the C++ call site doesn't change.

Engine values that take a script object also take a Luau table:
- `Object_Custom(table)` attaches the table as an object script.
- `Warp_Custom(table)` makes a warp from `table:GetDelta(point)`, which returns a vector.

**Reproducing LTSL's numbers:** generators such as the hull and system scripts must give the same result for the same seed. LTSL wraps ints silently (overflow, and int to uint conversion), but the Luau binder rejects out-of-range values. `Int.luau` has three helpers for these ports:
- `Int.Signed` and `Int.Unsigned` wrap a value like the C++ conversion.
- `Int.Float32` rounds like LTSL's single-precision `Float`, for arithmetic that is truncated to an integer afterwards.
- Keep the random draws in the LTSL order, including draws whose results are unused.

## Messages

`Widget/Messages.luau` defines the message tables (`Messages.AddWidget(w)`, `Messages.Refresh()`, ...).
- `Messages.Is(message, "AddWidget")` tests a message's type. It also matches the LTSL `MessageAddWidget` type, for LTSL senders.
- Query messages (`Messages.GetLabel`, `Messages.GetObject`) are answered by setting a field on the message.

## Known gaps

- **Engine call cost:** method calls cost about 0.05 µs, on par with LTSL; operators on engine values cost about 0.13 µs, because each allocates its result. Pure script code is about 10x faster than LTSL. `bin/launch luau_bench` measures each kind of call.
- **Vector precision:** `vector` is single precision, so positions lose precision far from the origin (about 3 cm at 300 km).
- **No script threads:** Luau runs on the main thread only. The binder's caches and the VM are not thread-safe, so the engine's `Thread_Create` works only for LTSL functions. (`App/threads.lts`, the LTSL thread demo, was retired for this reason.)
- **No sandboxing:** scripts are not sandboxed (not needed; they are part of the game).
