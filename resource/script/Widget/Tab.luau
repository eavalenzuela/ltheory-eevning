--!strict
-- Tabs: within a group, selecting one deselects the others (Luau port of
-- Widget/Tab.lts). The selected tab's label is read with
-- Messages.GetLabel(widget, group).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")
local Widgets = require("@lt/Widgets")

local Tab = {}

export type Select = { type: "TabSelect", group: string, label: string }

type State = { focus: boolean, selected: boolean }

-- Focus, selection and group messages shared by both kinds of tab
local function behavior(group: string, label: string, state: State, extra: { [string]: any })
  extra.PostUpdate = function(_, w: Widget)
    if w.focusMouse ~= state.focus then
      state.focus = w.focusMouse
      w:Rebuild()
      if state.focus then
        Sound_Play("ui/hover.wav", 0.008)
      end
    end
    if w.focusMouse and Mouse_LeftPressed() then
      state.selected = true
      local select: Select = { type = "TabSelect", group = group, label = label }
      w:SendUp(select)
      Sound_Play("ui/tabselect.wav", 0.1)
    end
  end
  extra.Receive = function(_, w: Widget, message: any)
    if Messages.Is(message, "GetLabel") then
      if message.label == group and state.selected then
        message.contents = label
      end
    elseif type(message) == "table" and message.type == "TabSelect" then
      if message.group == group and message.label ~= label then
        state.selected = false
        w:Rebuild()
      end
    end
  end
  return extra
end

-- A text tab
function Tab.Create(group: string, label: string): Widget
  local state: State = { focus = false, selected = false }
  local tab = Widget_Luau(Widget_Create(), behavior(group, label, state, {
    CreateChildren = function(): { Widget }
      local c = if state.focus then vector.create(0, 0, 0) else vector.create(1, 1, 1)
      return { Widgets.Text(Fonts.Default(), label, 13, c) }
    end,
    PreDraw = function(_, w: Widget)
      if state.focus then
        WidgetRenderer_DrawPanel(w.pos, w.size, 2.5 * Colors.Primary, 0.5, 1, 0)
      end
      if state.selected then
        WidgetRenderer_DrawPanel(w.pos, vector.create(4, w.size.y), 2.5 * Colors.Primary, 0.5, 1, 0)
      end
    end,
  }))
  return Components.CaptureMouse(Components.Padding(vector.create(12, 4), vector.create(8, 4), Widget_Stack(tab)))
end

-- An icon tab, optionally ringed and captioned
function Tab.CreateIcon(group: string, label: string, icon: Icon, color: vector, focusColor: vector,
    drawRing: boolean, drawText: boolean, selected: boolean): Widget
  local state: State = { focus = false, selected = selected }
  local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)
  local tab = Widget_Luau(Widget_Create(), behavior(group, label, state, {
    GetName = function()
      return label
    end,
    PreDraw = function(_, w: Widget)
      local c = if state.selected then 3 * focusColor else 2 * color
      local opacity = if state.selected then 0.5 else 0.1
      local size = w.size
      if drawText then
        local center = w:GetPoint(0.5, 0.4)
        if drawRing then
          Glyph_Draw(ring, center, 0.4 * size, c, opacity)
          if state.focus then
            Glyph_Draw(ring, center, 0.5 * size, c, 1)
          end
          if state.selected then
            Glyph_Draw(ring, center, 0.45 * size, c, opacity)
          end
        end
        Icon_Draw(icon, center, 0.25 * size, c, 1)
        WidgetRenderer_DrawText(Fonts.Subheading(), string.upper(label), w:BottomCenter() + vector.create(0, 1), 12, c, 0.5, true)
      else
        if drawRing then
          Glyph_Draw(ring, w:Center(), 0.5 * size, c, opacity)
          if state.focus then
            Glyph_Draw(ring, w:Center(), 0.6 * size, c, 1)
          end
          if state.selected then
            Glyph_Draw(ring, w:Center(), 0.55 * size, c, opacity)
          end
        end
        Icon_Draw(icon, w:Center(), (if drawRing then 0.25 else 0.4) * size, c, 1)
      end
    end,
  }))
  return Components.CaptureMouse(Components.Tooltip(tab))
end

return Tab
