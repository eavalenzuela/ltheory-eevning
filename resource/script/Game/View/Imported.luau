--!strict
-- A hull that was modelled in another program: read from a file under
-- resource/model (a Wavefront .obj or a binary glTF .glb: Tool/Mesh),
-- and made a hull's skin, in a hull's paints, lit and worn by the hull's
-- own shader as every other hull is (Game/View/Plates).
--
-- What is taken from the file is its shape and what its parts are
-- called. It is turned to lie as a hull does (the file's bow and back
-- are said, where they are not as Blender writes them: -Z and +Y), set
-- two units long about its middle, and its sharp edges kept sharp. Each
-- part has one paint: its material's, if that is named for one of a
-- hull's ("plating", "patch", "frame", "lit", "trim", "fire"), else a
-- guess from its names and its colour (Shape.Paint). Its engines are
-- where its fire is. Pictures laid on it, and anything that moves, are
-- not read.
--
-- Where its guns stand is not in the file: a design says where along
-- and across the hull each is, and the mounts are put on the surface
-- there, one above and one beneath (Imported.Mounts).

local File = require("@lt/Tool/Mesh/File")
local Plates = require("@lt/Game/View/Plates")
local Shape = require("@lt/Tool/Mesh/Shape")

local Imported = {}

Imported.FOLDER = "resource/model/"
Imported.LENGTH = 2

export type Options = {
  fore: string?,      -- which way the file's bow points ("-z" if not said)
  up: string?,        -- and its back ("+y")
  crease: number?,    -- faces more degrees apart than this have an edge between them (40)
}

export type Model = {
  shape: Shape.Shape,
  paints: { number },             -- the paint of each part, in the parts' order
  engines: { Shape.Engine },
  -- The surface a gun can stand on: everything that is not lit.
  deck: Shape.Caster,
  -- Each object of it that is closed, as something with an inside.
  solids: { Shape.Caster },
}

local loaded: { [string]: Model } = {}

-- A model by its file's name under resource/model. Read once and kept.
-- A file that is not there, or cannot be read, is an error that says so.
function Imported.Load(file: string, options: Options?): Model
  local had = loaded[file]
  if had then
    return had
  end
  local shape, why = File.Read(Imported.FOLDER .. file)
  if shape == nil then
    error(`Imported: {tostring(why)}`, 0)
  end
  Shape.Turn(shape, if options and options.fore then options.fore else "-z", if options and options.up then options.up else "+y")
  Shape.Fit(shape, Imported.LENGTH)
  local paints: { number } = {}
  local deck: { Shape.Part } = {}
  local byName: { [string]: { Shape.Part } } = {}
  local names: { string } = {}
  for index, part in shape.parts do
    Shape.Crease(part, if options and options.crease then options.crease else 40)
    local paint = Shape.Paint(part)
    paints[index] = paint
    if paint ~= Shape.LIT and paint ~= Shape.FIRE then
      table.insert(deck, part)
    end
    if byName[part.name] == nil then
      byName[part.name] = {}
      table.insert(names, part.name)
    end
    table.insert(byName[part.name], part)
  end
  local solids: { Shape.Caster } = {}
  for _, name in names do
    local whole = Shape.Merge(byName[name])
    if Shape.Closed(whole) then
      table.insert(solids, Shape.Cast({ whole }))
    end
  end
  local model: Model = { shape = shape, paints = paints, engines = Shape.Engines(shape), deck = Shape.Cast(deck), solids = solids }
  loaded[file] = model
  return model
end

-- Put a model into what is being built.
function Imported.Draw(b: Plates.Builder, model: Model)
  for index, part in model.shape.parts do
    Plates.Skin(b, model.paints[index], part.points, part.faces)
  end
  for _, solid in model.solids do
    Plates.Stands(b, function(p: vector): boolean
      return solid.Inside(p.x, p.y, p.z)
    end)
  end
end

-- A hardpoint on a model: a mount on its back and one on its belly, at
-- 'x' across it and 'z' along it (in a hull's units: it is two long,
-- its bow at +1), each looking the way the surface about it does (the
-- surface for a little way round: on a ridge a mount stands upright, not
-- leaning to whichever side its middle happens to be on). 'fore' is the
-- way what stands there faces (the bow, if not said).
export type Mount = { at: vector, up: vector, fore: vector? }
function Imported.Mounts(model: Model, x: number, z: number, fore: vector?): { Mount }
  local AROUND = 0.03
  local function mount(ask: (x: number, z: number) -> (number?, number, number, number)): Mount
    local height = ask(x, z)
    assert(height, `there is no hull at {x} across and {z} along to stand a gun on`)
    local up = vector.create(0, 0, 0)
    for _, way in { { 0, 0 }, { AROUND, 0 }, { -AROUND, 0 }, { 0, AROUND }, { 0, -AROUND } } do
      local there, nx, ny, nz = ask(x + way[1], z + way[2])
      if there then
        up += vector.create(nx, ny, nz)
      end
    end
    return { at = vector.create(x, height :: number, z), up = vector.normalize(up), fore = fore }
  end
  return { mount(model.deck.Top), mount(model.deck.Bottom) }
end

return Imported
