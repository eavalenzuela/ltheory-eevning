--!strict
-- Planets and moons as things to look at, built the way the engine's
-- own planet is and the way EVE's are (docs/roadmap.md, "Bodies: how to
-- build them"): what a world is like is drawn once into a cube map by
-- its kind's generator, and a shader dresses and lights the globe from
-- it; a shell around the globe adds the glow of its air, if it has any.
--
-- Kinds: "temperate" and "ocean" (the same heights with the sea
-- higher); "barren" (a planet of bare rock) and "moon"; "ice" and
-- "icemoon"; "lava"; "gas".

local Planet = {}

-- Colours are as they should look on a screen; the shaders turn them to
-- linear light.
type Colors = { [string]: { number } }

export type Kind = {
  generator: string,                  -- the shader that draws the cube map
  shader: string,                     -- the shader that lights the globe
  generate: { [string]: number },     -- settings of the generator
  settings: { [string]: number },     -- settings of the shader
  colors: Colors,
  -- Other colourings the kind comes in: each a set of colours to use in
  -- place of those above. Which one a world has follows from its seed.
  variants: { Colors }?,
  air: number,                        -- how thick the air is; 0 for none
  -- How strongly the air scatters red, green and blue (against the
  -- weights scattering.jsl gives each), and the colour of its glow.
  sky: { number },
  tint: { number },
  -- The colours of its rings, if worlds of this kind can have rings
  -- (two in five then do, by their seeds).
  rings: { pale: { number }, dark: { number } }?,
}

-- Settings to use in place of a kind's own, by name: a number for one of
-- its 'generate' or 'settings' (or for "atmoDensity"; "rings", 1 or 0, to
-- give it rings or not; "tilt", degrees), three for one of its 'colors'
-- (or for "atmoTint"). A name the kind does not have is
-- given to its shader all the same, or, if it starts "gen.", to its
-- generator: for trying a setting out before it is in the table.
export type Tweaks = { [string]: number | { number } }

export type World = {
  kind: string,
  seed: number,
  body: Object,
  surface: ShaderInstance,
  air: ShaderInstance?,
  ring: ShaderInstance?,
  map: CubeMap,
}

-- The size of a face of the cube map, in pixels. (Six faces at 16-bit
-- float: about 50 MB at 1024.)
Planet.RESOLUTION = 1024

-- The shell of air stands this far out, in planet radii (scattering.jsl
-- assumes it).
local AIR = 1.025

