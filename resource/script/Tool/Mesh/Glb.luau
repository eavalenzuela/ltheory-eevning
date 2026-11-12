--!strict
-- A binary glTF file (.glb), read: its meshes, as a shape
-- (Tool/Mesh/Shape) with a part for each piece of mesh under each node,
-- placed where its node puts it. A part has its node's name, its
-- material's name and colour (or, with no material, the colour its
-- points carry), and is known to give off light if its material does.
-- Only what is in the file itself is read (a .glb keeps its numbers in
-- itself), and only faces of three points; pictures, bones and motion
-- are not.

local Json = require("@lt/Tool/Mesh/Json")
local Shape = require("@lt/Tool/Mesh/Shape")

local Glb = {}

local MAGIC, JSON, BIN = 0x46546C67, 0x4E4F534A, 0x004E4942
local WIDTH: { [string]: number } = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4, MAT4 = 16 }
local BYTES: { [number]: number } = { [5120] = 1, [5121] = 1, [5122] = 2, [5123] = 2, [5125] = 4, [5126] = 4 }

type Matrix = { number }    -- sixteen numbers, a column at a time

local IDENTITY: Matrix = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

local function times(a: Matrix, b: Matrix): Matrix
  local out: Matrix = {}
  for column = 0, 3 do
    for row = 0, 3 do
      local sum = 0
      for k = 0, 3 do
        sum += a[k * 4 + row + 1] * b[column * 4 + k + 1]
      end
      out[column * 4 + row + 1] = sum
    end
  end
  return out
end

-- A node's own place: its matrix, or that made of where it is put, how
-- it is turned and how it is scaled.
local function placeOf(node: any): Matrix
  if node.matrix then
    return node.matrix
  end
  local t = node.translation or { 0, 0, 0 }
  local r = node.rotation or { 0, 0, 0, 1 }
  local s = node.scale or { 1, 1, 1 }
  local x, y, z, w = r[1], r[2], r[3], r[4]
  return {
    (1 - 2 * (y * y + z * z)) * s[1], (2 * (x * y + z * w)) * s[1], (2 * (x * z - y * w)) * s[1], 0,
    (2 * (x * y - z * w)) * s[2], (1 - 2 * (x * x + z * z)) * s[2], (2 * (y * z + x * w)) * s[2], 0,
    (2 * (x * z + y * w)) * s[3], (2 * (y * z - x * w)) * s[3], (1 - 2 * (x * x + y * y)) * s[3], 0,
    t[1], t[2], t[3], 1,
  }
end

-- (a colour as light adds up, to the colour as a screen shows it)
local function shown(c: number): number
  return math.clamp(c, 0, 1) ^ (1 / 2.2)
end

