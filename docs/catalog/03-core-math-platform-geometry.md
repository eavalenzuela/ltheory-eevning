# 03 — Engine core: containers, math, platform, I/O, procedural geometry

Scope: the low-level parts of `src/liblt/LTE/` (containers, smart pointers, math/geometry, platform/runtime, input, file/resource I/O, the text grammar) plus the procedural geometry stack (`Meshes`, `Geom`, `PlateMesh`, `Warp*`, `SDF*`, `SDFMesh`, `src/liblt/Volume/`). Also `src/liblt/Common.{h,cpp}` and `src/liblt/BuildMode.h`.

Other catalogs cover the rest: reflection/`AutoClass`/`Type`/`Function` and the LTSL VM, `Mesh`/`Texture`/`Shader`/`Renderer`, the world model, simulation (`Module/*`, physics), UI and scripts. I mention those only where this area depends on them.

Method: I read the code; I did not build or run anything. "Unused" means a grep of `src/` and `resource/script/` found no caller. CMake globs every `src/liblt/**/*.cpp` into `liblt.so`, so everything here is compiled unless it sits behind `#if 0`. The only executable built is `src/launch/launch.cpp`. The tools under `src/old/` (updater, makepatch, launcher, ltconsole) are **not built**.

---

## 1. Overview

| Area | What it is | Size (approx. lines) | Verdict |
|---|---|---|---|
| Containers / memory | Thin wrappers over `std::vector`/`std::map`/`tr1::unordered_*`, an intrusive refcounted `Reference<T>`, fixed-arena pools, macro-generated intrusive lists, FNV hashing | ~4.0k (mostly headers) | Works, but full of small latent bugs. Replace in a new project. |
| Math / geometry | Templated `V2T/V3T/V4T`, a column-major `MatrixT`, `BoundT` AABB, `Ray`, `Plane`, `Sphere`, `Transform` (double position, float basis), value/Worley noise, Mersenne Twister RNG | ~4.5k | Solid and readable. A few semantic traps (component-wise `operator<`). |
| Spatial / collision | Hash-grid and uniform-grid broadphase, an occupancy-bitset "spatial signature", a triangle-soup `CollisionMesh` | ~1.1k | Compact and usable. Worth extracting. |
| Platform / runtime | Program main loop, SFML window and input, `sf::Thread` threads and mutexes, scoped stack frames that feed a sampling profiler, assertions, logging, POSIX/Win32 `OS_*` helpers | ~3.0k | Works on Linux. Release build and crash handling are broken (see §5). |
| I/O | `Location` (file, resource, memory, web), a `ResourceMap` overlay (`resource/` plus `mod/*`), an obfuscated `.bin` archive (release only), rsync-like Diff/Patch (only used by tools that are not built) | ~1.0k | Location and ResourceMap are fine. The archive and patching are effectively dead. |
| Grammar | Weighted, tag-filtered recursive text grammar for procedural names, loaded from `resource/gamedata/grammar/default.txt` | ~240 | Small, self-contained, works. |
| **Procedural geometry** | (1) Primitive mesh builders. (2) **PlateMesh**: a union of rounded boxes plus vertex warps, used for ship/station hulls. (3) A **GPU per-vertex AO bake**. (4) An **SDF expression tree** that evaluates on the CPU *and* generates GLSL. (5) **SDFMesh**: the field is rasterized on the GPU into a 3D texture, resampled into 8 LODs, polygonized with **Lewiner's Marching Cubes 33** on a worker thread, then given a GPU AO pass. Used for asteroids and ice. | ~5.5k (2.3k of it is the MC33 lookup table) | The most interesting and most reusable part of this area. GPU-coupled, with some unfinished SDF nodes. |

---

## 2. Architecture

### 2.1 Build configuration and base macros

| Item | Location | Notes |
|---|---|---|
| `BUILD_DEBUG` / `BUILD_RELEASE` | `src/liblt/BuildMode.h` | Hard-coded `#if 0` means **`BUILD_DEBUG` is always on**. `BUILD_STRICT` is off (it gates GL error checks in `GL.h`). |
| OS / arch detection | `src/liblt/Common.h` | `LIBLT_WINDOWS/LINUX/MACOS`, `ARCH_32/64`, `LT_API` (dllexport on Win). |
| `LTE_ASSERT(x)` | `Common.h` | Always evaluated (not compiled out). Calls `LTE_ASSERT_FAILURE`. |
| `error(x)` | `Common.h` | Unconditional assertion failure. |
| `NOT_IMPLEMENTED` | `Common.h` | Assertion failure. Used in several SDF nodes (§2.12.5). |
| `LTE_ASSERT_FAILURE` | `src/liblt/Common.cpp` | Appends to `./cache/logAsserts.txt`, closes the window, creates `./cache/crashdumps/<time>.dmp` (written only on Windows), prints the stack frame trace. Debug on Linux: prints, then `raise(SIGABRT)`. Release: message box, then `exit(0)`. |
| `LTE/Common.h` | | Forward-declares nearly every engine type and `typedef Reference<FooT> Foo`. Defines the `Key`, `MouseButton` and `JoystickAxis` enums via the `XEnum.h` X-macro, the `FIELDS` reflection hook, `ToStream`, and `using namespace LTE`. |
| `LTE/LTE.h` | | Umbrella header. Contains a Windows `WinMain` shim. |

### 2.2 Memory and ownership model

| Type | Semantics | Refcount location | Thread-safe? | Used for |
|---|---|---|---|---|
| `RefCounted` | Base struct with `uint refCount`. The destructor asserts `refCount == 0`. | Intrusive | **No** (plain `uint`) | Every engine object: `MeshT`, `SDFT`, `WarpT`, `JobT`, `ThreadT`, `LocationT`, `RNGT`, `ButtonT`/`AxisT`… |
| `Reference<T>` | Intrusive strong pointer. Increments on copy, `delete t` when the count reaches 0. Implicit conversion to `T*` and to `bool`. `operator->` asserts non-null (`DEBUG_POINTERS` is always defined). | in `T` | No | The default handle. `typedef Reference<MeshT> Mesh` etc. |
| `Pointer<T>` | Raw non-owning pointer with a null-checked `->`. | — | n/a | Back-pointers, list links. |
| `AutoPtr<T>` | `std::auto_ptr`-style: **copy transfers ownership** (it mutates the source through a const cast). Deletes on destruction. | — | n/a | Sole ownership (`AutoPtr<Array<uchar>>` from `Location::Read`, `AutoPtr<SpatialPartition>`). |
| `Compare_*_*.h` | Cross-type `==`, `!=`, `<` between `Pointer`, `Reference` and `AutoPtr`. | | | |
| `Sparse<T>` | Lazily heap-allocated value with deep copy. | | | Unused. |
| `PoolRaw<BlockSize,32>` / `Pool<T>` | Free-list over 32-element arenas. Never returns memory to the OS. | | No | Through `POOLED_TYPE` only. |
| `POOLED_TYPE` macro | Overrides class `operator new/delete` to use one process-wide `PoolRaw` per type (`GetTypePool<T,sizeof(T)>`, a static that is never freed). | | **No** | ~105 small hot types: Buttons, Axes, Locations, Expression nodes, UI glyphs/widgets, `ShaderInstance`… |
| `StackAlloc<N>`, `StackArray<T,N>` | Small-buffer and fixed array. | | | `StackAlloc` is unused. `StackArray` is used in 2 Game files. |

Key consequences:
- **Ownership is refcount-everywhere. Cycles leak** (no weak references; `Pointer<T>` is the manual escape hatch).
- **Refcounting is not atomic.** Any `Reference` copied or destroyed on two threads at once is a data race. The threaded job system (§2.6) and script threads hand `Reference`s across threads.
- `Reference<T>::Release` does `delete t` through the static type `T`, so polymorphic bases need virtual destructors. They all have them (`virtual ~FooT()`).

### 2.3 Containers (summary)

