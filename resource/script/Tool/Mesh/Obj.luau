--!strict
-- A Wavefront OBJ file, read (Blender writes them: File, Export,
-- Wavefront): its points and faces, as a shape (Tool/Mesh/Shape) with a
-- part for each object in each material. A face of more than three
-- points is cut into threes from its first point. Points' normals and
-- places on a picture are not read: a hull is lit and painted by the
-- game's own rules. With the text of the file's materials (its .mtl), a
-- part has its material's colour, and is known to give off light if its
-- material does.

local Shape = require("@lt/Tool/Mesh/Shape")

local Obj = {}

-- The colours of the materials an .mtl file names, and which of them
-- give off light.
function Obj.Materials(text: string): ({ [string]: { number } }, { [string]: boolean })
  local colors: { [string]: { number } } = {}
  local glows: { [string]: boolean } = {}
  local name = ""
  for line in string.gmatch(text, "[^\r\n]+") do
    local word, rest = string.match(line, "^%s*(%S+)%s*(.-)%s*$")
    if word == "newmtl" then
      name = rest :: string
    elseif (word == "Kd" or word == "Ke") and name ~= "" then
      local r, g, b = string.match(rest :: string, "^(%S+)%s+(%S+)%s+(%S+)")
      local red, green, blue = tonumber(r), tonumber(g), tonumber(b)
      if red and green and blue then
        if word == "Kd" then
          colors[name] = { red, green, blue }
        elseif red + green + blue > 0 then
          glows[name] = true
        end
      end
    end
  end
  return colors, glows
end

function Obj.Parse(text: string, materials: string?): Shape.Shape
  local colors, glows = Obj.Materials(materials or "")
  local xs: { number }, ys: { number }, zs: { number } = {}, {}, {}
  local parts: { Shape.Part } = {}
  local byKey: { [string]: Shape.Part } = {}
  -- (which of the part's own points each of the file's points is)
  local places: { [Shape.Part]: { [number]: number } } = {}
  local object, material = "", ""
  local part: Shape.Part? = nil

  local function current(): Shape.Part
    if part then
      return part
    end
    local key = `{object}\n{material}`
    local found = byKey[key]
    if found == nil then
      found = { name = object, material = material, color = colors[material], glows = glows[material], points = {}, faces = {} }
      byKey[key] = found
      places[found] = {}
      table.insert(parts, found)
    end
    part = found
    return found
  end

  local number = 0
  for line in string.gmatch(text, "[^\r\n]+") do
    number += 1
    local word, rest = string.match(line, "^%s*(%S+)%s*(.-)%s*$")
    if word == "v" then
      local x, y, z = string.match(rest :: string, "^(%S+)%s+(%S+)%s+(%S+)")
      local px, py, pz = tonumber(x), tonumber(y), tonumber(z)
      if px == nil or py == nil or pz == nil then
        error(`Obj: line {number}: a point that is not three numbers`, 0)
      end
      table.insert(xs, px :: number)
      table.insert(ys, py :: number)
      table.insert(zs, pz :: number)
    elseif word == "o" or word == "g" then
      object, part = rest :: string, nil
    elseif word == "usemtl" then
      material, part = rest :: string, nil
    elseif word == "f" then
      local into = current()
      local mine = places[into]
      local corners: { number } = {}
      for corner in string.gmatch(rest :: string, "%S+") do
        local index = tonumber(string.match(corner, "^(-?%d+)"))
        if index == nil or index == 0 then
          error(`Obj: line {number}: a face's corner that is no point`, 0)
        end
        -- (counted back from the last point, if less than nothing)
        local point = if (index :: number) < 0 then #xs + 1 + (index :: number) else index :: number
        if xs[point] == nil then
          error(`Obj: line {number}: a face has point {index}, and there are {#xs}`, 0)
        end
        local place = mine[point]
        if place == nil then
          table.insert(into.points, xs[point])
          table.insert(into.points, ys[point])
          table.insert(into.points, zs[point])
          place = #into.points // 3
          mine[point] = place
        end
        table.insert(corners, place)
      end
      for index = 2, #corners - 1 do
        table.insert(into.faces, corners[1])
        table.insert(into.faces, corners[index])
        table.insert(into.faces, corners[index + 1])
      end
    end
  end
  -- (a part named and never drawn is no part)
  local kept: { Shape.Part } = {}
  for _, each in parts do
    if #each.faces > 0 then
      table.insert(kept, each)
    end
  end
  return { parts = kept }
end

return Obj
