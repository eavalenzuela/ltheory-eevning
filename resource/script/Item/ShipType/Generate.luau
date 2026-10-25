--!strict
-- Ship hulls (Luau port of Item/ShipType/Generate.lts): boxes grown off a
-- cross of two boxes, mirrored, then pinched and flared by two warps. The
-- engine calls Main(scale, seed) for each ship type; the random draws are
-- in the same order as the LTSL version, so a seed gives the same hull.

local Int = require("@lt/Int")

local MESH_QUALITY = 12
local BEVEL = 0.25

type Box = { center: vector, size: vector }

-- LTSL's Clamp: the lower bound wins when the bounds cross
local function clamp(v: vector, lower: vector, upper: vector): vector
  local function c(t: number, lo: number, hi: number): number
    if t < lo then return lo end
    if t > hi then return hi end
    return t
  end
  return vector.create(c(v.x, lower.x, upper.x), c(v.y, lower.y, upper.y), c(v.z, lower.z, upper.z))
end

local AXES = {
  vector.create(-1, 0, 0), vector.create(1, 0, 0),
  vector.create(0, -1, 0), vector.create(0, 1, 0),
  vector.create(0, 0, -1), vector.create(0, 0, 1),
}

-- Pinches the hull vertically away from the center line
local function verticalCompress(magnitude: number, offset: number, size: number, power: number, variance: number)
  return {
    GetDelta = function(_, p: vector): vector
      local t = math.max(0, math.abs(p.x - offset) - size) ^ power
      return vector.create(0, magnitude * Float_ExpDecay(t, variance), 0)
    end,
  }
end

-- Flares the hull sideways toward the front
local function horizontalExpand(magnitude: number, offset: number, size: number, power: number, variance: number)
  return {
    GetDelta = function(_, p: vector): vector
      local t = math.max(0, (p.z - offset) - size) ^ power
      return vector.create(math.sign(p.x) * magnitude * Float_ExpDecay(t, variance), 0, 0)
    end,
  }
end

return {
  Main = function(scale: number, seed: number): Model
    local mesh = PlateMesh_Create(MESH_QUALITY)
    local rng = RNG_MTG(Int.Signed(seed + 102))
    local plates = 2 + math.floor(math.sqrt(scale))

    local boxes: { Box } = {
      { center = vector.create(0, 0, 0), size = vector.create(2.0, 0.5, 0.5) },
      { center = vector.create(0, 0, 0), size = vector.create(0.5, 1.0, 2.0) },
    }
    local passive: { Box } = {}
    local boundLower, boundUpper = vector.create(-3, -2, -6), vector.create(3, 2, 6)

    for i = 1, plates do
      rng:Int(#boxes) -- drawn but unused, as in LTSL
      local box = boxes[i]
      local dir = AXES[rng:Int(6) + 1]
      local newSize = box.size * rng:Vec3(vector.create(0.9, 0.9, 0.9), vector.create(0.99, 0.99, 0.99))
      local newCenter = clamp(box.center + dir * (box.size + newSize), boundLower + newSize, boundUpper - newSize)
      for _ = 1, rng:Int(1, 5) do
        table.insert(boxes, { center = newCenter, size = newSize })
        table.insert(passive, { center = newCenter, size = newSize * vector.create(0.5, 0.5, 1.5) })
        newCenter += newSize * vector.create(0, 0, 3)
      end
    end
    for _, box in passive do
      table.insert(boxes, box)
    end

    local zero = vector.create(0, 0, 0)
    for _, box in boxes do
      mesh:Add(box.center, box.size, zero, BEVEL)
      mesh:Add(box.center * vector.create(-1, 1, 1), box.size * 0.99, zero, BEVEL)
      if scale >= 10 then
        mesh:Add(box.center * vector.create(1, -0.5, 1), box.size * vector.create(1.25, 0.50, 2.00), zero, BEVEL)
        mesh:Add(box.center * vector.create(-1, -0.5, 1), box.size * vector.create(1.24, 0.49, 1.99), zero, BEVEL)
      end
    end

    -- Two draws whose features are disabled, kept so later draws match
    rng:Float()
    rng:Float()

    mesh:Add(Warp_Custom(verticalCompress(1.0, 0.0, 1.25, 1.0, 1.0)))
    mesh:Add(Warp_Custom(horizontalExpand(0.5, 1.0, 0.0, 2.0, 0.25)))

    local built = mesh:GetMesh()
    Mesh_Center(built)
    Mesh_ComputeOcclusion(built)
    local model = Model_Create()
    model:Add(built, Material_Metal())
    return model
  end,
}