| Container | Backing | Notes |
|---|---|---|
| `Vector<T>` | `std::vector` | Adds `push/append/remove` (swap-remove), `erase` (ordered), `contains` (linear), `random()`/`shuffle()` (global `rand()`), and reflection `FIELDS` + script methods (`Append/Get/Set/Size`). Bounds checks only under `DEBUG_BOUNDS_CHECK`; see §5. |
| `Array<T>` | `new T[]` | Fixed-size owning buffer. `resize` **discards contents**. `operator[]` is const yet returns `T&`. |
| `Map<K,V>` | `std::map` | `get()` returns a pointer or null. Reservoir-sampling `random(rng)`. Reflection. |
| `HashMap<K,V,H>` / `HashSet<K>` | `std::tr1::unordered_*` on Linux, `std::unordered_*` on Win/Mac | Adds `contains`/`get`. |
| `VectorMap<K,V>` | `Vector<{key,value}>` | Linear-scan associative array. Insertion-ordered. Used where sizes are small (grammar, renderer state, weapons). |
| `Distribution<T>` | `VectorMap<T,float>` | Weighted sampling, O(n) (TODO: alias method). |
| `PriorityQueue<T>` | `Vector<Tuple2<T,float>>` | O(n) `popMin`. Unused. |
| `List<T>` | Intrusive singly linked through `T::next` | O(n) `pushBack`/`back`. Iterator supports erase-while-iterating. |
| `Iterator.h` macros | `LIST_ITERATE`/`DLIST_*` | Macro-generated intrusive (doubly) linked list iteration and removal. Used by `Game/Object.cpp`, `Interior`, `Visibility`, `Settings`. |
| `InternalList.h` | `INTERNAL_LIST(type,name)` | Intrusive doubly linked list with iterator fix-up on removal. **Unused.** |
| `IntrusiveList.h` | — | **Truncated / uncompilable** (the file ends mid-expression). Never included. |
| `ListElement<T>` | Raw `T*` with reflection | Used by `List` reflection. |
| `VectorNP` / `ListNPT` | Type-erased vector driven by reflection `Type` (construct/assign/destruct) | Backing store of the LTSL `List` type (`ListNP`). |
| `RingBuffer<T>` | `Array<T>` + index | Used by `Object/Trail.cpp`. |
| `Stack<T,Max>` | `std::vector` | Used by `Renderer`/`DrawState` state stacks and the profiler. |
| `Tuple2/3/4` | `AutoClass` | `Tuple(...)` helpers. |
| `XVector.h` | X-macro "named-field numeric vector" generator | Used by `Game/Stats.h`, `Game/Capability.h`, `AI/Traits.h`. |
| `Vec<T,N,Storage>` | Generic N-vector | Base for XVector. Also `Vec<Texture2D,2>` in Materials. |
| `String` | `std::string` subclass | Implicit `operator char const*`. Helpers: split/lower/upper/capital/Levenshtein `String_Distance`/`String_Hash` (FNV). `Stringize` is a streaming builder. `ToString/FromString` go through stringstream (precision 4). |
| `StringPool` | `Map<String, strdup>` | Interning that never frees. Used by `DrawState`. |
| `UniString` | UTF-8 iterator over `ThirdParty/UTF8` | Used by `Font`. Iterates **including the trailing NUL** (`end = size()+1`). |
| `Hash.h` | FNV-1 32-bit (`HashT = uint`) | `Hash(ptr,len)`, `Hasher` combiner. |
| `IDMap`, `LazyHash`, `Interpolated`, `Sparse`, `Finite` | small utilities | `IsFinite` is used by V2/V3/V4 and the Volume NaN check. The others are unused. |
| `Smooth<T>` | Exponential smoothing toward a target: `Mix(v, target, 1-exp(-rate))`, plus a linear variant | Camera, HUD, Mine, Drill, TransferUnit. |
| `Graph<T>` | Node/edge lists + **Kruskal MST** with path-compressed union-find | Used by `Game/Object/Region.cpp` (system connectivity). |
| `Diff` / `Patch` | Block-hash binary diff (rsync-like: 17k-bucket FNV table of 16-byte blocks; emits Direct/Indirect blocks) and transactional apply with rollback | Only `src/old/updater` and `makepatch` use them, and those are **not built**. Dead in practice. |

### 2.4 Program, main loop and frame timing

`Program` (`Program.{h,cpp}`) is an abstract app with `OnInitialize`/`OnUpdate`. The only concrete subclass is `Launcher` in `src/launch/launch.cpp`.

```
main(argc==2) -> Launcher(appName)
  ctor: chdir("..") if ./resource missing; Window_Create(1920x1080, vsync off); Renderer_Initialize()
  Program(): srand(time(0)); OS_ConfigureSignalHandlers()
Program::Execute():
  FRAME("Initialize"): Window_Push; OnInitialize()  -> Launcher::Launch():
        CreatePhysicsEngine(), SoundEngine_Fmod(), ScriptFunction_Load("App/<app>:Main"),
        construct returned script object, call its Initialize
  while window->IsOpen() && !deleted:
     Mouse_Update(); Keyboard_Update(focus); Joystick::Get(i)->Update()   (input poll)
     window->Update()               (SFML event pump -> Keyboard_AddDown, Mouse_SetPressed, resize, focus, text)
     OnUpdate()                     (F1 screenshot, F2 profiler 1s, Ctrl+W quit, F5 hot-reload app,
                                     script Update, physics->Update, sound->Update)
     Module_UpdateGlobal()          (global modules: FrameTimer, Scheduler (jobs), Profiler, ...)
     window->Display()              (SwapBuffers)
```

- **Variable timestep, no fixed tick.** The core keeps no frame time. `Module/FrameTimer.cpp` (a global module) measures `dt` with an `sf::Clock` and keeps EMAs over 0.5 s, 1 s and 10 s. Scripts read them through `FrameTimer_Get*`.
- **There is no `sf::Event::Closed` handler**, so the window's close button does nothing. You quit with Ctrl+W (or the script ends).
- `Program_InStaticSection()` returns true once the `Program` destructor has run, so code can avoid touching dead singletons during static destruction.

### 2.5 Input model

| Layer | Files | Model |
|---|---|---|
| Raw keyboard | `Keyboard.{h,cpp}` | Global `gKeyboard{down[], downLast[], chars, pressed}`. KeyPressed events set `down`. Each frame `Keyboard_Update` copies to `downLast` and **re-polls `sf::Keyboard::isKeyPressed` for keys that were down** (catches missed releases; zeroes on focus loss). `Pressed` = down && !downLast. `Keyboard_Block()` suppresses Pressed/Released for one frame (UI capture). `Keyboard_ModifyString` is a text-field editor (Backspace, Ctrl+Backspace). A full SFML↔LTE key map exists in both directions. |
| Raw mouse | `Mouse.{h,cpp}` | Global state: position, last position, scroll delta, per-button down/lastDown and down/release `Timer`s, idle time. Double-click threshold is **0.1 s** (very tight). Capture mode clamps the cursor inside the window border. |
| Joystick | `Joystick.{h,cpp}` | `Joystick::Get(i)` lazily creates a `JoystickImpl` per connected SFML joystick (leaked, held in a static `Pointer` array). Buttons and axes are polled; axes are normalized to [-1, 1]. |
| Abstract `Button` | `Button.h`, `Buttons.{h,cpp}`, `Button/{Key,Mouse,Joystick,And,Or}.cpp` | Refcounted, pooled polymorphic predicates: `Down/Pressed/Released/DownTime`. Combinators `And`/`Or`/`Inverted`, `Button_Axis(axis, sign)` thresholding, modifier helpers (`Button_AndControl`…). `Button_Capture()` returns whichever input is currently active (for rebinding UIs). Left/right stick button indices differ between Windows and Linux. |
| Abstract `Axis` | `Axis.{h,cpp}` | Float sources with `zeroValue`, `deadZone`, `power`, `invert` post-processing in `AxisT::Get()`. Sources: `Axis_Button`, `Axis_Joy`, `Axis_MouseX/Y`, `Axis_MouseDragX/Y`, `Axis_MouseWheel`, plus `Sum`/`Product`/`Range` combinators and `Axis_Capture()`. |

Bindings are built in `Module/Settings*` and `Game/Widget/HUD.cpp` (not catalogued here).

### 2.6 Threading and jobs

| Piece | File | Notes |
|---|---|---|
| `JobT` | `Job.h` | A refcounted unit of work: `CanRun`, `GetPriority`, `GetMemoryUsage`, `IsFinished`, `OnBegin/OnRun(units)/OnEnd`. It accumulates `totalTime`/`totalUnits` so the scheduler can estimate cost per unit. |
| `Thread_Create(job)` | `Thread.cpp` | Wraps `sf::Thread`. The constructor calls `job->OnBegin()` (under a global lock), then launches `job->OnRun(UINT_MAX)` on the new thread. `finished` is a plain `bool`. The destructor calls `job->OnEnd()`, and calls `Terminate()` if the thread is still running. |
| `Lock` / `ScopedLock` | `Lock.cpp` | `sf::Mutex`. |
| Scheduler (dependency) | `Module/Scheduler.cpp` | Not in this catalog's scope, but it drives jobs. **Serial jobs** run on the main thread, time-sliced: priority-ordered, about 1/60 s budget per frame, `jobSize` from the measured cost per unit, with `GL_Finish()` around each slice. So these are cooperative GPU jobs. **Threaded jobs** get up to 8 `Thread`s, gated by a `kMaxMemoryUsage = 1 MB` budget. Because the budget is checked *before* a job is added, one large job always starts, and in practice large jobs run one at a time. `Scheduler_Flush()` runs everything to completion synchronously. |
| Script threads | `ScriptAPI/Thread.cpp` | `Thread_Create(object, "fnName")` runs an LTSL function on a real OS thread. |

**No engine global is guarded against threads.** That includes the StackFrame/Profiler stack, the log, `POOLED_TYPE` pools, refcounts, `Stringize`'s static stringstream, global `rand()`, and `GetTypePool`. The only threaded engine job I found is `SDFMesh`'s `Polygonize` (pure CPU marching cubes). It mostly touches its own data, so it is fine in practice. Script threads are not.

### 2.7 Logging, assertions, crash handling, profiling

