--!strict
-- Skills: a window of its own (Game/UI/Windows), the fourth of what the
-- docked screen held to be one. Unlike the others it is not a station's:
-- the queue is the pilot's wherever they are, and it opens in space too
-- (what wants a station, buying a book and plugging an implant in, says
-- so there).
--
-- The Skills page is every skill in one list (its name, its five levels
-- as pips: had, queued, not yet; and what comes next for it: how long
-- the next level takes, that its book is here or what it costs, or what
-- it wants first), narrowed by a word and by four switches (all, known,
-- can train now, needs a book). Beside the list is the skill picked: what
-- it does, what its next level opens (the skills, hulls and modules
-- that want it), what it wants itself, how long its levels take, and
-- the buttons that train it, learn it or go for its book. Along the foot
-- is the training queue.
--
-- The skills' groups go down the left of the list, as the market's
-- categories do (Skills.GROUPS: the owner's, 2026-11-16), each with how
-- many of its skills the pilot knows.
--
-- The Implants page is the pilot's five places and the implants in the
-- hangar that could go in one.
--
-- A script's names are what they were when this was a tab of the docked
-- screen, and are there for every skill whether it is the one picked or
-- not: "Train:<skill>", "Learn:<skill>", "Book:<skill>",
-- "CancelTraining:<n>", "Unplug:<slot>", "Plug:<type>", "Inject:<type>"
-- (a training injector in reach: Data/Injectors). New with the
-- window: "Skills:skills" and "Skills:implants" (its pages),
-- "Skills:show:<all, known, train, book>", "Skills:filter",
-- "Skills:group:<all, or a group's id>",
-- "Skills:skill:<skill>" (a row), "Skills:upto" (queue the skill picked
-- to its last level), and "skills:close".

local Catalog = require("@lt/Core/Data/Catalog")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Hulls = require("@lt/Core/Data/Ships")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local Injectors = require("@lt/Core/Data/Injectors")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Sheet = {}

Sheet.ID = "skills"

-- How the market is opened at a type (a skill's book): set by
-- Game/UI/Market, which cannot be drawn on from here without a circle.
Sheet.Market = nil :: ((type: string) -> boolean)?

local current: Session.Session? = nil
local page = "skills"
local show = "all"
local filter = ""
local group = "all"
-- The groups' column.
local TREE_W = 212
local picked = ""
-- A skill being queued level after level to its last ("Add up to level
-- 5"): one level is asked for, and the next when that one is in the queue.
local adding = { skill = "", asked = -1 }

function Sheet.Open()
  Windows.Open(Sheet.ID)
  Windows.Raise(Sheet.ID)
end

function Sheet.Close()
  Windows.Close(Sheet.ID)
end

function Sheet.IsOpen(): boolean
  return Windows.IsOpen(Sheet.ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Sheet.Frame(session: Session.Session)
  current = session
end

-- What each level of each skill opens: the names of the skills, hulls
-- and modules that want it at that level. Worked out once.
local opens: { [string]: { [number]: { string } } }? = nil

local function opened(skill: string, level: number): { string }
  local index: { [string]: { [number]: { string } } } = opens or {}
  if opens == nil then
    local made: { [string]: { [number]: { string } } } = {}
    local function add(need: Skills.Need, name: string)
      local levels = made[need.skill]
      if levels == nil then
        levels = {}
        made[need.skill] = levels
      end
      local names = levels[need.level]
      if names == nil then
        names = {}
        levels[need.level] = names
      end
      table.insert(names, name)
    end
    for _, other in Skills.list do
      for _, need in other.requires do
        add(need, other.name)
      end
    end
    for _, hull in Hulls.list do
      for _, need in Skills.Needs(hull.id) do
        add(need, hull.name)
      end
    end
    for _, entry in Catalog.Listing("module") do
      local info = entry.info
      if info then
        for _, need in Skills.Needs(info.id) do
          add(need, info.name)
        end
      end
    end
    opens = made
    index = made
  end
  local levels = index[skill]
  return if levels and levels[level] then levels[level] else {}
end

-- A skill's five levels as pips: had, queued, not yet.
local function pips(x: number, y: number, level: number, queued: number, size: number)
  for each = 1, Skills.MAX_LEVEL do
    local px = x + (each - 1) * (size + 3)
    if each <= level then
      Im.Flat(px, y, size, size, Theme.ACCENT)
    elseif each <= queued then
      Im.Flat(px, y, size, size, Theme.ACCENT, 0.4)
    else
      Im.Flat(px, y, size, size, Theme.CONTROL)
    end
  end
end

local function heading(s: string, x: number, y: number, w: number): number
  Im.Strong(string.upper(s), x, y, 11, Theme.ACCENT)
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
  return y + 22
end

local COLUMNS: { List.Column } = {
  { id = "name", label = "Skill", width = 0, sort = false }, { id = "level", label = "Level", width = 62, sort = false },
  { id = "next", label = "Next", width = 150, right = true, sort = false },
}

-- The training queue, along the foot.
local QUEUE_ROWS = 3
local QUEUE_H = 40 + QUEUE_ROWS * 24

local function drawQueue(session: Session.Session, game: Core.Game, x: number, y: number, w: number)
  Im.Flat(x, y, w, QUEUE_H, Theme.RAISED, 0.45)
  Im.Flat(x, y, w, 1, Theme.EDGE_STRONG)
  local queue = Core.Query.Training(game)
  Im.Strong(`TRAINING  {#queue}`, x + 12, y + 10, 12, Theme.DIM)
  -- The training injectors in reach (in the hangar here, or the hold),
  -- a button for each kind along the heading: banked time, given to the
  -- queue at once.
  local player = Core.Query.Player(game)
  local held: { [string]: State.Item } = {}
  local counts: { [string]: number } = {}
  local places: { { holder: number, place: string } } = { { holder = player.ship, place = "cargo" } }
  if player.at ~= 0 then
    table.insert(places, 1, { holder = player.at, place = "hangar" })
  end
  for _, at in places do
    for _, item in Core.Query.Items(game, at.holder, at.place) do
      if Injectors.byId[item.type] then
        held[item.type] = held[item.type] or item
        counts[item.type] = (counts[item.type] or 0) + item.quantity
      end
    end
  end
  local injectX = x + 160
  for _, injector in Injectors.list do
    local item = held[injector.id]
    if item then
      local inject: State.Command = { kind = "Inject", actor = 0, item = item.id }
      local can, whyNot = Session.CanDo(session, inject)
      local label = `Inject {Format.Duration(injector.seconds)}  x{counts[injector.id]}`
      local bw = Im.TextWidth(label, 12) + 20
      Im.Because(whyNot)
      if Im.Button(label, injectX, y + 4, bw, 22, can, `Inject:{injector.id}`) then
        Session.Do(session, inject)
      end
      injectX += bw + 6
    end
  end
  if #queue == 0 then
    Im.Text("Nothing is training. Training goes on while you fly.", x + 12, y + 38, 13, Theme.CAUTION)
    return
  end
  local last = queue[#queue]
  local ends = Format.Duration(last.left)
  Im.Strong(ends, x + w - 12 - Im.StrongWidth(ends, 13), y + 9, 13, Theme.TEXT)
  Im.Text("ends in", x + w - 20 - Im.StrongWidth(ends, 13) - Im.TextWidth("ends in", 12), y + 10, 12, Theme.DIM)
  -- (all of it as one bar, a length to each level by how long it takes)
  local total = 0
  for _, entry in queue do
    total += entry.seconds
  end
  local at = x + 12
  for index, entry in queue do
    local wide = math.max(2, (w - 24) * entry.seconds / math.max(1, total) - 2)
    Im.Flat(at, y + 30, wide, 5, Theme.ACCENT, if index == 1 then 1 else math.max(0.2, 0.5 - 0.06 * index))
    at += wide + 2
  end
  local top = y + 40
  local first = Im.Scroll("skills queue", x, top, w, QUEUE_ROWS * 24, #queue, QUEUE_ROWS)
  -- (a row that is not in sight is a script's to press all the same)
  for index = 1, #queue do
    if (index <= first or index > first + QUEUE_ROWS) and Im.Hook(`CancelTraining:{index}`, true) then
      Session.Do(session, { kind = "CancelTraining", actor = 0, quantity = index })
    end
  end
  for row = 1, QUEUE_ROWS do
    local index = row + first
    local entry = queue[index]
    if entry == nil then
      break
    end
    local rowY = top + (row - 1) * 24
    local skill = Skills.byId[entry.skill]
    Im.Text(List.Cut(`{skill.name} {entry.level}`, 200, 14, false), x + 12, rowY + 4, 14, if index == 1 then Theme.TEXT else Theme.DIM)
    -- (how far the one in training is)
    local bx, bw = x + 226, w - 226 - 130
    Im.Flat(bx, rowY + 10, bw, 4, Theme.WELL)
    if index == 1 then
      Im.Flat(bx, rowY + 10, bw * math.clamp(1 - entry.left / math.max(1, entry.seconds), 0, 1), 4, Theme.ACCENT)
    end
    local left = Format.Duration(entry.left)
    Im.Text(left, x + w - 46 - Im.TextWidth(left, 13), rowY + 5, 13, if index == 1 then Theme.TEXT else Theme.DIM)
    local clicked, hot = Im.IconButton("close", x + w - 36, rowY + 1, 22, 22, true, `CancelTraining:{index}`)
    if hot then
      Im.Tip("Take it out of the queue")
    end
    if clicked then
      Session.Do(session, { kind = "CancelTraining", actor = 0, quantity = index })
    end
  end
end

-- The pilot's implants: the five places, and what in the hangar could go
-- into one.
local function drawImplants(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number, w: number)
  local places, open = Core.Query.Implants(game)
  local line = heading("Your implants", x + 14, y + 14, w - 28)
  for slot, place in places do
    local implant = place.implant
    Im.Strong(tostring(slot), x + 16, line + 5, 13, Theme.DIM)
    if implant then
      Im.Text(List.Cut(implant.name, 260, 14, false), x + 40, line + 4, 14, Theme.TEXT)
      Im.Text(List.Cut(implant.note, w - 430, 12, false), x + 310, line + 6, 12, Theme.DIM)
      if Im.Button("Info", x + w - 150, line, 50, 24, true, `Info:{implant.id}`) then
        Info.Open(implant.id)
      end
      if Im.Button("Unplug", x + w - 92, line, 78, 24, true, `Unplug:{slot}`) then
        Session.Do(session, { kind = "UnplugImplant", actor = 0, what = implant.id })
      end
    else
      Im.Text(if slot <= open then "empty" else `needs Cybernetics {slot}`, x + 40, line + 5, 13, if slot <= open then Theme.DIM else Theme.FAINT)
    end
    line += 30
  end
  line = heading("In the hangar here", x + 14, line + 12, w - 28)
  local any = false
  if player.at ~= 0 then
    for _, item in Core.Query.Items(game, player.at, "hangar") do
      local info = Types.Info(item.type)
      if info.category == "implant" then
        any = true
        local plug: State.Command = { kind = "PlugImplant", actor = 0, item = item.id }
        local can, whyNot = Session.CanDo(session, plug)
        Im.Text(List.Cut(info.name, w - 300, 14, false), x + 16, line + 4, 14, if can then Theme.TEXT else Theme.DIM)
        if not can then
          Im.Text(List.Cut(tostring(whyNot), 180, 12, false), x + w - 300, line + 6, 12, Theme.CAUTION)
        end
        Im.Because(whyNot)
        if Im.Button("Plug in", x + w - 92, line, 78, 24, can, `Plug:{item.type}`) then
          Session.Do(session, plug)
        end
        line += 30
      end
    end
  end
  if not any then
    Im.Text(if player.at ~= 0 then "None. A market sells implants (Implants)." else "An implant is plugged in at a station.", x + 16, line + 4,
      13, Theme.DIM)
  end
end

Windows.Kind(Sheet.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  -- (the list's x moves right of the groups' column; the queue is the width of the window)
  local left = x
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  local station = player.at
  local was = Im.Plain(true)
  local skills = Core.Query.Skills(game)
  local known = 0
  local levels: { [string]: number } = {}
  for _, info in skills do
    if info.level >= 0 then
      known += 1
      levels[info.skill.id] = info.level
    end
  end
  -- (the books in reach: in the hangar here, or in the hold of the pilot's ship)
  local books: { [string]: State.Item } = {}
  if station ~= 0 then
    for _, item in Core.Query.Items(game, station, "hangar") do
      if Types.Info(item.type).category == "skillbook" then
        books[item.type] = item
      end
    end
  end
  for _, item in Core.Query.Items(game, player.ship, "cargo") do
    if Types.Info(item.type).category == "skillbook" then
      books[item.type] = books[item.type] or item
    end
  end

  -- What can be done for a skill, and what a script can press for it
  -- whether it is the one picked or not.
  type Doing = { info: Core.SkillInfo, train: State.Command?, canTrain: boolean, whyNotTrain: string?, learn: State.Command?, canLearn: boolean,
    whyNotLearn: string?, missing: Skills.Need? }
  local doing: { [string]: Doing } = {}
  for _, info in skills do
    local skill = info.skill
    local each: Doing = { info = info, canTrain = false, canLearn = false }
    if info.level < 0 then
      each.missing = Skills.Missing(skill.requires, levels)
      local book = books[Skills.Book(skill.id)]
      if book then
        local learn: State.Command = { kind = "LearnSkill", actor = 0, item = book.id }
        each.learn = learn
        each.canLearn, each.whyNotLearn = Session.CanDo(session, learn)
        if Im.Hook(`Learn:{skill.id}`, each.canLearn) then
          Session.Do(session, learn)
        end
      elseif Im.Hook(`Book:{skill.id}`, station ~= 0) and Sheet.Market then
        Sheet.Market(Skills.Book(skill.id))
      end
    elseif info.queued < Skills.MAX_LEVEL then
      local train: State.Command = { kind = "TrainSkill", actor = 0, type = skill.id }
      each.train = train
      each.canTrain, each.whyNotTrain = Session.CanDo(session, train)
      if Im.Hook(`Train:{skill.id}`, each.canTrain) then
        Session.Do(session, train)
      end
    end
    doing[skill.id] = each
  end
  -- (a skill being queued to its last level: the next, when the one asked for is in)
  local more = doing[adding.skill]
  if more then
    if more.info.queued >= Skills.MAX_LEVEL or more.info.level < 0 then
      adding.skill = ""
    elseif more.info.queued ~= adding.asked then
      local train = more.train
      if train and more.canTrain then
        adding.asked = more.info.queued
        Session.Do(session, train)
      else
        adding.skill = ""
      end
    end
  end

  -- The pages, and the switches that narrow the list.
  local tx = x + 10
  for _, each in { { "skills", "Skills" }, { "implants", "Implants" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, page == each[1], `Skills:{each[1]}`)
    if pressed then
      page = each[1]
    end
    tx += wide + 2
  end
  local count = `{known} of {#skills} known`
  Im.Text(count, x + w - 12 - Im.TextWidth(count, 12), y + 11, 12, Theme.DIM)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top = y + 33
  local room = h - 33 - QUEUE_H

  if page == "implants" then
    drawImplants(session, game, player, x, top, w)
  else
    -- (what the other page's buttons do is a script's to press from this one too)
    for slot, place in (Core.Query.Implants(game)) do
      local implant = place.implant
      if implant and Im.Hook(`Unplug:{slot}`, true) then
        Session.Do(session, { kind = "UnplugImplant", actor = 0, what = implant.id })
      end
    end
    if station ~= 0 then
      for _, item in Core.Query.Items(game, station, "hangar") do
        if Types.Info(item.type).category == "implant" then
          local plug: State.Command = { kind = "PlugImplant", actor = 0, item = item.id }
          if Im.Hook(`Plug:{item.type}`, (Session.CanDo(session, plug))) then
            Session.Do(session, plug)
          end
        end
      end
    end
    local detailW = 270
    -- The groups, down the left: every skill, then each group, with how
    -- many of its skills are known.
    local ty = top + 8
    local function groupRow(id: string, name: string, have: number, of: number)
      local _, clicked = List.Row(x + 1, ty, TREE_W - 6, group == id, `Skills:group:{id}`)
      Im.Text(List.Cut(name, TREE_W - 70, 14, false), x + 11, ty + 5, 14, Theme.TEXT)
      local count = `{have}/{of}`
      Im.Text(count, x + TREE_W - 14 - Im.TextWidth(count, 12), ty + 6, 12, Theme.FAINT)
      if clicked and group ~= id then
        group = id
        Im.ScrollTo("skills list", 0)
      end
      ty += List.ROW
    end
    local knownAll = 0
    for _, info in skills do
      knownAll += if info.level >= 0 then 1 else 0
    end
    groupRow("all", "Every skill", knownAll, #skills)
    for _, each in Skills.GROUPS do
      local have = 0
      for _, id in each.skills do
        local entry = doing[id]
        have += if entry and entry.info.level >= 0 then 1 else 0
      end
      groupRow(each.id, each.name, have, #each.skills)
    end
    Im.Flat(x + TREE_W, top, 1, room, Theme.EDGE)
    x += TREE_W + 1
    local listW = w - TREE_W - 1 - detailW
    local cx = x + 10
    for _, each in { { "all", "All" }, { "known", "Known" }, { "train", "Can train now" }, { "book", "Needs a book" } } do
      local pressed, wide = List.Chip(each[2], cx, top + 8, show == each[1], `Skills:show:{each[1]}`)
      if pressed then
        show = each[1]
        Im.ScrollTo("skills list", 0)
      end
      cx += wide + 4
    end
    local sought = Im.Words("Skills:filter", filter, cx + 6, top + 6, math.max(60, x + listW - 10 - (cx + 6)), 26, 32, "Filter")
    if sought ~= filter then
      filter = sought
      Im.ScrollTo("skills list", 0)
    end
    local wanted = string.lower(filter)
    local rows: { Doing } = {}
    for _, info in skills do
      local each = doing[info.skill.id]
      local keep = (show == "all" or (show == "known" and info.level >= 0) or (show == "train" and each.canTrain)
        or (show == "book" and info.level < 0)) and (group == "all" or (Skills.groupOf[info.skill.id] ~= nil and Skills.groupOf[info.skill.id].id == group))
      if keep and (wanted == "" or string.find(string.lower(info.skill.name), wanted, 1, true)) then
        table.insert(rows, each)
      end
    end
    local layout = List.Columns(COLUMNS, x, listW - 6)
    local listTop = top + 40
    List.Head("skills", x, listTop, listW, COLUMNS, layout, "", false)
    listTop += List.HEAD
    local first, visible = List.Body("skills list", x, listTop, listW, room - 40 - List.HEAD, #rows)
    if #rows == 0 then
      Im.Text("No skill is like that.", x + 12, listTop + 10, 13, Theme.DIM)
    end
    for row = 1, visible do
      local each = rows[row + first]
      if each == nil then
        break
      end
      local info = each.info
      local skill = info.skill
      local rowY = listTop + (row - 1) * List.ROW
      local hot, clicked = List.Row(x, rowY, listW - 5, picked == skill.id, `Skills:skill:{skill.id}`)
      List.Text(skill.name, layout.name, rowY, hot, if info.level >= 0 then Theme.TEXT else Theme.DIM, 14)
      pips(layout.level.x, rowY + 8, info.level, info.queued, 9)
      -- what comes next for it
      local note, tone = "", Theme.DIM
      if info.level >= Skills.MAX_LEVEL then
        note, tone = "mastered", Theme.FAINT
      elseif info.level >= 0 and info.queued >= Skills.MAX_LEVEL then
        note = "queued to the last"
      elseif info.level >= 0 then
        note = `to {info.queued + 1}: {Format.Duration(Skills.TrainingSeconds(skill, info.queued + 1))}`
      elseif each.missing then
        note, tone = Skills.Describe(each.missing), Theme.FAINT
      elseif each.learn then
        note, tone = "its book is here", Theme.ACCENT
      else
        note, tone = "needs its book", Theme.ACCENT
      end
      List.Text(note, layout.next, rowY, hot, tone, 13)
      if clicked then
        picked = skill.id
      end
    end
    Im.Flat(x + listW, top, 1, room, Theme.EDGE)

    -- The skill picked.
    local dx, dw = x + listW + 14, detailW - 28
    local chosen = doing[picked]
    if chosen == nil then
      Im.Text("Pick a skill in the list.", dx, top + 16, 13, Theme.DIM)
    else
      local info = chosen.info
      local skill = info.skill
      local rank = `rank {skill.rank}`
      Im.Strong(List.Cut(skill.name, dw - Im.TextWidth(rank, 12) - 10, 18, true), dx, top + 14, 18, Theme.TEXT)
      Im.Text(rank, dx + dw - Im.TextWidth(rank, 12), top + 19, 12, Theme.DIM)
      pips(dx, top + 46, info.level, info.queued, 13)
      Im.Text(if info.level < 0 then "Not learned" else `Level {info.level}`, dx + 5 * 16 + 8, top + 45, 14,
        if info.level < 0 then Theme.DIM else Theme.TEXT)
      local line = Im.Wrapped(skill.note, dx, top + 72, dw, 13, Theme.TEXT) + 10
      local next = math.max(0, info.level) + 1
      if next <= Skills.MAX_LEVEL then
        local names = opened(skill.id, next)
        if #names > 0 then
          line = heading(`Level {next} opens`, dx, line, dw)
          for index = 1, math.min(4, #names) do
            Im.Text(List.Cut(names[index], dw, 13, false), dx, line, 13, Theme.TEXT)
            line += 18
          end
          if #names > 4 then
            Im.Text(`and {#names - 4} more`, dx, line, 13, Theme.DIM)
            line += 18
          end
          line += 8
        end
      end
      line = heading("Needs", dx, line, dw)
      if #skill.requires == 0 then
        Im.Text(if skill.start >= 0 then "Nothing: you began with it." else "Its book, and nothing else.", dx, line, 13, Theme.DIM)
        line += 18
      end
      for _, need in skill.requires do
        local met = (levels[need.skill] or -1) >= need.level
        Im.Text(`{Skills.byId[need.skill].name} {need.level}`, dx, line, 13, if met then Theme.GOOD else Theme.CAUTION)
        line += 18
      end
      line += 8
      if info.level < Skills.MAX_LEVEL then
        line = heading("Training", dx, line, dw)
        local function row(label: string, seconds: number)
          Im.Text(label, dx, line, 13, Theme.DIM)
          local value = Format.Duration(seconds)
          Im.Text(value, dx + dw - Im.TextWidth(value, 13), line, 13, Theme.TEXT)
          line += 18
        end
        row(`To level {next}`, Skills.TrainingSeconds(skill, next))
        if next < Skills.MAX_LEVEL then
          local all = 0
          for level = next, Skills.MAX_LEVEL do
            all += Skills.TrainingSeconds(skill, level)
          end
          row(`To level {Skills.MAX_LEVEL}`, all)
        end
        line += 8
      end
      -- What is done for it.
      local foot = top + room - 12
      if info.level < 0 then
        local learn = chosen.learn
        if learn then
          Im.Tone("primary")
          Im.Because(chosen.whyNotLearn)
          if Im.Button("Learn it from its book", dx, foot - 30, dw, 30, chosen.canLearn, `Learn:{skill.id}`) then
            Session.Do(session, learn)
          end
        else
          Im.Because("A book is bought at a station's market")
          if Im.Button("Find its book on the market", dx, foot - 30, dw, 30, station ~= 0 and Sheet.Market ~= nil, `Book:{skill.id}`)
            and Sheet.Market then
            Sheet.Market(Skills.Book(skill.id))
          end
        end
      elseif info.level >= Skills.MAX_LEVEL then
        Im.Text("Mastered: there is no more of it to learn.", dx, foot - 22, 13, Theme.DIM)
      else
        local train = chosen.train
        local queuing = adding.skill == skill.id
        Im.Because(chosen.whyNotTrain)
        if Im.Button(if queuing then "Being queued to the last level" else `Add up to level {Skills.MAX_LEVEL}`, dx, foot - 30, dw, 30,
          train ~= nil and chosen.canTrain and not queuing and info.queued < Skills.MAX_LEVEL - 1, "Skills:upto") then
          adding.skill, adding.asked = skill.id, -1
        end
        Im.Tone("primary")
        Im.Because(chosen.whyNotTrain)
        if Im.Button(if train then `Train to level {info.queued + 1}` else "Queued to the last level", dx, foot - 66, dw, 30,
          train ~= nil and chosen.canTrain, `Train:{skill.id}`) and train then
          Session.Do(session, train)
        end
      end
    end
  end
  drawQueue(session, game, left + 1, y + h - QUEUE_H, w - 2)
  Im.Plain(was)
end)
Windows.Make(Sheet.ID, Sheet.ID, "Skills", 904, 130, 1004, 720, 952, 520, nil)
Windows.Icon(Sheet.ID, "skills")

return Sheet
