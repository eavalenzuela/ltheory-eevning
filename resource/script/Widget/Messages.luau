--!strict
-- Widget messages (Luau port of Widget/Messages.lts). A message is a table
-- with a 'type' field, sent with widget:Send / SendUp / SendDown and
-- received as Receive(self, widget, message). Messages.Is also recognizes
-- the LTSL message types still sent by unported LTSL widgets.

local Messages = {}

export type AddWidget = { type: "AddWidget", widget: Widget }
export type AddContextMenu = { type: "AddContextMenu", widget: Widget }
export type Cancel = { type: "Cancel" }
export type Close = { type: "Close" }
export type Refresh = { type: "Refresh" }
export type Selected = { type: "Selected", widget: Widget }
export type SelectItem = { type: "SelectItem", item: Item }
export type UnselectItem = { type: "UnselectItem", item: Item }
export type SetPos = { type: "SetPos", pos: vector }
export type GetLabel = { type: "GetLabel", label: string, contents: any }
export type GetObject = { type: "GetObject", object: Object? }

-- Open 'widget' as a window over the HUD
function Messages.AddWidget(widget: Widget): AddWidget
  return { type = "AddWidget", widget = widget }
end

-- Show 'widget' as a context menu over the HUD
function Messages.AddContextMenu(widget: Widget): AddContextMenu
  return { type = "AddContextMenu", widget = widget }
end

function Messages.Cancel(): Cancel
  return { type = "Cancel" }
end

function Messages.Close(): Close
  return { type = "Close" }
end

function Messages.Refresh(): Refresh
  return { type = "Refresh" }
end

function Messages.Selected(widget: Widget): Selected
  return { type = "Selected", widget = widget }
end

function Messages.SelectItem(item: Item): SelectItem
  return { type = "SelectItem", item = item }
end

function Messages.UnselectItem(item: Item): UnselectItem
  return { type = "UnselectItem", item = item }
end

function Messages.SetPos(pos: vector): SetPos
  return { type = "SetPos", pos = pos }
end

-- Whether 'message' is of type 'name': a Luau message table, or an LTSL
-- message ("Message<name>" or "<name>") from an unported widget
function Messages.Is(message: any, name: string): boolean
  if type(message) == "table" then
    return message.type == name
  end
  local typeName = lt.typeof(message)
  return typeName == "Message" .. name or typeName == name
end

-- The value labelled 'label' in 'widget' or its ancestors (e.g. a slider's
-- position), or nil
function Messages.GetLabel(widget: Widget, label: string): any
  local message: GetLabel = { type = "GetLabel", label = label, contents = nil }
  widget:Send(message)
  widget:SendUp(message)
  return message.contents
end

-- The object 'widget' or one of its descendants shows, or nil
function Messages.GetObject(widget: Widget): Object?
  local message: GetObject = { type = "GetObject", object = nil }
  widget:Send(message)
  widget:SendDown(message)
  return message.object
end

return Messages
