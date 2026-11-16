--!strict
-- What is left of the docked screen: industry, the crew, the wallet and
-- the jobs, a tab each; and, at the
-- station a new pilot starts at, the career agents (Game/UI/Careers).
-- It was the whole of the interface while docked. The market and the
-- fitting of the ship, the ships kept here and the pilot's skills were
-- tabs of it, and are windows of their own now (Game/UI/Market,
-- Game/UI/Fitting, Game/UI/Ships, Game/UI/Skills), as the rest are to
-- be; and what a
-- pilot does at any station (to undock, to make it home) is beside the
-- corner's panel (Game/UI/Hud). So it is not open by itself any more:
-- the dock opens it at a tab, and shuts it.
--
-- Drawn every frame with Game/UI/Im. It reads the Core through queries
-- and acts on it only through the Session. Every button has a name a
-- script can press it by (Im.Press): its label, or the id given here.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Careers = require("@lt/Game/UI/Careers")
local Catalog = require("@lt/Core/Data/Catalog")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Industry = require("@lt/Core/Assets/Industry")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Ores = require("@lt/Core/Data/Ores")
local Reactions = require("@lt/Core/Data/Reactions")
local Session = require("@lt/Game/Session")
local Assault = require("@lt/Core/Tactical/Assault")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Moons = require("@lt/Core/Data/Moons")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Station = {}

Station.WIDTH = 940
Station.HEIGHT = 600

