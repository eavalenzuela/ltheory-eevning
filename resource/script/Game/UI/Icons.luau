--!strict
-- The interface's own signs: one for each of the dock's buttons, and the
-- few a window's frame wants (to shut it, to pause). Each is a handful
-- of lines and rings in a square from -1 to 1, made once and drawn at
-- whatever size it is wanted (as Game/UI/ItemIcon makes an item's).
--
--   Icons.Draw("market", cx, cy, 11, Theme.DIM, 1)

local Icons = {}

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

-- A line from point to point through some points; and the same, closed.
local function path(points: { vector }, closed: boolean?): { Glyph }
  local out: { Glyph } = {}
  for index = 1, #points - 1 do
    table.insert(out, Glyph_Line(points[index], points[index + 1], 1, 1))
  end
  if closed then
    table.insert(out, Glyph_Line(points[#points], points[1], 1, 1))
  end
  return out
end

local function all(...: { Glyph }): { Glyph }
  local out: { Glyph } = {}
  for _, part in { ... } do
    for _, glyph in part do
      table.insert(out, glyph)
    end
  end
  return out
end

local function line(ax: number, ay: number, bx: number, by: number): { Glyph }
  return { Glyph_Line(v(ax, ay), v(bx, by), 1, 1) }
end

local function ring(x: number, y: number, radius: number): { Glyph }
  return { Glyph_Ring(v(x, y), radius, 1, 1, 0) }
end

local function dot(x: number, y: number, radius: number): { Glyph }
  return { Glyph_Circle(v(x, y), radius, 1, 1) }
end

local SIGNS: { [string]: () -> { Glyph } } = {
  -- a crate, seen from its corner
  inventory = function()
    return all(path({ v(-0.8, -0.4), v(0, -0.8), v(0.8, -0.4), v(0.8, 0.4), v(0, 0.8), v(-0.8, 0.4) }, true),
      path({ v(-0.8, -0.4), v(0, 0), v(0.8, -0.4) }), line(0, 0, 0, 0.8))
  end,
  -- bars on a line
  market = function()
    return all(line(-0.9, 0.8, 0.9, 0.8), line(-0.6, 0.8, -0.6, 0.1), line(-0.15, 0.8, -0.15, -0.6), line(0.3, 0.8, 0.3, -0.1),
      line(0.75, 0.8, 0.75, -0.35))
  end,
  -- the fitting's wheel
  fitting = function()
    return all(ring(0, 0, 0.62), dot(0, 0, 0.14), line(0, -0.95, 0, -0.62), line(0, 0.62, 0, 0.95), line(-0.95, 0, -0.62, 0),
      line(0.62, 0, 0.95, 0))
  end,
  -- a hull, bow up
  ships = function()
    return path({ v(0, -0.9), v(0.6, 0.8), v(0, 0.4), v(-0.6, 0.8) }, true)
  end,
  -- a works: a saw-toothed roof and a stack
  industry = function()
    return all(path({ v(-0.9, 0.8), v(-0.9, -0.1), v(-0.4, 0.2), v(-0.4, -0.1), v(0.1, 0.2), v(0.1, -0.7), v(0.7, -0.7), v(0.7, 0.8) }),
      line(-0.95, 0.8, 0.95, 0.8))
  end,
  -- a sheet on a board
  jobs = function()
    return all(path({ v(-0.55, -0.65), v(0.55, -0.65), v(0.55, 0.85), v(-0.55, 0.85) }, true),
      path({ v(-0.25, -0.9), v(0.25, -0.9), v(0.25, -0.5), v(-0.25, -0.5) }, true), line(-0.25, -0.05, 0.25, -0.05),
      line(-0.25, 0.25, 0.25, 0.25), line(-0.25, 0.55, 0.05, 0.55))
  end,
  -- a book
  skills = function()
    return all(path({ v(-0.65, -0.75), v(0.65, -0.75), v(0.65, 0.8), v(-0.65, 0.8) }, true), line(-0.3, -0.75, -0.3, 0.8),
      line(0, -0.35, 0.4, -0.35))
  end,
  -- a coin
  wallet = function()
    return all(ring(0, 0, 0.78), path({ v(-0.22, -0.22), v(0.22, -0.22), v(0.22, 0.22), v(-0.22, 0.22) }, true))
  end,
  -- somebody
  crew = function()
    return all(ring(0, -0.42, 0.34), path({ v(-0.72, 0.85), v(-0.62, 0.35), v(-0.3, 0.12), v(0.3, 0.12), v(0.62, 0.35), v(0.72, 0.85) }))
  end,
  -- a house of business
  corporation = function()
    return all(path({ v(-0.7, 0.8), v(-0.7, -0.45), v(0, -0.85), v(0.7, -0.45), v(0.7, 0.8) }), line(-0.95, 0.8, 0.95, 0.8),
      line(-0.35, -0.15, -0.1, -0.15), line(0.1, -0.15, 0.35, -0.15), line(-0.35, 0.2, -0.1, 0.2), line(0.1, 0.2, 0.35, 0.2),
      path({ v(-0.15, 0.8), v(-0.15, 0.5), v(0.15, 0.5), v(0.15, 0.8) }))
  end,
  -- stars and the ways between them
  map = function()
    return all(ring(-0.62, -0.55, 0.17), ring(0.62, -0.28, 0.17), ring(-0.28, 0.6, 0.17), dot(0.58, 0.66, 0.09),
      line(-0.45, -0.51, 0.45, -0.32), line(-0.57, -0.38, -0.33, 0.43), line(-0.15, 0.48, 0.5, -0.15), line(-0.1, 0.61, 0.49, 0.65))
  end,
  -- a scanner's dish
  scanner = function()
    return all(ring(0, 0, 0.8), ring(0, 0, 0.4), line(0, 0, 0.56, -0.56), dot(0.36, 0.26, 0.09))
  end,
  -- a world and what goes round it
  colonies = function()
    return all(ring(0, 0, 0.55), line(-0.95, 0.34, -0.52, 0.18), line(0.52, -0.2, 0.95, -0.42))
  end,
  -- a bell
  events = function()
    return all(path({ v(-0.6, 0.45), v(-0.6, -0.1), v(-0.35, -0.6), v(0, -0.75), v(0.35, -0.6), v(0.6, -0.1), v(0.6, 0.45), v(0.8, 0.62),
      v(-0.8, 0.62) }, true), line(-0.16, 0.85, 0.16, 0.85))
  end,
  -- a question
  guide = function()
    return all(ring(0, 0, 0.8), path({ v(-0.26, -0.28), v(-0.12, -0.48), v(0.14, -0.48), v(0.28, -0.28), v(0.2, -0.08), v(0, 0.06),
      v(0, 0.2) }), dot(0, 0.44, 0.07))
  end,
  menu = function()
    return all(line(-0.7, -0.5, 0.7, -0.5), line(-0.7, 0, 0.7, 0), line(-0.7, 0.5, 0.7, 0.5))
  end,
  -- a window's own
  close = function()
    return all(line(-0.6, -0.6, 0.6, 0.6), line(-0.6, 0.6, 0.6, -0.6))
  end,
  pause = function()
    return all(line(-0.35, -0.6, -0.35, 0.6), line(0.35, -0.6, 0.35, 0.6))
  end,
  run = function()
    return path({ v(-0.4, -0.65), v(0.55, 0), v(-0.4, 0.65) }, true)
  end,
  minus = function()
    return line(-0.6, 0, 0.6, 0)
  end,
  -- (what is folded, and what is laid open)
  right = function()
    return path({ v(-0.3, -0.6), v(0.35, 0), v(-0.3, 0.6) })
  end,
  down = function()
    return path({ v(-0.6, -0.3), v(0, 0.35), v(0.6, -0.3) })
  end,
  up = function()
    return path({ v(-0.6, 0.3), v(0, -0.35), v(0.6, 0.3) })
  end,
  search = function()
    return all(ring(-0.15, -0.15, 0.55), line(0.25, 0.25, 0.8, 0.8))
  end,
  info = function()
    return all(ring(0, 0, 0.8), line(0, -0.1, 0, 0.45), dot(0, -0.42, 0.07))
  end,
  plus = function()
    return all(line(-0.6, 0, 0.6, 0), line(0, -0.6, 0, 0.6))
  end,
}

local built: { [string]: Icon } = {}

function Icons.Has(name: string): boolean
  return SIGNS[name] ~= nil
end

-- Draw a sign about (cx, cy), 'half' pixels from its middle to its edge.
function Icons.Draw(name: string, cx: number, cy: number, half: number, color: vector, alpha: number?)
  local icon: Icon? = built[name]
  if icon == nil then
    local made = Icon_Create()
    local sign = SIGNS[name]
    if sign then
      for _, glyph in sign() do
        Icon_AddGlyph(made, glyph)
      end
    end
    built[name] = made
    icon = made
  end
  Icon_Draw(icon :: Icon, vector.create(cx, cy), half, color, alpha or 1)
end

return Icons
