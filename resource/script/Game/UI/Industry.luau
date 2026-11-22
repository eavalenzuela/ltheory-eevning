--!strict
-- Industry: a window of its own (Game/UI/Windows), the fifth of what the
-- docked screen held to be one. A station's: opened from the dock, shut
-- when the pilot undocks.
--
-- Down the left is what is here to work with: the blueprints in the
-- hangar (and the copies of them), the ore, and the jobs that are
-- running, here and elsewhere. On the right is the blueprint picked: the
-- job it would be (how many runs, what they take of what is here, how
-- long and the fee) and what a laboratory does with it (research into
-- its materials and its time, a copy of it, the inventing of its tech 2
-- make).
--
-- A script's names are what they were when this was a tab of the docked
-- screen: "Refine:<type>", "Job:cancel:<n>", "Runs", "Runs:1",
-- "Runs:10", "Runs:most", "StartJob", "Research:material",
-- "Research:time", "Copy", "Invent". New with the window:
-- "Industry:blueprint:<type>" (a row), and "industry:close".
-- "Industry", the tab's name, opens it.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Industry = require("@lt/Core/Assets/Industry")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Ores = require("@lt/Core/Data/Ores")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Works = {}

Works.ID = "industry"

local current: Session.Session? = nil
-- The blueprint shown and the runs entered.
local chosen = ""
local runs = 1
-- The job whose "Call off" has been pressed once, and the frames it
-- stays asked for: a second press within them calls it off.
local calling = { job = 0, left = 0 }

function Works.Open()
  Windows.Open(Works.ID)
  Windows.Raise(Works.ID)
end

function Works.Close()
  Windows.Close(Works.ID)
end

function Works.IsOpen(): boolean
  return Windows.IsOpen(Works.ID)
end

-- Open the window at a blueprint, or at a copy of one, as clicking its
-- row would.
function Works.Choose(type: string): boolean
  if Blueprints.Of(type) == nil then
    return false
  end
  if chosen ~= type then
    chosen = type
    runs = 1
  end
  Works.Open()
  return true
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked (the window is a station's: Windows.Berthed).
function Works.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Works.ID, docked)
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

local function heading(s: string, x: number, y: number, w: number, note: string?): number
  Im.Strong(string.upper(s), x, y, 11, Theme.ACCENT)
  if note then
    Im.Text(note, x + w - Im.TextWidth(note, 12), y - 1, 12, Theme.DIM)
  end
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
  return y + 22
end

local LEFT_W = 440
local ORE_ROWS, JOB_ROWS, JOB_ROW = 3, 3, 46

