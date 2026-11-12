--!strict
-- A shape read from a file somebody else's program wrote (Tool/Mesh/Obj,
-- Tool/Mesh/Glb): its parts, each a name, a material and faces of three
-- points; and what is done to one before it is a hull (Game/View/Imported):
-- turned to face the way a hull does, set to a hull's size, its sharp
-- edges kept sharp, each part given one of a hull's paints, its engines
-- found, and questions about its surface answered (what is above this
-- spot, is this point inside it).
--
-- Engine-free: numbers in plain tables, so that it can be tested where
-- there is no engine.

local Shape = {}

-- A part: the object or node it was in its file, its material's name
-- ("" if it had none), its colour if the file says one (red, green and
-- blue from 0 to 1, as on a screen), whether the file says it gives off
-- light, its points (x, y and z of each, one after another) and its
-- faces (three points each, counted from 1, in order counter-clockwise
-- seen from outside).
export type Part = {
  name: string,
  material: string,
  color: { number }?,
  glows: boolean?,
  points: { number },
  faces: { number },
}

export type Shape = { parts: { Part } }

-- A hull's paints, as its shader numbers them (material/hull.jsl).
Shape.PLATING, Shape.PATCH, Shape.FRAME, Shape.LIT, Shape.TRIM, Shape.FIRE = 0, 1, 2, 3, 4, 5
local BY_NAME: { [string]: number } = { plating = 0, patch = 1, frame = 2, lit = 3, trim = 4, fire = 5 }

-- The corners of the box a shape fills: its least x, y and z, and its most.
function Shape.Bounds(shape: Shape): ({ number }, { number })
  local lower, upper = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for _, part in shape.parts do
    local points = part.points
    for at = 1, #points, 3 do
      for axis = 0, 2 do
        local value = points[at + axis]
        lower[axis + 1] = math.min(lower[axis + 1], value)
        upper[axis + 1] = math.max(upper[axis + 1], value)
      end
    end
  end
  return lower, upper
end

-- An axis by its name ("+x", "-z", "y"): the way it points.
local function axisOf(name: string): { number }
  local sign = if string.sub(name, 1, 1) == "-" then -1 else 1
  local letter = string.lower(string.sub(name, -1))
  local at = if letter == "x" then 1 elseif letter == "y" then 2 elseif letter == "z" then 3 else 0
  assert(at ~= 0, `'{name}' is no axis: "+x", "-y", "z"`)
  local out = { 0, 0, 0 }
  out[at] = sign
  return out
end

-- Turn a shape to lie as a hull does: its bow along +z and its back
-- along +y, where 'fore' and 'up' say which way those are in the file
-- ("-z" and "+y" for a file as Blender writes one). It is turned, never
-- mirrored: what was its starboard side still is.
function Shape.Turn(shape: Shape, fore: string, up: string)
  local f, u = axisOf(fore), axisOf(up)
  assert(f[1] * u[1] + f[2] * u[2] + f[3] * u[3] == 0, `a shape cannot have '{fore}' for its bow and '{up}' for its back`)
  -- (to starboard: back cross bow)
  local s = { u[2] * f[3] - u[3] * f[2], u[3] * f[1] - u[1] * f[3], u[1] * f[2] - u[2] * f[1] }
  for _, part in shape.parts do
    local points = part.points
    for at = 1, #points, 3 do
      local x, y, z = points[at], points[at + 1], points[at + 2]
      points[at] = s[1] * x + s[2] * y + s[3] * z
      points[at + 1] = u[1] * x + u[2] * y + u[3] * z
      points[at + 2] = f[1] * x + f[2] * y + f[3] * z
    end
  end
end

-- Put a shape's middle at the origin and make it 'length' long from
-- bow to stern. Returns how much bigger it was made.
function Shape.Fit(shape: Shape, length: number): number
  local lower, upper = Shape.Bounds(shape)
  local scale = length / math.max(upper[3] - lower[3], 1e-9)
  local middle = { (lower[1] + upper[1]) / 2, (lower[2] + upper[2]) / 2, (lower[3] + upper[3]) / 2 }
  for _, part in shape.parts do
    local points = part.points
    for at = 1, #points, 3 do
      for axis = 0, 2 do
        points[at + axis] = (points[at + axis] - middle[axis + 1]) * scale
      end
    end
  end
  return scale
end

