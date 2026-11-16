--!strict
-- The assets window: everything the pilot owns, place by place: the
-- hold, and every station with a ship or goods of theirs in it.
--
-- A window (Game/UI/Windows), open in space or docked: from the
-- inventory's "All assets" button. It only reads the Core, and sets the
-- session's destination: a station somewhere else has a button
-- ("Assets:course:<station>") that sets the pilot's course for its
-- system. Its close button is "assets:close" (Im.Press).

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
local Windows = require("@lt/Game/UI/Windows")

local Assets = {}

Assets.WIDTH = 468
Assets.HEIGHT = 660

local ROW = 24

-- The window's id, and whose game it shows (Assets.Frame).
local ID = "assets"
local current: Session.Session? = nil

function Assets.Open()
  Windows.Open(ID)
end

function Assets.Close()
  Windows.Close(ID)
end

function Assets.IsOpen(): boolean
  return Windows.IsOpen(ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Assets.Frame(session: Session.Session)
  current = session
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- A line of the list: a place's heading, a ship there, or a stack.
type Line = { place: Core.AssetsAt?, ship: State.Ship?, item: State.Item?, label: string? }

local function draw(_: Windows.Window, x: number, y: number, width: number, height: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local left, right = x + 16, x + width - 16

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
    -- (and what the corporation has there, under its own line)
    if #place.business > 0 then
      table.insert(lines, { label = "the corporation's" })
      local theirs = table.clone(place.business)
      table.sort(theirs, function(a: State.Item, b: State.Item): boolean
        if a.type ~= b.type then
          return Catalog.Before(a.type, b.type)
        end
        return a.id < b.id
      end)
      for _, item in theirs do
        table.insert(lines, { item = item })
      end
    end
  end
  Im.Text(`{#places} places`, left, y + 10, 13, Im.DIM)
  Im.TextRight(`worth {Format.Whole(worth)} cr with the wallet`, right, y + 10, 13, Im.TEXT)

  local top = y + 36
  local visible = math.max(1, (height - 46) // ROW)
  local first = Im.Scroll("assets", left - 4, top, width - 24, visible * ROW, #lines, visible)
  for row = 1, visible do
    local line = lines[row + first]
    if line == nil then
      break
    end
    local at = top + (row - 1) * ROW
    local place, ship, item = line.place, line.ship, line.item
    if line.label then
      Im.Text(line.label, left + 10, at + 4, 12, Im.ACCENT)
    elseif place then
      Im.Fill(left - 4, at + 1, width - 24, ROW - 3, Im.DIM, 0.12)
      Im.Text(shorten(place.name, 34), left, at + 4, 13, if place.here then Im.TEXT else Im.ACCENT)
      -- (a station somewhere else: its system, and a button that sets the
      -- pilot's course there. The owner's, 2026-11-15.)
      local elsewhere = place.station ~= 0 and place.system ~= Core.Query.Player(game).system
      Im.TextRight(if place.station == 0 then `{string.format("%.0f", place.volume)} m3` else place.systemName,
        right - (if elsewhere then 96 else 4), at + 4, 12, Im.DIM)
      if elsewhere then
        local set = session.destination == place.system
        if Im.Button(if set then "Course set" else "Set course", right - 88, at + 1, 86, ROW - 3, not set, `Assets:course:{place.station}`) then
          session.destination = place.system
        end
      end
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

Windows.Kind(ID, draw)
Windows.Make(ID, ID, "Assets", 538, 130, Assets.WIDTH, Assets.HEIGHT, 340, 240, nil)
Windows.Icon(ID, "inventory")

return Assets
