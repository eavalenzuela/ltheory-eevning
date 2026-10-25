# Limit Theory (old): codebase catalog and EVE roadmap

This catalog records what exists in this repository, how well it works, and how it maps onto the target: **a single-player game modelled on EVE Online**. There are two ways to get there: grow this codebase into that game, or take it apart and carry its best ideas into a new one.

It was produced in October 2026, right after the codebase was revived on Linux. Seven reviewers each read one subsystem. Almost everything comes from reading the code. The only runtime evidence is the smoke test of all 27 apps, the GPU-reset investigation and the bug fixes made in the same session. Claims the authors couldn't confirm are marked **(unverified)** in the section files.

## Sections

| # | Section | Covers |
|---|---|---|
| 01 | [Scripting runtime](01-scripting-runtime.md) | LTSL compiler and interpreter, reflection/type system, the ~800-function script API, **a reference for the language itself** |
| 02 | [Rendering](02-rendering.md) | Renderer, frame pipeline, materials and lighting, procedural texture generators, all 169 shaders |
| 03 | [Core, math, platform, geometry](03-core-math-platform-geometry.md) | Containers, smart pointers, math, OS/window/input, threads/jobs, file locations, spatial partitioning, **procedural meshes** (PlateMesh hulls, SDF asteroids, marching cubes, AO bake) |
| 04 | [Game world model](04-game-world-model.md) | Objects, items, universe generation, economy and market, players and factions, **gameplay feature matrix with EVE equivalents** |
| 05 | [Simulation systems](05-simulation-systems.md) | Components, AI tasks and the economic planner, physics, scheduler, audio, **EVE mapping of flight/combat/NPCs** |
| 06 | [UI](06-ui.md) | Widget framework, HUD and every screen, **status of EVE's UI surfaces** |
| 07 | [Apps, scripts, periphery](07-apps-scripts-periphery.md) | All 27 apps, gameplay scripts, launcher and legacy code, third-party libraries, assets, **licensing** |

---

## 1. The codebase at a glance

| Layer | Where | Size |
|---|---|---|
| Launcher (only executable) | `src/launch/launch.cpp` | 130 lines |
| Game content in LTSL: apps, system recipes, hull generators, all UI screens | `resource/script/` (141 files) | ~10.5k lines |
| Game C++: world model, items, AI tasks, components | `src/liblt/Game`, `Component`, `AI` | ~21.7k lines |
| Engine modules: physics, sound (miniaudio since Oct 2026; was FMOD), scheduler | `src/liblt/Module`, `Audio` | ~2.3k lines |
| UI framework (C++ core) | `src/liblt/UI` | ~3.1k lines |
| Engine (LTE): scripting runtime, renderer, core, math, geometry | `src/liblt/LTE`, `Volume`, `CodeGen`, `ThirdParty` | ~44.7k lines |
| Shaders (`.jsl`, GLSL 1.20) | `resource/shader/` (169 files) | ~6.4k lines |
| Data: name grammars, unused tech-tree notes | `resource/gamedata/` | 53 files |
| Assets: fonts (open licences), sounds, FMOD music banks (now unplayable), textures | `resource/` | ~360 MB |

```
 bin/launch <app> ─── loads resource/script/App/<app>.lts, calls Main, then Initialize once
     │               and every frame: Update ─► physicsEngine.Update ─► soundEngine.Update
     ▼
 ┌─────────────── LTSL (interpreted, hot-reloadable with F5) ────────────────┐
 │  App/ltheory.lts …   Object/System.lts (system recipe)   Widget/HUD …     │
 │  Item/ShipType/Generate.lts (hull grammar)   Widget/Market …              │
 └───────────────▲─────────────────────────────────────────────▲─────────────┘
                 │ ~800 bound functions (reflection: one definition    │
                 │ feeds scripting, serialization and debug printing)  │
 ┌───────────────┴───────────── Game (C++) ──────────────────────┴───────────┐
 │  Objects = compile-time chains of 45 components on a fat ObjectT          │
 │  Items = procedural types (value, seed, multipliers)                      │
 │  AI "players" = profit-seeking corporations running task chains           │
 │  Order-book station markets with escrow · warp rails · scanner signatures │
 └───────────────▲───────────────────────────────────────────────────────────┘
 ┌───────────────┴───────────── LTE engine ──────────────────────────────────┐
 │  LTSL runtime · GL 2.1 deferred-ish renderer · procedural generators      │
 │  PlateMesh / SDF / marching-cubes meshing · math (double positions)       │
 │  containers & intrusive refcounting · scheduler · Location I/O            │
 └───────────────▲───────────────────────────────────────────────────────────┘
          SFML 2.5.1 (window/input/threads) · GLEW · FreeType · miniaudio 0.11.21 (was FMOD Ex 4.44)
```

