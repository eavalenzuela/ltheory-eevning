--!strict
-- The wallet: a window of its own (Game/UI/Windows), of what the docked
-- screen held. A station's: opened from the dock, by either of two
-- buttons (the pilot's own books, and their corporation's), and shut
-- when the pilot undocks.
--
-- The pilot's side is their journal: what has come in and gone out. The
-- corporation's side is its founding, where there is none, and then its
-- journal, its books by head with the towers on them, its hangar at the
-- station and its members (Core/Assets/Members).
--
-- What it draws is what the tab drew, as it was set out there, in the
-- window layer's frame and colours: it has not been set out again. A
-- script's names are what they were: "Wallet:mine",
-- "Wallet:corporation", "Corporation:name", "Corporation:found" and the
-- rest. "Wallet", the tab's name, opens it.

local Catalog = require("@lt/Core/Data/Catalog")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Wallet = {}

Wallet.ID = "wallet"

local current: Session.Session? = nil

function Wallet.Open()
  Windows.Open(Wallet.ID)
  Windows.Raise(Wallet.ID)
end

function Wallet.Close()
  Windows.Close(Wallet.ID)
end

function Wallet.IsOpen(): boolean
  return Windows.IsOpen(Wallet.ID)
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- Which side of the Wallet tab is shown (the pilot's own, or their
-- corporation's); the name a corporation would be founded under; and
-- how much is to go into its account or come out of it.
local books = "mine"

-- Which of the wallet's books is open: "mine" or "corporation" (for the
-- dock, which has a button for each: Game/UI/Dock).
function Wallet.Books(): string
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
  Im.Heading(`MEMBERS  {#info.members} OF {info.room}`, left, line, 14, Theme.DIM)
  Im.Text("Tax", left + 250, line + 1, 13, Theme.DIM)
  if taxTyped < 0 then
    taxTyped = math.floor(info.tax * 100 + 0.5)
  end
  taxTyped = math.max(0, math.floor(Im.Number("Members:tax", taxTyped, left + 284, line - 4, 50, 24)))
  local setTax: State.Command = { kind = "SetTax", actor = 0, quantity = taxTyped }
  if Im.Button("Set", left + 340, line - 4, 44, 24, taxTyped ~= math.floor(info.tax * 100 + 0.5) and (Session.CanDo(session, setTax)),
    "Members:settax") then
    Session.Do(session, setTax)
  end
  Im.Text("% of what each earns. Over what a member will bear, they leave.", left + 394, line + 1, 12, Theme.DIM)
  line += 26
  if #info.members == 0 then
    Im.Text("Nobody yet. Pilots apply as the corporation has more to offer, and some at stations are open to being asked.", left, line, 12,
      Theme.DIM)
    line += 20
  end
  local rows = 6
  local first = Im.Scroll("members", left - 4, line, 860, rows * 20, #info.members, rows)
  for index = first + 1, math.min(#info.members, first + rows) do
    local member = info.members[index]
    Im.Text(shorten(member.name, 22), left, line, 13, Theme.TEXT)
    Im.Text(member.trade, left + 170, line, 13, Theme.DIM)
    Im.Text(shorten(member.hull, 20), left + 236, line, 13, Theme.DIM)
    Im.Text(shorten(`{member.doing} in {member.system}` .. (if member.called then " (a call)" else ""), 30), left + 390, line, 13,
      if member.doing == "idle" or member.doing == "refitting" then Theme.CAUTION else Theme.TEXT)
    -- (and what they have lost, if they have: it is theirs to bear)
    Im.TextRight(`paid {Format.Whole(member.paid)}` .. (if member.lost > 0 then `, {member.lost} lost` else ""), left + 760, line, 12, Theme.DIM)
    if Im.Button("Expel", left + 770, line - 2, 56, 18, true, `Member:expel:{index}`) then
      Session.Do(session, { kind = "ExpelMember", actor = 0, target = member.id })
    end
    line += 20
  end
  line = top + 26 + math.max(1, math.min(rows, math.max(1, #info.members))) * 20 + 8
  -- Who would join: those who applied, and those open to it here.
  Im.Heading("WOULD JOIN", left, line, 14, Theme.DIM)
  line += 22
  local shown = 0
  local function candidate(one: Core.ApplicantInfo, here: boolean, index: number)
    Im.Text(shorten(one.name, 22), left, line, 13, Theme.TEXT)
    Im.Text(one.trade, left + 170, line, 13, Theme.DIM)
    Im.Text(shorten(one.hull, 20), left + 236, line, 13, Theme.DIM)
    Im.Text(`bears {percent(one.bears)}` .. (if here then ", is here" else ", has applied"), left + 390, line, 12,
      if one.bears + 1e-9 < info.tax then Theme.CAUTION else Theme.DIM)
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
    Im.Text("Nobody is waiting, and nobody here is open to it today.", left, line, 12, Theme.DIM)
    line += 20
  end
  line += 8
  -- The calls.
  Im.Heading("CALLS", left, line, 14, Theme.DIM)
  Im.Text("Not orders: a member answers one that suits their trade and pays better than what they were doing.", left + 70, line + 1, 12,
    Theme.DIM)
  line += 22
  for index, call in info.calls do
    Im.Text(`{call.kind} in {call.system}`, left, line, 13, Theme.TEXT)
    Im.Text(if call.reward > 0 then `{Format.Whole(call.reward)} cr a day each` else "no reward", left + 236, line, 13, Theme.DIM)
    Im.Text(`{call.answering} answering`, left + 420, line, 13, if call.answering > 0 then Theme.GOOD else Theme.DIM)
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
    Im.Text("cr a day", left + 352, line + 5, 12, Theme.DIM)
    local post: State.Command = { kind = "PostCall", actor = 0, what = CALL_KINDS[callKind], target = info.places[callWhere].id,
      quantity = math.max(0, math.floor(callReward)) }
    local can, why = Session.CanDo(session, post)
    if Im.Button("Post call", left + 420, line, 90, 24, can, "Call:post") then
      Session.Do(session, post)
    end
    if not can and why then
      Im.Text(shorten(why, 46), left + 520, line + 5, 12, Theme.DIM)
    end
  end
end

local function drawBooks(corporation: Core.CorporationInfo, left: number, top: number)
  local line = top
  Im.Heading("BY HEAD", left, line, 14, Theme.DIM)
  Im.TextRight("since it was founded", left + 400, line + 1, 12, Theme.DIM)
  line += 24
  if #corporation.heads == 0 then
    Im.Text("Nothing has been earned or spent yet.", left, line, 13, Theme.DIM, 0.8)
    line += 22
  end
  for _, head in corporation.heads do
    Im.Text(head.name, left, line, 14, Theme.TEXT)
    Im.TextRight((if head.amount >= 0 then "+" else "") .. Format.Whole(head.amount), left + 400, line, 14,
      if head.amount >= 0 then Theme.GOOD else Theme.CAUTION)
    line += 22
  end
  local net = corporation.earned - corporation.spent
  Im.Flat(left, line + 2, 400, 1, Theme.DIM, 0.4)
  line += 8
  Im.Text("Which makes", left, line, 14, Theme.DIM)
  Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 400, line, 14, if net >= 0 then Theme.GOOD else Theme.CAUTION)
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
    Im.Heading("THE TOWERS, ALL TOLD", left, line, 14, Theme.DIM)
    Im.TextRight("in credits' worth", left + 400, line + 1, 12, Theme.DIM)
    line += 24
    local told: { { name: string, worth: number, gain: boolean } } = {
      { name = "Brought up", worth = raised, gain = true }, { name = "Carried off by raiders", worth = robbed, gain = false },
      { name = "Fuel burnt", worth = burnt, gain = false },
    }
    for _, row in told do
      Im.Text(row.name, left, line, 14, Theme.TEXT)
      Im.TextRight((if row.worth == 0 then "" elseif row.gain then "+" else "-") .. Format.Whole(row.worth), left + 400, line, 14,
        if row.worth == 0 then Theme.DIM elseif row.gain then Theme.GOOD else Theme.CAUTION)
      line += 22
    end
    Im.Text("A day, as they stand", left, line, 14, Theme.DIM)
    Im.TextRight(`+{Format.Whole(yieldADay)}  -{Format.Whole(fuelADay)}`, left + 400, line, 14,
      if yieldADay >= fuelADay then Theme.GOOD else Theme.CAUTION)
  end

  local right = left + 470
  line = top
  Im.Heading(`TOWERS  {#corporation.towers}`, right, line, 14, Theme.DIM)
  line += 24
  if #corporation.towers == 0 then
    Im.Text("You have no tower. One is anchored at a moon, from the hold.", right, line, 13, Theme.DIM, 0.8)
  end
  local visible = 5
  local first = Im.Scroll("corporation towers", right - 4, line, 440, visible * 68, #corporation.towers, visible)
  for row = 1, visible do
    local tower = corporation.towers[row + first]
    if tower == nil then
      break
    end
    local running = tower.running
    Im.Text(shorten(tower.name, 38), right, line, 14, Theme.TEXT)
    Im.TextRight(if tower.lit then tower.system else `{tower.system}: DARK`, right + 436, line + 1, 12, if tower.lit then Theme.DIM else Theme.CAUTION)
    local what = if running.material ~= "" then Types.Info(running.material).name else "nothing under it"
    Im.Text(`burnt {Format.Whole(running.used)} blocks ({Format.Whole(running.usedWorth)})`, right, line + 21, 12, Theme.DIM)
    Im.TextRight(if running.material == "" then what
      else `{Format.Whole(running.raised)} {what} up ({Format.Whole(running.raisedWorth)})`
        .. (if running.robbed > 0 then `, {Format.Whole(running.robbed)} lost` else ""), right + 436, line + 21, 12,
      if running.robbed > 0 then Theme.CAUTION else Theme.DIM)
    Im.Text(`a day: {Format.Whole(running.fuelADay)} of fuel`, right, line + 39, 12, Theme.DIM)
    Im.TextRight(if running.yieldADay > 0 then `brings up {Format.Whole(running.yieldADay)}` else "brings up nothing", right + 436,
      line + 39, 12, if running.yieldADay > running.fuelADay then Theme.GOOD else Theme.DIM)
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
    Im.Heading(if place == "corporate" then `THE CORPORATION'S HANGAR HERE  {#items}` else `YOUR HANGAR HERE  {#items}`, x, top, 16, Theme.DIM)
    local line = top + 26
    if #items == 0 then
      Im.Text(if place == "corporate" then "Nothing: what your pilots bring in here is put here." else "nothing here", x, line, 13, Theme.DIM, 0.8)
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
      Info.Name(item.type, name, x + 26, line + 3, 13, Theme.TEXT)
      Im.Text(`x{Format.Whole(item.quantity)}`, x + 30 + Im.TextWidth(name, 13), line + 3, 12, Theme.DIM)
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
    left, foot, 13, Theme.DIM)
  Im.Text("What is sold out of it is paid to the corporation's account. A tower's drill fills the corporation's hangar there.", left,
    foot + 19, 13, Theme.DIM)
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
    Im.Heading("NO CORPORATION", left, top, 16, Theme.DIM)
    line = top + 34
    for _, text in { "A corporation is the business your hired pilots work for. It has an account of its own:",
      "their signing on, their wages and the mending of their ships come out of it, and what they sell",
      "and the bounties they earn with you elsewhere go into it, so its books say what they make against",
      `what they cost. It has places for {corporation.staff} more pilots than your Leadership commands. Where its account`,
      "is short, your own wallet pays the difference. It is founded once, here, under a name of yours." } do
      Im.Text(text, left, line, 13, Theme.DIM)
      line += 19
    end
    line += 14
    Im.Text("Name", left, line + 5, 14, Theme.DIM)
    corporationName = Im.Words("Corporation:name", corporationName, left + 60, line, 300, 28, 24, "three letters to twenty-four")
    local found: State.Command = { kind = "FoundCorporation", actor = 0, what = corporationName }
    local can, whyNot = Session.CanDo(session, found)
    if Im.Button(`Found it: {Format.Credits(corporation.fee)}`, left + 372, line, 200, 28, can, "Corporation:found") then
      Session.Do(session, found)
      books = "corporation"
    end
    if not can and corporationName ~= "" then
      Im.Text(tostring(whyNot), left + 584, line + 6, 13, Theme.CAUTION)
    end
    return
  elseif books == "corporation" then
    journal = corporation.journal
    Im.Heading(string.upper(corporation.name), left, top, 16, Theme.DIM)
    Im.Heading(Format.Credits(corporation.wallet), left, top + 24, 22, Theme.TEXT)
    Im.Text(`founded {Format.Clock(corporation.since)}`, left + 2, top + 54, 12, Theme.DIM)
    -- Its books: what its pilots have made against what they have cost.
    local net = corporation.earned - corporation.spent
    Im.Text("earned", left + 250, top + 26, 12, Theme.DIM)
    Im.TextRight(Format.Whole(corporation.earned), left + 400, top + 24, 14, Theme.GOOD)
    Im.Text("spent", left + 250, top + 46, 12, Theme.DIM)
    Im.TextRight(Format.Whole(corporation.spent), left + 400, top + 44, 14, Theme.CAUTION)
    Im.Text("which makes", left + 420, top + 26, 12, Theme.DIM)
    Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 600, top + 24, 14, if net >= 0 then Theme.GOOD else Theme.CAUTION)
    Im.Text("wages a day", left + 420, top + 46, 12, Theme.DIM)
    Im.TextRight(Format.Whole(corporation.wages), left + 600, top + 44, 14, Theme.TEXT)
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
    Im.Heading("BALANCE", left, top, 16, Theme.DIM)
    Im.Heading(Format.Credits(game.state.wallet), left + 110, top - 4, 22, Theme.TEXT)
  end
  Im.Text("WHEN", left, line, 12, Theme.DIM)
  Im.Text("WHAT", left + 150, line, 12, Theme.DIM)
  Im.TextRight("AMOUNT", left + 600, line, 12, Theme.DIM)
  Im.TextRight("BALANCE", left + 780, line, 12, Theme.DIM)
  line += 20
  if #journal == 0 then
    Im.Text("Nothing has been paid or earned yet.", left, line, 14, Theme.DIM, 0.8)
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
    Im.Text(Format.Clock(entry.tick), left, rowY + 3, 13, Theme.DIM)
    Im.Text(entry.reason, left + 150, rowY + 3, 14, Theme.TEXT)
    Im.TextRight((if entry.amount >= 0 then "+" else "") .. Format.Whole(entry.amount), left + 600, rowY + 3, 14,
      if entry.amount >= 0 then Theme.GOOD else Theme.CAUTION)
    Im.TextRight(Format.Whole(entry.balance), left + 780, rowY + 3, 14, Theme.DIM)
  end
end

-- Open the window at one of its two sides: "mine" or "corporation".
function Wallet.Show(which: string)
  books = if which == "corporation" then "corporation" else "mine"
  Wallet.Open()
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked (the window is a station's: Windows.Berthed).
function Wallet.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Wallet.ID, docked)
end

Windows.Kind(Wallet.ID, function(_: Windows.Window, x: number, y: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  if Core.Query.Player(game).docked == 0 then
    Im.Text("The books are kept at a station: dock at one.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local was = Im.Plain(true)
  drawWallet(session, game, x - 4, y - 66)
  Im.Plain(was)
end)
Windows.Make(Wallet.ID, Wallet.ID, "Wallet", 534, 130, 932, 544, 932, 544, nil)
Windows.Icon(Wallet.ID, "wallet")

return Wallet
