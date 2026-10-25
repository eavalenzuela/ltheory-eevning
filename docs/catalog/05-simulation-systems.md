# 05 — Simulation Systems (Components, AI/Tasks, Attributes, Modules, Audio, misc)

Scope: `src/liblt/Component/`, `src/liblt/Game/Task/`, `src/liblt/Game/{Attribute,Action,Condition,Event}/`,
`src/liblt/AI/`, `src/liblt/Module/`, `src/liblt/Audio/`, `src/liblt/Network/`, `src/liblt/Strukt/`,
`src/liblt/ThirdParty/`. Where a fact depends on code outside this scope (Game/Object.h, Game/Project.cpp,
Game/Task.h, object files in Game/Object/), it was read for context and is cited, but those files belong to
other catalogers.

Everything below comes from reading the code. Nothing was run. Where runtime behavior is inferred, it is
marked **(inferred)**. Where I am unsure, it is marked **(uncertain)**.

---

## 1. Overview

| Subsystem | What it is | Health |
|---|---|---|
| Component model | ~45 mixin "components" composed into object classes through **template inheritance chains**. It is not a runtime ECS. Each component holds plain state plus an `OnUpdate` hook that chains to its base. | Solid core. Several components are inert data bags or dead. |
| AI economy | `Task_Play` (one per AI player) samples tasks from a per-system `ComponentEconomy` cache, wraps them in Buy/Sell chains, scores them by **gross = output value − input value + task value** from market EMAs, and turns them into a `Project` that hands the task to the player's ships. `Task_Manage` splits project revenue into four "metaprojects". | Runs live (this is where the "Add Project Mine -> Sell …" log line comes from). Loop is only partly closed: see §7. |
| Tasks | A per-object **task stack** (`ComponentTasks`). The top task is updated every frame, and a task can push sub-tasks (Goto, Dock). 19 task types. | Mine, Goto, Dock, Destroy, Sell, Wait, Play, Manage work. Others are partial, buggy, or unused. |
| Markets | A per-station, per-item **order book**: continuous double auction, midpoint pricing, escrow, and 27-depth EMA price/volume/supply/demand history. | Complete and the most portable piece. |
| Physics | No physics library. Explicit-Euler linear and angular motion with drag (`ComponentMotion`), a 2-level spatial hash broadphase (`ComponentQueryable`), and a triangle-mesh narrowphase (`PhysicsEngine` + `LTE/CollisionMesh`). | Works, but **collision only runs for human-owned ships**, and collision damage is hard-disabled. |
| Scheduler | Time-sliced serial jobs (adaptive batch sizing from measured time, `GL_Finish` fenced) plus up to 8 threaded jobs. | Complete. Used by procedural mesh generation (`LTE/SDFMesh.cpp`). |
| Sound | FMOD Ex 4.44 (`SoundEngine/Fmod.cpp`): 2D sounds, 3D sounds attached to objects (camera-relative positions), and an FMOD Designer event system for music. Null backend exists. | Works if FMOD initializes. Music engine is never instantiated. |
| Audio (offline DSP) | A small `Audio::` signal graph (instrument, delay, lowpass, compressor) rendered to a float buffer or WAV. | Built into liblt but only used by `src/old/soundstudio` (not built). Partly broken. |
| Network / Strukt | Empty stubs. | Dead. |
| ThirdParty | kdtree (BSD-3), Möller tri-tri overlap (via OPCODE), SMAA texture dimension headers. | Used by geometry and rendering code. |

---

## 2. Architecture

### 2.1 Component model (mixin chains, not an ECS)

**Declaration.** Every component is two pieces, declared in `Component/X.h`:

1. A data struct `ComponentX`, declared with `AutoClass(ComponentX, type, field, …)` (reflection macro from LTE). It holds state and usually a `Run(ObjectT* self, UpdateState&)` method.
2. A mixin template `Component_X<BaseT>`, declared with `AutoComponent(X)` (`Component/Common.h`). The mixin:
   - embeds `ComponentX X;` as a member;
   - adds `Pointer<ComponentX> GetX()`, which overrides a virtual on `ObjectT` that returns `nullptr` by default (`Game/Object.h:521`);
   - adds a `FIELDS` reflection block that maps the member and then chains to `BaseT::MapFields`;
   - overrides whichever `ObjectT` virtuals the component implements (`OnUpdate`, `SetSupertype`, `AddItem`, `GetCapability`, `OnMessage`, `Dock`, and so on), each calling `BaseT::…` to chain.

**Registry.** `COMPONENT_X` in `Game/Common.h:71` is an X-macro list of 45 names. It generates the `ComponentType` enum, forward declarations, the `virtual GetX()` stubs, and `ObjectT::HasComponent(type)`. `Info` and `Seeded` exist as components but are **not** in `COMPONENT_X`. `ComponentInfo` is reached through `GetInfo()` on the mixin. `GetSeed()` is a separate `ObjectT` virtual.

**Composition.** Each concrete object type is a `typedef` of nested mixins ending in `ObjectWrapperTail<ObjectType_X>` (`Game/ObjectWrapper.h`). Example from `Game/Object/Ship.cpp`:

```
ObjectWrapper< Component_Affectable< Component_Asset< Component_BoundingBox< Component_Cargo<
  Component_Collidable< Component_Crew< … Component_Tasks< ObjectWrapperTail<ObjectType_Ship> >…> ShipBaseT;
```

Consequences:
- The component set is fixed per type at compile time. There is no add/remove at runtime.
- Lookup is a virtual call, with no hashing.
- Per-frame update order is the mixin order. The **outermost mixin runs first** because each `OnUpdate` does its own work and then calls `BaseT::OnUpdate`.
- Functions such as `GetCapability`, `GetValue` and `GetHealth` are **aggregated by chaining**. For example, `Component_Sockets::GetCapability` adds up the capabilities of all plugged children.

**Update flow.**

```
launch.cpp  OnUpdate -> app Update (LTSL) -> e.g. ltheory.lts: container.Update dt  (Key_H = 20x time)
   ObjectT::Update(state)                       Game/Object.cpp:108
     OnUpdate(state)        -> mixin chain: Affectable -> Asset -> Collidable -> ... -> Motion -> MotionControl -> ... -> Tasks
     for child in children  -> child->Update   (sockets: thrusters, weapons, turrets, shields...)
   ComponentInterior::Run  -> updates every contained object, bucketed by ObjectType   Component/Interior.cpp
   ComponentPilotable::Run -> pilot->Update(state)   (the PLAYER object is updated through its ship)
then launch.cpp: physicsEngine->Update() (collision-mesh cache eviction), soundEngine->Update()
```

`UpdateState` (`Game/UpdateState.h`) carries `dt` (float seconds), `quanta = dt * kTimeScale(1000)`, and `hasFocus`.

**Steering pipeline.** This is a one-frame-lag chain, implied by the mixin order:

```
Task (Goto/Mine/Destroy/Patrol) pushes SDF_Sphere targets into ComponentMotionControl.elements
  next frame: MotionControl::Run takes the gradient of the summed SDFs at the predicted position (pos + v/drag)
              -> Broadcast(MessageThrustLinear dir), Broadcast(MessageThrustAngular pitch/yaw)
  child Thruster objects receive the messages -> add force to root ComponentMotion
  next frame: Motion::Run integrates
```

Humans steer through `ShipAffector` (`Game/Widget/HUD.cpp:36`), an `Affector` on the player's `ComponentAffectable`. It broadcasts the same thrust messages, and it yields whenever the ship has a current task ("Autopilot overrides manual control").

**Messaging.** `ObjectT::Broadcast(Data&)` sends a reflected value down the tree. `Component_Interior` re-broadcasts to its contents. `Send` targets one object. Typed messages live in `Game/Messages.h` (ThrustLinear/Angular, Fire, TargetPosition, TargetObject, Boost, Cruise, Waypoint, StartUsing/StopUsing, Ejected, Launch, …). `Component_Tasks::OnMessage` forwards to the top task. `Component_Scriptable::OnMessage` forwards to the script's `Receive`.

**Serialization / reflection.** Every component is an `AutoClass`, so its fields are reflected through `FIELDS`/`MapFields`, and the `AutoComponent` FIELDS chain reflects the whole object. Script field access and the LTE generic `LoadFrom/SaveTo` (used by `Module/Settings.cpp`) depend on this. Explicit gaps:
- `ComponentDrawable` says "CRITICAL : Serialization of renderable" and its renderable is not a mapped field.
- `ComponentQueryable` is `AutoClassEmpty`.
- `ComponentOrientation::version/myVersion` are unmapped.
- I found **no save-game code** in my area **(uncertain whether one exists elsewhere)**.

### 2.2 Tasks (per-object behavior stack)