| Piece | File | Behaviour |
|---|---|---|
| `Log_*` | `ProgramLog.cpp` | Levels Critical/Error/Warning/Event/Message. Each entry is prefixed with the current `StackFrame_Get()` path, kept in memory (cap 4096 entries; after that **all logging stops, console included**), echoed to stdout and to `./cache/logErrors.txt`. `Log_Critical` shows a message box, asserts (debug) and calls `exit(1)`. |
| Stack frames | `StackFrame.{h,cpp}` | `AUTO_FRAME`, `SFRAME(x)` and `FRAME(x){...}` push `{func,file,line,annotation}` onto a **global fixed 256-deep array**, and also call `Profiler_Push`. Active only under `BUILD_DEBUG` (always on). `StackFrame_Print` dumps the logical stack on crash. |
| Profiler | `Profiler.cpp` | A **sampling profiler driven by the frame stack**: a background `Thread` loops with ~1–2 µs sleeps while active, incrementing a counter for the current frame-path (`StackFrame*` interned by an FNV hash of the segment pointer array). `Profiler_Auto(sec)` (F2 in the launcher) prints a sorted table (%, cumulative %, ms per frame) to stdout. An optional RAD Telemetry path is `#ifdef`'d out. A "flushes" mode calls `Renderer_Flush()` on every Pop to attribute GPU time. |
| `Debug.h` | | `dbg | x | endl` stream helper. It is declared `static` **in the header**, so each translation unit gets its own copy. |
| Signal handlers | `OS.cpp` | Linux: SIGABRT/SIGINT → `IntHandler` (print stack, `exit(0)`). SIGSEGV → `SegHandler` → `error()` → `LTE_ASSERT_FAILURE` → `raise(SIGABRT)` → `IntHandler` → **`exit(0)`**. So crashes exit with **status 0 and no core dump**. These handlers are also not async-signal-safe. The Windows SEH handler is defined but never installed. |

### 2.8 File and resource location system

```
Location (RefCounted, polymorphic; Read() -> AutoPtr<Array<uchar>>, Write, Exists, Clone, ReadAscii (strips \r), GetHash)
 ├─ LocationFile(path)            std::ifstream/ofstream; Write creates parent dirs (OS_CreatePath)
 ├─ LocationResource(name)        release: archive "resources.bin" first; else ResourceMap lookup -> LocationFile
 ├─ LocationMemory(Array*/String) in-memory buffer
 └─ LocationWeb(host, item)       sf::Http GET (plain HTTP), read-only
Helpers: Location_Font/GameData/Script/Shader/Texture("x") = Resource("font/x") etc.
         Location_Cache(name) = File("./cache/cache/<name>")   (used by ScriptFunction.cpp for compiled-script cache)
```

| Piece | Behaviour |
|---|---|
| `kResourcePath` | `"resource/"` in debug, `"./"` in release. `kUseArchive` is true only in release. |
| `ResourceMap` | On first use, **recursively walks `resource/`** and maps every relative path to its file path, then walks each `./mod/<name>/` directory. **Mods override base files** (later `pathMap[alias]` wins). Lookups are exact and case-sensitive. A miss logs `Bad lookup` and returns `""`. New files added at runtime are not seen. |
| `Archive` | `resources.bin`: magic `12221991`, file count (<1024), index of `{name\0, streamoff location, size_t size}`, then data obfuscated by `c += i*i + 2*i`. Names are lower-cased with linear lookup. It writes back on destruction if modified. Only used in release builds, which do not compile (§5). |
| User data | `OS_GetUserDataPath()` always returns `"./cache/"` (relative to the CWD) and creates it. Asserts, logs, screenshots (`./cache/screenshot/N.png`), crash dumps and the script cache all live there. |
| `OS_*` | POSIX `stat`/`opendir`/`mkdir`/`chdir`/`posix_spawn` with Win32 equivalents. `OS_GetAppDir` returns `"/usr/bin"` on Linux (TODO; unused). `OS_GetDocumentsDir` returns `"./data"` on Linux (unused). `OS_WriteDump` is a no-op off Windows. `OS_MessageBox` prints to stdout and stderr off Windows. |

### 2.9 Math library

| Module | Contents | Notes |
|---|---|---|
| `StdMath.h` | Float/double overloads of `Abs, Ceil, Clamp, Exp, Floor, Fract, Log, Max, Min, Mix, Mod, Pow, Round, Saturate, Sign, SignPow, Sqrt`, trig, `Squared/Fourth/Eighth`, `kTau/kPi…` | `Mod` = `fmod` (keeps the sign of the dividend). |
| `V2T/V3T/V4T<T>` (`V2.h`, `V3.h`, `V4.h`) | `AutoClass` structs with `x,y(,z,w)`. Arithmetic with mixed `T2`, swizzle getters (`GetXY`, `GetXZ`…), friend functions `Dot, Cross, Length, Normalize` (safe on zero), `Mix, Clamp, Pow, PNorm, Angle, OrthoProjection`. Typedefs `V3`(float), `V3D`, `V3I`, `V3U`. | **`<`, `<=`, `>`, `>=` are "all components" tests**, not orderings (see §5). `operator[]` uses `(&x)[i]`. |
| `MatrixT<T>` (`Matrix.h`) | 4x4 **column-major storage** (`e[0..3]` = first column); the 16-arg constructor takes **row-major** arguments. Multiply, cofactor `Inverse`, `Transpose`, `TransformPoint/Vector/V3Norm/Ray`, factories `Frustum, Perspective, Orthographic, Look, LookAt, LookUpRight, RotationX/Y/Z/YPR/AxisAngle, Scale, Translation`. | OpenGL-style projection with a Z flip (`Scale(1,1,-1)`). `Inverse` does not check for a singular matrix. |
| `BoundT<P,D>` (`Bound.h`) | AABB with `lower/upper`. AddPoint, Union, Intersect, Contains, Overlaps, GetTransformed (by matrix), surface area, volume, faces as planes, ray slab test, conservative tri overlap. | Slab tests do not reject boxes **behind** the ray (`far < 0`). |
| `Ray`, `Plane`, `Sphere`, `Segment`, `Capsule` | Ray–triangle (Möller–Trumbore, degenerate-determinant check commented out), plane from points/normal, sphere containment/intersection, point–segment distance | `Capsule.h` (unused) and `Cylinder.h` (**does not compile**: it references `ray`/`ray.dir`; never included). |
| `Quaternion.h` | Axis+angle holder with `ToV4()` | **Stub.** There are no quaternion operations; rotations go through matrices and orthonormal bases. |
| `Transform` | `pos` (**V3D, double**) + `right/up/look` (float basis) + `scale`. `GetMatrix()` → `MatrixD`, Transform/Inverse Point/Vector/Dir, `Orthogonalize` (Gram–Schmidt), `Mix` (lerp position, lerp basis, re-orthogonalize, so no slerp), `operator*` via matrices. 13 script-visible functions. | The double position is what lets large star systems keep precision. `Transform_GetPoint` returns **V3F** and so loses that precision. |
| `Math.h/.cpp` | `ComputeImpact` (intercept time for lead targeting), `OrthoBasis/OrthoVector`, `RotateBasis/RotateTangentSpace`, `Spherical/Cylindrical/Polar`, `Gain`, `InterpQuintic`, `Sigmoid`, `Sigfigs`, sampling helpers using global `rand()` (`Rand`, `RandI`, `RandAngle`, `SampleSphere`, `RandDirection`, `RandExp`, `RandErlang`, `RandGauss`), `V3ToColor32`, `DecimalToString` (base-62) | `RandGauss` is actually a two-sided **exponential (Laplace)**, not a Gaussian. |

### 2.10 Spatial partitioning and collision

| Structure | File | Algorithm | Used by |
|---|---|---|---|
| `SpatialPartition` (interface) | `SpatialPartition.{h,cpp}` | `Add(obj, box[, perCellAcceptCallback])`, `Remove`, `Query(point/box/ray, callback)`, plus `Vector<void*>` overloads. Stores opaque `void*`. | |
| `SpatialPartition_Hash(cellSize, buckets)` | `SpatialPartition_HashGrid.cpp` | **Spatial hash grid**: integer cell = floor(p/cellSize), hash = `p1*x + p2*y + p3*z mod buckets`. Each bucket is a `Vector<void*>`. A per-bucket **version stamp** de-duplicates buckets within one Add/Query. Ray query = **3D DDA (Amanatides–Woo)** cell walk up to `tMax`. | `Component/Queryable.cpp`: multi-level hash grids for object proximity queries. |
| `SpatialPartition_Uniform(box, nx,ny,nz)` | `SpatialPartition_UniformGrid.cpp` | Dense grid with lazily allocated cells, clamped insertion, ray DDA. | `CollisionMesh` (triangle broadphase). |
| `SpatialSignature_Grid` | `SpatialSignature_UniformGrid.cpp` | Occupancy **bitset** (`std::vector<bool>`) at 4x the partition resolution. Gives a fast "is anything here?" reject. | `CollisionMesh`. |
| `CollisionMesh_Create(mesh)` | `CollisionMesh.cpp` | Triangle soup (after `RemoveDegeneracies`) + per-triangle AABBs + uniform grid (resolution ∝ cube root of the triangle count, shaped by the aspect ratio) + signature. **Mesh–mesh**: transform each triangle of the *smaller* mesh into the other's local space → AABB reject → signature reject → grid query → **Möller tri–tri overlap** (`ThirdParty/TriTriOverlap.cpp`). Returns the first hit and a crude contact normal (difference of face normals). **Ray–mesh**: inverse-transform the ray → grid DDA → AABB → Möller–Trumbore, keeping the closest hit. | `Module/PhysicsEngine.cpp`, `Component/Collidable.cpp`. |
| `SphereTree` | `SphereTree.{h,cpp}` | — | **Dead** (`#if 0`). Only `src/old/ltconsole` referenced it. |

