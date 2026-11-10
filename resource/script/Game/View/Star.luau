--!strict
-- A star as a thing to look at: a disc with a face (star.jsl) and a
-- corona on a shell round it (corona.jsl). The light it sheds, and the
-- flare the engine draws for that light, belong to the engine's own star
-- object; Star.Light is the colour to give it.
--
-- The classes are those the game describes (Core/Describe/System):
-- "yellow", "orange", "red", "white", "blue".

local Star = {}

export type Kind = {
  tint: { number },       -- the disc's colour, as it should look on a screen
  light: { number },      -- the colour of the light it sheds
  grain: number,          -- convection cells across its radius
  spots: number,          -- how spotted, 0 to 1
  glare: number,          -- how bright the middle of the disc is
  corona: number,         -- how bright its corona is
}

-- Settings to use in place of a kind's own, by name.
export type Tweaks = { [string]: number | { number } }

-- The corona's shell stands this far out, in star radii.
Star.REACH = 4

Star.kinds = {
  yellow = { tint = { 1.0, 0.88, 0.58 }, light = { 1.30, 1.22, 1.04 }, grain = 60, spots = 0.35, glare = 2.6, corona = 0.9 },
  orange = { tint = { 1.0, 0.64, 0.30 }, light = { 1.32, 1.06, 0.80 }, grain = 42, spots = 0.50, glare = 2.4, corona = 0.8 },
  red = { tint = { 1.0, 0.38, 0.20 }, light = { 1.34, 0.86, 0.66 }, grain = 24, spots = 0.75, glare = 2.2, corona = 0.7 },
  white = { tint = { 0.96, 0.97, 1.0 }, light = { 1.24, 1.26, 1.30 }, grain = 80, spots = 0.15, glare = 3.0, corona = 1.0 },
  blue = { tint = { 0.56, 0.74, 1.0 }, light = { 0.96, 1.12, 1.36 }, grain = 110, spots = 0.05, glare = 3.2, corona = 1.1 },
} :: { [string]: Kind }

local function kindOf(variety: string): Kind
  return Star.kinds[variety] or Star.kinds.yellow
end

-- The colour of the light a star of this class sheds.
function Star.Light(variety: string): vector
  local light = kindOf(variety).light
  return vector.create(light[1], light[2], light[3])
end

-- The star's body, of radius 1: scale it to the star's.
function Star.New(variety: string, seed: number, tweaks: Tweaks?): Object
  local kind = kindOf(variety)
  local function number(name: string, value: number): number
    local tweak = tweaks and tweaks[name]
    return if type(tweak) == "number" then tweak else value
  end
  local tweak = tweaks and tweaks.starTint
  local t = if type(tweak) == "table" then tweak else kind.tint
  local tint = vector.create(t[1], t[2], t[3])

  local face = ShaderInstance_Create(Shader_Create("npm.jsl", "star.jsl"))
  ShaderInstance_SetVec3(face, "starTint", tint)
  ShaderInstance_SetFloat(face, "grain", number("grain", kind.grain))
  ShaderInstance_SetFloat(face, "spots", number("spots", kind.spots))
  ShaderInstance_SetFloat(face, "glare", number("glare", kind.glare))
  ShaderInstance_SetFloat(face, "seed", seed % 1000 + 0.137)
  ShaderInstance_Link(face)

  local glow = ShaderInstance_Create(Shader_Create("npm.jsl", "corona.jsl"))
  ShaderInstance_SetVec3(glow, "starTint", tint)
  ShaderInstance_SetFloat(glow, "reach", Star.REACH)
  ShaderInstance_SetFloat(glow, "corona", number("corona", kind.corona))
  ShaderInstance_SetFloat(glow, "seed", seed % 1000 + 0.137)
  ShaderInstance_SetState(glow, "BlendModeAdditive")
  ShaderInstance_SetState(glow, "ZWritableOff")
  ShaderInstance_Link(glow)

  local model = Model_Create()
  Model_AddShell(model, Mesh_SetU(Mesh_BoxSphere(40, true), 1), face)
  local reach = vector.create(Star.REACH, Star.REACH, Star.REACH)
  Model_AddShell(model, Mesh_SetU(Mesh_ReverseWinding(Mesh_Scale(Mesh_BoxSphere(24, true), reach)), 1), glow)
  local body = Object_Scenery({})
  Object_SetRenderable(body, model)
  return body
end

return Star
