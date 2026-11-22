--!strict
-- The running of a starbase of the pilot's own: a window of its own
-- (Game/UI/Windows), of what the docked screen held. Open on arrival at
-- one, as its tab was (it is what the pilot has come for), opened again
-- from the panel beside the corner's, and shut when the pilot undocks.
--
-- The tower and its field, its fuel and what it burns, the system's
-- claim and its name, the moon under it and what a drill brings up, the
-- modules anchored and what in the hangar could be, the reactions it
-- runs, and what a day of it costs and brings.
--
-- What it draws is what the tab drew, as it was set out there, in the
-- window layer's frame and colours: it has not been set out again. A
-- script's names are what they were. "Starbase", the tab's name, opens it.

local CitadelFitting = require("@lt/Game/UI/CitadelFitting")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Moons = require("@lt/Core/Data/Moons")
local Reactions = require("@lt/Core/Data/Reactions")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Starbase = {}

Starbase.ID = "starbase"

local current: Session.Session? = nil

-- The window's size at a tower (at a citadel it is CitadelFitting's).
local TOWER_W, TOWER_H = 932, 544

function Starbase.Open()
  Windows.Open(Starbase.ID)
  Windows.Raise(Starbase.ID)
end

function Starbase.Close()
  Windows.Close(Starbase.ID)
end

function Starbase.IsOpen(): boolean
  return Windows.IsOpen(Starbase.ID)
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- The name typed for a system of the pilot's own.
local claimName = ""

-- A bar of what is used of what there is, with the figures over it.
local function supply(label: string, used: number, capacity: number, unit: string, x: number, y: number, width: number)
  Im.Text(label, x, y, 13, Theme.DIM)
  Im.TextRight(`{Format.Whole(used)} / {Format.Whole(capacity)} {unit}`, x + width, y, 13, Theme.TEXT)
  Im.Flat(x, y + 20, width, 6, Theme.DIM, 0.25)
  Im.Flat(x, y + 20, width * math.clamp(used / math.max(1, capacity), 0, 1), 6, if used > capacity * 0.9 then Theme.CAUTION else Theme.ACCENT, 0.95)
end

