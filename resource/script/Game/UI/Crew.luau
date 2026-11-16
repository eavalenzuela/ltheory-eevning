--!strict
-- Crew: a window of its own (Game/UI/Windows), of what the docked screen
-- held. A station's: opened from the dock, shut when the pilot undocks.
--
-- Its Pilots page is the pilots looking for work at the station, each
-- with their grade, their wage and what signing them costs, and the
-- pilots hired (Core/Tactical/Fleet): what each flies and is doing, and
-- for one docked here what it is to carry and where. Its Log page is
-- the fights hired pilots had with the pilot somewhere else
-- (Core/Tactical/Battles).
--
-- Its two pages are the window's tabs, and the pilots hired are a list
-- that scrolls (the tab showed the first five and no more). The rest is
-- laid out as the tab was, in the window layer's frame and colours. A
-- script's names are what they were: "Crew:pilots", "Crew:log",
-- "Hire:<n>", "Give:<n>:<m>", "Haul:what:<n>", "Haul:to:<n>",
-- "Haul:also:<n>", "Haul:drop:<n>", "Haul:go:<n>", "Recall:<n>",
-- "Sells:<n>", "TakeOff:<n>", "Dismiss:<n>". "Crew", the tab's name,
-- opens it.

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Crew = {}

Crew.ID = "crew"

local current: Session.Session? = nil

function Crew.Open()
  Windows.Open(Crew.ID)
  Windows.Raise(Crew.ID)
end

function Crew.Close()
  Windows.Close(Crew.ID)
end

