# Roadmap: from the Limit Theory prototype to an offline EVE

## The plan on one screen

- **Move all game state and rules into an engine-free, deterministic Luau "Core".** The C++ engine becomes its view (renderer, generators, widgets, audio). They talk through commands and events, like EVE's client and server, in one process. This is what makes saves, a 400-system galaxy, headless tests and replays cheap.
- **Stop repairing the old C++ gameplay layer.** Pure-EVE rules replace almost all of it. It is frozen now and deleted after M2.
- **Rebuild the galaxy sim as stocks and flows plus the existing faction timers.** The hauler-level economy is the part that failed; the war layer is kept.
- **Ten milestones.** M0 tooling → M1 space → M2 fitting and combat → M3 one-system economy → M4 living galaxy → M5 missions and exploration → M6 full ship game → M7 fleets and corporation → M8 sovereignty → M9 unknown space and polish. M1–M4 are the game; M5–M9 are EVE's breadth.
- **Content is generated, not authored:** hull grammar with four lineages, structure toolkit, six planet kinds, composed icons, an event-driven effects layer, wired-up placeholder audio.
- **Every milestone has an unattended exit test.** The first work is making failures visible (crashes and script errors exit 0 today).

Scope note: this is years of work for a human team. Sizes below are relative, not calendar estimates.

## Status

| Milestone | State |
|---|---|
| M0 Solid ground | Done 2026-11-09, with two items moved (below). `script/check --soak` passes. |
| M1 Space | Exit tests pass (2026-11-10); polish items open (below). `bin/launch game` plays it. |
| S1 Economy kernel | Done 2026-11-10: `Core/Strategic/Economy`, 13 specs on toy graphs. |
| M2 Ships | Rules done and playable (2026-11-10); content, effects and tools open (below). |
| M3 One-system economy | Exit tests pass (2026-11-10); menus, research and content open (below). |
| S2 Galaxy-scale economy | Done 2026-11-10: `script/econsweep` passes on 16 seeds over 30 game days. |
| S3 Faction layer | Done 2026-11-10: `script/factionsweep` passes on 32 seeds over 30 game days. The prototype in `Sim/` is retired. |
| M4 onward, S4 onward | Not started. Parked behind the content pass (below). |
| Content pass | In progress since 2026-11-10. |

**Direction since 2026-11-10: content and visuals first.** After S3 the choice was between wiring the simulation into the game (M4) and a visual and content pass; the content pass was chosen, with this reason: simulating an economy of abstract goods before the things themselves exist is backwards. The game should first have the ships, stations, planets, resources, blueprints and weapons that an economy is made of, power by power. `Core/Strategic` is parked as it stands. When it is taken up again it is to run on the real item database, not on 27 abstract classes.

A related question, answered no for now: splitting the game into a server and a client so that the simulation can run on another machine. The whole strategic simulation costs about half a millisecond per ten-second tick, which is a few thousandths of a percent of one core; drawing is the heavy part and has to stay local. The Core already takes commands and gives events and runs with no window (`bin/ltcore`), so the split stays cheap to make if another reason for it appears (a universe that runs while the game is closed, say).

The pass, in order. Each step ends in something to look at (a gallery sheet read as a screenshot and kept as a golden image) or a spec.

| Step | What | State |
|---|---|---|
| C1 The item database | Four yards (styles of shipbuilding), two powers each. Each yard's line of hulls from frigate to battleship and an industrial; civilian and mining hulls. Turrets of three families and launchers, in three sizes, with their charges. Tank, propulsion and capacitor modules in three sizes. Ores by how safe the space is, and their minerals. A blueprint and skill requirements for everything. Original names throughout (the first items borrowed some). A spec that every item can be made from ore and every hull fitted. | Started |
| C2 Hulls | A hull grammar in script on the engine's plate meshes: a silhouette per yard and class, paint per power. A gallery app with every hull on one sheet. The game draws each hull as itself. | |
| C3 Places | Stations by kind (trade hub, shipyard, refinery, mining outpost, habitat, fortress, pirate den) in each yard's style; a gate that looks like a gate; six kinds of planet; asteroids that show their ore. Sheets for each. | |
| C4 Fights and work | Weapons that fire what they are (beam, bolt, slug, missile), hits by layer, explosions by size, wrecks that are wrecks, a mining beam. | |
| C5 The interface for it | Item icons, an information window with attributes, the market and hangar grouped by kind, a ship tree by yard. | |

**M1 as built.** The Core flies the loop headless (`Core/Api.spec.luau`): undock, align and warp on schedule (a frigate covers 20 AU in 22 s), approach, orbit, keep at range, jump, dock. The game app shows it: grid objects at true size, planets and moons in scaled space, sunlit hulls, brackets, overview, selected-item orders, navigation bar, time controls, save and load. `script/check` flies it through the app, including a save in mid-warp that reloads to the same state hash. Fifty jumps leave memory flat.

**M1 items still open** (none blocks M2):
- UI toolkit depth: the interface is immediate-mode on the existing draw calls (`Game/UI/Im`), which carries the overview and brackets. Not yet done: batched text drawing in C++ (U1), sortable columns, context menus, a window manager, hotkeys.
- Camera: orbit only. Tracking and tactical cameras are not built.
- Warp looks like a wider field of view and a banner; no tunnel or streak effect yet (F21, F22). Gates use a station model (W8).
- The scene still uses the engine's old System and Ship objects as props. A lean scene container and proxy type (E6, E10) and the scaled-space depth pass (E8) wait until they are needed: the script-side version works at this scale.
- The old demo apps and `ltheory` are still in the tree.

**What M1 found:**
- The view needs no C++ for ship motion at this scale. Placing a few hundred ships from Luau each frame costs well under a millisecond, so the kinematic mode (E4) is deferred.
- Three engine behaviours to know: the camera's "relative" position is absolute; generated models are not centred on their origin; a ship whose scale is changed after creation is not drawn (hulls are generated at size instead).
- Metal had no direct sunlight; adding it (R1) was a two-line shader change and the largest visual gain so far.
- The tick is integrate, apply commands, decide. Each ball stores the velocity it steers toward, so the state at a tick fixes the next second of flight and the view never has to correct itself.

**M2 as built.** In the Core: hull and module data, the attribute engine with stacking penalties (`Core/Dogma`), items in hangars, holds and racks with fitting rules (`Core/Assets/Items`), locking, module cycles, turret and missile formulas, layered damage, capacitor and recharge (`Tactical/Gunnery`, `Tactical/Combat`), and what follows a fight: wrecks, loot, bounties, insurance, the capsule and repairs (`Tactical/Aftermath`). Pirates arrive at belts and fight with the same orders a player gives (`Tactical/Pirates`). The formulas are checked against hand-computed numbers and fights are played headless (hit rate and damage per shot match the formula over 170 shots). In the game: a fitting screen while docked; ship status, module rack, target list, lock and loot orders in space. `test/scenario/combat.txt` plays it through the app: fit by clicking, fight a pirate, collect the bounty, loot the tag, lose the ship, get home in the capsule.

**M2 items still open:**
- Content: 5 hulls, 20 modules and 9 charges so far, of the planned two lineages of frigates and destroyers and about 60 modules. Pirates come one or two at a time and are all scouts.
- Effects: a shot is a line drawn on the interface and an explosion is the engine's stock one. Turrets do not track or fire, there are no impact effects per layer, and a wreck is a lump of rock (E9, F1 to F20).
- UI: no drag and drop, no item information window, the tank readout is bars rather than a wheel.
- Tools: no balance report, effect previewer or hull gallery yet.
- `App/ltheory.luau` and the old C++ gameplay are still in the tree (E14).

**What M2 found:**
- A weapon that cannot reach its target is the common beginner's death: pirates spawn outside a starter ship's targeting range, and a pilot who does nothing until they arrive loses. The scripted scenario had to learn to wait for range.
- A ship cannot orbit tighter than its speed and agility allow: an afterburning frigate told to orbit at 600 m settles kilometres out, which is right, and makes close orbits a property of the hull rather than of the order.
- Resolving a tick's shots together before applying damage costs nothing and removes any advantage from ship id order.

**M3 as built.** In the Core: mining lasers that deliver a cycle's ore, four ores, belts that regrow, and refining (`Tactical/Mining`, `Assets/Industry`); a market at every station with trades at once, standing orders with escrow, a broker's fee, sales tax and trade history (`Assets/Market`, on the S1 kernel); hulls to buy, assemble and board (`Assets/Hangar`); a blueprint for every module, charge and hull, and timed manufacturing jobs; 25 skills that gate hulls and modules or improve the ship, mining, refining, building and trading, learned from books and trained through a queue (`Data/Skills`, `Character/Training`); a wallet journal. In the game: the docked screen has tabs for fitting, market, industry, skills, ships and wallet (`Game/UI/Station`).

Two unattended tests are the exit. `Core/Loop.spec.luau` plays the whole loop headless with nothing handed to it: a new pilot mines, refines, builds 13,900 rounds, sells them by standing order, trains, fits a second mining laser, and is aboard a Lancer after 2.9 game hours. `test/scenario/economy.txt` plays each link through the game's own screens: mine a hold, refine, build from the blueprint, sell by order, buy and assemble a Lancer, find it cannot be flown, train Frigates 2, board it. (There the hull's price is granted; earning it is the headless test's job. The roadmap asked for a destroyer, and there are none yet, so the hull is the Lancer.)

