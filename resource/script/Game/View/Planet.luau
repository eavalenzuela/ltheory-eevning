--!strict
-- Planets and moons as things to look at, built the way the engine's
-- own planet is and the way EVE's are (docs/roadmap.md, "Bodies: how to
-- build them"): the lie of the land is drawn once into a cube map, and a
-- shader dresses and lights the globe from it; a shell around the globe
-- adds the glow of its air, if it has any.
--
-- Kinds so far: "temperate" (and "ocean", which is the same heights
-- with the sea higher), "barren" (a planet of bare rock) and "moon".

local Planet = {}

export type Kind = {
  generator: string,                  -- the shader that draws the cube map
  shader: string,                     -- the shader that lights the globe
  generate: { [string]: number },     -- settings of the generator
  settings: { [string]: number },     -- settings of the shader, by name
  colors: { [string]: { number } },   -- its colours, as they should look on a screen
  air: number,                        -- how thick the air is; 0 for none
  -- How strongly the air scatters red, green and blue (against the
  -- weights scattering.jsl gives each), and the colour of its glow.
  sky: { number },
  tint: { number },
}

-- Settings to use in place of a kind's own, by name: a number for one of
-- its 'generate' or 'settings', three for one of its 'colors'.
export type Tweaks = { [string]: number | { number } }

export type World = {
  kind: string,
  seed: number,
  body: Object,
  surface: ShaderInstance,
  air: ShaderInstance?,
  map: CubeMap,
}

-- The size of a face of the cube map, in pixels. (Six faces at 16-bit
-- float: about 50 MB at 1024.)
Planet.RESOLUTION = 1024

-- The shell of air stands this far out, in planet radii (scattering.jsl
-- assumes it).
local AIR = 1.025

local BLUE_SKY = { 5.6, 7.1, 39 }
-- Dust scatters every colour alike (these undo scattering.jsl's
-- weights); the haze takes its colour from the tint.
local DUST_SKY = { 12, 6.7, 15 }
local WHITE = { 1, 1, 1 }

Planet.kinds = {
  temperate = {
    generator = "gen/world_temperate.jsl", shader = "world.jsl", generate = {},
    settings = {
      seaLevel = 0.46,      -- heights under this are sea
      cloudCover = 0.36,    -- how much of the sky has cloud in it, 0 to 1
      iceLine = 0.86,       -- how far toward a pole the sea freezes (0 equator, 1 pole)
      relief = 0.045,       -- how strongly slopes catch the light
      cityLights = 1,       -- 0 for a world nobody lives on
    },
    colors = {}, air = 0.6, sky = BLUE_SKY, tint = WHITE,
  },
  ocean = {
    generator = "gen/world_temperate.jsl", shader = "world.jsl", generate = {},
    settings = { seaLevel = 0.58, cloudCover = 0.42, iceLine = 0.88, relief = 0.045, cityLights = 1 },
    colors = {}, air = 0.6, sky = BLUE_SKY, tint = WHITE,
  },
  barren = {
    generator = "gen/world_barren.jsl", shader = "world_rock.jsl",
    generate = {
      craters = 0.5,        -- how heavily cratered, 0 to 1
      plains = 0.55,        -- how much of it is dark plain, 0 to 1
      rifts = 1,            -- how much it is cut by canyons, 0 to 1
    },
    settings = {
      relief = 0.10,        -- (0.083 draws the ground as high as it is)
      frostLine = 0.84,     -- how far toward a pole frost begins; above 1, none
    },
    colors = { rockPale = { 0.66, 0.47, 0.33 }, rockDark = { 0.30, 0.19, 0.14 }, rockFresh = { 0.80, 0.66, 0.52 } },
    air = 0.10, sky = DUST_SKY, tint = { 1.0, 0.72, 0.48 },
  },
  moon = {
    generator = "gen/world_barren.jsl", shader = "world_rock.jsl",
    generate = { craters = 1.0, plains = 0.58, rifts = 0 },
    settings = { relief = 0.10, frostLine = 2 },
    colors = { rockPale = { 0.58, 0.57, 0.55 }, rockDark = { 0.24, 0.24, 0.25 }, rockFresh = { 0.86, 0.86, 0.84 } },
    air = 0, sky = BLUE_SKY, tint = WHITE,
  },
} :: { [string]: Kind }

local function vec(c: { number }): vector
  return vector.create(c[1], c[2], c[3])
end

-- A world of a kind. 'seed' is any whole number.
function Planet.New(kindId: string, seed: number, resolution: number?, tweaks: Tweaks?): World
  local kind = assert(Planet.kinds[kindId], `no kind of planet '{kindId}'`)
  local function number(name: string, value: number): number
    local tweak = tweaks and tweaks[name]
    return if type(tweak) == "number" then tweak else value
  end
  local function color(name: string, value: { number }): vector
    local tweak = tweaks and tweaks[name]
    return vec(if type(tweak) == "table" then tweak else value)
  end

  local generator = ShaderInstance_Create(Shader_Create("identity.jsl", kind.generator))
  ShaderInstance_SetFloat(generator, "seed", seed % 1000 + 0.137)
  for name, value in kind.generate do
    ShaderInstance_SetFloat(generator, name, number(name, value))
  end
  local map = CubeMap_CreateHDR(resolution or Planet.RESOLUTION)
  CubeMap_GenerateFromShaderInstance(map, generator)

  local surface = ShaderInstance_Create(Shader_Create("globe.jsl", kind.shader))
  ShaderInstance_SetCubeMap(surface, "planetMap", map)
  for name, value in kind.settings do
    ShaderInstance_SetFloat(surface, name, number(name, value))
  end
  for name, value in kind.colors do
    ShaderInstance_SetVec3(surface, name, color(name, value))
  end
  local model = Model_Create()
  local shaders = { surface }
  local air: ShaderInstance? = nil
  if kind.air > 0 then
    local made = ShaderInstance_Create(Shader_Create("npm.jsl", "atmosphere.jsl"))
    ShaderInstance_SetState(made, "BlendModeAdditive")
    table.insert(shaders, made)
    air = made
  end
  for _, shader in shaders do
    ShaderInstance_SetFloat(shader, "atmoDensity", number("atmoDensity", kind.air))
    ShaderInstance_SetVec3(shader, "atmoTint", color("atmoTint", kind.tint))
    ShaderInstance_SetVec3(shader, "wavelength", vec(kind.sky))
    ShaderInstance_SetFloat(shader, "whiteLight", 0)
    ShaderInstance_Link(shader)
  end
  Model_Add(model, Mesh_SetU(Mesh_BoxSphere(50, true), 1), surface)
  if air then
    local shell = Mesh_SetU(Mesh_ReverseWinding(Mesh_Scale(Mesh_BoxSphere(50, true), vector.create(AIR, AIR, AIR))), 1)
    Model_AddShell(model, shell, air)
  end
  local body = Object_Custom({})
  Object_SetRenderable(body, model)
  return { kind = kindId, seed = seed, body = body, surface = surface, air = air, map = map }
end

-- Change one of a world's shader settings (a name from its kind's
-- 'settings', or "atmoDensity", or "whiteLight": 1 lights it white
-- whatever colour the star is, for judging its own colours).
function Planet.Set(world: World, name: string, value: number)
  ShaderInstance_SetFloat(world.surface, name, value)
  if world.air and (name == "atmoDensity" or name == "whiteLight") then
    ShaderInstance_SetFloat(world.air, name, value)
  end
end

return Planet
