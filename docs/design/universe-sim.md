# Universe simulation

The universe simulation produces the activity a single-player sandbox game has to fake: wars, trade, ownership changes, prices that move. A multiplayer game gets this from thousands of players; here the game has to do it.

Status: the proposal, decisions and design details below were agreed on 2026-10-25 and a headless prototype implemented them (see "Prototype"). On 2026-11-09 the economy was redesigned as stocks and flows and several decisions changed; see "Changes of 2026-11-09" directly below and `docs/roadmap.md` §6 for the current design. On 2026-11-10 the faction layer was rebuilt on that economy as `resource/script/Core/Strategic/` and the prototype was removed from the tree; see "The faction layer as rebuilt". The rest of this document describes the prototype as it was, for the record.

## Changes of 2026-11-09

The faction and timer layer stands. The hauler-level economy is replaced: each system is one market node with stock and prices for about 28 commodity classes, goods flow along gates when the price gap exceeds the per-jump cost, and money lives only with actors (factions, pirates, corporations, the player).

| Decision below | Now |
|---|---|
| Individual goods | Real stocks and prices for ~28 classes; individual item types are derived from them |
| Prices at each station | Per system; station orders are derived for display |
| Trade is a convoy action | True for strategic consignments only; bulk trade is flow |
| Pirates as fleets hunting haulers | A pressure field per system; fleets only for raids and den building |
| Coalitions | Three tiers (embargo, subsidy, military) plus a readiness gate: nobody joins while exhausted |
| Wars end when resources run out | Propose and evaluate, with terms from a war score |
| Siege timer of 20 ticks | About an hour, in stages, so the player can reach the fight |
| Sovereignty and ship upkeep | Superlinear and distance-weighted; ships are mothballed before any are scrapped; a lapse takes the lowest-control system |
| Station maintenance in goods | Consumption acts through prosperity with floors; independents have no treasury |
| Time while the game is closed (open question 1) | Frozen. "Wait until" while docked covers the legitimate use |
| Everything procedural is regenerated from seeds and never stored | System descriptions are stored in the save; only visuals are regenerated, so a generator edit cannot break a save |
| A tick's work is spread across frames by a coroutine | The tick runs whole, or in fixed stages keyed to the tactical tick. Slicing by wall clock breaks determinism once the tactical layer writes back |

Unchanged: 400+ systems, the 10 s tick, no fog between factions, physical resolution where the player is, 6 ticks per jump, homeworld starts, the 24 h war cooldown (8,640 ticks of sim time, binding the player too), no action limit, commitment and cancel-as-action, 3:1 odds, the two seeds.

## The faction layer as rebuilt (2026-11-10)

**Retired 2026-11-24** (the owner: "Yes, retire the headless faction model"). What follows describes the headless model of stage S3, which never ran in a game: the game's factions are `Core/Strategic/Wars` and its economy `Core/Strategic/Commerce` (docs/roadmap.md §6, as built). Kept as the record of what was tried.

`resource/script/Core/Strategic/` was the simulation then. Every number it was tuned by was in `Core/Data/Powers.luau`.

| Module | Contents |
|---|---|
| `Economy`, `Atlas` | The galaxy's economy and who lives where (stage S2) |
| `World` | The state: powers, systems, fleets, timers, wars, the ledger. A new world starts at the founding, each power on its homeworld |
| `Orders` | What a government can order: moves, ships built, laid up and brought back, supplies and kits bought, a system let go |
| `Battle` | Rounds of fighting, and sieges in stages |
| `Order` | Pirate pressure, control, security, and what they do to the lanes |
| `Fiscal` | The levy, the costs, arrears |
| `Diplomacy` | Relations, war, coalitions, peace |
| `Raiders` | The pirates' money, dens and raids |
| `Mind` | How a government decides |
| `Sim` | The tick |

What changed from the decisions below, beyond the table above:

