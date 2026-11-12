--!strict
-- Shapes read from other programs' files (Tool/Mesh).

local Glb = require("@lt/Tool/Mesh/Glb")
local Json = require("@lt/Tool/Mesh/Json")
local Obj = require("@lt/Tool/Mesh/Obj")
local Shape = require("@lt/Tool/Mesh/Shape")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Mesh")

-- A box from -1 to 1 each way, as an OBJ file: eight points, six faces
-- of four, wound counter-clockwise seen from outside.
local BOX = [[
# a box
mtllib box.mtl
o crate
v -1 -1 -1
v 1 -1 -1
v 1 1 -1
v -1 1 -1
v -1 -1 1
v 1 -1 1
v 1 1 1
v -1 1 1
usemtl plating
f 4 3 2 1
f 5 6 7 8
f 1 2 6 5
usemtl hazard
f 2/1/1 3/2/1 7/3/1 6/4/1
f 3 4 8 7
f -5 -8 -4 -1
]]

local MATERIALS = [[
newmtl plating
Kd 0.4 0.3 0.2
newmtl hazard
Kd 0.9 0.8 0.1
Ke 0.5 0.4 0.0
]]

-- The same box as one part, for asking about its surface.
local function box(): Shape.Part
  local shape = Obj.Parse((string.gsub(BOX, "usemtl hazard\n", "")))
  return shape.parts[1]
end

