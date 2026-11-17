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
-- "...:members", "...:hangar", "...:journal"; "Members:tax",
-- "Members:settax", "Member:expel:<n>", "Member:invite:<n>",
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
local page: "overview" | "books" | "members" | "hangar" | "journal" = "overview"
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

local MEMBERS: { List.Column } = {
  { id = "name", label = "Member", width = 0, sort = false }, { id = "trade", label = "Trade", width = 80, sort = false },
  { id = "ship", label = "Flies", width = 150, sort = false }, { id = "doing", label = "Doing", width = 220, sort = false },
  { id = "paid", label = "Paid", width = 110, right = true, sort = false }, { id = "act", label = "", width = 140, right = true, sort = false },
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
  Im.Text("% of what each earns. Over what a member will bear, they leave.", left + 160, y + 14, 12, Theme.DIM)
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
    local hot = List.Row(x, rowY, w - 5, false)
    List.Text(member.name .. (if member.alt then "  (yours)" else ""), layout.name, rowY, hot, if member.alt then Theme.GOOD else Theme.TEXT, 14)
    List.Text(member.trade, layout.trade, rowY, false, Theme.DIM, 13)
    List.Text(member.hull, layout.ship, rowY, hot, Theme.DIM, 13)
    List.Text(`{member.doing} in {member.system}` .. (if member.called then " (a call)" else ""), layout.doing, rowY, hot,
      if member.doing == "idle" or member.doing == "refitting" then Theme.CAUTION else Theme.TEXT, 13)
    List.Text(Format.Whole(member.paid) .. (if member.lost > 0 then `, {member.lost} lost` else ""), layout.paid, rowY, false, Theme.DIM, 12)
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
  for _, each in { { "overview", "Overview" }, { "books", "Books" }, { "members", "Members" }, { "hangar", "Hangar" }, { "journal", "Journal" } } do
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
