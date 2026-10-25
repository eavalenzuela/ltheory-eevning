--!strict
-- The central reticle: speed and integrity gauges, rotation hints and
-- target pointers with lead marks (Luau port of Widget/Reticle/Default.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

local Reticle = {}

local TAU = 2 * math.pi

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

local function polar(angle: number): vector
  return vector.create(math.cos(angle), math.sin(angle))
end

local function arc(angle: number, size: number): Glyph
  return Glyph_Arc(0, 1, 0.001, 1, 1, angle, size)
end

function Reticle.Create(_player: Player, object: Object): Widget
  local reticle = Widget_Luau(Widget_Create(), {
    GetName = function()
      return "Reticle"
    end,
    PostDraw = function(_, w: Widget)
      local pos = w:Center()
      local color = 2 * Colors.Primary
      local r1 = math.min(w.size.x, w.size.y) / 2
      local offset = 0.5 * vector.create(math.max(0, w.size.x - w.size.y), 0)
      local opacity = 0.5 * w.alpha
      local white = vector.create(1, 1, 1)

      -- Center
      for i = 0, 2 do
        Glyph_Draw(Glyph_Arc(0, 1, 0.2, 1, 1, (i / 3 + 0.25) % 1, 0.001), pos, 24, color, opacity)
      end

      -- Velocity, on the left
      local v = math.clamp(2 * object:GetSpeed() / object:GetTopSpeed(), 0, 1)
      Glyph_Draw(arc(0.9 + 0.1 * v, 0.1 * v), pos - offset, r1, color, v * opacity)
      WidgetRenderer_DrawText(Fonts.Default(), `{math.round(object:GetSpeed())}m/s`,
        pos - offset - vector.create(64 + r1, 0), 12, white, v, false)
      for i = 0, 4 do
        local p = pos - offset - r1 * polar(TAU * mix(-0.1, 0.1, i / 4))
        Glyph_Draw(Glyph_LineFade(p, p - vector.create(8, 0), 1, 1), 0, 1, color, w.alpha)
      end

      -- Integrity, on the right
      local h = object:GetHealthNormalized()
      local integrity = 2 * (Colors.Bad + (Colors.Good - Colors.Bad) * (h * h))
      Glyph_Draw(arc(0.6 - 0.1 * h, 0.1 * h), pos + offset, r1, integrity, opacity)
      for i = 0, 4 do
        local p = pos + offset + r1 * polar(TAU * mix(0.1, -0.1, i / 4))
        Glyph_Draw(Glyph_LineFade(p, p + vector.create(8, 0), 1, 1), 0, 1, integrity, w.alpha)
        WidgetRenderer_DrawText(Fonts.Heading(), `{math.round(100 * i / 4)}%`, p + vector.create(24, 0), 12, white, 0.5 * w.alpha, false)
      end

      -- Roll rate
      local spin = object:GetVelocityAngular()
      local rollLeft = 1 - Float_ExpDecay(math.max(0, -spin.z), 2)
      local rollRight = 1 - Float_ExpDecay(math.max(0, spin.z), 2)
      Glyph_Draw(arc(0, 0.1 * rollLeft), pos - offset, 112, color, rollLeft * opacity)
      Glyph_Draw(arc(0.5, 0.1 * rollRight), pos + offset, 112, color, rollRight * opacity)

      -- Pointers toward targets, with lead marks where to aim
      local cam = Camera_Get()
      if not cam then
        return
      end
      local speed = 1000
      local sockets = object:GetSockets()
      while sockets:HasMore() do
        local s = sockets:Get()
        if s and s:IsTurret() and s:GetSockets():HasMore() then
          local mount = s:GetSockets():Get()
          local mountType = mount and mount:GetSupertype()
          if mountType and mountType:HasSpeed() then
            speed = mountType:GetSpeed()
          end
        end
        sockets:Advance()
      end

      local targets = object:GetTargets()
      while targets:HasMore() do
        local target = targets:Get()
        local pointer = 2 * Colors.Secondary
        local to = vector.normalize(target:GetPos() - cam:GetPos())
        local relative = vector.create(vector.dot(to, cam:GetRight()), -vector.dot(to, cam:GetUp()))
        local length = vector.magnitude(relative)
        local n = if length > 0 then relative / length else vector.create(0, 0)
        local p0 = pos + n * 164
        local alpha = 1 - Float_ExpDecay(math.max(0, length - 0.15), 0.1)
        Glyph_Draw(Glyph_LineFade(p0, p0 - 16 * n, 1, 1), 0, 1, pointer, alpha)
        Icon_Draw(target:GetIcon(), pos + n * 132, 12, pointer, alpha)

        local impact = GetImpact(object:GetPos(), target:GetPos(), object:GetVelocity(), target:GetVelocity(), speed)
        if impact.t > 0 then
          local projected = cam:Project(impact.position)
          if projected.z > 0 then
            Icon_Draw(Icons.Cancel(), Position_Frame(projected), 8, Colors.Hostile, 1)
          end
        end
        targets:Advance()
      end
    end,
  })
  return Components.Expand(reticle)
end

return Reticle
