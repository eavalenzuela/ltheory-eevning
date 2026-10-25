# 02 — Rendering (engine + game-side) and Shaders

Scope: `src/liblt/LTE/` rendering files (Renderer, RenderPass*, RenderStyle, Renderable, DrawState, GL*, Shader, ShaderInstance, Texture2D/3D, CubeMap, Mesh, Model, Font, Color, ParticleSystem, Viewport, View, Vertex), `src/liblt/LTE/RenderPass/`, `src/liblt/Game/{Graphics,Renderable,RenderPass}/`, Game top-level `Renderables.h`, `RenderPasses.h`, `Materials`, `ShadingModels`, `Light`, `Particles`, `Beam`, and all 169 files in `resource/shader/`.

How this was checked: by reading the code. Nothing was built or run. Shader usage comes from grepping quoted shader paths in `src/` and `resource/script/`. Anything I'm unsure of is marked **(unverified)**.

---

## 1. Overview

LTE's renderer is a thin layer over **OpenGL 2.1 plus extensions** (FBOs, float textures, MRT, `GL_EXT_gpu_shader4`, texture LOD in fragment shaders, anisotropy). The EasyGL wrapper (`GL.h`, `GLEnum.h`, `GLType.h`) adds type safety. All shaders are compiled as **GLSL `#version 120`** (`attribute`/`varying`, `gl_FragData`, `texture2D`, `textureCube`). Shaders use a small custom preprocessor (`.jsl` files: `#include`, `#output`).

The state model is global and immediate. Blend, cull, depth, viewport, scissor and render targets are kept as **push/pop stacks**. Render targets are resolved through an **FBO cache keyed by a hash of the attachments**.

On top of that sits a **deferred-ish pipeline**, built by composing `RenderPass` objects:

- a visibility pass (frustum and distance culling)
- a linear-depth prepass
- a 2-target G-buffer: albedo+coverage, and packed normal / roughness / material-id
- a full-screen global (image-based) lighting pass
- a batched full-screen point-light pass (max 16 lights)
- a composite pass that applies fog and the background env-map
- a forward alpha-blended pass, then particles
- lens flares with GPU occlusion readback
- bloom, a tonemap curve, a per-star-system procedural 1D colour grade
- SMAA, then dither

Rendering is **camera-relative**: world positions are double precision and the camera position is subtracted on the CPU. Depth is **logarithmic**, computed per vertex, with near 0.05 and far 1e6.

The most distinctive part is **procedural content generation on the GPU**. Planet surfaces, nebula skyboxes, irradiance cubemaps, blurred skyboxes, metal plating textures, normal maps, lens-flare sprites, SDF font glyphs, SDF-mesh fields and per-vertex AO are all produced by running full-screen fragment shaders into textures or cubemaps. Big jobs are split into scissored column (or row) jobs with `glFinish` between them so the GPU watchdog doesn't fire. Large cubemaps are serialized to `cache/cache/*.bin`.