`TaskT` (`Game/Task.h`) is a ref-counted, stateless **description** of a job. Per-agent state lives in a `TaskInstance { Task task; Data data; float duration; }`. The `Data` is a reflected variant, which each task fills in `OnBegin` with its own `AutoClass` instance struct.

| `TaskT` member | Meaning |
|---|---|
| `GetInputs/GetOutputs(Vector<ItemDelta>)` | Items consumed or produced per cycle. `ItemDelta{item, node, delta}`. A `node == nullptr` means "not yet bound to a market". |
| `GetValue()` | Credits produced per cycle. Buy/Sell wrappers fold prices in here. |
| `GetDuration()` | Cycle time, used for `grossRate`. |
| `GetAlignment()` | −1 hostile … +1 friendly. Used to filter out "lawless" tasks. |
| `GetRateFactor/GetScaleFactor/GetRequirements()` | Capability weights (Attack, Motion, Transference, …). **Declared and returned, but never consumed by any planner code I could find.** |
| `CanPerform(owner)` | Number of cycles possible given the input items in the owner's storage lockers (`Game/Task.cpp`). |
| `IsFinished / OnBegin / OnUpdate / OnEnd / OnMessage` | Execution hooks. |

`ComponentTasks` (`Component/Tasks.cpp`) only updates the **top** `TaskInstance`, then pops finished tasks and calls `OnEnd`. A task that needs travel pushes `Task_Goto` or `Task_Dock` on top of itself and resumes once that finishes. `TaskInstance::IsFinished` always returns false until the first update has happened.

### 2.3 AI decision model ("Playing Limit Theory")

```
System.lts: player = Player_AI traits; player.Pilot ship; player.PushTask(Task_Play player)
            (Player object is updated every frame via ComponentPilotable on its ship)

Task_Play::OnUpdate  (Game/Task/Play.cpp)           -- every frame
 1. FindProject():
      economy = nearest ancestor container with ComponentEconomy (the System)
      task = economy->tasks.random()                       <-- random sampling, not search
      if task.alignment < 0 and traits.Lawless < -alignment: reject
      for each input with node==null:  task = Task_Buy (random market node, item, 10*delta, task)
      for each output with node==null: task = Task_Sell(random market node, item, 10*delta, task)
      ConsiderProject(task):
         project = Project_Create(player, task); project->UpdateGross()
         gross = Σ output.delta*EMA price - Σ input.delta*EMA price + task->GetValue()
         if gross >= kMinProfit(1) and projects.size() < kMaxProjects(1): add  -> dbg "Add Project <name> (<grossRate>)"
         (project replacement / switching is #if 0'd "CRITICAL : Project switching removed")
 2. Allocate free assets: every owned asset with ComponentTasks and no project -> Project_Allocate(best project)
      ("best" = first project; allocation score is a TODO constant 1.0); ship renamed "<Faction> <Noun> #n"
 3. ManageProject: runs project->management.task (= Task_Manage) with the player as manager
 4. SpawnNew(): while assets < 16 and credits > 1000: buy ship of value Pow(Rand(),8)*credits,
      rounded to a power of 10 (cost = value/100), plug 1-3 transfer units + fill weapon slots,
      spawn 1000 m from the player's ship.

ComponentEconomy::Run (Component/Economy.cpp) -- every frame on the System, rebuilds from scratch:
   nodes = all objects with ComponentMarket; items = all items seen in cargo/markets/zone resources
   tasks = Mine(zone) + Pirate(zone) per resource zone
         + Transport(a,b,item) both ways for every market pair x every listed item
         + Produce(chip) per AssemblyChip seen, Mint(bp) + Research(bp) per Blueprint seen

ProjectT::Update (Game/Project.cpp) -- via ComponentProjects on the Player
   - with probability ~dt/1s: UpdateMarketOrders(): bids for remaining inputs at EMA price,
     asks for outputs found in lockers at noisy sell price
   - book filled sells into metrics.revenue; 90% (settings.feedback=0.9) of revenue is moved from
     the owner's credits into project->wallet
   - drop dead assets (metrics.losses), detect idle assets (no current task)
   - dispatch: for each idle allocated asset (up to CanPerform): ClearTasks(); PushTask(project->task)

Task_Manage (Game/Task/Manage.cpp): splits project->wallet across metaprojects
   Develop 0.2 (TODO) | Expand 0.3 (TODO, creates an empty TemplateT) | Secure 0.3 (TODO)
   Monopolize 0.2: if a competitor has asks for the project's sell item, posts a Mission
                   "Damage the Enemy" (reward pool = wallet, paid per DataDamaged item of that owner)
                   on the market node's mission board.
```

So the "planner" is **random sampling, then a greedy profitability threshold, with one project per player for life**. There is no utility AI, GOAP or HTN. The interesting ideas are the **composable task algebra** (`Sell(Sell(Sell(Mine)))` folds prices into `GetValue` and peels the matching outputs off) and the **market-EMA valuation**. The log line `Add Project Mine -> Sell Kygen -> Sell Vierxite -> Sell Gamsite (1890)` is exactly `TaskSell::GetName()` (`inner + " -> Sell " + item`) wrapped three times around `Task_Mine`, for a zone with three ore types.

`Traits` (`AI/Traits.h`) is a 7-float X-vector: Aggressive, Creative, Explorative, Greedy, Intellectual, Lawless, Sociable. `XSIZE` is 6 while the list has 7 entries. `LTE/XVector.h` uses `XSIZE` for `size()`, `ToStream` and the `Vec<>` arithmetic, so `Sociable` is left out of vector operations (minor bug). Only `Lawless` is read, in `Task_Play::FindProject`. All fields default to 0 (`XVector.h` constructor). `System.lts` creates AI players with default traits, so Lawless = 0 and the Pirate task, with alignment −1, is always rejected for them.

### 2.4 Attributes / Actions / Conditions / Events

- **Attributes** (`Game/Attribute/*.h`) are the **item-type ("supertype") counterpart of components**. Each is a `template<class T> struct Attribute_X : T` with one field, a getter, a `HasX()` method, and a reflection entry (`ATTRIBUTE_COMMON`). Item types such as `ShipType` and `WeaponType` are mixin chains of attributes (`Attribute_Mass< Attribute_Value< … ItemWrapper<…> > >`). When an object is created, each component's `SetSupertype(type)` pulls its values from the item: Integrity←integrity, Motion←mass/inertia, Cargo←capability.Storage, Sockets←sockets, Dockable←docks, Drawable←renderable, Nameable←name. **They are static stats, not character skills.** There is no skill or progression system.
- **Actions** (`Game/Action.h`): `ActionT::Execute(UpdateState&)`, which is an immediate effect. There is one action. `Action_Mine(object, target, point)` (`Game/Action/Mine.cpp`) is called from the TransferUnit beam (`Game/Object/TransferUnit.cpp:190`). Yield is `exp(-6(1-dot(hitPhase, asteroidPhase))) * dt * RandExp * quantity * 0.25`, so you mine faster at the asteroid's "sweet spot" direction. It adds ore to the root's cargo, decrements `ComponentMineable.quantity`, and records `Event_Mined` into the container's `ComponentHistory`.
- **Conditions**: one free function, `Condition_Nearby(a, b, d)` (same container and surface distance ≤ d).
- **Events** (`Game/Event.h`, `Events.h`) are factory functions with side effects that also return a record object:
  - `Event_Damage` applies damage, calls `destOwner->OnAttacked(sourceOwner)` (opinion −1), and gives the attacker `Item_Data_Damaged(dest) × damage`. These "proof of damage" data items are what missions pay for.
  - `Event_Deposit` moves items into the owner's station locker. It returns nullptr, and its only caller is commented out.
  - `Event_Mined` is a record only.
  - `Event_Destroyed` is declared but has **no definition**.
  - `Event_Withdraw` is `#if 0`.

### 2.5 Physics model

