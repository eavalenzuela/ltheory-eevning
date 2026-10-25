--!strict
-- Widget showcase (Luau port of App/ui.lts): a draggable window with a
-- slider and icons, and a text editor window showing a script. P shows a
-- sample modal prompt (commented out in the LTSL version).

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Desktop = require("@lt/Widget/Desktop")
local Fonts = require("@lt/Fonts")
local IconButton = require("@lt/Widget/IconButton")
local Icons = require("@lt/Icons")
local Slider = require("@lt/Widget/Slider")
local TextEditor = require("@lt/Widget/TextEditor")
local Widgets = require("@lt/Widgets")
local Window = require("@lt/Widget/Window")

local white = vector.create(1, 1, 1)

local function icon(i: Icon, size: number): Widget
  return Components.AlignCenter(Components.MinSize(size, Widgets.Icon(i, Colors.Primary)))
end

local function windowList(): Widget
  return Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Widgets.SpacerH(32),
        Components.MinSize(vector.create(256, 0), Components.Expand(Slider.Create("myslide", 0, 128))),
        Widgets.SpacerH(32),
        Widgets.SpacerH(32),
        icon(Icons.Clock(), 32),
        icon(Icons.Clock(), 48),
        icon(Icons.Clock(), 64),
        icon(Icons.Database(), 64),
        icon(Icons.Medic(), 64),
      }
    end,
  }))
end

-- An icon in two thin rings
local function circleIcon(i: Icon): Widget
  local arc = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local c = 2 * Colors.Primary
      Glyph_Draw(arc, w:Center(), 0.5 * w.size, c, 0.025)
      Glyph_Draw(arc, w:Center(), 0.625 * w.size, c, 0.0125)
      Icon_Draw(i, w:Center(), 0.4 * w.size, c, 1)
    end,
  })
end

-- A modal prompt with two choices; either closes it
local function createPrompt(title: string, contents: Widget, option1: string, option2: string): Widget
  local function choice(i: Icon, text: string): Widget
    return Components.Expand(Components.GreedyX(Components.MinSize(48, Components.AlignCenter(
      IconButton.CreateText({ type = "PromptChoice", choice = text }, i, text)))))
  end
  local prompt = Widget_ListVertical(0, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.Padding(vector.create(16, 8), vector.create(16, 8),
          Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.75, 1, 16, Widgets.ListH(16,
            Components.AlignCenter(Components.MinSize(48, circleIcon(Icons.ExclamationMark()))),
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), title, 24, white)))))),
        Components.Margin(16, 16, contents),
        Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.25, 1, 16, Components.Expand(Components.Padding(8, 8,
          Widgets.ListH(8, choice(Icons.Person(), option1), choice(Icons.Cancel(), option2))))),
      }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "PromptChoice" then
        print(`prompt: {message.choice}`)
        w:Delete()
      end
    end,
  }))
  return Widgets.FocusWindow(0.8, Components.AlignCenter(
    Components.Backdrop(vector.create(0.08, 0.08, 0.08), 0.95, 1, 16, prompt)))
end

local function samplePrompt(): Widget
  local function text(font: Font, s: string, size: number, color: vector): Widget
    return Components.AlignBottomLeft(Widgets.Text(font, s, size, color))
  end
  return createPrompt("WARNING", Widgets.ListV(16,
    Widgets.Text(Fonts.Default(), "You are about to embark on an amazing journey.", 16, white),
    Components.Padding(16, 16, Components.AlignCenter(Widgets.ListH(32,
      Components.MinSize(32, Widgets.Icon(Icons.Cargo(), 1.5 * Colors.Primary)),
      Components.MinSize(32, Widgets.Icon(Icons.Wormhole(), 1.5 * Colors.Primary))))),
    Widgets.ListH(0,
      text(Fonts.Default(), "You will face many ", 16, white),
      text(Fonts.Medium(), "CHALLENGES", 20, Colors.Primary),
      text(Fonts.Default(), " and ", 16, white),
      text(Fonts.Medium(), "OBSTACLES", 20, Colors.Primary),
      text(Fonts.Default(), ".", 16, white))),
    "ACCEPT", "CANCEL")
end

return AppShell.Create(function(): Widget
  local windows = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Positioned(64, Components.Draggable(Window.Create("Fancy Window",
          Components.Padding(16, 16, windowList())))),
        Components.Expand(Components.Margin(256, 256, Window.Create("Text Editor",
          TextEditor.Create("resource/script/Widget/Map.luau")))),
      }
    end,
    PostUpdate = function(_, w: Widget)
      if Key_Pressed(Key_P()) then
        w:AddChild(samplePrompt())
      end
    end,
  })
  local desktop = Desktop.Create(Components.Expand(Widget_Stack(windows)), { cursorSize = 8 })
  return Widget_Layer(Compositor_Basic(0.1, 0.1, vector.create(0.40, 0.50, 0.75)), Mesh_Quad(), 1, desktop)
end)