Overall maturity: the main game pipeline works (the session's smoke tests show it running on Mesa). It is clearly a 2014-era research renderer, though. It uses legacy GL, client-side vertex arrays, no instancing or batching, sync points every frame, and several dead or half-finished passes and shaders.

---

## 2. Architecture

### 2.1 Renderer state model (`LTE/Renderer.{h,cpp}`)

| Concept | Implementation | Notes |
|---|---|---|
| Global state | one anonymous-namespace `Renderer renderer` struct | Not thread-safe. Single GL context assumed. |
| Pushable stacks | `blendMode`, `cullMode`, `zBuffer`, `zWritable`, `scissor`, `viewport`, `colorAttachment[4]`, `depthAttachment` | Each push and pop immediately issues GL calls. There is no deferred diffing. RAII helpers: `RendererBlendMode`, `RendererCullMode`, `RendererZBuffer`, `RendererZWritable`, `RendererState`. |
| Blend modes | `Additive` (1,1), `Alpha` (SrcA, 1-SrcA; alpha channel 1,1), `Complementary` (1, 1-SrcColor), `Multiplicative` (DstColor, 0), `Disabled` | |
| Cached state | bound VBO/IBO, enabled vertex attrib arrays (8) | `Renderer_ResetGlobalState()` runs on **every `Renderer_Clear`** (it resyncs attribs, unbinds buffers and switches to the fixed-function program). |
| Render targets | `Renderer_Push/PopColorBuffer(index, tex, guid, target)` and `Push/PopDepthBuffer(tex)` | Every push or pop calls `Renderer_UpdateFramebuffer()`. It hashes the top of each attachment stack (index, GL name, target, texture guid), looks the hash up in `fboCache` (a `VectorMap<hash, FBO>`), and creates and attaches an FBO on a miss. When nothing is attached it binds FBO 0. `glDrawBuffers` is set from the non-null colour attachments. |
| FBO cache eviction | when the cache has more than 128 entries, **all** cached FBOs are deleted | It is keyed only by hash, so a collision would silently reuse the wrong FBO (unlikely). Depth attachments are keyed by GL name only, not a guid. |
| Matrices | `world`, `view`, `proj`, `worldIT`, `wvp` | `kCameraSpaceRendering = true`: `SetViewTransform` zeroes the view translation and `SetWorldTransform` subtracts the camera position (both double) before building float matrices. This is a solid large-world technique. |
| Shader binding | `Renderer_SetShader(shader)` calls `shader.Use()` and then injects the WORLD/VIEW/PROJ/WORLDIT/WVP uniforms | Matrices are injected only when SetShader is called. Changing a transform afterwards needs another SetShader or `ShaderInstance::Begin`. |
| Draw entry points | `DrawMesh` (VBO/IBO), `DrawQuad` (client-side arrays, byte indices), `DrawFSQ` (quad with blend and depth off), `DrawFSQInParts` / `DrawFSQPart` (scissored), `DrawVertices` (client-side arrays; generic reflected vertex format via `Type`), `DrawQuadOutline` (**`glBegin`/`glEnd`**) | Attribute slots: 0 = position, 1 = normal, 2 = uv, 3 = colour. Generic vertex formats map field i to attribute i. |
| Mesh upload | `PrepareMeshForDraw`: when `mesh->bufferVersion != mesh->version` it deletes and recreates the VBO/IBO (`GL_STATIC_DRAW`) | Indices are narrowed to 16-bit when the mesh has fewer than 65535 vertices. |
| Stats | per-frame draw call and polygon counters (`Renderer_ResetCounters` is called from the Clear pass) | Exposed to scripts. |

### 2.2 Shader system (`LTE/Shader.{h,cpp}`, `LTE/ShaderInstance.{h,cpp}`)

**JSL preprocessing** (`JSLPreprocess`, applied recursively):

| Directive | Effect |
|---|---|
| `#include foo.jsl` | Inlines `resource/shader/common/foo.jsl`, recursively. **There is no include-once handling in the preprocessor.** About half of the common files carry `#ifndef common_x` guards; the rest (`frag.jsl`, `vert.jsl`, `global.jsl`, `cube.jsl`, `fdm.jsl`, `field.jsl`, `ui.jsl`, ...) rely on shaders not double-including them. |
| `#output N type name` | Emits `#define name gl_FragData[N].xyz…` with a swizzle sized to the type. This is how MRT outputs get named (for example `fragment_color0`/`fragment_color1` in `frag.jsl`, or `visibility` and `field_value` in the compute shaders). |
| other `#…` | passed through unchanged |
| `RETURN(x)` | Not a directive. It is a macro in `common/frag.jsl`: `{ fragment_color0 = x; return; }`. |

`#version 120` is prepended (`kVersionDirective`). `global.jsl` enables `GL_EXT_gpu_shader4` and defines `HIGHQ` when it is present. `VERT_IN`/`VERT_OUT`/`FRAG_IN` map to `attribute`/`varying` (an `#if 1` switch; a GLSL 1.30+ branch exists but is disabled).

**Objects and caching:**

| Layer | Key | Notes |
|---|---|---|
| `ShaderObjectT` (GL shader) | path (`vertex/x.jsl`, `fragment/y.jsl`) | On compile failure it logs the numbered source and **calls `getchar()`**, which blocks the process on stdin. |
| `ProgramObjectT` (GL program) | `"vs?fs"` | Fixed attribute bindings: `vertex_position`=0, `vertex_normal`=1, `vertex_uv`=2, `vertex_color`=3. Fragment outputs: `fragment_color0`=0, `fragment_linearDepth`=1. Caches the matrix uniform locations. The uniform location cache is a `Map<String,int>` (the fix from this session; it used to be keyed by `char const*`). Missing uniforms log a one-time "Unused variable" warning per program. |
| `ShaderImpl` (`Shader`) | wraps one program | Setters call `Use()` and upload immediately. Textures are bound to a **per-program round-robin texture unit counter, mod 16** (`GetTextureUnit`). Units are never reset per draw, so a program that sets more than 16 samplers over its lifetime wraps around. Units are assigned on every Set call, so per-draw rebinding works, but assignments are not stable. |
| `Shader_Create(vs, fs, vsHeader, fsHeader)` | **not cached** | Prepends headers. Used by `SDFMesh` to inject a GLSL `field()` function. These shaders have no path and are skipped by hot-reload. |
| `Shader_RecompileAll` | | Hot reload: re-reads and re-preprocesses every cached shader by path and recompiles and relinks those whose source changed. Bound to the **T** key in several apps (`rails`, `map`, `objectinfo`, `widget`). |

**ShaderInstance** is a "material instance": a `Shader` plus a `HashMap<uniformLocation, ShaderVar*>` plus a linked list of `RenderStateSwitch` values.

- Values are `Generic<T>`, which are lazy thunks. A uniform can be bound to a function (for example DrawState's `GetEnvMap`, `GetFrame` or `GetGameTime`) that is re-evaluated on every `Begin()`.
- `Begin()` calls `Renderer_SetShader`, pushes each render-state switch, and uploads every variable. `End()` pops the switches.
- State caching is **disabled** (`gSkippedState = false; /* TODO : Fix state caching. */`), so every draw re-uploads every uniform.
- Render-state switches: `BlendModeAdditive/Alpha/Complementary/Disabled`, `CullModeBackface/Disabled`, `WireframeOn/Off`, `ZBufferOn/Off`, `ZWritableOn/Off`. `HasBlending()` is set when an additive, alpha or complementary switch is added; render styles use it to route an instance to the opaque or blended pass.
- **Bug:** in `ShaderInstanceT::Clone()` the render-state copy loop never advances `next`. Cloning an instance that has any render-state switch loops forever, allocating as it goes. It is exposed to scripts as `ShaderInstance_Clone` / `.Clone`. The only script use (`Item/ShipType/Generate.lts`) is inside a commented block and clones `Material_Metal`, which has no switches.

**DrawState** (`LTE/DrawState.{h,cpp}`) is the per-render context. It is a `Pushable` struct holding:

- the view stack and envMap / envMapLF stacks
- the buffers: `primary`, `secondary`, `tertiary`, `color[3]`, `smallColor[2]`, `depth`
- the visible-object and light lists

It also provides a **global named-value blackboard**: `DrawState_Push/Pop(name, Data)`. `DrawState_Inject(shader)` uploads every blackboard entry whose name matches an active uniform. `DrawState_Link(shader | instance)` injects once and binds lazy getters for `depthBuffer`, `normalBuffer`, `camUp`, `eye`, `frame`, `rcpFrame`, `envMap`, `envMapLF`, `INVVIEW`, `INVPROJ` and `time`.

Quirks:
- `normalBuffer` is linked to **GetDepthBuffer**. The lighting passes override it explicitly, so this is probably a copy-paste slip.
- `eye` is always 0, because rendering is camera-relative.

Values the star system pushes through this blackboard: `starColor`, `starPos`, `irMap`, the colour-grade curves `rCurve…bCurve2` and `rDir/gDir/bDir`, `colorPoints`. The camera pass pushes `fogDensity` and `camVelocity`.

**RenderStyle** (`LTE/RenderStyle`, `Game/Graphics/RenderStyles`) is a global stack of strategies that decide *how* a `Model` piece is drawn in the current pass. `ModelT::RenderPiece` calls `style->SetShader(instance)` and then `style->Render(geometry)`.

| Style | Used by | Behaviour |
|---|---|---|
| `RenderStyle_Default(false)` | GBuffer | Draws only instances **without** blending. Sets uniform `prepass=0` when the instance changes and injects the DrawState blackboard. |
| `RenderStyle_Default(true)` | Blended, Particles | Draws only instances **with** blending (alpha blend, z-write off). |
| `DepthPrepassStyle` | DepthPrepass | Draws opaque, z-writing instances with **their own material shader** and `prepass=1` set on the program. `PREPASS` in `frag.jsl` makes the material output `linearDepth`. It also builds a `depthprepass.jsl` instance that is never used. |

Fragility: `prepass` is a *per-program* uniform, but the reset to 0 is tied to the *per-instance* pointer changing in a style that remembers `currentShader` across frames. It only works today because the star-system skybox instance is always drawn first in the G-buffer pass **(unverified for scenes with no system container)**.

### 2.3 Frame pipeline

The pass lists come from scripts. `App/ltheory.lts`, `handling`, `rails`, `model`, `dogfight`, `war`, `Widget/Observatory` and `Widget/ModelEditor/Preview` all build `Widget_Rendered [Clear, Camera, (CustomFilter), SMAA, (Interface), PostFilter "post/dither.jsl"]`. `Widget_Rendered` (`UI/Widget/Rendered.cpp`, owned by the UI cataloger) allocates 3 RGBA16F full-size buffers, 2 RGBA16F 1/4-size buffers and a `DepthComponent32F` depth texture. It sets `primary=color[0]`, `secondary=color[2]`, `tertiary=color[1]`, pushes the depth buffer, runs the passes, and presents `state.primary` to the window with `widgetTexture.jsl` + `ui/texture.jsl`.

```
Widget_Rendered::PreDraw  (per frame, fresh DrawState)
│ buffers: C0,C1,C2 = RGBA16F full-res; S0,S1 = RGBA16F 1/4-res; D = depth32F (HW)
│
├─ RenderPass_Clear(0)            C0 <- 0, S0,S1 <- 0, reset draw counters
├─ RenderPass_Camera(camera)      sets view/proj, fogDensity, camVelocity, container->BeginDrawInterior
│   │                             (System pushes envMap/envMapLF/irMap/starPos/starColor/color curves)
│   ├─ Visibility                 walk container interior: distance cull + frustum (double planes) -> state.visible, state.lights
│   ├─ DepthPrepass               R32F "depth" (own texture) <- material shaders w/ prepass=1 (linear clip-z);
│   │                             HW depth cleared before AND after -> no HW early-Z benefit
│   ├─ GBuffer                    MRT: C0 = albedo.rgb (linear) + coverage a ; C1 = enc.normal.xy, roughness, matId/4
│   │                             materials do EARLY_Z: discard if linearDepth > prepass depth
│   ├─ (SSAO)                     commented out; broken (see §6)
│   ├─ GlobalLighting             C2 <- light/global.jsl  (IBL: irMap mip by roughness for COOKT, ice refr/refl, NOSHADE=1)
│   ├─ LocalLighting              C2 += light/point.jsl, additive, 16 lights/batch, max 16 lights (sorted by |c|/dist)
│   │                             then light/composite.jsl -> C1: albedo*light, distance fog, env-map background
│   │                             via coverage alpha, **converted to gamma here**; primary=C1, secondary=C0, tertiary=C2
│   ├─ Blended                    forward alpha-blended instances into primary (HW depth from GBuffer)
│   ├─ (DustClouds)               commented out
│   ├─ Particles                  container's ParticleSystem -> primary (CPU-built billboards, client arrays)
│   ├─ LensFlares                 sprites -> tertiary (additive), composite + lens dirt -> secondary, flip;
│   │                             then GPU occlusion query texture + **glGetTexImage readback** -> light->visibility
│   ├─ Bloom(128, 64)             glowthresh -> S0, sep. gaussian S0->S1->S0, bloom_composite(primary,S0) -> secondary, flip
│   ├─ Tonemap                    post/tonemap.jsl: 1 - exp(-1.5 * c^1.25)
│   ├─ (MotionBlur)               commented out
│   └─ PostFilter colorgrade1D    per-system random R/G/B curves (6 x 1D R8 textures) blended across screen
├─ RenderPass_SMAA                edge (->tertiary) / weights (->secondary) / blend (->tertiary), swap
├─ [RenderPass_Interface ui]      rails.lts only (UI cataloger)
├─ RenderPass_PostFilter dither   +-1/256 noise
└─ Present: primary -> window quad (ui/texture.jsl, alpha blend)
```

How passes compose:
- `RenderPassT::Render` wraps `OnRender` in a profiler frame and checks `Settings_Bool("Graphics/<TypeName>", true)`, so every pass can be toggled from settings.
- `RenderPass_Composite` runs a list of passes.
- `CameraPass` owns a hard-coded list (`Game/RenderPass/Camera.cpp`). To change the in-camera pipeline you edit C++. Scripts can only wrap passes around it.
- Post passes ping-pong `primary`/`secondary` through `DrawState::Flip()`.
- `RenderPass_CustomFilter(scriptObject)` calls a script type's `Texture Render(Texture)` and replaces `primary` with the result. `Observatory.lts` uses it to chain `Texture/Filters.lts` operations.

### 2.4 Materials / shading models / lighting

G-buffer contract (`common/frag.jsl`):

| Target | .xyz | .w |
|---|---|---|
| `fragment_color0` (C0) | albedo, linear (`outputAlbedo`) | coverage / alpha (`outputAlpha`). 0 means background, and composite shows the env-map there. |
| `fragment_color1` (C1) | `.xy` normal encoded as spherical (atan2, z) — `encodeNormal`; a stereographic variant is behind `#if 0`. `.z` roughness. | material id / 4: `PHONG`=0, `COOKT`=1, `ICE`=2, `NOSHADE`=3 |
| prepass R32F | linear depth = clip-space z before log-depth remap | |

| C++ factory (`Game/ShadingModels.cpp`) | Shaders | Material id | Notes |
|---|---|---|---|
| `ShadingModel_Debug` | npm / material/debug | NOSHADE | Distance-adaptive grid lines. |
| `ShadingModel_FlatColor(color)` | skybox / solidcolor | NOSHADE | **`solidcolor.jsl` has a syntax error** (missing `;` after `outputMaterial(...)`). It would fail to compile and hit `getchar()`. No callers found, so it is dormant. |
| `ShadingModel_Fresnel(albedo, normal)` | npm / material/fresnel | ICE | Computes a bump value and discards it. Albedo is forced to white. |
| `ShadingModel_Lambert(albedo, normal)` | npm / material/lambert | COOKT (despite the name) | Uses "FDM" (frequency-dependent multi-scale triplanar) sampling and a bump map. Albedo is multiplied by `uv.x^4`; **uv.x carries baked AO** (see Mesh). |
| `ShadingModel_Metal(albedo, normal)` | npm / material/metal | COOKT | Triplanar procedural plating, a detail map from `filter_rust.jsl` (512²), roughness 0.01–0.2. The bump contribution is effectively zero (`mix(..., 0.0001)`). |
| `ShadingModel_Skybox` | skybox / skybox | NOSHADE | Samples `envMap` on a reversed far-plane box. Z-write off. |
| `ShadingModel_Water` | npm / material/water | forward, alpha | Soft depth-difference colour, Fresnel env reflection, fog. Atmosphere hooks are commented out ("CRITICAL"). |

| Material (`Game/Materials.cpp`; all are static singletons) | Built from |
|---|---|
| `Material_Metal` | GPU-generated 1024² plating (`gen/plating.jsl`, 2 MRT outputs), `filter_ao` (256 samples), `filter_dirt`, plus a 1×1 decal. This is the main ship and station material. |
| `Material_Rock` | `rock.jpg` + `Generator_NormalMap` -> Lambert |
| `Material_RockShiny` | Same as Rock, but returns a **new** instance on every call. |
| `Material_Ice` | `ice.jpg` + normal map built from `rock.jpg` -> Fresnel |
| `Material_Grass` | `gen/rock.jsl` texture -> Lambert. Used by Colony terrain. |
| `Material_Water`, `Material_Debug` | the shading models above |

Lighting model:
- **Global:** image-based. COOKT samples `irMap` at LOD `9*sqrt(roughness)` on `HIGHQ` hardware, otherwise `envMapLF`. PHONG uses a sharp sun term plus `envMapLF`. ICE uses refraction and reflection of `envMap` plus a sun specular / transmission term. **There is no direct sun term for COOKT**; it is commented out.
- **Local:** point lights only (`Game/Light`, an attachable object with `color`, `radius`, `flare`, `visibility`). 1/d falloff. Cook-Torrance for COOKT, Lambert for PHONG, ice lobes. Scaled by `kDynamicLightMult = 16`. Up to 16 lights per frame. They are sorted by `|color|/distance` and evaluated in a single full-screen batch (`kBatchSize = 16`), not as light volumes.
- **No shadows** of any kind. Planets fake terrain self-shadowing by marching their height cubemap, and rings shadow analytically.
- Fog: `getFog` / `getFoginess` in `common/lighting.jsl`, driven by `fogDensity` from zone containment.
- Atmospheric scattering: `common/scattering.jsl`, 8-sample O'Neil-style in/out scattering, used by planet, atmosphere, tree and planetskybox.

### 2.5 Particles

`LTE/ParticleSystem.cpp` keeps one `Map<ShaderInstance, Vector<Particle>>` per system. Systems live on a global stack (`ParticleSystem_Push/Get/Pop`); each container's interior owns one.

- `Run(dt)`: Euler integration and lifetime decay. Capped at 1M particles per shader. Removal uses `removeIndex`, an O(1) swap-with-last, so particle order is not stable.
- `Draw`: for each shader, CPU-builds a billboard quad (4 verts / 6 indices) per particle. Each particle gets a point-frustum test and a size/distance LOD cull (`d² < 512²·r²`). The vertex packs size and age into the normal and colour into the colour attribute. Drawn with `Renderer_DrawVertices` from **client memory** (no VBO). Particles are not sorted; they are additive in practice.
- The billboard is expanded in the vertex shader (`particle.jsl`) facing `camUp`, with fade-in/out from age and a z-offset toward the camera.
- Particle types (`Game/Particles.cpp`): `Particle_Fire`, `Particle_Firefly`, both `particle_radial.jsl`, additive. Spawners in `Game/Graphics/Effects.cpp`: `Effect_BeamHit`, `Effect_ParticleFirefly`, `Effect_SmallPlume`, plus `Effect_MultiExplosionRadial`, which spawns `Object_Explosion` children and sounds (gameplay side).
- Other "effects" are objects with their own renderables (owned by the world-model cataloger; shaders listed in §4): Beam (`Game/Beam.cpp`, `billboard_axis`+`beam`), Explosion, Trail, Thruster, Pulse, Rail, Shield, DustFlecks, Wormhole, WarpRail, TransferUnit.

### 2.6 Text / fonts (`LTE/Font.cpp`)

- FreeType loads `resource/font/<path>` at 64 px.
- Glyphs are added **lazily on first use**. Each glyph is rasterized into a 1024² R16F bitmap. Then `compute/sdffont.jsl` computes a brute-force **unsigned outside distance field** (search radius 64 px, about 16.6k taps per texel) into a 1024² R32F atlas, using an 80 px cell (64 + 2·8 padding), and regenerates the atlas mipmaps.
- Drawing builds a quad per glyph (`TextVertex` p/color/uvScale) with kerning cached per glyph pair, and renders with `widget.jsl` + `ui/text.jsl`. The fragment shader does bicubic SDF sampling, a normal mode (dark halo plus fill), and an additive "glow" mode.
- Limits: the atlas has **no overflow handling**. About 144 glyphs fit (12×12); past that, writes go off the texture. If `FT_New_Face` fails, `face` stays uninitialized and the next draw will likely crash.
- `Fonts.lts` asks for `NotoSansCJKSC/…`, but the directory is `NotoSansCJKsc`. That fails on case-sensitive filesystems; it is only referenced from a commented block today.

### 2.7 Texture / cubemap generation and disk caching

| Mechanism | Where | Details |
|---|---|---|
| `Texture_Generate(tex, shader)` | `Texture2D.cpp` | Binds the texture as RT0 and draws a full-screen quad in scissored **column jobs**. Job width starts at 1 px and is scaled toward `maxJobTime` (default 1 s), at most doubling per step (the 2× cap was added this session). `glFinish` runs after every job. A 2-target MRT variant exists. Mipmaps are generated afterwards. |
| `CubeMap::GenerateFromShader(shader)` | `CubeMap.cpp` | For each of the 6 faces: attach the face, set a 90° look-at view, compute `origin`/`du`/`dv` (the frustum corner rays) plus `halfTexel` and `texelScale`. `common/cube.jsl::GetCubePosition(uv)` turns these into a direction. Same adaptive column jobs. **Side effect:** it leaves the renderer's global view/proj matrices set to the last face. |
| `Texture2D_Filter(tex, shader)` | | Allocates a new texture of the same size and runs the shader with `texture` = input. |
| `Generic<T>` + `Cached(...)` | `LTE/Function/Cached.h` | In-memory memoized thunk. Generators return `Generic<CubeMap>` / `Generic<Texture2D>` that are evaluated **lazily on first use, which is often mid-frame inside the Camera pass**. The logs show "Camera Pass.Generate IRMap.Generate CubeMap". |
| `DiskCached(gen, name)` | same file | On first evaluation it tries `LoadFrom(cache/cache/<name>.bin)` (the reflective Serializer; `CubeMapImpl::FIELDS` dumps level 0 of all 6 faces). Otherwise it generates and calls `SaveTo`. **The key has no shader-version or format component**, so delete `cache/cache/` after editing generator shaders. |

| Generator (`Game/Graphics/Generator/`) | Output | Shader | Cached? | Used by |
|---|---|---|---|---|
| `Generator_PlanetSurface(seed)` | 2048² RGBA8 cube: height, colour index, clouds | `gen/planet.jsl` (32-iteration Kali-style 4D fractal for height, 24 for colour, fBm clouds) | **disk** `planetsurface_<seed>` (about 100 MB at level 0) | `Item/PlanetType.cpp` -> `planet.jsl` `planetMap` |
| `Generator_Nebula(args)` | 1024² **RGBA32F** cube | `gen/nebula.jsl` (emission fBm, star glow, 128-step absorption march with a 24-iteration fractal each step; quaternion-rotated domains) | **disk** `nebula_<systemSeed>` (about 100 MB) | `Object/System.cpp` envMap |
| `Generator_Blur(src, radius, res, samples)` | cube with the source format | `cubemap/blur.jsl` (random jitter taps) | **disk** `sysbg_<seed>_blurred` (0.1, 1024, 512 samples) | System envMapLF |
| `Generator_IRMap(src, samples)` | cube with full mip chain: level 0 copied, level i is a cone-blurred `angle=(i/(L-1))²` | `cubemap/irmap.jsl` (samples from an RNG direction texture) | memory only; **regenerated every launch** with 1024 samples per texel per level, plus a GPU->CPU->GPU copy of each level | System irMap (COOKT IBL) |
| `Generator_PlanetSkybox(planet)` | 1024² RGBA8 cube | `gen/planetskybox.jsl` (sky scattering from the surface) | memory | `Object/Colony.cpp` envMap |
| `Generator_NormalMap(tex, strength)` | RGBA8 | `gen/normalmap_lum.jsl` | memory | Materials |
| `Generator_ShaderInstance(w, h, inst)` | RGBA8 | any | memory | Material_Grass |
| `Generator_LoadTexture2D(loc)` | via SFML image | | memory | Materials |

Other one-off generated textures: lens-flare sprite (1024² R16F, `gen/lensflare`), star sprite (64² R16F, `gen/starbg`; the result is unused because `starbg.jsl`'s sampling branch is `#if 0`), planet rings (1024×1 R32F, `gen/planetring`), metal detail (512², `filter_rust`), metal plating chain (1024²), SMAA area/search LUTs loaded from `resource/texture/*.bin`. Sibling catalogers own the SDFMesh field / gradient / occlusion bakes (`gen/field*.jsl`, `Texture3D`) and `Mesh_ComputeOcclusion` (`compute/occlusion.jsl`, row bands via `Renderer_DrawFSQPart`).

Rough VRAM per star system: three RGBA32F 1024² cubes with mips (nebula, blurred, IR) come to about **400 MB**. Each planet surface (RGBA8 2048² with mips) is about **134 MB**.

### 2.8 Mesh / Model representation and upload

| Type | File | Representation |
|---|---|---|
| `Vertex` | `LTE/Vertex.h` | `V3 p, V3 n, float u, float v` (32 B). There are no tangents and no vertex colour. **`u` is overloaded as baked ambient occlusion** (`Mesh_SetOcclusion` sets u; materials multiply by `uv.x`). Starfield and particle code stuff colour into `n`. |
| `MeshT : GeometryT` | `LTE/Mesh.{h,cpp}` | `Vector<Vertex>`, `Vector<uint>`, lazily created VBO/IBO, `short version` / `bufferVersion`. Many CPU operations: normals, smoothing, share/unshare, decomposition, PCA, edge distance, ray intersection, transforms. **Only some mutators bump `version`.** `SetU`/`SetV` (and others **(unverified which)**) do not, so editing an already-uploaded mesh may not re-upload. `Clear()` drops the VBO/IBO handles without deleting them (leak). |
| `GeometryT` | `LTE/Geometry.h` | Abstract: Draw, GetBound, GetCollisionMesh, GetVersion, Intersects, Sample. |
| `RenderableT` | `LTE/Renderable.{h,cpp}` | Abstract: `Render(DrawState*)`, bound, collision mesh, hash, version, intersects, sample. `Renderable_Union(a, b)`. |
| `ModelT : RenderableT` | `LTE/Model.{h,cpp}` | List of `(Geometry, ShaderInstance, collidable)`. `Render` routes each piece through the current RenderStyle. The cached bound is keyed by the sum of geometry versions. |
| Object -> draw | `Component/Drawable.cpp` (world-model cataloger) | `RenderStyle_Get()->SetTransform(obj->GetTransform())`, then `renderable()->Render(state)`. |

No instancing, batching, sorting by material, or LOD system (beyond the unused Imposter). Every visible object costs at least one draw call per pass it takes part in (prepass + G-buffer for opaques), with a full uniform re-upload each time.

---

## 3. File inventory

### 3.1 Engine (`src/liblt/LTE/`)

| File | Purpose | Status |
|---|---|---|
| `GL.h` (1064) | EasyGL: typed inline wrappers over GL calls, plus `GLU` helpers. `DEBUG_GL_ERRORS` only in `BUILD_STRICT`. | complete (legacy API surface, includes `glBegin`) |
| `GLEnum.h` | Typed enums: blend, buffers, capabilities, texture formats (with Size/PixelFormat/DataFormat helpers), etc. | complete |
| `GLType.h` | `ExplicitTypedef` handles (`GL_Buffer`, `GL_Texture`, …) | complete |
| `Renderer.{h,cpp}` | Global state stacks, FBO cache, matrices, draw primitives, mesh upload | complete; legacy |
| `Shader.{h,cpp}` | JSL preprocessor, shader/program caches, uniform setters, hot reload | complete; `getchar()` on error |
| `ShaderInstance.{h,cpp}` | Material instance: lazy uniform map plus render-state switches | complete apart from the `Clone()` infinite loop; state caching disabled |
| `DrawState.{h,cpp}` | Per-render buffers and lists plus the global named uniform blackboard | complete |
| `RenderPass.{h,cpp}` | Pass base: profiler frame plus per-pass settings toggle | complete |
| `RenderPasses.{h,cpp}` | `RenderPassPost` (generic full-screen post filter), `Aberration`, `Tonemap`, `PostFilter` factories. Declarations for the LTE passes. | complete |
| `RenderPass/Bloom.cpp` | Threshold, separable gaussian at 1/4 res, composite | complete; used |
| `RenderPass/BloomLight.cpp` | Single-pass 2D luminance-adaptive blur bloom | complete; unused |
| `RenderPass/Composite.cpp` | Pass list | complete; unused by scripts |
| `RenderPass/CustomFilter.cpp` | Script-implemented filter pass | complete; used (Observatory) |
| `RenderPass/MotionBlur.cpp` | Speed-based radial blur (needs `camVelocity`) | complete; disabled in Camera |
| `RenderPass/RadialBlur.cpp` | Radial blur around a point | complete; unused (commented in model.lts) |
| `RenderStyle.{h,cpp}` | RenderStyle interface plus global stack | complete |
| `Renderable.{h,cpp}` | Renderable interface plus Union | complete |
| `Texture2D.{h,cpp}` | 2D textures: create, load (SFML), RT bind, generate-from-shader, atlas, screen capture, save | complete. `Texture_Atlas` is declared with `Vector<Texture2D*>` but defined with `Vector<Texture2D>` (the declared one has no definition). `SaveTo(flip)` uses the format's bpp on an RGBA8 buffer (wrong for float formats). |
| `Texture3D.{h,cpp}` | 3D textures (used by SDFMesh) | complete |
| `CubeMap.{h,cpp}` | Cube textures: generate-from-shader, get/set face data, serialization, save PNG per face | complete |
| `Mesh.{h,cpp}` | CPU mesh plus lazy GPU buffers | mostly complete; version bump gaps; `Clear()` leak |
| `Model.{h,cpp}` | Geometry + material list | complete |
| `Font.{h,cpp}` | FreeType + GPU SDF glyph atlas + text drawing | works; no atlas overflow handling; hard-coded `resource/font/` |
| `Color.{h,cpp}` | `Color` (V3F) plus HSL, desaturate, luminance, wavelength->RGB | complete |
| `ParticleSystem.{h,cpp}` | CPU particles, CPU-built billboard vertices | complete; slow at scale |
| `Viewport.{h,cpp}` | Viewport stack, ortho matrices, NDC transforms | complete |
| `View.h` | Camera view: double-precision frustum planes, projection, rays | complete |
| `Vertex.h` | Vertex struct | complete |
| `ScriptAPI/{Texture2D,Renderer,ShaderInstance,Renderable,Mesh,Model}.cpp` | Script bindings (§5) | complete |

### 3.2 Game side (`src/liblt/Game/`)

| File | Purpose | Status |
|---|---|---|
| `RenderPasses.h` | Declarations of the game passes | complete |
| `RenderPass/Camera.cpp` | Camera pass: view setup, zone fog, interior begin/end, hard-coded sub-pass list | complete; core |
| `RenderPass/Clear.cpp` | Clear primary + small buffers (and `ClearDepth`) | complete |
| `RenderPass/Visibility.cpp` | Recursive distance + frustum culling, light gathering | complete |
| `RenderPass/DepthPrepass.cpp` | Linear-depth R32F prepass using the materials' PREPASS path | works; no early-Z benefit; unused `depthprepass.jsl` instance |
| `RenderPass/GBuffer.cpp` | Opaque MRT pass | complete |
| `RenderPass/GlobalLighting.cpp` | IBL / sun full-screen pass into C2 | complete |
| `RenderPass/LocalLighting.cpp` | Batched point lights plus composite / fog / background | complete; capped at 16 lights |
| `RenderPass/Blended.cpp` | Forward alpha pass | complete |
| `RenderPass/Particles.cpp` | Draws the container's particle system | complete |
| `RenderPass/LensFlares.cpp` | Flare sprites, dirt composite, GPU occlusion with CPU readback | complete; per-frame sync stall |
| `RenderPass/SMAA.cpp` | 3-pass SMAA (iryoku reference shader) | complete |
| `RenderPass/SSAO.cpp` | Hemisphere SSAO | **broken / dead**: the composite multiplies by `smallColor[0]` instead of the SSAO result and writes into the buffer it reads (C2). Noise texture is hard-coded 1024×768. Disabled in Camera. |
| `RenderPass/DustClouds.cpp` | 4 camera-following volumetric dust shells (fogDensity-gated) | complete-ish; disabled |
| `Graphics/RenderStyles.{h,cpp}` | Default opaque / blended render style | complete |
| `Graphics/Generators.{h,cpp}` + `Generator/*.cpp` | GPU texture and cubemap generators (§2.7) | complete. Nebula has `#if 0` normalize and a `TODO Permute` stub. |
| `Graphics/Effects.{h,cpp}` | Particle and explosion spawn helpers | complete (gameplay-adjacent) |
| `Renderables.h`, `Renderable/Asteroid.cpp`, `Ice.cpp` | SDF-meshed rock / ice models | complete. Only **3 unique models**, chosen by `seed % 3`, generated with the non-seeded `Rand()`. |
| `Renderable/Imposter.cpp` | 6-view albedo/normal impostor bake plus LOD switch | **dead / buggy**: never used (commented in Asteroid); stray `args.source->Render(&state)` before the FBO is set up; "TODO: Valid depth buffer" |
| `Renderable/Starfield.cpp` | Skybox box (envMap) plus N star quads at 60 km | complete |
| `Materials.{h,cpp}` | Material singletons (§2.4) | complete |
| `ShadingModels.{h,cpp}` | ShaderInstance factories (§2.4) | complete; FlatColor's shader is broken |
| `Light.{h,cpp}` | Point-light object (colour, radius, flare, visibility) plus `Object_Light` | complete |
| `Particles.{h,cpp}` | Particle shader instances | complete; `particle_radialtextured` is compiled but has no instance |
| `Beam.{h,cpp}` | Beam weapon object: gameplay (raycast, damage, sound) plus a billboard renderable with a shared global ShaderInstance | complete. Mostly gameplay; only `RenderComponent` is rendering. |

---

## 4. Shader catalog

"Used by" lists files that reference the path. **UNUSED** means no reference found in `src/liblt`, `src/launch` or `resource/script`. The generic `RenderPass_PostFilter(path)` and `Shader_Create` could load any shader from a script, but scripts only reference the ones listed.

### 4.1 Common includes (`common/`)

| File | Contents | # includers |
|---|---|---|
| `global.jsl` | GL_EXT_gpu_shader4 / HIGHQ, attribute/varying macros, `saturate`, near/far (0.05 / 1e6), gamma 2.2 helpers | via frag/vert (all) |
| `vert.jsl` | Matrix uniforms, attributes, `VS_PROLOGUE`, varyings, `LogDepth` | 22 |
| `frag.jsl` | MRT outputs, `RETURN`, material ids, normal encode/decode, `output*` helpers, `EARLY_Z`, `PREPASS` | 114 |
| `math.jsl` | avg, pow2..8, gain, emix, contrast, ortho, … | 96 |
| `noise.jsl` | hash noise, cellular (`cnoise`/`fcnoise`/`frcnoise`), value, simplex-ish fBm (`fsnoise`) | 56 |
| `color.jsl` | lum, HSL<->RGB, oversaturate | 33 |
| `lighting.jsl` | env / IR uniforms, `cookTorrance`, `getMetalPBR`, fog | 30 |
| `texturing.jsl` | `texLod`, triplanar sampling, triplanar bump | 14 |
| `ui.jsl` | UI uniforms (frame, size, hover, opacity) | 13 |
| `cube.jsl` | `GetCubePosition` for cubemap generation | 7 |
| `scattering.jsl` | Atmospheric scattering (planet radius 50 km, 8 samples) | 7 |
| `smaa.jsl` (1044) | Jimenez et al. SMAA reference implementation | 6 |
| `fdm.jsl` | Frequency-dependent multi-scale texture sampling | 5 |
| `deferred.jsl` | Depth-buffer world-position reconstruction from `worldRay` | 4 |
| `bezier.jsl` | 3–5 point Bezier | 4 |
| `quat.jsl` | Quaternion rotate | 3 |
| `raytracing.jsl` | Ray-sphere | 3 |
| `softparticle.jsl` | Depth difference for soft edges | 3 |
| `field.jsl` | GLSL SDF primitives and combinators (box, capsule, torus, smooth union, hull…) | 1 |
| `blend.jsl` | screen / overlay | 1 |
| `atlas.jsl` | atlas UV helper | **0 (UNUSED)** |

### 4.2 Vertex shaders (`vertex/`)

| Shader | Purpose | Used by |
|---|---|---|
| `identity.jsl` | Pass-through NDC quad (FSQ, generators, post) | many |
| `npm.jsl` | Standard mesh VS: WVP, world normal, object scale / origin, log depth | materials, planet, prepass, Zone, Shield, Wormhole, WarpRail/Node, UI DrawRenderable |
| `worldray.jsl` | FSQ plus world-space view ray (for depth reconstruction) | Global/LocalLighting, SSAO, DustClouds |
| `skybox.jsl` | Box at the far plane, z = w | Skybox, Starfield |
| `particle.jsl` | CPU particle billboard expansion plus fade | Particles |
| `billboard.jsl` | Camera-facing billboard | Pulse |
| `billboard_axis.jsl` | Axis-locked billboard (beams, trails) | Beam, Pulse, Rail, Thruster, TransferUnit, Colony |
| `billboard_axis_wrapped.jsl` | Axis billboard, toroidally wrapped around the camera (1024 u) | DustFlecks |
| `billboard_soft.jsl` | Billboard with z-offset toward the camera | Explosion |
| `trail.jsl` | Ribbon trail expansion | Trail |
| `widget.jsl` | UI quads with 4 generic vec4 attributes | UI glyphs, Font |
| `widgetTexture.jsl` | UI textured quad | UI WidgetRenderer, Rendered |
| `smaa_1/2/3.jsl` | SMAA VS stages | SMAA |
| `default.jsl` | basic mesh VS | **UNUSED** |
| `imposter.jsl` | 3-axis impostor billboard | **UNUSED** (pairs with imposter2) |
| `occlude.jsl` | Flare occlusion in the VS | **UNUSED** (superseded by compute/lensflare_visibility) |
| `pc.jsl` | position + colour-in-normal | **UNUSED** |
| `screenproject.jsl` | Screen-projected, depth-tested sprite | **UNUSED** |
| `thruster_glare.jsl` | Thruster glare billboard | **UNUSED** |
| `ui.jsl` | Older UI VS | **UNUSED** |

### 4.3 Materials / deferred lighting / scene

| Shader | Purpose | Used by |
|---|---|---|
| `material/lambert.jsl` | FDM-textured rock (COOKT) | ShadingModel_Lambert |
| `material/metal.jsl` | Procedural triplanar plating (COOKT) | ShadingModel_Metal |
| `material/fresnel.jsl` | Ice (ICE id) | ShadingModel_Fresnel |
| `material/debug.jsl` | Adaptive grid debug | ShadingModel_Debug |
| `material/water.jsl` | Forward water | ShadingModel_Water |
| `material/lodfade.jsl` | Zone far-LOD env fade | Object/Zone.cpp. **Effectively invisible**: `alpha *= 0.0`. |
| `material/mineral.jsl` | Atlas triplanar env-lit mineral | **UNUSED**. It calls `getBumpNormal`/`sampleTriplanarAtlas`, which no common include defines, so it would not compile. |
| `light/global.jsl` | IBL / sun per material id | GlobalLighting |
| `light/point.jsl` | 16-light batch | LocalLighting |
| `light/composite.jsl` | albedo×light, fog, env background, gamma | LocalLighting |
| `depthprepass.jsl` | Output linear depth | DepthPrepass (compiled; instance never drawn) |
| `skybox.jsl` | envMap skybox into the G-buffer | ShadingModel_Skybox, Starfield |
| `starbg.jsl` | Star quads (analytic falloff) | Starfield |
| `solidcolor.jsl` | Flat colour, NOSHADE | ShadingModel_FlatColor. **Syntax error**; no callers. |
| `planet.jsl` | Planet surface from the height/colour/cloud cube, ocean spec, self-shadow march, scattering | Item/PlanetType |
| `atmosphere.jsl` | Additive atmosphere shell | Item/PlanetType |
| `planetring.jsl` | Rings with planet shadow and specular | Item/PlanetType |
| `imposter1.jsl` | Impostor from baked albedo/normal | Imposter (dead code path) |
| `imposter2.jsl` | 3-axis blended impostor | **UNUSED** |
| `terrain.jsl` | Detail-mapped terrain | **UNUSED**. Also calls the undefined `getBumpNormal`, so it would not compile. |
| `hologram.jsl` | Edge-glow hologram of a renderable | UI/WidgetRenderer/DrawRenderable |
| `tree.jsl` | Scattering-tinted billboard tree | Object/Colony |
| `default.jsl` | Debug UV output | **UNUSED** |
| `vertexcolor.jsl` | color+glow | **UNUSED** |
| `gate.jsl` | Animated gate surface | **UNUSED** |

### 4.4 Effects / particles (forward, mostly additive)

| Shader | Purpose | Used by |
|---|---|---|
| `beam.jsl` | Pulsing beam | Game/Beam |
| `particle_radial.jsl` | Radial-falloff particle | Particle_Fire / Firefly |
| `particle_radialtextured.jsl` | Rotated textured particle | Particles.cpp (shader compiled; no instance uses it) |
| `explosion.jsl` | Explosion sprite | Object/Explosion |
| `shield_explosion.jsl` | Noisy shield burst | Object/Explosion |
| `shield.jsl` | Shield hit ripples (array of hits) | Object/Shield |
| `pulse_head.jsl` / `pulse_tail.jsl` | Projectile head / tail | Object/Pulse |
| `rail.jsl` | Rail glow | Object/Rail |
| `warprail.jsl` | Kali-fractal warp rail | Object/WarpRail |
| `wormhole.jsl` | Kali-fractal wormhole | Object/Wormhole, WarpNode |
| `trail.jsl` | Ship trail | Object/Trail |
| `thruster_trail.jsl` | Thruster plume | Object/Thruster |
| `transferbeam.jsl` | Cargo transfer beam | Object/TransferUnit |
| `dustfleck.jsl` | Space dust streaks | Object/DustFlecks |
| `dustclouds.jsl` | Volumetric dust shells | DustClouds pass (disabled) |
| `lensflare.jsl` | Flare sprite | LensFlares |

### 4.5 Post-processing (`post/`)

| Shader | Purpose | Used by |
|---|---|---|
| `tonemap.jsl` | `1-exp(-1.5·c^1.25)` | RenderPass_Tonemap (Camera) |
| `colorgrade1D.jsl` | Per-channel procedural curves with a screen-space gradient between two curve sets | Camera |
| `dither.jsl` | ±1/256 noise | scripts (all game apps) |
| `bloom_composite.jsl` | Bright/dark adaptive bloom mix | Bloom, BloomLight |
| `glowthresh.jsl` | 2×2 box downsample (no actual threshold) | Bloom, BloomLight |
| `blur.jsl` | 1D gaussian | Bloom; Texture/Filters.lts |
| `blurlight.jsl` | 2D luminance-adaptive blur | BloomLight |
| `lensflare_composite.jsl` | scene + flares + dirt | LensFlares |
| `motionblur.jsl` | Radial speed blur | MotionBlur (disabled) |
| `radialblur.jsl` | Radial blur | RadialBlur (unused) |
| `aberration.jsl` | Chromatic aberration | RenderPass_Aberration (unused) |
| `ssao.jsl` | SSAO | SSAO (broken / disabled) |
| `multiply.jsl` | a·b | SSAO; Filters.lts |
| `add.jsl`, `levels.jsl`, `linear.jsl`, `power.jsl`, `saturate.jsl`, `vignette.jsl`, `expmap.jsl`, `edgedetect.jsl` (Sobel), `median.jsl`, `circleminmax.jsl`, `min.jsl`, `max.jsl`, `samplecubic.jsl` (bicubic), `colorgradebezier.jsl` | Image-op library | `resource/script/Texture/Filters.lts` (Observatory, ImageEditor, etc.) |
| `colorbalance.jsl`, `colorgrade3D.jsl` (3D LUT), `contrast.jsl`, `distancefog.jsl` (mostly `#if 0` / `if (false…)`), `identity.jsl`, `lofi.jsl` (scanlines), `screen.jsl` | various | **UNUSED** |

### 4.6 Procedural generation (`gen/`, `filter_*`, `cubemap/`)

| Shader | Purpose | Used by |
|---|---|---|
| `gen/planet.jsl` | Planet height / colour / cloud cubemap (Kali fractal + fBm) | Generator_PlanetSurface |
| `gen/nebula.jsl` | Volumetric-looking nebula skybox | Generator_Nebula |
| `gen/planetskybox.jsl` | Sky as seen from the planet surface | Generator_PlanetSkybox |
| `gen/planetring.jsl` | 1D ring density | PlanetType |
| `gen/plating.jsl` | Worley-based hull plating height + normal (MRT) | Material_Metal |
| `gen/rock.jsl` | Fractal rock albedo | Material_Grass |
| `gen/normalmap_lum.jsl` | Height (luminance) -> normal map | Generator_NormalMap |
| `gen/lensflare.jsl` | Flare sprite | LensFlares |
| `gen/starbg.jsl` | Star sprite | Starfield (result unused) |
| `gen/field.jsl`, `fieldcopy`, `fieldgradient`, `fieldocclusion` | SDF volume sampling / gradient / AO for SDFMesh | LTE/SDFMesh.cpp (other cataloger) |
| `filter_ao.jsl` | Heightmap AO | Material_Metal |
| `filter_dirt.jsl` | Grime multiply | Material_Metal |
| `filter_rust.jsl` | Tileable noise via **torus mapping** | ShadingModel_Metal detail map |
| `cubemap/blur.jsl` | Stochastic cube blur | Generator_Blur |
| `cubemap/irmap.jsl` | Cone-convolved irradiance / specular mips | Generator_IRMap |
| `cubemap/multiply.jsl` | Radiance normalize | Nebula (`#if 0`, **effectively unused**) |
| `cube_permute.jsl` | Combine cube with a rotated copy | Nebula (commented, **unused**) |
| `gen/normalmap.jsl` | Height (R channel) -> normal | **UNUSED** |
| `gen/noise.jsl`, `gen/noise_worley.jsl` | Noise textures | **UNUSED** |
| `gen/dustparticle.jsl`, `gen/explosion.jsl` | Sprite generators | **UNUSED** |
| `gen/sound.jsl` | **GPU audio synthesis** (sine/saw/tri harmonics into a texture) | **UNUSED** (curiosity) |

### 4.7 GPU "compute" via fragment shaders (`compute/`)

| Shader | Purpose | Used by |
|---|---|---|
| `compute/occlusion.jsl` | Per-vertex AO: every vertex against every surfel (area-based disk occlusion), O(V·S) | LTE/PlateMesh.cpp `Mesh_ComputeOcclusion` |
| `compute/sdffont.jsl` | Brute-force glyph distance field | Font |
| `compute/lensflare_visibility.jsl` | Per-flare depth test -> visibility texel | LensFlares |

### 4.8 SMAA / UI

| Shader | Purpose | Used by |
|---|---|---|
| `smaa_1/2/3.jsl` (frag) | Edge detection, blend weights, neighbourhood blend | SMAA |
| `ui/text.jsl` | SDF text (bicubic, halo / glow modes) | Font |
| `ui/texture.jsl`, `ui/textureadditive.jsl` | Textured quads (present, images) | Rendered, WidgetRenderer |
| `ui/panel.jsl`, `ui/radialpanel.jsl` | SDF panels with shadows | WidgetRenderer |
| `ui/arc, box, circle, gradient, grid, line, linefade, rect, ring, triangle` | Analytic SDF UI glyphs | UI/Glyph/* |
| `ui/basic.jsl`, `ui/none.jsl` | Layer compositors (CRT-ish grade / plain tonemap+dither) | UI/Compositor |
| `ui/composite.jsl` | Over-composite of a UI layer | UI/Interface |

Unused total: about 31 files (1 common, 8 vertex, about 22 fragment). This counts the "compiled but never drawn" ones (`depthprepass`, `particle_radialtextured`) and the "only in `#if 0` / commented code" ones (`cubemap/multiply`, `cube_permute`). `imposter1` is referenced only from the dead Imposter path, and `lodfade` is referenced but renders nothing.

---

## 5. Script exposure

Every C++ `DefineFunction(X)` and every `FreeFunction` / `VoidFreeFunction` registers X in the global function registry that LTSL resolves names against (`LTE/DeclareFunction.h`; details are in the scripting cataloger's doc). For rendering, scripts can use the following.

| Feature | Script names | Bound in |
|---|---|---|
| Pipeline composition | `RenderPass_Clear`, `_ClearDepth`, `_Camera`, `_Visibility`, `_DepthPrepass`, `_GBuffer`, `_GlobalLighting`, `_LocalLighting`, `_Blended`, `_Particles`, `_LensFlares`, `_SMAA`, `_SSAO`, `_DustClouds` | `Game/RenderPass/*.cpp` |
| | `RenderPass_Bloom`, `_BloomLight`, `_Tonemap`, `_PostFilter "path"`, `_Aberration`, `_RadialBlur`, `_MotionBlur`, `_Composite`, `_CustomFilter <scriptObj>` | `LTE/RenderPasses.cpp`, `LTE/RenderPass/*.cpp` |
| | `Widget_Rendered passes` (owns buffers, presents), `RenderPass_Interface` | UI (other cataloger) |
| Shaders | `Shader_Create vs fs`, `Shader_RecompileAll`, `ShaderInstance_Create`, `.Clone`, `.SetFloat/SetInt/SetVec2/3/4/SetTexture2D` (all aliased as `.Set`) | `LTE/Shader.cpp`, `LTE/ShaderInstance.cpp`, `LTE/ScriptAPI/ShaderInstance.cpp` |
| Textures | `Texture2D_Create w h` (RGBA8), `Texture2D_CreateHDR` (RGBA32F), `.BeginDrawTo` / `.EndDrawTo` (render to texture with identity transforms and an ortho viewport), `DrawClear color alpha`, `.GenerateFromShader shader / instance`, `.GenerateMipmap`, `.GetWidth/GetHeight`, `.SaveTo path`, `Texture_LoadFrom location`, `Texture_ScreenCapture` | `LTE/ScriptAPI/Texture2D.cpp`, `LTE/Texture2D.cpp` |
| Image-op library (script) | `Texture/Filters.lts`: Add, Blur(H/V), CircleMinMax, ColorGrade(Bezier), EdgeDetect, ExpMap, Gain, Levels, Linear / Invert, Median, Max, Min, Multiply, Power, SampleCubic, Saturate, Vignette (`…Out` variants write into a caller texture). Most allocate a new RGBA32F texture per call. | resource/script |
| Models / materials | `Model_Create`, `.Add geometry shaderInstance`, `Mesh_Create`, `.Center`, `.SetOcclusion`, `Renderable_GetBound`, `Object_SetRenderable`, `Material_Metal/Rock/RockShiny/Ice/Grass/Water/Debug`, `Renderable_Asteroid/Ice/Starfield/Imposter` | `LTE/ScriptAPI/{Model,Mesh,Renderable}.cpp`, `Game/Materials.cpp`, `Game/Renderable/*`, `Component/Drawable.cpp` |
| Lights / particles | `Object_Light`, `ParticleSystem_Create/Get/Push/Pop/Add`, `Particle_Fire`, `Particle_Firefly` | `Game/Light.cpp`, `LTE/ParticleSystem.cpp`, `Game/Particles.cpp` |
| DrawState blackboard | `DrawState_Push name data`, `DrawState_Pop`, `DrawState_Clear` | `LTE/DrawState.cpp` |
| Fonts / colour | `Font_Get path`, `Color_FromWavelength`, `Desaturate`, `Luminance`, `ToHSL`, `ToRGB` | `LTE/Font.cpp`, `LTE/Color.cpp` |
| Stats | `Renderer_GetDrawCallCount`, `Renderer_GetPolyCount` | `LTE/ScriptAPI/Renderer.cpp` |
| Generators | `Generator_Blur`, `_IRMap`, `_Nebula` are registered, but they take and return `Generic<>` thunks. No script use was found, and practical script usability is **unverified**. | `Game/Graphics/Generator/*` |
| 2D draw primitives | `Draw`, `DrawText`, `DrawTextGlow`, icons, glyphs | UI ScriptAPI (`UI/ScriptAPI/Glyph.cpp`, `Icon.cpp`), other cataloger |

What scripts **cannot** do: change the passes inside `RenderPass_Camera`, set cube-map, matrix or float-array uniforms on instances (only float, int, vec, Texture2D), add render-state switches to instances, create cubemaps, or write custom vertex formats.

---

## 6. Known issues, quirks and tech debt

| # | Area | Issue | Severity |
|---|---|---|---|
| 1 | API | Legacy GL 2.1 + GLSL 1.20: `attribute`/`varying`, `gl_FragData`, `texture2D/Cube`, `texture2DLod` in fragment shaders, `GL_EXT_gpu_shader4`, **client-side vertex arrays** (`DrawQuad`, `DrawVertices`, particles, text), `glBegin/End` (`DrawQuadOutline`), `glColor` / fixed-function fallback (`Shader_UseFixedFunction`), no VAOs. A **compatibility profile is required** (works on Mesa; would fail on macOS core or GLES/WebGL). | high (portability) |
| 2 | Sync | `glFinish` after every generation job; LensFlares does a **synchronous `glGetTexImage` every frame**; `Profiler_Flush` calls `glFinish` after every pass when profiling is active; IRMap copies whole cube levels GPU->CPU->GPU. | high (perf) |
| 3 | Hitches | Generators are lazy `Generic`s first evaluated **mid-frame** (IRMap in the Camera pass, nebula / planet if not disk-cached, font glyph SDFs on first use of each character). The IRMap is regenerated **every launch** (1024 samples × all mips). | high (UX) |
| 4 | Per-draw cost | ShaderInstance state caching disabled: every draw re-binds the program, re-pushes states and re-uploads all uniforms (lazy thunks re-evaluated). No instancing or batching; opaques are drawn twice (prepass + G-buffer). | medium |
| 5 | Depth prepass | HW depth is cleared after the prepass, and materials then do a shader-side `EARLY_Z` `discard`, which *disables* HW early-Z. The prepass mainly exists to supply linear depth to the lighting passes. | medium (perf) |
| 6 | Bugs | `ShaderInstance::Clone` infinite loop (instances with render states); `solidcolor.jsl` syntax error; SSAO composite wrong and feedback-looped; Imposter stray render; `Mesh::SetU/SetV` (and possibly other mutators) don't bump `version`; `Mesh::Clear` leaks GL buffers; `Texture_Atlas` declaration/definition mismatch; `Texture2D::SaveTo(flip=true)` stride wrong for non-RGBA8; `DrawState` links `normalBuffer` to the depth buffer; `CubeMap::GenerateFromShader` clobbers the global view/proj. | medium |
| 7 | Failure mode | A shader compile error calls **`getchar()`** (blocks a GUI app waiting on stdin). Missing uniforms only warn. Font load failure leaves `face` uninitialized. | medium |
| 8 | Fragile coupling | The `prepass` uniform is reset per instance but is per-program state; it relies on draw order. Texture units are per-program round-robin mod 16. The FBO cache is keyed by hash only and flushes all FBOs past 128. | medium |
| 9 | Gamma / HDR | Lighting composite converts to **gamma before** bloom, tonemap and colour grade, so bloom and tonemap operate on gamma-encoded HDR. Albedo and env samples go through `toLinear` (pow 2.2) per sample instead of using sRGB textures. | low (quality) |
| 10 | Log depth | Log depth is written **per vertex** (`gl_Position.z = LogDepth(...)`), so large triangles near the camera can clip or interpolate incorrectly. There is no `gl_FragDepth` path. | low |
| 11 | Lights | At most 16 dynamic lights per frame, evaluated full-screen for every pixel (no tiling or volumes). Point lights only. No shadows. | medium (design) |
| 12 | Hard-coded sizes / paths | Window 1920×1080 with vsync off (`src/launch/launch.cpp`); planet cube 2048; nebula / skybox / blur cubes 1024; IRMap 1024 samples; SSAO noise 1024×768; font 64 px in a 1024 atlas; flare 1024; metal 1024 / detail 512; impostor 512×3072; `resource/font/` prefix; shader root via `Location_Shader`; cache `./cache/cache/`. The in-camera pass list is hard-coded in C++. | medium |
| 13 | Disk cache | `DiskCached` keys have no versioning (stale results after shader changes); about 100 MB per cube file at level 0; no eviction. VRAM is about 400 MB per system for the three RGBA32F cubes with mips. | medium |
| 14 | Content variety | Only 3 asteroid and 3 ice meshes, picked with the unseeded `Rand()`, so they are not reproducible across runs. | low |
| 15 | Dead weight | About 31 unused or effectively unused shaders (§4). Disabled passes: SSAO, DustClouds, MotionBlur. Unused passes: BloomLight, RadialBlur, Aberration, Composite, Imposter. `#if 0` blocks throughout the materials. | low |
| 16 | GPU timeouts | The generation job splitting assumes Windows-style TDR. Very heavy shaders (`gen/nebula`: 128×24 fractal iterations per texel; `compute/sdffont`: about 16.6k taps; `compute/occlusion`: O(V·S)) are still risky on slow or integrated GPUs, even with the 2× growth cap. | medium |
| 17 | Includes | The JSL preprocessor has no include-once handling and no `#line` mapping, so compile errors report flattened line numbers (the numbered source is printed to the log). | low |

---

## 7. Dependencies

| Depends on | For |
|---|---|
| GLEW (static, bundled `Glew/GL/glew.h`), OpenGL 2.1 + FBO / float-texture / MRT / anisotropy / gpu_shader4 / texture LOD extensions | everything |
| SFML 2.5 (`sf::Image`, `sf::RenderWindow` via `LTE/Window`) | texture load and save, GL context |
| FreeType (bundled `FreeType/`) | Font |
| SMAA reference shader plus `ThirdParty/SMAA_AreaTex.h` / `SMAA_SearchTex.h` sizes and `resource/texture/SMAA_*.bin` | SMAA |
| LTE core (other cataloger): math (`Matrix`, `V3`, `Transform` with double pos, `Bound`), `RNG`, `Location`, `Serializer`, `Generic` / `Function` / `Cached`, `Settings`, `Profiler` / `StackFrame`, `Vector` / `Map` / `Pool`, `Type` reflection (generic vertex formats), `Meshes`, `SDF` / `SDFMesh`, `PlateMesh` | geometry, generators, caching |
| Scripting runtime (other cataloger): `DeclareFunction` registry, `ScriptFunction` (CustomFilter), `ScriptType` | script exposure |
| Game world (other cataloger): `ObjectT::OnDraw`, `Component_Drawable`, `Component_Cullable` / `BoundingBox`, Interior iteration, `Object/System.cpp` (envMap / irMap / color curves / starfield), `Item/PlanetType.cpp`, Camera, Zone fog | pass content and inputs |
| UI (other cataloger): `Widget_Rendered` (buffer allocation and present), `WidgetRenderer`, glyph shaders, `RenderPass_Interface`, compositors | pipeline host |
| Assets: `resource/shader/**`, `resource/texture/{rock,ice,water_normals,lensdirt}.jpg`, `resource/font/**` | |

---

## 8. Assessment

### 8a. Toward a playable game

**Is the renderer production-capable?** For a single-platform PC build on a desktop GL compatibility driver, it is *usable*: the full pipeline runs on Mesa and produces the intended look. It is not production-grade, for these reasons:

| Gap | What it would take |
|---|---|
| Startup and first-frame hitches (IRMap every launch, lazy mid-frame generation, glyph SDFs) | Disk-cache the IRMap as well; prewarm generators during a loading screen (`App/loading.lts` exists); add a version or hash to cache keys; pre-bake a glyph range at font load. |
| Per-frame sync stalls | Replace the LensFlares readback with a 1–2 frame delayed PBO / async read, or compute occlusion entirely on the GPU in the flare VS (`vertex/occlude.jsl` already does this; it is just unused). Drop `glFinish` outside generation. |
| Draw-call scaling | Re-enable ShaderInstance state caching (fix the TODO), sort by program, and instance repeated models (asteroids, ships of one type). Particles should move to a persistent VBO or GPU simulation. |
| Lighting limits | 16 lights and no shadows. For a space game, add at least a sun shadow (cascaded or per-object) and tiled or clustered point lights. Restore the commented-out direct sun term for COOKT materials. |
| Robustness | Remove `getchar()`; fall back to a magenta shader on failure; fix the Clone loop and `solidcolor.jsl`; guard the font atlas overflow and the FreeType failure; make window size and vsync settings rather than hard-coded values. |
| Gamma correctness | Move the gamma conversion after tonemap, use sRGB textures and framebuffer. |
| Portability | Required for macOS, consoles or Vulkan: a VAO/VBO-only draw path, GLSL 330+ (`in`/`out`, named outputs), removal of `glBegin` / fixed function. The `#if 1` switches in `global.jsl` show this was planned. |

Practical stance: keep it for a Linux/Windows-desktop prototype. Budget the first work on items 2, 3, 6 and 7 from §6. Leave shadows and many lights until gameplay needs them.

### 8b. Cross-mapping into a new engine: most valuable techniques

| Technique | Where | Self-containedness | Porting notes |
|---|---|---|---|
| **Procedural planet cubemaps** (Kali-style 4D fractal height/colour plus fBm clouds) and **planet surface shading** (height march for terrain shadows, 4-colour Bezier gradients, ocean specular, scattering) | `gen/planet.jsl`, `planet.jsl`, `common/{noise,math,cube,scattering}.jsl`, `Generator/PlanetSurface.cpp` | High. Pure functions of direction plus 4 uniforms. | Drop into any engine as a compute shader writing a cube array (`imageStore`). This removes the scissor-job hack. Consider generating at lower resolution plus detail noise to cut the 100 MB per planet. |
| **Nebula skybox generator** (emission plus 128-step absorption march over a fractal, quaternion-rotated domains, star glow) | `gen/nebula.jsl`, `Generator/Nebula.cpp`, `System.cpp` for parameter choice | High | Same as above. Very expensive, so bake offline or asynchronously and store as BC6H. Pairs well with the IR / blur generators. |
| **IBL chain**: blurred low-frequency env (`cubemap/blur`) plus a roughness-indexed cone-convolved mip chain (`cubemap/irmap`), sampled by `9·sqrt(roughness)` | `Generator/{Blur,IRMap}.cpp` | High | Equivalent to a modern split-sum prefilter (without the BRDF LUT). Replace it with GGX importance-sampled prefiltering in a compute shader. The idea maps 1:1. |
| **Per-system procedural colour grading** (random midpoint-displaced 1D curves per channel, blended across screen space) | `System.cpp::CreateColorCurve`, `post/colorgrade1D.jsl` | Very high | Easy to replicate as a generated 1D or 3D LUT. Strong "each system feels different" payoff for very little code. |
| **Camera-relative rendering with double-precision positions plus logarithmic depth** (near 0.05, far 1e6) | `Renderer.cpp` (`kCameraSpaceRendering`), `View.h`, `common/vert.jsl::LogDepth` | High | A standard large-world pattern. In a modern engine use reversed-Z float depth instead of log depth, or write log depth per fragment. |
| **GPU texture synthesis as "shader -> texture" jobs** with adaptive time-sliced dispatch | `Texture_Generate`, `CubeMap::GenerateFromShader` | High | The design is portable. The implementation (scissor + `glFinish`) should become compute dispatches with timestamps or fences. |
| **Metal plating material pipeline** (Worley plating -> AO filter -> grime -> torus-mapped tileable rust detail; triplanar FDM sampling) | `gen/plating.jsl`, `filter_{ao,dirt,rust}.jsl`, `material/metal.jsl`, `common/{fdm,texturing}.jsl` | Medium-high | Good for procedural ship hulls. The torus-mapping trick for seamless 2D noise is reusable on its own. |
| **SDF UI glyph set and SDF text** (analytic panels, rings, arcs, lines with AA; bicubic-sampled distance-field text with glow mode) | `ui/*.jsl`, `compute/sdffont.jsl`, `Font.cpp` | Medium | Shaders port directly. Replace the brute-force glyph SDF with msdfgen or a jump-flood pass. |
| **Lightweight deferred layout** (2 RGBA16F targets + R32F linear depth; spherical normal encode; material id in alpha selecting lighting branches) | `common/frag.jsl`, `light/*.jsl`, `RenderPass/*` | Medium | Fine as a reference, but a modern renderer would use octahedral normals, a proper BRDF and clustered lights. Main value: shows how few targets a stylized space renderer needs. |
| **Lens flares with GPU occlusion and lens dirt** | `RenderPass/LensFlares.cpp`, `gen/lensflare.jsl`, `compute/lensflare_visibility.jsl` | High | Port with GPU-only occlusion (no readback). |
| **Effect shaders** (beams, pulses, trails, thruster plumes, shields with hit ripples, Kali-fractal wormholes and warp rails) | §4.4 | High; each is about 20–50 lines | Mostly analytic alpha functions on billboard UVs. Trivial to port and a cheap source of visual style. |
| **Atmospheric scattering** (8-sample in/out scattering, planet radius normalized) | `common/scattering.jsl`, `atmosphere.jsl`, `gen/planetskybox.jsl` | Medium | Dated (O'Neil-style). A modern Bruneton or Hillaire LUT model is better, but this one is compact. |
| **Per-vertex AO bake on GPU** (surfel disk occlusion) | `compute/occlusion.jsl` (+ PlateMesh, other cataloger) | High | O(V·S); fine offline. A modern engine would bake to textures or use RTAO. |
| SMAA | `common/smaa.jsl` | n/a | Third-party; use the upstream SMAA or FXAA/TAA instead. |
| Not worth porting | `ShaderInstance` / `DrawState` blackboard design, the `RenderStyle` stack, the EasyGL wrapper, `ParticleSystem` | | They are tied to legacy GL and global state. Modern equivalents: material parameter blocks / UBOs, render-graph pass declarations, GPU particles. |

**Porting effort summary:**
- Shaders are GLSL 1.20 with a trivial include preprocessor. Converting them to GLSL 450 / HLSL / WGSL is mostly mechanical: `attribute/varying` to `in/out`, `gl_FragData` to named outputs, `texture2D/Cube` to `texture`, and uniforms into UBOs.
- The generators and post shaders are effectively pure functions of `uv` / direction plus uniforms, which makes them the easiest and most valuable parts to lift.
- The C++ render passes are small (40–200 lines each). They are easy to re-express as render-graph nodes, but they depend on the global Renderer / DrawState singletons. Rewrite them rather than port them.