| Aspect | Implementation | File |
|---|---|---|
| Integration | Explicit Euler. `force -= v*m*kLinearDrag(0.8)`, `torque -= ω*I*kAngularDrag(2)`, `v += F/m dt`, `ω += τ/I dt` (scalar inertia, "should be inertial tensor"), `pos += v dt`, `RotateBasis(ω dt)`. Forces are cleared each frame. Top speed = maxThrust / (0.8·mass). The model is "space with drag" (arcade/EVE-like, not Newtonian). | `Component/Motion.cpp` |
| Thrust | Thruster children receive `MessageThrustLinear/Angular/Cruise` and add to the root's force. Cruise raises the power request 100×. A power grid exists: `PowerGenerator` splits power proportionally to `ComponentPluggable.powerRequest × priority`, and `GetPowerFraction` scales thrusters, beams, scanners and shield recharge. | `Game/Object/Thruster.cpp`, `PowerGenerator.cpp`, `Component/Pluggable.*` |
| Broadphase | `ComponentQueryable` on each System is a 2-level spatial hash (cell size 1024, 4096 buckets, static level ×2). Static objects are inserted once. Movable objects are cleared and re-inserted **every frame** (`Run` sets dirty). Box queries dedupe with `BoundingBox.queryVersion`. Ray queries march the hash and call `PhysicsEngine::Raycast`. `LTE_ASSERT(marchDistance < 100000)`. | `Component/Queryable.cpp` |
| Narrowphase | `PhysicsEngine::CheckCollision` does triangle-mesh vs triangle-mesh with `LTE/CollisionMesh` (uses ThirdParty `TriTriOverlap`). Meshes are cached by renderable hash and evicted after 120 s unused (`PhysicsEngine::Update`). A Null engine exists. The engine is a push/pop global stack. | `Module/PhysicsEngine.cpp` |
| Collision response | Velocity along the contact normal is removed, scaled by `1.5 × otherMass/(m1+m2)`. No angular response, no restitution model. Collision damage is computed and then blocked by `if (false && …)` ("CRITICAL Don't apply any collision damage...ever"). | `Component/Collidable.cpp` |
| Who collides | `CheckCollisions` returns early unless **the owner is human** ("CRITICAL. Never check collisions for non-player objects"), the window has focus, and the object can move. **AI ships pass through everything.** Weapons use `ComponentDamager::Hit` from projectile and beam code, not this path. | `Component/Collidable.cpp:61` |
| Docking | `Dockable::Dock` moves the docker into the station's `Interior` at a random point in a random hangar box and zeroes its motion. `Undock` puts it back in the parent container near a random port at 1.25–5× radius. There is no approach or capacity logic: `CanDock` returns `docked >= capacity`, which looks inverted, `docked` is never incremented, and nothing calls `CanDock`. | `Component/Dockable.cpp` |
| Navigation | `Task_Goto` runs Dijkstra over {self, target, all `ComponentNavigable` nodes}. Free-flight edges cost Euclidean distance, and warp-rail links cost 0 (`WarpNode.cpp` `MessageLink` pushes cost 0). Riding a rail uses `MessageStartUsing`/`MessageWaypoint`/`MessageEjected`. It undocks if the target is in the parent container. **Inter-system travel is unimplemented** ("CRITICAL"). | `Game/Task/Goto.cpp` |

### 2.6 Scheduler (`Module/Scheduler.cpp`)

- `Scheduler_Get()` is a lazily created global module (`Module_RegisterGlobal`) that the Program loop updates every frame (`Module_UpdateGlobal`).
- **Serial jobs:** each frame has a budget of `kMaxRunTime = 1/60 s`. It picks the highest-`GetPriority()` job with `CanRun()`. It calls `GL_Finish` once before the first job, then runs `OnRun(jobSize)` where `jobSize = remainingTime / (job.totalTime / job.totalUnits)`, so the batch is sized from the job's measured average cost per unit. It then calls `GL_Finish` again so GPU time is measured, and accumulates `totalTime`/`totalUnits`. Finished jobs get `OnEnd` and are removed.
- **Threaded jobs:** at most 8 concurrent threads and `kMaxMemoryUsage` = 1 MiB, summed from `Job::GetMemoryUsage()`. FIFO launch.
- `Flush()` spins `Update()` until all jobs are done. Called from `LTE/SDFMesh.cpp:121`.
- Users: `LTE/SDFMesh.cpp`, which handles field textures, LOD levels, occlusion bakes and `Polygonize` (threaded). The recent commit 87d399f split the GPU occlusion bakes to avoid GPU timeouts.
- Quirk: `GetBestJob(remainingTime)` ignores its parameter.

### 2.7 Audio

> **Update (Oct 2026):** the FMOD Ex backend described below has been replaced by `Module/SoundEngine/Miniaudio.cpp` (vendored miniaudio 0.11.21 + stb_vorbis, public domain) behind the same `SoundEngine`/`SoundT` interface. The script API is unchanged. Missing files and missing audio devices are no longer fatal (the launcher falls back to the Null engine). Pitch is now relative to each file's own sample rate. `MusicEngine` and the FMOD music-bank code were deleted. This section is kept as a record of the original design.

**Runtime sound (`Module/SoundEngine*`)**
- `SoundEngine` is an abstract module on a push/pop global stack. `launch.cpp` hard-codes `SoundEngine_Fmod()`. There is no fallback to `SoundEngine_Null()`.
- FMOD Ex setup (`Fmod.cpp`):
  - `FMOD::EventSystem_Create`, DSP buffer 2048×4, 128 software channels, 1024 virtual voices.
  - `init(…, FMOD_INIT_HRTF_LOWPASS & FMOD_INIT_VOL0_BECOMES_VIRTUAL, …)` uses **bitwise AND** of 0x10 and 0x80, which equals **0**, so neither flag is set (bug).
  - `FMOD_EVENT_INIT_USE_GUIDS`, `setMediaPath("resource/music/")`.
- Sound files are read from `resource/sound/<file>` (17 category folders: ship, thruster, weapon, warpnode, techlab, …) via `Location_Resource` and created with `FMOD_OPENMEMORY` (the whole file is loaded into memory). The `FMOD::Sound` is cached per path and never released.
- **3D:** each `Sound3DInstance` holds a carrier `Object` plus an offset. Every frame the listener is set at the **origin**, and each sound's position is set as `carrierWorldPos − cameraPos`, which is camera-relative and avoids float precision problems at 100 km scales. Velocity is scaled by 1/50 for doppler, and min/max distance is `50·size … 100000`. Instances are dropped when the carrier is deleted, the sound finishes, or `Delete()` is called.
- `CheckError` calls `error()` (fatal) on any FMOD failure, including missing sound files and probably a missing audio device **(inferred)**.
- `SoundImpl::~SoundImpl` only **pauses** its channel. A dropped looped sound may hold a paused channel **(uncertain whether FMOD steals it)**.
- `Play(Array<float>)` plays a raw mono PCM float buffer. This is the hook for the offline `Audio::` synth.
- Script API (`Module/ScriptAPI/SoundEngine.cpp`): `Sound_Play`/`Sound_PlayLooped` (2D and 3D overloads), `Delete`, `IsFinished`, `GetDuration`, `SetCursor`, `RandomizePosition`, `SetPitch`, `SetVolume`, `Sound_None`. Ship engine hum, warp-node drones and similar live in LTSL `Scriptable` objects (`Object/Ship.lts`, `Object/WarpNode.lts`).

**Music (`Module/MusicEngine.cpp`)**
- Loads the FMOD Designer project `LtheoryTest01.fev`, which is in `resource/music/` together with `LtheoryTest01_bank00.fsb`, `LT_Music.fev` and `System01.fsb`.
- Starts the event GUID `{8d4e1467-…}` ("Space01 music") and drives two parameters, *tension* (`SPACE01_EX_BT_END`) and *volume (closing in)*, from `GenericFloat` callbacks.
- `MusicEngine/LtheoryTest01.h` is generated by FMOD Designer v4.44.20.
- **Never instantiated** by `launch.cpp`. Old `src/old/ltheory/ltheory.cpp:94` also has it commented out.

**Offline synth (`Audio/`)**
- Pull-based `Audio::SignalT` graph with a one-sample cache per node. Node types: `Signal_Instrument` (Generator + Note pattern + envelope), `Signal_Delay`, `Signal_Lowpass`, `Signal_Compress`, `Signal_Sum`, `Signal_Product`.
- `Signal_Render(signal, seconds)` returns a normalized float array. `WAV_Write` writes an int PCM WAV.
- Only `src/old/soundstudio` (not built) uses it.
- `Signal_ASR` is declared but **not defined**. `Envelopes.cpp`'s `ASRImpl` derives from `Audio::Signal`, which is the `Reference<>` typedef rather than `SignalT`, so it is nonsense that happens to compile.
- `Note`'s constructor never sets `duration`.

### 2.8 Networking

- `Network/Client.h` declares an empty `struct Client` and `Client_Create()`, with no definition. `Network/Common.h` forward-declares Client/Host/Peer.
- enet headers ship in `include/enet` and binaries in `extbin/linux64/libenet.so*`, but `enet` is commented out of `LINK_LIBRARIES` in `CMakeLists.txt`.
- SFML's `sfml-network` *is* linked (SFML is built statically), but nothing in my area uses it.
- **No networking exists.**

---

## 3. File inventory

Status key: **C** = complete for its purpose, **P** = partial, **S** = stub, **D** = dead (unused or unreachable), **B** = has a notable bug.

### 3.1 `src/liblt/Component/` (82 files)