-- What is here to work with.
local function drawHere(session: Session.Session, game: Core.Game, station: number, x: number, y: number, w: number, h: number)
  local blueprints: { State.Item } = {}
  local ores: { State.Item } = {}
  for _, item in Core.Query.Items(game, station, "hangar") do
    if Blueprints.Of(item.type) then
      table.insert(blueprints, item)
    elseif Ores.byId[item.type] then
      table.insert(ores, item)
    end
  end

  -- Blueprints here.
  local oreH = List.HEAD + ORE_ROWS * List.ROW
  local jobsH = List.HEAD + JOB_ROWS * JOB_ROW
  local room = h - oreH - jobsH - List.HEAD
  List.Group("Blueprints here", tostring(#blueprints), x, y, w, nil)
  local top = y + List.HEAD
  if #blueprints == 0 then
    Im.Text("None. The market sells them, under Blueprints.", x + 12, top + 8, 13, Theme.DIM)
  end
  local first, visible = List.Body("industry blueprints", x, top, w, room, #blueprints)
  for row = 1, visible do
    local item = blueprints[row + first]
    if item == nil then
      break
    end
    local blueprint, copy = Blueprints.Of(item.type)
    assert(blueprint)
    local rowY = top + (row - 1) * List.ROW
    local hot, clicked = List.Row(x, rowY, w - 5, chosen == item.type, `Industry:blueprint:{item.type}`)
    ItemIcon.Draw(blueprint.product, x + 10, rowY + 3, 19)
    -- (a copy says how many runs it is still good for)
    local note = if copy then `copy: {Format.Whole(item.quantity)} {if item.quantity == 1 then "run" else "runs"} left`
      else `makes {blueprint.perRun} a run`
    local noteWidth = Im.TextWidth(note, 12)
    Im.Text(note, x + w - 16 - noteWidth, rowY + 6, 12, if copy then Theme.ACCENT else Theme.DIM)
    local name, cut = List.Cut(Types.Info(blueprint.product).name, w - 60 - noteWidth, 14, false)
    Im.Text(name, x + 36, rowY + 5, 14, Theme.TEXT)
    if hot and cut then
      Im.Tip(Types.Info(blueprint.product).name)
    end
    if clicked and chosen ~= item.type then
      chosen = item.type
      runs = 1
    end
  end

  -- Ore to refine.
  local oreY = y + List.HEAD + room
  List.Group("Ore here", tostring(#ores), x, oreY, w, nil)
  oreY += List.HEAD
  if #ores == 0 then
    Im.Text("None. Mine some at a belt and bring it back.", x + 12, oreY + 8, 13, Theme.DIM)
  end
  local firstOre = Im.Scroll("industry ores", x, oreY, w, ORE_ROWS * List.ROW, #ores, ORE_ROWS)
  for row = 1, ORE_ROWS do
    local item = ores[row + firstOre]
    if item == nil then
      break
    end
    local rowY = oreY + (row - 1) * List.ROW
    ItemIcon.Draw(item.type, x + 10, rowY + 3, 19)
    Im.Text(List.Cut(Types.Info(item.type).name, w - 220, 14, false), x + 36, rowY + 5, 14, Theme.TEXT)
    local count = Format.Whole(item.quantity)
    Im.Text(count, x + w - 100 - Im.TextWidth(count, 13), rowY + 5, 13, Theme.DIM)
    local refine: State.Command = { kind = "Reprocess", actor = 0, item = item.id }
    local can, whyNot = Session.CanDo(session, refine)
    Im.Because(whyNot)
    if Im.Button("Refine", x + w - 88, rowY + 2, 72, 21, can, `Refine:{item.type}`) then
      Session.Do(session, refine)
    end
  end

  -- Jobs running, here and elsewhere.
  calling.left = math.max(0, calling.left - 1)
  local jobs = Core.Query.Jobs(game, nil)
  local jobsY = y + h - jobsH
  List.Group("Jobs running", `{#jobs} / {Core.Query.JobSlots(game)}`, x, jobsY, w, nil)
  jobsY += List.HEAD
  if #jobs == 0 then
    Im.Text("Nothing is being built.", x + 12, jobsY + 8, 13, Theme.DIM)
  end
  local firstJob = Im.Scroll("industry jobs", x, jobsY, w, JOB_ROWS * JOB_ROW, #jobs, JOB_ROWS)
  for row = 1, JOB_ROWS do
    local index = row + firstJob
    local job = jobs[index]
    if job == nil then
      break
    end
    local rowY = jobsY + (row - 1) * JOB_ROW
    local where = Core.Query.Body(game, job.station)
    local remaining = job.ends - game.state.tick
    -- (a copying and an inventing are named for what the blueprint
    -- builds, as the rows above are)
    local held = Blueprints.Of(job.blueprint)
    local drawing = if held then held.name else Types.Info(job.blueprint).name
    local builds = if held then Types.Info(held.product).name else drawing
    local what = if job.research == "copy" then `Copying, {Format.Whole(job.quantity)} {if job.quantity == 1 then "run" else "runs"}: {builds}`
      elseif job.research == "invent" then `Inventing from a copy: {builds}`
      elseif job.research ~= "" then `Research ({job.research}): {drawing}`
      else `{Format.Whole(job.quantity)} x {Types.Info(job.product).name}`
    local time = Format.Duration(remaining * Constants.TICK)
    Im.Text(time, x + w - 16 - Im.TextWidth(time, 13), rowY + 5, 13, Theme.TEXT)
    Im.Text(List.Cut(what, w - 40 - Im.TextWidth(time, 13), 14, false), x + 12, rowY + 4, 14, Theme.TEXT)
    Im.Text(List.Cut(if job.station == station then "here" else (if where then where.name else "?"), 150, 12, false), x + 12, rowY + 25, 12, Theme.DIM)
    local span = math.max(1, job.ends - job.started)
    -- (called off where it runs: pressed once it asks, and pressed again
    -- within a few seconds it is done. What went into the runs not
    -- finished is lost.)
    local cancel: State.Command = { kind = "CancelJob", actor = 0, target = job.id }
    local armed = calling.job == job.id and calling.left > 0
    if job.station == station then
      if armed then
        Im.Tone("danger")
      end
      if Im.Button(if armed then "Sure?" else "Call off", x + w - 96, rowY + 22, 80, 20, (Session.CanDo(session, cancel)), `Job:cancel:{index}`) then
        if armed then
          Session.Do(session, cancel)
          calling.job, calling.left = 0, 0
        else
          calling.job, calling.left = job.id, 240
        end
      end
    end
    local bx, bw = x + 170, w - 170 - 108
    Im.Flat(bx, rowY + 30, bw, 4, Theme.WELL)
    Im.Flat(bx, rowY + 30, bw * math.clamp(1 - remaining / span, 0, 1), 4, Theme.ACCENT)
    Im.Flat(x, rowY + JOB_ROW - 1, w, 1, Theme.EDGE, 0.6)
  end
end

local MATERIAL_COLUMNS: { List.Column } = {
  { id = "name", label = "Takes", width = 0, sort = false }, { id = "need", label = "Wants", width = 90, right = true, sort = false },
  { id = "have", label = "Here", width = 90, right = true, sort = false },
}

-- The blueprint picked: the job it would be, and what a laboratory does with it.
local function drawJob(session: Session.Session, game: Core.Game, station: number, x: number, y: number, w: number, h: number)
  local item = inHangar(game, station, chosen)
  local plan = if item then Core.Query.JobPlan(game, station, chosen, math.max(1, runs)) else nil
  if plan == nil or item == nil then
    heading("New job", x, y, w)
    Im.Text("Pick a blueprint in the list.", x, y + 28, 13, Theme.DIM)
    return
  end
  local product = Types.Info(plan.blueprint.product)
  local _, isCopy = Blueprints.Of(chosen)
  local line = heading(if isCopy then "New job, from a copy" else "New job", x, y, w)
  ItemIcon.Draw(product.id, x, line + 2, 30)
  Im.Strong(List.Cut(product.name, w - 110, 17, true), x + 40, line + 2, 17, Theme.TEXT)
  Im.Text(`makes {Format.Whole(plan.quantity)}`, x + 40, line + 22, 13, Theme.DIM)
  if Im.Button("Info", x + w - 54, line + 4, 54, 22, true, `Info:{product.id}`) then
    Info.Open(product.id)
  end
  line += 46
  Im.Text("Runs", x, line + 5, 14, Theme.DIM)
  runs = Im.Number("Runs", runs, x + 60, line, 100, 26)
  -- as many runs as the minerals here allow (and as a copy has left)
  local most = if isCopy then math.min(100, item.quantity) else 100
  for _, m in plan.blueprint.materials do
    local _, have = inHangar(game, station, m.type)
    most = math.min(most, have // m.quantity)
  end
  for index, preset in { 1, 10 } do
    if Im.Button(tostring(preset), x + 170 + (index - 1) * 52, line, 48, 26, true, `Runs:{preset}`) then
      runs = preset
    end
  end
  Im.Because("There is not enough here for one run")
  if Im.Button(`Most ({most})`, x + 274, line, 100, 26, most >= 1, "Runs:most") then
    runs = most
  end
  line += 36
  -- (a hull or a tower is built of a dozen things and more: as many as
  -- fit, and the wheel for the rest)
  local materialRows = 7
  local layout = List.Columns(MATERIAL_COLUMNS, x - 10, w + 20 - 6)
  List.Head("industry materials", x - 10, line, w + 20, MATERIAL_COLUMNS, layout, "", false)
  line += List.HEAD
  local firstMaterial = Im.Scroll("industry materials", x - 10, line, w + 20, materialRows * 22, #plan.materials, materialRows)
  for row = 1, materialRows do
    local m = plan.materials[row + firstMaterial]
    if m == nil then
      break
    end
    local rowY = line + (row - 1) * 22 - 2
    local enough = m.have >= m.need
    ItemIcon.Draw(m.type, layout.name.x, rowY + 3, 17)
    List.Text(Types.Info(m.type).name, layout.name, rowY, false, Theme.TEXT, 13, false, 24)
    List.Text(Format.Whole(m.need), layout.need, rowY, false, if enough then Theme.TEXT else Theme.BAD, 13)
    List.Text(Format.Whole(m.have), layout.have, rowY, false, if enough then Theme.DIM else Theme.BAD, 13)
  end
  line += materialRows * 22 + 8
  Im.Text("Takes", x, line, 13, Theme.DIM)
  Im.Text(Format.Duration(plan.seconds), x + 50, line, 13, Theme.TEXT)
  local fee = Format.Credits(plan.fee)
  Im.Text(fee, x + w - Im.TextWidth(fee, 13), line, 13, Theme.TEXT)
  Im.Text("fee", x + w - Im.TextWidth(fee, 13) - 30, line, 13, Theme.DIM)
  line += 26
  local job: State.Command = { kind = "StartJob", actor = 0, item = item.id, quantity = runs }
  local can, whyNot = Session.CanDo(session, job)
  Im.Tone("primary")
  Im.Because(whyNot)
  if Im.Button("Start job", x, line, 160, 30, can, "StartJob") then
    Session.Do(session, job)
  end
  if not can then
    Im.Text(List.Cut(tostring(whyNot), w - 180, 13, false), x + 172, line + 8, 13, Theme.CAUTION)
  end
  line += 46

  -- The laboratory: what the pilot has learned of this design and the
  -- next level of each kind, a copy of it, and the inventing of its
  -- tech 2 make.
  local research = Core.Query.Research(game, plan.blueprint.id)
  if research == nil then
    return
  end
  line = heading("Laboratory", x, line, w, `researched: materials -{research.material}%, time -{research.time * 2}%`)
  line += 4
  -- (a button, and beside it how long it takes and what it costs, or why it cannot be)
  local function study(label: string, id: string, command: State.Command, ready: boolean, first: string, second: string?, bx: number, tone: vector?)
    local canDo, why = false, nil :: string?
    if ready then
      canDo, why = Session.CanDo(session, command)
    end
    Im.Because(why)
    if Im.Button(label, bx, line, 150, 26, canDo, id) then
      Session.Do(session, command)
    end
    Im.Text(first, bx + 158, line - 1, 12, Theme.DIM)
    Im.Text(List.Cut(if canDo or why == nil then (second or "") else why, 240, 12, false), bx + 158, line + 13, 12,
      if canDo or why == nil then (tone or Theme.DIM) else Theme.CAUTION)
  end
  if isCopy then
    Im.Text("Research and copying take the blueprint itself, not a copy.", x, line, 12, Theme.DIM)
    line += 22
  else
    for index, what in { "material", "time" } do
      local next: Industry.ResearchPlan? = if what == "material" then research.nextMaterial else research.nextTime
      study(if what == "material" then "Research materials" else "Research time", `Research:{what}`,
        { kind = "StartResearch", actor = 0, item = item.id, what = what }, next ~= nil,
        if next then Format.Duration(next.seconds) else "done", if next then Format.Credits(next.fee) else nil, x + (index - 1) * (w / 2))
    end
    line += 36
    -- (a copy good for the runs entered above: what a job or an
    -- invention can use up in place of the blueprint)
    local copying = Core.Query.CopyPlan(game, chosen, math.max(1, runs))
    if copying then
      study("Copy", "Copy", { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = runs }, true,
        `a copy good for {Format.Whole(copying.runs)} {if copying.runs == 1 then "run" else "runs"}, {Format.Duration(copying.seconds)}`,
        Format.Credits(copying.fee), x)
      line += 36
    end
  end
  -- (one for each tech 2 make, where a hull has more than one: the Ouyou's Hoshizora and Raiden)
  local several = #research.inventions > 1
  for _, invention in research.inventions do
    local named = if several then Types.Info(invention.product).name else nil
    study(if named then `Invent {named}` else "Invent tech 2", if named then `Invent:{invention.product}` else "Invent",
      { kind = "StartResearch", actor = 0, item = item.id, what = "invent", type = if several then invention.product else nil }, true,
      string.format("%d datacores, %s, %d%% chance", invention.datacores, Format.Duration(invention.seconds),
        math.floor(invention.chance * 100 + 0.5)), Format.Credits(invention.fee), x)
    if several then
      line += 36
    end
  end
  local _ = h
end

Windows.Kind(Works.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  if player.at == 0 then
    Im.Text("Things are built, refined and researched at a station: dock at one.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local station = player.at
  local was = Im.Plain(true)
  -- (what can be done here is what the station has a module for: said along the foot, where it has not)
  local _, services = Core.Query.Station(game, station)
  local has: { [string]: boolean } = {}
  for _, service in services do
    has[service :: string] = true
  end
  local lacking: { string } = {}
  for _, service in { "refining", "industry", "research" } do
    if not has[service] then
      table.insert(lacking, Structures.Provider(service :: Structures.Service))
    end
  end
  local foot = if #lacking > 0 then List.FOOT else 0
  Im.Flat(x + LEFT_W, y, 1, h - foot, Theme.EDGE)
  drawHere(session, game, station, x + 1, y, LEFT_W - 1, h - foot)
  drawJob(session, game, station, x + LEFT_W + 16, y + 14, w - LEFT_W - 32, h - foot - 28)
  if #lacking > 0 then
    Im.Flat(x, y + h - foot, w, 1, Theme.EDGE)
    Im.Text(`This station has no {table.concat(lacking, " and no ")}.`, x + 12, y + h - foot + 7, 12, Theme.CAUTION)
  end
  Im.Plain(was)
end)
Windows.Make(Works.ID, Works.ID, "Industry", 534, 130, 1010, 660, 940, 600, nil)
Windows.Icon(Works.ID, "industry")

return Works