Caveats: queries can return the same object several times and can return hash-collision false positives, so callbacks must re-test. Ray–mesh `t` is in **local** space, so it is wrong for scaled transforms. Collision is boolean: there is no penetration depth or manifold.

### 2.11 RNG and noise

| Piece | Notes |
|---|---|
| `RNGT` (`RNG.h`) | Abstract `GetInt()` [0, 2^32). Derived helpers: `GetFloat` [0,1) (it can actually round to 1.0f), `GetInt(lo,hi)` (modulo-biased), `GetInt2` (float-scaled), `GetExp`, `GetErlang`, `GetGaussian` (real Box–Muller), `GetAngle`, `GetSign`, `GetSphere/Circle/Cube/CubeSurface/Direction` (rejection sampling), `GetV2/V3/V4`. |
| `RNG_MTG(seed)` / `RNG_MTG(arr,n)` | **MT19937** (standard init and init_by_array). This is the deterministic generator scripts use (`RNG_MTG` appears 28 times in scripts). |
| `RNG_LCG(seed)` | MSVC-constant LCG (214013/2531011). |
| `RNG_Default()` | Wraps global `rand()`. `rand()*RAND_MAX + rand()` **overflows a signed int** on glibc. |
| Global `Rand*()` (Math.h) | Global `rand()`, seeded with `time(0)` in `Program()`, so results are **not reproducible**. Asteroid and ice seeds come from `Rand(1,1000)`, so they differ every run. |
| CPU noise (`Math.h/.cpp`) | Hash `noise(x) = fract(sin(x)*4173.137)` (the classic shader hash), `ValueNoise1D–4D` (smoothstep), `WorleyNoise2D/3D` (3^d neighbour cells), `DistanceNoise3D` (F1/F2/F3 weighted over an explicit point set, O(N)), `VoronoiNoise3D`, generic `Fractal(fn, p, octaves, lacunarity)`. |
| GPU noise | `resource/shader/common/noise.jsl`: `snoise`/`fsnoise` (simplex fBm), `cnoise`/`fcnoise` (cellular fBm). These are what SDF codegen uses. |

### 2.12 Procedural geometry stack (the important part)

```
                    ┌──────────────── CPU ────────────────┐   ┌────────────── GPU ──────────────┐
Ship/station hull:  PlateMesh (N rounded boxes + child PMs) ─► Mesh ─► Warp deltas ─► normals ─► Mesh_ComputeOcclusion (disk AO bake) ─► vertex.u = AO
Asteroid/ice/etc:   SDF tree ──GetCode()──► GLSL "FIELDFN" ─► gen/field.jsl renders Z-slices ─► Texture3D (R32F field)
                                                                  │  per LOD: gen/fieldcopy.jsl resamples slices ─► readback ─► Array3DFloat
                     Volume::Mesh_Volume (Lewiner MC33, worker thread) ◄──┘
                     ─► Mesh (opt. keep largest component) ─► gen/fieldocclusion.jsl (AO by sampling the field) ─► vertex.u = AO
                     SDFMesh (GeometryT): 8 LODs + 32^3 collision level, picks LOD by distance/radius at Draw()
Primitives:         Meshes.h (Mesh_Box/BoxRounded/BoxSphere/Plane/Quad/Sphere/Polar*/Torus...), Geom.cpp (mirror, repeat, ring, smooth hull)
```

Convention: **AO is stored in `Vertex.u`**. Both AO bakes overwrite the U texture coordinate. Shaders downstream read it as occlusion.

#### 2.12.1 Primitive mesh builders — `Meshes.{h,cpp}`, `Geom.{h,cpp}`

| Function | Algorithm |
|---|---|
| `Mesh_Box(res, closed)` | Six `res x res` planar grids on [-1, 1]^3 (`BuildPlanarFace`). `closed` welds them. |
| `Mesh_BoxRounded(res, radius)` | Box grid, then each vertex is projected onto a rounded box: clamp to the inner box `[-(1-r), 1-r]`, push out to radius `r`. This is the plate primitive. |
| `Mesh_BoxSphere(res)` | Box grid normalized onto the sphere (a cube-sphere, which avoids pole pinching). Spherical UVs. |
| `Mesh_Polar(f(h,angle), slices, stacks)` / `Mesh_PolarClosed` / `Mesh_PolarPoints(ring, radii)` / `Mesh_PolarTorus` | Surfaces of revolution from radius functions (header templates). |
| `Mesh_Plane`, `Mesh_Quad`, `Mesh_SkirtedPlane`, `Mesh_Billboard`, `Mesh_Cone`, `Mesh_Cylinder`, `Mesh_CylinderHUD`, `Mesh_Sphere`, `Mesh_Tetrahedron` | Basic shapes. `Mesh_Quad` is the most used (22 script uses). |
| `Geom_*` | `Mirror` (scale by a sign vector + reverse winding), `MakeSymmetric`, `MakeSymmetricAngular` (N rotated copies), `Repeat`, `Retarget` (fit to an AABB), `DisplacePlane`/`Expand` (push vertices away from planes), `PolyBox`, `RingMesh` (random ring profile), **`SmoothHull`** (cube-sphere shrink-wrapped to the nearest source vertex + radius; O(hull x source)). Only `Geom_SmoothHull` has a caller (`Shield.cpp`); the rest are unused and not script-bound. |

#### 2.12.2 PlateMesh — `PlateMesh.{h,cpp}`

How procedural ship and station hulls are built:

| API | Behaviour |
|---|---|
| `PlateMesh_Create(quality)` | Empty container. `quality` = grid resolution of each rounded box (scripts use 12). |
| `Add(center, scale, rotationYPR, bevel)` | Records a plate. |
| `Add(childPlateMesh, offset, scale)` | Nested composition (translation × scale matrix). |
| `Add(warp)` | Records a deformation. |
| `GetMesh()` | For each plate, append `Mesh_BoxRounded(quality, bevel)` transformed by `T(center)·R(ypr)·S(scale)`. Append each child's `GetMesh()` transformed. Then for every vertex, `p += Σ warp->GetDelta(p)`. Finally `ComputeNormals()`. |
| `ReflectX/Y/Z` | Negate one center coordinate and the matching rotation component for **plates only** (children and warps are not reflected). |

Important: plates are **not merged or CSG'd**. The hull is an overlapping soup of closed rounded boxes, so interior faces remain (hidden by the depth buffer and darkened by AO). Generation is fast and simple, but triangle counts are high and the hull is unsuitable for anything that needs a manifold.

The ship generator (`resource/script/Item/ShipType/Generate.lts`, owned by the scripts catalog) grows boxes out from two seed boxes along random axes, mirrors them in X, adds two script-defined warps (`VerticalCompress`, `HExpand`), then calls `mesh.Center` and `Mesh_ComputeOcclusion`. Noted in passing: that loop picks `boxes.Get i` and never uses its random `index`. The C++ station path (`Game/Item/StationType.cpp`) also uses PlateMesh plus an SDFMesh interior.

#### 2.12.3 Warps — `Warp.h`, `Warps.h`, `Warp/*.cpp`

| Warp | `GetDelta(p)` |
|---|---|
| `Warp_AttractorPoint(center, s)` | `mix(p, center, exp(-|center-p|/s)) - p`. Pulls nearby vertices toward a point with exponential falloff. |
| `Warp_AttractorPlane(center, n, s)` | Same idea toward the projection of `p` onto a plane. |
| `Warp_Custom(scriptObject)` | Calls the script type's `GetDelta(Vec3)` through the LTSL VM **for every vertex**. Flexible but slow, and there is no null check if `GetDelta` is missing. |

#### 2.12.4 GPU per-vertex AO bake — `Mesh_ComputeOcclusion` (in `PlateMesh.cpp`)

Algorithm: Bunnell's **disk-based dynamic ambient occlusion** (GPU Gems 2, ch. 14), single pass and brute force.
1. **Emitters:** one surfel per triangle: centroid, area/π (in `.w`), unit normal. These are packed into `sDim x sDim` RGBA32F textures.
2. **Receivers:** every vertex position and normal, packed into `vDim x vDim` textures.
3. Render a full-screen pass into an R32F `vDim x vDim` target with `resource/shader/fragment/compute/occlusion.jsl`. For each receiver, loop over **all** surfels: `value = (1 - 1/sqrt(area/d² + 1)) · |dot(r, n_s)| · saturate(4·dot(r, n_v))`. Then `visibility = exp(-total^0.75)`.
4. Read back and write into `vertex.u`; bump `mesh->version`.

Cost is O(V·T). This session's fix splits the draw into **row bands** (`Renderer_DrawFSQPart`) sized to about 2e9 pairs each, with `GL_Finish()` between bands, to avoid amdgpu GPU-timeout resets. It still blocks the main thread for the whole bake. Callers: ship, thruster, turret, weapon and transfer-unit scripts, `StationType.cpp`, and the ModelEditor widget.

#### 2.12.5 SDF expression tree — `SDF.{h,cpp}`, `SDFs.h`, `SDF/*.cpp`