| File(s) | Purpose | Status |
|---|---|---|
| Common.h | `AutoComponent(x)` macro | C |
| Account.h/.cpp | Credits balance. Script: AddCredits/GetCredits/RemoveCredits | C |
| Affectable.h | List of timed `Affector`s run each update (used by HUD ShipAffector for human control) | C |
| Asset.h/.cpp | Owner link. Grants owner Scan info. On death, logs and removes from owner | C |
| Assets.h/.cpp | Owned objects list. Sums asset capability. Script iterator | C |
| Attachable.h/.cpp | Local transform relative to parent. Composes world transform into Orientation | C |
| BoundingBox.h/.cpp | Cached world AABB and radius, version-tracked. Grid bookkeeping | C |
| Cargo.h/.cpp | Item→quantity map with mass capacity (recomputed each change). Script iterator | C |
| Collidable.h/.cpp | Broadphase+narrowphase collision and response. **Human-owned only, no damage** | P/B |
| Crew.h | `Vector<Item>`, never populated | S/D |
| Cullable.h | Cull distance² = 500·radius·mult, squared | C |
| Damager.h/.cpp | Projectile/beam hit → effect + `Event_Damage` (beam damage × power × dt) | C |
| Database.h | Data-item store (StorageType_Database). Copy tracking commented "CRITICAL" | C |
| Detectable.h | `detectionTime` (60e6) for Info expiry | C (expiry inert, §7) |
| Dockable.h/.cpp | Hangars/ports. Dock/Undock teleport. `CanDock` inverted and unused | P/B |
| Drawable.h/.cpp | Renderable holder plus draw. Renderable not serialized | C |
| Economy.h/.cpp | Per-system cache of market nodes, items, candidate tasks. **Rebuilt every frame** | C (perf) |
| Explodable.h/.cpp | Spawn explosion effect once when integrity ≤ 0 | C |
| History.h/.cpp | Event log (Mined events). `Run` is empty. Script iterator | C (thin) |
| Info.h/.cpp | Player knowledge map ObjectID→{InfoLevel, expiration} | C (expiry inert) |
| Integrity.h/.cpp | Health/maxHealth. `ApplyDamage` → `OnDeath`. Lazy DataDamaged/Destroyed items | C |
| Interior.h/.cpp | Container: owns and updates children by type, particle system, iterators | C |
| Log.h/.cpp | Player message log (time, message, importance). Script iterator | C |
| Market.h/.cpp | Order book, matching, escrow, EMA history. Script API | C |
| Mineable.h | Ore item, quantity, "phase" sweet-spot vector | C |
| MissionBoard.h | Station mission listings. Purges deleted missions | C (thin) |
| Missions.h | Player's accepted missions. `Run` empty | S |
| MotionControl.h/.cpp | SDF-gradient steering → thrust messages | C |
| Motion.h/.cpp | Linear/angular Euler integration with drag. Script API incl. `GetImpact` lead calc | C |
| Nameable.h/.cpp | Name string | C |
| Navigable.h | Graph edges (dest, cost) for warp rails/nodes | C |
| Opinion.h | Opinions map ObjectID→[-1,1]. Never forgets ("TODO : Memory issues") | C |
| Orders.h | Player's open market orders. Purges filled ones | C |
| Orientation.h/.cpp | World transform plus version counter, lazy orthogonalize. Script getters/setters | C |
| Pilotable.h/.cpp | Pilot pointer. **Updates the pilot Player each frame** | C |
| Pluggable.h/.cpp | Socket index, power in/out/request/priority. Joint constraints (AxisX/Y/Z/Fixed) | C |
| Projects.h/.cpp | Player's projects. Updates each | C |
| ProximityTracker.h/.cpp | Every 60 frames, lists nearby ships/stations/asteroids/planets within 2 km | D (no object uses it) |
| Queryable.h/.cpp | Spatial hash for container contents. Box and ray queries | C |
| Resources.h/.cpp | Weighted `Distribution<Item>` of natural resources | C |
| Scriptable.h/.cpp | LTSL script objects with `Update(self)->Bool` and optional `Receive(self,msg)` | C |
| Seeded.h | Seed value (not in COMPONENT_X) | C |
| Sockets.h/.cpp | Hardpoints: plug item/object into typed slot, unplug, capability/value aggregation | C |
| Storage.h/.cpp | Per-owner locker at a station (lazily creates a `Pod` with capacity 100000) | C |
| Supertyped.h | Item "type" pointer. Icon | C |
| Targets.h/.cpp | Target list (script managed) | C |
| Tasks.h/.cpp | Task stack plus allocated Project | C |
| Zoned.h/.cpp | SDF region and fog density. `Object_GetZone` = max containment > 0.5 | C |

### 3.2 `src/liblt/Game/Task/` (19 files). See §5 for behavior.

| File | Status |
|---|---|
| Buy.cpp | P/B (never places a bid; see §7) |
| Custom.cpp | P (no dt, no IsFinished, inputs/outputs not bound; unused) |
| Destroy.cpp | C |
| Dock.cpp | C |
| Drill.cpp | C (unused) |
| Goto.cpp | P (in-system only) |
| LOD.cpp | P/D (abstract off-screen production; never instantiated) |
| Manage.cpp | P (1 of 4 metaprojects implemented) |
| Mine.cpp | C |
| Mint.cpp | C (reachable only if blueprints exist) |
| Patrol.cpp | C (unused by AI) |
| Pirate.cpp | B (target never re-chosen; `GetOutput` typo) |
| Play.cpp | P (one project per player, random sampling) |
| Produce.cpp | P/B (`GetOutput` typo means no declared outputs) |
| Research.cpp | C (reachable only if blueprints exist) |
| Sell.cpp | C ("This breaks metrics") |
| Spawn.cpp | S (body `#if 0`; `GetOutput` typo) |
| Transport.cpp | S/B (shuttles between docks but moves no goods) |
| Wait.cpp | C |

### 3.3 `src/liblt/Game/Attribute/` (29 files)

All are single-field mixins of the same shape (C). Item types using each:

| Attribute | Field | Used by item types |
|---|---|---|
| Capability | `Capability` (Attack…Transference) | PowerGenerator, ProductionLab, Ship, Station, TechLab, Thruster, TransferUnit, Weapon |
| Color | `Color` | Thruster, Weapon |
| Common.h | `ATTRIBUTE_COMMON` reflection macro | — |
| Damage | `Damage` | Weapon |
| Density | float t/m³ | **unused (D)** |
| Docks | `Vector<Bound3>` + capacity (not reflected) | Planet, Station |
| Hash | `HashT` | DataDamaged, DataDestroyed |
| Icon | `Icon` | most item types |
| Integrity | `Health` | Shield, Ship, Station, Thruster, Weapon |
| Level | float | **unused (D)** |
| Mass | `Mass` (tonnes) | most physical types |
| Metatype | `Data` | ProductionLab, Scanner, Ship, Station, Thruster, TransferUnit |
| Name | `String` | all named types |
| Object | `Object` | DataDamaged, DataDestroyed (the object the data refers to) |
| Offset | V3 | Thruster, TransferUnit, Weapon |
| PowerDrain | float | labs, Scanner, Shield, Thruster, TransferUnit, Weapon |
| Properties | V3 | Weapon |
| Range | float | Scanner, TransferUnit, Weapon |
| Rate | float | Weapon (fire rate) |
| Renderable | `Renderable` | Planet, Ship, Station, Thruster, TransferUnit, Weapon |
| Scale | float | most physical types |
| Seed | uint | Planet |
| Sockets | `Array<Socket>` (not reflected) | Ship, Station |
| Sound | `String` | Weapon |
| Speed | float | DroneBay, Weapon (projectile speed) |
| Task | `Task` | ColonyType (colony pushes it on creation, `Colony.cpp:265`) |
| Traits | `Traits` | Player (AI personality), ColonyType, Colony, Region, System |
| Uses | `Quantity` | Weapon (magazine; `kInfiniteAmmo = true` in Weapon.cpp) |
| Value | `Quantity` | most item types (base price) |

### 3.4 Action / Condition / Event / AI

| File | Purpose | Status |
|---|---|---|
| Game/Action/Mine.cpp | Mining yield action (see §2.4) | C |
| Game/Condition/Nearby.cpp | `Condition_Nearby` | C |
| Game/Event/Damage.cpp | Apply damage, notify owner, award DataDamaged | C |
| Game/Event/Deposit.cpp | Move items to locker (only caller commented out) | D |
| Game/Event/Mined.cpp | Mining record | C |
| AI/Traits.h | 7-trait personality vector | C (only Lawless read) |
| AI/Types.h | Forward declarations | C |
| AI/NLPContext.h, NLPPhrase.h/.cpp | Tiny English phrase builder (articles, capitalization, "for ages") | D (no users found in src) |

### 3.5 `src/liblt/Module/` (21 files)