function Glb.Parse(data: buffer, length: number?): Shape.Shape
  local size = length or buffer.len(data)
  if size < 20 or buffer.readu32(data, 0) ~= MAGIC then
    error("Glb: not a binary glTF file", 0)
  elseif buffer.readu32(data, 4) ~= 2 then
    error(`Glb: version {buffer.readu32(data, 4)} of glTF; this reads version 2`, 0)
  end
  local doc: any = nil
  local binary = -1
  local at = 12
  while at + 8 <= size do
    local long, kind = buffer.readu32(data, at), buffer.readu32(data, at + 4)
    if kind == JSON then
      doc = Json.Decode(buffer.readstring(data, at + 8, long))
    elseif kind == BIN and binary < 0 then
      binary = at + 8
    end
    at += 8 + long
  end
  if doc == nil then
    error("Glb: the file does not say what is in it", 0)
  end

  -- The numbers an accessor names, one after another, and how many to each.
  local function numbers(index: number): ({ number }, number)
    local accessor = doc.accessors[index + 1]
    local width = WIDTH[accessor.type]
    local bytes = BYTES[accessor.componentType]
    if width == nil or bytes == nil or accessor.bufferView == nil then
      error(`Glb: accessor {index} is of a kind this does not read`, 0)
    end
    local view = doc.bufferViews[accessor.bufferView + 1]
    if (view.buffer or 0) ~= 0 or doc.buffers[1].uri ~= nil or binary < 0 then
      error("Glb: its numbers are kept in another file, which is not read", 0)
    end
    local stride = view.byteStride or width * bytes
    local from = binary + (view.byteOffset or 0) + (accessor.byteOffset or 0)
    local kind = accessor.componentType
    local scale = 1
    if accessor.normalized then
      scale = if kind == 5121 then 1 / 255 elseif kind == 5123 then 1 / 65535 elseif kind == 5120 then 1 / 127 elseif kind == 5122 then 1 / 32767 else 1
    end
    local out: { number } = table.create(accessor.count * width)
    for element = 0, accessor.count - 1 do
      for part = 0, width - 1 do
        local where = from + element * stride + part * bytes
        local value = if kind == 5126 then buffer.readf32(data, where)
          elseif kind == 5125 then buffer.readu32(data, where)
          elseif kind == 5123 then buffer.readu16(data, where)
          elseif kind == 5122 then buffer.readi16(data, where)
          elseif kind == 5121 then buffer.readu8(data, where)
          else buffer.readi8(data, where)
        out[element * width + part + 1] = value * scale
      end
    end
    return out, width
  end

  local parts: { Shape.Part } = {}
  local function visit(index: number, parent: Matrix)
    local node = doc.nodes[index + 1]
    local place = times(parent, placeOf(node))
    if node.mesh ~= nil then
      local mesh = doc.meshes[node.mesh + 1]
      -- (a place that turns things inside out: their faces are turned back)
      local m = place
      local mirrored = m[1] * (m[6] * m[11] - m[7] * m[10]) - m[5] * (m[2] * m[11] - m[3] * m[10]) + m[9] * (m[2] * m[7] - m[3] * m[6]) < 0
      for number, primitive in mesh.primitives do
        if (primitive.mode or 4) == 4 and primitive.attributes and primitive.attributes.POSITION ~= nil then
          local raw = numbers(primitive.attributes.POSITION)
          local points: { number } = table.create(#raw)
          for p = 1, #raw, 3 do
            local x, y, z = raw[p], raw[p + 1], raw[p + 2]
            points[p] = m[1] * x + m[5] * y + m[9] * z + m[13]
            points[p + 1] = m[2] * x + m[6] * y + m[10] * z + m[14]
            points[p + 2] = m[3] * x + m[7] * y + m[11] * z + m[15]
          end
          local faces: { number } = {}
          if primitive.indices ~= nil then
            for _, corner in (numbers(primitive.indices)) do
              table.insert(faces, corner + 1)
            end
          else
            for corner = 1, #raw // 3 do
              table.insert(faces, corner)
            end
          end
          -- (whole faces only)
          for _ = 1, #faces % 3 do
            table.remove(faces)
          end
          if mirrored then
            for face = 1, #faces, 3 do
              faces[face + 1], faces[face + 2] = faces[face + 2], faces[face + 1]
            end
          end
          local material = if primitive.material ~= nil then doc.materials[primitive.material + 1] else nil
          local color: { number }? = nil
          local glows = false
          if material then
            local base = material.pbrMetallicRoughness and material.pbrMetallicRoughness.baseColorFactor
            if base then
              color = { shown(base[1]), shown(base[2]), shown(base[3]) }
            end
            local glow = material.emissiveFactor
            glows = glow ~= nil and glow[1] + glow[2] + glow[3] > 0
          end
          if color == nil and primitive.attributes.COLOR_0 ~= nil then
            -- (the colour its points carry: what they come to, all together)
            local carried, width = numbers(primitive.attributes.COLOR_0)
            local r, g, b, n = 0, 0, 0, 0
            for c = 1, #carried, width do
              r, g, b, n = r + carried[c], g + carried[c + 1], b + carried[c + 2], n + 1
            end
            if n > 0 then
              color = { r / n, g / n, b / n }
            end
          end
          local name = node.name or mesh.name or `node {index}`
          table.insert(parts, {
            name = if #mesh.primitives > 1 then `{name} {number}` else name,
            material = if material and material.name then material.name else "",
            color = color, glows = glows, points = points, faces = faces,
          })
        end
      end
    end
    for _, child in node.children or {} do
      visit(child, place)
    end
  end

  -- From the roots of the scene the file opens on; or, if it names no
  -- scene, from every node that is nobody's child.
  local roots: { number } = {}
  local scene = if doc.scenes then doc.scenes[(doc.scene or 0) + 1] else nil
  if scene and scene.nodes then
    roots = scene.nodes
  elseif doc.nodes then
    local child: { [number]: boolean } = {}
    for _, node in doc.nodes do
      for _, each in node.children or {} do
        child[each] = true
      end
    end
    for index = 0, #doc.nodes - 1 do
      if not child[index] then
        table.insert(roots, index)
      end
    end
  end
  for _, root in roots do
    visit(root, IDENTITY)
  end
  return { parts = parts }
end

return Glb