`SDFT` (refcounted) has three faces:
- `Evaluate(p)`: CPU distance.
- `GetBound()`: an AABB.
- `GetCode(p)`: a **GLSL expression string**.

The GLSL is built by streaming C++ values. V3 streams as `V3T(x, y, z)`, and `resource/shader/common/global.jsl` contains `#define V3T vec3` so that text is valid GLSL. Floats use default stringstream precision (6 significant digits).

| Node | CPU `Evaluate` | GLSL | Notes |
|---|---|---|---|
| `SDF_Sphere`, `SDF_Torus`, `SDF_Ring`, `SDF_Shell`, `SDF_Capsule` | ✔ exact | ✔ | |
| `SDF_Box` | ✔ but **unsigned exterior distance** (0 inside) | ✔ `max` of components (signed Chebyshev) | **CPU and GPU disagree.** |
| `SDF_RoundBox` | ✔ | ✔ | |
| `SDF_Polyhedron(planes, shape)` | ✔ | ✔ | `shape > 0`: p-norm "superellipsoid" over planes. Otherwise convex `max` of plane distances. |
| `SDF_Cylinder` | **NOT_IMPLEMENTED** (asserts) | ✔ | |
| `SDF_Wedge` | **NOT_IMPLEMENTED** | ✔ | |
| `SDF_FractalPerlin`, `SDF_FractalWorley` | **NOT_IMPLEMENTED** | ✔ `fsnoise`/`fcnoise` | Asteroids and ice depend on Worley. |
| `SDF_Union(a, b, k)` / `->Union` | `min`, or sigmoid blend `mix(a, b, sigmoid((a-b)k))` when k > 0 | ✔ `smoothUnion` | The blend is not a true smooth-min, so the result is not a distance field. |
| `SDF_Subtract` / `->Subtract` | `max(a, -b)` or sigmoid blend | ✔ | |
| `->Intersect` | `max` (ignores `sharpness`) | ✔ | |
| `SDF_Add`, `SDF_Multiply` | sum / scale of the field values | ✔ | |
| `SDF_Translate`, `SDF_Scale` | `f(p - t)`, `f(p / s)` | ✔ | Scale does not rescale distance, so the field is no longer Lipschitz-1. |
| `SDF_Repeat(src, times, spacing)` | `max(src(mod(p - phase, freq) + phase), boundingBox)` | ✔ | Uses `fmod` (sign issue for negative `p - phase`). |
| `SDF_Radial(src, rMin, rMax)` | `|p| - mix(rMin, rMax, src(p))` | ✔ | A star-shaped displaced sphere. This is the asteroid primitive. |
| `->Mirror(origin, n)` | half-space fold | ✔ | |
| `->MirrorRadial(origin, n, angle)` | angular fold (kaleidoscope) | ✔ | `GetBound` overwrites `radius` instead of taking the max, so only the last corner counts. |
| `->Expand(amount)` | `f(p - clamp(p, -a, a))` (stretch) | ✔ | |
| `->ExpandRadial`, `->PinchAxis` | **NOT_IMPLEMENTED** | ✔ | |
| `->PinchY` | ✔ | ✔ | |
| `->Rotate(ypr)` | **declared, never defined** | — | Link error if anything calls it. |
| `SDFT::Gradient` | central differences divided by `ds` instead of `2ds` | — | Magnitude is 2x too large. Harmless when the result is normalized. |

Since the mesher evaluates **only the GLSL**, the NOT_IMPLEMENTED CPU paths matter only for CPU callers. Those are `SDFMesh::Intersects`, which **would abort on asteroids and ice**, and the `Zoned.region` / motion-control uses, which only use `SDF_Sphere`. Nothing calls `Intersects` on an SDF-backed renderable today: physics uses `CollisionMesh`, and the only C++ caller of `Renderable::Intersects` is `ShipType.cpp`, which works on plate hulls. So this is a trap for new code.

#### 2.12.6 SDFMesh pipeline — `SDFMesh.{h,cpp}`

`SDFMesh_Create(sdf, resolutionMult, occlusionRadiusMult, tileMult(unused), eliminateFloaters)` returns a `GeometryT` that builds itself lazily on its first `Draw()` (`kPreload = false`):

| Step | Job (scheduler) | Thread | What happens |
|---|---|---|---|
| 0 | `Load()` | main | Bound = `sdf->GetBound()` expanded by 5%. Full resolution = 128 × aspect-normalized extents × `resolutionMult`, capped so the geometric mean is ≤ 256. Builds 8 LOD resolutions, each 0.666x the previous (min 4), plus a 32³ collision level. Compiles a shader `gen/field.jsl` with `#define FIELDFN <sdf->GetCode()>`. |
| 1 | `GenerateFieldTexture` | serial (GPU, time-sliced) | For each Z slice: draw a quad evaluating `field(origin + u·du + v·dv)` into a 2D R32F target, `GetData` readback, `Texture3D::SetData` slice. The result is the field as a 3D texture (border = 1, which means "outside"). |
| 2 | `GenerateLodLevel` ×9 | serial (GPU) | For each LOD, resample the 3D texture slice by slice with `gen/fieldcopy.jsl` (trilinear) and read back into an `Array3DFloat`. When complete, it enqueues `Polygonize`. |
| 3 | `Polygonize` | **threaded** | `Mesh_Volume(grid, bound)` = **Marching Cubes 33** at iso 0, then optionally `ComputePrincipleComponent()` (keep the largest connected piece, removing floaters). |
| 4 | `GenerateOcclusion` ×8 | serial (GPU) | Builds an exponentially distributed hemisphere sample kernel (√2048 x √2048 = 2025 samples, ~0.3 x mult radius). Per vertex: march out along the normal until the field is > 0, then average `exp(-1000·max(field, 0))` over the samples, giving `ao = (1 - sqrt(occ))^4`. Writes `vertex.u`. |
| Draw | — | main | LOD = `log(1 + max(0, dist/radius - 1)) / log(1/0.666)`. If that level is not ready, try coarser ones. **If none is ready, spin on `Scheduler_Flush()`** (a hitch on first sight). |
| Intersects | — | main | Ray-march the CPU `Evaluate` (64 steps + 8 bisection steps). |
| GetCollisionMesh | — | — | Clone of the 32³ level. |

Users: `Game/Renderable/Asteroid.cpp` (`Radial(FractalWorley(seed, 6, 2.6), 0, 2)`), `Ice.cpp`, `Pod.cpp` (RoundBox), `StationType.cpp` (shell minus cylinder), `Zone.cpp`, `Wormhole.cpp`, `WarpRail.cpp`.

#### 2.12.7 Volume — `src/liblt/Volume/`

| File | Content |
|---|---|
| `Array3D.h/.cpp` | `Array3D<T>` (flat `Array<T>`, x-fastest) and `Mesh_Volume(grid, bound, iso)`: NaN check (aborts on non-finite input), feeds the grid to MC, maps vertex grid coordinates to `bound`, keeps MC's gradient normals, emits triangles with swapped winding (v1, v3, v2). |
| `MarchingCubes.h/.cpp`, `LookUpTable.h` | **Thomas Lewiner's "Marching Cubes 33"** (2002, PUC-Rio): a topologically correct MC with face and interior ambiguity tests (`test_face`, `test_interior`), all 33 sub-cases, shared edge vertices via per-axis index grids, optional extra center vertex (case 7.3 and others), and gradient normals by central differences. `_originalMC = false`, so the full MC33 tables are used. Lightly adapted (`LTE_ASSERT` on `new`, `Abs`). **License: not stated in the files.** Check Lewiner's original distribution terms before reusing it. |
| `Contour.cpp` | **Dead** (`#if 0`). An experimental "cubical" contouring: emits the faces of sign-change cells, vertices pushed along the gradient by `0.5·d`. A surface-nets-like prototype. |
| `Common.h` | `Array3DFloat`, `Array3DVector` typedefs. |

So the engine has **no dual contouring and no surface nets in use**. It is plain MC33 on a GPU-sampled grid.

### 2.13 Procedural text grammar — `Grammar.{h,cpp}`

- **Format** (`resource/gamedata/grammar/default.txt`, 802 lines, ~49 rules): a rule-name line, then indented productions `weight|tok|tok|#tag…`, ending at a non-token line. A token starting with `$` recursively expands that rule. Other tokens are literal. `#tag` restricts a production to calls whose tag set contains it.
- **Generate(rng, "$rule", "tag1,tag2")**: weighted choice among matching productions using the supplied `RNG` (deterministic with `RNG_MTG`).
- **Callers:** system/planet names (`$system`), ore types, weapons, factions (`Play.cpp`), stations (`$station`, `$station_midfix`) from C++ and LTSL.
- The other 48 files in `resource/gamedata/grammar/` (e.g. `activity.txt`) are an older one-rule-per-file split without the header line. **Nothing loads them**; only `default.txt` is used.
- A lookup of an unknown rule inserts an empty entry (via `VectorMap::operator[]`) and logs an error.

---

## 3. File inventory

Status key: **C** complete/working · **P** partial · **S** stub · **D** dead (unused or uncompilable) · **R** release-only.

### 3.1 Root

| File | Purpose | Status |
|---|---|---|
| `src/liblt/BuildMode.h` | Debug/release/strict switches (hard-coded debug) | C |
| `src/liblt/Common.h` | Typedefs, OS/arch detection, `LTE_ASSERT`, `error`, `NOT_IMPLEMENTED` | C |
| `src/liblt/Common.cpp` | Assertion failure handler, debug break | C (exits 0 on Linux) |