| File | Purpose | Status |
|---|---|---|
| Common.h | Forward declarations, `Sound` typedef | C |
| FrameTimer.h/.cpp | Global frame dt plus EMAs (0.5 s / 1 s / 10 s) | C |
| PhysicsEngine.h/.cpp | Mesh-collision/raycast service and Null engine, global stack | C |
| Scheduler.h/.cpp | Time-sliced and threaded job scheduler | C |
| Settings.h/.cpp | Hierarchical persistent settings (`<userdata>/settings.bin`, version 8), Generic* accessors, settings widget | P (leaf widgets return nullptr, so the settings UI shows no editors) |
| SettingsEntry.h/.cpp | Typed setting entries (Axis/Bool/Button/Color/Float) | P (no `GetWidget` overrides) |
| Sound.h | `SoundT` interface | C |
| SoundEngine.h/.cpp | Abstract engine plus global stack, `Sound_Play2D/3D` helpers | C |
| SoundEngine/Fmod.h/.cpp | FMOD Ex backend plus `SoundEvent`/`LoadProject` | C/B (init flags) |
| SoundEngine/Null.cpp | Silent backend | C (not selectable at runtime) |
| ScriptAPI/SoundEngine.cpp | LTSL bindings | C |
| MusicEngine.h/.cpp | Adaptive FMOD Designer music | D (never created) |
| MusicEngine/LtheoryTest01.h | FMOD Designer generated IDs/GUIDs | C |

### 3.6 Audio, Network, Strukt, ThirdParty

| File | Purpose | Status |
|---|---|---|
| Audio/Audio.h, Common.h | Umbrella header and forward declarations | C |
| Audio/Generator.h | `GeneratorT::Get(note, t)` oscillator interface (no implementations here) | S |
| Audio/Note.h | Note {on, off, freq, duration, velocity}, `Pattern` | B (duration uninitialized) |
| Audio/Signal.h/.cpp | Signal base with per-sample cache, `Signal_Render` | C |
| Audio/Signals.h | Node factory declarations | P (`Signal_ASR` undefined) |
| Audio/Envelopes.cpp | ASR envelope | B/D |
| Audio/Filters.cpp | Sum/Product | C |
| Audio/IO.h/.cpp | WAV writer | C |
| Audio/Signal/{Compress,Delay,Instrument,Lowpass}.cpp | DSP nodes | C |
| Network/Client.h, Common.h | Empty declarations | S/D |
| Strukt/CodeObject.h, CodeObjects.h, Common.h, CodeObject/Custom.cpp | Visual "code object" editor stub. `CodeObject_Custom` ignores its data and returns placeholder name/type/null widget. `App/strukt.lts` defines only its own UI types and never calls into these files. | S/D |
| ThirdParty/KDTree.h/.cpp | kdtree by John Tsiombikas, **BSD 3-clause** (header). Used by `LTE/Mesh.cpp` (nearest-vertex welding) | C |
| ThirdParty/TriTriOverlap.cpp | Möller's triangle–triangle overlap test, apparently taken from **OPCODE** (Pierre Terdiman) given the `OPC_TRITRI_EPSILON_TEST` comment. **No license header in the file (uncertain license)**. Used by `LTE/CollisionMesh.cpp` | C |
| ThirdParty/SMAA_AreaTex.h, SMAA_SearchTex.h | Only width/height defines for SMAA lookup textures. The data is loaded from `SMAA_AreaTex.bin`/`SMAA_SearchTex.bin` by `Game/RenderPass/SMAA.cpp`. SMAA (Jimenez et al.) is MIT-style licensed, but **no license text is present** | C |

Repository license (`LICENSE`): **Unlicense / public domain**.

---

## 4. Component catalog

"Objects" lists the object types whose mixin chain includes the component, taken from `Game/Object/*.cpp`, `Game/Player.h`, `Universe.h`, `Camera.h`, `Light.h` and `Beam.h`.

| Component | State | Per-update behavior | Objects | Script / C++ users |
|---|---|---|---|---|
| Account | credits | — | Colony, Player | Market escrow, Project wallet, Play spawn. Script `AddCredits`… |
| Affectable | `Vector<AutoPtr<Affector>>` | runs/expires affectors | Ship, Station, Player | HUD `ShipAffector` (human flight + camera) |
| Asset | owner `Player` | grant owner Scan info; on death log + unregister | Ship, Station, Colony | Script `GetOwner` |
| Assets | `Vector<Object>` | — (capability sum) | Player | Play allocation/spawn. Script `AddAsset`, `GetAssets` |
| Attachable | local transform, moved flag | compose world transform from parent | DroneBay, Explosion, Shield, Thruster, Trail, TransferUnit, Turret, Weapon, Colony, Light | Sockets, Pluggable joints |
| BoundingBox | world AABB, radius, versions, grid level | (recompute on demand) | most physical objects | Queryable, Collidable, culling. Script `GetBound` |
| Cargo | item→qty, mass, capacity | — | Ship, Station, Colony, Pod | tasks, Action_Mine, Market lockers. Script `GetCargo`, `AddItem`… |
| Collidable | passive, solid | collision check (human-owned only) | Asteroid, Planet, Pod, Shield, Ship, Station, Thruster, Turret, Weapon | Damager::Hit, raycast filters |
| Crew | `Vector<Item>` | — | Ship, Station | none |
| Cullable | cull distance² | — | most visible objects | renderer culling |
| Damager | weapon type, source | — (Hit called by projectile code) | Missile, Pulse, Rail, Beam | Shield `CanCollide` |
| Database | data item→qty | — | Ship, Pod | DataDamaged/Destroyed storage (mission proof) |
| Detectable | detectionTime | — | Asteroid, Planet, Ship, Station, WarpNode, Wormhole | Info |
| Dockable | hangars, ports, docked, capacity | — | Station, Colony | Task_Dock, Task_Goto (undock) |
| Drawable | renderable | draw | nearly all | PhysicsEngine (collision mesh source). Script `SetRenderable` |
| Economy | nodes, items, tasks | full recache every frame | System | Task_Play |
| Explodable | exploded, type | explosion effect when health ≤ 0 | Ship, Station, Shield, Thruster, Weapon | — |
| History | `Vector<Event>` | — | System | Action_Mine. Script `GetHistory` |
| Info | ObjectID→{level, expiry} | — | Player | Asset, Scanner (`Game/Object/Scanner.cpp`) |
| Integrity | health, maxHealth, data items | — (ApplyDamage→OnDeath) | Ship, Station, Shield, Thruster, Weapon | Event_Damage, Explodable. Script `GetHealth`, `SetHealth` |
| Interior | objects, objectMap by type, particles | update all children, particles | System, Region, Station, Colony, Universe | everything spatial. Script `AddInterior`, `GetInteriorObjects` |
| Log | entries | — | Player | Asset, Research, HUD log widget (`Widget/HUD/Log.lts`) |
| Market | item→MarketData | match orders, EMA every 1 s | Station, Colony | Project, Sell/Buy tasks, Market UI scripts |
| Mineable | item, quantity, phase | — | Asteroid | Action_Mine, Task_Mine |
| MissionBoard | missions | purge deleted | Station, Colony | Task_Manage (Monopolize) |
| Missions | missions | — | Player | (mission UI, outside scope) |
| Motion | force, torque, v, ω, mass, inertia, speed | integrate | Ship, Pod, Missile, Payload, Dynamic, Custom, SoundEmitter, Camera | thrusters, collision, Fmod doppler |
| MotionControl | `Vector<SDF>` | SDF-gradient steering → thrust messages | Ship | Goto, Mine, Destroy, Patrol |
| Nameable | name | — | most | Script `GetName`/`SetName` |
| Navigable | edges (dest, cost) | — | WarpNode, Wormhole | Task_Goto pathfinding |
| Opinions | id→opinion, default | — | Player | Event_Damage→OnAttacked, Task_Destroy (−1 per frame). `Likes`/`Dislikes` (±0.5) are never called |
| Orders | open orders | purge filled | Player | Market |
| Orientation | transform, version | lazy orthogonalize | nearly all | everything. Script pos/look/up/scale |
| Pilotable | pilot | **updates the pilot Player** | Ship, Station | PlayerImpl::Pilot/Unpilot |
| Pluggable | socket index, power in/out/request, priority | — | DroneBay, PowerGenerator, ProductionLab, Scanner, TechLab, Thruster, TransferUnit, Turret, Weapon | PowerGenerator, joints |
| Projects | `Vector<Project>` | update each project | Player | Task_Play. Script `GetProjects` |
| ProximityTracker | nearby, maxDistance, counter | periodic proximity query | **none** | — |
| Queryable | spatial hash impl | rebuild dynamic level | System | Collidable, raycasts, ProximityTracker |
| Resources | `Distribution<Item>` | — | Region, System, Zone, Planet, Universe | Economy, Mine/Drill outputs. Script `AddResource` |
| Scriptable | script elements (object, Update, Receive) | call script Update | Ship, Colony, Custom, Thruster, WarpNode, Player | `Object/Ship.lts`, `Colony.lts`, `WarpNode.lts`, `Widget/Handling.lts` |
| Seeded | seed | — | Asteroid, Colony, Region, System, Zone, Planet, Universe | procedural generation |
| Sockets | socket defs, plugged instances | — (capability/value sums) | Ship, Station, Turret | Play spawn, Destroy/Mine (weapon/transfer discovery), ApplyDamage (shields first). Script `Plug`, `GetSockets` |
| Storage | owner→locker Pod | — | Station, Colony | Market escrow, Buy/Sell/LOD, CanPerform. Script `GetStorageLocker` |
| Supertyped | item type | — | most built objects | `GetSupertype`, icon |
| Targets | `Vector<Object>` | — | Ship, Station | HUD/scripts (`ltheory.lts` Y/U keys). Script `AddTarget`… |
| Tasks | task stack, project | run top task, pop finished | Ship, Colony, ProductionLab, TechLab, Player | Project dispatch. Script `PushTask`, `ClearTasks`, `GetCurrentTask` |
| Zoned | SDF region, fog | — | Colony, Station, Wormhole, Zone | Economy (resource zones), `Object_GetZone` |