**M3 items still open:**
- Main menu, new game, load and settings screens: the game still starts straight into a new game, with quick save and load on the docked screen.
- Blueprint research and copies; jobs cannot be cancelled.
- Skills: 25 of the planned 40. There are no attributes or implants, and training speed is the same for everyone.
- Market screen: no depth view or history chart; history is the last three days as text. An order's price cannot be changed, only cancelled.
- No assets view across stations: what is in another station's hangar can only be seen there.
- View: a mining laser has no beam, and every ore looks the same.
- The station markets stand alone: each has a fixed normal stock that an unsimulated wider world restores at a quarter of the gap an hour. S2 and S4 replace this with stocks that flow between systems.

**What M3 found:**
- The first order rule had an exploit. An order that fills while the station "would pay at least that" lets a trader buy one unit in a thin market, wait for the wider world to restock, and sell it back higher, for nothing. The rule that holds prices each fill off the stretch of the price curve that unit covers: then any path that returns the stock to where it began gains at most the two spreads, which the fees exceed. A spec plays three round trips with the best skills and requires a loss every time.
- Market depth has to be set against what one pilot produces. At the first setting a lone miner pushed a station's ore price to a third within a few hours, and an ammunition line could sell 300 rounds an hour. Raw materials and ammunition are now deep markets; modules and hulls stay thin, so selling a third hull to one station is slow.
- Skills that gate the starter kit make a first lesson without a tutorial: three of the modules in the first hangar are a minute's training away, and a second mining laser needs CPU Management 2.
- The interface is a frame behind the game, so a scripted run that presses a button the moment the state changes finds it still greyed out. Scripts wait for the button itself (`until GameDebug.Press(...)`).
- Jobs and blueprints live at a station. The scripted pilot docked at the nearest station instead of home and found nothing to build with: which is right, and is what an assets view is for.

**S2 as built.** `Core/Data/Goods` is 27 classes of goods in seven tiers and the 28 steps that make them; every price is rolled up from inputs, labour and a 15% margin. `Core/Strategic/Atlas` turns a galaxy into an economy: eight powers grown from homeworlds with the far fifth of systems unclaimed, security falling with distance from home, population, resources, and industry sized to what the galaxy's people use plus 35% slack. `Tool/econrun` runs it and `Tool/EconProbe` judges it on thirteen measures; `script/econsweep` does that for 16 seeds over 30 game days, and `script/check --soak` includes it. All 240 verdicts pass:

| Measure | 16 seeds | Limit |
|---|---|---|
| Needs met, by head | 0.942 to 0.962 | at least 0.92 |
| Needs met, worst-served tenth of systems | 0.890 to 0.918 | at least 0.75 |
| Price level against normal | 1.05 to 1.10 | 0.85 to 1.2 |
| Share of supply through homeworld anchors | 1.1% to 2.5% | at most 10% |
| The class anchors supply most | 6% to 12% | at most 25% |
| Industry in use | 0.67 to 0.71 | 0.5 to 0.95 |
| Stocks at the price ceiling or floor | none | at most 2%, 5% |
| Lanes that would pay a trader 5% a jump | 48% to 65% | at least 10% |
| Lanes short of haulage | 0.3% to 0.5% | at most 3% |
| Time a simulation tick | 0.4 ms | at most 1 ms |

The limits are the opening proposals from §6 made concrete; two were replaced during the work, and why is below. A trader's 5% is before their own costs and risk, and is mostly bulky raw material in lawless space.

**What S2 found:**
- The design ran at galaxy scale on the first attempt: books balanced, nothing starved, prices settled. What took the work was how well supplied people are, and each fix was to the model, not the limit.
- A lane's cost is a share of the goods' price, so at first hauling ore cost the same share as hauling electronics. Frontier mines sat idle behind a few lawless jumps while homeworld anchors supplied a third of the rare ore, ice and gas. Classes now carry a bulk: raw materials cost 1.6 times a lane's rate, finished goods 0.6.
- Industry has to cluster. With every stage placed by population alone, each stage sat several jumps from the last and finished goods ran 17% over normal. Placing half of each step's capacity where its inputs are made brought that to 7% and let the anchors be confined to the goods people use: raw materials and parts now come only from space, and anchors supply 2% of everything instead of 6%.
- Small works matter. Dropping the facilities that are under a thousandth of a step's capacity made people 2% worse supplied to save 10% of the time.
- Homeworld anchors that sell raw materials hide the problem they solve. The run without them is what showed that frontier capacity was stranded.
- The limit on "lanes that would pay a trader" started as a band. Its upper end was measuring nothing: it is replaced by "lanes short of haulage", which is what an economy whose flows have failed would show.
- Goods cross one lane a step, so the one-minute step is the speed of trade, not only a cost. Longer steps stay stable but supply people less well (30-minute steps: needs met 0.93).
- The scripts were running three times slower than they should. The VM was never told that the built-in functions are not replaced, so every `math.sqrt` was a table lookup and a full call. Both hosts now say so, compile with inlining, and compile modules marked `--!native` to machine code. The economy went from 12.7 ms a step to 1.9; all specs, scenarios and goldens are unchanged.

**S3 as built.** `Core/Strategic` now holds the whole strategic simulation, on the S2 economy, and `Core/Data/Powers` every number it is tuned by. A world starts at the founding: eight powers on their homeworlds, everything else independent, pirate dens in the far reaches.
- **Money** (`Fiscal`): a power's only income is a levy on what its people spend, in proportion to how well they are supplied and how firmly it holds them. It pays for holding systems (more with distance from the capital, and as the square of how many it holds), policing, crews, and the fuel and ammunition its fleets use, bought on the market where each fleet lies. Hulls and fittings are bought on the capital's market at its prices. Every credit that moves is in a double-entry ledger with a reason.
- **Fleets** (`Orders`, `Battle`): a minute a jump; nobody slips past an enemy fleet. A battle is fought a round a minute by the square law, and a side under half of what it faces pulls out. A siege is three stages over an hour (cut off, defences fought down, occupied); claiming an independent system is the same, shorter, and takes construction kits. A fleet abroad lives on a day's supplies.
- **Order** (`Order`, `Raiders`): piracy is a pressure in every system, raised by dens and lawlessness and pushed down by policing and garrisons. With the owner's control it gives each system's security, which sets what its lanes cost, what pirates take on them and how much they carry; war, an embargo or a siege closes a lane. The pirates' organisation lives on a cut of that and on raids, and spends it on bands and new dens.
- **Diplomacy**: relations settle where traits and borders put them and are knocked about by random incidents; a war starts when relations are bad and one side judges it can win. A power that attacks a clearly weaker one while well above average frightens the rest into embargo, then subsidy, then war. Peace is proposed and judged by one function whoever proposes: terms follow a score of what was taken and lost, and each side signs sooner the wearier it is.
- **Government** (`Mind`): budget, build, expand, attack, defend, hunt dens. It acts only through the orders a player ruling a power would have.

`Tool/factionrun` runs it and `Tool/FactionProbe` judges it; `script/factionsweep` does that for 32 seeds over 30 game days (in `script/check --soak`, with a save-and-load soak of eight histories over four and a half days). All 640 verdicts pass:

| Measure | 32 seeds | Limit |
|---|---|---|
| Powers alive at the end | 8 of 8, every seed | at least 6 of 8 |
| Largest power's share of systems | 9% to 19% | at most 45% |
| Power-time in arrears | none | at most 5% |
| People living under a power | 80% to 91% | at least 70% |
| Systems claimed | 48% to 66% | 35% to 90% |
| Wars declared in 30 days | 8 to 59 | at least 2 |
| Power-time at war | 1.6% to 16% | 1% to 60% |
| Systems taken or ceded in war | 16 to 118 | shown, not judged |
| Warning of a capture, median | 72 to 84 minutes | at least 45 minutes |
| Needs met, by head | 0.938 to 0.961 | at least 0.88 |
| Price level against normal | 1.05 to 1.10 | 0.85 to 1.3 |
| Goods lost to pirates, share of trade | 0.16% to 0.41% | 0.05% to 2% |
| Books: credits and goods | no residual | none |
| Time a tick | 0.4 to 0.9 ms (eight runs at once) | at most 5 ms |

The first three are the roadmap's thresholds; the rest are mine, to catch a dead or a broken galaxy. Three runs of 90 game days (seeds 1, 5, 6) end with all eight powers alive; the largest holds 15% of the systems and up to 35% of the people, and in two of the three a power has been cut back to its homeworld.