### 3.2 Containers and memory (`src/liblt/LTE/`)

| Module(s) | Purpose | Status |
|---|---|---|
| `Reference.h` | Intrusive refcount pointer + `RefCounted` | C (not thread-safe) |
| `Pointer.h`, `AutoPtr.h`, `Compare_AutoPtr_Pointer.h`, `Compare_AutoPtr_Reference.h`, `Compare_Pointer_Reference.h` | Raw and owning pointers plus comparisons | C (minor `operator<` bug in Pointer) |
| `Vector.h`, `Array.h`, `Map.h`, `HashMap.h`, `HashSet.h`, `VectorMap.h`, `List.h`, `ListElement.h`, `Stack.h`, `RingBuffer.h`, `Tuple.h`, `String.h/.cpp`, `StringPool.h`, `UniString.h/.cpp`, `Hash.h`, `Iterator.h`, `VectorNP.h`, `XVector.h`, `Vec.h`, `Distribution.h`, `Smooth.h`, `Graph.h`, `Finite.h` | Core containers and utilities (§2.3) | C (latent bugs, §5) |
| `Pool.h` | Arena free-list pool + `POOLED_TYPE` | C |
| `StackArray.h` | Fixed array with bounds check | C (2 users) |
| `BaseVector.h` | Hand-rolled vector | D (copy ctor would not compile; `pop_back` destroys the wrong slot) |
| `IntrusiveList.h` | Intrusive list | D (truncated file) |
| `InternalList.h` | Macro intrusive doubly linked list | D (unused) |
| `PriorityQueue.h`, `IDMap.h`, `LazyHash.h`, `Sparse.h`, `StackAlloc.h`, `Interpolated.h` | Misc | D (unused) |
| `Diff.h/.cpp`, `Patch.h/.cpp` | Binary diff/patch with rollback | D in the current build (only `src/old/` tools use them) |

### 3.3 Math and geometry

| Module | Purpose | Status |
|---|---|---|
| `StdMath.h` | Scalar math wrappers | C |
| `V2.h/.cpp`, `V3.h/.cpp`, `V4.h` | Templated vectors + `RandV2/RandV3` | C |
| `Matrix.h` | 4x4 matrix | C |
| `Bound.h` | AABB | C |
| `Ray.h`, `Plane.h`, `Sphere.h`, `Segment.h` | Primitives | C |
| `Capsule.h` | Capsule distance | D (unused) |
| `Cylinder.h` | Cylinder ray test | D (does not compile; never included) |
| `Quaternion.h` | Axis-angle holder | S |
| `Transform.h/.cpp` | Double-precision transform | C |
| `Math.h/.cpp` | Misc math, sampling, CPU noise | C |
| `RNG.h/.cpp` | MT19937 / LCG / rand() RNGs | C |
| `Geometry.h` | `GeometryT` interface (Draw, GetBound, GetCollisionMesh, Intersects, Sample) | C (implemented by `SDFMesh`, `Model`, etc.) |
| `Geom.h/.cpp` | Mesh helpers | P (only `SmoothHull` used) |
| `Patch.*` | (see containers) | |
| `SpatialPartition.h/.cpp`, `SpatialPartition_HashGrid.cpp`, `SpatialPartition_UniformGrid.cpp` | Broadphase grids | C |
| `SpatialSignature.h`, `SpatialSignature_UniformGrid.cpp` | Occupancy bitset | C |
| `CollisionMesh.h/.cpp` | Triangle-mesh collision | C (boolean only) |
| `SphereTree.h/.cpp` | Sphere BVH | D (`#if 0`) |

### 3.4 Platform and runtime

| Module | Purpose | Status |
|---|---|---|
| `LTE.h` | Umbrella header + WinMain shim | C |
| `Common.h` (LTE) | Forward declarations, enums, reflection hooks | C |
| `OS.h/.cpp` | Filesystem, spawn, message box, signal handlers | P (Linux: AppDir/Docs/WriteDump are TODO/no-op) |
| `Window.h/.cpp` | SFML window, event pump, window stack | P (no Closed event handling) |
| `Program.h/.cpp` | Main loop | C |
| `ProgramLog.h/.cpp` | Logging | C debug / **broken in release** (`GetWindow()` undefined) |
| `Profiler.h/.cpp` | Frame-stack sampling profiler | C (Telemetry path dead) |
| `StackFrame.h/.cpp` | Logical call stack | C (single-threaded only) |
| `Debug.h/.cpp` | `dbg` stream, debug level | C |
| `Thread.h/.cpp`, `Lock.h/.cpp` | `sf::Thread` / `sf::Mutex` wrappers | C |
| `Job.h` | Job interface | C |
| `Time.h/.cpp` | Wall-clock date (`Time_Current`) | C |
| `Timer.h/.cpp` | `sf::Clock` stopwatch | C |
| `Keyboard.h/.cpp`, `Mouse.h/.cpp`, `Joystick.h/.cpp` | Raw input | C |
| `Button.h`, `Buttons.h/.cpp`, `Button/{And,Or,Key,Mouse,Joystick}.cpp`, `Axis.h/.cpp` | Abstract bindable inputs | C |
| `Location.h/.cpp` | Polymorphic I/O locations | C (LocationMemory clone bug; Web is HTTP only) |
| `ResourceMap.h/.cpp` | Resource + mod overlay | C |
| `Archive.h/.cpp` | Packed resource archive | R (dead in debug builds; save path buggy) |
| `Grammar.h/.cpp` | Name grammar | C |

### 3.5 Procedural geometry

| Module | Purpose | Status |
|---|---|---|
| `Meshes.h/.cpp` | Primitive mesh builders (7 script-bound) | C |
| `PlateMesh.h/.cpp` | Plate hull builder + `Mesh_ComputeOcclusion` | C |
| `Warp.h/.cpp`, `Warps.h`, `Warp/Attractor.cpp`, `Warp/Custom.cpp` | Vertex warps | C |
| `SDF.h/.cpp`, `SDFs.h` | SDF base, fractal noise nodes, gradient | P (fractal CPU eval missing) |
| `SDF/{Add,Box,Capsule,Intersection,Mirror,Multiply,Polyhedron,Radial,Repeat,Ring,Scale,Shell,Sphere,Subtract,Torus,Translate,Union}.cpp` | SDF nodes | C (Box CPU/GPU mismatch; MirrorRadial bound bug) |
| `SDF/{Cylinder,Wedge}.cpp`, `SDF/Expand.cpp` (ExpandRadial), `SDF/Pinch.cpp` (PinchAxis) | SDF nodes | P (GPU only; CPU `NOT_IMPLEMENTED`) |
| `SDFMesh.h/.cpp` | GPU-field → MC33 → AO LOD geometry | C (GPU-coupled) |
| `Volume/Array3D.h/.cpp` | Grid + `Mesh_Volume` | C |
| `Volume/MarchingCubes.h/.cpp`, `Volume/LookUpTable.h` | Lewiner MC33 | C (third-party; license unverified) |
| `Volume/Contour.cpp` | Cubical contour prototype | D (`#if 0`) |
| `Volume/Common.h` | typedefs | C |

---

## 4. Script exposure (LTSL)

Two mechanisms make functions script-visible:
- `DeclareFunction` + `DefineFunction(Name)` in the module itself, which self-registers a reflected `Function` at static-init time.
- `FreeFunction`/`VoidFreeFunction` (+ `FunctionAlias` for method-call syntax) in `src/liblt/LTE/ScriptAPI/*.cpp` and elsewhere.

| Group | Where | Exposed |
|---|---|---|
| Scalars | `ScriptAPI/{Bool,Int,Float,Double}.cpp` | Arithmetic, comparisons, trig, `Pow2/Pow4`, `ExpDecay`, `Mix`, `Clamp`, `Random`, constants `Pi/2Pi/Pi2…` |
| Vectors | `ScriptAPI/{V2,V3,V4}.cpp` | Constructors, add/sub, dot, cross, length, normalize, min/max, clamp, floor, mix, pow, `Vec3_Spherical/Cylinder`, `Vec2_Polar`. **`V2.cpp` registers `Vec3_Distance` taking `V2` arguments**, a name clash with V3's (aliased to `Distance`). |
| Transform | `Transform.cpp` | `Transform_Identity/Inverse/Look/LookUp/Matrix/Rotate/Scale/Translation/ST`, `GetDir/GetVector/GetPoint/GetInverseDir` |
| Ray | `ScriptAPI/Ray.cpp` | `Ray_GetPoint` |
| RNG | `ScriptAPI/RNG.cpp` | `RNG_MTG`, `Float`, `Int` (3 overloads), `Gaussian`, `Exp`, `Angle`, `Direction`, `Sign`, `Sphere`, `Vec2/Vec3` |
| Strings / lists | `ScriptAPI/{String,StringList,List}.cpp` | Split, substring, case conversion, hash; `List_Get/Set/Size/GetRandom/Clear…` (`List_Get` has no bounds check; `GetRandom` on an empty list underflows) |
| Input | `ScriptAPI/Keyboard.cpp`, `Mouse.h` (DeclareFunction) | `Key_Down/Pressed/Released/Alt/Control/Shift`, `Keyboard_GetPressed`; `Mouse_GetPos/DP/DX/DY/ScrollDelta/IdleTime`, `Mouse_Left*/Right*`, `Mouse_DoubleClicked` |
| Timing / threads | `ScriptAPI/{Timer,Thread}.cpp`, `Time.cpp`, `Thread.cpp`, `Profiler.cpp` | `Timer()` (returns a **raw `Timer*` that is never freed**), `Timer_GetElapsed/Reset`, `Time_Current`, `Thread_Create/IsFinished/GetResult/SleepMS/SleepUS`, `Profiler_Auto/Start/Stop` |
| OS / I/O | `ScriptAPI/OS.cpp`, `Location.cpp` | `Directory_List`, `OS_IsDirectory/IsFile`, `File_Read`, `Location_File/Resource/Cache/Web` |
| Grammar | `ScriptAPI/Grammar.cpp` | `Grammar_Get(text, rng)` |
| Geometry | `Meshes.cpp`, `PlateMesh.cpp`, `ScriptAPI/PlateMesh.cpp`, `SDF/*.cpp`, `Warp/*.cpp` | `Mesh_Box/BoxRounded/BoxSphere/Plane/Quad/Sphere/CylinderHUD`; `PlateMesh_Create`, `.Add` (plate / child / warp), `.GetMesh`, `.ReflectX/Y/Z`; `Mesh_ComputeOcclusion`; all `SDF_*` constructors (`SDF_Subtract` aliased as `-`); `Warp_AttractorPoint/Plane/Custom` |