local function drawStarbase(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus,
  x: number, y: number)
  local station = player.at
  local left = x + 16
  local line = y + 78
  local tower = status.tower

  -- The tower: its fuel, and what it supplies.
  Im.Heading("TOWER", left, line, 16, Theme.DIM)
  line += 26
  ItemIcon.Draw(tower.id, left, line, 22)
  Info.Name(tower.id, tower.name, left + 30, line + 3, 15, Theme.TEXT)
  -- (taken down into the hold, with nothing on it and nothing in it:
  -- pressed when it cannot be, it says why not)
  -- (taken down only when it can be, with the reason on the button when it cannot; and it asks again)
  do
    local down: State.Command = { kind = "UnanchorTower", actor = 0 }
    local can, whyNot = Session.CanDo(session, down)
    local sure = can and Im.Asking("Tower:down")
    if sure then
      Im.Tone("danger")
    end
    Im.Because(whyNot)
    if Im.Button(if sure then "Sure? Take down" else "Take down", left + 300, line - 1, 100, 24, can, "Tower:down") and Im.Confirm("Tower:down") then
      Session.Do(session, down)
    end
  end
  -- The pilot's claim on the system (Core/Assets/Sovereignty): how a
  -- beacon here stands, and, once the system is theirs, a name for it.
  do
    local here = Core.Query.Player(game).system
    local how, gone, takes = Core.Query.Claim(game, here)
    if how == "claiming" then
      Im.Text(`Claiming this system: {gone} of {takes} hours`, left + 420, line + 3, 13, Theme.ACCENT)
    elseif how == "contested" then
      Im.Text("The beacon claims nothing: the system is somebody's.", left + 420, line + 3, 13, Theme.CAUTION)
      Im.Text("At war with them, it is a siege: their garrison is at the lines.", left + 420, line + 20, 12, Theme.DIM)
    elseif how == "held" then
      Im.Text(if gone > 0 then `Yours, but no beacon is lit: let go in {takes - gone} h` else "This system is yours", left + 420, line + 3, 13,
        if gone > 0 then Theme.CAUTION else Theme.GOOD)
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
    Im.Text(`SEALED: nothing can touch it, and it does nothing. It opens in {Format.Duration(status.sealed)}.`, left, line, 13, Theme.CAUTION)
  elseif status.lit then
    Im.Text("Lit: its field is up and its modules have power.", left, line, 13, Theme.GOOD)
  else
    Im.Text("DARK: no fuel. Its field is down and its modules give nothing.", left, line, 13, Theme.CAUTION)
  end
  line += 24
  Im.Text("Fuel", left, line, 13, Theme.DIM)
  Im.TextRight(`{Format.Whole(status.fuel)} blocks`, left + 400, line, 13, if status.lit then Theme.TEXT else Theme.CAUTION)
  line += 20
  Im.Text(`It burns {tower.fuel} an hour`, left, line, 13, Theme.DIM)
  Im.TextRight(if status.fuel > 0 then `{Format.Duration(status.hours * 3600)} left` else "none left", left + 400, line, 13,
    if status.hours >= 1 then Theme.TEXT else Theme.CAUTION)
  line += 30
  supply("Powergrid", status.powergrid, tower.powergrid, "MW", left, line, 400)
  line += 38
  supply("CPU", status.cpu, tower.cpu, "tf", left, line, 400)
  line += 44

  -- Its moon: what is under it, and how the drilling of it stands.
  local drilling = status.drilling
  local deposit = drilling.deposit
  Im.Heading(shorten(`MOON  {string.upper(status.moon)}`, 40), left, line, 16, Theme.DIM)
  line += 24
  if deposit then
    ItemIcon.Draw(deposit.material.id, left, line - 1, 18)
    Info.Name(deposit.material.id, deposit.material.name, left + 24, line, 13, Theme.TEXT)
    Im.TextRight(`{Moons.Word(deposit.richness)}: a drill brings up {Format.Whole(drilling.perHour)} an hour`, left + 400, line, 13, Theme.DIM)
    line += 20
    local full = drilling.stored >= drilling.room
    local held = `{Format.Whole(drilling.stored)} of {Format.Whole(drilling.room)} in the hangar`
    if not drilling.anchored then
      Im.Text("No drill is anchored: a Moon Drill gets at it.", left, line, 13, Theme.DIM)
    elseif full then
      Im.Text(`Full, {held}: take some away, or anchor a Storage Array.`, left, line, 13, Theme.CAUTION)
    elseif drilling.online then
      Im.Text(`Drilling: {held}`, left, line, 13, Theme.GOOD)
      Im.TextRight(`more in {Format.Duration(status.next)}`, left + 400, line, 13, Theme.DIM)
    else
      Im.Text(`The drill is not working: {held}`, left, line, 13, Theme.CAUTION)
    end
  else
    Im.Text("Nothing under it worth a drill.", left, line, 13, Theme.DIM)
    line += 20
  end
  line += 20
  -- What it has against the pirates who come for what a drill brings
  -- up, where order is thin: its batteries and whoever holds the place.
  if status.raidMost == 0 then
    Im.Text("Order is kept here: nobody raids it.", left, line, 13, Theme.DIM)
  else
    local parts = `{status.batteries} {if status.batteries == 1 then "battery" else "batteries"}, {status.patrol} on patrol`
    Im.Text(`Defence {status.defence} ({parts})`, left, line, 13, if status.defence >= status.raidMost then Theme.GOOD
      elseif status.defence >= status.raidLeast then Theme.TEXT else Theme.CAUTION)
    Im.TextRight(`raids here come {status.raidLeast} to {status.raidMost} strong`, left + 400, line, 13, Theme.DIM)
  end
  line += 20
  -- Under fire: what is left of its shield, its armour and its
  -- structure, the sealing charges it has, and who is after it.
  local function share(value: number): string
    return `{math.ceil(value * 100)}%`
  end
  local hurt = status.shield < 0.999 or status.armor < 0.999 or status.hull < 0.999
  Im.Text(`Shield {share(status.shield)}   armour {share(status.armor)}   structure {share(status.hull)}`, left, line, 13,
    if hurt then Theme.CAUTION else Theme.DIM)
  Im.TextRight(`sealing charges {status.charges} / {status.bay}`, left + 400, line, 13,
    if status.charges == 0 and status.besieged then Theme.CAUTION else Theme.DIM)
  line += 20
  if status.siege > 0 then
    Im.Text(if status.sealed > 0 then `They will be back when it opens: {status.siege} strong against your {status.defence}.`
      else `UNDER SIEGE: {status.siege} strong against your {status.defence}.`, left, line, 13, Theme.CAUTION)
  elseif status.besieged then
    Im.Text(if status.charges > 0 then `A raid it does not match is a siege here: it seals for {status.charges} h at a quarter shield.`
      else "A raid it does not match is a siege here, and with no charge it does not seal.", left, line, 13,
      if status.charges > 0 then Theme.DIM else Theme.CAUTION)
  else
    Im.Text("Nobody comes to bring a tower down here.", left, line, 13, Theme.DIM, 0.8)
  end
  line += 26

  -- What is anchored round it.
  Im.Heading(`ANCHORED  {#status.modules}`, left, line, 16, Theme.DIM)
  line += 26
  if #status.modules == 0 then
    Im.Text("Nothing yet. A module to hand is anchored from the list on the right.", left, line, 13, Theme.DIM, 0.8)
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
    Info.Name(type.id, shorten(type.name, 24), left + 26, line + 3, 13, Theme.TEXT)
    if module.online then
      Im.Text("online", left + 214, line + 3, 13, Theme.GOOD)
    elseif module.wait > 0 then
      Im.Text(`online in {Format.Duration(module.wait)}`, left + 214, line + 3, 13, Theme.DIM)
    else
      Im.Text("no power", left + 214, line + 3, 13, Theme.CAUTION)
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
  Im.Heading(`TO HAND  {#hand}`, right, line, 16, Theme.DIM)
  line += 26
  if #hand == 0 then
    Im.Text("No fuel and no modules in the hold or the hangar.", right, line, 13, Theme.DIM, 0.8)
    Im.Text("A market sells both, under Structures.", right, line + 20, 13, Theme.DIM, 0.8)
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
    Info.Name(item.type, name, right + 26, line + 3, 13, Theme.TEXT)
    Im.Text(`x{item.quantity}  {entry.where}`, right + 30 + Im.TextWidth(name, 13), line + 3, 12, Theme.DIM)
    local fuel = item.type == Structures.FUEL.id
    -- (a sealing charge goes in its bay as fuel goes in its tank)
    local seal = item.type == Structures.SEAL.id
    local command: State.Command = { kind = if fuel or seal then "Fuel" else "AnchorModule", actor = 0, item = item.id }
    local can, whyNot = Session.CanDo(session, command)
    Im.Because(whyNot)
    if Im.Button(if fuel then "Fuel" elseif seal then "Load" else "Anchor", right + 250, line, 60, 21, can,
      if fuel then `Fuel:{entry.where}` elseif seal then `Seal:{entry.where}` else `Anchor:{item.type}`) then
      Session.Do(session, command)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 20), right + 318, line + 3, 12, Theme.CAUTION)
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
    Im.Heading("REACTOR", right, line, 16, Theme.DIM)
    Im.TextRight(if not reacting.online then "not working: the tower is dark, or it is not online yet"
      elseif making == nil then "making nothing"
      elseif reacting.starved then "idle: not enough to make it of"
      elseif short then `not enough for the batch due in {Format.Duration(status.reacts)}`
      else `{Format.Whole(Reactions.BATCH)} more in {Format.Duration(status.reacts)}`, right + 440, line + 2, 12,
      if reacting.online and making and not reacting.starved and not short then Theme.GOOD elseif making or not reacting.online then Theme.CAUTION
        else Theme.DIM)
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
      Im.Text(shorten(`{table.concat(parts, "   ")}`, 44), right, line, 13, if short then Theme.CAUTION else Theme.TEXT)
      Im.TextRight(`{Format.Whole(Reactions.BATCH)} of each an hour`, right + 440, line, 12, Theme.DIM)
    else
      Im.Text("It makes a composite of the two moon materials of a grade.", right, line, 13, Theme.DIM, 0.8)
    end
    line += 28
  end
  Im.Heading("RUNNING", right, line, 16, Theme.DIM)
  Im.TextRight("in credits' worth, since it was anchored", right + 440, line + 2, 12, Theme.DIM)
  line += 26
  Im.Text(`Fuel burnt: {Format.Whole(running.used)} blocks`, right, line, 13, Theme.DIM)
  Im.TextRight(`-{Format.Whole(running.usedWorth)}`, right + 440, line, 13, if running.used > 0 then Theme.CAUTION else Theme.DIM)
  line += 20
  Im.Text(`Brought up: {Format.Whole(running.raised)}` .. (if running.robbed > 0 then `, and {Format.Whole(running.robbed)} carried off`
    else ""), right, line, 13, Theme.DIM)
  Im.TextRight(`+{Format.Whole(running.raisedWorth - running.robbedWorth)}`, right + 440, line, 13,
    if running.raised > 0 then Theme.GOOD else Theme.DIM)
  line += 20
  Im.Text("A day, as it stands", right, line, 13, Theme.DIM)
  Im.TextRight(`+{Format.Whole(running.yieldADay)}  -{Format.Whole(running.fuelADay)}`, right + 440, line, 13,
    if running.yieldADay >= running.fuelADay and running.yieldADay > 0 then Theme.GOOD elseif status.lit then Theme.CAUTION else Theme.DIM)
