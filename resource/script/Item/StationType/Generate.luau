--!strict
-- Station hulls: rings of spokes around a stacked column (Luau port of
-- Item/StationType/Generate.lts). The engine calls Main(seed) for each
-- station type; the random draws are in the same order as the LTSL
-- version, so a seed gives the same station.

local QUALITY = 8

local function addRing(mesh: PlateMesh, h: number, r: number, spokes: number, th: number)
  local origin = vector.create(0, h, 0)
  for i = 0, spokes - 1 do
    local angle = 2 * math.pi * (i / spokes)
    local dir = vector.create(math.cos(angle), 0, math.sin(angle))
    local rot = vector.create(math.pi / 2 - angle, 0, 0)
    mesh:Add(origin + 0.5 * r * dir, vector.create(0.2, 0.1, 0.5 * r), rot, 0.15)
    mesh:Add(origin + (r + th) * dir, vector.create(0.5, 0.5, th), rot, 0.25)
    mesh:Add(origin + 0.5 * r * dir, vector.create(0.5, 0.2, 1), rot, 0.5)
  end
end

local function addColumn(mesh: PlateMesh, rng: RNG, h: number, pieces: number, radius: number)
  local dh = h / pieces
  for i = 0, pieces - 1 do
    local y = 2 * (i / pieces) - 1.5
    local r = 0.1 + 0.4 * radius * rng:Exp() ^ 0.5 * math.exp(-0.5 * math.max(0, 1 - y))
    mesh:Add(vector.create(0, h * y, 0), vector.create(r, 1.5 * dh, r), vector.create(0, 0, 0), 0.25)
  end
end

return {
  Main = function(seed: number): PlateMesh
    local mesh = PlateMesh_Create(QUALITY)
    local rng = RNG_MTG(seed)
    addRing(mesh, -1, 4, 8, 0.05)
    addRing(mesh, 0, 8, 2 * rng:Int(2, 8), 0.1)
    addRing(mesh, 1, 3, 4, 0.05)
    addRing(mesh, -4, 2, 6, 0.05)
    addColumn(mesh, rng, 8, 2 * rng:Int(8, 16), 2)
    mesh:Add(Warp_AttractorPoint(vector.create(0, 10, 0), 8 * rng:Float()))
    mesh:Add(Warp_AttractorPoint(vector.create(0, -10, 0), 8 * rng:Float()))
    return mesh
  end,
}