| Decision below | As built |
|---|---|
| Attackers attack only at 3:1 or better | 3:1 over a system's own defences, plus a margin over the fleet its owner can bring (smaller for a bold power). At 3:1 over everything nobody of similar size ever attacked |
| Wars begin when relations fall low enough | Low relations make a war possible; a power declares one only when it judges its fleet a match for the other's. Relations are also knocked about by random incidents between neighbours, so histories differ |
| Truce of 10 hours | Two days for both sides, three for a side that gained by the peace, so that one neighbour is not ground down war after war |
| Sovereignty cost per system and station | Per system, rising with distance from the capital and with the square of the number held. A power also gives up, at peace, a system that costs it far more than it brings |
| Planets and stations defend strongly | A system's defences follow its population; a homeworld's are ten times that. A power can lose its provinces and keep its heart |
| Pirates pay station upkeep like everyone else | Pirates pay for dens, recruits and crews from a cut of what piracy takes on the lanes and from raid loot. Dens have no goods upkeep |
| Battles resolve when a fleet arrives | A battle is fought in rounds, a minute each, for as long as enemies share a system |
| Reaction phase | No separate phase: each government thinks once a minute, and its defensive decisions take their turn with the rest |

Everything else in the decision table stands as built: 400 systems, the 10 s tick, no fog between powers, six ticks a jump, homeworld starts, the one-day war cooldown, cancel-as-order, coalitions against a larger aggressor, independents that resist claims, upkeep for systems and ships.

## Proposal (as written by the designer)

> 2 layers:
>
> * Universe state as a database / data model
>     - every planet, station, etc (not ephemeral objects like asteroids)
>     - tracks prices of goods
>     - tracks ownership of objects
>     - tracks faction relations
>     - list of ACTION TIMERS (i.e. what an entity is in the process of doing)
>         - submitted by a faction during their "turn", and the change to the state only applies on timer completion
>         - other faction actions can interrupt (chance resolution, depending on the action and factors associated)
>
> * faction simulator with 3 key "phases" per tick:
>     1. timer-resolve phase: any actions that resolve this tick happen now, update universe state.
>     2. action phase (all factions perform in parallel): current-state review + new action submissions
>     3. reaction phase (all factions perform in parallel): review other factions' in-progress actions + react, submit new actions
>
> Example: Faction Red owns system A. Faction Blue owns system B.
>
> - Tick 2312343979, action phase: Red dispatches a fleet (an action with a timer) to attack system B. The fleet has properties drawn from Red's objects (count and type of ships). The timer is 300 ticks (travel time).
> - Tick 2312343979, reaction phase: Blue sees this and sends a fleet to intercept. Timer 120 ticks; that fleet has its own properties.
> - Tick 2312344099, resolve phase: Blue's fleet reaches Red's fleet; fleet-vs-fleet combat. Blue loses. Red's fleet continues with lower strength.
> - Tick 2312344159, resolve phase: Red's fleet reaches system B; combat against the planet/station/fleet. Blue loses. Red gains control of the entity.
> - Tick 2312344159, action phase: Red dispatches reinforcements, ETA 200 ticks.
> - Tick 2312344159, action phase: Blue dispatches an attack fleet to retake it, ETA 120 ticks.

## Decisions (2026-10-25)

| Question | Decision |
|---|---|
| Galaxy size | At least **400 systems**, able to scale up later |
| Tick | **1 tick = 10 s of real time.** The resolve, action and reaction phases all run within that window. 300 ticks = 50 minutes, plenty of time for a mission |
| Economy depth | **Individual goods** (ores, components, ships, ...), not an abstract capacity number |
| Information | **No fog of war between factions** at the simulation level |
| Layer boundary | The simulation doesn't control the in-system simulation directly. It changes the universe state, and the state determines what the in-system simulation shows when the player enters a system |
| Resolution where the player is | **Physical.** Fleets, traders and so on arriving or leaving warp in and out, as pirates already do. The abstract combat model applies only to systems the player is not in |
| Jumps | **6 ticks (1 minute) per gate jump** |
| Starting position | **Each faction starts with one home system around a self-sufficient homeworld**, with no missing key resources, so each faction is stable on its own; growth comes from claiming |
| War cooldowns | **A faction can't declare a new war within 24 real-time hours of declaring another, nor within 24 hours of one of its wars ending** |
| Coalitions | **Other factions tend to ally against a larger aggressor in a war** |
| Pirate stations | **Pirates pay to have stations (dens) constructed**, and then carry the same station upkeep as everyone else |
| Actions per tick | **No limit.** A faction can submit any number of actions in each phase (builds, convoys, claims, attacks, defence); only its ships, goods and credits constrain it |
| Commitment | Ships and goods are locked once in an action. **Cancelling a submitted action is itself an action** and unlocks them |
| Ending wars | **Wars end on lack of resources, with negotiated terms.** A side runs out of credits or loses most of its fleet, then sues for peace and cedes systems or pays |
| Defences | **Planets and stations defend strongly.** Attackers only attack at **3:1 odds or better** |
| Independents | **Independent systems and stations resist claims** |
| Sovereignty upkeep | **Every system and structure costs credits to maintain.** A faction that can't pay eventually loses control of systems. This gives credits a purpose |
| Ship maintenance | **Ships cost credits to maintain** (repairs, crew salaries), so large fleets are expensive |
| Station maintenance | **Stations and planets also need goods to run** (food, domestic goods, fuel). Independents must buy what they can't produce, which spends their credits and routes money to the factions that supply them |