---

## 5. AI / task catalog

| Task | Factory args | What it does per update | Finishes when | Used by | Status / notes |
|---|---|---|---|---|---|
| Play | player | FindProject → allocate idle assets → run Manage → spawn ships (§2.3) | never | `Object/System.lts:214` | P. `kMaxProjects=1`, project switching disabled, allocation score constant |
| Manage | project | split wallet into Develop/Expand/Monopolize/Secure | never | Play (as project manager) | P. Only Monopolize acts (posts a "Damage the Enemy" bounty mission). Can create several missions in one loop |
| Mine | zone | pick a random object in the zone's **container** until it gets a Mineable with ≥10 ore. Goto within 500 m. Orbit-wander with an SDF sphere around the asteroid. Broadcast Fire + TargetPosition (jittered) to each transfer-unit socket | never | Economy, `App/observatory.lts` | C. Target pick ignores the zone boundary. `CanMine` capacity check unused. Mining is done by TransferUnit → Action_Mine |
| Sell | target node, item, qty, inner task | run inner task until carrying ≥ qty, then Dock at node, move cargo to own locker. Every frame, cancel and re-post an ask for the whole locker at a noisy EMA price | never | Play binding | C. "This breaks metrics" (frame-by-frame re-posting) |
| Buy | target node, item, qty, inner task | Dock at node, take the item from own locker, then run inner task until it runs out | never | Play binding | **B**: nothing ever places a bid for the item (§7), so it waits forever unless the locker already holds stock |
| Transport | source, dest, item | alternately Dock at source / Dock at dest | never | Economy | **S/B**: withdraw/deposit commented out, so no goods move. Duration = distance, so grossRate is tiny |
| Goto | target, distance | Dijkstra path over warp nodes. Boost toward next node. Ride rails via Start/StopUsing and Waypoint messages. Undock if needed | Nearby(target, distance) | Mine, Dock, Destroy, scripts | P. No inter-system travel |
| Dock | target | Goto within 90 m, then `target->Dock(self)` | container == target | Buy, Sell, Transport | C. Teleport docking |
| Destroy | target | Goto within 10 km. **Orbit** at radius 1000+r₁+r₂ (8 s period). For each Attack socket (turret→weapon), lead the target with `ComputeImpact` and fire if in range. Opinion −1 each frame | target dead | System.lts (patrol vs pirate duels), `dogfight.lts`, `war.lts`, `observatory.lts`, Pirate | C. Assumes the turret's weapon is in socket 0 |
| Pirate | zone | pick a random object in the container. If it has cargo, is alive, is not ours and is not human-owned (TEMPCHANGE), push Destroy | never | Economy (rejected for Lawless=0) | **B**: after a kill, or a first pick that is not a valid target, never re-picks. `GetOutput` typo means outputs are not declared |
| Patrol | zone | fly to random points in the zone | never | none | C, unused |
| Produce | assembly chip | wait for chip + requirements in root cargo, consume, after `duration` add the product | never | Economy (if chips exist) | P/B. `GetOutput` typo means the planner sees no output, so gross < 0 and it is never picked **(inferred)** |
| Mint | blueprint | Poisson(dt) chance to add the blueprint's assembly chip to root | never | Economy (if blueprints exist) | C. No outputs declared (gross ≤ 0) |
| Research | blueprint | Poisson(dt/10) chance to derive a new blueprint, play `techlab/complete.ogg`, log "Discovered […]" | never | Economy (if blueprints exist) | C. No outputs declared |
| Drill | target | Poisson(dt) chance to add 1 unit of a random resource | never | none | C, unused |
| Spawn | item, rate | (body `#if 0`) | never | ColonyType (`System.lts:50`) | S |
| LOD | owner, wrapped task | abstract simulation: every `duration`, moves output items into lockers and removes input items (scale forced to 1) | never | none | P/D. A good idea for off-screen simulation, never wired up |
| Wait | duration | accumulate time | elapsed ≥ duration | `App/rails.lts` | C |
| Custom | script object | calls script `Begin/End/Update(instance, self, data)`, `GetName`, `GetIcon` | never (no IsFinished hook) | none | P. `getInputs/getOutputs` fields never bound, `dt` not passed |

Behavior outside the task system, but AI-related:
- `Object/System.lts` spawns 2 patrol ships and 3 pirates per zone, all with health 1e9, set to `Task_Destroy` each other. This is a deliberate **eternal ambient battle**.
- Colony governors and station managers are `Player_AI` objects that own assets but **pilot nothing**, so their `Tasks`/`Projects` are never updated. Station managers only seed 32 random sell orders at world creation.

---

## 6. Script exposure (LTSL)

| Mechanism | What scripts can do |
|---|---|
| `FreeFunction`/`DefineFunction` with `FunctionAlias` (registered into the LTSL function table, method-call syntax) | About 90 component functions, all listed in each `.cpp`: transform get/set, motion (ApplyForce, GetVelocity, GetImpact), cargo/market/locker ops, credits, assets/targets/log/history/projects iterators, Plug, health, AddScript, PushTask/ClearTasks/GetCurrentTask, GetZone, AddResource, SetRenderable |
| Task factories (`DeclareFunctionArgBind` + `DefineFunction`) | Every `Task_*` is callable (`Task_Goto obj 512.0`, `Task_Destroy`, `Task_Mine`, `Task_Wait`, `Task_Play`, `Task_Spawn` are used in scripts) |
| **`Task_Custom data`** | Define a task as an LTSL type with `Begin/End/Update/GetName/GetIcon`. Unused, and limited (no dt, never finishes) |
| **`Object.AddScript obj`** (`ComponentScriptable`) | Attach per-frame LTSL behavior (`Update(self)->Bool` keeps it alive) plus a message handler `Receive`. This is the practical way to extend objects from script |
| Reflection | All component fields are reflected, so scripts can read reflected structs (e.g. `MarketData*` from `GetMarketData`) |
| Sound | `Sound_Play`/`Sound_PlayLooped` (2D/3D) plus control functions |
| Not exposed | Defining **new components** (compile-time mixins), the Project/Economy internals beyond `Project_Allocate/Deallocate/Create`, the scheduler, the physics engine |

---

## 7. Known issues, quirks, tech debt

### Economy and AI
1. **Buy never buys.** `ProjectT::UpdateMarketOrders` bids only for `task->GetInputs()`, and `TaskBuy::GetInputs` *removes* the very item it is meant to buy. `TaskBuy::OnUpdate` only pulls from the owner's locker. So nothing places a bid, and any project with a Buy step waits forever **(high confidence from code; not run)**.
2. **Who buys the ore?** Mine→Sell projects post asks. Bids only come from projects with unbound inputs, which Buy (item 1) suppresses, and from the human through the market UI. Ore asks may therefore rarely fill, and AI revenue/feedback may stay near zero **(inferred; verify at runtime by watching `MarketData.trades`)**.
3. **Transport moves nothing.** Pirate never re-targets. Produce/Pirate/Spawn spell the output override `GetOutput` instead of `GetOutputs`, so their outputs are invisible to the planner.
4. `kMaxProjects = 1` with switching `#if 0` means each AI player commits to the first profitable random task for life.
5. `GetRateFactor/GetScaleFactor/GetRequirements` (capability-based task rates) are designed but **never used**.
6. `ComponentEconomy::Run` re-scans the whole system and regenerates O(nodes² × items) Transport tasks **every frame**. `Task_Play::FindProject` allocates a new `Project` every frame.

### Time
7. **`Universe::age` is never incremented** (no writer in C++ or LTSL), so `Universe_Age()` is always 0. As a result, Info expiry never triggers, Log and Trade timestamps are 0, and `Detectable.detectionTime` is meaningless.

