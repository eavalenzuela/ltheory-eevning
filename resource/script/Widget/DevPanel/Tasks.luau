--!strict
-- The developer panel's task list (Luau port of Widget/DevPanel/Tasks.lts):
-- type a task and press ADD.

local Button = require("@lt/Widget/Button")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Header = require("@lt/Widget/DevPanel/Header")
local Icons = require("@lt/Icons")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local TextField = require("@lt/Widget/TextField")
local Widgets = require("@lt/Widgets")

type Status = "todo" | "doing" | "done"
type Task = { name: string, status: Status }

local function taskRow(task: Task): Widget
  local icon = if task.status == "todo" then Widgets.Icon(Icons.Dot(), Colors.Primary)
    elseif task.status == "doing" then Widgets.Icon(Icons.CircleDot(), Colors.Secondary)
    else Widgets.Icon(Icons.CircleDot(), Colors.Good)
  return Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.5, 1, 1, Components.Expand(Widgets.ListH(16,
    Components.Padding(vector.create(16, 12), vector.create(16, 12), Widgets.ListH(16,
      Components.AlignCenter(Components.MinSize(8, icon)),
      Components.AlignCenter(Widgets.Text(Fonts.Default(), string.upper(task.name), 14, vector.create(1, 1, 1))))))))
end

local function initialTasks(): { Task }
  local tasks: { Task } = {}
  local function add(name: string, status: Status)
    table.insert(tasks, { name = name, status = status })
  end
  for _, name in { "PBR", "GGX", "Better Lens Flare", "Lens Flare Ghosts", "Sharpen", "Motion Blur", "Film Grain",
    "Pure Linear", "PlateMesh Editor" } do
    add(name, "doing")
  end
  for _, name in { "Ship / Station Generation", "Fleets", "Observatory Sandbox", "Fleets & formation editor",
    "Decals" } do
    add(name, "todo")
  end
  add("Glow Text", "done")
  add("Triangle Glyph", "done")
  return tasks
end

return {
  Create = function(): Widget
    local tasks = initialTasks()
    local newTask: TextField.Contents = { text = "" }
    local list = Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
      CreateChildren = function(): { Widget }
        local rows = {
          Components.Margin(vector.create(0, 8), vector.create(0, 8), Components.Expand(Widgets.ListH(16,
            Components.Expand(Components.GreedyX(TextField.Create(16, newTask))),
            Components.Expand(Button.Create({ type = "AddTask" }, "ADD", 16))))),
        }
        for _, task in tasks do
          table.insert(rows, taskRow(task))
        end
        return rows
      end,
      Receive = function(_, w: Widget, message: any)
        if type(message) == "table" and message.type == "AddTask" and #newTask.text > 0 then
          local task: Task = { name = newTask.text, status = "todo" }
          table.insert(tasks, task)
          w:AddChild(taskRow(task))
        end
      end,
    }))
    return Widgets.ListV(2,
      Header.Create(Icons.Log(), "TASK MANAGER"),
      Components.Backdrop(vector.create(0.08, 0.08, 0.08), 0.75, 1, 0,
        ScrollFrame.V(Components.Margin(8, 8, Components.Expand(list)))))
  end,
}