Key facts that shape every decision:

- **The game content and the UI live in LTSL.** C++ provides capabilities and LTSL composes them: what goes into a star system, what hulls look like, every screen. Universe generation calls back into scripts and creates GPU resources, so the world can't be generated without the script runtime and a GPU (04 §7).
- **Only the player's current container is simulated.** AI players elsewhere are frozen. `Task_LOD` (abstract off-screen simulation) was designed but never wired in (04 §2, 05 §9).
- **There is no save/load, no fixed timestep, and the universe clock never advances** (`Universe::age` is never incremented, which breaks everything time-based) (04 §6, 05 §9).

---

## 2. What the game is today

`ltheory` is the closest thing to a game (07 §2). It generates a seeded universe and drops you, flying a procedurally generated ship, into a star system with:
- a planet and colonies
- an asteroid belt
- market outposts with live order books
- AI corporations running mine→sell projects
- pirates duelling patrol ships (for show: they have 1e9 HP)
- warp rails

Working for the player now:
- direct Newtonian flight with boost and cruise
- the HUD: reticle, targets, minimap, scanner
- instant targeting and pulse-weapon combat
- remote trading through the radial "Trade" menu
- warp-rail travel (Y/U)
- object info and asset browsing

Not working for the player:
- **Mining:** the transfer-unit line in `ltheory.lts` is commented out.
- **Docking:** there's no dock action; `Task_Dock` is AI-only.
- **Moving cargo:** cargo can't be moved between ship and station hangar.
- **Fitting:** there's no fitting screen.
- **Ship purchase:** there's no way to buy a ship.
- **Stakes:** there are no enemies that attack you, and no death or respawn.
- **Meta:** no saving, a game menu whose buttons do nothing, and no settings screen.

The other 26 apps are tech demos and test beds that donate pieces. `dogfight` has enemies that hunt the player; `handling` has a player fleet with cargo; `map` has a system map; `platemesh`/`model` let you edit and view hulls; `observatory` has a mining fleet that is commented out.

---

## 3. EVE roadmap: what exists vs what's needed

Status: ✅ implemented · 🟡 partial · 🔧 stub (code exists, not wired up or not working) · ❌ absent.
Effort to reach a solid EVE-like single-player version on *this* codebase: **S** ≈ a day or less · **M** ≈ days to a week · **L** ≈ multiple weeks. Efforts are judgement calls from reading the code, not estimates from measured work.

### Flight and navigation
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Ship movement | Direct WASD/mouse piloting, drag-limited top speed, boost/cruise | ✅ (different) | — | EVE has no direct piloting. Keep both: direct flight plus EVE-style commands (05 §10) |
| Approach / orbit / keep at range / align | `Task_Goto` and the orbit inside `Task_Destroy`; SDF steering makes these one task each | 🟡 | S–M | `Component/MotionControl.cpp`, `Game/Task/Goto.cpp`. No UI issues them |
| In-system warp | **Warp rails**: physical lanes with slot allocation; Goto pathfinds through them | 🟡 (different) | M | Free "warp to anything" is absent. Rails are a distinctive feature worth keeping (04 §8b) |
| Stargates / jumps | Wormhole pairs generated along region spanning trees; teleport on dock | 🔧 | L | Goto's inter-system branch is empty, and arriving systems aren't simulated (needs off-screen sim) |
| Star map / route planner | — | ❌ | M | The system map exists (`Widget/Map.lts`); the galaxy view doesn't |
| Overview (sortable nearby list) | Brackets, radar, system map only | ❌ | M | Easy on `Dynamic` + list widgets (06 §4.2) |
| Selected-item panel | Radial RMB menu (Target, Trade) | 🟡 | S–M | Add approach/orbit/warp/dock actions |

