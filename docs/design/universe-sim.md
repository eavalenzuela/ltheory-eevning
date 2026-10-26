# Universe simulation

The universe simulation produces the activity a single-player EVE-like game has to fake: wars, trade, ownership changes, prices that move. EVE gets this from thousands of players; here the game has to do it.

Status: the proposal, decisions and design details below are agreed (2026-10-25). A headless prototype implements them (see "Prototype"); its war balance is the main open tuning question.

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
- The RNG for every roll is seeded from (universe seed, tick, action id), so the same save replays identically.
- **The universe state is the save file:** the universe seed plus the state (ownership, stock, prices, relations, fleets, active timers, player assets). Everything procedural (system layouts, hulls, item stats) is regenerated from seeds and never stored.

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

`resource/script/Sim/` implements the simulation in pure Luau, with no engine objects:

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
- **Ending wars.** A side is exhausted when it has less than two periods of running costs left, or its war fleet has fallen below half its strength at the start of the war. The exhausted side **sues for peace**: it cedes up to two border systems (besieged ones first) and pays 30% of its credits. If both are exhausted, the peace is white. A 10-hour truce follows.

**Results (seed 1, 400 systems, 20,000 ticks ≈ 55 game hours):**
- **Performance:** about 5 ms per tick, roughly 1/2000 of the 10 s budget. A full run takes about 110 s. The same seed gives identical results.
- **Economy:** stable and growing.
  - About 10,000 convoys per 2,500 ticks.
  - Station maintenance met at about 83% for both factions and independents.
  - Trade with independents roughly balanced, about 0.7–1 million credits each way per window.
  - No systems lost to arrears.
- **Expansion:** gradual. 106 claims; 88 independent systems remain at the end.
- **Fleets:** sized by income. A rich aggressive faction keeps about 200 cruisers, while two others decommission down to a few frigates.
- **War:** one full cycle, late in the run.
  1. The Iron Kestrel Union declares war on the Halcyon Accord.
  2. Kestrel launches assaults at 3:1 (260 against 45) and captures two systems through sieges.
  3. Halcyon sues for peace, ceding two systems and paying about 64,000 credits.

**Open questions from the prototype:**
1. **Pacing.** Wars arrive late, once expansion runs out of room; there was one war in 55 hours. More wars would come from stronger border friction or earlier land hunger.
2. **Pirate growth.** Pirate credits pile up with nothing to spend them on, and lost dens are never replaced.
3. **Fleet swings.** Factions overbuild cruisers, then decommission them. Smoother fleet planning would make fleet sizes steadier.

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