## Design details

### Space and movement
- The galaxy is a graph of systems joined by gates, generated from the universe seed with LT's existing region packing and spanning-tree links.
- A fleet's journey is a chain of **per-jump timers, 6 ticks each**, not one long timer. A fleet is therefore always in a system or on a known edge.
- **Interception needs no special action:** a fleet moves to a system on the enemy's route. Combat happens whenever hostile fleets are in the same system on the same tick (or at a station they're attacking).

### Actions and timers
- Every action is an entity in the state with an owner, a kind, an end tick and its parameters (fleet composition, cargo, target).
- **Reservation at submission:** ships, goods and credits committed to an action are locked immediately, so two actions submitted in the same phase can't spend the same fleet.
- **Cancelling** is an action a faction submits. It unlocks the reserved ships and goods; a moving fleet stops at the next system it reaches.
- **Interruption:** an action can be cancelled or modified by another resolving action (a fleet destroyed en route, a convoy intercepted, a station captured mid-build). The chance and outcome depend on the action and its factors.
- **Same-tick ordering:** within the resolve phase, all movement completes first, then all combat at each location is resolved together, then the remaining actions (build, trade, ...) resolve. Ties are broken deterministically (by action id), never by evaluation order.

### Combat (abstract)
- Fleet-vs-fleet uses a Lanchester square-law model: strength ∝ (ship count)² × quality, with quality from hull class and fitting (this ties into hull classes and the hull designer).
- Randomness comes from a seeded roll per battle. Fleets retreat at a loss threshold instead of fighting to the last ship.
- Station or planet assaults use the same model with defence values on the target. A win transfers ownership.

### Economy (individual goods)
- Each station or planet has stock, production and consumption per good: mines and ore fields produce ore, factories turn inputs into outputs, colonies consume goods.
- **Prices come from stock against demand at each station**, so they differ by place and over time. That is what makes hauling and trading worthwhile.
- Ships are built from goods. Fleets have upkeep. Destroyed ships, ammunition, fuel and colony consumption are the **sinks** that keep goods moving.
- Trade is an action: a **convoy** carrying goods from A to B on per-jump timers, interceptable by pirates, enemies or the player.