### Combat
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Weapons | Pulse only; Missile/Rail/Beam code is unreachable; infinite ammo | 🟡 | M | `Item/WeaponType.cpp` (`kAmmoProbabilityMult`) |
| Target lock, range, tracking | Instant lock, hard range cutoff, physical projectiles with lead | 🟡 (different) | M | Choose physical (current) vs statistical (EVE) hits |
| Shield / armor / hull, resists | Shield (socketed, never fitted by default) → hull; no armor, no damage types | 🟡 | M | `Object.cpp: ApplyDamage`, `Object/Shield.cpp` |
| Capacitor | Proportional power grid throttles modules; capacitor used for boost only | 🟡 | M | `Object/PowerGenerator.cpp` |
| E-war, drones | Drone bay launches a drone with an empty update | ❌ / 🔧 | L | |
| Hostile NPCs ("rats") | Pirates are decorative; `dogfight` has hunters; `Task_Pirate` is buggy | 🟡 | S–M | Lower HP, aim them at the player |
| Death, wrecks, loot, clones, insurance | Explosions; hulks left behind; no loot drop; "TODO: What if player dies?" | ❌ / 🟡 | M | `Component/Pilotable.cpp`, `Object/Pod.cpp` |

### Resources and industry
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Mining | Transfer-unit beam; yield depends on aiming at a hidden per-asteroid "phase" | ✅ | S (player) | Uncomment the plug in `ltheory.lts`. A fun mechanic worth keeping |
| Ore types | 9 procedural ores per universe | ✅ | S | Seed hard-coded to 190, so every universe has the same ores |
| Refining | — | ❌ | M | No mineral layer |
| Manufacturing | Chip → item; no material inputs; outputs hidden from AI by a `GetOutput` typo | 🔧 | L | `Game/Task/Produce.cpp`, `Item/AssemblyChip.cpp` |
| Blueprints, research, invention | Designed (research = mutating generator parameters, a good fit for ME/TE and invention) but never created | 🔧 | L | `Item/Blueprint.cpp`, `Task/Research.cpp`, `Mint.cpp` |
| Planetary industry | Colonies with markets and governors; production stubbed | 🔧 | L | `Object/Colony.cpp`, `Object/Colony.lts` |

### Economy
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Market order books | **Per-station buy/sell books, escrow via hangar lockers, 27-period price averages** | ✅ | — | `Component/Market.*`, ~250 lines. **The single best piece in the codebase** |
| Market UI | Browse, search, best bid/ask, quick buy/sell against the book | 🟡 | M | Missing: placing your own orders, "my orders", history, region scope |
| Regional markets, broker fees, contracts | — | ❌ | M | Each station is isolated |
| NPC economy | AI corps discover task chains and score them on market prices | 🟡 (half-broken) | M | Buy never bids, Transport moves nothing, 1 project per AI for life, O(stations² × items) rebuild every frame (05 §7, §9) |
| Goods sinks / NPC consumption | — | ❌ | M | Nothing ever leaves the economy |

### Ships and fitting
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Ship hulls | Infinite procedural hulls from (value, seed); class is a size label | ✅ | — | `Item/ShipType.cpp` + `Generate.lts`. No roles/bonuses; propulsion/systems/turrets multipliers are ignored |
| Modules | Procedural modules on the same value/seed model | ✅ | — | Item identity is per call, so identical parameters give different items |
| Fitting | Typed sockets, raycast-placed hardpoints, `Plug` API; free and instant; no unplug binding; no CPU/PG limits | 🟡 | M | Fitting UI absent (06 §4.2) |
| Hangar / cargo transfer | Per-owner station lockers (the market uses them) | 🟡 | S–M | No player UI to move ship↔locker |
| Ship purchase | AI buys ships; the player can't | ❌ | S–M | Sell `Item_ShipType` in markets |
| Docking, station services | AI teleport-dock; no player action or UI; no repair/insurance | 🟡 | S–M | `Task_Dock` is script-callable |

### World, factions, missions, progression
| EVE system | Here | Status | Effort | Notes / where |
|---|---|---|---|---|
| Universe generation | Universe → regions (circle packing) → systems; spanning-tree wormhole graph; grammar names; LTSL system recipe | ✅ | — | Planet always renamed "Melian Prime" (bug) |
| Factions / corporations | AI "players" act as corps with fleets and credits | 🟡 | M | No relations |
| Standings | Opinions written on attack, never read | 🔧 | M | `Component/Opinion.h` |
| Security space / CONCORD | — | ❌ | M–L | Could derive from region depth/distance |
| Missions / agents | AI posts bounty missions (paid in "damage evidence" items); no accept, turn-in or UI | 🔧 | L | `Game/Mission.cpp`. The evidence-as-proof design is good |
| Exploration / scanning | Spectral "D-scan" display with audio; no results, probes or sites | 🟡 | L | `Game/Signature.h`, `Object/Scanner.cpp` |
| Skills / training | — (tech-tree text files are never read; `Game/Attribute` is item stats) | ❌ | L | Design-heavy |
| Wallet | Credits | ✅ | — | |
| Save / load | Reflection and a serializer exist, unused for the world | ❌ | L | |
| Living universe (off-screen sim) | Only the current container ticks | ❌ | L | Prerequisite for jumps, regional economy and missions |

