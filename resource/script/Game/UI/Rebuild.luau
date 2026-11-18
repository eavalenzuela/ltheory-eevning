--!strict
-- The rebuild pane (the owner, 2026-11-18: "the rebuild pane (right-click
-- -> rebuild) will tell you which materials are needed for it. It picks
-- the materials needed"): a citadel's hulk (Core/Assets/Hulks), what it
-- was, and what rebuilding it takes, each material with how much of it
-- is in the ship's hold. Rebuild takes them from the hold itself, once
-- there is enough of everything, and the citadel is the pilot's.

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Rebuild = {}

Rebuild.ID = "rebuild"

local current: Session.Session? = nil
local showing = 0   -- the hulk, or its place

-- Open it on a hulk (its id, or its place's).
function Rebuild.Open(session: Session.Session, id: number)
  current, showing = session, id
  Windows.Open(Rebuild.ID)
  Windows.Raise(Rebuild.ID)
end

-- Whether something is a hulk there is a pane for.
function Rebuild.Of(session: Session.Session, id: number): boolean
  return Core.Query.Hulk(session.game, id) ~= nil
end

local COLUMNS: { List.Column } = {
  { id = "name", label = "Material", width = 0, sort = false },
  { id = "have", label = "In the hold", width = 110, right = true, sort = false },
  { id = "need", label = "Needed", width = 110, right = true, sort = false },
}

Windows.Kind(Rebuild.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  local hulk = if session then Core.Query.Hulk(session.game, showing) else nil
  if session == nil or hulk == nil then
    Im.Text("There is no hulk here to rebuild.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  Im.Heading(List.Cut(hulk.name, w - 28, 18, true), x + 14, y + 10, 18, Theme.TEXT)
  Im.Text(List.Cut("Rebuilt for half of what it was built of, taken from your hold. It is yours, unfuelled and anchoring again, with nothing fitted.",
    w - 28, 13, false), x + 14, y + 34, 13, Theme.DIM)
  local top = y + 58
  local layout = List.Columns(COLUMNS, x + 1, w - 8)
  List.Head("rebuild", x + 1, top, w - 2, COLUMNS, layout, "", false)
  top += List.HEAD
  local bottom = y + h - 48
  local first, visible = List.Body("rebuild", x + 1, top, w - 2, bottom - top, #hulk.needs)
  for index = 1, visible do
    local need = hulk.needs[index + first]
    if need == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot = List.Row(x + 1, rowY, w - 7, false)
    ItemIcon.Draw(need.type, layout.name.x + 6, rowY + 3, 19)
    List.Text(need.name, layout.name, rowY, hot, Theme.TEXT, 14, false, 25)
    List.Text(tostring(need.have), layout.have, rowY, false, if need.have >= need.quantity then Theme.GOOD else Theme.BAD, 13)
    List.Text(tostring(need.quantity), layout.need, rowY, false, Theme.DIM, 13)
  end
  local command = { kind = "Rebuild", actor = 0, target = hulk.wreck }
  local can, why = Session.CanDo(session, command)
  if not can and why then
    Im.Text(List.Cut(why, w - 200, 13, false), x + 14, y + h - 34, 13, Theme.BAD)
  end
  if Im.Button("Rebuild", x + w - 150, y + h - 40, 136, 28, can) then
    Session.Do(session, { kind = "Rebuild", actor = 0, target = hulk.wreck })
  end
end)
Windows.Make(Rebuild.ID, Rebuild.ID, "Rebuild", 640, 180, 520, 440, 420, 300, nil)
Windows.Icon(Rebuild.ID, "industry")

return Rebuild
