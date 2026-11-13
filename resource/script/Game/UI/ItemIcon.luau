--!strict
-- An icon for every type of item, put together from a few parts and not
-- drawn one by one: a tile in the colour of its category (module,
-- charge, hull, ore, ...), a pictogram for what it is (a beam for a
-- laser, a round for a gun's ammunition, a gear for a component), and
-- one to three pips for its size. Two hundred types get by on some two
-- dozen pictograms.
--
--   ItemIcon.Draw("laser.pulse.medium", x, y, 28)

local Types = require("@lt/Core/Data/Types")
local Ships = require("@lt/Core/Data/Ships")

local ItemIcon = {}

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

local TILE: { [string]: vector } = {
  module = vector.create(0.20, 0.42, 0.62),
  charge = vector.create(0.62, 0.44, 0.16),
  ship = vector.create(0.24, 0.50, 0.36),
  ore = vector.create(0.46, 0.36, 0.28),
  mineral = vector.create(0.42, 0.44, 0.50),
  component = vector.create(0.36, 0.46, 0.30),
  blueprint = vector.create(0.16, 0.32, 0.62),
  skillbook = vector.create(0.50, 0.30, 0.52),
  goods = vector.create(0.42, 0.42, 0.36),
  structure = vector.create(0.34, 0.40, 0.48),
  planetary = vector.create(0.30, 0.46, 0.44),
  moon = vector.create(0.46, 0.44, 0.56),
  drone = vector.create(0.46, 0.34, 0.50),
  implant = vector.create(0.50, 0.26, 0.40),
}

-- A closed outline through some points.
local function outline(points: { vector }): { Glyph }
  local out: { Glyph } = {}
  for index, point in points do
    table.insert(out, Glyph_Line(point, points[index % #points + 1], 1, 1))
  end
  return out
end

local function add(to: { Glyph }, more: { Glyph }): { Glyph }
  for _, glyph in more do
    table.insert(to, glyph)
  end
  return to
end

-- The parts of each pictogram, in a square from -1 to 1.
local PICTOGRAMS: { [string]: () -> { Glyph } } = {
  laser = function()
    return { Glyph_Box(v(-0.72, 0), v(0.2, 0.34), 1, 1), Glyph_Line(v(-0.5, 0), v(0.95, 0), 1, 1),
      Glyph_Line(v(0.55, -0.32), v(0.9, -0.12), 1, 0.7), Glyph_Line(v(0.55, 0.32), v(0.9, 0.12), 1, 0.7) }
  end,
  gun = function()
    return { Glyph_Box(v(-0.6, 0), v(0.3, 0.36), 1, 1), Glyph_Box(v(0.25, -0.14), v(0.6, 0.07), 1, 1),
      Glyph_Box(v(0.25, 0.14), v(0.6, 0.07), 1, 1) }
  end,
  hybrid = function()
    return { Glyph_Line(v(-0.9, -0.3), v(0.6, -0.3), 1, 1), Glyph_Line(v(-0.9, 0.3), v(0.6, 0.3), 1, 1),
      Glyph_Circle(v(0.15, 0), 0.2, 1, 1), Glyph_Line(v(0.45, 0), v(0.95, 0), 1, 0.7) }
  end,
  launcher = function()
    return add({ Glyph_Triangle(v(0.35, -0.3), v(0.35, 0.3), v(0.95, 0), 1, 1), Glyph_Box(v(-0.1, 0), v(0.45, 0.2), 1, 1) },
      { Glyph_Line(v(-0.55, -0.2), v(-0.9, -0.5), 1, 1), Glyph_Line(v(-0.55, 0.2), v(-0.9, 0.5), 1, 1) })
  end,
  shield = function()
    return { Glyph_Ring(0, 0.85, 1, 1, 0), Glyph_Ring(0, 0.5, 1, 0.6, 0), Glyph_Circle(0, 0.16, 1, 1) }
  end,
  armor = function()
    return { Glyph_Box(v(0, -0.55), v(0.8, 0.14), 1, 1), Glyph_Box(v(0, 0), v(0.8, 0.14), 1, 0.8), Glyph_Box(v(0, 0.55), v(0.8, 0.14), 1, 0.6) }
  end,
  engine = function()
    return { Glyph_Triangle(v(0.7, -0.55), v(0.7, 0.55), v(-0.1, 0), 1, 1), Glyph_Line(v(-0.3, 0), v(-0.95, 0), 1, 1),
      Glyph_Line(v(-0.3, -0.3), v(-0.8, -0.45), 1, 0.7), Glyph_Line(v(-0.3, 0.3), v(-0.8, 0.45), 1, 0.7) }
  end,
  battery = function()
    return add(outline({ v(-0.8, -0.45), v(0.65, -0.45), v(0.65, 0.45), v(-0.8, 0.45) }),
      { Glyph_Box(v(0.8, 0), v(0.1, 0.2), 1, 1), Glyph_Box(v(-0.45, 0), v(0.18, 0.28), 1, 1), Glyph_Box(v(0.0, 0), v(0.18, 0.28), 1, 0.6) })
  end,
  miner = function()
    return { Glyph_Line(v(-0.9, 0.6), v(0.15, -0.1), 1, 1), Glyph_Circle(v(0.45, -0.3), 0.42, 1, 1), Glyph_Box(v(-0.8, 0.55), v(0.16, 0.16), 1, 1) }
  end,
  crystal = function()
    return add(outline({ v(0, -0.9), v(0.55, 0), v(0, 0.9), v(-0.55, 0) }), { Glyph_Line(v(-0.55, 0), v(0.55, 0), 1, 0.6) })
  end,
  rounds = function()
    -- a round standing on its base
    return add(outline({ v(-0.32, 0.8), v(-0.32, -0.15), v(0, -0.85), v(0.32, -0.15), v(0.32, 0.8) }),
      { Glyph_Line(v(-0.32, 0.35), v(0.32, 0.35), 1, 0.7) })
  end,
  slug = function()
    return { Glyph_Circle(v(0.2, 0), 0.42, 1, 1), Glyph_Line(v(-0.95, -0.25), v(-0.3, -0.25), 1, 0.7), Glyph_Line(v(-0.95, 0), v(-0.4, 0), 1, 1),
      Glyph_Line(v(-0.95, 0.25), v(-0.3, 0.25), 1, 0.7) }
  end,
  missile = function()
    return { Glyph_Triangle(v(0.4, -0.22), v(0.4, 0.22), v(0.95, 0), 1, 1), Glyph_Box(v(-0.1, 0), v(0.5, 0.2), 1, 1),
      Glyph_Triangle(v(-0.6, -0.2), v(-0.95, -0.55), v(-0.95, -0.2), 1, 1), Glyph_Triangle(v(-0.6, 0.2), v(-0.95, 0.55), v(-0.95, 0.2), 1, 1) }
  end,
  ship = function()
    return { Glyph_Triangle(v(-0.8, -0.6), v(-0.8, 0.6), v(0.95, 0), 1, 1), Glyph_Triangle(v(-0.95, -0.25), v(-0.95, 0.25), v(-0.5, 0), 1, 0.4) }
  end,
  hauler = function()
    return add(outline({ v(-0.9, -0.5), v(0.5, -0.5), v(0.9, 0), v(0.5, 0.5), v(-0.9, 0.5) }),
      { Glyph_Line(v(-0.4, -0.5), v(-0.4, 0.5), 1, 0.7), Glyph_Line(v(0.1, -0.5), v(0.1, 0.5), 1, 0.7) })
  end,
  rock = function()
    return outline({ v(-0.8, -0.2), v(-0.35, -0.75), v(0.4, -0.7), v(0.85, -0.1), v(0.55, 0.65), v(-0.3, 0.8), v(-0.85, 0.35) })
  end,
  ingot = function()
    return add(outline({ v(-0.55, -0.4), v(0.55, -0.4), v(0.9, 0.45), v(-0.9, 0.45) }), { Glyph_Line(v(-0.35, 0), v(0.35, 0), 1, 0.6) })
  end,
  gear = function()
    local out: { Glyph } = { Glyph_Ring(0, 0.55, 1, 1, 0), Glyph_Circle(0, 0.18, 1, 1) }
    for tooth = 0, 7 do
      local a = tooth * math.pi / 4
      table.insert(out, Glyph_Line(v(0.6 * math.cos(a), 0.6 * math.sin(a)), v(0.92 * math.cos(a), 0.92 * math.sin(a)), 1, 1))
    end
    return out
  end,
  blueprint = function()
    return add(outline({ v(-0.8, -0.8), v(0.8, -0.8), v(0.8, 0.8), v(-0.8, 0.8) }),
      { Glyph_Line(v(-0.8, -0.25), v(0.8, -0.25), 1, 0.5), Glyph_Line(v(-0.8, 0.3), v(0.8, 0.3), 1, 0.5), Glyph_Line(v(-0.25, -0.8), v(-0.25, 0.8), 1, 0.5),
        Glyph_Line(v(0.3, -0.8), v(0.3, 0.8), 1, 0.5) })
  end,
  book = function()
    return add(outline({ v(-0.7, -0.85), v(0.7, -0.85), v(0.7, 0.85), v(-0.7, 0.85) }),
      { Glyph_Line(v(-0.4, -0.85), v(-0.4, 0.85), 1, 1), Glyph_Line(v(-0.15, -0.35), v(0.45, -0.35), 1, 0.7), Glyph_Line(v(-0.15, 0), v(0.45, 0), 1, 0.7) })
  end,
  crate = function()
    return add(outline({ v(-0.8, -0.7), v(0.8, -0.7), v(0.8, 0.7), v(-0.8, 0.7) }),
      { Glyph_Line(v(-0.8, -0.7), v(0.8, 0.7), 1, 0.6), Glyph_Line(v(-0.8, 0.7), v(0.8, -0.7), 1, 0.6) })
  end,
}

-- Which pictogram a type has, by the start of its id.
local BY_PREFIX: { { string } } = {
  { "laser.", "laser" }, { "autocannon", "gun" }, { "artillery", "gun" }, { "blaster", "hybrid" }, { "railgun", "hybrid" },
  { "launcher.", "launcher" }, { "shield.", "shield" }, { "armor.", "armor" }, { "afterburner", "engine" }, { "mwd.", "engine" }, { "capacitor.", "battery" },
  { "miner.", "miner" }, { "missile.", "missile" }, { "crystal.", "crystal" }, { "charge.", "slug" }, { "ammo.", "rounds" },
}
local BY_CATEGORY: { [string]: string } = {
  module = "gear", charge = "rounds", ore = "rock", mineral = "ingot", component = "gear", blueprint = "blueprint",
  skillbook = "book", goods = "crate", structure = "crate", planetary = "crate", moon = "rock", drone = "gear", implant = "gear",
}
local CLASS_PIPS: { [string]: number } = { frigate = 1, destroyer = 1, cruiser = 2, battleship = 3, industrial = 2, barge = 2, freighter = 3,
  attackbattlecruiser = 3, battlecruiser = 2, carrier = 3, dreadnought = 3, siegedreadnought = 3, capitalindustrial = 3, supercarrier = 3 }

-- The pictogram, the size (0 for none, else 1 to 3) and the category of
-- a type.
function ItemIcon.Parts(type: string): (string, number, string)
  local hull = Ships.byId[type]
  if hull then
    return if hull.class == "industrial" or hull.class == "barge" or hull.class == "freighter" or hull.class == "capitalindustrial"
      then "hauler" else "ship",
      CLASS_PIPS[hull.class] or 0, "ship"
  end
  local info = Types.Get(type)
  local category = if info then info.category else "goods"
  local size = if string.find(type, "large", 1, true) or string.find(type, "cruise", 1, true) or string.find(type, ".xl", 1, true)
      or string.find(type, "siege", 1, true) then 3
    elseif string.find(type, "medium", 1, true) or string.find(type, "heavy", 1, true) then 2
    elseif category == "module" or category == "charge" then 1
    else 0
  if category == "blueprint" then
    return "blueprint", 0, category
  end
  for _, pair in BY_PREFIX do
    if string.sub(type, 1, #pair[1]) == pair[1] then
      return pair[2], size, category
    end
  end
  return BY_CATEGORY[category] or "crate", size, category
end

local built: { [string]: Icon } = {}

local function pictogram(name: string): Icon
  local made: Icon? = built[name]
  if made then
    return made
  end
  local icon = Icon_Create()
  for _, glyph in (PICTOGRAMS[name] or PICTOGRAMS.crate)() do
    Icon_AddGlyph(icon, glyph)
  end
  built[name] = icon
  return icon
end

-- Draw the icon of a type with its top-left corner at (x, y), 'size'
-- pixels square.
function ItemIcon.Draw(type: string, x: number, y: number, size: number)
  local name, pips, category = ItemIcon.Parts(type)
  local tile = TILE[category] or TILE.goods
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), tile, 0.55, 0.9, math.max(2, size / 8))
  Icon_Draw(pictogram(name), vector.create(x + size / 2, y + size / 2 - (if pips > 0 then size * 0.06 else 0)), size * 0.30,
    vector.create(0.92, 0.95, 1.0), 1)
  -- size: one to three pips along the bottom
  local pip = math.max(2, size / 11)
  for index = 1, pips do
    WidgetRenderer_DrawPanel(vector.create(x + size / 2 + (index - (pips + 1) / 2) * pip * 2 - pip / 2, y + size - pip * 1.6),
      vector.create(pip, pip), vector.create(1, 1, 1), 0.9, 0.9, 0)
  end
end

return ItemIcon
