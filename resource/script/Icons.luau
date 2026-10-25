--!strict
-- Vector icons drawn from glyphs (Luau port of Icons.lts and
-- Icon/Cursors.lts). Each is built once on first use. Coordinates span
-- -1..1; colors and alphas here are multipliers applied when drawn.

local Icons = {}

local TAU = 2 * math.pi

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

local function polar(angle: number): vector
  return v(math.cos(angle), math.sin(angle))
end

local function build(glyphs: { Glyph }): Icon
  local icon = Icon_Create()
  for _, glyph in glyphs do
    Icon_AddGlyph(icon, glyph)
  end
  return icon
end

-- An icon accessor that builds the icon the first time it is asked for
local function cached(make: () -> Icon): () -> Icon
  local icon: Icon? = nil
  return function(): Icon
    local built = icon or make()
    icon = built
    return built
  end
end

Icons.ArrowLeft = cached(function()
  return build({ Glyph_Triangle(v(-0.75, 0), v(0.25, -0.75), v(0.25, 0.75), 1, 1) })
end)

Icons.ArrowRight = cached(function()
  return build({ Glyph_Triangle(v(0.75, 0), v(-0.25, -0.75), v(-0.25, 0.75), 1, 1) })
end)

Icons.Assets = cached(function()
  local glyphs = { Glyph_Circle(0, 1, 1, 1) }
  for i = 0, 4 do
    local offset = 0.8 * polar(TAU * i / 5)
    table.insert(glyphs, Glyph_Circle(offset, 1, 1, 1))
    table.insert(glyphs, Glyph_Line(0, offset, 1, 0.2))
  end
  return build(glyphs)
end)

Icons.Badge = cached(function()
  return build({
    Glyph_Arc(v(0, -0.3), 0.4, 0.02, 1, 1, 0.375, 0.375),
    Glyph_LineFade(v(0, 0.1), v(0, 0.6), 1, 1),
    Glyph_Circle(v(0, 0.85), 1, 1, 1),
  })
end)

Icons.Cancel = cached(function()
  return build({
    Glyph_Line(v(-0.7, -0.7), v(0.7, 0.7), 1, 1.5),
    Glyph_Line(v(0.7, -0.7), v(-0.7, 0.7), 1, 1.5),
  })
end)

Icons.CircleDot = cached(function()
  return build({ Glyph_Circle(0, 4, 1, 1), Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1) })
end)

Icons.Clock = cached(function()
  local glyphs = {
    Glyph_Circle(0, 1, 1, 1),
    Glyph_Line(0, 0.75 * polar(TAU * -3 / 12), 2, 1),
    Glyph_Line(0, 0.50 * polar(TAU * 1 / 12), 2, 1),
  }
  for i = 0, 11 do
    local size = if i % 3 == 0 then 1.5 else 0.75
    table.insert(glyphs, Glyph_Circle(polar(TAU * i / 12), 1, size, 1))
  end
  return build(glyphs)
end)

Icons.Credits = cached(function()
  return build({
    Glyph_Arc(v(0.2, 0), 0.8, 0.01, 1, 1, 0, 0.3),
    Glyph_Arc(v(0.2, 0), 0.4, 0.01, 1, 0.5, 0.5, 0.3),
    Glyph_Line(v(-1.0, 0.0), v(0.9, 0.0), 1, 1),
  })
end)

Icons.City = cached(function()
  return build({
    Glyph_Box(v(-0.8, 0.6), v(0.10, 0.4), 1, 1),
    Glyph_Box(v(-0.4, 0.7), v(0.05, 0.3), 1, 1),
    Glyph_Box(v(0.0, 0.0), v(0.10, 1.0), 1, 1),
    Glyph_Box(v(0.4, 0.3), v(0.05, 0.7), 1, 1),
    Glyph_Box(v(0.8, 0.7), v(0.05, 0.3), 1, 1),
  })
end)