### Factions and decisions
- Each faction has goals (expand, defend, profit), a personality (LT's `Traits`: Aggressive, Greedy, Lawless, ...) and relations with the others.
- In the action phase a faction scores candidate actions (attack, defend, build, mine, trade, expand) by utility against its goals, weighted by personality, and submits the best few within a budget.
- The reaction phase is the same machinery restricted to responding to actions submitted this tick, plus posting contracts (e.g. "defend system B, attack ETA 300 ticks"), which become player missions.
- Pirates are a faction whose goal is raiding convoys and weakly held systems. Independent traders and miners are convoys and operations owned by minor factions.

### Determinism and persistence
- **Two seeds.** The **galaxy seed** fixes the layout, stations, names and starting setup, so a galaxy can be shared. The **history seed** drives every roll during play (combat, resistance, desertion). It is picked fresh for each new game, so the same galaxy unfolds differently each time, and it is stored in the state.
- Each roll's stream is derived from (history seed, tick, ids), so a run replays exactly from its two seeds. This is used for tuning and debugging.
- **The universe state is the save file:** the galaxy seed plus the state, including the history seed (ownership, stock, prices, relations, fleets, active timers, player assets). Everything procedural (system layouts, hulls, item stats) is regenerated from seeds and never stored.

### Generation and the two layers
- System generation splits into two parts:
  - **Describe:** data only. The planets, stations, zones, their types and seeds, with no engine objects or GPU work. Run once per system to build the state.
  - **Materialize:** builds the physical objects for one system when the player enters it.
- Today `Object/System.luau` does both at once for every system, which can't scale to 400. This split is the main engineering prerequisite.

### Time and scheduling
- A tick's work is spread across frames within its 10-second window (a Luau coroutine resumed for a slice each frame), so a 400-system tick never causes a frame hitch.
- Sim time and real time run together while playing. Behaviour while the game is closed (frozen, or catch-up on load) is an open question.

## Open questions

**The physical layer (agreed).** While the player is in system X:
- changes to X in the universe state are pushed into the physical simulation (arrivals warp in, departures warp out, ownership changes update station owners);
- physical events in X are written back to the state (ships destroyed, trades made, cargo moved);
- a timer resolving in X (such as a battle) is resolved physically instead of with the abstract model, and the result is written back when it ends.

1. Time while the game is closed: frozen, or simulated forward on load?
2. How the player's own assets and actions enter the state as a participant: kills, trades, owned ships, and later owned stations.
3. Starting set of factions and goods: the prototype proposes one in `resource/script/Sim/Data.luau`, for the designer to adjust.

## First implementation step

A **headless simulation runner** in Luau, with no rendering:
- Generate the galaxy description (400+ systems) from the universe seed.
- Run a handful of factions plus pirates for 100k ticks, much faster than real time.
- Print a news feed (wars, captures, convoys lost) and stats over time: territory, fleet sizes, stock and prices by station.

This shows whether the dynamics are stable and interesting before anything is rendered. After it come materializing the current system from the state, the physical write-back, and save/load.

## Prototype

(Removed from the tree on 2026-11-10; the branch `universe-sim-design` has it.) `resource/script/Sim/` implemented the simulation in pure Luau, with no engine objects:

| Module | Contents |
|---|---|
| `Data.luau` | **The content and tuning:** goods, station kinds and recipes, ship classes, factions and personalities, timing, combat and relations constants |
| `Galaxy.luau` | The Describe step: positions, gates (spanning tree plus extra links), stations, precomputed routes |
| `State.luau` | The universe state (the save file with the seed), the timer heap, the initial setup |
| `Market.luau` | Station prices from stock, the offer index |
| `Combat.luau` | Lanchester battles |
| `Actions.luau` | Move, convoy, build, siege, cancel |
| `Ai.luau` | Faction decisions for the action and reaction phases |
| `Sim.luau` | The tick: resolve, action, reaction |
| `Rng.luau` | Deterministic random streams |

Run it with `bin/launch simrun` (`App/simrun.luau` sets the seed, size and length). It prints a report every 2500 ticks and writes the full news feed to `cache/sim_news.txt`.

**How the agreed rules are implemented:**
- **Defence and attack odds.** Stations defend strongly (10–40 each). Attackers prepare: they pick an enemy border system they can take at **3:1** against its stations plus any relief that can arrive within the siege. They muster fleets at an adjacent staging system and launch when the gathered force is enough. A win starts a **siege timer** (20 ticks); the system falls if the besiegers still hold it at the end.
- **Independents resist.** A claim fights the system's own defences at the same odds, then **pacifies** it with the same siege timer. Independents keep a treasury and **earn only by selling goods**; they collect no taxes.
- **Maintenance in goods.** Every station consumes food, fuel and domestic goods each cycle, drawn from any station in its system. A station short of them produces and defends at reduced strength (down to half). Independents import what they lack, which routes money to the factions that supply them.
- **Maintenance in credits.** Each faction pays sovereignty upkeep (per system and per station) and ship maintenance every period.
  - A faction in arrears loses its most remote system each period after a grace period, and its crews desert.
  - A faction running a deficit decommissions ships first.
  - Warships are only built from a working-capital reserve, and only when income covers their upkeep.
- **Income.** Habitat taxes plus a 3% industry tax on the value of everything produced, both paid to the owning faction.
- **Pirate stations.** Pirates pay to have dens constructed. A construct action sends an escort to an empty independent system far from faction space; the den is built after 60 ticks if the escort still holds the site. Pirates pay the same sovereignty and ship upkeep as factions, and their dens consume maintenance goods. Since nobody trades with them, they supply those goods by raiding: looted maintenance goods go to the nearest den and the rest is fenced for credits. Built stations are recorded in the state, because the galaxy description is regenerated from the seed.
- **War cooldowns and coalitions.** Each war has a declarer. A faction can't declare war within 24 hours (8,640 ticks) of its last declaration or of one of its wars ending. While an aggressor is more than 1.2 times as powerful (war fleet plus territory) as its victim, the other factions' relations with it fall, in proportion to its dominance, and rise with the victim. Once they cross the war threshold, those factions join the war against the aggressor, as declarers themselves.
- **Budget discipline.**
  - New ships are only built when income covers running costs by 10% plus the ship's upkeep (a minimum of six haulers excepted).
  - A faction running a deficit with less than 15 periods of runway scraps ships until costs fall to 90% of income.
- **Ending wars.** A side is exhausted when it has less than two periods of running costs left, or its war fleet has fallen below half its strength at the start of the war. The exhausted side **sues for peace**: it cedes up to two border systems (besieged ones first) and pays 30% of its credits. If both are exhausted, the peace is white. A 10-hour truce follows.

**Results (galaxy seed 1, history seed 1, 400 systems, 40,000 ticks ≈ 4.6 game days):**
- **Performance:** about 4.5 ms per tick; a run takes about 3 minutes. The same two seeds replay identically.
- **Economy:** stable throughout. Station maintenance met at about 75% for factions and 60% for independents, no systems lost to arrears, and every faction alive. Pirates hold at 9 dens and about 55 frigates.
- **Wars:**
  1. The Iron Kestrel Union, the largest power (about 80 systems), declares war on Meridian, which sues for peace within an hour.
  2. Kestrel's next declaration comes exactly 24 hours after that war ended.
  3. Halcyon joins a coalition against Kestrel; both Meridian and Halcyon later sue for peace, each ceding a system.

**With eight factions** (25 starting systems each; galaxy seed 1, history seed 1, 40,000 ticks):
- **Military snowball contained:**
  - Coalitions form repeatedly against the Iron Kestrel Union, which twice has to sue for peace and pay reparations.
  - It holds at 24–29 systems instead of reaching 80.
  - There are 10 wars and 10 peaces, spaced by the 24-hour cooldown.
- **Economies fragile:** five of the eight factions collapse to a single system through arrears.
  - Small factions run at about 45% station maintenance, with few haulers and almost no warships.
  - Broke factions join coalitions and sue for peace within minutes, because they are already exhausted when they join.

Two fixes went in for this:
- **Shipyards draw materials from their whole system.**
- **Emergency haulers:** a faction with fewer than six haulers can buy one for credits alone. Without this, losing every hauler deadlocked a faction, since its shipyards were supplied by hauler.

**Homeworld starts** (one self-sufficient home system each; planets have unlimited storage):
- **Two fixes:**
  - **Storage caps were too coarse.** A recipe stopped entirely when any one output was full, which also stopped its tax. Recipes now produce whatever outputs have room, and taxes are always paid.
  - **Planets have unlimited storage.**
- **With 8 factions over 4.6 days:**
  - **Stable:** every faction survives, nobody loses a system to arrears, and there are 127 claims.
  - **Poor:** by day 5 every faction is near zero credits and has scrapped its fleets, and there are no wars.
- **Cause: a logistics trap.** Station maintenance is met at only about 40%, which cuts taxes. The budget rule then blocks the haulers that would raise it.

**Open questions from the prototype:**
1. **Small-faction economies.** Factions with about 25 systems can't sustain themselves. Suspects: fixed overheads (starting fleets, upkeep) that don't scale with territory, and pirate attrition on thin logistics. Factions should also not declare or join wars while already exhausted.
2. **Coalitions need teeth.** Coalition members are often poor and have no fleets, so joining a war against a dominant aggressor changes little. Options: allies defend each other's systems, coalition members pool forces, or aggressors pay an economic penalty (trade embargoes).
3. **Economic snowball.** The strongest economy grows its territory and fleet the most, and the others hover near zero credits. Catch-up mechanics might be needed (for example, upkeep that rises faster than linearly with size).
4. **Pirate strength.** This is now in check (9 dens), but it is worth watching across seeds.

## What LT supplies

| Need | LT today | Plan |
|---|---|---|
| Gate graph | Regions with spanning-tree links (`Game/Object/Region.cpp`) | Reuse the topology in the Describe step |
| Markets when the player is present | Order books with escrow (`Component/Market.*`) | Seed from the state's prices and stock on entry; fold trades back on exit |
| Faction personality | `AI/Traits.h` | Utility weights |
| Physical NPC behaviour in the current system | Task chains (`Mine`, `Sell`, `Goto`, `Destroy`, `Dock`) | Turn abstract actions into ships doing things |
| Missions | Bounties paid in damage evidence (`Game/Mission.cpp`) | Mission type for reaction-phase contracts |
| AI corporations (`Task_Play`, projects) | Shallow planner | Superseded by the faction simulator |
| Off-screen simulation (`Task_LOD`) | Unused | Superseded |