Script usage counts from `resource/script`: `RNG_MTG` 28, `Mesh_Quad` 22, `Warp_AttractorPoint` 9, `SDF_Sphere` 7, `PlateMesh_Create` 7, `Grammar_Get` 6, `Location_File` 3, `Warp_Custom` 2, `Time_Current` 2, others 1. **`SDFMesh_Create` is not script-bound.** Scripts can build SDFs but cannot mesh them.

---

## 5. Known issues, quirks and tech debt

Severity: **H** likely to bite in normal use · **M** latent or under specific conditions · **L** cosmetic or in dead code.

### 5.1 Correctness / UB

| Sev | Where | Issue |
|---|---|---|
| H | `RefCounted` / `Reference` | Non-atomic refcounts while References cross threads (scheduler threads, script `Thread_Create`). |
| H | `StackFrame.cpp`, `Profiler.cpp` | One global frame stack for every thread. Any `AUTO_FRAME`/`FRAME` reached from a script thread corrupts it (possible assert at depth 256, or wrong pops). |
| M | `SDFMesh::Intersects` | Uses CPU `Evaluate`, which is `NOT_IMPLEMENTED` for `FractalWorley/Perlin`, `Cylinder`, `Wedge`, `ExpandRadial` and `PinchAxis`. **Ray-picking an asteroid or ice rock through `Model/Renderable::Intersects` would abort the process.** No current caller does this (physics uses `CollisionMesh`), so it is latent, but it blocks adding mouse picking or hitscan against rocks. |
| M | `SDF/Box.cpp` | CPU box distance is unsigned (0 inside) while the GLSL version is signed Chebyshev. CPU queries are wrong inside boxes. |
| M | `Vector.h`/`Array.h` vs `BaseVector.h`/`StackArray.h` | `DEBUG_BOUNDS_CHECK` is `#define`d inside `BaseVector.h` and `StackArray.h`. Inline template code therefore gets bounds checks only in the TUs that happen to include those first. That is an **ODR violation**, and in effect `Vector`/`Array` are unchecked. |
| M | `VectorMap::operator[] const` | Casts to `const VectorMap*` and calls itself: **infinite recursion**. `Distribution::getMin()` reaches it (and passes an index as a key). Both are currently unused. |
| M | `Array::operator==` | `memcmp` of `size()` bytes instead of `size()*sizeof(T)`. |
| M | `Tuple3/Tuple4 ==, !=` | Compare `a.z == a.z`, so the z component is ignored. |
| M | `Vector::shuffle()` | `size()-1` underflow on an empty vector. |
| M | `Pointer` | `operator<(T*, Pointer)` returns `p.t < t` (operands reversed). |
| M | `LocationMemory::Clone` | Copies the raw buffer pointer **with `ownsMemory = true`**, so it is double-freed when both are destroyed. |
| M | `LocationFile::Read` | `new[]` buffer released with `free()` on a read error. |
| M | `Archive` save | Writes `files[i].data` even for files never loaded (NULL), which crashes. Also writes raw `size_t`/`streamoff`, so the format differs between 32-bit and 64-bit. |
| M | `RNG_Default`, `Rand32` | Signed-int overflow (`rand()*RAND_MAX`, `i1 << 16`). |
| M | `V2/V3/V4` comparisons | `<` means "all components less". This is not a strict weak ordering, so V3 is unusable as a `std::map`/`Map` key or with `std::sort`. |
| M | `Bound::Intersects(ray)` | Accepts boxes entirely behind the ray origin. |
| M | `CollisionMesh` ray query | `t` is returned in the mesh's local space (wrong under scale). |
| M | `SDFT::Rotate` | Declared, never defined: link error on first use. |
| M | `SDFMirrorRadial::GetBound` | `radius =` instead of `radius = Max(...)`. |
| M | `Grammar::Parse` | Unknown-rule lookup inserts an empty rule into the map. |
| M | Jobs in `SDFMesh` | Hold raw `SDFMesh*` and `SDFMeshLevel&` (references into a `Vector`). If an `SDFMesh` is destroyed with jobs pending, they dangle. |
| L | `RandGauss` | Is a Laplace distribution, not a Gaussian. |
| L | `RNGT::GetFloat` | Can return exactly 1.0f. |
| L | `SDFT::Gradient` | Missing factor of 1/2. |
| L | `HashMap.h` `DefaultHash` | `std::hash<T>(t)` constructs a hasher instead of calling one. It would not compile if used (it is unused). |
| L | `BaseVector`, `IntrusiveList`, `Cylinder.h`, `SphereTree` | Dead or uncompilable code. |
| L | `PlateMesh::ReflectX/Y/Z` | Reflect plates only, not children or warps. |
| L | `AxisButton` | Declares its own `invert` field that shadows `AxisT::invert`. |
| L | `Debug.h` | `static DebugPrint dbg` in a header, so each TU has its own indent state. |
| L | `UniString_Begin` | Iterates one byte past the string (the NUL). |

### 5.2 Platform / portability

| Sev | Where | Issue |
|---|---|---|
| H | `ProgramLog.cpp` | `BUILD_RELEASE` path calls an undefined `GetWindow()`, so **release builds do not compile**. Release also switches resources to the archive, which no longer exists. |
| H | `OS.cpp` signal handlers + `Common.cpp` | SEGV and assert both end in **`exit(0)`** via the SIGABRT handler. Crash exit codes are 0 and no core dump is produced. The handlers do non-async-signal-safe work (iostreams, file I/O, SFML window close). |
| M | `Window.cpp` | `sf::Event::Closed` is ignored, so the window manager's close button does nothing. |
| M | `HashMap.h`/`HashSet.h` | Linux uses deprecated `std::tr1::unordered_*`. Works on current GCC/libstdc++ but should become `std::`. |
| M | `OS.cpp` | `OS_GetAppDir` = `/usr/bin` (TODO), `OS_GetDocumentsDir` = `./data`, `OS_WriteDump` is a no-op. All user data is CWD-relative `./cache/` (no XDG). `OS_Spawn` leaks a `strdup`. |
| M | `Buttons.h` | Joystick stick-button indices are hard-coded per OS (Windows 8/9, else 9/10). |
| L | `Common.h` | MSVC `#pragma warning` block; `LT_API` dllexport only on Windows. |
| L | `Location_Web` | Plain HTTP via `sf::Http`; only the unbuilt `old/launcher` uses it. |

### 5.3 Performance hazards

| Where | Issue |
|---|---|
| `Mesh_ComputeOcclusion` | O(vertices × triangles) on the GPU, synchronous on the main thread (banded only to avoid GPU timeouts). Big hulls take seconds. |
| `SDFMesh` | Every Z slice of every LOD does a GPU→CPU readback (`GetData`) under `GL_Finish`. `Draw()` **spins on `Scheduler_Flush()`** until some LOD exists, so every newly visible asteroid causes a frame hitch. |
| `Warp_Custom` | One LTSL VM call per vertex per warp. |
| `Geom_SmoothHull` | O(hull vertices × source vertices) nearest-vertex search (used for shields). |
| `Diff_Create` | Puts a 17,408-element array of `Vector<size_t>` (about 400 KB) on the stack. |
| `Profiler` | The sampler thread spins with 1–2 µs sleeps while active. |
| `ProgramLog` | Every log line flushes stdout and the file. Multi-line entries are printed once per line, so N lines are printed N times. |
| `VectorMap`, `Distribution`, `PriorityQueue`, `Vector::contains/remove`, `Archive::Contains` | Linear scans. |
| `Scheduler` memory gate (dependency) | 1 MB budget means big threaded jobs effectively run one at a time, despite the 8-thread cap. |

### 5.4 Determinism