### Physics
8. Collision only for human-owned objects. AI ships overlap freely.
9. Collision damage permanently disabled.
10. No angular collision response. Scalar inertia.
11. Explicit Euler with a variable `dt`. Since `ltheory.lts` multiplies dt by 20 when H is held, large steps can tunnel or overshoot.
12. Raycasts assert when march distance ≥ 100 km.
13. Dock capacity is not enforced (`CanDock` inverted and uncalled, `docked` never counted).
14. No inter-system travel in Goto.

### Audio
15. **FMOD Ex 4.44.24** is a 2014 binary SDK (`extbin/linux64/libfmodex64-4.44.24.so`, `libfmodevent64-4.44.24.so`). It is discontinued, x86-only on Linux, and the Designer `.fev/.fsb` format is unsupported by modern FMOD Studio. Licensing for redistribution of old Ex binaries is unclear. Problems in the code:
    - `FMOD_INIT_HRTF_LOWPASS & FMOD_INIT_VOL0_BECOMES_VIRTUAL` equals 0.
    - Any FMOD error is fatal (`error()`).
    - There is no Null fallback at launch.
    - Sound sources are never released.
    - Destroyed sounds are paused rather than stopped.
16. Replacement options. The `SoundEngine`/`SoundT` interface is small (Play2D, Play3D with carrier+offset, Play(buffer), plus volume/pitch/cursor/loop), so swapping backends is about one file.

    | Option | Fit |
    |---|---|
    | **miniaudio** (public domain/MIT-0, single header) | Best drop-in: `ma_engine` + `ma_sound` with spatialization, decodes wav/ogg(via stb_vorbis)/mp3/flac from memory. Music adaptivity would be rebuilt by hand (crossfaded stems driven by a tension value) |
    | **OpenAL Soft** (LGPL) | Mature 3D positional audio with HRTF. Needs a decoder (stb_vorbis/dr_libs) and more boilerplate |
    | **FMOD Studio / Core** (proprietary, free tier for small indies) | Closest API (Core ≈ Ex low-level). Adaptive music needs re-authoring the `.fev` project in FMOD Studio. License terms apply |
    | SoLoud (zlib) | Simple and game-oriented, with 3D and filters. A reasonable middle ground |

17. MusicEngine is dead code. The `Audio::` synth is partly broken (ASR undefined/misdeclared, Note.duration uninitialized).

### Misc
18. Settings UI shows only category nodes (leaf `GetWidget` returns nullptr).
19. `Network` and `Strukt` are empty.
20. `TriTriOverlap.cpp` and the SMAA textures carry no license text.
21. AI pirates won't attack humans (TEMPCHANGE in `Pirate.cpp`).
22. "CRITICAL"/"TEMPCHANGE" markers are useful grep targets for the remaining hacks: `Collidable.cpp`, `Database.h`, `Drawable.h`, `Play.cpp`, `LOD.cpp`, `Goto.cpp`.

---

## 8. Dependencies

| Depends on | For |
|---|---|
| `LTE/` (core, other cataloger) | AutoClass/reflection (`FIELDS`), `Reference`/`Pointer`, `Vector`/`Map`/`HashMap`, `Data` variant, `Transform`/`V3`/`Bound`, `SDF`/`SDFs` (steering and zones), `SpatialPartition`, `CollisionMesh`/`Mesh`, `ParticleSystem`, `Job`/`Thread`/`Timer`, `GL_Finish`, `Location_*`, `Module`, `Script`/`ScriptFunction` |
| `Game/` world model (other cataloger) | `ObjectT`, object types, `Item` types (attributes live on them), `Player`, `Project`, `Order`, `Mission`, `Messages`, `Universe`, `Camera` (listener), `Graphics/Effects` (explosions, plumes) |
| `UI/` | Icon, Widget (settings widget, HUD affector) |
| External | FMOD Ex 4.44.24 (`include/FMOD`, `extbin/linux64`); enet (headers/binary present, not linked); SFML (window/system/network statically linked; audio disabled in CMake) |
| Resources | `resource/sound/**` (17 folders), `resource/music/*.fev,*.fsb`, `resource/script/Object/{System,Ship,WarpNode,Colony}.lts`, `<userdata>/settings.bin` |

Things that depend on this area: every `Game/Object/*` (mixins), `Game/Widget/HUD.cpp` (Affectable), `LTE/SDFMesh.cpp` (Scheduler), `LTE/CollisionMesh.cpp` and `LTE/Mesh.cpp` (ThirdParty), and LTSL apps (task factories, sounds).

---

## 9. Assessment for the two goals

### (a) Pushing toward a playable game

| System | End-to-end today? | Gap to "playable" |
|---|---|---|
| Flight (human) | Yes. HUD affector → thrusters → Motion. Boost/cruise. Collision for the player | Tune drag/thrust; decide on collision damage |
| AI flight/steering | Yes. SDF steering, Goto with warp-rail pathing, orbiting | Add AI collision avoidance (AI collision is off) |
| Combat | Yes (AI vs AI duels in `System.lts`; `dogfight.lts`). Turret tracking, lead calculation, shields absorb first, regen, explosions | Damage feedback, loot, death handling for the player ("TODO : What if player dies?") |
| Mining | Yes for AI (Mine task → TransferUnit → Action_Mine → cargo) | Player mining UX; asteroid depletion/respawn |
| Docking/stations | Teleport dock/undock works for AI. Lockers and market work | Player dock command (none found in `ltheory.lts`; Y/U only use rail targets), station services UI wiring |
| Market | Order book fully works | Make AI place bids (fix Buy), add NPC consumption/sinks so goods leave the economy |
| AI economy | Runs and logs projects. Ships mine and post asks | Fix items 1–5 in §7, raise `kMaxProjects`, re-enable switching, make governors/managers act |
| Missions | Bounty missions created by Manage (Monopolize) | Acceptance/payout loop lives in `Game/Mission.cpp` (outside scope) |
| Time/knowledge | — | Advance `Universe::age` (one line per frame) |
| Audio | 2D/3D SFX work under FMOD | Replace FMOD Ex (§7.16). Optionally revive adaptive music |
| Save/load | Reflection exists | No save game found **(uncertain)** |

Priority fixes for a game loop:
1. `Universe::age += quanta`.
2. Buy places bids, or projects bid for Buy items.
3. Transport withdraw/deposit (the commented code is there).
4. Pirate re-target.
5. `GetOutput`→`GetOutputs` typos.
6. Throttle `ComponentEconomy::Run` to every N seconds.
7. Init a Null sound engine if FMOD fails.

### (b) Cross-mapping ideas and code into a new game

| Design | Value | Portability |
|---|---|---|
| **Market order book** (`Component/Market.*`): sorted asks/bids, midpoint trades, escrow via per-owner lockers, interval stats and 27 doubling-period EMAs | High. A ready-made EVE-style regional market | High. About 250 lines. Depends only on Item/Order/owner credits. Port almost verbatim |
| **Task algebra plus market valuation** (`Game/Task.h`, `Buy.cpp`/`Sell.cpp`, `Project.cpp::UpdateGross`): tasks declare inputs/outputs/value. Wrappers bind unbound I/O to markets and fold prices into value. Project gross = outputs − inputs | High. A clean, composable way to make NPCs reason about profit | High as a design. Rewrite in your own ECS. Fix the Buy flaw |
| **Project layer** (allocation, idle detection, dispatch, metrics revenue/expense/losses, revenue-feedback wallet, metaprojects) | Medium-high. A good skeleton for faction/corp AI | Medium. Coupled to Player/Assets/Tasks |
| **Task stack** with push-subtask travel (Goto/Dock inside Mine/Sell) | Medium. Simple and robust | High |
| **SDF steering** (MotionControl): behaviors push distance fields, the ship follows the gradient at its predicted position | Medium-high. Elegant orbit/approach/avoid composition | High. Needs an SDF primitive set |
| **Task_LOD** (abstract off-screen production cycles) | High concept for a large single-player universe | Design only (never wired) |
| **Data items as proof** (DataDamaged/Destroyed awarded on damage, missions priced per item) | Medium. Neat bounty/evidence mechanic | High as a design |
| Mixin-chain components | Low-medium. Fast and simple, but compile-time-fixed and hard to extend from script | Low. Prefer a real ECS (EnTT/flecs) and keep the component *list* as a checklist |
| Camera-relative 3D audio and carrier-attached sounds | Medium | High. Trivially reimplemented on miniaudio |
| Adaptive scheduler (time-budgeted, self-calibrating batch size, GPU fenced) | Medium. Good for procedural generation | High. Self-contained (~180 lines) |
| Power grid (PowerGenerator proportional allocation → `GetPowerFraction`) | Medium. Capacitor/fitting analog | High |

---

## 10. EVE Online mapping

Status key: **Impl** = implemented, **Partial**, **Stub**, **Absent**.