**S3 items still open:**
- Over 90 days power still concentrates, slowly: one power comes to hold up to a third of the people, and a loser can be cut back to its homeworld, where it survives. A power that is eliminated never returns, and a beaten one recovers only by its own income. There is no revolt or liberation.
- Coalition members fight side by side but not together: each plans its own attacks and defends only its own systems.
- Governments keep their free fleets at the capital. Nothing is garrisoned for long, and nothing escorts anything.
- Sieges are of systems; there are no structures to shoot yet, and industry is not damaged by war.
- The warning the roadmap asked for was "a median near 45 minutes". It is about 78: a siege alone is an hour. The check is "at least 45".
- The HTML report was written for the prototype's series and went with it. `factionrun --out` writes the new series as CSV; a report on them is to do.
- The parity test (an NPC power driven only through the player's interface) is stage S8. The interface exists; the test does not.

**What S3 found:**
- The civil economy is about a thousand times a power's budget: the galaxy's people spend 61 million credits an hour, and a power lives on about 50,000. Anything defined as a share of trade swamps the powers. The first pirates took 2% of trade at the price of the goods and were forty times richer than every power together in two days; the organisation now gets a small cut and a raid carries off what its ships can hold.
- Spending rules have to rank investments. The first governments put every spare credit into frigates the moment it arrived and never saved the price of a claim; expansion ran at a tenth of the planned pace until claims could earmark money the yards may not touch.
- An empire has a natural size, and it is set by the cost of holding systems. With that cost linear in the number held, one power took two others' homeworlds and reached 85 systems in a month, profitably. With it rising as the square, and with conquests on another living power's ground paying half, the largest power in any of 32 seeds holds 19% of the map, and what a war takes tends to drift back afterwards.
- Relations that only drift settle. Under the first rule each pair came to rest at a level its border set, usually just above the threshold of war: two seeds in eight had no war in thirty days, the rest had the same pairs fighting daily. Random incidents between neighbours, a declaration that needs a judgement of strength as well as bad blood, and longer truces gave every seed wars and none a forever war.
- Three to one over everything means nobody of similar size ever attacks. The rule that works is three to one over a system's own defences plus a margin over the fleet its owner can bring; a bold power takes a smaller margin and sometimes loses the battle, which is where most ships are lost.
- A power must not start a war it has nothing to do in. Under the first rule (declare when relations are bad and the fleet is a match) one power declared on the same neighbour six times in a month and never fired a shot: it faced that neighbour across a system neither owned and had nothing next door to attack. A government now declares only if it can see a system it could take, and can attack across one empty system.
- A homeworld is two fifths of a power's people. While it could be taken like any system, losing it ended a power in all but name. Its defences are now ten times a system's of its size.
- Ownership at the start is the original decision (homeworlds only), not S2's settled map. The powers fill their natural parts of the map in about two days, and about half the systems, the poor far ones, stay independent: they cost a distant empire more than they bring, and would pay a small local power.
- The save had one shared table in it (the atlas and the economy both held each system's tastes), which the codec refuses. The reload test found it on its first run.

**What S1 found:**
- The first flow rule had its own deadlock: a node starved to zero could never be resupplied. The blockade test caught it. Flows now close a price gap exactly on the true curve.
- Idle stock has honest hysteresis: goods nobody at a node uses stay there if carrying them back is not worth the trip. Working markets return to the same prices after a blockade.
- A lone trader on thin lanes profits every day at about a 30% margin: the rent that capacity-limited routes were meant to leave.

**Moved out of M0:**
- The in-game console overlay and its cheats (spawn, give item, set skill, teleport, advance time) need the Core's ships, items and skills and the new UI toolkit, so they land in M1–M2. M0 delivers the plumbing: `bin/launch APP --console` (a Luau prompt in the terminal) and the harness command `lua CODE`.
- "Ordered containers replace hash iteration" was done for fleets and actions, which is where the sim actually diverged. The prototype's other map loops are left for S1–S3, where that code is rewritten; the soak guards them meanwhile.

**What M0 found:**
- The sim did depend on map order: one seed in five gave a different history after a save and load (a battle at tick 3961 assigned losses to different fleets). After the fix, eight seeds match over 6,000 ticks with a reload every 97.
- The prototype fails the new sweep on all eight seeds: faction credits fall at about 130% of their level per game day, warships likewise, and station maintenance is about 45% met. That is the baseline the new economy has to beat (`script/simsweep` and `script/simreport`, both retired with the prototype in S3).
- This machine gives the engine an OpenGL 4.6 compatibility context, so instancing and newer GLSL can be mixed in without a renderer port (E11, E12).
- A 1.8 MB sim state saves and loads in about 130 ms in Luau. Fine for autosave on dock or jump; a C encoder is the fallback if it ever hitches.
- With the screen asleep the desktop holds each buffer swap for about 460 ms, which cuts any window to two frames a second. Scripted runs use `--no-present`.
- The engine builds as C++17 and the LTSL runtime is gone (about 4,700 lines).

The commands are listed in `docs/tools.md`; the rules for Core code are in `docs/design/core.md`.

## 1. Context

The repo is the revived Limit Theory engine with a one-system prototype on top (`App/ltheory.luau`: fly, mine, dock, sell, buy, fit, two pirates, respawn) and an unconnected headless faction sim (`resource/script/Sim/`, branch `universe-sim-design`). The goal is a single-player, offline game whose systems roughly match EVE Online. Work stalled when the sim's hauler-level economy kept collapsing and the direction was reopened.

This roadmap replaces the earlier ones (`docs/catalog/00-overview.md` §3–6 and its "decide later" fork). It rests on these decisions:

| Decision | Source |
|---|---|
| Pure EVE-style flight and combat: commands only, statistical hits, direct piloting removed | owner, 2026-11-09 |
| Player ceiling: pilot → fleet → corporation with employees and stations → sovereign faction | owner, 2026-11-09 |
| Personal project: Linux only, placeholder assets fine, no packaging | owner, 2026-11-09 |
| Sim architecture is the roadmap's call | owner, 2026-11-09 |
| Stay on this engine; scripts in Luau | earlier sessions |

## 2. Where we are (verified 2026-11-09)

**Works:** one generated system; WASD flight; mining; teleport docking; fill-only market against per-station order books; fitting of weapons and transfer units; two script-spawned pirates; free respawn; a scripted screenshot/input harness; strict Luau type checking; a deterministic headless faction sim (wars, sieges, coalitions, peace) at ~4.5 ms per tick.

**Structural limits:**
- Only the player's container updates; other systems are frozen. All systems are generated eagerly with GPU work and never freed (~200–400 MB of cubemaps each).
- No save. The reflection serializer cannot store Luau state and breaks on any field change.
- The object model is closed: a compile-time mixin chain, so volume, damage types, standings and so on each need engine edits.
- Positions are double, but collision, the spatial grid, ray queries (100 km cap), script vectors and the far plane (1e6) are float-limited. Systems are ~1e6 units wide.
- Variable timestep; time compression is one big step.
- The C++ gameplay layer (tasks, AI planner, items) is half-disabled and buggy: `Task_Play` project switching off, `Transport` moves nothing, `GetOutput` typo, every weapon is a pulse.
- Tooling: no headless mode, crashes and script errors exit 0, tests print instead of asserting, no CI.
- Content: one hull archetype, one station archetype, one planet type, three asteroid meshes, one material; 44 vector icons; 130 sounds (45 used); no playable music.

**The pure-EVE decision changes the cost picture.** Command flight and statistical combat need no physical projectiles, no triangle collision and no hand-flying physics. Most of the weak C++ gameplay layer becomes unnecessary instead of needing repair.

## 3. Architecture: an authoritative Core with the engine as its view

All game state and rules live in `resource/script/Core/`: pure Luau, no engine calls, deterministic. The engine draws what the Core says. NPC AI issues the same commands as the player, which is what later lets wingmen, employees and a player faction reuse one command path.

**Why not the alternatives**
- *Extend the C++ object layer:* fails on saves, galaxy-wide simulation and headless testing. Constructors do GPU and script work, gameplay data sits in reference cycles, and pure-EVE rules replace nearly all of it anyway. The one strong piece, the market, is 246 lines.
- *A new C++ core:* buys speed that isn't needed and costs a store, bindings, a serializer and a test host in the slow-iteration language.

**Luau is fast enough.** Measured on 2026-11-09 in the standalone Luau VM (synthetic loops, 8 modules per ship):

| Work per 1 s tactical tick | 300 ships | 1000 ships |
|---|---|---|
| Movement with orbit steering | 0.05 ms | 0.16 ms |
| Module cycles, hit resolution, layered damage, one event per shot | 0.28 ms | 1.0 ms |
| Naive all-pairs nearest-hostile scan (the one trap; use persistent locks and a cell hash) | 1.6 ms | 17.7 ms |

The strongest argument against: every rule runs in one single-threaded VM. If a later system needs tens of thousands of agents per tick, hot loops move to stateless C kernels over Luau buffers; plain-data state keeps that door open.

**Core modules**
| Module | Responsibility |
|---|---|
| `Kernel` | Root state, ids, RNG streams (existing `Sim/Rng`), ordered map and set, command queue, event buffer |
| `Data` | Type database: hulls, modules, goods, skills, factions |
| `Describe` | Galaxy and system layout as data (from `Sim/Galaxy`) |
| `Tactical` | Grids, movement and warp, locks, attribute engine, module cycles, hit and damage, NPC AI, wrecks |
| `Strategic` | Factions, economy, diplomacy (from `Sim/*`, §6) |
| `Lod` | The bridge: promote strategic entities to balls on grid and demote them back |
| `Assets` | Items with volume, containers, ships, fits, wallets, order book (port of `Component/Market.cpp`) |
| `Persist` | Binary codec, save, migrations, command journal, state hash |
| `Api` | `New`, `Load`, `Save`, `Submit`, `Validate`, `Step`, `Events`, `Query.*` |

The view lives in `resource/script/Game/` (`Clock`, `View/Scene`, `View/Proxies`, `View/Celestials`, `View/Effects`, `View/Camera`, `UI/*`).

**Rules of the Core**
- State is plain data: no functions, metatables, engine values or cycles; references are ids. Money and quantities are integers; time is integer ticks; units are SI.
- Commands are plain tables (`Approach`, `Orbit`, `KeepAtRange`, `AlignTo`, `WarpTo`, `Dock`, `Undock`, `Jump`, `LockTarget`, `ActivateModule`, `MoveItems`, `Fit`, `PlaceOrder`, …). `Validate` returns ok or a reason, and the UI uses it to grey out actions.
- Events (`BallAdded`, `WarpStarted`, `Shot{src, slot, dst, outcome}`, `BallDestroyed`, `OrderFilled`, `News`, …) are transient and only drive one-shot effects and sounds. The view must be rebuildable from a state snapshot alone.
- Determinism: never iterate hash tables in rule code (order changes after a save and load; the prototype does this in ~24 places); no tables or functions as keys; no `math.random` or `os.*`; total-order sort comparators.

**Space model**
- Systems at astronomical scale. Positions are three doubles in system space, never Luau `vector` (float32).
- Grids are anchored to sites (station, gate, belt, warp-in point). A warp landing inside an existing grid's radius joins it.
- Movement is EVE's: velocity relaxes exponentially toward a target velocity. That has a closed form, so the engine evaluates the same formula each frame from one `Object_SetBallState` call per ball per tick. No per-frame script calls, and no correction at tick boundaries.
- Tactical tick 1 s, as a named constant (0.5 s is tried for feel in M1). The strategic tick runs every tenth tactical tick.
- Planets, moons and the sun are drawn first in scaled space (placed at `direction × D'` with radius scaled to match), so the far plane and every float-limited system stay as they are. The engine only ever holds one grid.
- One scene exists at a time. Leaving a system deletes it; with no gameplay references in view objects the existing reference cycles never form.

**Per frame:** scale and accumulate time → UI submits commands → while a tick is due, `Core.Step` (apply commands, strategic tick if due, bridge arrivals and departures, NPC decisions, movement, locks, modules and hits, deaths, emit events) → on tick frames the view consumes events and pushes ball states → engine update → draw.

**Saves and replay**
- `save/<slot>/` at the repo root (git-ignored; `cache/` is wiped by `configure.py clean`): `meta.json`, `state.bin`, `journal.bin`. Written to a temporary file, then renamed. Rotating autosaves.
- Stored: seeds, tick, id counter, the system descriptions, all strategic state, player assets, live grids, belt depletion, wrecks. Regenerated: all visuals.
- Versions: save schema, content data, generator. Migrations are ordered pure functions, checked against golden saves.
- Replay: seeds + data version + command journal → state hash every N ticks. The test that exists from day one: run N ticks; save and load into a fresh VM at tick k; the final hash must equal an uninterrupted run.
- F5 keeps the game: stash the state buffer across the script reload and rebuild the view.

## 4. Gap map: EVE's systems against today

Milestones (M0–M9) are defined in §5.

### Space and travel
| EVE system | Today | Needed | When |
|---|---|---|---|
| System layout at astronomical scale | One ~1e6-unit system: 1 planet, 2 fields, 2 outposts; no moons or gates | Star, planets, moons, belts, stations, gates at AU scale; grids; far-field rendering | M1 |
| Command flight (approach, orbit, keep range, align, stop) | Player has WASD only; AI has `Task_Goto` | Ball movement in the Core; commands from overview, context menu and hotkeys | M1 |
| Warp | Align-then-lerp inside `Task_Goto`; no UI | Warp to any celestial or bookmark at a chosen range; speed by hull; capacitor cost; tunnel effect | M1 |
| Docking | Teleport dock and undock work | Docking range, hangar view, undock vector | M1 |
| Stargates and jumps | Wormhole teleport stub; inter-system `Goto` empty | Gate objects, jump with system unload and load, post-jump cloak | M1 two or three linked systems · M4 galaxy |
| Star map, route, autopilot | System map only | Galaxy and region map, shortest/safest route, autopilot | M4 |
| Security space and police | Absent | Security level per system from the sim; sentry guns; police response; aggression timers; security status | M4 |
| Bookmarks | Absent | Saved locations | M5 |
| D-scan, probes, signatures | Cosmetic spectrum widget; scanner disabled | Directional scan, probe scanning, anomalies and signatures | M5 |
| Jump drives, cynos, jump bridges | Absent | Capital travel | M8 |
| Wormholes | Shader and teleport stub | Shifting connections, unknown space | M9 |

### Ships and fitting
| EVE system | Today | Needed | When |
|---|---|---|---|
| Hull classes with roles and bonuses | Procedural (value, seed); class is a size label | Type database of hulls with slot layouts, bonuses, lineage style | M2 frigates and destroyers · M6 to battleship · M8 capitals |
| Attribute engine ("Dogma") | None; stats are formulas in C++ constructors | Attributes, modifiers, stacking penalties; skills, modules, implants and boosts all modify the ship | M2 |
| Slots, CPU, powergrid | Typed sockets, no limits | High/mid/low/rig slots, turret and launcher hardpoints, fitting rules | M2 |
| Capacitor | Proportional power grid; used for boost only | Capacitor pool, recharge curve, module costs | M2 |
| Shield, armor, hull, four resists | Shield (never fitted) then hull; one damage type | Three layers, EM/thermal/kinetic/explosive, repairers and hardeners | M2 |
| Turrets, missiles | Pulse only; beam `#if 0`; missile and rail unreachable | Three turret families and missiles, with ammo and reload | M2 |
| Drones, smartbombs | Drone bay launches an inert drone | Drone control, bandwidth, bay | M6 |
| E-war and remote assistance | Absent | Web, scram, disruptor, ECM, damp, tracking disruptor, painter, neut; remote repair and cap | M6 |
| Propulsion modules, cloaks, rigs, overheating | Absent | Afterburner, MWD, micro jump drive; cloak; rigs; heat | M6 |
| Tech 2, faction and meta tiers | Absent | Tiers in the type database; invention | M6 |

### Combat
| EVE system | Today | Needed | When |
|---|---|---|---|
| Target locking | Instant list | Lock time from scan resolution and signature; max targets; range | M2 |
| Hit resolution | Physical projectiles | Turret tracking formula; missile application formula | M2 |
| NPC pirates | Decorative 1e9-HP ships; two script-spawned hunters | Spawns from pirate pressure; orbit-and-shoot AI, target switching; later e-war and logistics | M2 basic · M4 sim-driven · M6 advanced |
| Death, pod, clone, insurance | Free starter ship | Pod, clone at home station, insurance, implant loss | M2 basic · M6 full |
| Wrecks, loot, salvage | Hulks, no loot | Wreck with loot roll; salvager and tractor | M2 loot · M5 salvage |
| Aggression flags, bounties | Absent | Timers and flags; bounty payouts | M4 |

### Industry and economy
| EVE system | Today | Needed | When |
|---|---|---|---|
| Mining | Beam with phase aiming; rocks never respawn | Cycle-based mining modules, ore by security level, belt regeneration; ice, gas, moon | M3 ore · M6 ice and gas · M7 moon |
| Reprocessing | Absent | Ore to minerals with yield | M3 |
| Manufacturing and blueprints | AI-only stubs | Originals and copies, material and time efficiency research, timed jobs | M3 |
| Invention, reactions | Absent | Tech 2 chain | M6 |
| Planetary industry | Colony stubs | Extractor and factory network | M6 |
| Order-book market | Per-station books with escrow in C++; player can only fill orders | Port to the Core; player limit orders, modify and cancel, fees and taxes, history | M3 |
| NPC supply and demand | Seeded once, never restocked | Derived from the strategic sim; regional price differences, shortages | M4 |
| Contracts, courier | Absent | Courier and item-exchange contracts with NPC counterparties | M6 |
| Wallet journal | A credits number | Ledger of every faucet and sink | M3 |

### Character and world
| EVE system | Today | Needed | When |
|---|---|---|---|
| Skills and training | Absent | Skill books, queue, prerequisites, training time tuned to play sessions | M3 core set · M6 full tree |
| Implants, boosters, jump clones | Absent | | M6 |
| Standings | Opinions written, never read | Faction, corporation and agent standings affecting prices, access and aggression | M4 faction · M5 agents |
| Factions, sovereignty, wars | Only in the Sim prototype | Strategic sim wired into the game | M4 |
| Agents, missions, loyalty points | AI bounty listing with no UI | Missions generated from sim state | M5 |
| Exploration sites, hacking | Absent | Combat, data, relic, gas and ore sites; escalations | M5 |
| Fleets | Absent | NPC wingmen under player command | M7 |
| Corporation | Absent | Employees with standing orders, corporate assets, owned structures | M7 |
| Player sovereignty and war | Absent | Player faction in the strategic sim; sieges; diplomacy | M8 |
| World events | Absent | Pirate surges, invasions | M9 |

### Meta
| System | Today | Needed | When |
|---|---|---|---|
| Save and load | Absent | Versioned Core-state serializer; every Core module round-trips | M1 onward |
| Time control | Hold H for ×20 | Pause with queued orders; ×1–×N acceleration | M1 basic · M6 polished |
| Main menu, settings, key bindings | Backend only | New game, load, settings and rebinding screens | M3 |
| Onboarding | Absent | Career-agent tutorial | M9 |

## 5. Milestones

Each milestone ends in something playable, with an exit test that runs unattended. Sizes are relative (M < L < XL) and are judgement, not measurement. M1–M3 make a complete one-system EVE; M4 makes it a living galaxy and is where the game gets its identity; M5–M9 add EVE's breadth.

The strategic sim (track S) is engine-free, so it is rebuilt headless in parallel from M0 and joins the game at M4.

### M0 — Solid ground (M)
- Failures become visible: script errors, asserts and crashes exit non-zero (E1).
- `bin/ltcore`, the windowless Core host (E2); the Core type-check boundary (E3); a test kit with assertions; one `script/check` command running type check, Core tests, replays and harness scenarios.
- Golden-screenshot runner (T6), with a fixed-timestep harness flag and a seeded global RNG.
- Determinism groundwork on the prototype: ordered containers replace hash iteration; the save–load–continue hash test.
- Sim instruments (S0): ledger, recorder, seed sweep, HTML report.
- Dev console (Luau prompt) with cheats: spawn, give item, set skill, teleport, advance time.
- Remove LTSL and dead subsystems; C++17 (E13).
- Write `docs/design/core.md` (the conventions in §3) and the type-database skeleton shared by both tracks.
- **Exit:** `script/check` passes, and fails with a non-zero status on a planted script error, a planted failing assertion and a planted segfault; the prototype sim runs in `ltcore` on 8 seeds in parallel; the save–load–continue hash test passes.

### M1 — Space: undock, warp, orbit, dock (XL)
- **Core:** kernel and persistence with the round-trip test first; two or three AU-scale systems described as data (star, planets, moons, belts, stations, gates); grids and balls; all navigation commands (stop, go to direction, approach, orbit, keep at range, align, warp to, dock, undock, jump); clock with pause and acceleration; event stream.
- **Engine and view:** kinematic ship proxies; scene built from the description and torn down on jump; scaled-space celestials with a directional sun; orbit, tracking and tactical cameras; brackets; first warp tunnel.
- **UI:** toolkit first pass (batched drawing, store, virtualised sortable table, context menus, window manager, bracket layer); overview; selected-item panel; navigation HUD; station panel.
- **A new app** (`App/game.luau`) beside `ltheory`; the two never share state. WASD flight is not carried over. Warp-rail visuals are kept for later use as acceleration gates.
- **Exit:** a harness scenario undocks, warps 30+ AU to a belt, approaches and orbits a rock, jumps to the next system, docks; a save taken mid-warp reloads to an identical state hash; align and warp times match the formulas in Core tests; 50 jumps leave the live-object count and VRAM flat.

### M2 — Ships: fitting and combat (XL)
- **Core:** type database v1 (frigates and destroyers of two lineages, ~60 modules, ammo); attribute engine; inventory with stacks, volume and containers; fitting rules; capacitor; module cycles; locking; turret and missile formulas; layered tank with resists; NPC pirates with orbit-and-shoot AI; wrecks and loot; pod, clone and respawn; basic insurance; bounties; repair.
- **View:** turrets track and fire on Core events (laser, projectile, hybrid, missile); impacts per layer; explosions by hull size; wreck models.
- **UI:** capacitor and tank wheel, module rack with cycle timers, target list with lock progress, fitting window with live stats, inventory with drag and drop, info window with attributes.
- **Tools:** headless duel simulator; balance report (damage, tank, capacitor stability per fit); effect previewer; hull gallery.
- Items come from a starter kit and loot until the market arrives in M3.
- **Retire:** `App/ltheory.luau` and the C++ combat path (physical projectiles as truth).
- **Exit:** headless duels match hand-computed results; a harness scenario fits a frigate, kills three pirates at a belt, loots a wreck, dies and respawns.

### M3 — One-system economy: mine, refine, build, trade, train (L–XL)
- **Core:** cycle-based mining, ore types, belt regeneration; reprocessing; market (order book ported from `Component/Market`, player limit orders, fees, taxes, history) fed by a placeholder local supply-and-demand model; blueprints, manufacturing and research jobs; skills v1 (~40 skills gating hulls and modules) with a training queue; wallet ledger; buying, assembling and switching ships.
- **UI:** market (browse, depth, my orders, history chart), industry, character sheet and skill queue, wallet, assets; main menu, new game, load, settings.
- **View:** mining beams and impacts; ore-specific asteroid materials.
- **Exit:** a scenario mines, reprocesses, builds ammunition from a blueprint, sells it through a limit order, buys a destroyer and trains the skill to fly it. This is the full EVE loop in one system.

### M4 — The living galaxy (XL)
- **Core:** 400+ systems in regions and constellations; stargates and jumps; route planner and autopilot; strategic sim v2 (§6) with the bridge that turns sim state into ships on grid and writes outcomes back; station markets derived from sim stock; security levels, police and sentries, aggression timers, security status; faction standings.
- **Engine and view:** stargate models, jump effect and tunnel; one nebula per region with a bounded cache; station and gate ambient animation.
- **UI:** star map, route, local list, news feed, sovereignty on the system panel.
- **Tools:** sim dashboard; multi-seed soak with conservation invariants.
- **Exit:** a ten-jump trade run profits from a simulated shortage; a system changes hands in the news and the new owner's ships are there on arrival; a 200 game-hour soak passes its invariants on 20 seeds; a save taken mid-war replays identically.

### M5 — Things to do: agents and exploration (L–XL)
- Agents and missions generated from sim events (kill, courier, mining, trade, escort, defend), standings, loyalty-point stores, mission pockets behind acceleration gates.
- Directional scan, probe scanning, anomalies and signatures (combat, data, relic, gas, ore), hacking game, escalations, salvage, bookmarks.
- NPC mining operations and roaming fleets that can be attacked; journal and an opportunity finder.
- **Exit:** scenarios complete one mission of each kind and scan down and run one site of each kind; standings and loyalty points change as specified.

### M6 — Depth: the full ship game (XL)
- Cruisers to battleships, industrials, mining barges; drones; e-war; remote repair; propulsion modules; rigs; cloaks; overheating; tech 2 and meta tiers; invention; planetary industry; full skill tree (~150), implants, boosters, jump clones; courier and exchange contracts; full insurance and clone rules.
- NPC AI that uses e-war, logistics and kiting. Tactical pause with queued orders; time acceleration polish.
- **Exit:** balance report covers every hull and module with no outliers beyond set bounds; scenario fleets of mixed classes fight to expected outcomes.

### M7 — Fleets and corporation (XL)
- Hire NPC pilots (skills, salary, loyalty); fleet window and fleet commands through the same command interface the player uses; fleet warp.
- Corporation: employees on standing orders (mine here, haul this route, patrol), corporate hangars and wallet, player-owned structures with services, fuel and reinforcement timers; moon mining.
- Battles involving player forces while the player is away are resolved by running the Core's tactical sim headless.
- **Exit:** a soak in which the player's corporation runs a mining-and-hauling operation for 50 game-hours with books that balance.

### M8 — Sovereignty and war (XL)
- The player's faction is one more faction in the strategic sim: claims, upkeep, system upgrades, defence fleets, diplomacy, war and negotiated peace.
- Sieges on timers that the player can fight in person; large-battle performance work; capitals (carriers, dreadnoughts, later titans), jump drives, cynos and jump bridges.
- **Exit:** a scripted campaign claims a system, survives a siege fought on grid with 300 ships at a playable frame rate, and concludes a peace.

### M9 — Unknown space, events, polish (L)
- Wormhole space with shifting connections; sim-driven world events (pirate surges, invasions); rare spawns and loot; story arcs.
- Onboarding through career agents; music and voice pass; balance and performance passes.

## 6. Strategic sim v2 (track S)

**Why the prototype failed.** The last run's news feed shows it was structural: 1,496 of 1,498 battles are pirates killing a loaded hauler; the budget rule counts ship purchases and supply buying as falling income (`Sim.luau:585-588`), so investing triggers scrapping; small demands are hidden from big haulers (`Market.luau:66`); money has no closed design. Each tuning lesson was a patch on indivisible haulers and hard thresholds.

**Design: stocks and flows carry the economy; timers carry the politics.**
- **Node:** one market per system, with stations as facilities on it. Each node holds stock and smoothed throughput for ~28 commodity classes (ores, minerals, fuel, food, consumer goods, components, ammunition, modules, hulls by size, construction kits, salvage).
- **Price:** `par × clamp((stock / target)^-e, ¼, 4)`. `par` is rolled up from the recipe tree, so every processing step has margin and the price level cannot inflate.
- **Flow:** goods move along a gate when the price gap exceeds the per-jump cost (transport + tariff + risk), limited by that edge's hauling capacity and damped so it cannot overshoot. War closes borders; pirate pressure raises risk and cuts capacity.
- **The mass market has no wallet.** Money lives only with actors: factions, the pirate organisation, corporations, the player. Liquidity traps cannot form outside actors.
- **Anchors:** homeworlds and a few hubs supply and absorb basics near par at a finite rate, and not through a blockade. Their share of volume is a headline metric; if it is high the economy is being faked.
- **Discrete consignments** (military supply, construction kits, player and corporation shipments) stay as per-jump timer actions. The economy still works if all of them die.
- **Simulated pilots:** a per-system population with mining, hauling and ratting shares supplies edge capacity, belt output, private ship losses (the stand-in for EVE's player losses) and the ships the bridge puts on grid.

**Per-type markets are derived, not simulated.** A type's order ladder is its class's price curve cut into slices, with hashed per-type noise. Walking the ladder is the same as moving the class stock. Only three things are saved: a sparse, decaying overlay per (node, type) the player touched; player and corporation orders with escrow; a price-history ring. Resting player orders fill at the type's share of local throughput, and an order through the market acts as a floor or ceiling that neighbours' flows respond to. That is how cornering works.

**The bridge has three tiers:** strategic (system level, 10 s); manifest (the player's system expanded into entities on timelines, which local, overview and scanning read); grid (the tactical Core where the player is). One writer per ledger account per tick. Civilian flow on the player's system's edges rides in escrow on token haulers; killing one debits the escrow into the wreck and a "destroyed" sink. Belt ore is a saved reserve; pirate spawns come from pressure and each kill debits it. Battles become multi-tick processes so the player can arrive mid-fight and hand-off is a copy of the counts.

**Faction layer: keep the timers, fix the money.**
- Keep: timer actions, per-jump moves, reservation, cancel-as-action, muster at 3:1, cooldowns, truces, coalitions, dens, seeded rolls.
- Change: income means tax receipts only; ships beyond budget are mothballed, never scrapped; supply and shipbuilding buy at the local node; sovereignty cost is superlinear and distance-weighted; peace is propose-and-evaluate with terms from a war score; sieges last about an hour in stages so the player can reach them; coalitions get three tiers (embargo, subsidy, military).
- Pirates become a pressure field per system, fed by dens and loot and suppressed by garrison, policing and kills. Discrete pirate fleets remain for raids and den building.
- Security level is derived from control, pirate pressure and front lines; policing is a budget line the owner pays, so a sovereign player sets it too.

**The player is an actor like any other:** a wallet, assets, relations, optional claims, and a controller (AI, player, or steward). The corporation exists from the first minute with one ship. Diplomacy is proposal entities evaluated by the same function for NPC and player offers. A parity test drives an NPC faction only through the player interface and requires the same outcome distribution.

**Content comes from state, not tables.** Missions, bounties, anomalies, trade tips and news are queries over sim state, with rewards escrowed from a real wallet and completion written as a real delta.

**Time:** 10 s tick; the economy steps every 6 ticks (one jump); slow fields every 60. The tick runs whole on a tactical-tick boundary (about 5 ms every 10 s); if it grows it is split into fixed stages keyed to the tactical tick index, never by wall clock. All inputs are journaled and applied at the boundary. The game is frozen while closed; "wait until" while docked, with interrupts, covers the legitimate use.

**Departures from `docs/design/universe-sim.md`:**
| Decision | Change |
|---|---|
| Individual goods | Real stocks and prices for ~28 classes; individual types derived from them |
| Prices at each station | Per system; station orders derived for display |
| Trade is a convoy action | True for consignments only; bulk trade is flow |
| Pirates as fleets hunting haulers | Pressure field; fleets only for raids and dens |
| Coalitions | Three tiers plus a readiness gate (nobody joins while exhausted) |
| Peace when resources run out | Propose and evaluate, terms from war score |
| Siege 20 ticks | About an hour, staged |
| Sovereignty and ship upkeep | Superlinear, distance-weighted; mothball before scrapping; lapse takes the lowest-control system |
| Station maintenance in goods | Consumption acts through prosperity with floors; independents have no treasury |
| Time while closed (was open) | Frozen |
| Everything procedural regenerated from seeds, never stored | System descriptions are stored in the save; only visuals are regenerated. Otherwise any generator edit breaks every save |
| A tick's work spread across frames by a coroutine | Whole, or fixed stages. Wall-clock slicing breaks determinism once the tactical layer writes back |

Everything else in the decision table stands: 400+ systems, 10 s tick, no fog between factions, physical resolution where the player is, 6 ticks per jump, homeworld starts, 24 h war cooldown (as 8,640 sim ticks, binding the player too), no action limit, commitment and cancel-as-action, 3:1 odds, two seeds.

**Build order (all headless until stage 6):**
| Stage | Size | Exit test |
|---|---|---|
| S0 Instruments: windowless runner, double-entry ledger for credits and goods, recorder, state hash, seed sweep, HTML report | M | The unchanged prototype runs on 8 seeds in parallel and the trend test fails its known "poor by day 5" run |
| S1 Economy kernel on toy graphs | M | Conservation, chain gradient, impulse decay, starve-and-restore, blockade and step-size tests pass; a one-hauler bot trader earns inside a band |
| S2 Galaxy-scale economy, static ownership | M | 16 seeds × 30 game-days pass the economy thresholds; < 1 ms per tick |
| S3 Faction layer v2 | L | 32 seeds pass the faction thresholds (≥ 6 of 8 alive, largest < 45% of systems, arrears < 5% of faction-time) |
| S4 Type markets and participant interface, with bots | M | Big-trade cost equals the ladder integral; buying then selling at one node never profits |
| S5 Bridge against a stub tactical layer | M | 1,000 fuzzed enter/leave/kill sequences leave zero ledger residual |
| S6 Real materialisation and market screen (M4) | L | A harness session kills a token hauler, loots it and sells, producing the expected ledger lines |
| S7 Content hooks (M5) | M | Several offer kinds within 5 jumps of a random position ≥ 90% of the time; no reward drawn from the world account |
| S8 Corporation to sovereignty (M7–M8) | L | The parity test passes headless |

**Salvage from `resource/script/Sim/`** (done in S3; see Status)**:** keep `Rng`, `Galaxy` (extend), `Combat` (add stepped battles); refactor `State`, `Actions`, `Ai`; rewrite `Market` and the content in `Data`; split `Sim` into tick orchestration plus economy, fiscal and diplomacy modules.

## 7. Engine work, in dependency order

| # | Change | Size | Anchor | When |
|---|---|---|---|---|
| E1 | Non-zero exit on script error, assert and crash (handlers call `exit(0)` today) | S | `src/liblt/LTE/OS.cpp:36-45`, `src/launch/launch.cpp` | M0 |
| E2 | `bin/ltcore`: windowless host linking only the Luau VM and compiler, with binary file I/O, rename, clock and args | S–M | new `src/ltcore`, modelled on `src/luaucheck/luaucheck.cpp` | M0 |
| E3 | `luaucheck` checks `Core/**` against host-only definitions, so an engine call in the Core is a type error | S | `src/luaucheck/luaucheck.cpp` | M0 |
| E4 | Kinematic mode in `ComponentMotion::Run` and `Object_SetBallState`; thrust glow follows target velocity; bind `SetUp` | S | `src/liblt/Component/Motion.cpp:10-45`, `MotionControl.cpp:21-26` | M1 |
| E5 | View clock for the shader `time` uniform (reads `Universe_Age()` today) | S | `src/liblt/LTE/DrawState.cpp:69-70` | M1 |
| E6 | Scene container without gameplay components, runtime sun direction, teardown with a live-object counter | M | derived from `src/liblt/Game/Object/System.cpp` | M1 |
| E7 | State stash across script reload | S | `src/liblt/Luau/Luau.cpp:2089`, `launch.cpp:168` | M1 |
| E8 | Scaled-space celestial list drawn first; directional sun term (commented out at `global.jsl:70`); explicit flare sizing | M–L | `src/liblt/LTE/DrawState.h:29-30`, `Game/RenderPass/DepthPrepass.cpp:104`, `resource/shader/fragment/light/global.jsl` | M1 |
| E9 | Cosmetic combat: weapons track a target object and fire on message; tracers with no damage or ray query | M | `src/liblt/Game/Object/Weapon.cpp:88-133,193-197`, `Pulse.cpp:134-176` | M2 |
| E10 | Lean proxy object type with no gameplay components | M | `src/liblt/Game/Common.h:71,180` | M2 |
| E11 | Draw cost: shader state caching (forced off today), sort by renderable, explicit GL context request, per-shader `#version` | M | `src/liblt/LTE/ShaderInstance.cpp:187`, `Game/Graphics/RenderStyles.cpp:55`, `LTE/Window.cpp:58`, `LTE/Shader.cpp:23` | M2 |
| E12 | Instanced draws for hulls and turrets | L | `src/liblt/LTE/Renderer.cpp:439-463`, `resource/shader/vertex/npm.jsl` | M8 (earlier if the M1 spike says so) |
| E13 | Remove LTSL (`LTE/Expression`, `Script.cpp`, `LTSL.cpp`, `ScriptFunction` fallbacks) and `Network`, `Strukt`, `CodeGen`, `src/old`; C++17 (all 383 sources already pass `-std=c++17 -fsyntax-only`) | M | `CMakeLists.txt:201` | M0 |
| E14 | Delete the old gameplay layer and shrink `ObjectT` | L | `src/liblt/Game/Object.h:121-508` | after M2 |

No C++ is needed for the fixed tick: a Luau accumulator steps the Core and passes the same scaled time to the scene, so pause and acceleration stay consistent.

## 8. Content: what has to exist, and how it gets made with no artist

Target scale: 4 visual lineages shared by the 8 factions (faction = lineage + palette + insignia); ~100 hulls; several hundred module types generated from tables; ~6 station kinds per lineage; stargates, wrecks, containers, player structures; 6 planet kinds; ~28 commodity classes; ~150 skills.

### Hulls (today: one archetype, one grey material, 90k–300k triangles each, no LOD, no mesh cache)
| # | Item | Size |
|---|---|---|
| H1 | PlateMesh: per-plate tag in the free vertex channel, `GetMesh(quality)`, child rotation, plate-list introspection (`src/liblt/LTE/PlateMesh.cpp`) | S |
| H2 | `HullSpec` data + `Hull.Build(spec, quality)`; a saved hull stores its resolved plate list, not just a seed | M |
| H3 | Hull data file; faction → lineage, palette, insignia table | S |
| H4 | Grammar: spine and sections, class silhouette table, symmetry modes, parts library (nacelle, pylon, bridge, cargo rack, engine cluster, turret shelf, launcher bay, mining arm) | M |
| H5 | `Material_Hull`: paint zones, wear, emissive windows and engines, insignia decal, per-lineage plating (`metal.jsl` has the hooks commented out) | M |
| H6 | Four lineage bundles (slab, blade, bulb, lattice) and native taper/bend/twist warps | M |
| H7 | Hardpoints emitted by the generator and snapped to the surface; socket size class; slot counts from data | M |
| H8 | Module models per family × size, each reporting its barrel tip | S–M |
| H9 | LOD chain, baked-mesh disk cache, cull distances for turrets and thrusters | M |
| H10 | Wreck mesh (drop plates, break warp), debris chunks, low-HP fire emitters | M |
| H12 | Curate ~100 hulls in the gallery tool | M, ongoing |

### World (today: one station archetype, one planet kind, three asteroid meshes, sun is a light only, ~200 MB of sky per system)
| # | Item | Size |
|---|---|---|
| W1 | Cache manager: versioned keys, size budget, LRU eviction | S–M |
| W2 | Nebula per region at 512² half-float (~14 MB per region instead of ~200 MB per system); cached irradiance map | S–M |
| W3 | Sun disc and corona at true angular size | M |
| W4 | Far-layer proxy mode for planet, moon and sun shaders | M |
| W5 | Planet kinds: temperate, ocean, barren, ice, lava, gas giant; moons; optional rings; city lights; resolution tiers | M |
| W6 | 12–16 seeded asteroid shapes, per-ore material, ice revival, depletion scale | S–M |
| W7 | Structure toolkit: trade hub, shipyard, refinery, mining outpost, habitat, fortress, pirate den; dock-bay part; nav-light sprites | M |
| W8 | Stargate model with membrane (`gate.jsl` exists, unreferenced) | S–M |
| W9 | Gas clouds and deadspace fog (revive the DustClouds pass) | S–M |
| W10 | Deadspace scenery recipes (wreck fields, derelicts) | M |
| W11 | Player structure modules with visible build progress | M |

### Game data (new; nothing data-driven exists for the playable game)
- Type database in typed Luau tables, so `luaucheck` is the schema check: categories, groups, types, attributes, effects, blueprints, skill requirements.
- Generated from archetype tables rather than hand-written: hulls per lineage × class × role, modules per group × size × tier, blueprints from value curves, NPC fits from templates, loot tables, spawn tables, site and mission templates, text grammar for names and briefings (`Grammar_Get` exists).
- Icons with no artist: rendered hull thumbnails baked to an atlas; item icons composed from group frame + pictogram (~50) + size pips + tier corner; ~30 bracket icons; faction insignia shared with hull decals. Needs new glyph primitives (polygon, wide line, rotation, n-gon, character, atlas image).

## 9. Effects backlog

The first item is a cosmetic effects layer. Today Pulse, Beam, Rail and Missile are damage-dealing simulation objects; under the Core they become visuals triggered by events.

| # | Effect | Today | Action | Size | When |
|---|---|---|---|---|---|
| F1 | Cosmetic FX layer driven by Core events (beam, bolt, rail, missile, burst, ring, attached emitter) | Effects deal damage | New | M | M2 |
| F2 | Particle upgrade: textured fireball, stretched sparks, drag, emitters, smoke | 2 radial types | Extend | M | M2 |
| F3–F6 | Energy bolts, projectile tracers, rail streak, beam laser, in four sizes | Pulse live; rail unreachable; beam `#if 0` | Reuse / revive | S each | M2 |
| F7–F8 | Missiles with trail and timed arrival; muzzle and launch flashes | Missile code unreachable | Extend / new | M, S | M2 |
| F11–F14 | Shield ripple from an event, armor sparks, hull fire and smoke, visible misses | Ripple exists, collision-triggered | Extend | S–M each | M2 |
| F15–F17 | Explosions: small; medium with secondaries and chunks; capital breakup with shake | 2 sprites, one size | Extend / new | S–M, M, L | M2, M6, M8 |
| F18–F20 | Shockwave ring; debris chunks; wreck and loot container | — | New | S, M, S | M2 |
| F21–F22 | Warp tunnel for own ship; warp-in and warp-out streaks for others | Motion blur disabled; dust streaks capped | Revive, extend | M, S–M | M1 |
| F23 | Gate activation, jump flash, jump tunnel | `gate.jsl` unused; `wormhole.jsl` live | Revive, extend | M | M4 |
| F24 | Dock and undock transition, exterior view while docked | Rock-shell interior | New | S–M | M1 |
| F25–F27 | Mining beam with impact; salvage, tractor, remote repair, energy transfer; e-war beams with target-side sprite | Transfer beam | One parameterised beam | S–M total each | M3, M5, M6 |
| F28 | Propulsion flares, engine glare, engine trails | Trail `#if 0`; glare shader unused | Revive | S | M1 |
| F9 | Drones (tiny hulls, miniature weapons) | Inert | Extend | M | M6 |
| F10 | Sphere-shell shader: smartbomb, scan pulse, disruption bubble | — | New | S–M | M5 |
| F29 | Cloak and decloak dissolve | — | New | M | M6 |
| F30 | Station and gate ambient: blinkers, rotating sections, signs | — | New | M | M4 |
| F31 | Tactical overlay: range spheres, orbit rings, target lines, velocity vectors | — | New | M | M1 reduced, M6 full |
| F32 | Asteroid depletion pop; structure damage states | — | New | S each | M3, M7 |

Renderer upgrades that pay for the effects: R1 direct sun term on metal (S; biggest single visual gain, prerequisite for paint) · R3 emissive via per-pixel no-shade (S) · R10 script-driven post pass (S) · R4 bloom and tonemap in linear space (S–M) · R6 light cap 16 → 32–48 (S) · R2 sun shadow map (M–L) · R5 SSAO fixed, not just re-enabled (M) · R7 state caching, sorting, then instancing (M–L).

## 10. UI

The widget core cannot carry EVE-density lists as built: decorators are Luau closures called per widget per frame, each text draw is its own draw call, `Widget_Dynamic` re-creates every child every frame, there is no table, tree, focus owner, window z-order or list menu.

### Toolkit
| # | Item | Size |
|---|---|---|
| U1 | Batched canvas drawing in C++: text without per-call flush, clipping, ellipsis, right-align, texture rect with UV and tint, alpha blending (`src/liblt/UI/WidgetRenderer.cpp`) | M |
| U2 | Store with change notification; screens subscribe; Core events feed it | S–M |
| U3 | Virtualised sortable table drawn as one widget (columns, sort, resize, selection, keyboard) | M |
| U4 | Tree view as a flattened table | S |
| U5 | Window manager: drag, resize, z-order, snap, pin, modal layer, saved layout | M |
| U6–U8 | List context menus with submenus; drag-and-drop; confirm, quantity and text dialogs | S, S–M, S |
| U9–U10 | Keyboard focus, caret editing, clipboard; hotkey map with contexts and rebinding | S–M each |
| U11, U17 | Formatting (ISK, m/km/AU, durations, volume); theme tokens | S each |
| U12 | Fonts: larger atlas, overflow guard, pre-warm, tabular digits, word wrap | M |
| U13–U16 | Radial cycle timers and gauges; charts; notifications; rich tooltips | S to S–M each |
| U18 | Bracket layer as one immediate-mode widget for 200–500 brackets with declutter | M |
| U19 | Settings schema in Luau with a bridge to the C++ graphics toggles | S |

### Screens
| When | Screens |
|---|---|
| M1 | Overview, brackets, selected item, navigation HUD wheel, station panel, Escape menu and settings stub |
| M2 | Module rack, target list, fitting, inventory and loot, combat log, death and respawn, Show Info |
| M3 | Market (tree, depth, my orders, history chart), industry, skills and character sheet, wallet, assets, main menu, new game, load, settings |
| M4 | Star map and route, local list, news feed, notifications history |
| M5 | Agent conversation and journal, system map with probe scanner, D-scan, opportunity finder |
| M6 | Drones, contracts, planetary industry |
| M7 | Fleet, corporation and employees, structure management |
| M8 | Sovereignty and diplomacy |

## 11. Audio

Playback works (miniaudio, streaming for large files). Mixing and content are missing: no buses, no instance limits, no playable music, 85 of 130 sound files unused.

| # | Item | Size |
|---|---|---|
| A1 | Buses (master, music, world, UI, ambience, voice) with volumes and fades; voice and alarms duck music | S–M |
| A2 | Event → sound table (files, bus, pitch range, 2D/3D, caps); the same Core events that drive effects drive it | S |
| A3 | Instance caps, cooldowns, priority stealing | S–M |
| A4 | Wire the unused files: jump drive → warp, warp-node set → gate and tunnel, UI set → selection and modules, weapon sets by size, lab sounds → industry, ambience loops → space, station and site beds | S |
| A5 | Listener policy for the zoomed-out tactical camera | S |
| A6 | Music contexts (menu, docked, calm, threat, combat) with playlists under `resource/music/<context>/`, crossfade, combat hold | M |
| A7 | Synth tool for alarms, lock tones and error buzzers (finish the unused `src/liblt/Audio` library, render to files) | S–M |
| A8 | Voice lines by offline TTS from a text list | S |
| A9 | CC0 packs for the gaps (projectile guns, repair loops, large explosions); layered and pitched explosion sizes | S–M |
| A10 | Audio settings | S |

Music has no source today (the FMOD banks are unplayable). Drop your own tracks into the context folders, or use CC0 ambient sets.

## 12. Tools

### Core and test tools
| Tool | Purpose | When |
|---|---|---|
| Headless Core host | Run Core tests, soaks and reports with no window | M0 |
| Test kit and `script/check` | Assertions; type check + Core tests + harness scenarios in one command; non-zero exit on any failure | M0 |
| Replay recorder | Record the command journal; replay to a state hash; the regression net for every Core system | M1 |
| Save inspector | Dump and diff saves as text | M1 |
| Dev console and cheats | Luau prompt in game; spawn, give, set skill, teleport, advance time | M0 |
| Duel simulator and balance report | Headless fits against fits; HTML/CSV of damage, tank, capacitor, cost per hull and module | M2 |
| Type-database validator | Referential integrity; every hull has a valid fit; every item has a source and a sink | M2 |
| Performance capture | Profiler to file; fleet stress scene with a ship-count slider; tick budget print | M2, M8 |

### Sim tools (track S)
Double-entry ledger; recorder to CSV; state hash; seed sweep across processes; balance check of capacity against demand before a run; static HTML dashboard (source and sink stacks, price fans and galaxy price maps, faction income and runway, territory and war timeline, pirate pressure, anchor share, seeds × thresholds scorecard).

### Content tools
| # | Tool | Grows from | Size |
|---|---|---|---|
| T6 | Golden-screenshot runner with tolerance compare; needs a fixed-timestep harness flag and seeded global RNG | harness | S–M |
| T1 | Hull gallery: contact sheets by lineage, class, role and seed; palette cycle; LOD and triangle counts; hardpoint gizmos; pick and save | `App/model.luau` | M |
| T2 | Station, planet, asteroid and sky sheets | T1 | S each |
| T5 | UI gallery: every widget, a 10k-row table, icon sheets, every screen on fixture data so screens can be built before their systems | `App/ui.luau` | M + S per screen |
| T4 | Effect previewer: fires every row of the event table on loop with its sound | `App/observatory.luau` | M |
| T3 | Plate editor v2 (the planned hull designer): load and save hull specs, three views, paint tags, hardpoints | `App/platemesh.luau` | M–L |
| T7–T9 | Icon atlas baker; fleet stress scene; cache inspector | T1, observatory, DevPanel | S each |

## 13. What gets retired

| What | Fate |
|---|---|
| `Game/Task`, `AI`, the gameplay components (Economy, Market, Projects, Tasks, Pilotable, Assets, Storage, Cargo, Missions), `Player`, `Universe`, `Region`, `App/ltheory.luau` | Frozen now. Their known bugs (`GetOutput` typo, `Transport`, `Task_Play`) are not fixed. Deleted after M2 (E14) |
| LTSL compiler, `Network`, `Strukt`, `CodeGen`, `src/old`, stale `extbin/` | Deleted in M0 (E13) |
| Demo apps that are not tools | Deleted after M1. `model`, `observatory`, `platemesh`, `ui` grow into the content tools |
| Renderer, passes, generators, PlateMesh, SDF meshing, widget core and Luau widget library, audio, input, harness; `Orientation`, `Drawable`, `BoundingBox`, `Cullable`, `Attachable`, `Sockets`, `Interior` | Kept as view machinery |
| Order book; hull, station and system recipes; `Sim/*`; the existing screens | Ported into the Core, the Describe step and the new UI |
| WASD flight, phase-aim mining, physical projectiles as truth | Dropped by the pure-EVE decision |
| Warp-rail visuals, the spectral scanner display, evidence-based bounties | Reused as acceleration gates, probe-scanner flavour, and pirate tags as loot |
| Unplayable FMOD music banks (90 MB) | Removed when the music system lands (try extracting them first) |

## 14. Risks, and the cheap experiment that retires each

| Risk | Experiment | When |
|---|---|---|
| The bridge loses or duplicates ships and cargo | Headless fuzz of 1,000 enter/leave/kill sequences against a stub tactical layer; property-test promote and demote mid-battle | S5, before M4 |
| Determinism breaks after a save and load | The round-trip hash test, written before any rules code | M0 |
| Flows give a flat price surface or nothing for a trader | Toy chain and star graphs with a one-hauler bot trader | S1 |
| Hundreds of ships cost too much to draw | 300 kinematic proxies orbiting, profiled; decides state caching versus instancing | start of M1 |
| Scene teardown leaks | Create and destroy the scene 50 times, watching live-object count and VRAM | start of M1 |
| Scaled-space celestials look wrong | One planet and the sun at 1 AU; check atmosphere, flare, lighting | start of M1 |
| The UI toolkit is the long pole | Prove U1–U3 and U18 with a 10k-row table and 500 brackets in the UI gallery before building screens | M1 |
| Attribute-engine scope creep | Data-driven from the first module; validator from M2 | M2 |
| Abstract and tactical combat disagree, so leaving a fight pays | 500 headless matchups; fit the stepped model to within ~15% | M4 |
| A 1 s tick feels sluggish | Try 0.5 s; all durations are data | M1 |
| Saving hitches | Encode a 400-system state with 50k items and time it; C encoder as fallback | M1 |
| War pace outruns the player | Measure warning time from detectable plan to capture; require a median near 45 minutes | S3 |
| Scope | M1–M4 are the game. Each later milestone is separable breadth, and content comes from tables | always |

## 15. Verification

- **One command:** `script/check` runs the strict type check (with the Core boundary), Core unit tests and replays in `bin/ltcore`, harness scenarios with assertions, and golden screenshots. Any failure exits non-zero.
- **Per milestone:** the exit tests in §5, each a scripted scenario or headless run.
- **Sim:** the toy-graph suite, seed-sweep thresholds, and a ledger residual of zero.
- **Visuals:** harness screenshots (`bin/launch APP --do … --out DIR`, `DRI_PRIME=1`) read directly; galleries and screens on fixture data under golden tests.
- **Performance:** the fleet stress scene; budgets of ≤ 2 ms per tactical tick and ≤ 5 ms per strategic tick.

## 16. First steps

1. Work happens on branch `eve-core`, branched from `universe-sim-design` so the sim prototype comes along.
2. M0 in this order: E1 → E2 and E3 → test kit and `script/check` → determinism round-trip on the prototype → S0 instruments → T6 → dev console → E13 → `docs/design/core.md`.

**Files touched first:** `src/liblt/LTE/OS.cpp`, `src/launch/launch.cpp`, `src/luaucheck/luaucheck.cpp`, `CMakeLists.txt`, new `src/ltcore/`, `resource/script/Sim/{Sim,State,Ai}.luau`, `resource/script/App/simrun.luau`, new `resource/script/Core/`, `docs/`.

**Not verified when this was written:** nothing was built or run with a window. Render cost, VRAM, teardown, the GL context version SFML obtains, and how revived shaders look are judged from source. The Luau timings are synthetic loops. Every tuning threshold in §6 is an opening proposal.