end

-- Whether the pilot is docked at a starbase of their own.
function Starbase.Here(game: Core.Game, player: Core.PlayerInfo): boolean
  local status = if player.at ~= 0 then Core.Query.Starbase(game, player.at) else nil
  return status ~= nil and status.mine
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- where the pilot is docked. Come to a starbase of their own, the window
-- is open. Anywhere else it is shut.
local seenAt = -1
-- (and in front of whatever else opens as the pilot docks, the fitting
-- window for one: it is brought forward again on the frames after)
local forward = 0

function Starbase.Frame(session: Session.Session, game: Core.Game, player: Core.PlayerInfo)
  current = session
  if player.at ~= seenAt then
    seenAt = player.at
    if Starbase.Here(game, player) then
      Starbase.Open()
      forward = 2
    else
      Starbase.Close()
      forward = 0
    end
  elseif forward > 0 then
    forward -= 1
    if Windows.IsOpen(Starbase.ID) then
      Windows.Raise(Starbase.ID)
    end
  end
end

Windows.Kind(Starbase.ID, function(window: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  local status = if player.at ~= 0 then Core.Query.Starbase(game, player.at) else nil
  if status == nil or not status.mine then
    Im.Text("This is not a starbase of yours.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  -- A citadel's is laid out as the ship fitting window is, and called
  -- so (the owner's, 2026-11-19); a tower's is as it was. (The window
  -- takes the size of the one it is.)
  local citadel = status.tower.citadel == true
  local wide = if citadel then CitadelFitting.WIDTH else TOWER_W
  local tall = if citadel then CitadelFitting.HEIGHT else TOWER_H
  if window.minW ~= wide or window.minH ~= tall then
    window.w, window.h, window.minW, window.minH = wide, tall, wide, tall
  end
  window.title = if citadel then "Citadel" else "Starbase"
  local was = Im.Plain(true)
  if citadel then
    CitadelFitting.Draw(session, game, player, status, x, y, w, h)
  else
    drawStarbase(session, game, player, status, x - 4, y - 66)
  end
  Im.Plain(was)
end)
Windows.Make(Starbase.ID, Starbase.ID, "Starbase", 534, 130, TOWER_W, TOWER_H, TOWER_W, TOWER_H, nil)
Windows.Icon(Starbase.ID, "station")

return Starbase
