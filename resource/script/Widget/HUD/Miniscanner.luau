--!strict
-- A live spectrum of the ship's scanner output (Luau port of
-- Widget/HUD/Miniscanner.lts); click to open the scanner.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Messages = require("@lt/Widget/Messages")

local Miniscanner = {}

local Scanner = require("@lt/Widget/Scanner")

local RESOLUTION = 64

function Miniscanner.Create(player: Player, object: Object): Widget
  local output = Object_GetScannerOutput(object, RESOLUTION)
  local latest = output
  local time, timer = 0, 0
  local scanner: Widget? = nil
  local box = Glyph_Box(0, 1, 1, 1)
  local widget = Widget_Create()
  Widget_Luau(widget, {
    GetName = function()
      return "Mini-Scanner"
    end,
    PostDraw = function(_, w: Widget)
      local dy = 0.5 * w.size.y
      local y = w.pos.y + dy
      local color = 2 * (if w.focusMouse then Colors.Secondary else Colors.Primary)
      Glyph_Draw(Glyph_Line(w:LeftCenter(), w:RightCenter(), 1, 1), 0, 1, Colors.Primary, 0.5)

      local count = output:Size()
      local barWidth = 0.45 * w.size.x / math.max(1, count - 1)
      local last0, last1 = vector.create(0, 0), vector.create(0, 0)
      for i = 0, count - 1 do
        local t = i / count
        local x = w.pos.x + w.size.x * t
        local v = 1 - Float_ExpDecay(output:Get(i), 3)
        v += 0.25 * (0.5 + 0.5 * math.sin(3 * time + 32 * t)) * (1 - t)
        local p0 = vector.create(x, y - v * dy)
        local p1 = vector.create(x, y + v * dy)
        local p2 = vector.create(x, y)
        if i > 0 then
          Glyph_Draw(Glyph_Line(last0, p0, 1, 1), 0, 1, color, 0.5)
          Glyph_Draw(Glyph_Line(last1, p1, 1, 1), 0, 1, color, 0.125)
        end
        Glyph_Draw(box, 0.5 * (p2 + p0), vector.create(barWidth, 0.5 * math.abs(p0.y - p2.y)), color, 0.05)
        Glyph_Draw(box, 0.5 * (p2 + p1), vector.create(barWidth, 0.5 * math.abs(p1.y - p2.y)), color, 0.0125)
        last0, last1 = p0, p1
      end
    end,
    PreUpdate = function()
      local dt = FrameTimer_Get()
      timer -= dt
      if timer < 0 then
        latest = Object_GetScannerOutput(object, RESOLUTION)
        timer = 1
      end
      output:Blend(latest, 1 - Float_ExpDecay(dt, 0.25))
      time += dt
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Click" then
        if scanner and scanner:HasParent() then
          scanner:Delete()
          scanner = nil
        else
          local window = Scanner.Create(player, object)
          scanner = window
          w:SendUp(Messages.AddWidget(window))
        end
      end
    end,
  })
  return Components.CaptureMouse(Components.Clickable({ type = "Click" }, widget, widget))
end

return Miniscanner
