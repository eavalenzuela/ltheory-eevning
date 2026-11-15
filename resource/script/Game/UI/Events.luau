--!strict
-- The events window: what is going on in the galaxy that a pilot could
-- go to (Core/Strategic/Happenings), nearest first, each with where it
-- is, how many jumps off, how long it has left, and a button that sets
-- the pilot's course for it; and under them, what has been left behind.
-- (The owner's ruling, 2026-11-14: "An events window and map marks".)
--
-- A window (Game/UI/Windows), open in space or docked: from the Events
-- button at the foot of the screen (Im.Press "Events"). It only reads
-- the Core, and sets the session's destination. Its close button is
-- "events:close", and a row's button is "Events:course:<id>" with the
-- happening's id.
--
-- Events.Title and Events.Colour say what a happening is called and
-- what colour it goes by, for whoever else shows one (the star map, the
-- line that says one has begun).

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local Windows = require("@lt/Game/UI/Windows")

local Events = {}

Events.WIDTH = 620
Events.HEIGHT = 420

local ROW = 44

local ID = "events"
local current: Session.Session? = nil
-- What there is to show, as last asked: a screen draws many times a second, and this changes by the minute.
local shown = { age = 1000, epoch = -1, list = {} :: { Core.HappeningInfo }, left = {} :: { Core.AftermathInfo } }

local COLOURS: { [string]: vector } = {
  surge = vector.create(0.95, 0.32, 0.26),
  invasion = vector.create(0.78, 0.42, 0.95),
  sighting = vector.create(0.96, 0.80, 0.30),
  disaster = vector.create(0.96, 0.58, 0.24),
  windfall = vector.create(0.42, 0.86, 0.50),
}

-- The colour a kind of happening goes by.
function Events.Colour(kind: string): vector
  return COLOURS[kind] or Im.TEXT
end

-- What a happening is called, and a line more about it.
function Events.Title(one: { kind: string, what: string, name: string, stage: number, strength: number, kills: number }): (string, string)
  if one.kind == "surge" then
    return "Pirate surge", `bounties doubled there; {one.kills} destroyed, and ten break it`
  elseif one.kind == "invasion" then
    local stage = ({ "a way has opened and their van is through", "they are landed, and dug in", "they are at the stations" })[one.stage]
    return "Invasion out of the deep", `{stage or "they hold it"}; {math.max(0, math.floor(one.strength))} of them left`
  elseif one.kind == "sighting" then
    if one.what == "captain" then
      return `{one.name}, a pirate captain`, "seen with a small escort: what such a one carries is worth the taking"
    elseif one.what == "derelict" then
      return "A derelict hull", "adrift, and not yet picked over"
    end
    return "A wandering trader", `{one.name}: rare stock, while they stay`
  elseif one.kind == "disaster" then
    if one.what == "gate" then
      return `The gate to {one.name} is closed`, "for repairs: nothing goes through until it is done"
    end
    return `{one.name}: out of use`, "the station cannot do it until it is mended"
  elseif one.kind == "windfall" then
    return "A rich belt found", "rare ore, and nobody's yet"
  end
  return one.kind, ""
end

function Events.Open()
  Windows.Open(ID)
end

function Events.Close()
  Windows.Close(ID)
end

function Events.IsOpen(): boolean
  return Windows.IsOpen(ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Events.Frame(session: Session.Session)
  current = session
end

-- What is going on, as the window last asked (and asked again if that was long ago).
function Events.List(session: Session.Session): ({ Core.HappeningInfo }, { Core.AftermathInfo })
  shown.age += 1
  if shown.age > 30 or shown.epoch ~= session.epoch then
    shown.age, shown.epoch = 0, session.epoch
    shown.list = Core.Query.Happenings(session.game)
    shown.left = Core.Query.Aftermath(session.game)
  end
  return shown.list, shown.left
end

local function far(jumps: number, here: boolean): string
  return if here then "here" elseif jumps < 0 then "far off" elseif jumps == 1 then "1 jump" else `{jumps} jumps`
end

local function draw(_: Windows.Window, x: number, y: number, width: number, height: number)
  local session = current
  if session == nil then
    return
  end
  local left, right = x + 16, x + width - 16
  local list, behind = Events.List(session)
  Im.Text(if #list == 0 then "Nothing is going on that anybody has word of." else `{#list} going on, the nearest first`, left, y + 10, 13,
    Im.DIM)

  -- (a line for each, and under them what has been left behind, a line each)
  type Line = { one: Core.HappeningInfo?, mark: Core.AftermathInfo?, heading: string? }
  local lines: { Line } = {}
  for _, one in list do
    table.insert(lines, { one = one })
  end
  if #behind > 0 then
    table.insert(lines, { heading = "LEFT BEHIND" })
    for _, mark in behind do
      table.insert(lines, { mark = mark })
    end
  end
  local top = y + 36
  local visible = math.max(1, (height - 46) // ROW)
  local first = Im.Scroll("events", left - 4, top, width - 24, visible * ROW, #lines, visible)
  for row = 1, visible do
    local line = lines[row + first]
    if line == nil then
      break
    end
    local at = top + (row - 1) * ROW
    local one, mark = line.one, line.mark
    if line.heading then
      Im.Text(line.heading, left, at + 16, 12, Im.ACCENT)
    elseif one then
      local title, more = Events.Title(one)
      Im.Fill(left - 4, at + 2, 3, ROW - 6, Events.Colour(one.kind), 0.9)
      Im.Text(title, left + 6, at + 4, 14, Events.Colour(one.kind))
      Im.Text(more, left + 6, at + 23, 12, Im.DIM)
      Im.TextRight(`{one.where}, {far(one.jumps, one.here)}`, right - 108, at + 4, 13, Im.TEXT)
      Im.TextRight(`{Format.Duration(one.left)} left`, right - 108, at + 23, 12, Im.DIM)
      local can = not one.here and one.jumps >= 0 and session.destination ~= one.system
      if Im.Button(if session.destination == one.system then "Course set" else "Set course", right - 98, at + 6, 98, 28, can,
        `Events:course:{one.id}`) then
        session.destination = one.system
      end
    elseif mark then
      Im.Text(`{mark.name}: order is {if mark.delta < 0 then "thinner" else "firmer"} there`, left + 6, at + 4, 13, Im.TEXT)
      Im.Text(`after {mark.why}, for {Format.Duration(mark.left)} more`, left + 6, at + 23, 12, Im.DIM)
    end
  end
end

Windows.Kind(ID, draw)
Windows.Make(ID, ID, "Events", 520, 150, Events.WIDTH, Events.HEIGHT, 480, 200, nil)

return Events
