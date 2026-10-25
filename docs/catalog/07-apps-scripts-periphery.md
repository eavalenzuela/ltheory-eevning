# 07 — Apps, gameplay scripts, launcher, legacy code, build and assets

Scope: `resource/script/App/` (27 apps + `App/Life/`), `resource/script/{Object,Item,Task,Texture,Common}/`, `src/launch/`, `src/old/`, the build files and third-party code, and `resource/{font,music,sound,texture,gamedata}`.
Method: I read every app and gameplay script in full, plus the C++ call sites that load them. I did not build or run anything. Where a claim depends on runtime behaviour I couldn't check, it is marked **(unverified)**.

---

## 1. Overview

- **One executable, many scripts.** `bin/launch <app>` compiles `resource/script/App/<app>.lts`, calls `Main`, then calls `Initialize` once and `Update` every frame on whatever script type `Main` returned (§4).
- **The apps fall into two styles:**
  - **"Direct" apps** (`war`, `dogfight`, `rails`, `market`, `map`, plus the one-shot apps `font`, `prime`, `sandbox`, `threads`). `Main` returns a type that has its own `Initialize`/`Update`. These apps manage `Interface`s and render passes themselves.
  - **"Widget" apps** (everything else). `function Data Main () widget:Create <widget tree>` returns the `App` type from `App/widget.lts`. LTSL *infers* a function's return type from its body (`Expression/Function.cpp:72`: `fn->returnType = fn->expression->GetType()`), so the declared `Data` is ignored. `widget.lts`'s `Initialize` adds the tree to a `UI` interface. Its `Update` runs `ui.Update`/`ui.Draw`, toggles the dev panel on **Ctrl+Tab** and recompiles shaders on **T**. The app logic lives in a `Custom Widget App` with the callbacks `Create`, `CreateChildren`, `PreUpdate`, `PostUpdate`, `PreDraw`, `PostDraw` and `Receive` (the UI catalog covers these).
- **How the apps split by kind:**
  - **5 are game-like 3D sandboxes** you can fly in: `ltheory`, `war`, `dogfight`, `handling`, `rails`.
  - **3 are 3D spectator/viewer apps:** `observatory`, `model`, `map` (the last is 2D but simulates a system).
  - **5 are game-UI screen tests:** `hud`, `market`, `objectinfo`, `ui`, `platemesh`.
  - **6 are abstract experiments with no game objects:** `brain`, `hnn`, `life`, `universe`, `loading`, `draw`.
  - **8 are tools, placeholders or one-shot tests:** `image`, `strukt`, `launcher`, `colony`, `font`, `prime`, `sandbox`, `threads`.
- **None of them is a game.** No app has win/lose conditions, saving, missions, player docking or progression. `ltheory.lts` comes closest: a procedural universe, a flyable ship, HUD, targeting, markets reachable through a context menu, and warp rails.
- **LTSL comment gotcha (important when reading apps):** `#` as the first token comments out **that line and its whole indented block** (`Expression.cpp:68`: a list whose head is `#` compiles to nothing). So `# desc "Miners"` in `observatory.lts` disables the entire miners block. The same applies to the second `CreateLine` in `hnn.lts`, the prompt in `ui.lts`, the F4 settings toggle in `widget.lts` and the decal block in `Item/ShipType/Generate.lts`.

---

## 2. App catalog

### 2.1 Summary table

Controls listed are app-specific. Every 3D app that creates `Widget/HUD:Create player` also gets the **flight/HUD controls** in §2.2. The launcher keys (F1 screenshot, F2 profiler, F5 reload, Ctrl+W quit, `~` debugprint) work everywhere. **F6** re-randomizes system colours in any app that renders a `System` (`Game/Object/System.cpp:186`).

"Smoke" = result of this session's Linux smoke test: *runs* = keeps running; *one-shot* = prints/writes and exits by design.

