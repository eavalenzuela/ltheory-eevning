--!strict
-- The assets window: everything the pilot owns, place by place: the
-- hold, and every station with a ship or goods of theirs in it.
--
-- Open in space or docked, from the Assets button. Drawn every frame
-- with Game/UI/Im; it only reads the Core. Its close button is
-- "Assets:close" (Im.Press).

local Catalog = require("@lt/Core/Data/Catalog")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Assets = {}

Assets.WIDTH = 468
Assets.HEIGHT = 660

local ROW = 24

local open = false

function Assets.Open()
  open = true
end

function Assets.Close()
  open = false
end

function Assets.IsOpen(): boolean
  return open
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- A line of the list: a place's heading, a ship there, or a stack.
type Line = { place: Core.AssetsAt?, ship: State.Ship?, item: State.Item? }

function Assets.Draw(session: Session.Session, x: number, y: number)
  if not open then
    return
  end
  local game = session.game
  local width, height = Assets.WIDTH, Assets.HEIGHT
  local left, right = x + 16, x + width - 16
  Im.Panel(x, y, width, height)
  Im.Heading("ASSETS", left, y + 12, 16, Im.DIM)
  if Im.Button("x", x + width - 38, y + 10, 24, 24, true, "Assets:close") then
    open = false
    return
  end

  local places = Core.Query.Assets(game)
  local worth = game.state.wallet
  local lines: { Line } = {}
  for _, place in places do
    worth += place.worth
    table.insert(lines, { place = place })
    for _, ship in place.ships do
      table.insert(lines, { ship = ship })
    end
    -- (set out as a hangar is: modules, then charges, and so on)
    local items = table.clone(place.items)
    table.sort(items, function(a: State.Item, b: State.Item): boolean
      if a.type ~= b.type then
        return Catalog.Before(a.type, b.type)
      end
      return a.id < b.id
    end)
    for _, item in items do
      table.insert(lines, { item = item })
    end
  end
  Im.Text(`{#places} places`, left, y + 42, 13, Im.DIM)
  Im.TextRight(`worth {Format.Whole(worth)} cr with the wallet`, right, y + 42, 13, Im.TEXT)

  local top = y + 70
  local visible = (height - 86) // ROW
  local first = Im.Scroll("assets", left - 4, top, width - 24, visible * ROW, #lines, visible)
  for row = 1, visible do
    local line = lines[row + first]
    if line == nil then
      break
    end
    local at = top + (row - 1) * ROW
    local place, ship, item = line.place, line.ship, line.item
    if place then
      Im.Fill(left - 4, at + 1, width - 24, ROW - 3, Im.DIM, 0.12)
      Im.Text(shorten(place.name, 34), left, at + 4, 13, if place.here then Im.TEXT else Im.ACCENT)
      Im.TextRight(if place.station == 0 then `{string.format("%.0f", place.volume)} m3` else place.systemName, right - 4, at + 4, 12,
        Im.DIM)
    elseif ship then
      local hull = Ships.byId[ship.type]
      ItemIcon.Draw(hull.id, left + 10, at + 2, 20)
      Info.Name(hull.id, shorten(ship.name, 22), left + 36, at + 4, 13, Im.TEXT)
      Im.TextRight(if ship.id == game.state.player.ship then "you are aboard" else "assembled", right - 4, at + 4, 12, Im.DIM)
    elseif item then
      local info = Types.Info(item.type)
      ItemIcon.Draw(item.type, left + 10, at + 2, 20)
      Info.Name(item.type, shorten(info.name, 30), left + 36, at + 4, 13, Im.TEXT)
      Im.TextRight(`x{Format.Whole(item.quantity)}`, right - 4, at + 4, 12, Im.DIM)
    end
  end
end

return Assets