**Totals:**
- **Strong foundations:** order-book markets, procedural ships/modules/universe, mining, flight, AI corp planner (needs fixes), HUD/market/info UI, warp rails.
- **Thin or missing, and EVE's depth lives here:** industry, missions, skills, travel between systems, save/load, combat depth (armor, e-war, drones).

---

## 4. Cross-cutting risks and blockers

| Risk | Impact | Section |
|---|---|---|
| ~~**FMOD Ex 4.44**: proprietary, discontinued; the launcher can't start without it~~ | **Resolved (Oct 2026):** replaced by vendored miniaudio + stb_vorbis (public domain) behind the same `SoundEngine` interface. Missing sound files and missing audio devices are no longer fatal. The 4 FMOD music banks (`resource/music/*.fev/.fsb`) can no longer be played | 05 §7, 07 §5 |
| **LTSL silently drops lines that fail to compile**, often with no message and never a line number | The biggest day-to-day productivity cost; several "features" are silently off (`#` also comments out whole blocks) | 01 §6, 07 §1 |
| **Single-system simulation + no save + no fixed timestep** | Blocks a persistent EVE-like galaxy; deep changes to a tightly coupled world model | 04 §6, 07 §8 |
| **World model coupled to GPU, audio and scripts** | Can't simulate headless or off-screen without refactoring constructors | 04 §7 |
| **Unsafe threading**: plain refcounts, unguarded globals, script code on worker threads | Latent crashes; limits use of more cores | 01 §6, 03 §5 |
| **Legacy OpenGL 2.1 / GLSL 1.20** | Fine on Linux/Windows desktop; no macOS core/GLES path | 02 §6 |
| **Assets with unknown licences**: sound effects, music, some textures | Placeholder-only; fonts are clean (OFL/Apache/UFL); code is Unlicense | 07 §6 |

---

## 5. The two paths

### (a) Grow this codebase into the game
**For:** a great deal already works together: a living-looking system, a real market, procedural everything, a distinctive visual style, and fast iteration (hot reload, scripted UI). The first playable loop is cheap (§6).
**Against:** the expensive EVE pillars (galaxy simulation, save/load, industry, missions) need deep work in a world model that is tightly coupled and was frozen mid-refactor. You'd own a custom engine and language with no community or tooling, legacy GL, and unsafe threading. (The FMOD dependency has since been replaced.)