| App | Purpose | Systems exercised | App-specific controls | EVE-like pieces shown | Gameplay vs demo | Smoke |
|---|---|---|---|---|---|---|
| **ltheory** | Main game prototype: fly a ship in a procedural universe | `Object_Universe` (seed 39) → regions → systems built by `Object/System:Init`; ShipType/WeaponType gen; `Player_Human`; HUD; render passes (Clear, Camera, SMAA, dither); FMOD looped ambience | Y = enter warp rail of last-targeted object, U = leave it; H (hold) = 20× time | Flight, combat (weapons fitted), warp rails, stations with markets ("Trade" context menu), colonies on planets, asteroid belt/zones, AI pilots, pirates vs patrols | **Closest to gameplay**, but no goals | runs (fixed earlier: undefined `ui` pass removed) |
| **war** | AI skirmish: 32 AI ships of 4 hull sizes, each told to destroy an earlier ship | `Object_System`, `Task_Destroy`, weapons, HUD in `RenderPass_Interface` | P pause, H 20× time, T recompile shaders | Combat / fleet battle | Combat test bed | runs |
| **dogfight** | 10 enemies all hunt the player; big planet backdrop | Same as war + `Item_PlanetType`, `Task_Destroy ship` | H 20× time, T recompile | PvE combat, flight | Closest to a "combat mission" | runs |
| **handling** | Flight-model test, plus a fake player empire for the info UI | System with named ore resource, `Item_TransferUnitType` fitted, 16 player-owned ships/stations with `Task_Goto`, cargo, `player.AddLog`, `Grammar_Get` names | P pause, H 20× time | Flight, asset list/fleet, cargo, log, mining *equipment* (no field: zone not added) | Sandbox / UI testbed | runs |
| **rails** | Warp-rail test: 8 warp nodes in a line between 2 stations; 64 AI ships shuttle between the stations | `Object_WarpNode`, `Object/WarpRail:Create`, `Task_Goto` (AI uses rails), `Task_Wait`, `Item_StationType` | Y/U enter/leave rail (**no null check**, see §7), T recompile | Warp travel (EVE "warp" analogue), traffic | Tech demo | runs |
| **observatory** | Cinematic spectator view of a 32-ship free-for-all near a station | `Widget/Observatory` (free camera + `Texture/Filters` post-processing), `Object_Zone` asteroid field, `Task_Destroy` | P pause, H 20× time; camera controls in `Widget/Observatory` (LMB / RMB drag, F3) | Combat spectating; *mining exists but is commented out* | Demo | runs |
| **model** | Model viewer: a random ship, station, planet and 1024 asteroids | ShipType/StationType/PlanetType gen, `Object_Asteroid`, orbit camera | R regenerate; RMB-drag orbit, scroll zoom, WASD/QE pan, F3 frame info | Ship "show-info" 3D view | Tool | runs |
| **map** | 2D system map of a fully generated system, simulated at 10× speed | `Object/System:Init`, `Widget/Map`, context menus | WASD pan (in `Widget/Map`), right-click context menus | System map / navigation, AI economy at work | UI prototype | runs |
| **market** | Station market screen with 256 random buy/sell orders | `Item_StationType`, `GetStorageLocker`, `AddMarketBuyOrder/SellOrder`, `Widget/Browser` + `Widget/ObjectInfo` | Mouse; Esc closes browser pages | Trading / market UI | UI prototype | runs |
| **objectinfo** | "Show info"/asset browser for the player's ship in a fake 3-system empire with a market station | Same as market + `Object_System` ×3, `Grammar_Get "$system"` | Mouse | Assets window, cargo, ship info, market | UI prototype | runs |
| **hud** | HUD layout over a screenshot background, with no 3D | `Object_Universe 42`; borrows an AI player's ship; `Widget/HUD` | HUD keys (§2.2), no world render | HUD only | UI test | runs |
| **colony** | Placeholder: draws the first system's name huge over a compositor background | `Object_Universe 42` | none | none (doesn't show colonies) | Stub | runs (fixed earlier: converted to `widget:Create`) |
| **platemesh** | Plate-mesh model editor (the "ship designer" idea) | `Widget/ModelEditor` (UI catalog) | Tab, WASD, LMB/RMB in editor | Ship design (not fitting) | Tool prototype | runs |
| **ui** | Widget gallery: draggable window with slider/icons, plus a text-editor window | `Widget/Window`, `Slider`, `TextEditor`, `Draggable` | Mouse drag, Esc | none | UI test | runs (text editor path broken, §7) |
| **image** | Image filter editor applied to a random screenshot | `Widget/ImageEditor`, `Texture/Filters` | Mouse (editor) | none | Tool | runs (fixed earlier: no dev-local screenshots) |
| **draw** | Doodle: drag lines; RMB grows lines that repel each other | Glyph drawing | LMB-drag draw line; hold RMB grow | none | Toy | runs (fixed earlier: RMB guard) |
| **brain** | "Neural Sandbox": 1024 nodes with complex-valued energy flowing over random edges | Glyph drawing, `RNG_MTG` | LMB inject energy near cursor (RMB does nothing) | none | Experiment | runs |
| **hnn** | "Harmonic Neural Network": 512 oscillators on a line | Glyph drawing | Up/Down double/halve sim speed; LMB impulse at nearest node | none | Experiment | runs |
| **life** | "Harmonic Lattice": parity automaton on a 128×128 lattice driven by 4 fixed-sequence points | `App/Life/*`, `SaveTo`/`LoadFrom` serialization | Space pause (starts paused), Ctrl+S / Ctrl+L save/load `organism.bin` | none | Experiment | runs |
| **universe** | "Universe Lattice Simulation": 512 nodes on concentric rings, integer diffusion to the 3 nearest neighbours | Glyph drawing, `Widget/Dev/FrameInfo` | none | none (unrelated to the game's Universe object) | Experiment | runs |
| **loading** | Mock loading screen ("LIMIT THEORY", fake %, spring ring that reacts to the cursor) | DrawText, Glyphs | Mouse proximity | none | Splash prototype | runs |
| **launcher** | Intended app picker: lists files in an App directory | `Directory_List` | none (no click-to-launch) | none | Broken stub (wrong path, §7) | runs (shows empty list **(unverified)**) |
| **strukt** | Empty three-pane layout for "Strukt" (visual coding; see `src/liblt/Strukt/`) | Widget components | F3 frame info | none | Stub | runs |
| **font** | Renders a string at 6 sizes into a 1024×640 texture and saves `test.bmp` | `Texture2D_Create`, `BeginDrawTo`, `DrawText`, `SaveTo` | — | — | Test | one-shot |
| **prime** | Prints primes < 1000 | LTSL loops, `@` print | — | — | Test | one-shot |
| **sandbox** | Prints the current time; comments sketch procedural news/dialogue generation | `Time_Current` | — | — | Test / design notes | one-shot |
| **threads** | Runs a script function on a worker thread and prints `Result: 49995000` | `Thread_Create`, `GetResult` | — | — | Test | one-shot (fixed earlier: restructured) |
| widget | Shared host for widget apps (not an app itself) | `Interface`, `Widget/DevPanel` | Ctrl+Tab dev panel, T recompile | — | Infrastructure | n/a |

### 2.2 Shared flight and HUD controls (from `Widget/Handling.lts`, `Widget/HUD*.lts`)

Applies to ltheory, war, dogfight, handling, rails and hud. Source owned by the UI cataloger; listed here so the app table is usable.

| Key | Action |
|---|---|
| Space | Toggle mouse-steering (cursor offset from screen centre → pitch/yaw) |
| W / S | Thrust forward / back |
| A / D | Strafe left / right |
| Q / E | Roll |
| Tab (hold) | Boost |
| RMB (hold) | Fire weapons at the cursor or the target under the reticle |
| `-` / `=` | Cycle camera target index |
| T (over a world-object marker) | Target / untarget |
| Right-click a world-object marker | Context menu: Communications, Owner, **Trade** (if the object has a market), [DEV] Jump To, [DEV] Fireworks!, Information (handler commented out), Target |
| G | Toggle world-object markers |
| B | Lock/unlock HUD panels; Shift-drag resizes |
| F3 | Frame info |
| F4 | Toggle the whole HUD |
| Esc | Game menu (`Widget/GameMenu`) |

### 2.3 Per-app notes

**ltheory**
- **Setup.** Builds `Object_Universe 39 0` and walks down to the first `System`. That system's contents come from `Object/System:Init`, which C++ calls from `Region.cpp:153`. Spawns the player's ship 10 km from the first dockable station (or at a random point if none). The ship is a 20000-value hull, seed 55, with as many `Item_WeaponType 46` as fit. The player gets 10000 credits and the name "SuperSpaceSquirrel".
- **Each frame.** Only the player's current container (the system) is updated, with `dt` capped at 0.1 and ×20 while H is held.
- **What the generated system contains:**
  - a planet with 1–3 colonies (each with an AI governor)
  - a torus asteroid belt
  - 4 arcs of orbital warp rail
  - 2 asteroid zones, each with an outpost station that sells 32 item listings, plus 2 invulnerable patrols and 3 invulnerable pirates per patrol fighting each other
  - rails linking the points of interest
  - 2 AI players running `Task_Play` in boss-class ships with transfer units
- **EVE-like features available:**
  - flight
  - combat (hostiles exist, but pirates only target patrols, so nothing attacks the player unprovoked **(unverified)**)
  - targeting
  - trading via right-click → Trade on an outpost
  - warp rails (Y/U)
  - an AI economy in the background
- **Missing:** see §8.

**war / dogfight**
- Both are "direct" apps with a separate `ui` Interface drawn inside the 3D pass through `RenderPass_Interface`.
- **war:** 32 random ships of value 10⁴–10⁷. Each is tasked to destroy a random previously spawned ship, which produces a cascading free-for-all. The player sits in the middle with 4× `WeaponType 54`.
- **dogfight:** 10 value-10⁵ ships, each with a random weapon type ×4, all running `Task_Destroy` on the player's 10⁶ ship. A planet 400 km away gives lighting and a backdrop.
- Both build an `Object_Zone` but never add it (the `# system.AddInterior zone` line is commented out).
- These are the best ready-made **combat encounter** templates.

**handling**
- The flight test bed, and the most "EVE-like empire" setup:
  - a named system ("Fermat's Last") with a named ore ("Mercoxit")
  - 16 player-owned assets (Fighter/Hauler/Battleship/stations) scattered 10 km out, about half of them flying `Task_Goto` to each other
  - random weapons and ore loaded into cargo
  - two "Pirate" ships (unarmed, no tasks, random health)
  - fake log lines ("Received new message from Darth Vader")
  - the player ship fitted with transfer units (mining/transfer equipment)
- A station is created and given cargo but **never added to the system**, and the zone isn't added either, so there is nothing to mine.

**rails**
- Dedicated test of the warp-rail system: 8 `Object_WarpNode`s 10 km apart along +Z, joined by `Object/WarpRail` objects, with a 10⁸-value station near each end.
- 64 AI ships alternate `Task_Goto station1` / `Task_Goto station2` eight times after a random 0–10 s wait. `Task/Goto.cpp` sends `MessageStartUsing` to rails, so AI traffic rides them.
- The player starts at the last node and uses Y/U to board/leave the targeted node (`WarpNode.cpp:400`).
- Shows EVE-style "warp to" travel along fixed lanes.

**observatory**
- Spectator camera targeting a station (`Widget/Observatory` adds post FX via `Texture/Filters`). Contains a 1024-asteroid zone and a 32-ship battle.
- The "Miners" block (32 haulers with transfer units running `Task_Mine zone`) is **commented out** by `# desc "Miners"`. Re-enabling it is a one-character change and gives a mining demo.
- Bug: the hull-type switch never picks `shipType4`.

**model**
- Orbit-camera viewer. Each R press deletes and regenerates: one ship of value 10^(5–7), a station, planet type 155, and 1024 asteroids of random scale.
- Useful for inspecting `Item/ShipType/Generate.lts` and `Item/StationType/Generate.lts` output.

**map**
- Generates a system through `Object/System:Init`, then picks `player` as the owner of the **last** owned interior object. That should be one of the AI players' ships, since those are added last **(unverified)**.
- Shows `Widget/Map` (2D system map with WASD panning and context menus) while the system simulates at 10× speed.
- The basis for an EVE-style system map / overview.

**market / objectinfo**
- Both build a station whose market has 256 random orders (10% sell orders with stock placed in the seller's storage locker, 90% buy orders) and show `Widget/Browser` → `Widget/ObjectInfo`.
- `market` targets the station.
- `objectinfo` targets the player's ship, which is "Blue Dragon" in a 3-system fake empire with 32 assets; that exercises the assets/cargo/overview tabs.
- Only `station.Update` runs, so orders can match but nothing moves in space.

**hud**
- Takes the first system of universe 42, borrows the last owned object's owner (an AI player), adds 10 weapon items to its ship's cargo, and renders only `Widget/HUD` over a screenshot.
- No 3D, no simulation. Layout test.

**colony**
- Despite the name, it only prints the system name. The real colony UI is `Object/Widget/Colony.lts`, which C++ opens from `Colony::GetWidget`.

**platemesh / ui / image / strukt**
- Hosts for UI-catalog widgets (ModelEditor, Window/Slider/TextEditor, ImageEditor, an empty Strukt layout).
- `image` runs a hard-coded filter chain and saves `newImage.png` (`Widget/ImageEditor.lts:81`).

**brain / hnn / life / universe / loading / draw**
- Josh's math and visual experiments (energy networks, oscillators, a parity automaton, ring lattices, a spring ring). No game objects.
- `life` is the only one that uses script serialization (`SaveTo`/`LoadFrom` writing `organism.bin` to the working directory).
- `loading` is a usable loading-screen design.

**launcher**
- Meant to be an in-engine app picker, but it only lists file names and has no launch action.
- Its path `../lt/resource/script/App/` is from Josh's dev layout.

**font / prime / sandbox / threads**
- No `Update`, so the launcher exits after `Initialize` (`launch.cpp:83`).
- `font` writes `test.bmp` to the working directory (now git-ignored).

### 2.4 Experiments: what they were for

The code has almost no comments about intent. Each entry below says what the code computes (from reading it) and gives an **inferred** purpose, plus possible uses in an EVE-style game. Four of the experiments share a naming theme: "Harmonic Neural Network", "Harmonic Lattice", "Universe Lattice Simulation", and the unused "HARMONIC REALITY" splash. That suggests a side research thread on emergent behaviour in networks of simple units. **None of them is connected to the game's AI**, which is the task planner in `src/liblt/Game/Task/`.

| Item | What it actually computes | Inferred purpose | Possible use |
|---|---|---|---|
| `App/loading.lts` | "LIMIT THEORY" title; a fake percentage (`Sin time`); a ring of 512 spring-coupled nodes with random Gaussian pulses that also reacts to the cursor; a frame-time readout | Prototype of the game's loading screen. No progress API exists anywhere in the engine | A real loading screen for universe generation. Startup takes ~10–15 s, but generation runs synchronously on the main thread, so the screen can't animate until generation runs incrementally through the `Scheduler` or reports progress between steps |
| `Widget/SplashScreen.lts` | Glowing "HARMONIC REALITY" text around an icon, plus drifting particles | A studio/project title card (guess). Referenced nowhere | Template for a splash screen |
| `App/hnn.lts` "Harmonic Neural Network" | 512 coupled oscillators on a line. Each node has a phase (`angle`), angular velocity (`energy`) and a momentum term (`mass`). Edges transfer energy in proportion to the difference, which is a discrete wave equation. A click sends a Gaussian pulse that propagates and reflects. Two random long-range edges act as shortcuts. A commented-out line adapts edge weights by phase distance (a Hebbian-style learning rule) | Exploring oscillator networks as neural nets. **The same spring-chain algorithm, closed into a ring, drives the loading screen**, so this was also R&D for that effect | UI/VFX: pulse rings, shield-hit ripples, scanner or comms waveforms |
| `App/brain.lts` "Neural Sandbox" | 1024 nodes in a disc, ~8 distance-biased random edges each. Node state is a complex number (amplitude + phase); edges hold complex weights (phase shifts). Energy flows by complex multiplication, phases rotate in proportion to amplitude, and node and edge energy are renormalized every step (conservation). LMB injects energy; the RMB "synch node" is stubbed out | Exploring phase-based (holographic/oscillatory) neural dynamics | The "energy spreading through a graph" visual: trade flows, influence spreading through a region, a hacking minigame. The simulation itself is a curiosity |
| `App/universe.lts` "Universe Lattice Simulation" | 512 nodes on rings whose counts grow by `count*3 − last` (hexagon-like), each linked to its 3 nearest neighbours. Each step spreads a node's integer value to its neighbours and keeps the remainder (exactly conserved). **All values start at 0 and nothing injects any, so it renders a static lattice** | "Digital physics": a universe as a lattice automaton with conserved quantities. Unfinished | Nothing beyond the ring-layout trick |
| `App/life.lts` + `App/Life/*` "Harmonic Lattice" | A 128×128 triangular lattice. Each cell becomes the sum of its neighbours' previous values mod 2 (a linear XOR automaton, the 2D relative of Rule 90). Four "fixed points" inject repeating bit sequences, and their interference produces **self-similar Sierpinski-like fractal patterns**. Edges are drawn where both ends are 1. Unused per-cell "heat" and average trackers measure stability | Artificial-life research: the driven configuration is called an "organism", and the stability metrics suggest a search for persistent structures | Procedural pattern generator (alien glyphs, anomaly/exploration-site visuals, textures). **It is the only script that saves and loads a custom script type to disk** (Ctrl+S/Ctrl+L, `organism.bin`, via `SaveTo`/`LoadFrom` + `cast`), so it is the working reference for building save games |

**Audio pieces** (none computes audio "fractals"):

| Item | What it is | Intended use | Status |
|---|---|---|---|
| Scanner (`Widget/Scanner.lts`, `HUD/Miniscanner.lts`, `Object_GetScannerOutput`) | Each nearby object's signature drawn as a log-frequency spectrum, over a looping ambient sound | Basis for exploration and probe-scanning gameplay | Display only; no results or gameplay attached. **The most directly useful piece for EVE-style probe scanning** |
| `src/liblt/Audio/` | A small offline signal-graph synth: instrument (generator + note pattern + envelope), delay, lowpass, compressor, sum/product nodes, rendered to a float buffer or WAV (see 05 §2.7) | Procedural sound design | Used only by `src/old/soundstudio` (glass synth, wind, scales), which isn't built. Partly broken |
| `resource/shader/fragment/gen/sound.jsl` | A GPU synth that writes audio samples into a texture (sine/saw/tri waves, envelope) | Experiment in GPU audio synthesis | Unused |

---

## 3. Gameplay scripts

### 3.1 Who loads them

| Script | Loaded from (C++) | When |
|---|---|---|
| `Object/System:Init` | `Game/Object/Region.cpp:153` | Every system generated inside an `Object_Universe`/`Region` (not for a bare `Object_System`; `map.lts` calls it explicitly) |
| `Object/Ship:Init` | `Game/Object/Ship.cpp:92` | Every ship instantiated |
| `Object/WarpNode:Init`, `:EjectPassenger`, `:UpdatePassenger` | `Game/Object/WarpNode.cpp:456/253/303` | Every warp node, and passengers leaving or riding it |
| `Object/Thruster:Init` | `Game/Object/Thruster.cpp:207` | Every thruster (the script is an empty function) |
| `Object/Colony:Init` | `Game/Object/Colony.cpp:266` | Every colony |
| `Object/Widget/Colony:Create` | `Game/Object/Colony.cpp:189` | Colony info widget |
| `Item/ShipType/Generate:Main` | `Game/Item/ShipType.cpp:220` (preceded by `Script_Reload`) | Every new ship type (hull mesh) |
| `Item/StationType/Generate:Main` | `Game/Item/StationType.cpp:61` | Every new station type |
| `Item/{Thruster,Weapon,TransferUnit,Turret}Type:Generate` | the matching `Game/Item/*.cpp` | Once per process (cached in a static) |
| `Object/WarpRail:Create` | scripts only (`rails.lts`, `Object/WarpNode.lts`) | — |
| `Object/Firework:ShootFrom` | `Widget/HUD/WorldObject.lts` ([DEV] Fireworks menu) | — |
| `Texture/Filters:*` | `Widget/Observatory.lts`, `Widget/ImageEditor.lts` | — |
| `Texture/RandomScreenshot:Get` | hud, launcher, objectinfo, platemesh, ui, map, market apps | — |
| `Task/Test.lts`, `Common/Grammar.lts` | **nothing** (orphaned) | — |

### 3.2 What each implements

| File | Lines | Implements | Reuse notes |
|---|---|---|---|
| `Object/System.lts` | 221 | **The procedural star-system recipe** (see the list below this table) | **The single most valuable gameplay script**: a compact, readable "what's in a system" recipe. Ports directly to any engine as design. |
| `Object/WarpNode.lts` | 123 | `BuildRail` (straight rail, a node every 15 km), `BuildRailRadial` (arc), particle effects and 3 looped drones per node, exit burst plus `warpnode/exit.wav` | Rail-lane generation logic is reusable |
| `Object/WarpRail.lts` | 54 | `Object_Custom` segment between two nodes: sends `MessageLink` both ways, draws particles along the segment. Its own mesh is built but `SetRenderable` is commented out | — |
| `Object/Ship.lts` | 33 | Per-ship script: looped interior hum plus engine loop, with volume/pitch driven by speed | Simple audio pattern |
| `Object/Colony.lts` | 29 | `Culture` type (unused); `ColonyUpdate` gives the colony a 1%/tick chance to add a production-lab item; replies to `MessageGatherWidgets` with a "Test it out!" text | Placeholder |
| `Object/Widget/Colony.lts` | 65 | "Cultural Traits" panel: 7 bars (Aggressive, Creative, Explorative, Greedy, Intellectual, Lawless, Sociable) | The trait model is a nice faction/NPC idea |
| `Object/Firework.lts` | 85 | Recursive firework objects (gravity, particles, lights, child bursts for 2 generations, explosion sound) | Toy; shows `Object_Custom` + `Update` |
| `Object/Thruster.lts` | 1 | Empty `Init` hook | — |
| `Item/ShipType/Generate.lts` | 105 | **Procedural hull generation** (see the list below this table) | Algorithm portable (a box-grammar "kitbash" hull); needs a PlateMesh/SDF equivalent |
| `Item/StationType/Generate.lts` | 42 | Station plate mesh: 4 spoked rings at different heights, a tapered central column of 16–32 pieces, 2 random attractor warps | Same |
| `Item/ThrusterType.lts`, `TurretType.lts`, `WeaponType.lts`, `TransferUnitType.lts` | 9–10 each | Tiny plate meshes for socket items. **WeaponType and TransferUnitType are byte-identical meshes** | Trivial |
| `Task/Test.lts` | 7 | `TestTask` with `Begin`/`End`/`Update`: the interface `Task_Custom` expects (`Game/Task/Custom.cpp:65`). Template for script-defined AI tasks. Unreferenced | Documents the extension point |
| `Texture/Filters.lts` | 226 | GPU image-filter library over `post/*.jsl` shaders: Add, Blur(H/V), CircleMin/Max, ColorGrade (5-point bezier), EdgeDetect, ExpMap, Gain, Levels, Linear/Invert, Median, Min/Max, Multiply, Power, Resample (cubic), Saturate, Vignette, and an "Artistic" preset. `*Out` variants write into an existing texture | Works now: commit 88bbac3 fixed the uniform cache that zeroed script shaders |
| `Texture/RandomScreenshot.lts` | 12 | Random file from `cache/screenshot/` (where F1 saves), falling back to `resource/texture/splash.png` (rewritten this session) | — |
| `Common/Grammar.lts` | 58 | Script re-implementation of a weighted string-rewrite grammar (`Rule` → weighted outputs, expanded until stable). Unreferenced; the game uses the C++ `Grammar_Get` with `resource/gamedata/grammar/*.txt` | Name-generator algorithm; trivially portable |

**`Object/System.lts` in detail:**
- the system name comes from the grammar `$system`
- 1 planet of radius about 100 km
- 1–3 colonies on that planet; each has random personality traits, a `Task_Spawn` colony type, an AI governor with 1M credits, and sits on the planet surface via `planet.Attach`
- a torus asteroid belt around the planet
- 4 arcs of radial warp rail around the planet
- 2 ellipsoidal asteroid zones, each with:
  - an outpost station with an AI manager (1M credits) and 32 sell orders drawn from a pool of 32 weapons plus a drone bay, production lab, tech lab and transfer unit
  - 2 patrols plus 6 pirates set to destroy each other (all with health 10⁹, so effectively an eternal skirmish)
- straight rails from the planet to each zone
- 2 AI players with 1.5M credits, boss hulls, transfer units and weapons, each running `Task_Play`

**`Item/ShipType/Generate.lts` in detail:**
- starts from 2 seed boxes
- grows `2 + sqrt(scale)` plates by stepping along a random axis
- repeats each plate 1–5 times along Z, with a slimmer "passive" twin
- mirrors everything in X
- adds lower hull boxes for scale ≥ 10
- applies two custom warp functions (vertical compress, rear horizontal expand)
- centres the mesh, computes occlusion and assigns `Material_Metal`
- the decal experiment (Chinese text via `Fonts:ChineseSimp`) is commented out

---

## 4. Launcher and legacy code

### 4.1 `src/launch/launch.cpp`: the only built executable

| Aspect | Behaviour |
|---|---|
| Args | Exactly one: the app name. Otherwise prints an error and returns **0**, so the exit code doesn't signal failure |
| Working dir | If `resource/` isn't in the cwd, `chdir("../")`, so it works from the repo root or `bin/` |
| Window | Fixed 1920×1080 windowed ("App Launcher"), **vsync off** (`SetSync(false)`); no config file |
| Launch() | Creates the physics engine and `SoundEngine_Fmod()` (FMOD is mandatory; there's no null sound engine), `Script_ClearCache`, loads `App/<name>:Main`. It **errors out cleanly** (patched this session) if Main's inferred return type isn't a script type. Then it constructs an instance, calls `Main(instance)`, calls `Initialize`, and exits if there's no `Update` |
| Per frame | F1 screenshot to `OS_GetUserDataPath()+"screenshot/N.png"` (= `cache/screenshot/`); F2 `Profiler_Auto(1s)`; Ctrl+W quit; `~` held = `debugprint`; F5 = `Launch()` again (full hot reload with fresh engines and script cache); then app `Update`, physics update, sound update |
| Leftovers | `#if 0` WinMain; `TIME_LTSL_COMPILE` timing option |

### 4.2 `src/old/`: not in CMakeLists, none of it builds as-is

| Dir | Lines | What it was | Builds against current liblt? | Salvage value |
|---|---|---|---|---|
| `ltheory/ltheory.cpp` | 245 | **The old native game main** ("Limit Theory" window from `Config_*` settings, mouse capture, vsync). Universe seed 98080 at level 1, player "Trent Edison" in a 10000-value ship 250 km above the home station, weapon 40, random cargo, a second player-owned ship "Voyager" with production and tech labs plus 1200 cargo items. HUD from `Widget/HUD:Create` (F5 reloads it), passes Clear/Camera/SMAA/Interface/**Bloom**/dither, two ambience loops. **Fixed-step simulation at 30 Hz with interpolation** (`container->Update(state)` + `SetInterpolant`). Debug keys: M +1M credits, K random weapon, H 10× time | **No.** Uses `AddModule`, `Profiler_AutoProfile` and `SetInterpolant`, which no longer exist; `Universe_Get`, `UpdateState`, `Sound_Play2D`, `Config_Int` and `RenderPass_Bloom` still exist | **High as reference:** the fixed-timestep + interpolation loop, config-driven window and starting-loadout recipe are what `ltheory.lts` lacks. Porting to a ~100-line `src/game/` target looks feasible **(unverified)** |
| `launcher/launcher.cpp` | 146 | Pre-game settings launcher (video mode, mesh quality, fullscreen/audio/vsync → `Config_Set`, update check against ltheory.com, `OS_Spawn("./ltheory")`) | No. The body is `#if 0` and uses a removed retained-mode UI (`CreateUIGroupY`, `UIManager`); `main` returns 0 | Low (the settings list is a checklist) |
| `ltconsole/ltconsole.cpp` | 134 | Headless console: runs `App/Benchmark:Main` (that script **no longer exists**); disabled code paths for an LTSL→C emitter (`EmitC`), function-list dump, and a headless simulation-speed benchmark of universe 130 | Probably close (uses mostly current APIs) **(unverified)**, but the active path loads a missing script | Medium: the LTSL→C emitter idea and headless benchmark |
| `codegen/` | 817 | Generator for the macro headers `AutoClass.h` / `Functions.h`. liblt now has `LTE/AutoClass_Generated.h` and `LTE/Function_Generated.h`, almost certainly its renamed output **(unverified)** | Probably (needs only `LTE/LTE.h` + local headers) **(unverified)** | Needed only to regenerate those headers (e.g. to raise `kMaxFields = 16`) |
| `makepatch/makepatch.cpp` | 51 | Built a binary diff of "LT Prototype" v1.0→v1.1 (Windows paths) into `updater/patchdata.h`. Body `#if 0` | Compiles to a no-op | None (`LTE/Patch.*` still exists if wanted) |
| `updater/` | 59 | Windows registry-checking patch applier for the 2013 prototype. Body `#if 0`; `patchdata.h` is a 20-byte dummy | No-op | None |
| `soundstudio/soundstudio.cpp` | 189 | Procedural synth toy: additive "Glass" synth, wind noise, minor scales, on-screen note buttons playing through `src/liblt/Audio` signals | No: old `Program` API (`window.width`, `UIClickData`, `MakeMouseListener`) | Low–medium: shows how to use the `Audio/` signal library, which is otherwise unused |

---

## 5. Build and third-party inventory

### 5.1 Build files

| File | Notes |
|---|---|
| `CMakeLists.txt` | Builds SFML 2.5.1 statically from `ext/SFML` (audio module disabled, PIC on, CMake-4 policy shim). `liblt` is a SHARED library globbed from `src/liblt/**/*.cpp`. The single target is `launch` (`src/resources.rc` is added on all platforms). Linux64 links system FreeType + GLEW + dl + OpenGL, and **copies `libfmodex64-4.44.24.so` / `libfmodevent64-4.44.24.so` into `bin/`** with `$ORIGIN` rpath. Linux32 / Mac link `extbin/` FMOD. Windows links `extlib/win32/*.lib` and copies DLLs. Flags: `-std=c++0x -O2 -g -fno-exceptions -msse2 -Wfatal-errors`. `enet` is commented out everywhere |
| `configure.py` | `python3 configure.py` (cmake configure, RelWithDebInfo; Win32 arch on Windows), `build` (parallel), `run <app> …`, `clean` (deletes bin, build, **cache**, so also screenshots) |
| `cmake/FindGLEW.cmake` | Used for the Windows `GLEW_GLEW_LIBRARY` variable |
| `script/` (top level) | Dev utilities: `assetlist.py` (writes asset list), `tloc.py` (line counter), `install_dependencies.sh` (old Ubuntu packages: glew1.5, sndfile, openal, now partly obsolete), `meta/DeclareFunction.py` (macro generator) |
| `.gitattributes` | All binaries (wav/ogg/ttf/otf/fsb/png/jpg/bin/so/dll/lib…) are **Git LFS**; a checkout without LFS gets pointer files |

### 5.2 Third-party code

| Component | Location | Version | Used on Linux64? | License | Notes |
|---|---|---|---|---|---|
| **FMOD Ex + Event system** *(removed Oct 2026; replaced by vendored miniaudio, public domain)* | `include/FMOD/*`, `extbin/linux32` (4.44.20), `extbin/linux64` (**4.44.24**), `extbin/osx`, `extbin/win32`, `extlib/win32/FMOD` | Headers: `FMOD_VERSION 0x00044414` (4.44.14), `FMOD_EVENT_VERSION 0x00044420` | **Yes, required** (`Module/SoundEngine/Fmod.cpp`, loaded unconditionally by the launcher) | **Proprietary (Firelight Technologies).** Historically free for non-commercial use only; commercial use needed a paid licence. FMOD Ex is discontinued, so a licence for 4.44 is probably no longer sold (check with Firelight). Josh's Unlicense **cannot** relicense these binaries | Main licensing blocker; see §8 |
| SFML | `ext/SFML` (git submodule) | **2.5.1** (`git describe`) | Yes (static: graphics, window, system, network) | zlib/png | Fine. `extbin/*/libsfml-*` (2.0) are stale and unused on Linux64 |
| FreeType | `include/FreeType` (2.5.3), `extbin/linux64/libfreetype.so.6.11.2`, win32/osx libs | 2.5.3 | System FreeType instead (CMake deliberately avoids extbin's) | FTL (BSD-style w/ credit) or GPLv2 | Fine |
| GLEW | `include/Glew/GL/{glew,glxew,wglew}.h`, `extlib/win32/Glew/glew32s.lib`, `extbin/osx/libGLEW.1.9.0.dylib` | Headers go up to GL 4.2 (≈ GLEW 1.7–1.9; osx lib is 1.9.0) | Headers from `include/`, **library is system GLEW**, a possible header/lib mismatch **(unverified, but it builds)** | Modified BSD + MIT (Mesa) | Fine |
| UTF8-CPP | `include/UTF8` | 2.x (2006 Nemanja Trifunovic) | Yes (`LTE/UniString.cpp`) | Boost Software License 1.0 | Fine |
| ENet | `include/enet` (1.3.11), `extbin/*/libenet*` | 1.3.11 | **No** (commented out; `src/liblt/Network/Client.h` is an empty stub) | MIT | Removable |
| Oculus OVR SDK | `include/OVR/OVR.h`, `OVRVersion.h` | 0.2.5 | **No** (no includes; the headers reference `../Src/…` that isn't shipped) | Oculus proprietary SDK licence | Dead; delete |
| windirent.h | `include/windirent.h` | 2006–2012 Toni Ronkko | No (Windows-only branch of `LTE/OS.cpp`) | MIT | Fine |
| GL/GLU/GLUT/GLUI/GLAux headers | `include/GL/` | Ancient Windows SDK copies | No includes found | GLUT: Kilgard licence; GLUI: LGPL/zlib by version **(unverified)** | Dead; delete |
| zlib1.dll | `extbin/win32` | ? | No | zlib | — |
| libsndfile (osx framework) | `extbin/osx/sndfile.framework` | ? | No | LGPL | Dead |
| In-tree ThirdParty | `src/liblt/ThirdParty` (KDTree, SMAA area/search tex, TriTriOverlap) | — | Yes | SMAA: MIT; others per file **(not checked; rendering/core catalogs)** | — |

**What Linux64 actually uses:** only `extbin/linux64/libfmodex64-4.44.24.so` and `libfmodevent64-4.44.24.so` (copied to `bin/`). Everything else in `extbin/linux64` (old SFML 2.0, freetype, enet, `old/`) is unused, and so are `extbin/linux32`, `osx` and `win32` on this platform.

**Repo licence:** `LICENSE` is the **Unlicense** (public domain dedication by Josh Parnell, commit 940a207). It covers Josh's code and presumably his own assets. It cannot cover FMOD, the OVR headers, or assets of unknown third-party origin.

---

## 6. Asset inventory

Sizes are from `du`. "Referenced" means a literal path appears in `src/liblt`, `src/launch`, `resource/script` or `resource/gamedata`.

### 6.1 Fonts: `resource/font/` (29 MB, 127 files = 91 TTF/OTF + 36 licence files)

| Family (files) | Licence file | Referenced by |
|---|---|---|
| **Rajdhani** (Regular/Light/Medium…) | OFL | `Fonts.lts` Default/Light/Medium: **the main UI font** |
| **Iceland** | OFL | `Fonts.lts` Heading/Subheading |
| **NotoSans** (Regular/Bold) | *none in folder* (Noto is OFL today; older releases were Apache 2.0) | `Fonts.lts` Unicode |
| **NotoSansCJKsc** (16 MB) | *none* (Noto CJK: OFL) | `Fonts.lts` ChineseSimp asks for **`NotoSansCJKSC/`**: a case mismatch, so it fails on Linux. Only used by the commented-out decal code |
| SourceCodePro (8) | OFL | Light and Bold referenced (text editor / dev UI) |
| Gafata | OFL | `loading.lts` |
| Play | OFL | `font.lts` |
| Abel, Anaheim, Aubrey, Baumans, Coda, Dosis, Economica, Exo, Exo2, Homenaje, Inconsolata, Jura, KellySlab, Khand, Mako, Marmelad, Marvel, NewsCycle, Nova, Offside, Oxygen, PontanoSans, PTSansNarrow, ShareTech, ShareTechMono, Strait, TitilliumWeb, unicaone, YanoneKaffeesatz | OFL each | **Unreferenced** (a font-picking palette; `Widget/FontPreview.lts` may browse them; UI catalog) |
| DroidSans | Apache 2.0 (`LICENSE.txt`) | Unreferenced |
| UbuntuMono | Ubuntu Font Licence (`UFL.txt`) | Unreferenced |

Licensing: **every font is open (OFL / Apache / UFL) and reusable**, including commercially. Keep the licence files, and if you ship a modified OFL font, don't distribute it under its reserved font name. Add the missing Noto licence text if you redistribute them.

### 6.2 Music: `resource/music/` (90 MB, 4 files)

| File | Size | Content |
|---|---|---|
| `LtheoryTest01.fev` | 3 KB | FMOD Designer event project "LtheoryTest01": events `Space01_music`, `TestEx_BT_01`, a parameter "Volume (closing in)", and stems BState01, Eploratory01, Final, Transitional01, TransitionalBt_S01-02 |
| `LtheoryTest01_bank00.fsb` | 66 MB | Sound bank for the above (`FSB5` header) |
| `LT_Music.fev` | 4 KB | Project "LT_Music", event `music/System01`: adaptive music with Explo01, Transition01, Tension01/02 and Event01–04 layers |
| `System01.fsb` | 28 MB | Bank for the above (`FSB5`) |

- **Runtime status: orphaned.** Only `Module/MusicEngine.cpp` loads music, and it loads `LtheoryTest01.fev`. `CreateMusicEngine()` is never called; its only call site is commented out in `src/old/ltheory/ltheory.cpp:94`. `LT_Music.fev` isn't referenced anywhere.
- **Format lock-in:** these are FMOD Designer banks. Playing them requires FMOD Ex's event system; reusing them elsewhere means extracting the audio with third-party FSB tools.
- **Licensing:** the composer isn't named anywhere in the files. This was presumably commissioned music; whether the Unlicense actually covers it is **unknown**. Treat it as **not cleared** for reuse.

### 6.3 Sound effects: `resource/sound/` (241 MB, 130 files: 79 OGG, 51 WAV)

| Category (dir) | Files | Size | Referenced | Notes |
|---|---|---|---|---|
| system/ambiance | 11 WAV | **118 MB** | 1 (`089.wav`, ltheory.lts) | `002`/`037` were used by the old native main. Numbered names suggest a purchased ambience library **(unverified)** |
| ui (+ misc/open/select) | 35 | 33 MB | 18 | click/hover/window/target/scanner/drag. `select/`, `open/`, `misc/` unreferenced |
| warpnode | 12 | 31 MB | 4 (drone1–3, exit) | |
| station | 3 WAV | 21 MB | 0 | Named `ambiance_ship_loops_14/15/16.wav`, which looks like a commercial library pack's naming **(unverified)** |
| ice/ambiance | 5 OGG | 15 MB | 0 | |
| weapon (beam, missile, rail, pulse 1–6, torpedo) | 39 | 7.3 MB | ~11 (beam1, missile1, rail1, pulse 1–5 first variant, pulse4_fire…) | Pulse 6, torpedo, rail/1 and missile/ variants are unreferenced |
| techlab / productionlab / transferunit / dronebay / scanner / shield / thruster / jumpdrive | 2–3 each | ~12 MB | most loops referenced; **jumpdrive** 0 | `thruster/loop1.ogg` and `ship/ambiance/interior/1.wav` are used by `Object/Ship.lts` |
| explosion, impact/metal | 6 | small | `explosion/altsmall3.ogg`, `impact/metal/1.wav` | |
| **Total** | 130 | 241 MB | **45 referenced, 85 orphaned** | No referenced path is missing |

- **Licensing/provenance:** no credits, readme or licence anywhere under `resource/sound`.
- **Embedded metadata:** the only tags are "Sound Forge Pro 10.0 (libsndfile)" in some UI WAVs and "Xiph libVorbis 20070622" in the OGGs.
- Provenance is therefore **unknown**. Some files carry library-style names. Do **not** assume the Unlicense covers them; for a new game, treat them as placeholders.

### 6.4 Textures: `resource/texture/` (2.4 MB, 10 files)

| File | Referenced by | Provenance / reuse |
|---|---|---|
| `SMAA_AreaTex.bin`, `SMAA_SearchTex.bin` | `Game/RenderPass/SMAA.cpp` | SMAA lookup tables (MIT); reusable |
| `ice.jpg` (480²), `rock.jpg` (512², made in Paint.NET) | `Game/Materials.cpp` | Unknown origin; replace |
| `water_normals.jpg` (512²) | `Game/ShadingModels.cpp` | Unknown; a common internet normal map; replace |
| `lensdirt.jpg` (1024×576) | `Game/RenderPass/LensFlares.cpp` | Unknown; replace |
| `tree.png` (238×577) | `Game/Object/Colony.cpp` | Unknown |
| `splash.png` (1920×1080) | `Texture/RandomScreenshot.lts` (fallback background) | LT key art (Josh's); LT branding |
| `icon.png` (128²) | only `src/old/launcher` (orphaned) | LT branding |
| `multi.ico` | `src/resources.rc` (Windows exe icon) | LT branding |

### 6.5 Gamedata: `resource/gamedata/` (232 KB)

Listed only; the world-model catalog explains these.
- `grammar/*.txt` (49 files): name grammars for systems, stations, ships, ores, people, etc., consumed by C++ `Grammar_Get` (`$system`, `$station`, `$station_midfix`, `$oretype`…)
- `item/thruster.txt`
- `technology/{root,structural_engineering,subsystem_engineering}.txt`

These are Josh's text (Unlicense) and reusable.

### 6.6 Generated / runtime files

| Path | Written by |
|---|---|
| `cache/screenshot/N.png` | F1 |
| `test.bmp` | `font` app |
| `newImage.png` | `image` app |
| `organism.bin` | `life` app (Ctrl+S) |
| `cache/` | engine caches |

`configure.py clean` deletes `cache/`.

---

## 7. Known issues and quirks in this area

| # | Where | Issue |
|---|---|---|
| 1 | All apps | `#` comments out a line **and its indented block**. Several features are silently disabled that way (observatory miners, hnn second line, ui prompt, widget F4 settings, ship decal) |
| 2 | `rails.lts` Y/U | Calls `target.Send` without the `IsNotNull` check that `ltheory.lts` has. Pressing Y/U with nothing targeted calls through a null `Object`, a **probable crash (unverified)** |
| 3 | `hnn.lts` LMB | `network.nodes.Get selected + i` for i < 64 overruns the 512-node array when the cursor is near the right end: **out-of-bounds read/write (unverified: depends on whether `Array.Get` bounds-checks)** |
| 4 | `launcher.lts`, `ui.lts` | Hard-coded dev paths `../lt/resource/script/App/` and `../lt/resource/script/Widget/Map.lts`. From the repo root these don't exist, so the launcher list is empty and the text editor is blank. Should be `resource/script/...` |
| 5 | `Fonts.lts` | `NotoSansCJKSC` vs directory `NotoSansCJKsc`: fails on case-sensitive filesystems (only matters if the decal code is re-enabled) |
| 6 | `handling.lts` | Station created and filled with cargo but never `AddInterior`'d; zone not added, so the transfer units have nothing to mine |
| 7 | war / dogfight / rails / handling / model | `Object_Zone` constructed but not added. If zone construction generates its field eagerly this is wasted startup work **(unverified)** |
| 8 | `observatory.lts` | Hull-type switch can never yield `shipType4` (the last two branches both return `shipType3`) |
| 9 | `Item/ShipType/Generate.lts` | `index` is computed but `boxes.Get i` is used; branches guarded by `rng.Float < 0.0` are dead. `ShipType.cpp` calls `Script_Reload` on this script **for every ship type**, re-parsing it each time (handy for live editing, a startup cost in big universes) |
| 10 | `Item/WeaponType.lts` / `TransferUnitType.lts` | Identical meshes (copy-paste) |
| 11 | `map.lts`, `hud.lts` | "Player" is whichever owner the object loop saw last (an AI player). That's fragile and depends on `System:Init` insertion order |
| 12 | `ltheory.lts` | Only the player's current system is updated; the rest of the universe is frozen. There's no fixed timestep (the old native main had 30 Hz + interpolation) |
| 13 | Most widget apps | Background is `Texture/RandomScreenshot`; until you press F1 in some app it's always `splash.png` |
| 14 | `launch.cpp` | Error paths exit with status 0. The window is fixed at 1920×1080 with vsync off (uncapped FPS, high GPU use). FMOD is mandatory, so the game won't start without the FMOD `.so` files |
| 15 | `widget.lts` T key | Shader recompile on **T** collides with HUD "target object under cursor" (T) in widget-hosted 3D apps (`ltheory`, `handling`): both fire |
| 16 | `src/old/ltconsole` | Its only live path loads `App/Benchmark`, which doesn't exist |
| 17 | Assets | 85/130 sound files and all of `resource/music` are unreferenced at runtime (≈ 90 MB music + ~170 MB sfx of dead weight) |

---

## 8. Assessment for the two goals

### 8(a) Pushing this engine toward a playable game (EVE-style single-player loop)

**Best foundation: `ltheory.lts`, merged with pieces of `handling.lts` and `src/old/ltheory/ltheory.cpp`.**

`ltheory.lts` is the only app that:
- generates a **whole universe** (regions → systems through `Object/System:Init`: planets, colonies, asteroid belts and zones, market outposts, pirates, patrols, AI capitalists running `Task_Play`, warp rails)
- puts a **player-piloted ship** in it with the full HUD/flight/targeting stack
- exposes **trading** (right-click → Trade on an outpost) and **warp-rail travel** (Y/U)

That is the skeleton of EVE's loop of flying, fighting, mining, trading and travelling. The other apps are best used as donors:

| EVE-like loop piece | Status in ltheory.lts | Donor app / script | What's missing |
|---|---|---|---|
| Flight / piloting | ✅ Works (Handling.lts) | — | EVE-style click-to-approach/orbit/align (AI `Task_Goto` exists and is used in handling/rails; give the player a "fly to" via `ship.PushTask`) |
| Combat | ✅ Weapons fitted; pirates exist | `dogfight` (hostiles that hunt the player), `war` (fleet battles) | Hostile NPCs aimed at the player, damage feedback, death/respawn/clone, loot drops |
| Mining | ❌ Transfer-unit plug is commented out | `handling` (transfer units), `observatory` (`Task_Mine zone`, re-enable `# desc "Miners"`) | Fit a transfer unit, a player "mine" action on a zone/asteroid, ore → cargo → sell |
| Trading / market | ⚠️ Trade window reachable via context menu on outposts | `market`, `objectinfo` (market + storage locker UI) | Docking flow, buy/sell feedback, profit loop; outposts only *sell* (32 sell orders), so you need buy orders for ore/loot |
| Station docking | ❌ No player docking (`Task_Dock`/`Dockable` exist, AI only) | — (C++ `Game/Task/Dock.cpp`, `Component/Dockable`) | Dock/undock UI, station services screen |
| Map / navigation | ⚠️ HUD minimap only | `map` (`Widget/Map` system map) | Galaxy map; inter-system travel (only the current system simulates; `jumpdrive` sounds exist but are unreferenced) |
| Warp lanes | ✅ Y/U on warp nodes | `rails` | Auto-pathing "warp to" UI |
| Fitting / ship editing | ⚠️ `HUD/Sockets` panel shows sockets | `platemesh` (hull editor), `model` (viewer) | Fitting screen that plugs items from cargo, ship purchase |
| Assets / inventory | ⚠️ Menu-bar → Browser → ObjectInfo | `handling`, `objectinfo` (16–32 owned assets, cargo) | Persistent ownership and progression |
| Colonies / factions | ✅ Generated, with trait-based governors | `Object/Widget/Colony.lts` | Standings/reputation, missions (`Game/Mission.cpp` exists: see world/sim catalogs) |
| Game loop plumbing | ❌ | `src/old/ltheory/ltheory.cpp` | Fixed-timestep sim + interpolation, config-driven window/vsync, save/load (only `life` uses `SaveTo`/`LoadFrom`), main menu (`loading` + `Widget/GameMenu`), simulating more than the current system |

**Suggested first steps** (if going this route):
1. Copy `ltheory.lts` and uncomment the transfer unit so the player can mine; add a station buy order for ore so mining pays.
2. Add a hostile spawner from `dogfight`.
3. Hook the context-menu "Information" window back up.
4. Add a player dock action using `Task_Dock` or a direct `Dock` call.
5. Port the 30 Hz fixed step from `src/old/ltheory`.

### 8(b) Dissecting it for a new game

| Category | Reusable | Notes / blockers |
|---|---|---|
| **Design recipes (port as logic)** | `Object/System.lts` (system composition), `Object/WarpNode.lts` (lane generation), `Item/ShipType/Generate.lts` + `StationType/Generate.lts` (box-grammar hulls/stations), `Common/Grammar.lts` + `resource/gamedata/grammar/*` (name generation), colony trait model, `Texture/Filters.lts` (post-FX chain), app setups (dogfight encounter, war FFA, rails traffic, market seeding) | All Josh's work under the Unlicense: **free to reuse, commercially, without attribution** |
| **Code** | `src/launch` pattern; `src/old/ltheory` loop; `codegen` only if staying on liblt | Unlicense |
| **Fonts** | All 38 families | OFL / Apache 2.0 / UFL: **clear for commercial use**. Keep the licence texts; add Noto's |
| **Textures** | SMAA tables (MIT) | ice/rock/water/lensdirt/tree have **unknown provenance**: replace. splash/icon are LT branding: don't ship them under a different game, and avoid the "Limit Theory" name/logo |
| **Gamedata** | grammar/technology text | Unlicense |
| **Sound effects** | Useful as placeholders | **No provenance or licence info**; some names look like commercial library packs. **Do not ship without clearing them**; replace with CC0/licensed packs |
| **Music** | — | Composer unknown, licence unknown, and locked in FMOD Designer `.fev/.fsb` format: **treat as not reusable** |
| **FMOD Ex 4.44** | — | **Resolved Oct 2026: replaced by miniaudio; FMOD code and binaries deleted.** Original assessment: **Main blocker.** Proprietary, discontinued, historically non-commercial-free only, and the Unlicense can't override Firelight's EULA. For a new game: the current FMOD Engine/Studio (Firelight's indie terms; check current revenue limits) or an open alternative (miniaudio, SoLoud, OpenAL Soft: all permissive). The engine's `SoundEngine` interface is small, so swapping the backend is feasible even if you stay on liblt |
| **Other third-party** | SFML (zlib), FreeType (FTL), GLEW (BSD/MIT), UTF8-CPP (Boost), ENet (MIT), windirent (MIT) | Fine. Delete the unused OVR (Oculus proprietary), GL/GLUT/GLUI headers, `extbin/*` except FMOD (until replaced), and `extbin/linux64/old` |