function Crew.IsOpen(): boolean
  return Windows.IsOpen(Crew.ID)
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- What a pilot docked here would be set to carry, and where to: which
-- of the kinds, and which of the places, by the pilot's id.
local haulWhat: { [number]: number } = {}
local haulTo: { [number]: number } = {}
-- And the further stations they would collect at on the way, in the
-- order they were added (a round of several: Core/Tactical/Fleet).
local haulAlso: { [number]: { number } } = {}
-- (and the stations picked as more to carry to, by the pilot's id)
local haulMore: { [number]: { number } } = {}
local CARGO: { [string]: string } = { ore = "ore", mineral = "minerals", moon = "moon ore", planetary = "planetary", component = "components",
  all = "all goods" }

-- Which side of the Crew tab is shown: "pilots" (hiring, and the pilots
-- hired) or "log" (the fights the pilot was not at).
local crewPage = "pilots"

function Crew.Page(): string
  return crewPage
end

-- A tally of names, in a line: "2 x Pirate Raider, Pirate Jackal".
local function tallied(tally: { State.Tally }): string
  local parts: { string } = {}
  for _, entry in tally do
    table.insert(parts, if entry.count == 1 then entry.name else `{entry.count} x {entry.name}`)
  end
  return table.concat(parts, ", ")
end

-- The fleet's log (Core/Tactical/Battles): the fights hired pilots had
-- with the pilot somewhere else, the latest first.
local function drawFleetLog(game: Core.Game, x: number, y: number, width: number)
  local log = Core.Query.FleetLog(game)
  Im.Heading(`FIGHTS YOU WERE NOT AT  {#log}`, x, y, 16, Theme.DIM)
  local line = y + 30
  if #log == 0 then
    Im.Text("None on record. When a pilot of yours is attacked while you are somewhere else, how it went is put down here.", x, line, 13,
      Theme.DIM, 0.8)
    return
  end
  local visible = 7
  local first = Im.Scroll("fleet log", x - 4, line, width + 4, visible * 62, #log, visible)
  for row = 1, visible do
    local fight = log[row + first]
    if fight == nil then
      break
    end
    local rowY = line + (row - 1) * 62
    local over = fight.ended ~= 0
    Im.Text(`{Format.Clock(fight.began)}   {shorten(fight.where, 46)}`, x, rowY, 14, Theme.TEXT)
    Im.TextRight(if over then `over in {Format.Duration((fight.ended - fight.began) * Constants.TICK)}`
      .. (if fight.joined then ", you came to it" else "") else "going on now", x + width - 8, rowY + 1, 12, if over then Theme.DIM else Theme.CAUTION)
    Im.Text(shorten(`{table.concat(fight.pilots, ", ")} against {if #fight.attackers > 0 then tallied(fight.attackers) else "nobody seen"}`, 112),
      x, rowY + 19, 12, Theme.DIM)
    local came = if #fight.destroyed > 0 then `destroyed: {tallied(fight.destroyed)}` else "nothing destroyed"
    if fight.fled > 0 then
      came ..= `, {fight.fled} got away`
    end
    Im.Text(shorten(came, 70), x, rowY + 35, 12, Theme.TEXT)
    if #fight.lost > 0 then
      Im.Text(shorten(`lost: {table.concat(fight.lost, ", ")}`, 44), x + 420, rowY + 35, 12, Theme.CAUTION)
    end
    Im.TextRight(if fight.bounty > 0 then `bounty {Format.Credits(fight.bounty)}` else "no bounty", x + width - 8, rowY + 35, 12,
      if fight.bounty > 0 then Theme.GOOD else Theme.DIM)
    Im.Flat(x, rowY + 55, width - 8, 1, Theme.DIM, 0.15)
  end
end

local function drawCrew(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local left, right = x + 16, x + 400
  local line = y + 78
  -- (its two pages, the pilots and the log of their fights, are the window's tabs)
  if crewPage == "log" then
    drawFleetLog(game, left, line, 908)
    return
  end
  local candidates, most = Core.Query.Candidates(game, station)
  local fleet = Core.Query.Fleet(game)

  Im.Heading("LOOKING FOR WORK HERE", left, line, 16, Theme.DIM)
  line += 30
  if #candidates == 0 then
    Im.Text("Nobody more today.", left, line, 14, Theme.DIM, 0.8)
  end
  for index, found in candidates do
    Im.Text(found.name, left, line, 15, Theme.TEXT)
    Im.TextRight(`grade {found.skill}`, left + 350, line, 15, Theme.ACCENT)
    Im.Text(`{Format.Credits(found.wage)} a day`, left, line + 21, 12, Theme.DIM)
    Im.TextRight(`{Format.Credits(found.fee)} to sign`, left + 350, line + 21, 12, Theme.DIM)
    local hire: State.Command = { kind = "HirePilot", actor = 0, what = found.key }
    local can, whyNot = Session.CanDo(session, hire)
    if Im.Button("Hire", left, line + 42, 90, 24, can, `Hire:{index}`) then
      Session.Do(session, hire)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 38), left + 100, line + 46, 12, Theme.CAUTION)
    end
    line += 84
  end
  line = y + 78 + 30 + 3 * 84 + 4
  Im.Heading("WHAT A PILOT IS", left, line, 14, Theme.DIM)
  for index, text in { "A hired pilot flies a ship of yours and goes where you go:", "out when you undock, to warp and through gates after you,",
    "into a fight beside you. Every skill counts as their grade.", "Grade 1 flies frigates and haulers, 2 destroyers and barges,",
    "3 cruisers, 4 battleships and freighters. You command one a level", "of Leadership. A ship lost is insured; its pilot is not lost.",
    "In space one can be set to mine a belt, to hold a place against", "pirates (Patrol here) or to go with another pilot (Guard);",
    "one docked here to haul what is in your hangar elsewhere (+", "adds a station to collect at on the way: a round); any to",
    "sell what they bring in. They learn by it, to grade 5." } do
    -- (eleven lines in the room ten had)
    Im.Text(text, left, line + 6 + index * 15.5, 12, Theme.DIM)
  end

  -- The pilots hired, and for each the ships here they could be given.
  local free: { State.Ship } = {}
  for _, ship in Core.Query.Ships(game, station) do
    if ship.id ~= player.ship and ship.pilot == 0 and Ships.byId[ship.type].class ~= "capsule" then
      table.insert(free, ship)
    end
  end
  line = y + 78
  -- (whose they are, where a corporation has been founded: the Wallet tab has its books)
  local whose = Core.Query.Corporation(game)
  Im.Heading(if whose.founded then `{string.upper(shorten(whose.name, 24))}  {#fleet} / {most}` else `YOUR PILOTS  {#fleet} / {most}`,
    right, line, 16, Theme.DIM)
  line += 30
  if #fleet == 0 then
    Im.Text("Nobody is hired.", right, line, 14, Theme.DIM, 0.8)
  end
  local shown = 5
  local firstPilot = Im.Scroll("crew pilots", right - 6, line, 536, shown * 90, #fleet, shown)
  for index, row in fleet do
    if index <= firstPilot then
      continue
    elseif index > firstPilot + shown then
      break
    end
    Im.Text(row.name, right, line, 15, Theme.TEXT)
    -- (their grade, and how far they are toward the next)
    Im.Text(if row.needed > 0 then `grade {row.skill}  {row.experience} / {row.needed}` else `grade {row.skill}`, right + 210, line + 1,
      13, Theme.ACCENT)
    -- (and how they stand toward the pilot)
    Im.Text(row.mood, right + 352, line + 1, 13, if row.mood == "wary" then Theme.CAUTION elseif row.mood == "devoted" then Theme.GOOD else Theme.DIM)
    Im.TextRight(`{Format.Credits(row.wage)} a day`, right + 520, line + 1, 13, Theme.DIM)
    local reason: string? = nil
    local note = ""
    local here = false
    if row.ship ~= 0 then
      ItemIcon.Draw(row.hull, right, line + 20, 18)
      local ship = game.state.ships[row.ship]
      here = ship ~= nil and ship.docked == station
      local where = if here then "docked here" else row.where
      if row.order == "mine" then
        where = `{row.doing}: {row.hauled} units of ore brought in`
      elseif row.order == "buy" then
        where = row.doing
        note = `{Format.Whole(row.need)} {row.want} still to buy at {row.from}, to bring to {row.to}`
      elseif row.order == "stock" then
        where = row.doing
        note = `Keeps {Format.Whole(row.keep)} {row.want} in the hangar {if here then "here" else `at {row.to}`}, from {row.from}`
      elseif row.order == "haul" then
        where = row.doing
        -- (a round of several stations says how many it collects at)
        note = if #row.stops > 1 then `Hauling {CARGO[row.cargo] or row.cargo} from {#row.stops} stations to {row.to}: {row.hauled} units`
          else `Hauling {CARGO[row.cargo] or row.cargo} to {row.to}: {row.hauled} units`
      elseif row.order == "patrol" then
        where = `{row.doing}: {row.post}`
      elseif row.order == "guard" then
        where = `{row.doing} {row.ward}` .. (if here then ", docked here" else `, {row.where}`)
      elseif row.order == "stay" then
        where ..= ", told to stay"
      end
      if row.earned > 0 then
        note = if note ~= "" then `{note}, sold for {Format.Credits(row.earned)}` else `What they brought in has sold for {Format.Credits(row.earned)}`
      end
      -- (one who is gone for with the pilot somewhere else: that first, and plainly)
      if row.hunted then
        Im.Text(shorten(`{row.shipName}: UNDER ATTACK in {row.where}` .. (if row.post ~= "" then `, at {row.post}` else ""), 58),
          right + 24, line + 22, 12, Theme.CAUTION)
      else
        Im.Text(shorten(`{row.shipName} ({Ships.byId[row.hull].name}), {where}`, 58), right + 24, line + 22, 12, Theme.DIM)
      end
    else
      Im.Text("No ship: give them one of yours that is docked here.", right, line + 22, 12, Theme.CAUTION)
    end
    if row.ship == 0 then
      -- (the ships here they could have: the first three)
      local bx = right
      for at, ship in free do
        if at > 3 then
          break
        end
        local give: State.Command = { kind = "AssignShip", actor = 0, pilot = row.id, target = ship.id }
        local can, whyNot = Session.CanDo(session, give)
        if Im.Button(shorten(`Give {ship.name}`, 16), bx, line + 42, 124, 24, can, `Give:{index}:{at}`) then
          Session.Do(session, give)
        end
        reason = reason or (if can then nil else whyNot)
        bx += 128
      end
      if #free == 0 then
        Im.Text("No ship of yours is free here (the Ships window).", right, line + 46, 12, Theme.DIM)
      end
    elseif here then
      -- Docked here: what in the hangar they are to carry, and where to.
      local targets = Core.Query.HaulTargets(game, row.id, if session.destination ~= 0 then session.destination else nil)
      local what = math.clamp(haulWhat[row.id] or 1, 1, #Fleet.CARGO)
      local to = math.clamp(haulTo[row.id] or 1, 1, math.max(1, #targets))
      local kind = Fleet.CARGO[what]
      if Im.Button(`Carry {CARGO[kind]}`, right, line + 42, 112, 24, true, `Haul:what:{index}`) then
        haulWhat[row.id] = what % #Fleet.CARGO + 1
      end
      local target = targets[to]
      if Im.Button(if target then shorten(`to {target.name}`, 17) else "nowhere to go", right + 116, line + 42, 124, 24, #targets > 1,
        `Haul:to:{index}`) then
        haulTo[row.id] = to % #targets + 1
      end
      -- (and the station shown, as one more to collect at on the way: a
      -- round of several. Pressed again, it is not one.)
      local also: { number } = haulAlso[row.id] or {}
      haulAlso[row.id] = also
      local added = if target then table.find(also, target.id) else nil
      if Im.Toggle("+", right + 244, line + 42, 22, 24, added ~= nil, `Haul:also:{index}`) and target then
        if added then
          table.remove(also, added)
        elseif #also + 1 < Fleet.STOPS then
          table.insert(also, target.id)
        end
      end
      -- (or as one more to carry to: a load to each in turn, the one
      -- picked last first. Pressed again, it is not one.)
      local more: { number } = haulMore[row.id] or {}
      haulMore[row.id] = more
      local dropped = if target then table.find(more, target.id) else nil
      if Im.Toggle("&", right + 268, line + 42, 22, 24, dropped ~= nil, `Haul:drop:{index}`) and target then
        if dropped then
          table.remove(more, dropped)
        elseif #more + 1 < Fleet.DROPS then
          table.insert(more, target.id)
        end
      end
      local haul: State.Command = { kind = "FleetOrder", actor = 0, what = "haul", pilot = row.id, target = if target then target.id else 0,
        type = kind, stops = if #also > 0 then table.clone(also) else nil, drops = if #more > 0 then table.clone(more) else nil }
      local can, whyNot = Session.CanDo(session, haul)
      if Im.Button("Haul", right + 292, line + 42, 48, 24, can, `Haul:go:{index}`) then
        Session.Do(session, haul)
      end
      reason = if can then nil else whyNot
      if target and row.order ~= "haul" and row.order ~= "buy" and row.order ~= "stock" then
        note = `{target.name}: ` .. (if target.jumps == 0 then "in this system" elseif target.jumps == 1 then `1 jump, in {target.system}`
          else `{target.jumps} jumps, in {target.system}`) .. (if target.market then ", has a market" else ", no market")
      end
      if #also > 0 then
        -- (the round as it stands: here, and the stations added with +, in order)
        local names: { string } = {}
        for _, id in also do
          local stop = Core.Query.Body(game, id)
          table.insert(names, if stop then shorten(stop.name, 22) else "?")
        end
        note = `Collecting here, then at {table.concat(names, ", ")}` .. (if target and not added then `; to {target.name}` else "; + is another, then pick where to")
      end
      if #more > 0 then
        -- (and where else it is carried to, a load to each in turn)
        local names: { string } = {}
        for _, id in more do
          local drop = Core.Query.Body(game, id)
          table.insert(names, if drop then shorten(drop.name, 22) else "?")
        end
        note = (if target and not dropped then `A load to {shorten(target.name, 22)}, then to ` else "A load in turn to ")
          .. table.concat(names, ", ") .. (if #also > 0 then " (collecting at more than here)" else "")
      end
    else
      -- Out flying: called back, they come to where you are.
      local recall: State.Command = { kind = "FleetOrder", actor = 0, what = "follow", pilot = row.id }
      if Im.Button("Recall", right, line + 42, 90, 24, row.order ~= "follow" and (Session.CanDo(session, recall)), `Recall:{index}`) then
        Session.Do(session, recall)
      end
    end
    if row.ship ~= 0 then
      -- (what they bring in, mined or carried, is sold where there is a market)
      local sell: State.Command = { kind = "FleetOrder", actor = 0, what = if row.sells then "keep" else "sell", pilot = row.id }
      if Im.Toggle("Sell", right + 344, line + 42, 40, 24, row.sells, `Sells:{index}`) then
        Session.Do(session, sell)
      end
    end
    local off: State.Command = { kind = "AssignShip", actor = 0, pilot = row.id, target = 0 }
    if row.ship ~= 0 and Im.Button("Take off", right + 388, line + 42, 64, 24, (Session.CanDo(session, off)), `TakeOff:{index}`) then
      Session.Do(session, off)
    end
    local dismiss: State.Command = { kind = "DismissPilot", actor = 0, pilot = row.id }
    if Im.Button("Dismiss", right + 456, line + 42, 64, 24, (Session.CanDo(session, dismiss)), `Dismiss:{index}`) then
      Session.Do(session, dismiss)
    end
    if reason then
      Im.Text(shorten(reason, 70), right, line + 69, 12, Theme.CAUTION)
    elseif note ~= "" then
      Im.Text(shorten(note, 84), right, line + 69, 12, Theme.DIM)
    end
    line += 90
  end
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked (the window is a station's: Windows.Berthed).
function Crew.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Crew.ID, docked)
end

Windows.Kind(Crew.ID, function(_: Windows.Window, x: number, y: number, w: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  if player.docked == 0 then
    Im.Text("Pilots are hired, and given their ships and their work, at a station: dock at one.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local was = Im.Plain(true)
  -- Its two pages.
  local tx = x + 10
  for _, each in { { "pilots", "Pilots" }, { "log", "Log" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, crewPage == each[1], `Crew:{each[1]}`)
    if pressed then
      crewPage = each[1]
    end
    tx += wide + 2
  end
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  -- (what is under them is laid out as the tab was, from where its corner would be)
  drawCrew(session, game, player, x - 4, y - 66 + 32)
  Im.Plain(was)
end)
Windows.Make(Crew.ID, Crew.ID, "Crew", 534, 130, 932, 580, 932, 580, nil)
Windows.Icon(Crew.ID, "crew")

return Crew