### (b) Take the designs into a new game
Carry over, roughly in order of value (details in each section's assessment):
1. **Order-book market** (04 §8b, 05 §9): port nearly verbatim.
2. **AI economic planner and task algebra** (tasks with inputs and outputs priced off markets; projects; `Task_LOD` off-screen idea).
3. **Procedural item model**: value/seed/multiplier curves in `Constants.h`, and research by mutating generator parameters.
4. **Universe topology + grammar naming** (region packing, spanning-tree gate graph, `Grammar.cpp` + `default.txt`).
5. **Procedural geometry**: PlateMesh hulls with raycast hardpoints, dual CPU/GLSL SDF asteroids, the AO bake (03 §7).
6. **Procedural shaders**: planet surface, nebula, per-system colour grade, irradiance chain, UI glyph/text shaders. Mostly mechanical ports to modern GLSL (02 §8).
7. **UI design as specs**: HUD layout, reticle, radial menus, Show-Info browser, market flow. The widget model maps almost 1:1 onto Godot's Control nodes (06 §8b).
8. **Small mechanics**: mining phase aiming, spectral scanner, warp rails, evidence-based bounties.

Leave behind:
- the component-mixin object model (use a real ECS)
- the containers, math, RNG and profiler (use std/GLM/Tracy)
- the C++ renderer framework
- the uncleared assets (FMOD Ex is already gone)
- probably LTSL itself: the reflection idea is worth keeping; the language is not

### Recommendation
**Do one short playable-loop milestone on this codebase first, then decide.** It's cheap: mostly LTSL and existing systems. It turns this static catalog into hands-on knowledge of the systems you'd carry over either way, and it tests whether the core loop is fun before you invest in either path. The real fork comes at the **living-universe milestone** (off-screen simulation, inter-system travel, save/load). That is where this codebase stops being cheap, so make the keep-or-port decision there, with the milestone's experience behind it.

---

## 6. Suggested first milestone: fly → mine → dock → sell → buy → fit

> **Status (Oct 2026): done and merged, except ship purchase (deferred: switching ships means rebinding the HUD and flight controls).** Mining needed two engine fixes: asteroid collision meshes only existed once drawn, and per-frame yields truncated to zero. The work also fixed a market escrow bug that created credits, and gave weapons a value. It adds LTSL line-numbered errors, a station panel, a fitting window, ore demand, pirates and respawn. `App/test_gameplay.lts` checks the loop end to end, and the screenshot and input harness (`docs/harness.md`) lets UI changes be checked visually. The fixed-timestep port is still open.

Mostly from 04 §8a, 05 §9 and 07 §8a:

1. **Prerequisites (C++, small):**
   - Advance `Universe::age`.
   - Throttle `ComponentEconomy::Run` to run every N seconds instead of every frame.
   - ~~Fix the FMOD init flags and fall back to the Null sound engine on error.~~ Done: FMOD was replaced by miniaudio, with a Null fallback.
   - Add line numbers and the disabled "no matching overload" messages to LTSL errors.
2. **Mining:** uncomment the transfer unit in `ltheory.lts`, and give the starting hull more cargo.
3. **Docking:** add a "Dock" radial action (`PushTask (Task_Dock station)`) and an undock action.
4. **Selling:** add deposit/withdraw between ship cargo and the station locker in the market panel. Seed station buy orders for ore in `Object/System.lts` so mining pays.
5. **Fitting:** add a fitting widget that plugs locker items, plus an `Object_Unplug` binding (`ComponentSockets::Unplug` exists). Optionally enforce a power budget.
6. **Ships:** sell `Item_ShipType` in station markets.
7. **Stakes:** spawn a few hostile pirates aimed at the player (pattern from `dogfight`), with respawn on death.
8. **Timestep:** port the 30 Hz fixed step with interpolation from `src/old/ltheory/ltheory.cpp`.

---

## 7. Quick-fix list (known bugs, mostly S effort)

Collected from all sections. Several are one-liners.

| Bug | Where | Section |
|---|---|---|
| `Universe::age` never advances (timestamps, knowledge expiry) | `Game/Universe.cpp` | 04, 05 |
| ~~FMOD init flags ANDed (=0); any FMOD error is fatal; no Null fallback~~ (fixed: FMOD replaced by miniaudio) | `Module/SoundEngine/Miniaudio.cpp`, `launch.cpp` | 05 |
| `GetOutput` typo hides Produce/Pirate/Spawn outputs from the planner | `Game/Task/*.cpp` | 04, 05 |
| `TaskBuy` never bids; `Transport` withdraw/deposit commented out; `Pirate` never re-targets | `Game/Task/` | 05 |
| Economy rebuilt every frame (O(stations² × items)) | `Component/Economy.cpp` | 04, 05 |
| Planet renamed "Melian Prime"; ore seed fixed at 190 | `Object/System.lts`, `Game/Universe.cpp` | 04 |
| LTSL struct padding wrong after `Bool` fields; script `Array` crashes after emptying; CRLF tokenizer bug | `LTE/Expression/Type.cpp`, … | 01 |
| Shader compile failure blocks on `getchar()` | `LTE/Shader.cpp` | 02 |
| `ShaderInstance::Clone` infinite loop with render-state switches | `LTE/ShaderInstance.cpp` | 02 |
| Window close button ignored; crash handler exits with status 0 | `LTE/Window.cpp`, `LTE/OS.cpp` | 03 |
| Release builds don't compile (`ProgramLog.cpp` calls undefined `GetWindow()`) | `LTE/ProgramLog.cpp` | 03 |
| Bounds checks effectively disabled (`DEBUG_BOUNDS_CHECK` defined in headers) | `LTE/Vector.h`, `Array.h` | 03 |
| `Widget_SendSiblings` sends to children; T key both recompiles shaders and targets | `UI/`, `App/widget.lts` | 06 |
| Hard-coded `../lt/` developer paths (DevPanel app list, FontPreview, text editor) | `resource/script/Widget/` | 06, 07 |
| SDF CPU `Evaluate` asserts for FractalWorley (asteroids): would abort on CPU picking | `LTE/SDF/` | 03 |

Already fixed this session:
- uniform cache keyed by pointer (`Shader.cpp`)
- cast-of-rvalue null deref (`Conversion.cpp`)
- non-script `Main` segfault (`launch.cpp`)
- AO bake GPU timeout (`PlateMesh.cpp`)
- generator job growth cap (`CubeMap.cpp`, `Texture2D.cpp`)
- the broken apps (developer Dropbox paths, `colony`/`threads` structure, `draw` right-click)