Icons.Cargo = cached(function()
  return build({
    Glyph_Box(v(-0.2, -0.2), 0.1, 1, 1),
    Glyph_Box(v(-0.55, -0.2), 0.1, 1, 1),
    Glyph_Box(v(-0.2, -0.55), 0.1, 1, 1),
    Glyph_Box(v(0.4, -0.4), 0.25, 1, 1),
    Glyph_Box(v(-0.4, 0.4), 0.25, 1, 1),
    Glyph_Box(v(0.4, 0.4), 0.25, 1, 1),
  })
end)

Icons.Comm = cached(function()
  return build({
    Glyph_Circle(v(0, 0.3), 1, 1, 1),
    Glyph_Arc(v(0, 0.3), 0.3, 0.01, 1, 1, 0.25, 0.15),
    Glyph_Arc(v(0, 0.3), 0.6, 0.01, 1, 1, 0.25, 0.15),
    Glyph_Arc(v(0, 0.3), 0.9, 0.01, 1, 1, 0.25, 0.15),
  })
end)

Icons.Database = cached(function()
  local glyphs = {}
  local rng = RNG_MTG(15)
  for i = 0, 5 do
    local y = 2 * ((i + 1) / 7) - 1
    local w = rng:Float()
    table.insert(glyphs, Glyph_Box(v(w - 1, y), v(0.5 * w, 1 / 20), 1, 0.75))
    table.insert(glyphs, Glyph_Box(v(w, y), v(0.5 * (1 - w), 1 / 20), 1, 0.75))
  end
  return build(glyphs)
end)

Icons.Dot = cached(function()
  return build({ Glyph_Circle(0, 4, 1, 1) })
end)

Icons.ExclamationMark = cached(function()
  return build({
    Glyph_Box(v(0, -0.25), v(0.05, 0.5), 1, 1),
    Glyph_Circle(v(0, 0.95), 1.5, 1, 1),
  })
end)

Icons.Gear = cached(function()
  local glyphs = { Glyph_Arc(0, 0.5, 0.1, 1, 1, 0, 1) }
  for i = 0, 7 do
    table.insert(glyphs, Glyph_Arc(0, 0.8, 0.1, 1, 1, i / 8, 0.15 / 8))
  end
  return build(glyphs)
end)

Icons.Hardpoints = cached(function()
  local glyphs = { Glyph_Circle(0, 1, 1, 1) }
  for i = 0, 3 do
    local offset = 0.9 * polar(TAU * i / 4)
    table.insert(glyphs, Glyph_Arc(offset, 0.1, 0.01, 1, 1, 0, 1))
    table.insert(glyphs, Glyph_Line(0, offset, 1, 0.2))
  end
  return build(glyphs)
end)

Icons.Hexagon = cached(function()
  local glyphs = {}
  for i = 0, 5 do
    local p1 = 1.1 * polar(TAU * (i + 0.65) / 6)
    local p2 = 1.1 * polar(TAU * (i + 1.35) / 6)
    table.insert(glyphs, Glyph_Circle(1.1 * polar(TAU * (i + 0.5) / 6), 0.5, 1, 2))
    table.insert(glyphs, Glyph_Line(p1, p2, 1, 1.5))
  end
  return build(glyphs)
end)

Icons.JumpTo = cached(function()
  return build({
    Glyph_Circle(v(-0.7, 0), 1, 1, 1),
    Glyph_Arc(v(0.7, 0), 0.1, 0.01, 1, 1, 0, 1),
    Glyph_LineFade(v(0.3, 0), v(-0.5, 0), 1, 1),
    Glyph_LineFade(v(0.3, 0), v(0, 0.2), 1, 1),
    Glyph_LineFade(v(0.3, 0), v(0, -0.2), 1, 1),
  })
end)

Icons.Lock = cached(function()
  return build({
    Glyph_Arc(v(0, -0.3), 0.5, 0.1, 1, 1, 0.25, 0.25),
    Glyph_Box(v(0, 0.3), v(0.8, 0.5), 1, 1),
  })
end)

Icons.Log = cached(function()
  local glyphs = {}
  for i = 0, 4 do
    local y = 2 * ((i + 1) / 6) - 1
    table.insert(glyphs, Glyph_Circle(v(-0.75, y), 1, 1, 1))
    table.insert(glyphs, Glyph_Line(v(-0.30, y), v(0.75, y), 1, 0.5))
  end
  return build(glyphs)
end)