local BLUE_SKY = { 5.6, 7.1, 39 }
-- Dust and smoke scatter every colour alike (these undo scattering.jsl's
-- weights); the haze takes its colour from the tint.
local GREY_SKY = { 12, 6.7, 15 }
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
      dust = 0.55,          -- how far the ground scatters light back like dust, 0 to 1
      gloss = 0,            -- how brightly it shines
    },
    colors = { rockPale = { 0.66, 0.47, 0.33 }, rockDark = { 0.30, 0.19, 0.14 }, rockFresh = { 0.80, 0.66, 0.52 } },
    variants = {
      { rockPale = { 0.62, 0.53, 0.40 }, rockDark = { 0.27, 0.22, 0.18 }, rockFresh = { 0.80, 0.72, 0.60 } },
      { rockPale = { 0.55, 0.38, 0.30 }, rockDark = { 0.22, 0.15, 0.14 }, rockFresh = { 0.74, 0.58, 0.48 } },
    },
    air = 0.10, sky = GREY_SKY, tint = { 1.0, 0.72, 0.48 },
  },
  moon = {
    generator = "gen/world_barren.jsl", shader = "world_rock.jsl",
    generate = { craters = 1.0, plains = 0.58, rifts = 0 },
    settings = { relief = 0.10, frostLine = 2, dust = 0.55, gloss = 0 },
    colors = { rockPale = { 0.58, 0.57, 0.55 }, rockDark = { 0.24, 0.24, 0.25 }, rockFresh = { 0.86, 0.86, 0.84 } },
    variants = {
      { rockPale = { 0.56, 0.52, 0.46 }, rockDark = { 0.25, 0.22, 0.20 }, rockFresh = { 0.84, 0.80, 0.74 } },
      { rockPale = { 0.46, 0.46, 0.48 }, rockDark = { 0.17, 0.17, 0.19 }, rockFresh = { 0.78, 0.78, 0.80 } },
    },
    air = 0, sky = BLUE_SKY, tint = WHITE,
  },
  ice = {
    generator = "gen/world_ice.jsl", shader = "world_rock.jsl",
    generate = {
      cracks = 1,           -- how much of it the great cracks cross, 0 to 1
      chaos = 0.5,          -- how much of it is broken ground, 0 to 1
      craters = 0.3,
    },
    settings = { relief = 0.14, frostLine = 2, dust = 0.2, gloss = 0.35 },
    colors = { rockPale = { 0.74, 0.82, 0.90 }, rockDark = { 0.20, 0.33, 0.46 }, rockFresh = { 0.96, 0.98, 1.0 } },
    variants = {
      { rockPale = { 0.80, 0.80, 0.76 }, rockDark = { 0.42, 0.28, 0.20 }, rockFresh = { 0.97, 0.97, 0.95 } },
    },
    air = 0.15, sky = BLUE_SKY, tint = WHITE,
  },
  icemoon = {
    generator = "gen/world_ice.jsl", shader = "world_rock.jsl",
    generate = { cracks = 1, chaos = 0.4, craters = 0.5 },
    settings = { relief = 0.14, frostLine = 2, dust = 0.2, gloss = 0.35 },
    colors = { rockPale = { 0.78, 0.82, 0.86 }, rockDark = { 0.26, 0.34, 0.42 }, rockFresh = { 0.96, 0.98, 1.0 } },
    variants = {
      { rockPale = { 0.80, 0.79, 0.74 }, rockDark = { 0.44, 0.30, 0.22 }, rockFresh = { 0.97, 0.97, 0.95 } },
    },
    air = 0, sky = BLUE_SKY, tint = WHITE,
  },
  lava = {
    generator = "gen/world_lava.jsl", shader = "world_lava.jsl",
    generate = {
      seas = 0.5,           -- how much of it is open lava, 0 to 1
      fissures = 0.6,       -- how far its crust is cracked through, 0 to 1
    },
    settings = {
      relief = 0.10,
      glow = 1,             -- how bright the lava is
    },
    colors = { crustDark = { 0.07, 0.06, 0.06 }, crustPale = { 0.30, 0.26, 0.24 } },
    air = 0.30, sky = GREY_SKY, tint = { 1.0, 0.42, 0.22 },
  },
  gas = {
    generator = "gen/world_gas.jsl", shader = "world_gas.jsl",
    generate = {
      bands = 14,           -- about how many bands there are from pole to pole
      turbulence = 0.7,     -- how churned they are, 0 to 1
      storms = 0.6,         -- how stormy, 0 to 1
    },
    settings = {},
    colors = {
      bandDark = { 0.56, 0.36, 0.24 }, bandPale = { 0.90, 0.82, 0.68 }, bandStorm = { 0.78, 0.36, 0.22 },
      bandPole = { 0.50, 0.44, 0.40 }, atmoTint = { 1.0, 0.85, 0.7 },
    },
    variants = {
      -- pale gold
      { bandDark = { 0.70, 0.58, 0.38 }, bandPale = { 0.93, 0.86, 0.66 }, bandStorm = { 0.96, 0.93, 0.84 },
        bandPole = { 0.62, 0.56, 0.44 }, atmoTint = { 1.0, 0.9, 0.7 } },
      -- deep blue
      { bandDark = { 0.10, 0.22, 0.52 }, bandPale = { 0.32, 0.52, 0.86 }, bandStorm = { 0.86, 0.92, 1.0 },
        bandPole = { 0.12, 0.20, 0.42 }, atmoTint = { 0.6, 0.8, 1.0 } },
      -- sea green
      { bandDark = { 0.30, 0.56, 0.58 }, bandPale = { 0.66, 0.86, 0.84 }, bandStorm = { 0.92, 0.98, 0.96 },
        bandPole = { 0.30, 0.48, 0.52 }, atmoTint = { 0.7, 1.0, 0.95 } },
      -- rust and violet
      { bandDark = { 0.36, 0.20, 0.30 }, bandPale = { 0.80, 0.56, 0.48 }, bandStorm = { 0.96, 0.80, 0.60 },
        bandPole = { 0.30, 0.22, 0.30 }, atmoTint = { 1.0, 0.7, 0.75 } },
    },
    air = 0.22, sky = GREY_SKY, tint = WHITE,
    rings = { pale = { 0.86, 0.80, 0.70 }, dark = { 0.46, 0.40, 0.34 } },
  },
} :: { [string]: Kind }

