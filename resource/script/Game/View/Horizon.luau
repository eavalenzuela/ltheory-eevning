--!strict
-- The event horizon of a stargate (the project owner's, 2026-11-21): a
-- shimmering, water-like surface across its mouth with the system beyond
-- seen through it. Cheaply: every sky is sorted into one of a few colour
-- families, and the horizon shows a picture baked once of a sky of the
-- family of the system the gate leads to.

local Horizon = {}

-- The two colours a system's sky is made of, from the seed the system is
-- made with, drawn as the engine draws them (src/liblt/Game/Object/
-- System.cpp): the star's (the sky's glow), drawn first from the seed;
-- and the dust's, which the engine draws in Initialize from the seed
-- again, after six other draws, and mixes half and half with the star's.
-- (A star's colour there: 1 - 0.5 log of three draws, the green halved.)
local function starColor(rng: RNG): vector
  local x, y, z = rng:Float(), rng:Float(), rng:Float()
  return vector.create(1 - 0.5 * math.log(x), 1 - 0.25 * math.log(y), 1 - 0.5 * math.log(z))
end

function Horizon.SkyColors(seed: number): (vector, vector)
  local first = RNG_MTG(seed)
  local glow = starColor(first)
  local again = RNG_MTG(seed)
  for _ = 1, 6 do
    again:Float()
  end
  local dust = (glow + starColor(again)) * 0.5
  return glow, dust
end

-- The colour a sky comes out, on the whole, as shares of red, green and
-- blue: the glow's colour and much more the dust's, which decides what
-- of the glow gets through it (fitted to 24 skies drawn by the engine
-- and measured all round, 2026-11-21: glow^0.5 dust^2.5, within a few
-- hundredths of each share).
function Horizon.SkyTint(seed: number): vector
  local glow, dust = Horizon.SkyColors(seed)
  local t = vector.create(glow.x ^ 0.5 * dust.x ^ 2.5, glow.y ^ 0.5 * dust.y ^ 2.5, glow.z ^ 0.5 * dust.z ^ 2.5)
  return t / (t.x + t.y + t.z)
end

-- The families, each by where its middle is in (red less blue, green
-- less the other two) of a tint: the ten clusters of four thousand
-- skies' tints (k-means), each holding a sixteenth to an eighth of them.
-- Its picture is texture/horizon/family-NN.png, a sky of the family
-- near its middle, baked with App/skies: the sky of the system made
-- with 'seed', looked at with Skies.Fov(60) and Skies.LookOff(off,
-- around), the 1920x1080 shot cut square (from its middle where 'around'
-- is 0.6, from its left edge where it is 3.5, so the star is in it) and
-- made 512 across.
Horizon.FAMILIES = {
  { name = "amber", x = 0.2027, y = -0.0035, seed = 55797, off = 0.55, around = 0.6 },
  { name = "green", x = 0.0164, y = 0.2234, seed = 68059, off = 0.55, around = 0.6 },
  { name = "steel blue", x = -0.2137, y = -0.0084, seed = 57400, off = 0.55, around = 3.5 },
  { name = "deep blue", x = -0.6009, y = -0.3208, seed = 67440, off = 0.55, around = 0.6 },
  { name = "blue", x = -0.3486, y = -0.2339, seed = 16900, off = 0.55, around = 0.6 },
  { name = "violet", x = -0.1042, y = -0.2354, seed = 10355, off = 0.55, around = 3.5 },
  { name = "magenta", x = 0.1522, y = -0.2206, seed = 48443, off = 0.55, around = 3.5 },
  { name = "red", x = 0.3939, y = -0.2285, seed = 63918, off = 0.55, around = 3.5 },
  { name = "crimson", x = 0.6309, y = -0.342, seed = 10583, off = 0.55, around = 3.5 },
  { name = "pale", x = -0.0112, y = -0.043, seed = 11235, off = 0.55, around = 3.5 },
}

-- The family of the sky of the system made with 'seed'.
function Horizon.Family(seed: number): number
  local t = Horizon.SkyTint(seed)
  local x, y = t.x - t.z, t.y - (t.x + t.z) / 2
  local best, least = 1, math.huge
  for index, family in Horizon.FAMILIES do
    local far = (x - family.x) ^ 2 + (y - family.y) ^ 2
    if far < least then
      best, least = index, far
    end
  end
  return best
end

-- ---------------------------------------------------------------------
-- A horizon in a scene

local pictures: { [number]: Texture } = {}
local function picture(family: number): Texture
  local kept: Texture? = pictures[family]
  if kept then
    return kept
  end
  local made = Texture_LoadFrom(Location_Resource(string.format("texture/horizon/family-%02d.png", family)))
  pictures[family] = made
  return made
end

local disc: Mesh? = nil
local GLOW = vector.create(0.78, 0.93, 1.0)
-- (when no ripple is running: long ago)
local LONG_AGO = -1000

export type Made = { object: Object, shader: ShaderInstance, rippleA: number, rippleB: number }

-- A horizon showing a sky of 'family', 'radius' across the mouth of a
-- gate at 'at' facing 'look' (out of its system), with 'up' above it: a
-- thing of the scene, to be put in it by the caller.
function Horizon.Make(family: number, radius: number, at: vector, look: vector, up: vector): Made
  if disc == nil then
    disc = Mesh_BoxSphere(16, true)
  end
  local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "horizon.jsl"))
  ShaderInstance_SetState(shader, "BlendModeAlpha")
  ShaderInstance_SetState(shader, "ZWritableOff")
  ShaderInstance_SetState(shader, "CullModeDisabled")
  ShaderInstance_SetTexture2D(shader, "horizonPicture", picture(family))
  local right = vector.normalize(vector.cross(up, look))
  ShaderInstance_SetVec3(shader, "faceN", look)
  ShaderInstance_SetVec3(shader, "faceU", right)
  ShaderInstance_SetVec3(shader, "horizonGlow", GLOW)
  ShaderInstance_SetFloat(shader, "pictureGain", 1.6)
  ShaderInstance_SetFloat(shader, "time", 0)
  ShaderInstance_SetFloat(shader, "open", 1)
  ShaderInstance_SetFloat(shader, "rippleA", LONG_AGO)
  ShaderInstance_SetFloat(shader, "rippleB", LONG_AGO)
  ShaderInstance_SetFloat(shader, "seeThrough", 0)
  ShaderInstance_Link(shader)
  local model = Model_Create()
  Model_AddShell(model, disc :: Mesh, shader)
  local object = Object_Scenery({})
  Object_SetRenderable(object, model)
  -- (flattened into the plane of the mouth)
  object:SetScale(vector.create(radius, radius, radius * 0.01))
  object:SetPos(at)
  Object_SetAxes(object, look, up)
  return { object = object, shader = shader, rippleA = LONG_AGO, rippleB = LONG_AGO }
end

-- A ship going through it, now ('time' as Horizon.Update is given it):
-- a ring of ripples runs out from the middle.
function Horizon.Ripple(made: Made, time: number)
  made.rippleB = made.rippleA
  made.rippleA = time
  ShaderInstance_SetFloat(made.shader, "rippleA", made.rippleA)
  ShaderInstance_SetFloat(made.shader, "rippleB", made.rippleB)
end

-- Each frame: the time (seconds, any clock that runs on), how far open
-- it is, 0 to 1, and whether it is the one the pilot is coming out of
-- (seen through from its outer side as the system it opens on, not as a
-- picture).
function Horizon.Update(made: Made, time: number, open: number, through: boolean)
  ShaderInstance_SetFloat(made.shader, "time", time)
  ShaderInstance_SetFloat(made.shader, "open", open)
  ShaderInstance_SetFloat(made.shader, "seeThrough", if through then 1 else 0)
end

return Horizon
