--!strict
-- A ring menu around a point (Luau port of Widget/RadialList.lts): its
-- children sit on a circle, each in its own segment; moving the cursor
-- away from the center focuses the nearest segment.

local Colors = require("@lt/Colors")

local RadialList = {}

local SEPARATION = 6

-- Fraction of a turn for child 'i' of 'count', starting at the top
local function turn(i: number, count: number): number
  return (i / count - 0.25) % 1
end

local function direction(t: number): vector
  local angle = 2 * math.pi * t
  return vector.create(math.cos(angle), math.sin(angle))
end

-- 'widget' laid out as a ring of radius 'radius'
function RadialList.Create(radius: number, widget: Widget): Widget
  return Widget_Luau(widget, {
    Create = function()
      Sound_Play("ui/objectmenuopen.wav", 0.4)
    end,
    Destroy = function()
      Sound_Play("ui/objectmenuclose.wav", 0.4)
    end,
    PreDraw = function(_, w: Widget)
      local center = w.pos
      WidgetRenderer_DrawPanelRadial(center, 0.5 * radius, radius, 0, 1, 0.03, 1, 0, 0)
      local children = w:GetChildren()
      local count = children:Size()
      local i = 0
      while children:HasMore() do
        local child = children:Get()
        local t = turn(i, count)
        local c = if child.focusMouse then Colors.Primary else vector.create(0.05, 0.05, 0.05)
        WidgetRenderer_DrawPanelRadial(center + direction(t) * SEPARATION,
          0.5 * radius, radius - SEPARATION, t, 1 / count, c, 1, 1, 0)
        i += 1
        children:Advance()
      end
    end,
    PrePosition = function(_, w: Widget)
      w.minSize = vector.create(radius, radius)
    end,
    PostPosition = function(_, w: Widget)
      local children = w:GetChildren()
      local count = children:Size()
      local i = 0
      while children:HasMore() do
        local child = children:Get()
        child.pos += w.pos + 0.75 * radius * direction(turn(i, count))
        i += 1
        children:Advance()
      end
    end,
    PreUpdate = function(_, w: Widget)
      local children = w:GetChildren()
      local count = children:Size()
      local toCursor = Cursor_Get() - w.pos
      if count == 0 or vector.magnitude(toCursor) <= 0.5 * radius then
        return
      end
      local closest: Widget? = nil
      local best = -math.huge
      local i = 0
      while children:HasMore() do
        local d = vector.dot(toCursor, direction(turn(i, count)))
        if d > best then
          best = d
          closest = children:Get()
        end
        i += 1
        children:Advance()
      end
      if closest then
        closest.focusMouse = true
      end
    end,
  })
end

return RadialList