-- The way a face looks (not made a unit long: twice its area long).
local function facing(points: { number }, a: number, b: number, c: number): (number, number, number)
  local ax, ay, az = points[3 * a - 2], points[3 * a - 1], points[3 * a]
  local ux, uy, uz = points[3 * b - 2] - ax, points[3 * b - 1] - ay, points[3 * b] - az
  local vx, vy, vz = points[3 * c - 2] - ax, points[3 * c - 1] - ay, points[3 * c] - az
  return uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
end

-- Keep a part's sharp edges sharp. A point shared by faces is lit as
-- one smooth surface through them all; where faces at a point look more
-- than 'degrees' apart, the point is made one for each such group of
-- them, so that the edge between shows as an edge. (A box read from a
-- file has eight points and would be lit as a ball.)
function Shape.Crease(part: Part, degrees: number)
  local points, faces = part.points, part.faces
  local limit = math.cos(math.rad(degrees))
  -- (each point's groups: the way each looks, and the point that is its)
  local groups: { [number]: { { number } } } = {}
  local count = #points // 3
  for at = 1, #faces, 3 do
    local nx, ny, nz = facing(points, faces[at], faces[at + 1], faces[at + 2])
    local long = math.sqrt(nx * nx + ny * ny + nz * nz)
    if long > 0 then
      nx, ny, nz = nx / long, ny / long, nz / long
      for corner = 0, 2 do
        local point = faces[at + corner]
        local mine = groups[point]
        if mine == nil then
          mine = {}
          groups[point] = mine
        end
        local found: { number }? = nil
        for _, group in mine do
          if group[1] * nx + group[2] * ny + group[3] * nz >= limit then
            found = group
            break
          end
        end
        if found == nil then
          local as = point
          if #mine > 0 then
            -- (another group at this point: a point of its own)
            count += 1
            as = count
            points[3 * as - 2], points[3 * as - 1], points[3 * as] = points[3 * point - 2], points[3 * point - 1], points[3 * point]
          end
          local made = { nx, ny, nz, as }
          table.insert(mine, made)
          found = made
        end
        faces[at + corner] = (found :: { number })[4]
      end
    end
  end
end

-- Whether a part is closed: along every edge of it as many faces go one
-- way as go the other, and it has an edge. (Two faces, one each way, is
-- the usual thing; a face squeezed to nothing lies along others' edges
-- and is not counted.) Only a closed part has an inside.
function Shape.Closed(part: Part): boolean
  -- (points in the same place are one point, however many the file has there)
  local same: { [string]: number } = {}
  local as: { number } = {}
  local points = part.points
  for point = 1, #points // 3 do
    local key = string.format("%.5f,%.5f,%.5f", points[3 * point - 2], points[3 * point - 1], points[3 * point])
    local first = same[key]
    if first == nil then
      first = point
      same[key] = point
    end
    as[point] = first
  end
  local edges: { [string]: number } = {}
  local faces = part.faces
  for at = 1, #faces, 3 do
    local nx, ny, nz = facing(points, faces[at], faces[at + 1], faces[at + 2])
    if nx * nx + ny * ny + nz * nz > 1e-20 then
      for corner = 0, 2 do
        local a, b = as[faces[at + corner]], as[faces[at + (corner + 1) % 3]]
        if a ~= b then
          local key, way = if a < b then `{a}:{b}` else `{b}:{a}`, if a < b then 1 else -1
          edges[key] = (edges[key] or 0) + way
        end
      end
    end
  end
  for _, net in edges do
    if net ~= 0 then
      return false
    end
  end
  return next(edges) ~= nil
end

-- Parts as one part: every point and face of them, under the first's
-- name. (An object in two materials is two parts; whether it is closed,
-- and what is inside it, are questions for the two together.)
function Shape.Merge(parts: { Part }): Part
  local out: Part = { name = if parts[1] then parts[1].name else "", material = "", points = {}, faces = {} }
  for _, part in parts do
    local base = #out.points // 3
    table.move(part.points, 1, #part.points, #out.points + 1, out.points)
    for _, corner in part.faces do
      table.insert(out.faces, base + corner)
    end
  end
  return out
end

-- Which of a hull's paints a part is to have. Its material's name says,
-- if it is one of theirs ("plating", "patch", "frame", "lit", "trim",
-- "fire"). Otherwise it is guessed: from its names and whether it gives
-- off light (an engine's glow is its fire, any other glow, a light or a
-- window is lit, a nozzle or a barrel is trim),
-- and then from its colour: bright and strong is lit, strong is the
-- hull's plating, grey is its other plating, and near black is trim.
function Shape.Paint(part: Part): number
  local named = BY_NAME[string.lower(part.material)]
  if named then
    return named
  end
  local words = string.lower(part.name .. " " .. part.material)
  local engine = string.find(words, "engine", 1, true) or string.find(words, "exhaust", 1, true) or string.find(words, "thrust", 1, true)
  if part.glows or string.find(words, "glow", 1, true) or string.find(words, "emissi", 1, true) then
    return if engine then Shape.FIRE else Shape.LIT
  elseif string.find(words, "light", 1, true) or string.find(words, "lamp", 1, true) or string.find(words, "window", 1, true) then
    return Shape.LIT
  elseif string.find(words, "nozzle", 1, true) or string.find(words, "barrel", 1, true) then
    return Shape.TRIM
  end
  local color = part.color
  if color == nil then
    return Shape.PLATING
  end
  local most, least = math.max(color[1], color[2], color[3]), math.min(color[1], color[2], color[3])
  local strong = if most > 0 then (most - least) / most else 0
  if most > 0.85 and strong > 0.5 then
    return Shape.LIT
  elseif most < 0.18 then
    return Shape.TRIM
  elseif strong > 0.25 then
    return Shape.PLATING
  end
  return Shape.PATCH
end

-- Where a shape's engines are: the middle of each part painted as an
-- engine's fire, and half the widest it is across the ship.
export type Engine = { x: number, y: number, z: number, radius: number }
function Shape.Engines(shape: Shape): { Engine }
  local found: { Engine } = {}
  for _, part in shape.parts do
    if Shape.Paint(part) == Shape.FIRE and #part.points >= 9 then
      local lower, upper = Shape.Bounds({ parts = { part } })
      table.insert(found, {
        x = (lower[1] + upper[1]) / 2, y = (lower[2] + upper[2]) / 2,
        -- (its fire leaves by its after end)
        z = lower[3],
        radius = math.max(upper[1] - lower[1], upper[2] - lower[2]) / 2,
      })
    end
  end
  table.sort(found, function(a, b)
    if a.x ~= b.x then
      return a.x < b.x
    elseif a.y ~= b.y then
      return a.y < b.y
    end
    return a.z < b.z
  end)
  return found
end

-- Questions about where the surface of some parts is, answered by
-- looking straight up and down (along y) through their faces. The faces
-- are sorted into a grid over x and z once, so that a question looks at
-- the few faces over its own spot.
export type Caster = {
  -- The heights at which the faces cross the upright line through (x, z),
  -- lowest first, and for each whether the face there looks up.
  Cross: (x: number, z: number) -> ({ number }, { boolean }),
  -- Whether a point is inside: more of the surface above it an odd
  -- number of times. Right for parts that are closed.
  Inside: (x: number, y: number, z: number) -> boolean,
  -- The highest the surface is over (x, z), or the lowest, and the way
  -- the face there looks (a unit long); nil if there is none there.
  Top: (x: number, z: number) -> (number?, number, number, number),
  Bottom: (x: number, z: number) -> (number?, number, number, number),
}

function Shape.Cast(parts: { Part }): Caster
  -- Every face as nine numbers, and the way it looks as three.
  local corners: { number } = {}
  local looks: { number } = {}
  local lowX, lowZ, highX, highZ = math.huge, math.huge, -math.huge, -math.huge
  for _, part in parts do
    local points, faces = part.points, part.faces
    for at = 1, #faces, 3 do
      local nx, ny, nz = facing(points, faces[at], faces[at + 1], faces[at + 2])
      local long = math.sqrt(nx * nx + ny * ny + nz * nz)
      -- (a face seen edge on from above is crossed by no upright line)
      if long > 0 and math.abs(ny) > 1e-9 * long then
        for corner = 0, 2 do
          local point = faces[at + corner]
          local x, y, z = points[3 * point - 2], points[3 * point - 1], points[3 * point]
          table.insert(corners, x)
          table.insert(corners, y)
          table.insert(corners, z)
          lowX, highX, lowZ, highZ = math.min(lowX, x), math.max(highX, x), math.min(lowZ, z), math.max(highZ, z)
        end
        table.insert(looks, nx / long)
        table.insert(looks, ny / long)
        table.insert(looks, nz / long)
      end
    end
  end
  local count = #looks // 3
  local across = math.clamp(math.floor(math.sqrt(count / 2)), 1, 96)
  local cellX, cellZ = math.max(highX - lowX, 1e-9) / across, math.max(highZ - lowZ, 1e-9) / across
  local cells: { [number]: { number } } = {}
  for face = 1, count do
    local base = 9 * face - 9
    local x0 = math.min(corners[base + 1], corners[base + 4], corners[base + 7])
    local x1 = math.max(corners[base + 1], corners[base + 4], corners[base + 7])
    local z0 = math.min(corners[base + 3], corners[base + 6], corners[base + 9])
    local z1 = math.max(corners[base + 3], corners[base + 6], corners[base + 9])
    for i = math.clamp(math.floor((x0 - lowX) / cellX), 0, across - 1), math.clamp(math.floor((x1 - lowX) / cellX), 0, across - 1) do
      for j = math.clamp(math.floor((z0 - lowZ) / cellZ), 0, across - 1), math.clamp(math.floor((z1 - lowZ) / cellZ), 0, across - 1) do
        local key = i * across + j
        local cell = cells[key]
        if cell == nil then
          cell = {}
          cells[key] = cell
        end
        table.insert(cell, face)
      end
    end
  end

  -- The faces over (x, z): the height of each there, and which face it is.
  local function over(x: number, z: number): ({ number }, { number })
    local heights: { number } = {}
    local which: { number } = {}
    if count == 0 or x < lowX or x > highX or z < lowZ or z > highZ then
      return heights, which
    end
    local cell = cells[math.clamp(math.floor((x - lowX) / cellX), 0, across - 1) * across
      + math.clamp(math.floor((z - lowZ) / cellZ), 0, across - 1)]
    if cell == nil then
      return heights, which
    end
    for _, face in cell do
      local base = 9 * face - 9
      local ax, ay, az = corners[base + 1], corners[base + 2], corners[base + 3]
      local bx, by, bz = corners[base + 4], corners[base + 5], corners[base + 6]
      local cx, cy, cz = corners[base + 7], corners[base + 8], corners[base + 9]
      -- (seen from above with its corners going one way round, whichever
      -- way the face looks)
      local area = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
      if area < 0 then
        bx, by, bz, cx, cy, cz = cx, cy, cz, bx, by, bz
        area = -area
      end
      -- How far the spot is to the inside of each edge. A spot on an
      -- edge is the face's if the edge is one of its left or upper ones
      -- (seen so), and its neighbour's if not: so a line down a seam
      -- between two faces crosses the surface once, and one that only
      -- grazes it at an edge crosses it twice or not at all.
      local function within(px: number, pz: number, qx: number, qz: number): (boolean, number)
        local side = (qx - px) * (z - pz) - (qz - pz) * (x - px)
        return side > 0 or (side == 0 and (qz < pz or (qz == pz and qx < px))), side
      end
      local inA, sideA = within(bx, bz, cx, cz)
      local inB, sideB = within(cx, cz, ax, az)
      local inC, sideC = within(ax, az, bx, bz)
      if inA and inB and inC then
        local height = (sideA * ay + sideB * by + sideC * cy) / area
        local place = #heights + 1
        while place > 1 and heights[place - 1] > height do
          heights[place], which[place] = heights[place - 1], which[place - 1]
          place -= 1
        end
        heights[place], which[place] = height, face
      end
    end
    return heights, which
  end

  local caster = {} :: Caster
  function caster.Cross(x: number, z: number): ({ number }, { boolean })
    local heights, which = over(x, z)
    local up: { boolean } = {}
    for index, face in which do
      up[index] = looks[3 * face - 1] > 0
    end
    return heights, up
  end
  function caster.Inside(x: number, y: number, z: number): boolean
    local above = 0
    for _, height in (over(x, z)) do
      above += if height > y then 1 else 0
    end
    return above % 2 == 1
  end
  function caster.Top(x: number, z: number): (number?, number, number, number)
    local heights, which = over(x, z)
    local face = which[#which]
    if face == nil then
      return nil, 0, 1, 0
    end
    return heights[#heights], looks[3 * face - 2], looks[3 * face - 1], looks[3 * face]
  end
  function caster.Bottom(x: number, z: number): (number?, number, number, number)
    local heights, which = over(x, z)
    local face = which[1]
    if face == nil then
      return nil, 0, -1, 0
    end
    return heights[1], looks[3 * face - 2], looks[3 * face - 1], looks[3 * face]
  end
  return caster
end

return Shape