local TABS: { string } = { "Industry", "Crew", "Wallet", "Missions" }
-- (and one more at a starbase of the pilot's own: the running of it)
local OWN: { string } = { "Industry", "Crew", "Wallet", "Missions", "Starbase" }
-- (and at the station the career agents are at: them)
local SCHOOL: { string } = { "Industry", "Crew", "Wallet", "Missions", "Careers" }
-- The services each tab's doings are done by (Core/Assets/Stations).
local WANTS: { [string]: { string } } = {
  Industry = { "refining", "industry", "research" },
}
local tab = "Industry"
local dockedAt = 0    -- the station the pilot was last seen docked at (Station.Arrived)

-- (The market was a tab here: it is a window of its own now, Game/UI/Market.)

-- The name typed for a system of the pilot's own (the Starbase tab).
local claimName = ""

-- The job whose "Call off" has been pressed once, and the frames it
-- stays asked for: a second press within them calls it off.
local calling = { job = 0, left = 0 }

-- Industry: the blueprint shown and the runs entered.
local blueprintChosen = ""
local runs = 1

local GOOD = vector.create(0.45, 0.85, 0.55)
local HOSTILE = vector.create(0.85, 0.35, 0.3)

-- ---------------------------------------------------------------------
-- Small pieces

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- A type's stack in a station's hangar, and how many it holds.
local function inHangar(game: Core.Game, station: number, type: string): (State.Item?, number)
  for _, item in Core.Query.Items(game, station, "hangar") do
    if item.type == type then
      return item, item.quantity
    end
  end
  return nil, 0
end

-- What is done when one of this screen's tabs is shown: it is brought
-- in front of the windows about it (set by whoever draws the windows,
-- Game/UI/Hud). And how the market is opened at a type, which is a
-- window of its own (set by Game/UI/Market, which draws on this and so
-- cannot be drawn on from here).
Station.Front = nil :: (() -> ())?
Station.Market = nil :: ((type: string) -> boolean)?

-- Show a tab, as clicking it would: for scripted runs, and the dock.
function Station.Show(name: string): boolean
  for _, known in { OWN, SCHOOL } do
    if table.find(known, name) then
      tab = name
      if Station.Front then
        Station.Front()
      end
      return true
    end
  end
  return false
end

function Station.Tab(): string
  return tab
end

-- The tabs there are at the station the pilot is docked at: one more at
-- a starbase of their own (the running of it), and one more where the
-- career agents are.
function Station.Tabs(game: Core.Game, player: Core.PlayerInfo): { string }
  local starbase = Core.Query.Starbase(game, player.docked)
  if starbase and starbase.mine then
    return OWN
  end
  return if Core.Query.Careers(game).station == player.docked then SCHOOL else TABS
end

-- Once a frame while the pilot is docked: whether they have just come
-- to a starbase of their own, where the running of it is what they have
-- come for. The screen is then to be opened, and is at that tab.
function Station.Arrived(game: Core.Game, player: Core.PlayerInfo): boolean
  if player.docked == dockedAt then
    return false
  end
  dockedAt = player.docked
  local starbase = Core.Query.Starbase(game, player.docked)
  if starbase and starbase.mine then
    tab = "Starbase"
    return true
  end
  return false
end

-- And once a frame while they are not.
function Station.Left()
  dockedAt = 0
end

-- Open the industry tab at a blueprint, or at a copy of one, as
-- clicking its row would.
function Station.Blueprint(type: string): boolean
  if Blueprints.Of(type) == nil then
    return false
  end
  tab = "Industry"
  if blueprintChosen ~= type then
    blueprintChosen = type
    runs = 1
  end
  if Station.Front then
    Station.Front()
  end
  return true
end

-- ---------------------------------------------------------------------
-- Industry

local function drawIndustry(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78
  local left = x + 16
  local hangar = Core.Query.Items(game, station, "hangar")

  -- On the left, what is here: blueprints (and copies of them), ore, and
  -- the jobs running. On the right, the blueprint chosen: the job it
  -- would be, and what a laboratory does with it.

  -- Blueprints here.
  local blueprints: { State.Item } = {}
  local ores: { State.Item } = {}
  for _, item in hangar do
    if Blueprints.Of(item.type) then
      table.insert(blueprints, item)
    elseif Ores.byId[item.type] then
      table.insert(ores, item)
    end
  end
  Im.Heading(`BLUEPRINTS HERE  {#blueprints}`, left, top, 16, Im.DIM)
  local line = top + 26
  if #blueprints == 0 then
    Im.Text("None. The market sells them, under Blueprints.", left, line, 14, Im.DIM, 0.8)
  end
  local visible = 6
  local first = Im.Scroll("blueprints", left - 4, line, 434, visible * 24, #blueprints, visible)
  for row = 1, visible do
    local item = blueprints[row + first]
    if item == nil then
      break
    end
    local blueprint, copy = Blueprints.Of(item.type)
    assert(blueprint)
    local rowY = line + (row - 1) * 24
    local _, clicked = Im.Row(left - 4, rowY, 430, 24, blueprintChosen == item.type)
    Im.Text(shorten(Types.Info(blueprint.product).name, 34), left + 4, rowY + 4, 14, Im.TEXT)
    -- (a copy says how many runs it is still good for)
    Im.TextRight(if copy then `copy: {Format.Whole(item.quantity)} {if item.quantity == 1 then "run" else "runs"} left`
      else `makes {blueprint.perRun} a run`, left + 418, rowY + 5, 12, if copy then Im.ACCENT else Im.DIM)
    if clicked then
      blueprintChosen = item.type
      runs = 1
    end
  end

  -- Ore to refine.
  line = top + 26 + visible * 24 + 14
  Im.Heading(`ORE HERE  {#ores}`, left, line, 16, Im.DIM)
  line += 26
  if #ores == 0 then
    Im.Text("None. Mine some at a belt and bring it back.", left, line, 14, Im.DIM, 0.8)
  end
  local oreRows = 3
  local firstOre = Im.Scroll("ores", left - 4, line, 434, oreRows * 26, #ores, oreRows)
  for row = 1, oreRows do
    local item = ores[row + firstOre]
    if item == nil then
      break
    end
    local rowY = line + (row - 1) * 26
    Im.Text(`{Types.Info(item.type).name}  x{Format.Whole(item.quantity)}`, left + 4, rowY + 3, 14, Im.TEXT)
    local can = Session.CanDo(session, { kind = "Reprocess", actor = 0, item = item.id })
    if Im.Button("Refine", left + 348, rowY, 70, 22, can, `Refine:{item.type}`) then
      Session.Do(session, { kind = "Reprocess", actor = 0, item = item.id })
    end
  end

  -- Jobs running, here and elsewhere.
  calling.left = math.max(0, calling.left - 1)
  local jobs = Core.Query.Jobs(game, nil)
  line += oreRows * 26 + 14
  Im.Heading(`JOBS  {#jobs} / {Core.Query.JobSlots(game)}`, left, line, 16, Im.DIM)
  line += 26
  if #jobs == 0 then
    Im.Text("Nothing is being built.", left, line, 14, Im.DIM, 0.8)
  end
  local jobRows = 3
  local firstJob = Im.Scroll("jobs", left - 4, line, 434, jobRows * 42, #jobs, jobRows)
  for row = 1, jobRows do
    local index = row + firstJob
    local job = jobs[index]
    if job == nil then
      break
    end
    local rowY = line + (row - 1) * 42
    local where = Core.Query.Body(game, job.station)
    local remaining = job.ends - game.state.tick
    -- (a copying and an inventing are named for what the blueprint
    -- builds, as the rows above are)
    local held = Blueprints.Of(job.blueprint)
    local drawing = if held then held.name else Types.Info(job.blueprint).name
    local builds = if held then Types.Info(held.product).name else drawing
    Im.Text(if job.research == "copy" then `Copying, {Format.Whole(job.quantity)} {if job.quantity == 1 then "run" else "runs"}: {shorten(builds, 28)}`
      elseif job.research == "invent" then `Inventing from a copy: {shorten(builds, 24)}`
      elseif job.research ~= "" then `Research ({job.research}): {shorten(drawing, 26)}`
      else `{Format.Whole(job.quantity)} x {shorten(Types.Info(job.product).name, 30)}`, left + 4, rowY, 14, Im.TEXT)
    Im.TextRight(Format.Duration(remaining * Constants.TICK), left + 418, rowY, 14, Im.TEXT)
    Im.Text(if job.station == station then "here" else shorten(if where then where.name else "?", 30), left + 4, rowY + 18, 12, Im.DIM)
    local span = math.max(1, job.ends - job.started)
    -- (called off where it runs: pressed once it asks, and pressed again
    -- within a few seconds it is done. What went into the runs not
    -- finished is lost.)
    local cancel: State.Command = { kind = "CancelJob", actor = 0, target = job.id }
    local armed = calling.job == job.id and calling.left > 0
    if job.station == station and Im.Button(if armed then "Sure?" else "Call off", left + 64, rowY + 16, 76, 20, (Session.CanDo(session, cancel)),
      `Job:cancel:{index}`) then
      if armed then
        Session.Do(session, cancel)
        calling.job, calling.left = 0, 0
      else
        calling.job, calling.left = job.id, 240
      end
    end
    Im.Fill(left + 154, rowY + 23, 264, 4, Im.DIM, 0.25)
    Im.Fill(left + 154, rowY + 23, 264 * math.clamp(1 - remaining / span, 0, 1), 4, Im.ACCENT, 0.95)
  end

  -- The job the chosen blueprint would be.
  local dx = x + 470
  line = top
  local chosenItem = inHangar(game, station, blueprintChosen)
  local plan = if chosenItem then Core.Query.JobPlan(game, station, blueprintChosen, math.max(1, runs)) else nil
  if plan == nil or chosenItem == nil then
    Im.Heading("NEW JOB", dx, line, 16, Im.DIM)
    Im.Text("Choose a blueprint.", dx, line + 28, 14, Im.DIM, 0.8)
    return
  end
  local product = Types.Info(plan.blueprint.product)
  local _, isCopy = Blueprints.Of(blueprintChosen)
  Im.Heading(if isCopy then "NEW JOB, FROM A COPY" else "NEW JOB", dx, line, 16, Im.DIM)
  line += 26
  Im.Text("Runs", dx, line + 5, 14, Im.DIM)
  runs = Im.Number("Runs", runs, dx + 80, line, 100, 26)
  -- as many runs as the minerals here allow (and as a copy has left)
  local most = if isCopy then math.min(100, chosenItem.quantity) else 100
  for _, m in plan.blueprint.materials do
    local _, have = inHangar(game, station, m.type)
    most = math.min(most, have // m.quantity)
  end
  for index, preset in { 1, 10 } do
    if Im.Button(tostring(preset), dx + 190 + (index - 1) * 52, line, 48, 26, true, `Runs:{preset}`) then
      runs = preset
    end
  end
  if Im.Button(`Most ({most})`, dx + 294, line, 100, 26, most >= 1, "Runs:most") then
    runs = most
  end
  line += 36
  Im.Text(`Makes {Format.Whole(plan.quantity)} x {product.name}`, dx, line, 14, Im.TEXT)
  line += 24
  -- (a hull or a tower is built of a dozen things and more: as many as
  -- fit, and the wheel for the rest)
  local materialRows = 7
  local firstMaterial = Im.Scroll("materials", dx, line, 452, materialRows * 20, #plan.materials, materialRows)
  for row = 1, materialRows do
    local m = plan.materials[row + firstMaterial]
    if m == nil then
      break
    end
    local enough = m.have >= m.need
    Im.Text(Types.Info(m.type).name, dx + 12, line, 14, Im.DIM)
    Im.TextRight(Format.Whole(m.need), dx + 240, line, 14, if enough then Im.TEXT else Im.WARN)
    Im.TextRight(`{Format.Whole(m.have)} here`, dx + 440, line, 13, if enough then Im.DIM else Im.WARN)
    line += 20
  end
  line += 6
  Im.Text(`Takes {Format.Duration(plan.seconds)}`, dx, line, 14, Im.TEXT)
  Im.TextRight(`fee {Format.Credits(plan.fee)}`, dx + 446, line, 14, Im.TEXT)
  line += 28
  local job: State.Command = { kind = "StartJob", actor = 0, item = chosenItem.id, quantity = runs }
  local can, whyNot = Session.CanDo(session, job)
  if Im.Button("Start job", dx, line, 160, 30, can, "StartJob") then
    Session.Do(session, job)
  end
  if not can then
    Im.Text(tostring(whyNot), dx + 172, line + 8, 13, Im.WARN)
  end
  line += 40
  -- The laboratory: what the pilot has learned of this design and the
  -- next level of each kind, a copy of it, and the inventing of its
  -- tech 2 make.
  local research = Core.Query.Research(game, plan.blueprint.id)
  if research == nil then
    return
  end
  Im.Heading("LABORATORY", dx, line, 14, Im.DIM)
  Im.TextRight(`researched: materials -{research.material}%, time -{research.time * 2}%`, dx + 446, line + 1, 12, Im.DIM)
  line += 24
  if isCopy then
    Im.Text("Research and copying take the blueprint itself, not a copy.", dx, line, 12, Im.DIM, 0.8)
    line += 22
  else
    for index, what in { "material", "time" } do
      local next: Industry.ResearchPlan? = if what == "material" then research.nextMaterial else research.nextTime
      local study: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = what }
      local canStudy = next ~= nil and (Session.CanDo(session, study))
      local bx = dx + (index - 1) * 226
      if Im.Button(if what == "material" then "Research materials" else "Research time", bx, line, 150, 26, canStudy,
        `Research:{what}`) then
        Session.Do(session, study)
      end
      Im.Text(if next then `{Format.Duration(next.seconds)}` else "done", bx + 156, line - 1, 12, Im.DIM)
      if next then
        Im.Text(Format.Credits(next.fee), bx + 156, line + 13, 12, Im.DIM)
      end
    end
    line += 34
    -- (a copy good for the runs entered above: what a job or an
    -- invention can use up in place of the blueprint)
    local copying = Core.Query.CopyPlan(game, blueprintChosen, math.max(1, runs))
    if copying then
      local copy: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = "copy", quantity = runs }
      local canCopy, whyNotCopy = Session.CanDo(session, copy)
      if Im.Button("Copy", dx, line, 150, 26, canCopy, "Copy") then
        Session.Do(session, copy)
      end
      Im.Text(`a copy good for {Format.Whole(copying.runs)} {if copying.runs == 1 then "run" else "runs"}, {Format.Duration(copying.seconds)}`,
        dx + 156, line - 1, 12, Im.DIM)
      Im.Text(if canCopy then Format.Credits(copying.fee) else shorten(tostring(whyNotCopy), 44), dx + 156, line + 13, 12,
        if canCopy then Im.DIM else Im.WARN)
      line += 34
    end
  end
  local invention = research.invention
  if invention then
    local invent: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = "invent" }
    local canInvent, whyNotInvent = Session.CanDo(session, invent)
    if Im.Button("Invent tech 2", dx, line, 150, 26, canInvent, "Invent") then
      Session.Do(session, invent)
    end
    Im.Text(string.format("%d datacores, %s, %d%% chance", invention.datacores, Format.Duration(invention.seconds),
      math.floor(invention.chance * 100 + 0.5)), dx + 156, line - 1, 12, Im.DIM)
    Im.Text(if canInvent then Format.Credits(invention.fee) else shorten(tostring(whyNotInvent), 44), dx + 156, line + 13, 12,
      if canInvent then Im.DIM else Im.WARN)
  end
end

-- ---------------------------------------------------------------------
-- Crew: pilots to hire, and the pilots hired (Core/Tactical/Fleet)

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

function Station.CrewPage(): string
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
  Im.Heading(`FIGHTS YOU WERE NOT AT  {#log}`, x, y, 16, Im.DIM)
  local line = y + 30
  if #log == 0 then
    Im.Text("None on record. When a pilot of yours is attacked while you are somewhere else, how it went is put down here.", x, line, 13,
      Im.DIM, 0.8)
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
    Im.Text(`{Format.Clock(fight.began)}   {shorten(fight.where, 46)}`, x, rowY, 14, Im.TEXT)
    Im.TextRight(if over then `over in {Format.Duration((fight.ended - fight.began) * Constants.TICK)}`
      .. (if fight.joined then ", you came to it" else "") else "going on now", x + width - 8, rowY + 1, 12, if over then Im.DIM else Im.WARN)
    Im.Text(shorten(`{table.concat(fight.pilots, ", ")} against {if #fight.attackers > 0 then tallied(fight.attackers) else "nobody seen"}`, 112),
      x, rowY + 19, 12, Im.DIM)
    local came = if #fight.destroyed > 0 then `destroyed: {tallied(fight.destroyed)}` else "nothing destroyed"
    if fight.fled > 0 then
      came ..= `, {fight.fled} got away`
    end
    Im.Text(shorten(came, 70), x, rowY + 35, 12, Im.TEXT)
    if #fight.lost > 0 then
      Im.Text(shorten(`lost: {table.concat(fight.lost, ", ")}`, 44), x + 420, rowY + 35, 12, Im.WARN)
    end
    Im.TextRight(if fight.bounty > 0 then `bounty {Format.Credits(fight.bounty)}` else "no bounty", x + width - 8, rowY + 35, 12,
      if fight.bounty > 0 then GOOD else Im.DIM)
    Im.Fill(x, rowY + 55, width - 8, 1, Im.DIM, 0.15)
  end
end

local function drawCrew(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local left, right = x + 16, x + 400
  local line = y + 78
  -- (the tab's two sides: the pilots, and the log of their fights)
  if Im.Toggle("Pilots", x + 770, line - 6, 70, 26, crewPage == "pilots", "Crew:pilots") then
    crewPage = "pilots"
  end
  if Im.Toggle("Log", x + 844, line - 6, 80, 26, crewPage == "log", "Crew:log") then
    crewPage = "log"
  end
  if crewPage == "log" then
    drawFleetLog(game, left, line, 908)
    return
  end
  local candidates, most = Core.Query.Candidates(game, station)
  local fleet = Core.Query.Fleet(game)

  Im.Heading("LOOKING FOR WORK HERE", left, line, 16, Im.DIM)
  line += 30
  if #candidates == 0 then
    Im.Text("Nobody more today.", left, line, 14, Im.DIM, 0.8)
  end
  for index, found in candidates do
    Im.Text(found.name, left, line, 15, Im.TEXT)
    Im.TextRight(`grade {found.skill}`, left + 350, line, 15, Im.ACCENT)
    Im.Text(`{Format.Credits(found.wage)} a day`, left, line + 21, 12, Im.DIM)
    Im.TextRight(`{Format.Credits(found.fee)} to sign`, left + 350, line + 21, 12, Im.DIM)
    local hire: State.Command = { kind = "HirePilot", actor = 0, what = found.key }
    local can, whyNot = Session.CanDo(session, hire)
    if Im.Button("Hire", left, line + 42, 90, 24, can, `Hire:{index}`) then
      Session.Do(session, hire)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 38), left + 100, line + 46, 12, Im.WARN)
    end
    line += 84
  end
  line = y + 78 + 30 + 3 * 84 + 4
  Im.Heading("WHAT A PILOT IS", left, line, 14, Im.DIM)
  for index, text in { "A hired pilot flies a ship of yours and goes where you go:", "out when you undock, to warp and through gates after you,",
    "into a fight beside you. Every skill counts as their grade.", "Grade 1 flies frigates and haulers, 2 destroyers and barges,",
    "3 cruisers, 4 battleships and freighters. You command one a level", "of Leadership. A ship lost is insured; its pilot is not lost.",
    "In space one can be set to mine a belt, to hold a place against", "pirates (Patrol here) or to go with another pilot (Guard);",
    "one docked here to haul what is in your hangar elsewhere (+", "adds a station to collect at on the way: a round); any to",
    "sell what they bring in. They learn by it, to grade 5." } do
    -- (eleven lines in the room ten had)
    Im.Text(text, left, line + 6 + index * 15.5, 12, Im.DIM)
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
    right, line, 16, Im.DIM)
  line += 30
  if #fleet == 0 then
    Im.Text("Nobody is hired.", right, line, 14, Im.DIM, 0.8)
  end
  for index, row in fleet do
    if index > 5 then
      break
    end
    Im.Text(row.name, right, line, 15, Im.TEXT)
    -- (their grade, and how far they are toward the next)
    Im.Text(if row.needed > 0 then `grade {row.skill}  {row.experience} / {row.needed}` else `grade {row.skill}`, right + 210, line + 1,
      13, Im.ACCENT)
    -- (and how they stand toward the pilot)
    Im.Text(row.mood, right + 352, line + 1, 13, if row.mood == "wary" then Im.WARN elseif row.mood == "devoted" then GOOD else Im.DIM)
    Im.TextRight(`{Format.Credits(row.wage)} a day`, right + 520, line + 1, 13, Im.DIM)
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
          right + 24, line + 22, 12, Im.WARN)
      else
        Im.Text(shorten(`{row.shipName} ({Ships.byId[row.hull].name}), {where}`, 58), right + 24, line + 22, 12, Im.DIM)
      end
    else
      Im.Text("No ship: give them one of yours that is docked here.", right, line + 22, 12, Im.WARN)
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
        Im.Text("No ship of yours is free here (Ships tab).", right, line + 46, 12, Im.DIM)
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
      Im.Text(shorten(reason, 70), right, line + 69, 12, Im.WARN)
    elseif note ~= "" then
      Im.Text(shorten(note, 84), right, line + 69, 12, Im.DIM)
    end
    line += 90
  end
end

-- ---------------------------------------------------------------------
-- Missions: the jobs a station has, and the jobs in hand

-- (Whether the left of it shows the faction's loyalty store in place of
-- the jobs offered.)
local storeOpen = false

-- The level of each line of work with levels that the list shows: the
-- hardest there is, until the pilot steps it down.
local ladder: { [string]: number } = {}

-- Which level of a line of work ("assault", "mining", "courier",
-- "defence") the list shows: given one, it is set to that. 0: the
-- hardest there is.
function Station.Level(kind: string, to: number?): number
  if to then
    ladder[kind] = to
  end
  return ladder[kind] or 0
end

local function drawMissions(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Missions(game)
  local left, right = x + 16, x + 480
  local line = y + 78
  local function about(mission: State.Mission, jumps: number, ward: number): string
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

  Im.Heading(if storeOpen then "LOYALTY STORE" else "JOBS OFFERED HERE", left, line, 16, Im.DIM)
  -- (the faction's store, and the way back from it)
  if Im.Toggle(if storeOpen then `Back to the jobs  ({status.loyalty} LP)` else `Loyalty store: {status.loyalty} LP`, left + 230, line - 4,
    200, 24, storeOpen, "LoyaltyStore") then
    storeOpen = not storeOpen
  end
  line += 30
  -- The store: what the faction lets a pilot have for loyalty points.
  if storeOpen then
    if #status.store == 0 then
      Im.Text("There is no store here.", left, line, 14, Im.DIM, 0.8)
    end
    -- (more than fit: the list scrolls)
    local visible = 21
    local first = Im.Scroll("LoyaltyStore", left, line, 440, visible * 20, #status.store, visible)
    for index, row in status.store do
      if index <= first then
        continue
      elseif index > first + visible then
        break
      end
      Info.Name(row.stock.type, shorten(row.name, 30), left, line + 1, 13, if row.can then Im.TEXT else Im.DIM)
      if row.can or string.sub(row.why, 1, 5) ~= "needs" then
        Im.TextRight(`{row.stock.points} LP` .. (if row.stock.credits > 0 then `  {Format.Credits(row.stock.credits)}` else ""),
          left + 372, line + 2, 12, Im.DIM)
      else
        Im.TextRight(shorten(row.why, 36), left + 372, line + 2, 11, Im.WARN)
      end
      if Im.Button("Get", left + 380, line, 50, 18, row.can, `Redeem:{row.stock.type}`) then
        Session.Do(session, { kind = "RedeemLoyalty", actor = 0, type = row.stock.type, quantity = 1 })
      end
      line += 20
    end
  elseif #status.offers == 0 then
    Im.Text("Nothing more today.", left, line, 14, Im.DIM, 0.8)
  end
  -- The day's jobs, each a row; then the fourth agent's assault, the
  -- fifth's mining contract, the sixth's courier contract and the
  -- seventh's defence job, a row each: the level shown is stepped up
  -- and down, as far as the pilot's standing has opened.
  local offers: { Core.MissionStatus } = if storeOpen then {} else status.offers
  local function offered(offer: Core.MissionStatus, id: string, kind: string?, level: number, levels: number)
    -- (a job with levels says its level in a word less: the steps beside it say the rest)
    Im.Text(shorten(if kind then (string.gsub(offer.title, ", level", "", 1)) else offer.title, if kind then 30 else 34), left, line, 15,
      Im.TEXT)
    -- (or what it pays with: one of the people's own makes)
    local pays = offer.mission.prize
    Im.TextRight(if pays then shorten(Types.Info(pays).name, 30) else Format.Credits(offer.mission.reward), left + 356, line,
      if pays then 13 else 15, GOOD)
    local accept: State.Command = { kind = "AcceptMission", actor = 0, what = offer.mission.key }
    local can, whyNot = Session.CanDo(session, accept)
    Im.Text(if can then shorten(about(offer.mission, offer.jumps, offer.ward), 44) else shorten(tostring(whyNot), 44), left, line + 21, 12,
      if can then Im.DIM else Im.WARN)
    -- (who gives it, what they think of the pilot once they think anything, and the points it is worth)
    local thinks = if offer.regard ~= 0 then string.format(" (%.1f)", offer.regard) else ""
    Im.TextRight(`{shorten(offer.mission.agent, 16)}{thinks}  +{offer.mission.loyalty} LP`, left + 356, line + 21, 12,
      if offer.regard > 0 then GOOD elseif offer.regard < 0 then Im.WARN else Im.DIM)
    if kind and levels > 1 then
      if Im.Button("<", left + 236, line - 1, 20, 20, level > 1, `Level:{kind}:down`) then
        ladder[kind] = level - 1
      end
      if Im.Button(">", left + 260, line - 1, 20, 20, level < levels, `Level:{kind}:up`) then
        ladder[kind] = level + 1
      end
    end
    if Im.Button("Accept", left + 364, line + 4, 66, 28, can, id) then
      Session.Do(session, accept)
    end
    line += 50
  end
  local daily = 0
  for _, offer in offers do
    if offer.mission.level == 0 then
      daily += 1
      offered(offer, `Accept:{daily}`, nil, 0, 0)
    end
  end
  for _, kind in { "assault", "mining", "courier", "defence" } do
    local levels: { Core.MissionStatus } = {}
    for _, offer in offers do
      if offer.line == kind then
        table.insert(levels, offer)
      end
    end
    if #levels > 0 then
      local level = math.clamp(if (ladder[kind] or 0) == 0 then #levels else ladder[kind], 1, #levels)
      offered(levels[level], `Accept:{kind}`, kind, level, #levels)
    end
  end

  -- What every faction thinks of the pilot (it is their stations' fees,
  -- their jobs' pay and, at the worst, their patrols' guns).
  if not storeOpen then
    line = y + 78 + 30 + 7 * 50 + 16
    Im.Heading("STANDINGS", left, line, 14, Im.DIM)
    for index, row in Core.Query.Standings(game) do
      -- (four to a row: the four human factions, and under them any
      -- other that has come to think something of the pilot)
      local sx = left + (index - 1) % 4 * 110
      local sy = line + (index - 1) // 4 * 44
      Im.Text(row.name, sx, sy + 24, 13, Im.DIM)
      Im.Text(string.format("%.1f", row.standing), sx, sy + 42, 15, if row.hostile then HOSTILE elseif row.standing < 0 then Im.WARN else Im.TEXT)
      if row.hostile then
        Im.Text("hostile", sx + 44, sy + 44, 12, HOSTILE)
      end
    end
  end

  line = y + 78
  Im.Heading(`IN HAND  {#status.inHand} / 5`, right, line, 16, Im.DIM)
  Im.TextRight(`{status.done} done`, right + 430, line + 2, 13, Im.DIM)
  line += 30
  if #status.inHand == 0 then
    Im.Text("No jobs in hand.", right, line, 14, Im.DIM, 0.8)
  end
  for index, held in status.inHand do
    Im.Text(held.title, right, line, 15, Im.TEXT)
    local paid = held.mission.prize
    Im.TextRight(if paid then shorten(Types.Info(paid).name, 30) else Format.Credits(held.mission.reward), right + 430, line,
      if paid then 13 else 15, GOOD)
    -- (a rig that is going down says so in the colour of a warning)
    Im.Text(shorten(about(held.mission, held.jumps, held.ward), 68), right, line + 21, 12,
      if held.ward >= 0 and held.ward < 0.5 and held.mission.done < held.mission.need then Im.WARN else Im.DIM)
    -- (how long it can still be kept: in the colour of a warning at the last)
    Im.TextRight(Format.Duration(held.left), right + 430, line + 21, 12, if held.left < 6 * 3600 then Im.WARN else Im.DIM)
    local complete: State.Command = { kind = "CompleteMission", actor = 0, target = held.mission.id }
    if Im.Button("Complete", right, line + 42, 90, 24, held.ready, `Complete:{index}`) then
      Session.Do(session, complete)
    end
    if not held.ready then
      Im.Text(shorten(held.why, 34), right + 100, line + 46, 12, Im.DIM)
    end
    if Im.Button("Abandon", right + 350, line + 42, 80, 24, true, `Abandon:{index}`) then
      Session.Do(session, { kind = "AbandonMission", actor = 0, target = held.mission.id })
    end
    line += 84
  end
end

-- ---------------------------------------------------------------------
-- Careers: the agents who show a new pilot the ropes (Game/UI/Careers
-- draws them: the list on the left, the one picked out on the right)

local function drawCareers(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Careers(game)
  local left, right = x + 16, x + 480
  Im.Heading("CAREER AGENTS", left, y + 78, 16, Im.DIM)
  Im.Text("Seven people who teach a way of making a living each, and pay for the learning.", left, y + 104, 13, Im.DIM)
  Im.Text("A lesson from each can be in hand at once. The Guide (top left) shows them in space.", left, y + 122, 13, Im.DIM)
  Careers.List(status, left - 8, y + 152, 448)
  Careers.Detail(session, status, right, y + 78, 444)
end

-- ---------------------------------------------------------------------
-- Starbase: the running of a tower of the pilot's own

-- A bar of what is used of what there is, with the figures over it.
local function supply(label: string, used: number, capacity: number, unit: string, x: number, y: number, width: number)
  Im.Text(label, x, y, 13, Im.DIM)
  Im.TextRight(`{Format.Whole(used)} / {Format.Whole(capacity)} {unit}`, x + width, y, 13, Im.TEXT)
  Im.Fill(x, y + 20, width, 6, Im.DIM, 0.25)
  Im.Fill(x, y + 20, width * math.clamp(used / math.max(1, capacity), 0, 1), 6, if used > capacity * 0.9 then Im.WARN else Im.ACCENT, 0.95)
end

local function drawStarbase(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus,
  x: number, y: number)
  local station = player.docked
  local left = x + 16
  local line = y + 78
  local tower = status.tower

  -- The tower: its fuel, and what it supplies.
  Im.Heading("TOWER", left, line, 16, Im.DIM)
  line += 26
  ItemIcon.Draw(tower.id, left, line, 22)
  Info.Name(tower.id, tower.name, left + 30, line + 3, 15, Im.TEXT)
  -- (taken down into the hold, with nothing on it and nothing in it:
  -- pressed when it cannot be, it says why not)
  if Im.Button("Take down", left + 300, line - 1, 100, 24, true, "Tower:down") then
    Session.Do(session, { kind = "UnanchorTower", actor = 0 })
  end
  -- The pilot's claim on the system (Core/Assets/Sovereignty): how a
  -- beacon here stands, and, once the system is theirs, a name for it.
  do
    local here = Core.Query.Player(game).system
    local how, gone, takes = Core.Query.Claim(game, here)
    if how == "claiming" then
      Im.Text(`Claiming this system: {gone} of {takes} hours`, left + 420, line + 3, 13, Im.ACCENT)
    elseif how == "contested" then
      Im.Text("The beacon claims nothing: the system is somebody's.", left + 420, line + 3, 13, Im.WARN)
      Im.Text("At war with them, it is a siege: their garrison is at the lines.", left + 420, line + 20, 12, Im.DIM)
    elseif how == "held" then
      Im.Text(if gone > 0 then `Yours, but no beacon is lit: let go in {takes - gone} h` else "This system is yours", left + 420, line + 3, 13,
        if gone > 0 then Im.WARN else GOOD)
      claimName = Im.Words("Claim:name", claimName, left + 420, line + 24, 190, 24, 32, "a name for it")
      local rename: State.Command = { kind = "RenameSystem", actor = 0, target = here, what = claimName }
      if Im.Button("Rename", left + 616, line + 24, 70, 24, claimName ~= "" and (Session.CanDo(session, rename)), "Claim:rename") then
        Session.Do(session, rename)
        claimName = ""
      end
    end
  end
  line += 30
  if status.sealed > 0 then
    Im.Text(`SEALED: nothing can touch it, and it does nothing. It opens in {Format.Duration(status.sealed)}.`, left, line, 13, Im.WARN)
  elseif status.lit then
    Im.Text("Lit: its field is up and its modules have power.", left, line, 13, GOOD)
  else
    Im.Text("DARK: no fuel. Its field is down and its modules give nothing.", left, line, 13, Im.WARN)
  end
  line += 24
  Im.Text("Fuel", left, line, 13, Im.DIM)
  Im.TextRight(`{Format.Whole(status.fuel)} blocks`, left + 400, line, 13, if status.lit then Im.TEXT else Im.WARN)
  line += 20
  Im.Text(`It burns {tower.fuel} an hour`, left, line, 13, Im.DIM)
  Im.TextRight(if status.fuel > 0 then `{Format.Duration(status.hours * 3600)} left` else "none left", left + 400, line, 13,
    if status.hours >= 1 then Im.TEXT else Im.WARN)
  line += 30
  supply("Powergrid", status.powergrid, tower.powergrid, "MW", left, line, 400)
  line += 38
  supply("CPU", status.cpu, tower.cpu, "tf", left, line, 400)
  line += 44

  -- Its moon: what is under it, and how the drilling of it stands.
  local drilling = status.drilling
  local deposit = drilling.deposit
  Im.Heading(shorten(`MOON  {string.upper(status.moon)}`, 40), left, line, 16, Im.DIM)
  line += 24
  if deposit then
    ItemIcon.Draw(deposit.material.id, left, line - 1, 18)
    Info.Name(deposit.material.id, deposit.material.name, left + 24, line, 13, Im.TEXT)
    Im.TextRight(`{Moons.Word(deposit.richness)}: a drill brings up {Format.Whole(drilling.perHour)} an hour`, left + 400, line, 13, Im.DIM)
    line += 20
    local full = drilling.stored >= drilling.room
    local held = `{Format.Whole(drilling.stored)} of {Format.Whole(drilling.room)} in the hangar`
    if not drilling.anchored then
      Im.Text("No drill is anchored: a Moon Drill gets at it.", left, line, 13, Im.DIM)
    elseif full then
      Im.Text(`Full, {held}: take some away, or anchor a Storage Array.`, left, line, 13, Im.WARN)
    elseif drilling.online then
      Im.Text(`Drilling: {held}`, left, line, 13, GOOD)
      Im.TextRight(`more in {Format.Duration(status.next)}`, left + 400, line, 13, Im.DIM)
    else
      Im.Text(`The drill is not working: {held}`, left, line, 13, Im.WARN)
    end
  else
    Im.Text("Nothing under it worth a drill.", left, line, 13, Im.DIM)
    line += 20
  end
  line += 20
  -- What it has against the pirates who come for what a drill brings
  -- up, where order is thin: its batteries and whoever holds the place.
  if status.raidMost == 0 then
    Im.Text("Order is kept here: nobody raids it.", left, line, 13, Im.DIM)
  else
    local parts = `{status.batteries} {if status.batteries == 1 then "battery" else "batteries"}, {status.patrol} on patrol`
    Im.Text(`Defence {status.defence} ({parts})`, left, line, 13, if status.defence >= status.raidMost then GOOD
      elseif status.defence >= status.raidLeast then Im.TEXT else Im.WARN)
    Im.TextRight(`raids here come {status.raidLeast} to {status.raidMost} strong`, left + 400, line, 13, Im.DIM)
  end
  line += 20
  -- Under fire: what is left of its shield, its armour and its
  -- structure, the sealing charges it has, and who is after it.
  local function share(value: number): string
    return `{math.ceil(value * 100)}%`
  end
  local hurt = status.shield < 0.999 or status.armor < 0.999 or status.hull < 0.999
  Im.Text(`Shield {share(status.shield)}   armour {share(status.armor)}   structure {share(status.hull)}`, left, line, 13,
    if hurt then Im.WARN else Im.DIM)
  Im.TextRight(`sealing charges {status.charges} / {status.bay}`, left + 400, line, 13,
    if status.charges == 0 and status.besieged then Im.WARN else Im.DIM)
  line += 20
  if status.siege > 0 then
    Im.Text(if status.sealed > 0 then `They will be back when it opens: {status.siege} strong against your {status.defence}.`
      else `UNDER SIEGE: {status.siege} strong against your {status.defence}.`, left, line, 13, Im.WARN)
  elseif status.besieged then
    Im.Text(if status.charges > 0 then `A raid it does not match is a siege here: it seals for {status.charges} h at a quarter shield.`
      else "A raid it does not match is a siege here, and with no charge it does not seal.", left, line, 13,
      if status.charges > 0 then Im.DIM else Im.WARN)
  else
    Im.Text("Nobody comes to bring a tower down here.", left, line, 13, Im.DIM, 0.8)
  end
  line += 26

  -- What is anchored round it.
  Im.Heading(`ANCHORED  {#status.modules}`, left, line, 16, Im.DIM)
  line += 26
  if #status.modules == 0 then
    Im.Text("Nothing yet. A module to hand is anchored from the list on the right.", left, line, 13, Im.DIM, 0.8)
  end
  local visible = 4
  local first = Im.Scroll("anchored", left - 4, line, 420, visible * 26, #status.modules, visible)
  for row = 1, visible do
    local module = status.modules[row + first]
    if module == nil then
      break
    end
    local type = Structures.moduleById[module.type]
    ItemIcon.Draw(type.id, left, line + 1, 20)
    Info.Name(type.id, shorten(type.name, 24), left + 26, line + 3, 13, Im.TEXT)
    if module.online then
      Im.Text("online", left + 214, line + 3, 13, GOOD)
    elseif module.wait > 0 then
      Im.Text(`online in {Format.Duration(module.wait)}`, left + 214, line + 3, 13, Im.DIM)
    else
      Im.Text("no power", left + 214, line + 3, 13, Im.WARN)
    end
    local unanchor: State.Command = { kind = "UnanchorModule", actor = 0, type = type.id }
    if Im.Button("Unanchor", left + 320, line, 80, 21, (Session.CanDo(session, unanchor)), `Unanchor:{type.id}`) then
      Session.Do(session, unanchor)
    end
    line += 26
  end

  -- What there is to hand, in the hold and in the tower's hangar (the
  -- pilot's own there, and the corporation's), to burn or to anchor.
  local right = x + 480
  line = y + 78
  local hand: { { item: State.Item, where: string } } = {}
  for _, place in { "cargo", "hangar", "corporate" } do
    for _, item in Core.Query.Items(game, if place == "cargo" then player.ship else station, place) do
      if item.type == Structures.FUEL.id or item.type == Structures.SEAL.id or Structures.moduleById[item.type] then
        table.insert(hand, { item = item, where = if place == "cargo" then "hold" elseif place == "hangar" then "hangar" else "corporation" })
      end
    end
  end
  Im.Heading(`TO HAND  {#hand}`, right, line, 16, Im.DIM)
  line += 26
  if #hand == 0 then
    Im.Text("No fuel and no modules in the hold or the hangar.", right, line, 13, Im.DIM, 0.8)
    Im.Text("A market sells both, under Structures.", right, line + 20, 13, Im.DIM, 0.8)
  end
  -- (a tower with a reactor has that under the list, and a shorter list)
  local reacting = status.reacting
  local shown = if reacting.anchored then 10 else 13
  local top = Im.Scroll("tohand", right - 4, line, 448, shown * 26, #hand, shown)
  for row = 1, shown do
    local entry = hand[row + top]
    if entry == nil then
      break
    end
    local item = entry.item
    local name = shorten(Types.Info(item.type).name, 22)
    ItemIcon.Draw(item.type, right, line + 1, 20)
    Info.Name(item.type, name, right + 26, line + 3, 13, Im.TEXT)
    Im.Text(`x{item.quantity}  {entry.where}`, right + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
    local fuel = item.type == Structures.FUEL.id
    -- (a sealing charge goes in its bay as fuel goes in its tank)
    local seal = item.type == Structures.SEAL.id
    local command: State.Command = { kind = if fuel or seal then "Fuel" else "AnchorModule", actor = 0, item = item.id }
    local can, whyNot = Session.CanDo(session, command)
    if Im.Button(if fuel then "Fuel" elseif seal then "Load" else "Anchor", right + 250, line, 60, 21, can,
      if fuel then `Fuel:{entry.where}` elseif seal then `Seal:{entry.where}` else `Anchor:{item.type}`) then
      Session.Do(session, command)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 20), right + 318, line + 3, 12, Im.WARN)
    end
    line += 26
  end

  -- Its running since it was anchored, priced: what it has burnt
  -- against what it has brought up, and what a day of it costs and
  -- brings. (The corporation's books have every tower's: the Wallet tab.)
  local running = status.running
  line = y + 78 + 26 + shown * 26 + 12
  if reacting.anchored then
    -- Its reactor: what it is set to make (a press sets it, and "Off"
    -- stops it), what of each thing that is made of there is in the
    -- hangars, and when the next batch is.
    local making = reacting.making
    -- (whether there is too little of either thing for its next batch)
    local short = false
    if making then
      for index in making.from do
        short = short or reacting.have[index] < Reactions.BATCH
      end
    end
    Im.Heading("REACTOR", right, line, 16, Im.DIM)
    Im.TextRight(if not reacting.online then "not working: the tower is dark, or it is not online yet"
      elseif making == nil then "making nothing"
      elseif reacting.starved then "idle: not enough to make it of"
      elseif short then `not enough for the batch due in {Format.Duration(status.reacts)}`
      else `{Format.Whole(Reactions.BATCH)} more in {Format.Duration(status.reacts)}`, right + 440, line + 2, 12,
      if reacting.online and making and not reacting.starved and not short then GOOD elseif making or not reacting.online then Im.WARN
        else Im.DIM)
    line += 24
    local across = right
    for _, composite in Reactions.composites do
      local wide = Im.TextWidth(composite.name, 13) + 18
      if Im.Toggle(composite.name, across, line, wide, 21, making == composite, `React:{composite.id}`) and making ~= composite then
        Session.Do(session, { kind = "SetReaction", actor = 0, type = composite.id })
      end
      across += wide + 6
    end
    if Im.Button("Off", across, line, 40, 21, making ~= nil, "React:off") then
      Session.Do(session, { kind = "SetReaction", actor = 0, type = "" })
    end
    line += 26
    if making then
      local parts: { string } = {}
      for index, from in making.from do
        table.insert(parts, `{Types.Info(from).name} {Format.Whole(reacting.have[index])}`)
      end
      Im.Text(shorten(`{table.concat(parts, "   ")}`, 44), right, line, 13, if short then Im.WARN else Im.TEXT)
      Im.TextRight(`{Format.Whole(Reactions.BATCH)} of each an hour`, right + 440, line, 12, Im.DIM)
    else
      Im.Text("It makes a composite of the two moon materials of a grade.", right, line, 13, Im.DIM, 0.8)
    end
    line += 28
  end
  Im.Heading("RUNNING", right, line, 16, Im.DIM)
  Im.TextRight("in credits' worth, since it was anchored", right + 440, line + 2, 12, Im.DIM)
  line += 26
  Im.Text(`Fuel burnt: {Format.Whole(running.used)} blocks`, right, line, 13, Im.DIM)
  Im.TextRight(`-{Format.Whole(running.usedWorth)}`, right + 440, line, 13, if running.used > 0 then Im.WARN else Im.DIM)
  line += 20
  Im.Text(`Brought up: {Format.Whole(running.raised)}` .. (if running.robbed > 0 then `, and {Format.Whole(running.robbed)} carried off`
    else ""), right, line, 13, Im.DIM)
  Im.TextRight(`+{Format.Whole(running.raisedWorth - running.robbedWorth)}`, right + 440, line, 13,
    if running.raised > 0 then GOOD else Im.DIM)
  line += 20
  Im.Text("A day, as it stands", right, line, 13, Im.DIM)
  Im.TextRight(`+{Format.Whole(running.yieldADay)}  -{Format.Whole(running.fuelADay)}`, right + 440, line, 13,
    if running.yieldADay >= running.fuelADay and running.yieldADay > 0 then GOOD elseif status.lit then Im.WARN else Im.DIM)
end

-- ---------------------------------------------------------------------
-- Wallet

-- Which side of the Wallet tab is shown (the pilot's own, or their
-- corporation's); the name a corporation would be founded under; and
-- how much is to go into its account or come out of it.
local books = "mine"

-- Which of the wallet's books is open: "mine" or "corporation" (for the
-- dock, which has a button for each: Game/UI/Dock).
function Station.Books(): string
  return books
end
local corporationName = ""
local corporationAmount = 0
-- And which of the corporation's pages: its journal, its books by
-- head with the towers on them, or its hangar at the station.
local corporationPage: "journal" | "books" | "hangar" | "members" = "journal"

-- The corporation's books: on the left what has come in and gone out
-- under each head, and what that makes; on the right the pilot's
-- towers, each with what it has burnt, brought up and lost since it
-- was anchored, priced, and what a day of it costs and brings.
-- The corporation's members (Core/Assets/Members): the tax, who they
-- are and what each is doing, who would join, and the calls posted for
-- them. A call is posted with the buttons at the foot: what for
-- ("Call:kind" goes round the four), where ("Call:where" goes round the
-- systems the corporation has a place in), and what it pays a day.
local callKind, callWhere, callReward = 1, 1, 0
-- (the tax as typed, per cent: -1 until the page has been looked at)
local taxTyped = -1
local CALL_KINDS = { "defend", "mine", "haul", "scout" }
local function drawMembers(session: Session.Session, left: number, top: number)
  local game = session.game
  local info = Core.Query.Membership(game)
  local line = top
  local function percent(share: number): string
    return `{math.floor(share * 100 + 0.5)}%`
  end
  Im.Heading(`MEMBERS  {#info.members} OF {info.room}`, left, line, 14, Im.DIM)
  Im.Text("Tax", left + 250, line + 1, 13, Im.DIM)
  if taxTyped < 0 then
    taxTyped = math.floor(info.tax * 100 + 0.5)
  end
  taxTyped = math.max(0, math.floor(Im.Number("Members:tax", taxTyped, left + 284, line - 4, 50, 24)))
  local setTax: State.Command = { kind = "SetTax", actor = 0, quantity = taxTyped }
  if Im.Button("Set", left + 340, line - 4, 44, 24, taxTyped ~= math.floor(info.tax * 100 + 0.5) and (Session.CanDo(session, setTax)),
    "Members:settax") then
    Session.Do(session, setTax)
  end
  Im.Text("% of what each earns. Over what a member will bear, they leave.", left + 394, line + 1, 12, Im.DIM)
  line += 26
  if #info.members == 0 then
    Im.Text("Nobody yet. Pilots apply as the corporation has more to offer, and some at stations are open to being asked.", left, line, 12,
      Im.DIM)
    line += 20
  end
  local rows = 6
  local first = Im.Scroll("members", left - 4, line, 860, rows * 20, #info.members, rows)
  for index = first + 1, math.min(#info.members, first + rows) do
    local member = info.members[index]
    Im.Text(shorten(member.name, 22), left, line, 13, Im.TEXT)
    Im.Text(member.trade, left + 170, line, 13, Im.DIM)
    Im.Text(shorten(member.hull, 20), left + 236, line, 13, Im.DIM)
    Im.Text(shorten(`{member.doing} in {member.system}` .. (if member.called then " (a call)" else ""), 30), left + 390, line, 13,
      if member.doing == "idle" or member.doing == "refitting" then Im.WARN else Im.TEXT)
    -- (and what they have lost, if they have: it is theirs to bear)
    Im.TextRight(`paid {Format.Whole(member.paid)}` .. (if member.lost > 0 then `, {member.lost} lost` else ""), left + 760, line, 12, Im.DIM)
    if Im.Button("Expel", left + 770, line - 2, 56, 18, true, `Member:expel:{index}`) then
      Session.Do(session, { kind = "ExpelMember", actor = 0, target = member.id })
    end
    line += 20
  end
  line = top + 26 + math.max(1, math.min(rows, math.max(1, #info.members))) * 20 + 8
  -- Who would join: those who applied, and those open to it here.
  Im.Heading("WOULD JOIN", left, line, 14, Im.DIM)
  line += 22
  local shown = 0
  local function candidate(one: Core.ApplicantInfo, here: boolean, index: number)
    Im.Text(shorten(one.name, 22), left, line, 13, Im.TEXT)
    Im.Text(one.trade, left + 170, line, 13, Im.DIM)
    Im.Text(shorten(one.hull, 20), left + 236, line, 13, Im.DIM)
    Im.Text(`bears {percent(one.bears)}` .. (if here then ", is here" else ", has applied"), left + 390, line, 12,
      if one.bears + 1e-9 < info.tax then Im.WARN else Im.DIM)
    local command: State.Command = { kind = if here then "InviteMember" else "AcceptMember", actor = 0, what = one.key }
    if Im.Button(if here then "Invite" else "Accept", left + 620, line - 2, 64, 18, (Session.CanDo(session, command)),
      if here then `Member:invite:{index}` else `Member:accept:{index}`) then
      Session.Do(session, command)
    end
    if not here and Im.Button("Decline", left + 690, line - 2, 64, 18, true, `Member:decline:{index}`) then
      Session.Do(session, { kind = "DeclineMember", actor = 0, what = one.key })
    end
    line += 20
    shown += 1
  end
  for index, one in info.applicants do
    candidate(one, false, index)
  end
  for index, one in info.open do
    candidate(one, true, index)
  end
  if shown == 0 then
    Im.Text("Nobody is waiting, and nobody here is open to it today.", left, line, 12, Im.DIM)
    line += 20
  end
  line += 8
  -- The calls.
  Im.Heading("CALLS", left, line, 14, Im.DIM)
  Im.Text("Not orders: a member answers one that suits their trade and pays better than what they were doing.", left + 70, line + 1, 12,
    Im.DIM)
  line += 22
  for index, call in info.calls do
    Im.Text(`{call.kind} in {call.system}`, left, line, 13, Im.TEXT)
    Im.Text(if call.reward > 0 then `{Format.Whole(call.reward)} cr a day each` else "no reward", left + 236, line, 13, Im.DIM)
    Im.Text(`{call.answering} answering`, left + 420, line, 13, if call.answering > 0 then GOOD else Im.DIM)
    if Im.Button("Call off", left + 620, line - 2, 64, 18, true, `Call:cancel:{index}`) then
      Session.Do(session, { kind = "CancelCall", actor = 0, target = call.id })
    end
    line += 20
  end
  if #info.places > 0 then
    callKind = math.clamp(callKind, 1, #CALL_KINDS)
    callWhere = math.clamp(callWhere, 1, #info.places)
    if Im.Button(CALL_KINDS[callKind], left, line, 80, 24, true, "Call:kind") then
      callKind = callKind % #CALL_KINDS + 1
    end
    if Im.Button(shorten(info.places[callWhere].name, 16), left + 86, line, 140, 24, true, "Call:where") then
      callWhere = callWhere % #info.places + 1
    end
    callReward = Im.Number("Call:reward", callReward, left + 236, line, 110, 24)
    Im.Text("cr a day", left + 352, line + 5, 12, Im.DIM)
    local post: State.Command = { kind = "PostCall", actor = 0, what = CALL_KINDS[callKind], target = info.places[callWhere].id,
      quantity = math.max(0, math.floor(callReward)) }
    local can, why = Session.CanDo(session, post)
    if Im.Button("Post call", left + 420, line, 90, 24, can, "Call:post") then
      Session.Do(session, post)
    end
    if not can and why then
      Im.Text(shorten(why, 46), left + 520, line + 5, 12, Im.DIM)
    end
  end
end

local function drawBooks(corporation: Core.CorporationInfo, left: number, top: number)
  local line = top
  Im.Heading("BY HEAD", left, line, 14, Im.DIM)
  Im.TextRight("since it was founded", left + 400, line + 1, 12, Im.DIM)
  line += 24
  if #corporation.heads == 0 then
    Im.Text("Nothing has been earned or spent yet.", left, line, 13, Im.DIM, 0.8)
    line += 22
  end
  for _, head in corporation.heads do
    Im.Text(head.name, left, line, 14, Im.TEXT)
    Im.TextRight((if head.amount >= 0 then "+" else "") .. Format.Whole(head.amount), left + 400, line, 14,
      if head.amount >= 0 then GOOD else Im.WARN)
    line += 22
  end
  local net = corporation.earned - corporation.spent
  Im.Fill(left, line + 2, 400, 1, Im.DIM, 0.4)
  line += 8
  Im.Text("Which makes", left, line, 14, Im.DIM)
  Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 400, line, 14, if net >= 0 then GOOD else Im.WARN)
  line += 34
  -- (the towers, all told: what they have burnt against what they have brought up, in credits' worth)
  local burnt, raised, robbed, fuelADay, yieldADay = 0, 0, 0, 0, 0
  for _, tower in corporation.towers do
    burnt += tower.running.usedWorth
    raised += tower.running.raisedWorth
    robbed += tower.running.robbedWorth
    fuelADay += tower.running.fuelADay
    yieldADay += tower.running.yieldADay
  end
  if #corporation.towers > 0 then
    Im.Heading("THE TOWERS, ALL TOLD", left, line, 14, Im.DIM)
    Im.TextRight("in credits' worth", left + 400, line + 1, 12, Im.DIM)
    line += 24
    local told: { { name: string, worth: number, gain: boolean } } = {
      { name = "Brought up", worth = raised, gain = true }, { name = "Carried off by raiders", worth = robbed, gain = false },
      { name = "Fuel burnt", worth = burnt, gain = false },
    }
    for _, row in told do
      Im.Text(row.name, left, line, 14, Im.TEXT)
      Im.TextRight((if row.worth == 0 then "" elseif row.gain then "+" else "-") .. Format.Whole(row.worth), left + 400, line, 14,
        if row.worth == 0 then Im.DIM elseif row.gain then GOOD else Im.WARN)
      line += 22
    end
    Im.Text("A day, as they stand", left, line, 14, Im.DIM)
    Im.TextRight(`+{Format.Whole(yieldADay)}  -{Format.Whole(fuelADay)}`, left + 400, line, 14,
      if yieldADay >= fuelADay then GOOD else Im.WARN)
  end

  local right = left + 470
  line = top
  Im.Heading(`TOWERS  {#corporation.towers}`, right, line, 14, Im.DIM)
  line += 24
  if #corporation.towers == 0 then
    Im.Text("You have no tower. One is anchored at a moon, from the hold.", right, line, 13, Im.DIM, 0.8)
  end
  local visible = 5
  local first = Im.Scroll("corporation towers", right - 4, line, 440, visible * 68, #corporation.towers, visible)
  for row = 1, visible do
    local tower = corporation.towers[row + first]
    if tower == nil then
      break
    end
    local running = tower.running
    Im.Text(shorten(tower.name, 38), right, line, 14, Im.TEXT)
    Im.TextRight(if tower.lit then tower.system else `{tower.system}: DARK`, right + 436, line + 1, 12, if tower.lit then Im.DIM else Im.WARN)
    local what = if running.material ~= "" then Types.Info(running.material).name else "nothing under it"
    Im.Text(`burnt {Format.Whole(running.used)} blocks ({Format.Whole(running.usedWorth)})`, right, line + 21, 12, Im.DIM)
    Im.TextRight(if running.material == "" then what
      else `{Format.Whole(running.raised)} {what} up ({Format.Whole(running.raisedWorth)})`
        .. (if running.robbed > 0 then `, {Format.Whole(running.robbed)} lost` else ""), right + 436, line + 21, 12,
      if running.robbed > 0 then Im.WARN else Im.DIM)
    Im.Text(`a day: {Format.Whole(running.fuelADay)} of fuel`, right, line + 39, 12, Im.DIM)
    Im.TextRight(if running.yieldADay > 0 then `brings up {Format.Whole(running.yieldADay)}` else "brings up nothing", right + 436,
      line + 39, 12, if running.yieldADay > running.fuelADay then GOOD else Im.DIM)
    line += 68
  end
end

-- The corporation's hangar at the station: what is in it on the left,
-- each stack to be taken into the pilot's own hangar or sold for the
-- corporation's account; and the pilot's own hangar on the right, each
-- stack to be given.
local function drawCorporateHangar(session: Session.Session, game: Core.Game, station: number, left: number, top: number)
  local function sorted(place: string): { State.Item }
    local items = table.clone(Core.Query.Items(game, station, place))
    table.sort(items, function(a: State.Item, b: State.Item): boolean
      if a.type ~= b.type then
        return Catalog.Before(a.type, b.type)
      end
      return a.id < b.id
    end)
    return items
  end
  local visible = 11
  local width = 440
  for column, place in { "corporate", "hangar" } do
    local x = left + (column - 1) * (width + 28)
    local items = sorted(place)
    Im.Heading(if place == "corporate" then `THE CORPORATION'S HANGAR HERE  {#items}` else `YOUR HANGAR HERE  {#items}`, x, top, 16, Im.DIM)
    local line = top + 26
    if #items == 0 then
      Im.Text(if place == "corporate" then "Nothing: what your pilots bring in here is put here." else "nothing here", x, line, 13, Im.DIM, 0.8)
    end
    local first = Im.Scroll(if place == "corporate" then "corporate hangar" else "own hangar", x - 4, line, width, visible * 24, #items, visible)
    for row = 1, visible do
      local item = items[row + first]
      if item == nil then
        break
      end
      local info = Types.Info(item.type)
      local name = shorten(info.name, 24)
      ItemIcon.Draw(item.type, x, line + 1, 20)
      Info.Name(item.type, name, x + 26, line + 3, 13, Im.TEXT)
      Im.Text(`x{Format.Whole(item.quantity)}`, x + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
      if place == "corporate" then
        local take: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" }
        if Im.Button("Take", x + width - 116, line, 52, 21, (Session.CanDo(session, take)), `FromCorp:{item.type}`) then
          Session.Do(session, take)
        end
        local sell: State.Command = { kind = "SellNow", actor = 0, item = item.id, quantity = item.quantity }
        if Im.Button("Sell", x + width - 60, line, 52, 21, (Session.CanDo(session, sell)), `SellCorp:{item.type}`) then
          Session.Do(session, sell)
        end
      else
        local give: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "corporate" }
        if Im.Button("Give", x + width - 60, line, 52, 21, (Session.CanDo(session, give)), `ToCorp:{item.type}`) then
          Session.Do(session, give)
        end
      end
      line += 24
    end
  end
  local foot = top + 26 + visible * 24 + 10
  Im.Text("Your hired pilots put what they bring in into the corporation's hangar and carry away what is in it; they leave your own alone.",
    left, foot, 13, Im.DIM)
  Im.Text("What is sold out of it is paid to the corporation's account. A tower's drill fills the corporation's hangar there.", left,
    foot + 19, 13, Im.DIM)
end

local function drawWallet(session: Session.Session, game: Core.Game, x: number, y: number)
  local top = y + 78
  local left = x + 16
  local corporation = Core.Query.Corporation(game)
  if Im.Toggle("Mine", x + 700, top - 6, 80, 26, books == "mine", "Wallet:mine") then
    books = "mine"
  end
  if Im.Toggle("Corporation", x + 784, top - 6, 140, 26, books == "corporation", "Wallet:corporation") then
    books = "corporation"
  end
  local journal = Core.Query.Journal(game)
  local line = top + 40
  if books == "corporation" and not corporation.founded then
    -- Nobody's yet: what one is, and the founding of it.
    Im.Heading("NO CORPORATION", left, top, 16, Im.DIM)
    line = top + 34
    for _, text in { "A corporation is the business your hired pilots work for. It has an account of its own:",
      "their signing on, their wages and the mending of their ships come out of it, and what they sell",
      "and the bounties they earn with you elsewhere go into it, so its books say what they make against",
      `what they cost. It has places for {corporation.staff} more pilots than your Leadership commands. Where its account`,
      "is short, your own wallet pays the difference. It is founded once, here, under a name of yours." } do
      Im.Text(text, left, line, 13, Im.DIM)
      line += 19
    end
    line += 14
    Im.Text("Name", left, line + 5, 14, Im.DIM)
    corporationName = Im.Words("Corporation:name", corporationName, left + 60, line, 300, 28, 24, "three letters to twenty-four")
    local found: State.Command = { kind = "FoundCorporation", actor = 0, what = corporationName }
    local can, whyNot = Session.CanDo(session, found)
    if Im.Button(`Found it: {Format.Credits(corporation.fee)}`, left + 372, line, 200, 28, can, "Corporation:found") then
      Session.Do(session, found)
      books = "corporation"
    end
    if not can and corporationName ~= "" then
      Im.Text(tostring(whyNot), left + 584, line + 6, 13, Im.WARN)
    end
    return
  elseif books == "corporation" then
    journal = corporation.journal
    Im.Heading(string.upper(corporation.name), left, top, 16, Im.DIM)
    Im.Heading(Format.Credits(corporation.wallet), left, top + 24, 22, Im.TEXT)
    Im.Text(`founded {Format.Clock(corporation.since)}`, left + 2, top + 54, 12, Im.DIM)
    -- Its books: what its pilots have made against what they have cost.
    local net = corporation.earned - corporation.spent
    Im.Text("earned", left + 250, top + 26, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.earned), left + 400, top + 24, 14, GOOD)
    Im.Text("spent", left + 250, top + 46, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.spent), left + 400, top + 44, 14, Im.WARN)
    Im.Text("which makes", left + 420, top + 26, 12, Im.DIM)
    Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 600, top + 24, 14, if net >= 0 then GOOD else Im.WARN)
    Im.Text("wages a day", left + 420, top + 46, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.wages), left + 600, top + 44, 14, Im.TEXT)
    -- Into its account from the pilot's own wallet, and out of it.
    corporationAmount = Im.Number("Corporation:amount", corporationAmount, left + 620, top + 34, 110, 26)
    local deposit: State.Command = { kind = "CorporationDeposit", actor = 0, quantity = corporationAmount }
    if Im.Button("Pay in", left + 736, top + 34, 76, 26, (Session.CanDo(session, deposit)), "Corporation:deposit") then
      Session.Do(session, deposit)
    end
    local withdraw: State.Command = { kind = "CorporationWithdraw", actor = 0, quantity = corporationAmount }
    if Im.Button("Take out", left + 816, top + 34, 92, 26, (Session.CanDo(session, withdraw)), "Corporation:withdraw") then
      Session.Do(session, withdraw)
    end
    -- Its pages: the journal, the books by head, and its hangar here.
    if Im.Toggle("Journal", x + 404, top - 6, 90, 26, corporationPage == "journal", "Corporation:journal") then
      corporationPage = "journal"
    end
    if Im.Toggle("Books", x + 498, top - 6, 90, 26, corporationPage == "books", "Corporation:books") then
      corporationPage = "books"
    end
    if Im.Toggle("Hangar", x + 592, top - 6, 90, 26, corporationPage == "hangar", "Corporation:hangar") then
      corporationPage = "hangar"
    end
    if Im.Toggle("Members", x + 686, top - 6, 90, 26, corporationPage == "members", "Corporation:members") then
      corporationPage = "members"
    end
    line = top + 84
    if corporationPage == "books" then
      drawBooks(corporation, left, line)
      return
    elseif corporationPage == "hangar" then
      drawCorporateHangar(session, game, Core.Query.Player(game).docked, left, line)
      return
    elseif corporationPage == "members" then
      drawMembers(session, left, line)
      return
    end
  else
    Im.Heading("BALANCE", left, top, 16, Im.DIM)
    Im.Heading(Format.Credits(game.state.wallet), left + 110, top - 4, 22, Im.TEXT)
  end
  Im.Text("WHEN", left, line, 12, Im.DIM)
  Im.Text("WHAT", left + 150, line, 12, Im.DIM)
  Im.TextRight("AMOUNT", left + 600, line, 12, Im.DIM)
  Im.TextRight("BALANCE", left + 780, line, 12, Im.DIM)
  line += 20
  if #journal == 0 then
    Im.Text("Nothing has been paid or earned yet.", left, line, 14, Im.DIM, 0.8)
  end
  local visible = if books == "corporation" then 16 else 18
  local first = Im.Scroll(if books == "corporation" then "corporation journal" else "journal", left - 4, line, 900, visible * 22, #journal,
    visible)
  for row = 1, visible do
    -- newest first
    local entry = journal[#journal - (row + first) + 1]
    if entry == nil then
      break
    end
    local rowY = line + (row - 1) * 22
    Im.Text(Format.Clock(entry.tick), left, rowY + 3, 13, Im.DIM)
    Im.Text(entry.reason, left + 150, rowY + 3, 14, Im.TEXT)
    Im.TextRight((if entry.amount >= 0 then "+" else "") .. Format.Whole(entry.amount), left + 600, rowY + 3, 14,
      if entry.amount >= 0 then GOOD else Im.WARN)
    Im.TextRight(Format.Whole(entry.balance), left + 780, rowY + 3, 14, Im.DIM)
  end
end

-- ---------------------------------------------------------------------

-- 'preview' is the player's ship as it is fitted, for the fitting
-- screen to show (Scene.Dressed).
function Station.Draw(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local width, height = Station.WIDTH, Station.HEIGHT
  local station = Core.Query.Body(game, player.docked)
  Im.Panel(x, y, width, height)
  Im.Heading("DOCKED", x + 16, y + 12, 16, Im.DIM)
  Im.Heading(if station then shorten(station.name, 32) else "?", x + 16, y + 36, 17, Im.TEXT)
  -- At a starbase of the pilot's own there is the running of it too,
  -- which is what the pilot has come for: it is open on arrival.
  local starbase = Core.Query.Starbase(game, player.docked)
  local own: Core.StarbaseStatus? = if starbase and starbase.mine then starbase else nil
  if tab == "Starbase" and own == nil then
    tab = "Industry"
  end
  -- And where the career agents are, there is them.
  local careers = Core.Query.Careers(game)
  local school = careers.station == player.docked
  if tab == "Careers" and not school then
    tab = "Industry"
  end
  local tabs: { string } = if own then OWN elseif school then SCHOOL else TABS
  local pitch = (width - 364 - 12) / #tabs
  for index, name in tabs do
    if Im.Toggle(name, x + 364 + (index - 1) * pitch, y + 18, pitch - 4, 28, tab == name) then
      tab = name
      if Station.Front then
        Station.Front()
      end
    end
  end
  -- What can be done here is what the station has a module for: say
  -- what the tab that is open wants and the station has not.
  local _, services = Core.Query.Station(game, player.docked)
  local has: { [string]: boolean } = {}
  for _, service in services do
    has[service] = true
  end
  local lacking: { string } = {}
  local wanted: { string } = WANTS[tab] or {}
  for _, service in wanted do
    if not has[service] then
      table.insert(lacking, Structures.Provider(service :: Structures.Service))
    end
  end
  if #lacking > 0 then
    Im.Text(`This station has no {table.concat(lacking, " and no ")}.`, x + 16, y + 58, 13, Im.WARN)
  elseif school and not careers.begun and tab ~= "Careers" and select(2, Core.Query.Guide(game)) < 12 then
    -- (a pilot who has not met them yet is told they are here; one who
    -- has done half of what there is to do without them is not new)
    Im.Text("New here? The career agents teach the ropes, and pay: Careers.", x + 16, y + 58, 13, Im.ACCENT)
  end

  if tab == "Wallet" then
    drawWallet(session, game, x, y)
  elseif tab == "Crew" then
    drawCrew(session, game, player, x, y)
  elseif tab == "Missions" then
    drawMissions(session, game, x, y)
  elseif tab == "Careers" then
    drawCareers(session, game, x, y)
  elseif tab == "Starbase" and own then
    drawStarbase(session, game, player, own, x, y)
  else
    drawIndustry(session, game, player, x, y)
  end
end

return Station