### Flight model
| EVE feature | Here | Status | Where |
|---|---|---|---|
| Direct piloting | Human flies directly (WASD-style thrust plus mouse look) through `ShipAffector`. EVE has no direct piloting | n/a (different) | `Game/Widget/HUD.cpp:36-95` |
| Approach / move-to | `Task_Goto(target, distance)` steers to within distance and finishes. For the human it is autopilot (HUD yields while a task exists), but no HUD command issues it; only scripts do (`objectinfo.lts`, `handling.lts`) | Partial | `Game/Task/Goto.cpp` |
| Orbit | `Task_Destroy` orbits the target at 1000 m + radii (8 s period). Mine wanders around the asteroid surface. There is no standalone Orbit task, but SDF steering makes one trivial | Partial | `Destroy.cpp`, `Mine.cpp`, `Component/MotionControl.cpp` |
| Keep at range | No task. Goto stops once inside range and does not hold it | Absent (trivial with SDF) | — |
| Warp | **Warp rails**: chains of WarpNodes (15 km spacing) between POIs and orbital rings. Ships enter via `MessageStartUsing` and are carried along. Goto pathfinds through rails at zero cost (Dijkstra). This works like acceleration-gate lanes. No free warp-to-anywhere, no align time | Partial (different) | `Goto.cpp`, `Game/Object/WarpNode.cpp`, `Object/WarpNode.lts`, `Component/Navigable.h` |
| Stargates / inter-system jumps | Wormhole objects have Navigable, but Goto's inter-system branch is empty ("CRITICAL") | Stub | `Goto.cpp`, `Game/Object/Wormhole.cpp` |
| Speed model | Drag-limited top speed = thrust/(0.8·mass), with cruise/boost overcharge. Similar in spirit to EVE's exponential velocity curve | Impl | `Component/Motion.*`, `Thruster.cpp` |

### Combat
| EVE feature | Here | Status | Where |
|---|---|---|---|
| Target locking | `ComponentTargets` is a plain list (Add/Remove/Has). No lock time, max-targets or sensor strength. AI tasks aim directly without locking | Partial | `Component/Targets.*` |
| Ranges (optimal/falloff) | Weapon `Range` attribute is a hard cutoff, with no falloff curve | Partial | `Destroy.cpp`, `Attribute/Range.h` |
| Tracking / transversal | Turrets rotate at a fixed `kTrackSpeed` toward the aim point, and AI computes lead (`ComputeImpact`). Projectiles physically miss. There is no hit-chance formula | Partial (physical, not statistical) | `Game/Object/Turret.cpp`, `Motion.cpp` (`GetImpact`) |
| Weapon classes | Beam, Missile, Pulse, Rail (`WEAPONCLASS_X`). Cooldown and rate. Ammo exists but `kInfiniteAmmo = true` | Impl | `Game/Common.h`, `Weapon.cpp` |
| Shield / armor / hull layers | Two layers: socketed Shield objects absorb first (recharge scales with power, auto-restore after depletion), then hull `ComponentIntegrity`. No armor layer, no damage types/resists | Partial | `Game/Object.cpp:234`, `Shield.cpp`, `Component/Integrity.*` |
| Capacitor | PowerGenerator distributes power proportionally to module requests, and `GetPowerFraction` scales beams, thrusters, shields, scanners. There is no capacitor pool or depletion | Partial | `PowerGenerator.cpp`, `Component/Pluggable.h` |
| ECM / e-war | None | Absent | — |
| Drones | DroneBay launches a "prospecting drone" on `MessageLaunch`, but the drone's `OnUpdate` is empty. A Construction drone type also exists | Stub | `DroneBay.cpp`, `Game/Object/Drone/*.cpp` |
| Scanning / D-scan | Scanner module adds InfoLevel_Location for objects within `range × power` to the owner's `ComponentInfo`. Owners always get Scan level on their own assets. Expiry is broken (age frozen) | Partial | `Scanner.cpp`, `Component/Info.*`, `Detectable.h` |
| Aggression / standings | `ComponentOpinions` in [−1, 1]. Being attacked costs −1, and Destroy costs −1 every frame. Likes/Dislikes thresholds are defined but never used for decisions | Partial | `Component/Opinion.h`, `Event/Damage.cpp` |
| Bounties / kill rights | DataDamaged/Destroyed items are awarded per damage dealt, and missions pay per item (Manage→Monopolize "Damage the Enemy") | Partial | `Event/Damage.cpp`, `Task/Manage.cpp` |

### NPC / AI ecosystem
| EVE role | Here | Status |
|---|---|---|
| NPC miners | AI players' spawned ships run Mine→Sell projects | Impl (`Play.cpp`, `Mine.cpp`) |
| NPC haulers / traders | Transport task exists but moves no goods. Sell hauls own ore to market | Partial / Stub |
| Pirates / rats | Pirate task is filtered out for default traits and buggy. Ambient pirates in `System.lts` are scripted eternal Destroy duels | Partial (scripted) |
| Police / faction navy | "Patrol Unit" ships in `System.lts` only duel pirates. Patrol task unused. No CONCORD-style response | Partial (scripted) |
| Station owners / governors | Player_AI managers seed sell orders once, then stay idle (they pilot nothing, so never update) | Stub |
| Factions | AI players get grammar-generated faction names and a random weapon type (`Play.cpp`). No faction relations beyond Opinions | Partial |

**Economy comparison.** EVE's economy is player-driven, with regional order books, buy/sell orders, escrow, broker fees and NPC seeding. This engine already has the same core: **per-station order books with escrow and price history** (`Component/Market.cpp`). Its "players" are AI corporations choosing profitable production chains from market EMAs. What is missing compared with EVE: broker fees and taxes, regional or remote orders (orders are per station and require docking), contracts, NPC consumption sinks, manufacturing at scale (Produce is buggy, and blueprints are only reachable through Mint/Research), and a working buy side (§7.1).

### Docking and station services
| EVE feature | Here | Status | Where |
|---|---|---|---|
| Dock / undock | Teleport into hangar / out near a port. AI uses it through Task_Dock/Goto. No player dock command found in `ltheory.lts` | Partial | `Component/Dockable.cpp`, `Task/Dock.cpp` |
| Item hangar | Per-owner locker per station (Pod with capacity 100000), used as market escrow | Impl | `Component/Storage.cpp` |
| Market | Full order book. Market UI scripts exist (`Widget/Market/*.lts`, `App/market.lts`, outside scope) | Impl | `Component/Market.*` |
| Fitting | Sockets with typed slots, Plug/Unplug, capability aggregation, joint constraints | Impl (C++/script API; UI outside scope) | `Component/Sockets.*`, `Pluggable.*` |
| Agents / missions | Mission boards on stations. AI posts bounty missions | Partial | `Component/MissionBoard.h`, `Task/Manage.cpp` |
| Repair, insurance, clone | None | Absent | — |
| Manufacturing / research | ProductionLab/TechLab objects with Tasks. Produce/Mint/Research tasks exist but are only reachable when chips/blueprints exist | Partial | `Task/Produce.cpp`, `Mint.cpp`, `Research.cpp` |

### Mining and cargo
| EVE feature | Here | Status |
|---|---|---|
| Mining lasers | TransferUnit beam module → `Action_Mine`. Yield is best at the asteroid's "phase" sweet spot (a fun twist) | Impl (`Action/Mine.cpp`, `TransferUnit.cpp`) |
| Asteroid belts / ore types | Zones with weighted `Resources`, and asteroids with `Mineable` item+quantity. Orbital belt zones in `System.lts` | Impl |
| Cargo hold (m³) | Mass-based capacity (tonnes, not volume) from `Capability.Storage` | Impl (`Component/Cargo.*`) |
| Ore hold / specialized holds | `StorageType` enum: Cargo, CrewQuarters, Database. Only Cargo and Database are implemented | Partial |
| Depletion / respawn | Quantity decrements. No respawn found | Partial |

### Skills / progression
| EVE feature | Here | Status |
|---|---|---|
| Skills / training queue | None. `Game/Attribute/*` are **item-type stat mixins** (mass, range, rate, damage, …), not character attributes | Absent |
| Character attributes | `Traits` (7 personality floats) exist for AI players only, and only `Lawless` is read | Absent for player |
| Ship progression | Credits buy ships (AI auto-buys via `GetShipType`) and modules can be plugged. Ship value tiers are powers of 10 | Partial |
| Implants / standings-gated content | None | Absent |

**Bottom line for an EVE-like single-player game.** The engine gives you:
- EVE's economic core (order-book markets, escrow, hangars) and a profit-seeking NPC-corp planner to fill it;
- a flight model that can do EVE's approach/orbit/keep-at-range through SDF steering with very little code (one task each);
- lane-based warp travel;
- two-layer damage with power-scaled modules.

It is missing: lock/e-war/drone combat mechanics, a statistical tracking formula, an armor layer and resists, inter-system jumps, station services beyond market/hangar/fitting, and any skill system.