Icons.MagnifyingGlass = cached(function()
  return build({
    Glyph_Arc(v(0.3, -0.3), 0.4, 0.05, 1, 1, 0, 1),
    Glyph_LineFade(v(-0.7, 0.7), v(-0.1, 0.1), 1, 2),
    Glyph_Circle(v(-0.7, 0.7), 1, 1, 1),
  })
end)

Icons.Mail = cached(function()
  return build({
    Glyph_Box(0, v(0.9, 0.5), 1, 0.1),
    Glyph_Line(v(-0.9, -0.5), v(0.0, 0.1), 1, 0.8),
    Glyph_Line(v(0.9, -0.5), v(0.0, 0.1), 1, 0.8),
    Glyph_Line(v(-0.9, -0.5), v(0.9, -0.5), 1, 0.3),
    Glyph_Line(v(-0.9, 0.5), v(0.9, 0.5), 1, 0.3),
    Glyph_Line(v(-0.9, 0.5), v(-0.9, -0.5), 1, 0.3),
    Glyph_Line(v(0.9, 0.5), v(0.9, -0.5), 1, 0.3),
  })
end)

Icons.Medic = cached(function()
  return build({
    Glyph_Box(0, v(0.50, 0.15), 1, 1),
    Glyph_Box(0, v(0.15, 0.50), 1, 1),
    Glyph_Arc(0, 0.9, 0.01, 1, 1, 0, 1),
  })
end)

Icons.Person = cached(function()
  local icon = build({
    Glyph_Circle(v(0, -0.6), 3.5, 1, 0.5),
    Glyph_Arc(v(0, -0.6), 0.40, 0.01, 1, 1, 0.75, 0.1),
    Glyph_LineFade(v(-0.25, -0.2), v(0, 0.8), 1, 1),
    Glyph_LineFade(v(0.25, -0.2), v(0, 0.8), 1, 1),
    Glyph_Circle(v(-0.4, 0.2), 1, 1, 1),
    Glyph_Circle(v(0.4, 0.2), 1, 1, 1),
  })
  Icon_Transform(icon, 0, 1.25)
  return icon
end)

Icons.Planet = cached(function()
  return build({
    Glyph_Arc(0, 0.9, 0.01, 1, 1, 0, 1),
    Glyph_Arc(0.6, 1.0, 0.01, 1, 1, 0.25, 0.1),
    Glyph_Arc(-0.6, 1.0, 0.01, 1, 1, 0.75, 0.1),
  })
end)

Icons.QuestionMark = cached(function()
  return build({
    Glyph_Arc(v(0, -0.5), 0.4, 0.02, 1, 1, 0.375, 0.375),
    Glyph_LineFade(v(0, 0.0), v(0, 0.4), 1, 1),
    Glyph_Circle(v(0, 0.8), 1.5, 1, 1),
  })
end)

Icons.Refresh = cached(function()
  return build({
    Glyph_Arc(0, 0.7, 0.01, 1, 1, 0.0, 0.15),
    Glyph_Arc(0, 0.7, 0.01, 1, 1, 0.5, 0.15),
    Glyph_LineFade(0.7 * polar(TAU * 0.15), 1.0 * polar(TAU * 0.1), 1, 1),
    Glyph_LineFade(0.7 * polar(TAU * 0.15), 0.4 * polar(TAU * 0.1), 1, 1),
    Glyph_LineFade(0.7 * polar(TAU * 0.65), 1.0 * polar(TAU * 0.6), 1, 1),
    Glyph_LineFade(0.7 * polar(TAU * 0.65), 0.4 * polar(TAU * 0.6), 1, 1),
  })
end)

Icons.Scanner = cached(function()
  return build({
    Glyph_Arc(0, 0.00, 0.05, 1, 1, 0.0, 1.0),
    Glyph_Arc(0, 0.3, 0.01, 1, 1, 0.0, 0.1),
    Glyph_Arc(0, 0.6, 0.01, 1, 1, 0.0, 0.1),
    Glyph_Arc(0, 0.9, 0.01, 1, 1, 0.0, 0.1),
    Glyph_Arc(0, 0.3, 0.01, 1, 1, 0.5, 0.1),
    Glyph_Arc(0, 0.6, 0.01, 1, 1, 0.5, 0.1),
    Glyph_Arc(0, 0.9, 0.01, 1, 1, 0.5, 0.1),
    Glyph_LineFade(0, v(0, 0.9), 1, 1),
  })
end)