suite:Case("JSON is read into tables, and what is not JSON is refused with where", function(t)
  local doc = Json.Decode('{ "a": [1, -2.5, 3e2, true, false], "b": { "c": "x\\n\\"y\\"\\u0041" }, "d": null, "e": [] }')
  t.eq(doc.a, { 1, -2.5, 300, true, false } :: { any })
  t.eq({ doc.b.c, doc.d, #doc.e } :: { any }, { 'x\n"y"A', nil, 0 } :: { any })
  t.eq(Json.Decode(" 42 "), 42)
  for _, bad in { "{", '{"a" 1}', "[1 2]", '"open', "tru", "{} x", "" } do
    local ok, why = pcall(Json.Decode, bad)
    t.ok(not ok and string.find(tostring(why), "^Json: .+ at byte %d+") ~= nil, `'{bad}' was read as JSON: {tostring(why)}`)
  end
end)

suite:Case("an OBJ file is read as a part for each object in each material", function(t)
  local shape = Obj.Parse(BOX, MATERIALS)
  t.eq(#shape.parts, 2)
  local plating, hazard = shape.parts[1], shape.parts[2]
  t.eq({ plating.name, plating.material, hazard.name, hazard.material }, { "crate", "plating", "crate", "hazard" })
  -- (a face of four is two of three; a part has only the points its own faces use)
  t.eq({ #plating.faces, #hazard.faces, #plating.points, #hazard.points }, { 18, 18, 24, 24 })
  t.eq({ plating.color, plating.glows, hazard.color, hazard.glows } :: { any }, { { 0.4, 0.3, 0.2 }, nil, { 0.9, 0.8, 0.1 }, true } :: { any })
  -- (points counted back from the last, and corners that say more than a point, are read)
  t.eq({ Shape.Bounds(shape) }, { { -1, -1, -1 }, { 1, 1, 1 } })
  -- Without its materials it is the same shape, of no colour.
  t.eq(Obj.Parse(BOX).parts[2].color, nil)
  -- A face that names a point there is not is refused, with its line.
  local ok, why = pcall(Obj.Parse, "v 0 0 0\nf 1 2 3\n")
  t.ok(not ok and string.find(tostring(why), "line 2", 1, true) ~= nil, tostring(why))
end)

suite:Case("a shape is turned to lie as a hull does, never mirrored, and set to a hull's length", function(t)
  -- A wedge that knows its sides: long along the file's -z (its bow),
  -- tall along +y, and with one point out to +x.
  local wedge = "v 0 0 -4\nv 0 0 0\nv 0 1 0\nv 0.5 0 0\nf 1 2 3\nf 1 4 2\nf 1 3 4\nf 2 4 3\n"
  local shape = Obj.Parse(wedge)
  Shape.Turn(shape, "-z", "+y")
  local lower, upper = Shape.Bounds(shape)
  -- (its bow is along +z now, its back along +y; and its point is still
  -- on the side it was: with the bow turned about, that is -x)
  t.eq({ lower, upper }, { { -0.5, 0, 0 }, { 0, 1, 4 } })
  local part = shape.parts[1]
  t.ok(Shape.Closed(part), "turning it should not open it")
  -- Not mirrored: it is still wound counter-clockwise from outside,
  -- which is to say it still has its inside in.
  local volume = 0
  local p, f = part.points, part.faces
  for at = 1, #f, 3 do
    local a, b, c = f[at], f[at + 1], f[at + 2]
    local ax, ay, az = p[3 * a - 2], p[3 * a - 1], p[3 * a]
    local bx, by, bz = p[3 * b - 2], p[3 * b - 1], p[3 * b]
    local cx, cy, cz = p[3 * c - 2], p[3 * c - 1], p[3 * c]
    volume += (ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx)) / 6
  end
  t.near(volume, 4 * 1 * 0.5 / 6, 1e-9)
  -- A file whose bow is -x and whose back is +z (as some are written).
  local other = Obj.Parse("v -4 0 0\nv 0 0 0\nv 0 0 1\nv 0 0.5 0\nf 1 2 3\n")
  Shape.Turn(other, "-x", "+z")
  lower, upper = Shape.Bounds(other)
  t.eq({ upper[3] - lower[3], upper[2] - lower[2] }, { 4, 1 })
  t.ok(not pcall(Shape.Turn, other, "+x", "-x"), "a bow and a back along one line is no way to lie")
  -- Two units long, about its middle.
  t.near(Shape.Fit(shape, 2), 0.5, 1e-12)
  lower, upper = Shape.Bounds(shape)
  t.eq({ lower, upper }, { { -0.125, -0.25, -1 }, { 0.125, 0.25, 1 } })
end)

suite:Case("sharp edges are kept sharp, and a closed part is known from an open one", function(t)
  local part = box()
  t.eq({ #part.points // 3, #part.faces // 3 }, { 8, 12 })
  t.ok(Shape.Closed(part))
  -- Every corner of a box is three faces a quarter turn apart: a point for each.
  Shape.Crease(part, 40)
  t.eq({ #part.points // 3, #part.faces // 3 }, { 24, 12 })
  t.ok(Shape.Closed(part), "it is as closed as it was: the points made are where the old ones are")
  -- Told that a quarter turn is no edge, it is left alone.
  local smooth = box()
  Shape.Crease(smooth, 100)
  t.eq(#smooth.points // 3, 8)
  -- A box with its lid off is open.
  local open = Obj.Parse((string.gsub((string.gsub(BOX, "usemtl hazard\n", "")), "f 5 6 7 8\n", "")))
  t.ok(not Shape.Closed(open.parts[1]))
end)

suite:Case("a part that is inside out is turned about, where it can be told", function(t)
  -- A box with every face wound the wrong way holds less than nothing.
  local inside = box()
  for at = 1, #inside.faces, 3 do
    inside.faces[at + 1], inside.faces[at + 2] = inside.faces[at + 2], inside.faces[at + 1]
  end
  t.ok(Shape.Mend(inside), "an inside-out box was left as it was")
  local caster = Shape.Cast({ inside })
  local _, _, ny = caster.Top(0, 0)
  t.eq(ny, 1)
  t.ok(not Shape.Mend(inside) and not Shape.Mend(box()), "a box that is right was turned about")
  -- A sheet lying on a hull's back, to one side of its middle line,
  -- looking down into it: turned to look up. Looking up, it is left.
  local sheet = Obj.Parse("v 1 2 0\nv 2 2 0\nv 2 2 1\nv 1 2 1\nf 1 2 3 4\n").parts[1]
  local _, _, before = Shape.Cast({ sheet }).Top(1.5, 0.5)
  t.eq(before, -1)
  t.ok(Shape.Mend(sheet))
  local _, _, after = Shape.Cast({ sheet }).Top(1.5, 0.5)
  t.eq(after, 1)
  t.ok(not Shape.Mend(sheet))
  -- A tube with no ends, off to one side: as much of it looks each way,
  -- and whichever way it is wound it is left alone.
  local lines = {}
  for i = 0, 7 do
    local a = i * math.pi / 4
    table.insert(lines, string.format("v %.6f %.6f 0", 3 + math.cos(a), math.sin(a)))
    table.insert(lines, string.format("v %.6f %.6f 1", 3 + math.cos(a), math.sin(a)))
  end
  for i = 0, 7 do
    local j = (i + 1) % 8
    table.insert(lines, `f {2 * i + 1} {2 * j + 1} {2 * j + 2} {2 * i + 2}`)
  end
  local tube = Obj.Parse(table.concat(lines, "\n") .. "\n").parts[1]
  t.ok(not Shape.Closed(tube) and not Shape.Mend(tube))
end)

suite:Case("a part's paint is its material's if that is a hull's, and guessed if not", function(t)
  local function part(name: string, material: string, color: { number }?, glows: boolean?): Shape.Part
    return { name = name, material = material, color = color, glows = glows, points = {}, faces = {} }
  end
  t.eq(Shape.Paint(part("x", "trim", { 1, 0, 0 })), Shape.TRIM)
  t.eq(Shape.Paint(part("x", "Fire")), Shape.FIRE)
  -- By its names.
  t.eq(Shape.Paint(part("Engine 0 exhaust glow", "")), Shape.FIRE)
  t.eq(Shape.Paint(part("Amber hull light 1", "")), Shape.LIT)
  t.eq(Shape.Paint(part("Engine 1 exhaust barrel", "", { 0.15, 0.16, 0.17 })), Shape.TRIM)
  -- By whether it gives off light.
  t.eq(Shape.Paint(part("strip", "mat7", { 0.2, 0.2, 0.2 }, true)), Shape.LIT)
  t.eq(Shape.Paint(part("thruster", "mat7", { 0.2, 0.2, 0.2 }, true)), Shape.FIRE)
  -- By its colour: brown is plating, grey the other plating, near black
  -- trim, and bright orange is lit.
  t.eq(Shape.Paint(part("Main hull", "", { 0.45, 0.33, 0.23 })), Shape.PLATING)
  t.eq(Shape.Paint(part("Side armor", "", { 0.29, 0.27, 0.24 })), Shape.PATCH)
  t.eq(Shape.Paint(part("thing", "", { 0.10, 0.10, 0.11 })), Shape.TRIM)
  t.eq(Shape.Paint(part("thing", "", { 0.96, 0.65, 0.26 })), Shape.LIT)
  t.eq(Shape.Paint(part("thing", "")), Shape.PLATING)
end)

suite:Case("questions about a shape's surface are answered through its faces", function(t)
  local part = box()
  local caster = Shape.Cast({ part })
  local top, nx, ny, nz = caster.Top(0.3, -0.2)
  t.eq({ top, nx, ny, nz } :: { any }, { 1, 0, 1, 0 } :: { any })
  local bottom, bx, by, bz = caster.Bottom(0.3, -0.2)
  t.eq({ bottom, bx, by, bz } :: { any }, { -1, 0, -1, 0 } :: { any })
  t.eq((caster.Top(1.5, 0)), nil)
  local heights, up = caster.Cross(0, 0)
  t.eq({ heights, up } :: { any }, { { -1, 1 }, { false, true } } :: { any })
  t.ok(caster.Inside(0.9, 0.9, -0.9) and caster.Inside(0, 0, 0))
  t.ok(not caster.Inside(0, 1.1, 0) and not caster.Inside(0, -1.1, 0) and not caster.Inside(1.2, 0, 0))
  -- A line down a seam between two faces crosses the surface once at
  -- each side of the box, not twice: or the box would have no inside there.
  for _, spot in { { 0, 0 }, { 0.5, 0.5 }, { -0.25, 0.25 }, { 0.999, -0.999 } } do
    t.eq(#(caster.Cross(spot[1], spot[2])), 2, `over ({spot[1]}, {spot[2]})`)
  end
  -- Its engines: the parts painted as fire, by their after ends.
  local shape = Obj.Parse(BOX)
  shape.parts[2].material = "fire"
  local engines = Shape.Engines(shape)
  t.eq(#engines, 1)
  t.eq({ engines[1].x, engines[1].y, engines[1].z, engines[1].radius }, { 0, 0, -1, 1 })
end)

-- A binary glTF file of one triangle under a node that is moved, with a
-- material: put together a byte at a time.
local function tiny(node: string, material: string): (buffer, number)
  local json = `\{"asset":\{"version":"2.0"},"scene":0,"scenes":[\{"nodes":[0]}],`
    .. `"nodes":[\{"name":"root","children":[1]},{node}],`
    .. `"meshes":[\{"primitives":[\{"attributes":\{"POSITION":0,"COLOR_0":2},"indices":1{material}}]}],`
    .. `"materials":[\{"name":"paint","pbrMetallicRoughness":\{"baseColorFactor":[1,0.2140,0,1]},"emissiveFactor":[1,0.5,0]}],`
    .. `"buffers":[\{"byteLength":56}],`
    .. `"bufferViews":[\{"buffer":0,"byteOffset":0,"byteLength":36},\{"buffer":0,"byteOffset":36,"byteLength":6},`
    .. `\{"buffer":0,"byteOffset":44,"byteLength":12}],`
    .. `"accessors":[\{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},`
    .. `\{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"},`
    .. `\{"bufferView":2,"componentType":5121,"normalized":true,"count":3,"type":"VEC4"}]}`
  while #json % 4 ~= 0 do
    json ..= " "
  end
  local total = 12 + 8 + #json + 8 + 56
  local data = buffer.create(total)
  buffer.writeu32(data, 0, 0x46546C67)
  buffer.writeu32(data, 4, 2)
  buffer.writeu32(data, 8, total)
  buffer.writeu32(data, 12, #json)
  buffer.writeu32(data, 16, 0x4E4F534A)
  buffer.writestring(data, 20, json)
  local bin = 20 + #json
  buffer.writeu32(data, bin, 56)
  buffer.writeu32(data, bin + 4, 0x004E4942)
  bin += 8
  for index, value in { 0, 0, 0, 1, 0, 0, 0, 1, 0 } do
    buffer.writef32(data, bin + (index - 1) * 4, value)
  end
  for index, value in { 0, 1, 2 } do
    buffer.writeu16(data, bin + 36 + (index - 1) * 2, value)
  end
  for index, value in { 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255 } do
    buffer.writeu8(data, bin + 44 + index - 1, value)
  end
  return data, total
end

suite:Case("a binary glTF file is read as a part for each mesh under each node, where its node puts it", function(t)
  local data, length = tiny('{"name":"wing","mesh":0,"translation":[10,0,0],"scale":[2,2,2]}', ',"material":0')
  local shape = Glb.Parse(data, length)
  t.eq(#shape.parts, 1)
  local part = shape.parts[1]
  t.eq({ part.name, part.material, part.glows } :: { any }, { "wing", "paint", true } :: { any })
  t.eq(part.points, { 10, 0, 0, 12, 0, 0, 10, 2, 0 })
  t.eq(part.faces, { 1, 2, 3 })
  -- (its material's colour, as a screen shows it)
  local color = part.color :: { number }
  t.near(color[1], 1, 1e-9)
  t.near(color[2], 0.2140 ^ (1 / 2.2), 1e-9)
  t.eq(color[3], 0)
  -- With no material it has the colour its points carry, all together;
  -- and a node that turns it inside out has its faces turned back.
  data, length = tiny('{"name":"wing","mesh":0,"scale":[-1,1,1]}', "")
  part = Glb.Parse(data, length).parts[1]
  t.eq({ part.material, part.glows } :: { any }, { "", false } :: { any })
  t.eq(part.points, { 0, 0, 0, -1, 0, 0, 0, 1, 0 })
  t.eq(part.faces, { 1, 3, 2 })
  color = part.color :: { number }
  t.near(color[1], 1 / 3, 1e-9)
  t.near(color[2], 1 / 3, 1e-9)
  -- A node turned a quarter about y (a rotation said in four numbers).
  data, length = tiny('{"name":"wing","mesh":0,"rotation":[0,0.7071067811865476,0,0.7071067811865476]}', "")
  part = Glb.Parse(data, length).parts[1]
  for index, want in { 0, 0, 0, 0, 0, -1, 0, 1, 0 } do
    t.near(part.points[index], want, 1e-6)
  end
  -- What is not one is refused.
  local junk = buffer.create(32)
  local ok, why = pcall(Glb.Parse, junk)
  t.ok(not ok and string.find(tostring(why), "not a binary glTF", 1, true) ~= nil, tostring(why))
end)

return suite
