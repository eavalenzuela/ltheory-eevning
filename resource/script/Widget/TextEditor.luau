--!strict
-- A read-only, line-numbered view of a text file in two scrolling panes
-- (Luau port of Widget/TextEditor.lts).

local Components = require("@lt/Widget/Components")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Widgets = require("@lt/Widgets")

local TextEditor = {}

local function lines(path: string): Widget
  return Widget_ListVertical(2, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local numbers = Font_Get("SourceCodePro/Bold.ttf")
      local text = Font_Get("SourceCodePro/Light.ttf")
      local rows = {}
      local contents = String_SplitLines(File_Read(path))
      for i = 0, contents.size - 1 do
        table.insert(rows, Widgets.ListH(0,
          Components.Expand(Components.MinSize(vector.create(32, 0),
            Widgets.Text(numbers, tostring(i + 1), 14, vector.create(0.2, 0.2, 0.2)))),
          Widgets.Text(text, contents:Get(i), 14, vector.create(1, 1, 1))))
      end
      return rows
    end,
  }))
end

local function pane(path: string): Widget
  return Components.Expand(Components.GreedyX(ScrollFrame.V(Components.Margin(8, 8, lines(path)))))
end

function TextEditor.Create(path: string): Widget
  return Components.Backdrop(vector.create(0.15, 0.15, 0.15), 0.5, 1, 0, Components.Expand(Widgets.ListV(0,
    Components.Expand(Components.GreedyY(Widgets.ListH(0, pane(path), pane(path)))),
    Components.Expand(Components.Backdrop(vector.create(0.1, 0.1, 0.1), 1, 1, 0,
      Components.MinSize(24, Widget_Create()))))))
end

return TextEditor