Icons.Smiley = cached(function()
  return build({
    Glyph_Circle(v(-0.5, -0.5), 2, 1, 1),
    Glyph_Circle(v(0.5, -0.5), 2, 1, 1),
    Glyph_Arc(0, 0.7, 0.1, 1, 1, 0.75, 0.2),
  })
end)

Icons.Star = cached(function()
  local glyphs = {}
  for i = 0, 4 do
    local center = polar(TAU * (i - 0.25) / 5)
    local left = polar(TAU * (i - 0.4 - 0.25) / 5)
    local right = polar(TAU * (i + 0.4 - 0.25) / 5)
    table.insert(glyphs, Glyph_LineFade(0.25 * left, center, 1, 0.75))
    table.insert(glyphs, Glyph_LineFade(0.25 * right, center, 1, 0.75))
  end
  return build(glyphs)
end)

Icons.Station = cached(function()
  local glyphs = {
    Glyph_Arc(0, 0.8, 0.05, 1, 0.8, 0.0, 1.0),
    Glyph_Arc(0, 0.4, 0.05, 1, 0.8, 0.0, 1.0),
  }
  for i = 0, 7 do
    table.insert(glyphs, Glyph_Arc(0, 0.9, 0.1, 1, 0.8, i / 8, 1 / 64))
  end
  for i = 0, 2 do
    table.insert(glyphs, Glyph_Arc(0, 0.6, 0.2, 1, 0.8, 0.25 + i / 3, 0.001))
  end
  return build(glyphs)
end)

-- A ring with four inward ticks
local function crosshair(): Icon
  local glyphs = { Glyph_Ring(0, 0.6, 1, 1, 0) }
  for i = 0, 3 do
    local offset = polar(TAU * i / 4 + 0.25 * math.pi)
    table.insert(glyphs, Glyph_LineFade(0.8 * offset, 0.3 * offset, 2, 1))
  end
  return build(glyphs)
end

Icons.Target = cached(crosshair)
Icons.Turret = cached(crosshair)

Icons.Trade = cached(function()
  return build({
    Glyph_LineFade(v(0.8, -0.5), v(-0.8, -0.5), 1, 1),
    Glyph_LineFade(v(-0.8, 0.5), v(0.8, 0.5), 1, 1),
    Glyph_LineFade(v(0.8, -0.5), v(0.3, -0.8), 1, 1),
    Glyph_LineFade(v(-0.8, 0.5), v(-0.3, 0.8), 1, 1),
    Glyph_LineFade(v(-0.3, 0.3), v(-0.3, 0.0), 2, 1),
    Glyph_LineFade(v(0.0, 0.3), v(0.0, -0.2), 2, 1),
    Glyph_LineFade(v(0.3, 0.3), v(0.3, -0.4), 2, 1),
  })
end)

Icons.Wormhole = cached(function()
  local glyphs = { Glyph_Circle(0, 2, 1, 1) }
  for i = 0, 6 do
    local offset = polar(TAU * i / 7)
    table.insert(glyphs, Glyph_LineFade(0.9 * offset, 0.6 * offset, 2, 1))
  end
  return build(glyphs)
end)

--------------------------------------------------------------- Cursors

Icons.Cursors = {
  Cross = cached(function()
    return build({
      Glyph_LineFade(v(-1, 0), 0, 1, 1),
      Glyph_LineFade(v(1, 0), 0, 1, 1),
      Glyph_LineFade(v(0, -1), 0, 1, 1),
      Glyph_LineFade(v(0, 1), 0, 1, 1),
    })
  end),
  Pointer = cached(function()
    return build({
      Glyph_LineFade(0, v(1, 2), 1, 1),
      Glyph_LineFade(0, v(2, 1), 1, 1),
    })
  end),
}

return Icons
