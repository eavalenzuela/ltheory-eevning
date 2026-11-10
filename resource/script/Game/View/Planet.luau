--!strict
-- Planets as things to look at, built the way the engine's own planet
-- is and the way EVE's are (docs/roadmap.md, "Bodies: how to build
-- them"): the lie of the land is drawn once into a cube map, and a
-- shader dresses and lights the globe from it; a shell around the globe
-- adds the glow of its air.
--
-- One kind so far: temperate.

local Planet = {}

export type World = {
  kind: string,
  seed: number,
  body: Object,
  surface: ShaderInstance,
  air: ShaderInstance,
  map: CubeMap,
}

-- The size of a face of the cube map, in pixels. (Six faces at 16-bit
-- float: about 50 MB at 1024.)
Planet.RESOLUTION = 1024

-- The shell of air stands this far out, in planet radii (scattering.jsl
-- assumes it).
local AIR = 1.025
-- How strongly each colour of light is scattered: blue far more than red.
-- (Against the weights scattering.jsl gives red, green and blue, these
-- come out as the blue of a sky like Earth's.)
local WAVELENGTH = vector.create(5.6, 7.1, 39)

-- What the temperate shader is told, where a caller says nothing else.
Planet.TEMPERATE = {
  seaLevel = 0.46,      -- heights under this are sea
  cloudCover = 0.36,    -- the share of sky with cloud in it, roughly
  iceLine = 0.86,       -- how far toward a pole the sea freezes (0 equator, 1 pole)
  relief = 0.045,       -- how strongly slopes catch the light
  cityLights = 1,       -- 0 for a world nobody lives on
  atmoDensity = 0.6,
  whiteLight = 0,       -- 1 to light it white whatever the star (for judging its colours)
} :: { [string]: number }

-- A temperate world. 'seed' is any whole number.
function Planet.NewTemperate(seed: number, resolution: number?): World
  local generator = ShaderInstance_Create(Shader_Create("identity.jsl", "gen/world_temperate.jsl"))
  ShaderInstance_SetFloat(generator, "seed", seed % 1000 + 0.137)
  local map = CubeMap_CreateHDR(resolution or Planet.RESOLUTION)
  CubeMap_GenerateFromShaderInstance(map, generator)

  local surface = ShaderInstance_Create(Shader_Create("npm.jsl", "world.jsl"))
  ShaderInstance_SetCubeMap(surface, "planetMap", map)
  local air = ShaderInstance_Create(Shader_Create("npm.jsl", "atmosphere.jsl"))
  ShaderInstance_SetState(air, "BlendModeAdditive")
  for _, shader in { surface, air } do
    ShaderInstance_SetFloat(shader, "atmoDensity", Planet.TEMPERATE.atmoDensity)
    ShaderInstance_SetVec3(shader, "atmoTint", vector.create(1, 1, 1))
    ShaderInstance_SetVec3(shader, "wavelength", WAVELENGTH)
    ShaderInstance_Link(shader)
  end
  for name, value in Planet.TEMPERATE do
    if name ~= "atmoDensity" then
      ShaderInstance_SetFloat(surface, name, value)
    end
  end

  local model = Model_Create()
  Model_Add(model, Mesh_SetU(Mesh_BoxSphere(50, true), 1), surface)
  local shell = Mesh_SetU(Mesh_ReverseWinding(Mesh_Scale(Mesh_BoxSphere(50, true), vector.create(AIR, AIR, AIR))), 1)
  Model_AddShell(model, shell, air)
  local body = Object_Custom({})
  Object_SetRenderable(body, model)
  return { kind = "temperate", seed = seed, body = body, surface = surface, air = air, map = map }
end

-- Change one of a world's settings (a name from Planet.TEMPERATE).
function Planet.Set(world: World, name: string, value: number)
  ShaderInstance_SetFloat(world.surface, name, value)
  if name == "atmoDensity" or name == "whiteLight" then
    ShaderInstance_SetFloat(world.air, name, value)
  end
end

return Planet