Global `rand()` is seeded from `time(0)` and drives `Rand*`, `Vector::random/shuffle`, `Array::random` and asteroid/ice seeds. Only code that explicitly uses `RNG_MTG(seed)` (most scripts, the grammar) is reproducible.

---

## 6. Dependencies

| Depends on | Used by (this area) | Notes |
|---|---|---|
| **SFML 2.5.1** System/Window/Graphics/Network | `Timer` (`sf::Clock`), `Thread` (`sf::Thread`), `Lock` (`sf::Mutex`), `Window` (`sf::RenderWindow`, events), `Keyboard`/`Mouse`/`Joystick` (polling), `Location_Web` (`sf::Http`) | Vendored in `ext/SFML`, statically linked. |
| OpenGL / GLEW (via the Renderer) | `Mesh_ComputeOcclusion`, `SDFMesh` | Uses `Texture2D/3D`, `Shader`, `Renderer_DrawQuad/DrawFSQPart`, `GL_Finish` (rendering catalog). |
| Shaders | `resource/shader/fragment/compute/occlusion.jsl`, `fragment/gen/{field,fieldcopy,fieldgradient,fieldocclusion}.jsl`, `common/{field,noise,global}.jsl` | The SDF GLSL library must stay in sync with the C++ `GetCode` strings. `fieldgradient.jsl` is loaded but its shader is never invoked in `SDFMesh.cpp`. |
| Reflection / LTSL (scripting catalog) | `AutoClass`, `FIELDS`, `Type_Get`, `DefineFunction`/`FreeFunction`, `Data`, `ScriptType`/`ScriptFunction` (Warp_Custom, Thread_Create) | Nearly every struct here carries reflection metadata. Extracting code means stripping it. |
| `Mesh`/`Vertex` (rendering catalog) | All geometry code | `Vertex{p, n, u, v}`. AO lives in `u`. |
| `Module/Scheduler`, `Module/FrameTimer` | SDFMesh jobs, frame dt | |
| `ThirdParty/TriTriOverlap.cpp` (Möller), `ThirdParty/UTF8` | CollisionMesh, UniString | |
| Lewiner MC33 | Volume | Embedded source; license unverified. |
| C++ stdlib incl. `tr1` | Containers | No C++11 features required (it is C++03-style code). |
| POSIX (`stat`, `dirent`, `unistd`, `spawn`, `signal`) | OS | Win32 branches still present. |
| Game layer (consumers) | `Asteroid/Ice/Pod/Zone/Wormhole/WarpRail/StationType` (SDFMesh), `ShipType/StationType` (PlateMesh), `Queryable` (hash grid), `PhysicsEngine`/`Collidable` (CollisionMesh), `Region` (Graph MST, Grammar), `Shield` (SmoothHull) | |

---

## 7. Assessment

### 7.1 Goal (a): push toward a playable game

Most of this area is "good enough" and does not block gameplay. Fix these, in priority order:

| # | Fix | Why | Effort |
|---|---|---|---|
| 1 | Handle `sf::Event::Closed` in `Window::Update` | Basic usability | Trivial |
| 2 | Make `SDFMesh::Intersects` fall back to the polygon mesh (or a CollisionMesh) instead of CPU `Evaluate`, or implement the missing `Evaluate`s (FractalWorley needs a CPU `cnoise` port) Any future picking or hitscan against asteroids through `Renderable::Intersects` would abort | Small–Medium |
| 3 | Stop `Draw()` busy-waiting. Draw nothing, or the 32³ collision mesh, until LOD 0 is ready; and/or keep `kPreload` off but warm up asteroids during loading | Hitches when flying into fields | Small |
| 4 | Signal and assert path: let SIGSEGV/SIGABRT terminate with non-zero status (or re-raise with `SIG_DFL`) so crashes are debuggable with gdb and core dumps | Debuggability | Small |
| 5 | Make `RefCounted` atomic (`std::atomic<uint>`), or forbid `Reference` across threads; make `StackFrame` thread-local | Removes heisenbugs when script threads are used | Small (atomic) |
| 6 | Fix the `ProgramLog` `GetWindow()` reference, so `BUILD_RELEASE` compiles (and keep `kUseArchive = false`) | Optimized builds | Trivial |
| 7 | Seed asteroid/ice SDFs from a deterministic `RNG_MTG` instead of `Rand()` | Save/load reproducibility | Small |
| 8 | Move the AO bake (`Mesh_ComputeOcclusion`) behind the Scheduler as a time-sliced serial job (like `SDFMesh::GenerateOcclusion`) and/or cache baked meshes in `./cache/` | Ship generation stalls | Medium |
| 9 | Swap `std::tr1` for `std::` and fix the small container bugs in §5.1 as they come up | Hygiene | Small |

Nothing here needs rewriting to ship a game. The main load-bearing risks are threading and the GPU-synchronous procedural jobs.

### 7.2 Goal (b): dissect and cross-map into a new game

| Piece | Self-contained? | Worth extracting? | Recommendation |
|---|---|---|---|
| **SDF tree with dual CPU/GLSL backends** (`SDF*.cpp` + `common/field.jsl`) | Mostly. Needs V3/Bound/Stringize and the reflection macros stripped. | **Yes: the idea is the gem.** One expression tree that both evaluates on the CPU and emits shader code. | Re-implement as a small node graph that emits GLSL/WGSL/HLSL (or compute shaders). Replace the sigmoid "smooth union" with a proper polynomial smooth-min (Quilez), make every node signed and exact (fix Box), and make CPU and GPU share one definition. |
| **SDFMesh pipeline** (GPU field → LOD grids → MC → AO) | No. Tied to the Renderer, Scheduler and Texture3D. | **Yes, as a design.** | In a modern engine, do field evaluation and meshing in one compute pass (GPU MC or surface nets, or dual contouring for sharp features), with no per-slice readbacks. Keep the LOD scheme (0.666x per level, chosen by distance/radius), the largest-component floater removal, and the field-sampled AO kernel. |
| **Lewiner MC33** (`Volume/`) | **Yes.** Plain C++ with only `LTE_ASSERT`, `Abs` and a vertex/triangle array output. | Maybe | A topologically correct MC is nice to have. Verify the license first. Alternatives: a standard MC table (public domain, Bourke), or surface nets / dual contouring for fewer, better triangles. |
| **PlateMesh + warps** | Mostly (needs `Mesh_BoxRounded` and the matrix helpers) | **Yes, conceptually.** Cheap, convincing kit-bashed hulls. | Port as a "union of rounded boxes, then deform, then AO" generator. Consider SDF-unioning the plates (the rounded-box SDF is already here) and meshing them, to get a manifold hull without interior faces. Keep the mirror-symmetry and grow-from-seed-boxes logic (in the scripts). |
| **Disk-based AO bake** (`Mesh_ComputeOcclusion` + `occlusion.jsl`) | Small and clear | Yes | Port to a compute shader with a BVH or hierarchical surfels (Bunnell's two-pass hierarchy) for O(V log T). Or bake offline. |
| **Spatial hash grid** (`SpatialPartition_HashGrid.cpp`) | **Yes** (~190 lines; `Vector`, `V3`, `Bound3`, `Ray`) | Yes | A good compact reference: version-stamp de-duplication and a DDA ray walk. Template it over the object type instead of `void*`. |
| **CollisionMesh** (grid + signature + tri–tri) | Fairly (needs a Mesh, the grids and TriTriOverlap) | Partly | Fine for boolean triangle-mesh tests. For a real game, prefer a physics library (Jolt, Bullet, Rapier) that gives contact manifolds and penetration depth. |
| **Math library** (V2–V4, Matrix, Bound, Transform) | Mostly; reflection macros are woven into `AutoClass` | Ideas only | Use GLM/`glam`/DirectXMath instead. Keep the **Transform design** (double-precision position + float basis + per-axis scale) and `ComputeImpact` (lead targeting). |
| **RNG** | Yes | Low | MT19937 is in `<random>`. Use PCG/xoshiro for speed. Keep the convenience samplers (`GetSphere`, `GetDirection`, `GetCubeSurface`, `GetErlang`) as free functions. |
| **CPU noise** | Yes | Low | Use FastNoiseLite or similar. The sin-hash noise has poor quality and precision. |
| **Grammar** | **Yes** (~240 lines; RNG + String + VectorMap) | **Yes** | A drop-in procedural-naming system with weighted, tagged productions. The data file (`default.txt`) is reusable as is. Port it as-is or to Tracery-style JSON. |
| **Graph MST** | Yes | Low | Standard Kruskal. Any library has it. |
| **Input abstraction** (Button/Axis combinators, `Capture`) | Needs SFML | Ideas | The composable Button/Axis tree with dead zone, power and capture-for-rebinding is a nice pattern. Re-implement on SDL3 or your engine's input layer. |
| **Frame-stack sampling profiler** | Needs StackFrame + Thread | Ideas | Use Tracy instead. The scoped-frame pattern maps directly onto Tracy zones. |
| **Location / ResourceMap with mod overlay** | Mostly | Ideas | A virtual filesystem with mod directories overriding base files is worth keeping as a concept (PhysFS does this). |
| **Containers, smart pointers, String, Hash, Pool, Diff/Patch, Archive** | — | **No** | Replace with the standard library (`std::vector`/`unordered_map`/`shared_ptr` or an intrusive pointer with atomics), a modern allocator, and zstd/PhysFS for archives. |