local function vec(c: { number }): vector
  return vector.create(c[1], c[2], c[3])
end

-- A world of a kind. 'seed' is any whole number.
function Planet.New(kindId: string, seed: number, resolution: number?, tweaks: Tweaks?): World
  local kind = assert(Planet.kinds[kindId], `no kind of planet '{kindId}'`)
  local used: { [string]: boolean } = {}
  local function number(name: string, value: number): number
    local tweak = tweaks and tweaks[name]
    used[name] = true
    return if type(tweak) == "number" then tweak else value
  end
  -- The kind's colours, or those of the variant this seed has.
  local colors = table.clone(kind.colors)
  if kind.variants then
    local which = seed % (#kind.variants + 1)
    if which > 0 then
      for name, value in kind.variants[which] do
        colors[name] = value
      end
    end
  end
  local function color(name: string, value: { number }): vector
    local tweak = tweaks and tweaks[name]
    used[name] = true
    return vec(if type(tweak) == "table" then tweak else colors[name] or value)
  end

  local generator = ShaderInstance_Create(Shader_Create("identity.jsl", kind.generator))
  ShaderInstance_SetFloat(generator, "seed", seed % 1000 + 0.137)
  for name, value in kind.generate do
    ShaderInstance_SetFloat(generator, name, number(name, value))
  end
  if tweaks then
    for name, value in tweaks do
      if type(value) == "number" and string.sub(name, 1, 4) == "gen." then
        ShaderInstance_SetFloat(generator, string.sub(name, 5), value)
        used[name] = true
      end
    end
  end
  local map = CubeMap_CreateHDR(resolution or Planet.RESOLUTION)
  CubeMap_GenerateFromShaderInstance(map, generator)

  local surface = ShaderInstance_Create(Shader_Create("globe.jsl", kind.shader))
  ShaderInstance_SetCubeMap(surface, "planetMap", map)
  for name, value in kind.settings do
    ShaderInstance_SetFloat(surface, name, number(name, value))
  end
  for name, value in colors do
    if name ~= "atmoTint" then
      ShaderInstance_SetVec3(surface, name, color(name, value))
    end
  end
  -- Rings: a sheet in the plane of the equator, from 'inner' to 'outer'
  -- planet radii. The globe's shader is told of them, for their shadow.
  local rings = kind.rings
  local ringed = rings ~= nil and number("rings", if (seed // 3) % 5 < 2 then 1 else 0) > 0
  local inner = 1.25 + 0.30 * ((seed // 11) % 100) / 100
  local outer = inner + 0.55 + 0.75 * ((seed // 1009) % 100) / 100
  ShaderInstance_SetFloat(surface, "ringInner", inner)
  ShaderInstance_SetFloat(surface, "ringOuter", if ringed then outer else 0)
  ShaderInstance_SetFloat(surface, "ringSeed", seed % 100 + 0.5)

  local model = Model_Create()
  local shaders = { surface }
  local air: ShaderInstance? = nil
  local density = number("atmoDensity", kind.air)
  if density > 0 then
    local made = ShaderInstance_Create(Shader_Create("npm.jsl", "atmosphere.jsl"))
    ShaderInstance_SetState(made, "BlendModeAdditive")
    table.insert(shaders, made)
    air = made
  end
  local tint = color("atmoTint", kind.tint)
  for _, shader in shaders do
    ShaderInstance_SetFloat(shader, "atmoDensity", density)
    ShaderInstance_SetVec3(shader, "atmoTint", tint)
    ShaderInstance_SetVec3(shader, "wavelength", vec(kind.sky))
    ShaderInstance_SetFloat(shader, "whiteLight", 0)
  end
  if tweaks then
    for name, value in tweaks do
      if not used[name] and name ~= "whiteLight" then
        if type(value) == "number" then
          ShaderInstance_SetFloat(surface, name, value)
        else
          ShaderInstance_SetVec3(surface, name, vec(value))
        end
      end
    end
  end
  for _, shader in shaders do
    ShaderInstance_Link(shader)
  end
  Model_Add(model, Mesh_SetU(Mesh_BoxSphere(50, true), 1), surface)
  if air then
    local shell = Mesh_SetU(Mesh_ReverseWinding(Mesh_Scale(Mesh_BoxSphere(50, true), vector.create(AIR, AIR, AIR))), 1)
    Model_AddShell(model, shell, air)
  end
  local ring: ShaderInstance? = nil
  if ringed and rings then
    local made = ShaderInstance_Create(Shader_Create("globe.jsl", "ring.jsl"))
    ShaderInstance_SetFloat(made, "ringInner", inner)
    ShaderInstance_SetFloat(made, "ringOuter", outer)
    ShaderInstance_SetFloat(made, "ringSeed", seed % 100 + 0.5)
    ShaderInstance_SetFloat(made, "ringOpacity", number("ringOpacity", 1.6))
    ShaderInstance_SetVec3(made, "ringPale", vec(rings.pale))
    ShaderInstance_SetVec3(made, "ringDark", vec(rings.dark))
    ShaderInstance_SetFloat(made, "whiteLight", 0)
    ShaderInstance_SetState(made, "BlendModeAlpha")
    ShaderInstance_SetState(made, "ZWritableOff")
    ShaderInstance_SetState(made, "CullModeDisabled")
    ShaderInstance_Link(made)
    -- (the counts are of vertices a side: 2 is one square)
    local sheet = Mesh_Plane(vector.create(-outer, 0, -outer), vector.create(2 * outer, 0, 0), vector.create(0, 0, 2 * outer), 2, 2)
    Model_AddShell(model, sheet, made)
    ring = made
  end
  -- (scenery: drawn, and no part of the physical world. As an ordinary
  -- object a body this size costs milliseconds a frame: Object_Scenery.)
  local body = Object_Scenery({})
  Object_SetRenderable(body, model)
  -- Its axis leans, by an angle and toward a side that follow from its
  -- seed; a ringed world leans enough for its rings to be seen.
  local lean = math.rad(number("tilt", if ringed then 12 + 18 * ((seed // 37) % 100) / 100 else 24 * ((seed // 37) % 100) / 100))
  local toward = math.rad((seed // 53) % 360)
  Object_SetAxes(body, vector.create(-math.sin(toward), 0, math.cos(toward)),
    vector.create(math.sin(lean) * math.cos(toward), math.cos(lean), math.sin(lean) * math.sin(toward)))
  return { kind = kindId, seed = seed, body = body, surface = surface, air = air, ring = ring, map = map }
end

-- Change one of a world's shader settings (a name from its kind's
-- 'settings', or "atmoDensity", or "whiteLight": 1 lights it white
-- whatever colour the star is, for judging its own colours).
function Planet.Set(world: World, name: string, value: number)
  ShaderInstance_SetFloat(world.surface, name, value)
  if world.air and (name == "atmoDensity" or name == "whiteLight") then
    ShaderInstance_SetFloat(world.air, name, value)
  end
  if world.ring and name == "whiteLight" then
    ShaderInstance_SetFloat(world.ring, name, value)
  end
end

-- The kind that draws a body of the game: 'body' is "planet" or "moon",
-- 'variety' what Core/Describe calls it. Nil if nothing here draws it.
function Planet.KindOf(body: string, variety: string): string?
  if body == "moon" then
    return if variety == "barren" then "moon" elseif variety == "ice" then "icemoon" else nil
  end
  return if Planet.kinds[variety] then variety else nil
end

return Planet
