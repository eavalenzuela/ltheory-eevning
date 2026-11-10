--!strict
-- Stars, planets and moons as things to look at.
--
-- A star is two objects in the same place: its face, a sphere shaded by
-- star.jsl, and around it a larger shell on which starcorona.jsl adds
-- the corona, flares and prominences. Its kind (Game/View/StarTypes)
-- sets every colour and rate; a seed makes one star of a kind differ
-- from the next.

local StarTypes = require("@lt/Game/View/StarTypes")

local Bodies = {}

export type Star = {
  type: StarTypes.StarType,
  face: Object,
  corona: Object,
  faceShader: ShaderInstance,
  coronaShader: ShaderInstance,
  shellRadii: number,     -- the shell's radius, in star radii
}

-- How bright a star's face and corona are drawn. (The picture is
-- tone-mapped afterwards, so more than 1 is how a star outshines what
-- it lights.)
Bodies.STAR_BRIGHTNESS = 1.8
Bodies.CORONA_BRIGHTNESS = 0.55

local FLOATS = { "limbDarken", "granulationScale", "granulationStrength", "granulationSpeed", "spotDensity", "spotSize",
  "spotIntensity", "coronaRadius", "coronaStrength", "coronaFalloff", "coronaNoiseScale", "coronaNoiseStrength",
  "coronaPulseRate", "coronaPulseAmp", "breatheRate", "breatheAmp", "flareDensity", "flareIntensity", "flareExtent",
  "flareSpeed", "prominenceDensity", "prominenceIntensity", "prominenceExtent", "prominenceSpeed", "prominenceBend" }
local COLORS = { "colorHot", "colorMid", "colorCool", "spotColor", "coronaColor", "flareColor", "prominenceColor" }

local function color(c: { number }): vector
  return vector.create(c[1], c[2], c[3])
end

-- A star of a kind. 'seed' is any whole number.
function Bodies.NewStar(typeId: string, seed: number): Star
  local t = assert(StarTypes.byId[typeId], `no kind of star '{typeId}'`)
  -- (finely divided: the corona begins exactly at the true limb, and a
  -- coarse sphere's outline would fall visibly short of it)
  local sphere = Mesh_Sphere(128, 96)
  local faceShader = ShaderInstance_Create(Shader_Create("npm.jsl", "star.jsl"))
  local coronaShader = ShaderInstance_Create(Shader_Create("npm.jsl", "starcorona.jsl"))
  ShaderInstance_SetState(coronaShader, "BlendModeAdditive")
  ShaderInstance_SetState(coronaShader, "ZWritableOff")

  -- The shell reaches a little past whatever reaches furthest.
  local shellRadii = 1.05 * math.max(t.coronaRadius * 1.1, 1 + t.prominenceExtent, 1 + t.flareExtent)
  local starSeed = color(t.seed) + vector.create(seed * 7.31 % 97, seed * 3.17 % 89, seed * 5.71 % 83)
  for _, shader in { faceShader, coronaShader } do
    for _, name in FLOATS do
      ShaderInstance_SetFloat(shader, name, t[name])
    end
    for _, name in COLORS do
      ShaderInstance_SetVec3(shader, name, color(t[name]))
    end
    ShaderInstance_SetVec3(shader, "starSeed", starSeed)
    ShaderInstance_SetFloat(shader, "clock", 0)
  end
  ShaderInstance_SetInt(faceShader, "granulationOctaves", t.granulationOctaves)
  ShaderInstance_SetFloat(faceShader, "brightness", Bodies.STAR_BRIGHTNESS)
  ShaderInstance_SetFloat(coronaShader, "brightness", Bodies.CORONA_BRIGHTNESS)
  ShaderInstance_SetFloat(coronaShader, "shellRadii", shellRadii)

  local function body(shader: ShaderInstance): Object
    local model = Model_Create()
    Model_Add(model, sphere, shader)
    local object = Object_Custom({})
    Object_SetRenderable(object, model)
    return object
  end
  return { type = t, face = body(faceShader), corona = body(coronaShader), faceShader = faceShader,
    coronaShader = coronaShader, shellRadii = shellRadii }
end

-- Put a star somewhere, at a size.
function Bodies.PlaceStar(star: Star, at: vector, radius: number)
  star.face:SetPos(at)
  star.face:SetScale(vector.create(radius, radius, radius))
  star.corona:SetPos(at)
  local shell = radius * star.shellRadii
  star.corona:SetScale(vector.create(shell, shell, shell))
end

-- Move a star's surface on to a time, in seconds.
function Bodies.TickStar(star: Star, clock: number)
  ShaderInstance_SetFloat(star.faceShader, "clock", clock)
  ShaderInstance_SetFloat(star.coronaShader, "clock", clock)
end

return Bodies
