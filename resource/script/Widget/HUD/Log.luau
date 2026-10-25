--!strict
-- The player's notification log (Luau port of Widget/HUD/Log.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

local Log = {}

local function entry(index: number, message: string): Widget
  local icon = if string.find(message, "order", 1, true) then Icons.Credits()
    elseif string.find(message, "message", 1, true) then Icons.Comm()
    else Icons.Assets()
  local row = Widgets.ListH(8,
    Components.AlignCenter(Widgets.Text(Fonts.Heading(), `[{192 + index}.30.10]`, 14, Colors.Primary)),
    Components.AlignCenter(Components.MinSize(24, Widgets.Icon(icon, Colors.Primary))),
    Components.AlignCenter(Widgets.Text(Fonts.Default(), message, 16, vector.create(1, 1, 1))))
  -- Keep entries' identity across rebuilds by their text
  local text = `{index}:{message}`
  return Widget_Luau(row, {
    GetHash = function()
      local h = 5381
      for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % 4294967296
      end
      return h
    end,
  })
end

function Log.Create(player: Player): Widget
  local log = Widget_Luau(Widget_Create(), {
    GetName = function()
      return "Notifications"
    end,
    CreateChildren = function(): { Widget }
      local entries = {}
      local it = player:GetLog()
      local i = 0
      while it:HasMore() do
        table.insert(entries, entry(i, it:Get().message))
        i += 1
        it:Advance()
      end
      return entries
    end,
  })
  return Widget_Dynamic(Widget_ListVertical(8, log))
end

return Log
