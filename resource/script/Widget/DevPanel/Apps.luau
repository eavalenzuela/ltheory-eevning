--!strict
-- The developer panel's list of apps (Luau port of
-- Widget/DevPanel/Apps.lts): every App/*.luau and App/*.lts.

local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Header = require("@lt/Widget/DevPanel/Header")
local Icons = require("@lt/Icons")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Widgets = require("@lt/Widgets")

local Apps = {}

-- App names, without extensions, sorted
function Apps.List(): { string }
  local seen: { [string]: boolean } = {}
  local names: { string } = {}
  local files = Directory_List("resource/script/App/")
  for i = 0, files.size - 1 do
    local name = string.match(files:Get(i), "^(.*)%.luau$") or string.match(files:Get(i), "^(.*)%.lts$")
    if name and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function Apps.Create(): Widget
  local list = Widget_ListVertical(4, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local rows = {}
      for _, name in Apps.List() do
        table.insert(rows, Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.1, 1, 4,
          Components.Padding(8, 8, Components.Expand(Widgets.Stack(
            Widgets.Text(Fonts.Default(), string.upper(name), 14, vector.create(1, 1, 1)))))))
      end
      return rows
    end,
  }))
  return Widgets.ListV(2,
    Header.Create(Icons.Gear(), "APPLICATIONS"),
    ScrollFrame.V(Components.Margin(8, 8, Components.Expand(list))))
end

return Apps
