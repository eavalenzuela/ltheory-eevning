--!strict
-- Jobs: a window of its own (Game/UI/Windows), the sixth of what the
-- docked screen held to be one. It opens in space too: the jobs in hand
-- are the pilot's wherever they are (the jobs offered, the store and
-- the completing of a job are a station's, and are there when docked).
--
-- On the left, docked, are the jobs the station offers: the day's, each
-- a row, and then the agents' lines of work that have levels (assault,
-- mining, courier, defence), a row each, the level shown stepped up and
-- down as far as the pilot's standing has opened. A switch over them
-- shows the faction's loyalty store in their place. Under them is what
-- every faction thinks of the pilot. On the right are the jobs in hand:
-- how each is going, how long it can be kept, and its completing and
-- its abandoning.
--
-- A script's names are what they were when this was a tab of the docked
-- screen: "Accept:<n>" (the day's, counted), "Accept:<line>",
-- "Level:<line>:down" and "Level:<line>:up", "LoyaltyStore",
-- "Redeem:<type>", "Complete:<n>", "Abandon:<n>". "Missions", the tab's
-- name, opens the window; and "jobs:close" shuts it.

local Assault = require("@lt/Core/Tactical/Assault")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Jobs = {}

Jobs.ID = "jobs"

local current: Session.Session? = nil
-- (Whether the left of it shows the faction's loyalty store in place of
-- the jobs offered.)
local storeOpen = false
-- The level of each line of work with levels that the list shows: the
-- hardest there is, until the pilot steps it down.
local ladder: { [string]: number } = {}

function Jobs.Open()
  Windows.Open(Jobs.ID)
  Windows.Raise(Jobs.ID)
end

function Jobs.Close()
  Windows.Close(Jobs.ID)
end

function Jobs.IsOpen(): boolean
  return Windows.IsOpen(Jobs.ID)
end

-- Which level of a line of work ("assault", "mining", "courier",
-- "defence") the list shows: given one, it is set to that. 0: the
-- hardest there is.
function Jobs.Level(kind: string, to: number?): number
  if to then
    ladder[kind] = to
  end
  return ladder[kind] or 0
end

-- Once a frame, before the windows are drawn: whose game it is.
function Jobs.Frame(session: Session.Session)
  current = session
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- What a job is about, in a line: where it is, and how it is going.
local function about(game: Core.Game, mission: State.Mission, jumps: number, ward: number): string
  if mission.kind == "bounty" and mission.type ~= "" then
    -- (war work: a strike at a front)
    return `at the lines in {game.state.galaxy.systems[mission.system].name}`
      .. (if jumps > 0 then `, {jumps} {if jumps == 1 then "jump" else "jumps"} off` else "")
      .. `: {mission.done} of {mission.need} destroyed`
  elseif mission.kind == "bounty" then
    local _, band = Core.Query.Security(game, mission.system)
    return `in {game.state.galaxy.systems[mission.system].name} ({band or "?"} space): {mission.done} of {mission.need} destroyed`
  elseif mission.kind == "assault" and (mission.aim == "hold" or Assault.Tender(mission.aim) or mission.aim == "lost") then
    -- (where the rig is, or the tender; and, once the job is taken, how it is going and how the thing is)
    local name = game.state.galaxy.systems[mission.system].name
    local place = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
    local escort = Assault.Tender(mission.aim)
    local convoy = mission.aim == "convoy"
    if place == nil then
      -- (they do not wait their turn, as a camp's keepers do)
      return `in {name}: {#mission.waves} waves, {Assault.PRESS // 60} minutes apart`
        .. (if convoy then (if mission.system == Core.Query.Player(game).system then ", the last off this station" else ", the last at the gate home")
          elseif escort then ", while it flies out" else "")
    elseif mission.done >= mission.need then
      return `{place.name}, in {name}: {if convoy then "in" elseif escort then "through" else "held"}`
    elseif convoy and mission.done >= 1 then
      -- (away from its place, and on its way in)
      local dest = Core.Query.Body(game, mission.to)
      return `away to {if dest then shorten(dest.name, 28) else "the station"}: see it in`
        .. (if ward >= 0 then `, the tender at {math.ceil(ward * 100)}%` else "")
    elseif ward < 0 then
      return `{place.name}, in {name}: they come when you do`
    elseif escort then
      return `{place.name}, {name}: wave {mission.wave} of {#mission.waves}, the tender at {math.ceil(ward * 100)}%`
    end
    return `{place.name}, {name}: wave {mission.wave} of {#mission.waves}, {mission.done}/{mission.need} down, the rig at `
      .. `{math.ceil(ward * 100)}%`
  elseif mission.kind == "assault" then
    -- (where the camp is; and, once the job is taken, how it is going)
    local name = game.state.galaxy.systems[mission.system].name
    local camp = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
    local rooms = if #mission.ends == 1 then "one room" else `{#mission.ends} rooms`
    if camp == nil then
      return `in {name}: {rooms}, {#mission.waves} waves`
    elseif mission.aim ~= "fetch" and mission.done >= mission.need then
      return `{camp.name}, in {name}: done`
    end
    -- (how far in the pilot has got: the rooms whose way is found)
    local open = 0
    for _, room in mission.rooms do
      open += if Core.Query.Found(game, room) then 1 else 0
    end
    local where = if #mission.rooms > 1 then `room {open} of {#mission.rooms}, ` else ""
    local how = if mission.aim == "chief" then "the chief comes with the last"
      elseif mission.aim == "fetch" then "the cargo is in the last room"
      elseif mission.aim == "raze" then `{mission.done}/{mission.need} of its works razed, in the last room`
      else `{mission.done}/{mission.need} down`
    return `{camp.name}, {name}: {where}wave {mission.wave} of {#mission.waves}, {how}`
  elseif mission.kind == "mining" then
    -- (where the pocket is; and whether anybody disputes it)
    local name = game.state.galaxy.systems[mission.system].name
    local place = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
    local disputed = if #mission.waves > 0 then ", disputed" else ""
    return if place then `{place.name}, in {name}{disputed}` else `a pocket in {name}{disputed}`
  elseif mission.kind == "courier" then
    -- (where to, and how far that is)
    local to = Core.Query.Body(game, mission.to)
    local far = if jumps == 0 then "this system" elseif jumps == 1 then "1 jump" else `{jumps} jumps`
    return `{far}: to {if to then shorten(to.name, 40) else "?"}`
  end
  local at = Core.Query.Body(game, mission.station)
  return `to {if at then shorten(at.name, 40) else "?"}`
end

local function heading(s: string, x: number, y: number, w: number, note: string?): number
  Im.Strong(string.upper(s), x, y, 11, Theme.ACCENT)
  if note then
    Im.Text(note, x + w - Im.TextWidth(note, 12), y - 1, 12, Theme.DIM)
  end
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
  return y + 22
end

local LEFT_W = 480
local OFFER_H, HELD_H = 52, 88

Windows.Kind(Jobs.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local docked = Core.Query.Player(game).at ~= 0
  local status = Core.Query.Missions(game)
  local was = Im.Plain(true)
  Im.Flat(x + LEFT_W, y, 1, h, Theme.EDGE)

  -- The left: the jobs offered here, or the faction's store in their place.
  local left, lw = x + 14, LEFT_W - 28
  local line = y + 12
  if not docked then
    storeOpen = false
    line = heading("Jobs offered", left, line, lw)
    Im.Text("Jobs are offered at stations: dock at one.", left, line + 2, 13, Theme.DIM)
    line += 30
  else
    -- (the faction's store, and the way back from it)
    local tx = left - 4
    for _, each in { { false, "Jobs offered here" }, { true, `Loyalty store  {status.loyalty} LP` } } :: { { any } } do
      local on = storeOpen == each[1]
      -- (one name for a script, as the old switch had: pressed, it goes to the other)
      local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, on, if on then `Jobs:page:{if each[1] then "store" else "offers"}` else "LoyaltyStore")
      if pressed and not on then
        storeOpen = each[1]
      end
      tx += wide + 2
    end
    Im.Flat(x + 1, y + 32, LEFT_W - 1, 1, Theme.EDGE)
    line = y + 44
  end
  local standingsH = 124
  if docked and storeOpen then
    -- The store: what the faction lets a pilot have for loyalty points.
    if #status.store == 0 then
      Im.Text("There is no store here.", left, line, 13, Theme.DIM)
    end
    local room = y + h - 8 - line
    local first, visible = List.Body("jobs store", x + 1, line, LEFT_W - 1, room, #status.store)
    for row = 1, visible do
      local stocked = status.store[row + first]
      if stocked == nil then
        break
      end
      local rowY = line + (row - 1) * List.ROW
      local hot, _, double = List.Row(x + 1, rowY, LEFT_W - 6, false)
      Im.Text(List.Cut(stocked.name, 200, 14, false), left, rowY + 5, 14, if stocked.can then Theme.TEXT else Theme.DIM)
      if stocked.can or string.sub(stocked.why, 1, 5) ~= "needs" then
        local cost = `{stocked.stock.points} LP` .. (if stocked.stock.credits > 0 then `  {Format.Credits(stocked.stock.credits)}` else "")
        Im.Text(cost, left + lw - 66 - Im.TextWidth(cost, 12), rowY + 6, 12, Theme.DIM)
      else
        local why = List.Cut(stocked.why, 180, 12, false)
        Im.Text(why, left + lw - 66 - Im.TextWidth(why, 12), rowY + 6, 12, Theme.CAUTION)
      end
      Im.Because(stocked.why)
      if Im.Button("Get", left + lw - 56, rowY + 2, 52, 21, stocked.can, `Redeem:{stocked.stock.type}`) then
        Session.Do(session, { kind = "RedeemLoyalty", actor = 0, type = stocked.stock.type, quantity = 1 })
      end
      if double then
        Info.Open(stocked.stock.type)
      elseif hot then
        Im.Tip(stocked.name, "double-click for its sheet")
      end
    end
  elseif docked then
    if #status.offers == 0 then
      Im.Text("Nothing more today.", left, line, 13, Theme.DIM)
    end
    -- The day's jobs, each a row; then the fourth agent's assault, the
    -- fifth's mining contract, the sixth's courier contract and the
    -- seventh's defence job, a row each: the level shown is stepped up
    -- and down, as far as the pilot's standing has opened.
    local function offered(offer: Core.MissionStatus, id: string, kind: string?, level: number, levels: number)
      -- (a job with levels says its level in a word less: the steps beside it say the rest)
      local title = if kind then (string.gsub(offer.title, ", level", "", 1)) else offer.title
      -- (or what it pays with: one of the people's own makes)
      local pays = offer.mission.prize
      local reward = if pays then Types.Info(pays).name else Format.Credits(offer.mission.reward)
      reward = List.Cut(reward, 170, 13, true)
      Im.Strong(reward, left + lw - 78 - Im.StrongWidth(reward, 13), line + 2, 13, Theme.GOOD)
      Im.Strong(List.Cut(title, lw - 100 - Im.StrongWidth(reward, 13) - (if kind and levels > 1 then 56 else 0), 14, true), left, line, 14, Theme.TEXT)
      local accept: State.Command = { kind = "AcceptMission", actor = 0, what = offer.mission.key }
      local can, whyNot = Session.CanDo(session, accept)
      -- (who gives it, what they think of the pilot once they think anything, and the points it is worth)
      local thinks = if offer.regard ~= 0 then string.format(" (%.1f)", offer.regard) else ""
      local giver = `{shorten(offer.mission.agent, 16)}{thinks}  +{offer.mission.loyalty} LP`
      Im.Text(giver, left + lw - 78 - Im.TextWidth(giver, 12), line + 22, 12,
        if offer.regard > 0 then Theme.GOOD elseif offer.regard < 0 then Theme.CAUTION else Theme.DIM)
      Im.Text(List.Cut(if can then about(game, offer.mission, offer.jumps, offer.ward) else tostring(whyNot), lw - 90 - Im.TextWidth(giver, 12), 12,
        false), left, line + 22, 12, if can then Theme.DIM else Theme.CAUTION)
      if kind and levels > 1 then
        local sx = left + lw - 78 - Im.StrongWidth(reward, 13) - 54
        if Im.Button("<", sx, line - 2, 22, 20, level > 1, `Level:{kind}:down`) then
          ladder[kind] = level - 1
        end
        if Im.Button(">", sx + 24, line - 2, 22, 20, level < levels, `Level:{kind}:up`) then
          ladder[kind] = level + 1
        end
      end
      Im.Tone("primary")
      Im.Because(whyNot)
      if Im.Button("Accept", left + lw - 68, line + 4, 68, 30, can, id) then
        Session.Do(session, accept)
      end
      Im.Flat(x + 1, line + OFFER_H - 8, LEFT_W - 1, 1, Theme.EDGE, 0.6)
      line += OFFER_H
    end
    local daily = 0
    for _, offer in status.offers do
      if offer.mission.level == 0 then
        daily += 1
        offered(offer, `Accept:{daily}`, nil, 0, 0)
      end
    end
    for _, kind in { "assault", "mining", "courier", "defence" } do
      local levels: { Core.MissionStatus } = {}
      for _, offer in status.offers do
        if offer.line == kind then
          table.insert(levels, offer)
        end
      end
      if #levels > 0 then
        local level = math.clamp(if (ladder[kind] or 0) == 0 then #levels else ladder[kind], 1, #levels)
        offered(levels[level], `Accept:{kind}`, kind, level, #levels)
      end
    end
  end

  -- What every faction thinks of the pilot (it is their stations' fees,
  -- their jobs' pay and, at the worst, their patrols' guns): along the
  -- foot of the left, but where the store has it.
  if not (docked and storeOpen) then
    local sy = if docked then y + h - standingsH else line + 6
    sy = heading("Standings", left, sy, lw)
    for index, row in Core.Query.Standings(game) do
      -- (four to a row: the four human factions, and under them any
      -- other that has come to think something of the pilot)
      local cx = left + (index - 1) % 4 * (lw / 4)
      local cy = sy + (index - 1) // 4 * 44
      Im.Text(List.Cut(row.name, lw / 4 - 8, 12, false), cx, cy, 12, Theme.DIM)
      Im.Strong(string.format("%.1f", row.standing), cx, cy + 16, 15, if row.hostile then Theme.BAD elseif row.standing < 0 then Theme.CAUTION else Theme.TEXT)
      if row.hostile then
        Im.Text("hostile", cx + 42, cy + 18, 12, Theme.BAD)
      end
    end
  end

  -- The right: the jobs in hand.
  local right, rw = x + LEFT_W + 14, w - LEFT_W - 28
  line = heading(`In hand  {#status.inHand} / 5`, right, y + 12, rw, `{status.done} done`)
  if #status.inHand == 0 then
    Im.Text("No jobs in hand.", right, line + 2, 13, Theme.DIM)
  end
  for index, held in status.inHand do
    local paid = held.mission.prize
    local reward = List.Cut(if paid then Types.Info(paid).name else Format.Credits(held.mission.reward), 170, 13, true)
    Im.Strong(reward, right + rw - Im.StrongWidth(reward, 13), line + 2, 13, Theme.GOOD)
    Im.Strong(List.Cut(held.title, rw - 16 - Im.StrongWidth(reward, 13), 14, true), right, line, 14, Theme.TEXT)
    -- (how long it can still be kept: in the colour of a warning at the last)
    local kept = Format.Duration(held.left)
    Im.Text(kept, right + rw - Im.TextWidth(kept, 12), line + 22, 12, if held.left < 6 * 3600 then Theme.CAUTION else Theme.DIM)
    -- (a rig that is going down says so in the colour of a warning)
    Im.Text(List.Cut(about(game, held.mission, held.jumps, held.ward), rw - 16 - Im.TextWidth(kept, 12), 12, false), right, line + 22, 12,
      if held.ward >= 0 and held.ward < 0.5 and held.mission.done < held.mission.need then Theme.CAUTION else Theme.DIM)
    local complete: State.Command = { kind = "CompleteMission", actor = 0, target = held.mission.id }
    Im.Tone("primary")
    Im.Because(held.why)
    if Im.Button("Complete", right, line + 44, 96, 26, held.ready, `Complete:{index}`) then
      Session.Do(session, complete)
    end
    if not held.ready then
      Im.Text(List.Cut(held.why, rw - 96 - 100 - 20, 12, false), right + 106, line + 50, 12, Theme.DIM)
    end
    if Im.Button("Abandon", right + rw - 86, line + 44, 86, 26, true, `Abandon:{index}`) then
      Session.Do(session, { kind = "AbandonMission", actor = 0, target = held.mission.id })
    end
    Im.Flat(x + LEFT_W + 1, line + HELD_H - 8, w - LEFT_W - 2, 1, Theme.EDGE, 0.6)
    line += HELD_H
  end
  Im.Plain(was)
end)
Windows.Make(Jobs.ID, Jobs.ID, "Jobs", 534, 130, 980, 640, 900, 560, nil)
Windows.Icon(Jobs.ID, "jobs")

return Jobs
