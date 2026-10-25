# Luau scripting

Luau (typed Lua, `ext/luau`, pinned to 0.742) is replacing LTSL as the game's scripting language. Both run side by side during the migration. A Luau app or module can call LTSL code, and LTSL can create Luau widgets.

## Running

- An app is `resource/script/App/<name>.luau`, run with `bin/launch <name>`.
  - It returns a table. `Initialize` runs once and `Update` every frame, each called as a method.
  - If both an `.luau` and an `.lts` file exist for a name, the `.luau` one runs.
  - A script error prints a traceback and ends the app.
- Modules load with `require("@lt/Path/Name")`, which resolves to `resource/script/Path/Name.luau`. The result is cached.

`App/luau_gameplay.luau` is the Luau port of `test_gameplay`; it is the reference example.

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
bin/luaucheck resource/script/App/luau_gameplay.luau
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

## Calling LTSL during the migration

| Call | Effect |
| --- | --- |
| `ltsl("Widget/Components:AlignCenter")` | An LTSL function as a callable. Its arguments are checked against the LTSL parameter types at runtime. |
| `ltsl_new("Widget/Messages:MessageAddWidget")` | An LTSL type instance, with fields zeroed; LTSL default values are not applied. |

Both are untyped for the checker. Port the LTSL helpers a module depends on to remove them.

## Widgets

`Widget_Luau(widget, object)` makes a Luau object a component of `widget`, the counterpart of LTSL's `Custom Widget`.
- Its methods receive the widget's events, each with the widget as the first argument: `PreUpdate`, `PostUpdate`, `PreDraw`, `PostDraw`, `PrePosition`, `PostPosition`, `Create`, `Destroy`, `CaptureFocus`, `CreateChildren` (returns `{ Widget }`), `Receive(widget, message)`, `GetName`, `GetHash`.
- Messages sent with `widget:SendUp(...)` can be plain Luau tables.

LTSL creates a Luau widget with `Luau_CreateWidget "@lt/Path" arg`, which calls the module's `Create(arg)`.

`Widget/HUD/Station.luau` is the example: the station panel, created by the LTSL HUD.

## Known gaps

- **Engine call overhead:** an engine call costs about 0.19 µs, versus 0.06 µs in LTSL. This comes from method lookup and overload resolution on every call. Pure script code is about 10x faster than LTSL.
  - Planned fixes: userdata tags instead of metatable checks, the `__namecall` fast path, and caching resolved overloads.
- **Vector precision:** `vector` is single precision, so positions lose precision far from the origin (about 3 cm at 300 km).
- **Untyped LTSL boundary:** `ltsl()` / `ltsl_new()` values are untyped.
- **No sandboxing:** scripts are not sandboxed (not needed; they are part of the game).
