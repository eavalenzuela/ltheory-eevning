--!strict
-- The corporation: a window of its own (Game/UI/Windows) since
-- 2026-11-16, out of the wallet's Corporation tab (the owner, asked
-- whether it should be: "Own window"). Opened from the dock's
-- Corporation button, docked or in space.
--
-- Where there is no corporation, what one is and the founding of it (at
-- a station). Then its pages, set out as the market is: the Overview
-- (its account, what its pilots make against what they cost, money in
-- and out of it); its Books (by head, and its towers); its Members
-- (Core/Assets/Members: the tax, who they are and what each is doing,
-- who would join, and the calls posted for them); its Hangar at the
-- station the pilot is at; and its Journal.
--
-- A script's names are what they were in the wallet: "Corporation:name",
-- "Corporation:found", "Corporation:amount", "Corporation:deposit",
-- "Corporation:withdraw"; the pages "Corporation:overview", "...:books",
-- "...:members", "...:activity", "...:ops", "...:hangar", "...:journal"; "Members:tax",
-- "Op:kind", "Op:where", "Op:ahead", "Op:hours", "Op:post", "Op:course:<n>", "Op:cancel:<n>",
-- "Members:settax", "Members:share", "Members:setshare", "Member:row:<n>"
-- (a member's page), "Member:back", "Member:budget", "Member:setbudget",
-- "Member:target", "Member:plan", "Member:expel:<n>", "Member:invite:<n>",
-- "Member:accept:<n>", "Member:decline:<n>"; "Call:kind", "Call:where",
-- "Call:reward", "Call:post", "Call:cancel:<n>"; "FromCorp:<type>",
-- "SellCorp:<type>", "ToCorp:<type>". "corporation:close" shuts it.

local Catalog = require("@lt/Core/Data/Catalog")
local Characters = require("@lt/Core/Character/Characters")
local Core = require("@lt/Core/Api")
local Members = require("@lt/Core/Assets/Members")
local Skills = require("@lt/Core/Data/Skills")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Portrait = require("@lt/Game/UI/Portrait")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Game/UI/Wallet")
local Windows = require("@lt/Game/UI/Windows")

local Corporation = {}

Corporation.ID = "corporation"

local current: Session.Session? = nil
local page: "overview" | "books" | "members" | "activity" | "ops" | "hangar" | "journal" = "overview"
-- (an op as it is being posted: its kind, where, hours on, hours long)
local opKind, opWhere, opAhead, opHours = 1, 1, 2, 3
-- (the member whose page is up on the Members page: 0 for the list)
local profile = 0
-- (the share as typed, per cent: -1 until the page has been looked at)
local shareTyped = -1
local name = ""
local amount = 0
local callKind, callWhere, callReward = 1, 1, 0
-- (the tax as typed, per cent: -1 until the page has been looked at)
local taxTyped = -1
local CALL_KINDS = { "defend", "mine", "haul", "scout" }

function Corporation.Open(at: string?)
  if at then
    page = at :: any
  end
  Windows.Open(Corporation.ID)
  Windows.Raise(Corporation.ID)
end

function Corporation.Close()
  Windows.Close(Corporation.ID)
end

function Corporation.IsOpen(): boolean
  return Windows.IsOpen(Corporation.ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Corporation.Frame(session: Session.Session)
  current = session
end

-- (the wallet's old way in, for a script: "Wallet:corporation")
Wallet.ToCorporation = function()
  Corporation.Open()
end

local function heading(s: string, x: number, y: number, w: number, note: string?)
  Im.Text(s, x, y, 11, Theme.ACCENT)
  if note then
    Im.Text(note, x + w - Im.TextWidth(note, 11), y, 11, Theme.FAINT)
  end
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
end

local function signed(n: number): string
  return (if n >= 0 then "+" else "") .. Format.Whole(n)
end

-- ---------------------------------------------------------------------
-- No corporation yet

local function drawFounding(session: Session.Session, corporation: Core.CorporationInfo, x: number, y: number, w: number)
  local left = x + 16
  Im.Strong("No corporation", left, y + 14, 18, Theme.TEXT)
  local line = Im.Wrapped("A corporation is the business your hired pilots and its members work for. It has an account of its own: their signing on, "
    .. "their wages and the mending of their ships come out of it, and what they sell and the bounties they earn with you elsewhere go into "
    .. `it, so its books say what they make against what they cost. It has places for {corporation.staff} more pilots than your Leadership `
    .. "commands. Where its account is short, your own wallet pays the difference. It is founded once, at a station, under a name of yours.",
    left, y + 46, math.min(760, w - 32), 14, Theme.DIM, 21) + 18
  Im.Text("Name", left, line + 6, 14, Theme.DIM)
  name = Im.Words("Corporation:name", name, left + 60, line, 300, 28, 24, "three letters to twenty-four")
  local found: State.Command = { kind = "FoundCorporation", actor = 0, what = name }
  local can, whyNot = Session.CanDo(session, found)
  Im.Tone("primary")
  Im.Because(whyNot)
  if Im.Button(`Found it: {Format.Credits(corporation.fee)}`, left + 372, line, 220, 28, can, "Corporation:found") then
    Session.Do(session, found)
    page = "overview"
  end
  if not can and name ~= "" then
    Im.Text(tostring(whyNot), left + 604, line + 7, 13, Theme.CAUTION)
  end
end

-- ---------------------------------------------------------------------
-- The pages

local function drawOverview(session: Session.Session, corporation: Core.CorporationInfo, game: Core.Game, x: number, y: number, w: number)
  local left = x + 16
  local half = math.floor((w - 48) / 2)
  -- Its account, and money in and out of it.
  Im.Strong(corporation.name, left, y + 14, 20, Theme.TEXT)
  Im.Text(`founded {Format.Clock(corporation.since)}`, left, y + 42, 12, Theme.DIM)
  local line = y + 74
  heading("ACCOUNT", left, line, half)
  line += 24
  Im.Heading(Format.Credits(corporation.wallet), left, line, 24, Theme.TEXT)
  line += 40
  amount = Im.Number("Corporation:amount", amount, left, line, 140, 28)
  local deposit: State.Command = { kind = "CorporationDeposit", actor = 0, quantity = amount }
  local canPay, whyNotPay = Session.CanDo(session, deposit)
  Im.Because(whyNotPay)
  if Im.Button("Pay in", left + 150, line, 100, 28, canPay, "Corporation:deposit") then
    Session.Do(session, deposit)
  end
  local withdraw: State.Command = { kind = "CorporationWithdraw", actor = 0, quantity = amount }
  local canTake, whyNotTake = Session.CanDo(session, withdraw)
  Im.Because(whyNotTake)
  if Im.Button("Take out", left + 256, line, 100, 28, canTake, "Corporation:withdraw") then
    Session.Do(session, withdraw)
  end
  line += 36
  Im.Text(`from and to your own wallet: {Format.Credits(game.state.wallet)}`, left, line, 12, Theme.DIM)

  -- What its pilots make against what they cost.
  local rx = left + half + 16
  line = y + 74
  heading("SINCE IT WAS FOUNDED", rx, line, half)
  line += 24
  local net = corporation.earned - corporation.spent
  for _, row in { { "Earned", Format.Whole(corporation.earned), Theme.GOOD }, { "Spent", Format.Whole(corporation.spent), Theme.CAUTION },
    { "Which makes", signed(net), if net >= 0 then Theme.GOOD else Theme.CAUTION }, { "Wages a day", Format.Whole(corporation.wages), Theme.TEXT } } :: { { any } } do
    Im.Text(row[1], rx, line, 14, Theme.DIM)
    Im.TextRight(row[2], rx + half, line, 14, row[3])
    line += 24
  end
  line += 12
  local members = Core.Query.Membership(game)
  heading("ITS PEOPLE AND PLACES", rx, line, half)
  line += 24
  for _, row in { { "Members", `{#members.members} of {members.room}` }, { "Tax", `{math.floor(members.tax * 100 + 0.5)}%` },
    { "Calls posted", `{#members.calls}` }, { "Towers", `{#corporation.towers}` } } :: { { string } } do
    Im.Text(row[1], rx, line, 14, Theme.DIM)
    Im.TextRight(row[2], rx + half, line, 14, Theme.TEXT)
    line += 24
  end
end

local HEADS: { List.Column } = {
  { id = "head", label = "Head", width = 0, sort = false }, { id = "amount", label = "Amount", width = 140, right = true, sort = false },
}
local TOWERS: { List.Column } = {
  { id = "tower", label = "Tower", width = 0, sort = false }, { id = "burnt", label = "Burnt", width = 110, right = true, sort = false },
  { id = "raised", label = "Brought up", width = 140, right = true, sort = false },
  { id = "day", label = "A day", width = 130, right = true, sort = false },
}

local function drawBooks(corporation: Core.CorporationInfo, x: number, y: number, w: number, h: number)
  local leftW = math.floor(w * 0.36)
  -- By head, since it was founded.
  local layout = List.Columns(HEADS, x, leftW - 6)
  List.Head("corp heads", x, y, leftW, HEADS, layout, "", false)
  local top = y + List.HEAD
  local first, visible = List.Body("corp heads", x, top, leftW, h - List.HEAD - List.FOOT, #corporation.heads)
  if #corporation.heads == 0 then
    Im.Text("Nothing has been earned or spent yet.", x + 12, top + 8, 13, Theme.DIM)
  end
  for index = 1, visible do
    local head = corporation.heads[index + first]
    if head == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot = List.Row(x, rowY, leftW - 5, false)
    List.Text(head.name, layout.head, rowY, hot, Theme.TEXT, 14)
    List.Text(signed(head.amount), layout.amount, rowY, false, if head.amount >= 0 then Theme.GOOD else Theme.CAUTION, 14)
  end
  local net = corporation.earned - corporation.spent
  List.Foot(x, y + h - List.FOOT, leftW, "which makes", signed(net))
  Im.Flat(x + leftW, y, 1, h, Theme.EDGE)

  -- The towers, each with what it has burnt and brought up, in credits' worth.
  local tx, tw = x + leftW + 1, w - leftW - 1
  local tLayout = List.Columns(TOWERS, tx, tw - 6)
  List.Head("corp towers", tx, y, tw, TOWERS, tLayout, "", false)
  local tTop = y + List.HEAD
  local tFirst, tVisible = List.Body("corporation towers", tx, tTop, tw, h - List.HEAD - List.FOOT, #corporation.towers)
  if #corporation.towers == 0 then
    Im.Text("You have no tower. One is anchored at a moon, from the hold.", tx + 12, tTop + 8, 13, Theme.DIM)
  end
  local burnt, raised, fuelADay, yieldADay = 0, 0, 0, 0
  for _, tower in corporation.towers do
    burnt += tower.running.usedWorth
    raised += tower.running.raisedWorth
    fuelADay += tower.running.fuelADay
    yieldADay += tower.running.yieldADay
  end
  for index = 1, tVisible do
    local tower = corporation.towers[index + tFirst]
    if tower == nil then
      break
    end
    local running = tower.running
    local rowY = tTop + (index - 1) * List.ROW
    local hot = List.Row(tx, rowY, tw - 5, false)
    local what = if running.material ~= "" then Types.Info(running.material).name else "nothing under it"
    List.Text(tower.name, tLayout.tower, rowY, hot, if tower.lit then Theme.TEXT else Theme.CAUTION, 14, false, 0,
      `{tower.system}{if tower.lit then "" else ": dark"}; {what}`
        .. (if running.robbed > 0 then `, {Format.Whole(running.robbed)} carried off by raiders` else ""))
    List.Text(Format.Whole(running.usedWorth), tLayout.burnt, rowY, false, Theme.CAUTION, 13)
    List.Text(Format.Whole(running.raisedWorth), tLayout.raised, rowY, false, Theme.GOOD, 13)
    List.Text(`+{Format.Whole(running.yieldADay)} -{Format.Whole(running.fuelADay)}`, tLayout.day, rowY, false,
      if running.yieldADay >= running.fuelADay then Theme.GOOD else Theme.CAUTION, 13)
  end
  List.Foot(tx, y + h - List.FOOT, tw, `{#corporation.towers} towers, in credits' worth`,
    `burnt {Format.Whole(burnt)}, brought up {Format.Whole(raised)}; a day +{Format.Whole(yieldADay)} -{Format.Whole(fuelADay)}`)
end

-- How long ago, said shortly.
local function ago(seconds: number): string
  if seconds < 3600 then
    return `{math.max(1, seconds // 60)}m ago`
  elseif seconds < 86400 then
    return `{seconds // 3600}h ago`
  end
  return `{seconds // 86400}d ago`
end

-- A bar of how far along something is, 0 to 1.
local function bar(x: number, y: number, w: number, share: number, color: vector)
  Im.Flat(x, y, w, 6, Theme.RAISED)
  Im.Flat(x, y, w * math.clamp(share, 0, 1), 6, color)
end

-- A member's page (docs/design/members.md, phase 1): who they are, what
-- they have, what they want, and what they have done lately.
local budgetTyped: { [number]: number } = {}
local planned: { [string]: { at: number, queue: number } } = {}
local function drawProfile(session: Session.Session, member: Core.MemberInfo, info: Core.MembershipInfo, x: number, y: number, w: number,
  h: number)
  local left = x + 16
  if Im.Button("Back", left, y + 8, 70, 26, true, "Member:back") then
    profile = 0
  end
  Im.Strong(member.name, left + 84, y + 10, 20, if member.alt then Theme.GOOD else Theme.TEXT)
  local sub = (if member.title ~= "" then `{member.title}, ` else "") .. `a {member.trade}` .. (if member.alt then ", one of your characters" else "")
    .. `, a member {math.floor(member.days)} days`
  Im.Text(sub, left + 84, y + 36, 13, Theme.DIM)
  local line = y + 66
  local half = (w - 48) // 2
  local function row(label: string, value: string, color: vector?)
    Im.Text(label, left, line, 13, Theme.DIM)
    Im.Text(value, left + 130, line, 13, color or Theme.TEXT)
    line += 22
  end
  -- (who they are)
  if member.alt then
    row("Skills", "their own, as trained")
  else
    row("Grade", if member.nextGrade > 0 then `{member.grade} of 5: {member.practice} of {member.nextGrade} hours to the next` else `{member.grade} of 5`)
    if member.nextGrade > 0 then
      bar(left + 130, line - 4, half - 140, member.practice / member.nextGrade, Theme.GOOD)
      line += 8
    end
  end
  row("Lives at", member.home)
  row("Now", `{member.doing} in {member.system}` .. (if member.called then " (answering a call)" else ""))
  row("Loyalty", `{math.floor(member.loyalty * 100 + 0.5)}%`)
  bar(left + 130, line - 4, half - 140, member.loyalty, Theme.ACCENT)
  line += 8
  if member.aim ~= "" then
    row("Wants", member.aim)
    bar(left + 130, line - 4, half - 140, member.aimDone, Theme.ACCENT)
    line += 8
  end
  -- (what they have, on the right)
  local right = left + half + 16
  local rline = y + 66
  local function rrow(label: string, value: string, color: vector?)
    Im.Text(label, right, rline, 13, Theme.DIM)
    Im.Text(value, right + 130, rline, 13, color or Theme.TEXT)
    rline += 22
  end
  rrow("Flies", member.hull)
  rrow("Fitted", if #member.fit == 0 then "nothing yet" else `{math.floor(member.fitted * 100 + 0.5)}%: {List.Cut(table.concat(member.fit, ", "),
    half - 150, 13, false)}`, if member.fitted < 1 then Theme.CAUTION else nil)
  if member.charge ~= "" then
    rrow("Charges", `{Format.Whole(member.ammo)} {member.charge}`, if member.ammo <= 0 then Theme.CAUTION else nil)
  end
  rrow("Owns", table.concat(member.ships, ", "))
  if #member.implants > 0 or member.boosted then
    rrow("Implants", (if #member.implants > 0 then List.Cut(table.concat(member.implants, ", "), half - 150, 13, false) else "none")
      .. (if member.boosted then ", and on a booster today" else ""))
  end
  rrow("Shops at", if member.market ~= "" then member.market else "nowhere near")
  if not member.alt then
    rrow("Wallet", Format.Credits(member.wealth))
  end
  if member.owed > 0 then
    rrow("Owed", Format.Credits(member.owed), Theme.CAUTION)
  end
  rrow("Brought in", `{Format.Credits(member.delivered)} of goods`)
  if not member.alt then
    rrow("Paid for it", Format.Credits(member.shares))
  end
  if member.earned > 0 then
    rrow("Earned", `{Format.Credits(member.earned)}, {Format.Credits(member.paid)} of it to the corporation`)
  end
  rrow("Ships lost", tostring(member.lost))
  -- (one of the player's own characters: what they may spend of the
  -- corporation's, the hull they are to fly, and their training for it)
  if member.alt then
    line += 10
    Im.Text("Budget", left, line + 5, 13, Theme.DIM)
    local typed = budgetTyped[member.id] or member.budget
    typed = math.max(0, math.floor(Im.Number(`Member:budget`, typed, left + 130, line, 140, 26)))
    budgetTyped[member.id] = typed
    local setBudget: State.Command = { kind = "SetBudget", actor = 0, target = member.id, quantity = typed }
    if Im.Button("Set", left + 276, line, 50, 26, typed ~= member.budget and (Session.CanDo(session, setBudget)), "Member:setbudget") then
      Session.Do(session, setBudget)
    end
    Im.Text(`{Format.Credits(member.budget)} left of the corporation's`, left + 334, line + 6, 12, Theme.DIM)
    line += 34
    Im.Text("To fly", left, line + 5, 13, Theme.DIM)
    local at = 0
    for index, option in member.targets do
      at = if option.id == member.target then index else at
    end
    if Im.Button(if member.target ~= "" then member.targetName else "what they have", left + 130, line, 196, 26, #member.targets > 0,
      "Member:target") then
      local nextAt = at % (#member.targets + 1) + 1
      local next = member.targets[nextAt]
      Session.Do(session, { kind = "SetTarget", actor = 0, target = member.id, what = if next then next.id else "" })
    end
    local plan = planned[member.altId]
    if Host.Clock() - (if plan then plan.at else -math.huge) > 5 then
      local character = Session.Character(member.altId)
      plan = { at = Host.Clock(), queue = if character then #character.training else 0 }
      planned[member.altId] = plan
    end
    if Im.Button("Train for it", left + 334, line, 120, 26, member.target ~= "", "Member:plan") then
      local queued, books = Session.PlanAlt(session, member.altId, member.target)
      Session.Say(session, `{member.name}: {queued} {if queued == 1 then "level" else "levels"} queued`
        .. (if books > 0 then `, and {books} {if books == 1 then "skill wants its book" else "skills want their books"}, which they buy` else ""))
      planned[member.altId] = nil
    end
    Im.Text(`{if plan then plan.queue else 0} levels in their queue`, left + 462, line + 6, 12, Theme.DIM)
    line += 34
  end
  -- (and what they have done lately)
  local top = math.max(line, rline) + 12
  Im.Flat(x + 1, top, w - 2, 1, Theme.EDGE)
  Im.Text("LATELY", left, top + 10, 12, Theme.DIM)
  local at = top + 32
  for _, note in info.log do
    if note.member == member.id and at < y + h - 20 then
      Im.Text(ago(note.ago), left, at, 12, Theme.DIM)
      Im.Text(note.text, left + 80, at, 13, Theme.TEXT)
      at += 20
    end
  end
  if at == top + 32 then
    Im.Text("Nothing yet.", left, at, 13, Theme.DIM)
  end
end

-- The corporation's activity log: what its members have done, newest first.
local function drawActivity(game: Core.Game, x: number, y: number, w: number, h: number)
  local info = Core.Query.Membership(game)
  local first, visible = List.Body("activity", x, y + 8, w, h - 16, #info.log)
  if #info.log == 0 then
    Im.Text("Nothing yet: what members do is kept here.", x + 16, y + 16, 13, Theme.DIM)
  end
  for index = 1, visible do
    local note = info.log[index + first]
    if note == nil then
      break
    end
    local rowY = y + 8 + (index - 1) * List.ROW
    Im.Text(ago(note.ago), x + 16, rowY + 6, 12, Theme.DIM)
    Im.Text(if note.name ~= "" then note.name else "The corporation", x + 100, rowY + 5, 13, Theme.TEXT)
    Im.Text(note.text, x + 300, rowY + 5, 13, Theme.DIM)
  end
end

-- The corporation's ops (Core/Assets/Members, phase 5): posting one, and
-- the ops planned, running and over, the pilot's and its members', each
-- with the way there and, for the pilot's own, calling it off.
local OPS: { List.Column } = {
  { id = "what", label = "Op", width = 0, sort = false }, { id = "lead", label = "Led by", width = 150, sort = false },
  { id = "when", label = "When", width = 150, sort = false }, { id = "signed", label = "Signed up", width = 90, right = true, sort = false },
  { id = "brought", label = "Brought in", width = 110, right = true, sort = false },
  { id = "act", label = "", width = 200, right = true, sort = false },
}
local function drawOps(session: Session.Session, game: Core.Game, x: number, y: number, w: number, h: number)
  local info = Core.Query.Membership(game)
  local left = x + 12
  -- Posting one.
  if #info.places > 0 then
    local kinds = Core.OpKinds()
    opKind = math.clamp(opKind, 1, #kinds)
    opWhere = math.clamp(opWhere, 1, #info.places)
    if Im.Button(kinds[opKind], left, y + 8, 90, 26, true, "Op:kind") then
      opKind = opKind % #kinds + 1
    end
    if Im.Button(List.Cut(info.places[opWhere].name, 150, 13, false), left + 96, y + 8, 170, 26, true, "Op:where") then
      opWhere = opWhere % #info.places + 1
    end
    Im.Text("in", left + 276, y + 14, 12, Theme.DIM)
    opAhead = math.max(0, math.floor(Im.Number("Op:ahead", opAhead, left + 296, y + 8, 60, 26)))
    Im.Text("hours, for", left + 362, y + 14, 12, Theme.DIM)
    opHours = math.max(1, math.floor(Im.Number("Op:hours", opHours, left + 424, y + 8, 60, 26)))
    local post: State.Command = { kind = "PostOp", actor = 0, what = kinds[opKind], target = info.places[opWhere].id, quantity = opAhead,
      range = opHours }
    local can, why = Session.CanDo(session, post)
    Im.Tone("primary")
    Im.Because(why)
    if Im.Button("Post op", left + 494, y + 8, 110, 26, can, "Op:post") then
      Session.Do(session, post)
    end
  else
    Im.Text("An op is in a system the corporation has a place in: it has none.", left, y + 14, 13, Theme.DIM)
  end
  -- The ops.
  local layout = List.Columns(OPS, x, w - 6)
  local line = y + 44
  List.Head("ops head", x, line, w, OPS, layout, "", false)
  line += List.HEAD
  local first, visible = List.Body("ops", x, line, w, h - (line - y) - 4, #info.ops)
  if #info.ops == 0 then
    Im.Text("No ops. Post one, and members of the trades it wants sign up; members who lead now and then post their own.",
      x + 12, line + 6, 13, Theme.DIM)
  end
  for index = 1, visible do
    local op = info.ops[index + first]
    if op == nil then
      break
    end
    local rowY = line + (index - 1) * List.ROW
    local hot = List.Row(x, rowY, w - 5, false)
    List.Text(`{op.kind} in {op.system}, {op.hours}h`, layout.what, rowY, hot, if op.stage == "done" then Theme.DIM else Theme.TEXT, 14)
    List.Text(op.leader, layout.lead, rowY, false, if op.leader == "you" then Theme.GOOD else Theme.DIM, 13)
    List.Text(if op.stage == "running" then "running now" elseif op.stage == "planned" then `in {Format.Duration(op.starts)}` else "over",
      layout.when, rowY, false, if op.stage == "running" then Theme.GOOD else Theme.DIM, 13)
    List.Text(tostring(op.signed), layout.signed, rowY, false, Theme.DIM, 13)
    List.Text(Format.Whole(op.brought), layout.brought, rowY, false, Theme.DIM, 12)
    if op.stage ~= "done" then
      local set = session.destination == op.systemId
      if Im.Button(if set then "Course set" else "Set course", layout.act.x + layout.act.w - 190, rowY + 2, 104, List.ROW - 4, not set,
        `Op:course:{index + first}`) then
        session.destination = op.systemId
      end
    end
    if op.mine and Im.Button("Call off", layout.act.x + layout.act.w - 80, rowY + 2, 80, List.ROW - 4, true, `Op:cancel:{index + first}`) then
      Session.Do(session, { kind = "CancelOp", actor = 0, target = op.id })
    end
  end
end

local MEMBERS: { List.Column } = {
  { id = "name", label = "Member", width = 0, sort = false }, { id = "trade", label = "Trade", width = 80, sort = false },
  { id = "ship", label = "Flies", width = 150, sort = false }, { id = "doing", label = "Doing", width = 220, sort = false },
  { id = "paid", label = "Brought in", width = 110, right = true, sort = false }, { id = "act", label = "", width = 140, right = true, sort = false },
}

-- The player's characters (read every few seconds, not every frame), and
-- the trade each other one would be asked in at.
local alts: { Characters.Character } = {}
local altsAt = -math.huge
local altTrades: { [string]: string } = {}
local TRADES = { "miner", "fighter", "hauler", "scout" }

local function drawMembers(session: Session.Session, game: Core.Game, x: number, y: number, w: number, h: number)
  local info = Core.Query.Membership(game)
  local left = x + 12
  if profile ~= 0 then
    for _, member in info.members do
      if member.id == profile then
        drawProfile(session, member, info, x, y, w, h)
        return
      end
    end
    profile = 0
  end
  -- The tax, at the top.
  if taxTyped < 0 then
    taxTyped = math.floor(info.tax * 100 + 0.5)
  end
  Im.Text("Tax", left, y + 13, 13, Theme.DIM)
  taxTyped = math.max(0, math.floor(Im.Number("Members:tax", taxTyped, left + 34, y + 8, 60, 26)))
  local setTax: State.Command = { kind = "SetTax", actor = 0, quantity = taxTyped }
  if Im.Button("Set", left + 100, y + 8, 50, 26, taxTyped ~= math.floor(info.tax * 100 + 0.5) and (Session.CanDo(session, setTax)),
    "Members:settax") then
    Session.Do(session, setTax)
  end
  Im.Text("% of what they earn as money", left + 160, y + 14, 12, Theme.DIM)
  -- (and the share of what they bring in to the hangar that is theirs)
  if shareTyped < 0 then
    shareTyped = math.floor(info.share * 100 + 0.5)
  end
  local sx = left + 370
  Im.Text("Share", sx, y + 13, 13, Theme.DIM)
  shareTyped = math.max(0, math.floor(Im.Number("Members:share", shareTyped, sx + 44, y + 8, 60, 26)))
  local setShare: State.Command = { kind = "SetShare", actor = 0, quantity = shareTyped }
  if Im.Button("Set", sx + 110, y + 8, 50, 26, shareTyped ~= math.floor(info.share * 100 + 0.5) and (Session.CanDo(session, setShare)),
    "Members:setshare") then
    Session.Do(session, setShare)
  end
  Im.Text("% of what they bring in", sx + 170, y + 14, 12, Theme.DIM)
  local count = `{#info.members} of {info.room} members`
  Im.Text(count, x + w - 12 - Im.TextWidth(count, 12), y + 14, 12, Theme.DIM)

  local layout = List.Columns(MEMBERS, x, w - 6)
  local line = y + 42
  -- The members.
  List.Head("members head", x, line, w, MEMBERS, layout, "", false)
  line += List.HEAD
  local room = math.max(3, math.min(#info.members, 7))
  local first, visible = List.Body("members", x, line, w, room * List.ROW, #info.members)
  if #info.members == 0 then
    Im.Text("Nobody yet. Pilots apply as the corporation has more to offer, and some at stations are open to being asked.", x + 12, line + 6,
      13, Theme.DIM)
  end
  for index = 1, visible do
    local member = info.members[index + first]
    if member == nil then
      break
    end
    local rowY = line + (index - 1) * List.ROW
    local hot, clicked = List.Row(x, rowY, w - 5, false, `Member:row:{index + first}`)
    if clicked then
      profile = member.id
    end
    List.Text(member.name .. (if member.title ~= "" then `, {member.title}` else "") .. (if member.alt then "  (yours)" else ""), layout.name,
      rowY, hot, if member.alt then Theme.GOOD else Theme.TEXT, 14)
    List.Text(if member.alt then member.trade else `{member.trade} g{member.grade}`, layout.trade, rowY, false, Theme.DIM, 13)
    List.Text(member.hull, layout.ship, rowY, hot, Theme.DIM, 13)
    List.Text(`{member.doing} in {member.system}` .. (if member.called then " (a call)" else ""), layout.doing, rowY, hot,
      if member.doing == "idle" or member.doing == "refitting" then Theme.CAUTION else Theme.TEXT, 13)
    List.Text(Format.Whole(member.delivered + member.earned) .. (if member.lost > 0 then `, {member.lost} lost` else ""), layout.paid, rowY,
      false, if member.owed > 0 then Theme.CAUTION else Theme.DIM, 12)
    if Im.Button("Expel", layout.act.x + layout.act.w - 70, rowY + 2, 70, List.ROW - 4, true, `Member:expel:{index + first}`) then
      Session.Do(session, { kind = "ExpelMember", actor = 0, target = member.id })
    end
  end
  line += room * List.ROW + 10

  -- Who would join: those who applied, and those open to it here.
  heading("WOULD JOIN", left, line, w - 24)
  line += 22
  local waiting: { { one: Core.ApplicantInfo, here: boolean, index: number } } = {}
  for index, one in info.applicants do
    table.insert(waiting, { one = one, here = false, index = index })
  end
  for index, one in info.open do
    table.insert(waiting, { one = one, here = true, index = index })
  end
  if #waiting == 0 then
    Im.Text("Nobody is waiting, and nobody here is open to it today.", left, line + 4, 13, Theme.DIM)
    line += List.ROW
  end
  for _, each in waiting do
    local one, here = each.one, each.here
    local hot = List.Row(x, line, w - 5, false)
    List.Text(one.name, layout.name, line, hot, Theme.TEXT, 14)
    List.Text(one.trade, layout.trade, line, false, Theme.DIM, 13)
    List.Text(one.hull, layout.ship, line, hot, Theme.DIM, 13)
    List.Text(`bears {math.floor(one.bears * 100 + 0.5)}%` .. (if here then ", is here" else ", has applied"), layout.doing, line, false,
      if one.bears + 1e-9 < info.tax then Theme.CAUTION else Theme.DIM, 12)
    local command: State.Command = { kind = if here then "InviteMember" else "AcceptMember", actor = 0, what = one.key }
    local ax = layout.act.x + layout.act.w - 140
    if Im.Button(if here then "Invite" else "Accept", ax, line + 2, 66, List.ROW - 4, (Session.CanDo(session, command)),
      if here then `Member:invite:{each.index}` else `Member:accept:{each.index}`) then
      Session.Do(session, command)
    end
    if not here and Im.Button("Decline", ax + 70, line + 2, 70, List.ROW - 4, true, `Member:decline:{each.index}`) then
      Session.Do(session, { kind = "DeclineMember", actor = 0, what = one.key })
    end
    line += List.ROW
  end
  line += 10

  -- The player's other characters, who can be asked in (2026-11-17:
  -- Core/Character/Characters): each at a trade, picked on its button.
  if Host.Clock() - altsAt > 5 then
    alts, altsAt = Session.Characters(), Host.Clock()
  end
  local others = 0
  for _, alt in alts do
    others += if alt.id ~= session.character then 1 else 0
  end
  if others > 0 then
    heading("YOUR OTHER CHARACTERS", left, line, w - 24, "asked in, one works as a member does, with the skills they have, and stays")
    line += 22
    for _, alt in alts do
      if alt.id ~= session.character then
        local hot = List.Row(x, line, w - 5, false)
        Portrait.Draw(alt.portrait, layout.name.x + 4, line + 3, List.ROW - 6)
        List.Text(alt.name, layout.name, line, hot, Theme.TEXT, 14, false, List.ROW)
        local trade = altTrades[alt.id] or "miner"
        if Im.Button(trade, layout.trade.x, line + 2, layout.trade.w - 6, List.ROW - 4, true, `Alt:trade:{alt.id}`) then
          local at = table.find(TRADES, trade) or 1
          altTrades[alt.id] = TRADES[at % #TRADES + 1]
        end
        local can, why = Core.CanJoinAlt(game, alt.id, trade)
        -- (what makes them the better at the trade: Assets/Members)
        local skill = Skills.byId[Members.ALT_SKILL[trade] or ""]
        local level = if skill then alt.skills[skill.id] or -1 else -1
        List.Text(if not can then why or "" elseif skill and level >= 0 then `{skill.name} {level}` elseif skill then `no {skill.name}` else "",
          layout.doing, line, false, if can then Theme.DIM else Theme.CAUTION, 12)
        if Im.Button("Ask in", layout.act.x + layout.act.w - 70, line + 2, 70, List.ROW - 4, can, `Alt:ask:{alt.id}`) then
          Session.AskAlt(session, alt.id, trade)
        end
        line += List.ROW
      end
    end
    line += 10
  end

  -- The calls.
  heading("CALLS", left, line, w - 24, "not orders: a member answers one that suits their trade and pays better than what they were doing")
  line += 22
  for index, call in info.calls do
    local hot = List.Row(x, line, w - 5, false)
    List.Text(`{call.kind} in {call.system}`, layout.name, line, hot, Theme.TEXT, 14)
    List.Text(if call.reward > 0 then `{Format.Whole(call.reward)} cr a day each` else "no reward", layout.doing, line, false, Theme.DIM, 13)
    List.Text(`{call.answering} answering`, layout.paid, line, false, if call.answering > 0 then Theme.GOOD else Theme.DIM, 12)
    if Im.Button("Call off", layout.act.x + layout.act.w - 80, line + 2, 80, List.ROW - 4, true, `Call:cancel:{index}`) then
      Session.Do(session, { kind = "CancelCall", actor = 0, target = call.id })
    end
    line += List.ROW
  end
  if #info.places > 0 then
    line += 6
    callKind = math.clamp(callKind, 1, #CALL_KINDS)
    callWhere = math.clamp(callWhere, 1, #info.places)
    if Im.Button(CALL_KINDS[callKind], left, line, 90, 26, true, "Call:kind") then
      callKind = callKind % #CALL_KINDS + 1
    end
    if Im.Button(List.Cut(info.places[callWhere].name, 150, 13, false), left + 96, line, 170, 26, true, "Call:where") then
      callWhere = callWhere % #info.places + 1
    end
    callReward = Im.Number("Call:reward", callReward, left + 272, line, 110, 26)
    Im.Text("cr a day", left + 390, line + 6, 12, Theme.DIM)
    local post: State.Command = { kind = "PostCall", actor = 0, what = CALL_KINDS[callKind], target = info.places[callWhere].id,
      quantity = math.max(0, math.floor(callReward)) }
    local can, why = Session.CanDo(session, post)
    Im.Tone("primary")
    Im.Because(why)
    if Im.Button("Post call", left + 460, line, 110, 26, can, "Call:post") then
      Session.Do(session, post)
    end
  end
  local _ = h
end

local HANGAR: { List.Column } = {
  { id = "name", label = "Item", width = 0, sort = false }, { id = "qty", label = "Qty", width = 70, right = true, sort = false },
  { id = "act", label = "", width = 120, right = true, sort = false },
}

-- The corporation's hangar at the station: what is in it on the left,
-- each stack to be taken into the pilot's own hangar or sold for the
-- corporation's account; and the pilot's own hangar on the right, each
-- stack to be given.
local function drawHangar(session: Session.Session, game: Core.Game, x: number, y: number, w: number, h: number)
  local station = Core.Query.Player(game).docked
  if station == 0 then
    Im.Text("The corporation's hangars are at stations: dock at one to see what it has there.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local half = math.floor(w / 2)
  for column, place in { "corporate", "hangar" } do
    local cx = x + (column - 1) * half
    local cw = half - (if column == 1 then 1 else 0)
    local items = table.clone(Core.Query.Items(game, station, place))
    table.sort(items, function(a: State.Item, b: State.Item): boolean
      if a.type ~= b.type then
        return Catalog.Before(a.type, b.type)
      end
      return a.id < b.id
    end)
    local layout = List.Columns(HANGAR, cx, cw - 6)
    List.Head(`hangar {place}`, cx, y, cw, HANGAR, layout, "", false)
    local top = y + List.HEAD
    local first, visible = List.Body(if place == "corporate" then "corporate hangar" else "own hangar", cx, top, cw,
      h - List.HEAD - List.FOOT, #items)
    if #items == 0 then
      Im.Text(if place == "corporate" then "Nothing: what your pilots bring in here is put here." else "nothing here", cx + 12, top + 8, 13,
        Theme.DIM)
    end
    for index = 1, visible do
      local item = items[index + first]
      if item == nil then
        break
      end
      local rowY = top + (index - 1) * List.ROW
      local hot = List.Row(cx, rowY, cw - 5, false)
      local info = Types.Info(item.type)
      ItemIcon.Draw(item.type, layout.name.x, rowY + 3, 19)
      if hot then
        Im.Tip(info.name, nil)
      end
      Info.Name(item.type, List.Cut(info.name, layout.name.w - 30, 14, false), layout.name.x + 26, rowY + 5, 14, Theme.TEXT)
      List.Text(Format.Whole(item.quantity), layout.qty, rowY, false, Theme.TEXT, 13)
      local ax = layout.act.x + layout.act.w
      if place == "corporate" then
        local take: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" }
        if Im.Button("Take", ax - 116, rowY + 2, 56, List.ROW - 4, (Session.CanDo(session, take)), `FromCorp:{item.type}`) then
          Session.Do(session, take)
        end
        local sell: State.Command = { kind = "SellNow", actor = 0, item = item.id, quantity = item.quantity }
        if Im.Button("Sell", ax - 56, rowY + 2, 56, List.ROW - 4, (Session.CanDo(session, sell)), `SellCorp:{item.type}`) then
          Session.Do(session, sell)
        end
      else
        local give: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "corporate" }
        if Im.Button("Give", ax - 56, rowY + 2, 56, List.ROW - 4, (Session.CanDo(session, give)), `ToCorp:{item.type}`) then
          Session.Do(session, give)
        end
      end
    end
    List.Foot(cx, y + h - List.FOOT, cw, if place == "corporate" then "the corporation's hangar here" else "your hangar here",
      if place == "corporate" then "what is sold out of it is paid to its account" else "given, it is the corporation's")
    if column == 1 then
      Im.Flat(cx + cw, y, 1, h, Theme.EDGE)
    end
  end
end

Windows.Kind(Corporation.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local was = Im.Plain(true)
  local corporation = Core.Query.Corporation(game)
  if not corporation.founded then
    drawFounding(session, corporation, x, y, w)
    Im.Plain(was)
    return
  end
  local tx = x + 10
  for _, each in { { "overview", "Overview" }, { "books", "Books" }, { "members", "Members" }, { "activity", "Activity" }, { "ops", "Ops" },
    { "hangar", "Hangar" }, { "journal", "Journal" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, page == each[1], `Corporation:{each[1]}`)
    if pressed then
      page = each[1] :: any
    end
    tx += wide + 2
  end
  local balance = Format.Credits(corporation.wallet)
  Im.Text(balance, x + w - 12 - Im.TextWidth(balance, 13), y + 10, 13, Theme.TEXT)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  if page == "books" then
    drawBooks(corporation, x + 1, top, w - 2, room)
  elseif page == "members" then
    drawMembers(session, game, x + 1, top, w - 2, room)
  elseif page == "activity" then
    drawActivity(game, x + 1, top, w - 2, room)
  elseif page == "ops" then
    drawOps(session, game, x + 1, top, w - 2, room)
  elseif page == "hangar" then
    drawHangar(session, game, x + 1, top, w - 2, room)
  elseif page == "journal" then
    Wallet.Journal("corporation journal", corporation.journal, x + 1, top, w - 2, room)
  else
    drawOverview(session, corporation, game, x, top, w)
  end
  Im.Plain(was)
end)
Windows.Make(Corporation.ID, Corporation.ID, "Corporation", 420, 130, 1040, 640, 960, 520, nil)
Windows.Icon(Corporation.ID, "corporation")

return Corporation
