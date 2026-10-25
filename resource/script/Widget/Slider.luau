--!strict
-- An integer slider with min / step / max buttons (Luau port of
-- Widget/Slider.lts). Its value is read with Messages.GetLabel(widget,
-- label) from inside or above it.

local Button = require("@lt/Widget/Button")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Messages = require("@lt/Widget/Messages")

local Slider = {}

type Step = { type: "SliderStep", step: "min" | "down" | "up" | "max" }
type Set = { type: "SliderSet", value: number }

local function bar(label: string, minValue: number, maxValue: number): Widget
  local box = Glyph_Box(0.5, vector.create(0.5, 1), 1, 1)
  local marker = Glyph_Triangle(vector.create(0, 1), vector.create(-0.8, 0), vector.create(0.8, 0), 1, 1)
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local value = tonumber(Messages.GetLabel(w, label)) or minValue
      local range = math.max(1, maxValue - minValue)
      local t = (value - minValue) / range
      local markerWidth = math.max(8, w.size.x / (maxValue - minValue + 1))
      local c = if w.focusMouse then Colors.Secondary else Colors.Primary
      Glyph_Draw(box, w.pos + vector.create(0, 0.5 * w.size.y), vector.create(w.size.x, 1), c, 1)
      Glyph_Draw(marker,
        vector.create(w.pos.x + t * (w.size.x - markerWidth), w.pos.y),
        vector.create(markerWidth, 0.5 * w.size.y), 2 * c, 1)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftDown() then
        local t = (Cursor_Get().x - w.pos.x) / w.size.x
        local value = math.floor(minValue + (maxValue + 1 - minValue) * t)
        local set: Set = { type = "SliderSet", value = math.clamp(value, minValue, maxValue) }
        w:SendUp(set)
      end
    end,
  })
end

-- A slider named 'label' over minValue..maxValue, starting at 'value'
function Slider.Create(label: string, minValue: number, maxValue: number, value: number?): Widget
  local current = value or minValue
  local function step(kind: "min" | "down" | "up" | "max", text: string, size: number): Widget
    local message: Step = { type = "SliderStep", step = kind }
    return Button.Create(message, text, size)
  end

  local slider = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        step("min", "<<", 12),
        step("down", "<", 12),
        Components.CaptureMouse(Components.Expand(Components.GreedyX(
          Components.MinSize(vector.create(64, 0), bar(label, minValue, maxValue))))),
        step("up", ">", 10),
        step("max", ">>", 10),
      }
    end,
    Receive = function(_, _w: Widget, message: any)
      if Messages.Is(message, "GetLabel") then
        if message.label == label then
          message.contents = current
        end
      elseif type(message) == "table" and message.type == "SliderStep" then
        local s = (message :: Step).step
        if s == "min" then
          current = minValue
        elseif s == "max" then
          current = maxValue
        elseif s == "down" then
          current = math.clamp(current - 1, minValue, maxValue)
        else
          current = math.clamp(current + 1, minValue, maxValue)
        end
        Sound_Play("ui/click_off.wav", 0.1)
      elseif type(message) == "table" and message.type == "SliderSet" then
        current = (message :: Set).value
      end
    end,
  })
  return Widget_ListHorizontal(0, slider)
end

return Slider
