--!strict
-- The inventory: what the pilot has within reach, place by place, and
-- the moving of it from one place to another.
--
-- A window (Game/UI/Windows), in space and docked. Down its left side
-- are the places in reach (Core.Query.Places): the holds of the ship
-- the pilot flies; docked, the station's hangar, the holds of their
-- other ships that lie there and the corporation's hangar; in space,
-- the wrecks and containers near enough to take from. Beside them is
-- what is in the place picked out: as a list (name, how many, how much
-- room they take, what they are worth) or as icons, in the order of
-- any column, and only what a word typed in the filter is part of.
--
-- Things are moved by being carried: a stack (or all the stacks picked
-- out: Ctrl picks out more than one, Shift all from the last picked to
-- the one clicked, Ctrl+A everything shown, and a box dragged out from
-- where there is no stack all it touches) is dragged onto a place in the
-- tree, or into another inventory window, and as much of it goes as
-- there is room for. Let go with Shift held, it asks how many. A right
-- click on a stack is a menu of what can be done with it there; a
-- double click does the plain thing (out of the hangar into the hold,
-- out of the hold into the hangar, out of a wreck aboard).
--
-- Any place can have a window of its own, beside the first: a double
-- click on it in the tree, or a click with Shift held. Such a window
-- has no tree, and is gone when its place is out of reach.
--
-- For a script (Im.Press, Im.Carry): the first window's places are
-- "Inv:place:<kind>" to pick out and "Inv:onto:<kind>" to carry to
-- (the second of a kind is "<kind>:2", and so on), a stack shown is
-- "Inv:item:<type>", what is shown is "Inv:onto:contents", and its
-- other controls are "Inv:view", "Inv:filter", "Inv:sort:<column>" and
-- "Inv:lootall". A stack's menu is asked for with "Inv:menu:<type>",
-- and its entries are "Menu:<label>"; one that asks how many has the
-- field "Inv:some" and the buttons "Inv:move" and "Inv:cancel". A
-- place's own window is asked for with "Inv:beside:<kind>", and its
-- things are "Inv2:...", the next one's "Inv3:...". And what a menu
-- would offer for anything in reach can be done by name while the first
-- window is open, whatever it shows: "Fit:<type>", "Load:<type>",
-- "Refine:<type>", "ToHold:<type>", "ToHangar:<type>", "ToBay:<type>",
-- "ToShipBay:<type>", "FromBay:<type>" and "Jettison:<type>".
--
-- Ships are here too (the owner, 2026-11-23: "We should just make the
-- ships icons in the inventory, that you can right-click and
-- board/repackage/assemble/etc."): the pilot's ships that lie at the
-- station are listed in its hangar, before what it holds, each with its
-- own menu (board it, fit it out without boarding it, name it, package
-- it, leave it: the ship flown), and a packaged hull's menu assembles
-- it. A double click boards one. The ship flown is in the tree too, at
-- its top: its menu there leaves it, in space as docked. A script's
-- names for them are the Ships window's they replace: "Board:<n>",
-- "FitShip:<n>", "Repackage:<n>" (the ships at the station counted in
-- the order Core.Query.Ships has them), "Assemble:<type>", and
-- "LeaveShip"; a name is given in the field "Inv:rename" and taken with
-- "Inv:renamego".

local Catalog = require("@lt/Core/Data/Catalog")
local Core = require("@lt/Core/Api")
local Deployables = require("@lt/Core/Data/Deployables")
local Format = require("@lt/Game/Format")
local Hulls = require("@lt/Core/Data/Ships")
local List = require("@lt/Game/UI/List")
local Fitting = require("@lt/Game/UI/Fitting")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Modules = require("@lt/Core/Data/Modules")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Market = require("@lt/Game/UI/Market")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Inventory = {}

-- The first window's id, and the kind they all are.
Inventory.MAIN = "inventory"
local KIND = "inventory"

type Action = { label: string, hook: string?, can: boolean, run: () -> () }
type Split = { item: number, to: string, most: number, quantity: number }
type View = {
  place: string,                  -- the key of the place shown
  tree: boolean,                  -- whether it has the tree of places (the first window does)
  icons: boolean,
  sort: string,                   -- "" (as a hangar is set out), "name", "quantity", "volume" or "value"
  down: boolean,
  filter: string,
  chosen: { [number]: boolean },  -- the stacks picked out, by id
  anchor: number?,                -- the stack a range picked with Shift runs from
  pending: number?,               -- one of several picked, clicked: picked alone if it is let go without being carried
  box: { x: number, y: number, kept: { [number]: boolean } }?,  -- a box being dragged out to pick what it touches
  menu: { Action }?,              -- what the menu that is up offers
  split: Split?,                  -- a move that is asking how many
  rename: { ship: number, name: string }?,  -- a ship being given a name
}

local ROW = 24
local CELL = 76

local current: Session.Session? = nil
-- Whether the button for the assets window has been pressed since anybody asked.
local wantsAssets = false
-- Whether the pilot was docked when last looked at ("" before the first
-- look), and whether the first window is open in space and docked: it
-- is as it was left in each.
local mode = ""
local openIn: { [string]: boolean } = { space = false }
local windowCount = 1

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, math.max(1, limit - 1)) .. "." else text
end

local function newView(place: string, tree: boolean): View
  return { place = place, tree = tree, icons = false, sort = "", down = false, filter = "", chosen = {} }
end

-- What a script calls a window's things by: "Inv" for the first, "Inv2" for the next.
local function prefixOf(window: Windows.Window): string
  local n = string.match(window.id, ":(%d+)$")
  return if n then `Inv{n}` else "Inv"
end

-- What a script calls each place by: its kind, and for the second of a kind "<kind>:2".
local function labels(places: { Core.PlaceInfo }): { [string]: string }
  local seen: { [string]: number } = {}
  local found: { [string]: string } = {}
  for _, place in places do
    seen[place.kind] = (seen[place.kind] or 0) + 1
    found[place.key] = if seen[place.kind] == 1 then place.kind else `{place.kind}:{seen[place.kind]}`
  end
  return found
end

local function placeOf(places: { Core.PlaceInfo }, key: string): Core.PlaceInfo?
  for _, place in places do
    if place.key == key then
      return place
    end
  end
  return nil
end

-- A ship of the pilot's, as the inventory lists it: a stack of one, by
-- the ship's id made negative (it is no item: Core.Query.Ships), in the
-- hangar it lies in.
-- What a listed stack is, as a type: a ship's stack is its hull, which
-- for a capsule (listed when the pilot is in one) is no item type at
-- all, so its hull says. (2026-11-24: the capsule in the list was looked
-- up as an item and the window stopped drawing.)
local function typeInfo(id: string): Types.Info
  local known = Types.Get(id)
  if known then
    return known
  end
  local hull = Hulls.byId[id]
  return { id = id, name = if hull then hull.name else id, category = "ship", volume = if hull then hull.volume else 0,
    basePrice = if hull then hull.basePrice else 0 }
end

local function asStack(ship: State.Ship, place: string): State.Item
  return { id = -ship.id, type = ship.type, quantity = 1, holder = State.At(ship), place = place :: any, slot = 0, charge = "", rounds = 0 }
end

-- The ship a listed stack is, if it is one.
local function shipOf(game: Core.Game, item: State.Item): State.Ship?
  return if item.id < 0 then game.state.ships[-item.id] else nil
end

-- What a stack is called: a ship by its name.
local function nameOf(game: Core.Game, item: State.Item): string
  local ship = shipOf(game, item)
  return if ship then ship.name else typeInfo(item.type).name
end

-- The pilot's ships listed in a hangar here: those whose it is (theirs,
-- or the corporation's), nobody else flying them.
local function shipsIn(game: Core.Game, shown: Core.PlaceInfo): { State.Ship }
  local found: { State.Ship } = {}
  if shown.kind ~= "hangar" and shown.kind ~= "corporate" then
    return found
  end
  for _, ship in Core.Query.Ships(game, shown.holder) do
    if ship.pilot == 0 and (ship.corporate == true) == (shown.kind == "corporate")
      and (Hulls.byId[ship.type].class ~= "capsule" or ship.id == game.state.player.ship) then
      table.insert(found, ship)
    end
  end
  return found
end

-- A ship's place among those at its station (Core.Query.Ships): what a
-- script calls it by, as the Ships window did.
local function shipIndex(game: Core.Game, ship: State.Ship): number
  for index, other in Core.Query.Ships(game, State.At(ship)) do
    if other.id == ship.id then
      return index
    end
  end
  return 0
end

-- The weapons on the ship a charge would go in: every one that takes it
-- and holds something else or nothing (and a module loaded as a weapon
-- is: a booster, an ancillary repairer). All of them at once, as the
-- fitting window does (the owner, 2026-11-23).
local function weaponsFor(game: Core.Game, ship: number, charge: State.Item): { State.Item }
  local family = Modules.chargeById[charge.type].family
  local into: { State.Item } = {}
  for _, item in Core.Query.Fitted(game, ship) do
    local takes = Modules.Takes(Modules.byId[item.type])
    if takes and takes.family == family and item.charge ~= charge.type
      and (Core.Validate(game, { kind = "LoadCharge", actor = ship, item = item.id, other = charge.id })) then
      table.insert(into, item)
    end
  end
  return into
end

-- The order that moves so many of a stack to a place, or why there is none.
local function moveCommand(game: Core.Game, item: State.Item, to: Core.PlaceInfo, quantity: number): (State.Command?, string?)
  local own = game.state.player.ship
  local from = game.state.wrecks[item.holder]
  if to.kind == "wreck" then
    return nil, "nothing goes into a wreck"
  elseif to.kind == "can" then
    if item.holder ~= own then
      return nil, "take it aboard first"
    end
    return { kind = "Jettison", actor = 0, item = item.id, quantity = quantity, target = to.holder }, nil
  elseif from then
    if to.holder ~= own or to.place ~= "cargo" then
      return nil, "take it aboard first: into the hold"
    end
    return { kind = "Loot", actor = 0, target = from.id, item = item.id, quantity = quantity }, nil
  end
  return { kind = "MoveItems", actor = 0, item = item.id, to = to.place, quantity = quantity,
    target = if to.holder ~= own and to.kind ~= "hangar" and to.kind ~= "corporate" then to.holder else nil }, nil
end

-- Move stacks to a place: of each, as many as there is room for there
-- (or 'quantity' of the one, if that is said). What will not go says why.
local function move(session: Session.Session, ids: { number }, to: Core.PlaceInfo, quantity: number?)
  local game = session.game
  local room = if to.capacity > 0 then to.capacity - to.used else math.huge
  for _, id in ids do
    local ship = if id < 0 then game.state.ships[-id] else nil
    if ship then
      -- (a ship goes from one hangar here to the other: its own and the corporation's)
      local into = if to.kind == "corporate" then true elseif to.kind == "hangar" then false else nil
      if into == nil then
        Session.Say(session, "A ship goes into a hangar, the corporation's or yours")
      elseif (ship.corporate == true) ~= into then
        Session.Do(session, { kind = "MoveShip", actor = 0, target = ship.id, to = to.place })
      end
      continue
    end
    local item = game.state.items[id]
    if item and not (item.holder == to.holder and item.place == to.place) then
      local volume = typeInfo(item.type).volume
      local fits = math.min(quantity or item.quantity, item.quantity, if volume > 0 then math.floor((room + 1e-9) / volume) else item.quantity)
      if fits < 1 then
        Session.Say(session, `No room for {typeInfo(item.type).name} in {to.name}`)
      else
        local command, why = moveCommand(game, item, to, fits)
        if command == nil then
          Session.Say(session, why or "that cannot go there")
        elseif Session.Do(session, command) then
          room -= fits * volume
        end
      end
    end
  end
end

-- Where the plain thing to do with a stack puts it: out of a wreck or a
-- container aboard, out of the hangar into the hold, and anything else
-- into the hangar. Nil where there is nowhere (aboard, in space).
local function plainPlace(game: Core.Game, shown: Core.PlaceInfo, places: { Core.PlaceInfo }): Core.PlaceInfo?
  local own = game.state.player.ship
  local want = if shown.kind == "wreck" or shown.kind == "can" or shown.kind == "hangar" then `ship:{own}:cargo` else ""
  for _, place in places do
    if (want ~= "" and place.key == want) or (want == "" and place.kind == "hangar") then
      return place
    end
  end
  return nil
end

-- What can be done with a stack where it is: what a right click offers.
local shipActions: (session: Session.Session, view: View?, ship: State.Ship, places: { Core.PlaceInfo }) -> { Action }

local function actionsFor(session: Session.Session, view: View?, item: State.Item, shown: Core.PlaceInfo, places: { Core.PlaceInfo }): { Action }
  local game = session.game
  local own = game.state.player.ship
  local listedShip = shipOf(game, item)
  if listedShip then
    return shipActions(session, view, listedShip, places)
  end
  -- (docked, the hangar is in reach; and the corporation's, where there is one)
  local docked, hasCorporation = false, false
  for _, place in places do
    docked = docked or place.kind == "hangar"
    hasCorporation = hasCorporation or place.kind == "corporate"
  end
  local info = typeInfo(item.type)
  local type = item.type
  local found: { Action } = {}
  local function add(label: string, hook: string?, command: State.Command?, run: (() -> ())?, can: boolean?)
    local id = item.id
    -- (greyed, an entry says why, as the paint and book entries did and the rest did not)
    local able = can
    if able == nil and command then
      local ok, why = Session.CanDo(session, command)
      able = ok
      if not ok and why then
        label = `{label} ({why})`
      end
    end
    table.insert(found, { label = label, hook = hook,
      can = if able ~= nil then able else true,
      run = run or function()
        if command and game.state.items[id] then
          Session.Do(session, command)
        end
      end })
  end
  -- A module in the hangar is put through a mutator from its own menu
  -- (Core/Assets/Mutators): it cannot be undone, and the menu says so.
  -- Where it cannot be done (no mutator there, or the module has been
  -- through one), the entry is there only if there is a mutator to use.
  if info.category == "module" and shown.kind == "hangar" then
    local mutate: State.Command = { kind = "Mutate", actor = 0, item = item.id }
    local can, why = Session.CanDo(session, mutate)
    if can then
      add("Mutate (cannot be undone)", `Mutate:{type}`, mutate, nil, true)
    elseif why == "it has been through a mutator already" then
      add("Mutated already", nil, nil, nil, false)
    end
  end
  -- A paint or a design is made the pilot's own from its menu, wherever
  -- it lies in reach (the hangar here, or the hold): it is used up, and
  -- is theirs for good on the fitting screen's list
  -- (Core/Assets/Paintwork). Where it cannot be, the menu says why.
  -- Docked, either can be tried on the ship first, which paints
  -- nothing: the fitting screen shows the ship in it.
  if info.category == "paint" and (shown.kind == "hangar" or shown.holder == own) then
    local unlock: State.Command = { kind = "UnlockPaint", actor = 0, item = item.id }
    local can, why = Session.CanDo(session, unlock)
    add(if can then "Make it yours (uses it up)" else `Make it yours ({why or "not now"})`, `Unlock:{type}`, unlock, nil, can)
    if shown.kind == "hangar" then
      add("Try it on the ship", `Try:{type}`, nil, function()
        Session.Try(session, type)
        Fitting.Show("appearance")
      end, true)
    end
  end
  -- A skill book is learned from its own menu, wherever it lies in
  -- reach (the hangar here, or the hold): and where it cannot be, the
  -- menu says why.
  if info.category == "skillbook" and (shown.kind == "hangar" or shown.holder == own) then
    local learn: State.Command = { kind = "LearnSkill", actor = 0, item = item.id }
    local can, why = Session.CanDo(session, learn)
    add(if can then "Learn this skill" else `Learn ({why or "not now"})`, `Learn:{type}`, learn, nil, can)
  end
  -- Ore aboard a hull that is a refinery too is refined from its menu,
  -- where it lies, in space or docked (Core/Assets/Industry: the
  -- Drowned's Griever). Where it cannot be, the menu says why.
  if info.category == "ore" and shown.holder == own and Core.Query.Player(game).hull.refinery then
    local refine: State.Command = { kind = "Reprocess", actor = 0, item = item.id }
    local can, why = Session.CanDo(session, refine)
    add(if can then "Refine aboard" else `Refine aboard ({why or "not now"})`, `RefineAboard:{type}`, refine, nil, can)
  end
  if shown.kind == "wreck" or shown.kind == "can" then
    add("Take", nil, { kind = "Loot", actor = 0, target = shown.holder, item = item.id })
  elseif shown.kind == "hangar" then
    if info.category == "module" then
      add("Fit", `Fit:{type}`, { kind = "Fit", actor = 0, item = item.id })
    elseif info.category == "charge" then
      local into = weaponsFor(game, own, item)
      add(if #into > 1 then `Load into all {#into}` else "Load", `Load:{type}`, nil, function()
        for _, weapon in into do
          Session.Do(session, { kind = "LoadCharge", actor = 0, item = weapon.id, other = item.id })
        end
      end, #into > 0)
    elseif info.category == "ore" then
      add("Refine", `Refine:{type}`, { kind = "Reprocess", actor = 0, item = item.id })
    elseif info.category == "drone" then
      -- (as many of the stack as the bay has room for)
      local drones = Core.Query.Drones(game)
      local room = math.floor((drones.bay - drones.bayUsed + 1e-9) / info.volume)
      local toBay: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "dronebay", quantity = math.min(item.quantity, room) }
      add("To drone bay", `ToBay:{type}`, toBay, nil, room >= 1 and (Session.CanDo(session, toBay)))
    elseif info.category == "ship" and Core.Query.ShipBay(game, own) > 0 then
      local size, used = Core.Query.ShipBay(game, own)
      local room = math.floor((size - used + 1e-9) / info.volume)
      local toBay: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "shipbay", quantity = math.min(item.quantity, room) }
      add("To ship bay", `ToShipBay:{type}`, toBay, nil, room >= 1 and (Session.CanDo(session, toBay)))
    end
    if info.category == "ship" then
      -- (a packaged hull, put together into a ship here: Assets/Hangar)
      add("Assemble", `Assemble:{type}`, { kind = "Assemble", actor = 0, item = item.id })
    end
    add("To hold", `ToHold:{type}`, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    if hasCorporation then
      add("To corporation hangar", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "corporate" })
    end
    -- The whole stack, there and then, at what the market here pays
    -- (the owner, 2026-11-23); where it cannot be, the menu says why.
    local sell: State.Command = { kind = "SellNow", actor = 0, item = item.id, quantity = item.quantity }
    local canSell, whyNot = Session.CanDo(session, sell)
    add(if canSell then `Sell all: {Format.Credits(Core.Query.SellValue(game, item.holder, type, item.quantity))}`
      else `Sell all ({whyNot or "not now"})`, `SellAll:{type}`, sell, nil, canSell)
    add("Sell in the market...", nil, nil, function()
      Market.Choose(type)
    end)
  elseif shown.holder == own then
    if docked then
      add("To hangar", if shown.kind == "cargo" then `ToHangar:{type}` elseif shown.kind == "dronebay" then `FromBay:{type}` else nil,
        { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
      if hasCorporation then
        add("To corporation hangar", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "corporate" })
      end
    else
      add("Jettison", `Jettison:{type}`, { kind = "Jettison", actor = 0, item = item.id })
      -- (what is put out into space and picked up again: Core/Tactical/Deploy)
      if shown.kind == "cargo" and Deployables.byId[type] then
        local deploy: State.Command = { kind = "Deploy", actor = 0, item = item.id }
        local can, why = Session.CanDo(session, deploy)
        add(if can then "Put out" else `Put out ({why or "not now"})`, `Deploy:{type}`, deploy, nil, can)
      end
    end
    if shown.kind ~= "cargo" then
      add("To hold", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    elseif info.category == "drone" and placeOf(places, `ship:{own}:dronebay`) then
      add("To drone bay", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "dronebay" })
    elseif info.category == "ore" and placeOf(places, `ship:{own}:orehold`) then
      add("To ore hold", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "orehold" })
    end
  else
    -- (the corporation's hangar, or the hold of another ship that lies
    -- here; a packaged hull in the corporation's is assembled into a ship of its)
    if shown.kind == "corporate" and info.category == "ship" then
      add("Assemble", nil, { kind = "Assemble", actor = 0, item = item.id })
    end
    add("To hangar", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
    add("To hold", nil, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
  end
  local plain = plainPlace(game, shown, places)
  if view and item.quantity > 1 and plain then
    add("Move some...", nil, nil, function()
      view.split = { item = item.id, to = plain.key, most = item.quantity, quantity = 1 }
    end)
  end
  add("Info", nil, nil, function()
    Info.Open(type)
  end)
  return found
end

-- What can be done with a ship of the pilot's: what a right click on it
-- offers, in the hangar where it lies, or (the ship flown) at the top of
-- the tree.
function shipActions(session: Session.Session, view: View?, ship: State.Ship, places: { Core.PlaceInfo }): { Action }
  local game = session.game
  local flown = ship.id == game.state.player.ship
  local index = shipIndex(game, ship)
  local found: { Action } = {}
  local function add(label: string, hook: string?, command: State.Command?, run: (() -> ())?, can: boolean?)
    local able = can
    if able == nil and command then
      local ok, why = Session.CanDo(session, command)
      able = ok
      if not ok and why then
        label = `{label} ({why})`
      end
    end
    table.insert(found, { label = label, hook = hook, can = if able ~= nil then able else true,
      run = run or function()
        if command and game.state.ships[ship.id] then
          Session.Do(session, command)
        end
      end })
  end
  local hull = Hulls.byId[ship.type]
  local capsule = hull.class == "capsule"
  if flown then
    if not capsule then
      add("Leave ship", "LeaveShip", { kind = "LeaveShip", actor = 0 })
    end
  else
    add("Board", `Board:{index}`, { kind = "BoardShip", actor = 0, target = ship.id })
  end
  local docked = State.At(ship) ~= 0
  if docked and not capsule then
    add("Fit", if flown then "FitShip:0" else `FitShip:{index}`, nil, function()
      Fitting.Edit(if flown then 0 else ship.id)
    end, ship.member == nil)
  end
  if not capsule then
    add("Rename...", `RenameShip:{index}`, { kind = "RenameShip", actor = 0, target = ship.id, name = ship.name }, function()
      if view then
        view.rename = { ship = ship.id, name = ship.name }
      end
    end)
  end
  if ship.member then
    -- (assigned a member: theirs, till taken off them)
    local member = game.state.membership.members[ship.member]
    add(`Take it off {if member then member.name else "its member"}`, `Unassign:{index}`,
      { kind = "AssignMember", actor = 0, target = ship.member, item = 0 })
  end
  if not flown and docked then
    -- (into the corporation's hangar here, or out of it into the pilot's)
    local hasCorporation = false
    for _, place in places do
      hasCorporation = hasCorporation or place.kind == "corporate"
    end
    if hasCorporation then
      local to = if ship.corporate then "hangar" else "corporate"
      add(if ship.corporate then "To your hangar" else "To corporation hangar", `MoveShip:{index}`,
        { kind = "MoveShip", actor = 0, target = ship.id, to = to })
    end
    -- (packed for the market: what is fitted and carried goes into the
    -- hangar, and a rig is destroyed, as the menu says)
    local rigs = 0
    for _, fitted in Core.Query.Items(game, ship.id, "rig") do
      rigs += fitted.quantity
    end
    add(if rigs > 0 then `Repackage (destroys {rigs} rig{if rigs == 1 then "" else "s"})` else "Repackage", `Repackage:{index}`,
      { kind = "Repackage", actor = 0, target = ship.id })
  end
  add("Info", nil, nil, function()
    Info.Open(ship.type)
  end)
  return found
end

-- What is in a place, as a view shows it: only what the filter lets
-- through, in the view's order.
local function listed(game: Core.Game, view: View, shown: Core.PlaceInfo): { State.Item }
  local items: { State.Item } = {}
  local want = string.lower(view.filter)
  for _, item in Core.Query.Items(game, shown.holder, if shown.kind == "wreck" or shown.kind == "can" then nil else shown.place) do
    if item.slot == 0 and (want == "" or string.find(string.lower(typeInfo(item.type).name), want, 1, true)) then
      table.insert(items, item)
    end
  end
  -- (and the ships that lie in it, by their names or their hulls')
  for _, ship in shipsIn(game, shown) do
    if want == "" or string.find(string.lower(ship.name), want, 1, true) or string.find(string.lower(typeInfo(ship.type).name), want, 1, true) then
      table.insert(items, asStack(ship, shown.place))
    end
  end
  local function figure(item: State.Item): number
    local info = typeInfo(item.type)
    return if view.sort == "quantity" then item.quantity elseif view.sort == "volume" then item.quantity * info.volume
      else item.quantity * info.basePrice
  end
  table.sort(items, function(a: State.Item, b: State.Item): boolean
    -- (the ships first, whatever the order)
    if (a.id < 0) ~= (b.id < 0) then
      return a.id < 0
    end
    if view.sort == "name" then
      local an, bn = nameOf(game, a), nameOf(game, b)
      if an ~= bn then
        return (an < bn) ~= view.down
      end
    elseif view.sort ~= "" and figure(a) ~= figure(b) then
      -- (the most first, at first: it is what a pilot is looking for)
      return (figure(a) > figure(b)) ~= view.down
    elseif a.type ~= b.type then
      return Catalog.Before(a.type, b.type)
    end
    return a.id < b.id
  end)
  return items
end

-- What is carried when a stack is taken hold of: it, or all that are
-- picked out if it is one of them.
local function carried(game: Core.Game, view: View, item: State.Item, items: { State.Item }): ({ number }, string)
  local ids: { number } = {}
  if view.chosen[item.id] then
    for _, other in items do
      if view.chosen[other.id] then
        table.insert(ids, other.id)
      end
    end
  end
  if #ids <= 1 then
    return { item.id }, if item.id < 0 then nameOf(game, item) else `{Format.Whole(item.quantity)} {typeInfo(item.type).name}`
  end
  return ids, `{#ids} stacks`
end

-- The stacks drawn this frame, where (for a box dragged out over them),
-- and whether the cursor is on one.
local drawnStacks: { { id: number, x: number, y: number, w: number, h: number } } = {}
local overStack = false

-- A stack, as a row of the list or a cell of the icons: picked out,
-- taken hold of, clicked twice, or right clicked.
local function stack(session: Session.Session, window: Windows.Window, view: View, shown: Core.PlaceInfo, places: { Core.PlaceInfo },
  items: { State.Item }, item: State.Item, x: number, y: number, w: number, h: number)
  -- (a ship by its place among the ships here: its hull's name may be a packaged hull's)
  local listedShip = shipOf(session.game, item)
  local name = if listedShip then `{prefixOf(window)}:item:ship:{shipIndex(session.game, listedShip)}` else `{prefixOf(window)}:item:{item.type}`
  local ids, label = carried(session.game, view, item, items)
  local hot, clicked, twice = Im.Row(x, y, w, h, view.chosen[item.id] == true, name)
  Im.Grab(name, { items = ids }, label, x, y, w, h)
  -- (where it is, for a box dragged out over the stacks)
  table.insert(drawnStacks, { id = item.id, x = x, y = y, w = w, h = h })
  if hot then
    overStack = true
  end
  if clicked then
    local shift = Key_Down(Key_LShift()) or Key_Down(Key_RShift())
    local ctrl = Key_Down(Key_LControl()) or Key_Down(Key_RControl())
    if shift and view.anchor then
      -- (all from the last picked to this one, in the order they are shown)
      local a, b = 0, 0
      for index, other in items do
        if other.id == view.anchor then
          a = index
        end
        if other.id == item.id then
          b = index
        end
      end
      if a > 0 and b > 0 then
        local picked: { [number]: boolean } = if ctrl then view.chosen else {}
        for index = math.min(a, b), math.max(a, b) do
          picked[items[index].id] = true
        end
        view.chosen = picked
      end
    elseif ctrl then
      if view.chosen[item.id] then
        view.chosen[item.id] = nil
      else
        view.chosen[item.id] = true
      end
      view.anchor = item.id
    elseif not view.chosen[item.id] then
      view.chosen = { [item.id] = true }
      view.anchor = item.id
    else
      -- (one of several picked: they are carried together if it is
      -- dragged, and it is picked alone if it is only clicked)
      view.pending = item.id
    end
  end
  -- (a script asks for a stack's menu by name: it has no right click)
  local asked = Im.Hook(if listedShip then `{prefixOf(window)}:menu:ship:{shipIndex(session.game, listedShip)}` else `{prefixOf(window)}:menu:{item.type}`,
    true)
  if twice and listedShip then
    -- (a ship, clicked twice, is boarded)
    if listedShip.id ~= session.game.state.player.ship then
      Session.Do(session, { kind = "BoardShip", actor = 0, target = listedShip.id })
    end
  elseif twice then
    local plain = plainPlace(session.game, shown, places)
    if plain then
      move(session, { item.id }, plain)
    end
  elseif asked or (hot and Im.RightPressed()) then
    view.chosen = { [item.id] = true }
    local actions = actionsFor(session, view, item, shown, places)
    local names: { string }, can: { boolean } = {}, {}
    for index, action in actions do
      names[index], can[index] = action.label, action.can
    end
    view.menu = actions
    Im.OpenMenu(window.id, if asked then x + 40 else Im.Cursor().x, if asked then y + h else Im.Cursor().y, names, can)
  end
end

-- (a window of a place's own: Inventory.Beside, below)
local beside: (key: string) -> () = function() end

-- The tree of places, down a window's left side.
local function drawTree(session: Session.Session, window: Windows.Window, view: View, places: { Core.PlaceInfo }, x: number, y: number,
  w: number, h: number)
  local prefix = prefixOf(window)
  local names = labels(places)
  local rows = math.max(1, (h - 42) // 30)
  local first = Im.Scroll(`{window.id}:tree`, x, y, w, h - 34, #places, rows)
  for row = 1, rows do
    local place = places[row + first]
    if place == nil then
      break
    end
    local ry = y + 6 + (row - 1) * 30
    local inset = 10 + 12 * place.indent
    local hot, clicked, twice = Im.Row(x + 4, ry, w - 8, 28, place.key == view.place, `{prefix}:place:{names[place.key]}`)
    -- (the ship flown, at the top: its menu, to leave it, name it, look it up)
    local ship = session.game.state.ships[place.holder]
    if hot and Im.RightPressed() and place.kind == "cargo" and ship and ship.id == session.game.state.player.ship then
      local actions = shipActions(session, view, ship, places)
      local labels, can = {}, {}
      for index, action in actions do
        labels[index], can[index] = action.label, action.can
      end
      view.menu = actions
      Im.OpenMenu(window.id, Im.Cursor().x, Im.Cursor().y, labels, can)
    end
    local dropped = Im.Drop(`{prefix}:onto:{names[place.key]}`, x + 4, ry, w - 8, 28)
    if dropped and dropped.items then
      if Key_Down(Key_LShift()) and #dropped.items == 1 and session.game.state.items[dropped.items[1]]
        and session.game.state.items[dropped.items[1]].quantity > 1 then
        view.split = { item = dropped.items[1], to = place.key, most = session.game.state.items[dropped.items[1]].quantity, quantity = 1 }
      else
        move(session, dropped.items, place)
      end
    end
    Im.Text(shorten(place.name, math.max(6, (w - inset - 12) // 7)), x + inset, ry + 4, 13,
      if place.sealed then Im.WARN elseif place.key == view.place then Im.TEXT else Im.DIM)
    if place.capacity > 0 then
      local share = math.clamp(place.used / place.capacity, 0, 1)
      Im.Fill(x + inset, ry + 23, w - inset - 14, 2, Im.DIM, 0.3)
      Im.Fill(x + inset, ry + 23, (w - inset - 14) * share, 2, if share > 0.95 then Im.WARN else Im.ACCENT, 0.9)
    end
    -- (a script asks for a place's own window by name: "Inv:beside:<kind>")
    if Im.Hook(`{prefix}:beside:{names[place.key]}`, true) or (clicked and (twice or Key_Down(Key_LShift()))) then
      beside(place.key)
    elseif clicked then
      view.place, view.chosen = place.key, {}
    end
  end
  Im.Fill(x + w - 1, y + 4, 1, h - 8, Im.DIM, 0.25)
  -- (and everything the pilot owns anywhere, which is another window: Game/UI/Assets)
  if Im.Button("All assets", x + 8, y + h - 30, w - 18, 24, true, "Assets") then
    wantsAssets = true
  end
end

-- What is in the place shown, beside the tree.
local function drawContents(session: Session.Session, window: Windows.Window, view: View, shown: Core.PlaceInfo,
  places: { Core.PlaceInfo }, x: number, y: number, w: number, h: number)
  local game = session.game
  local prefix = prefixOf(window)
  local left, right = x + 10, x + w - 10
  view.filter = Im.Words(`{prefix}:filter`, view.filter, left, y + 6, math.min(150, w - 90), 24, 24, "filter")
  if Im.Button(if view.icons then "List" else "Icons", left + math.min(150, w - 90) + 8, y + 6, 56, 24, true, `{prefix}:view`) then
    view.icons = not view.icons
  end
  local top = y + 38
  if shown.capacity > 0 then
    local share = math.clamp(shown.used / shown.capacity, 0, 1)
    Im.TextRight(string.format("%s / %s m3", Format.Whole(math.floor(shown.used + 0.5)), Format.Whole(math.floor(shown.capacity + 0.5))),
      right, y + 11, 12, if share > 0.95 then Im.WARN else Im.DIM)
    Im.Fill(left, top, w - 20, 3, Im.DIM, 0.3)
    Im.Fill(left, top, (w - 20) * share, 3, if share > 0.95 then Im.WARN else Im.ACCENT, 0.9)
    top += 8
  elseif shown.sealed then
    Im.TextRight("sealed: it has to be hacked", right, y + 11, 12, Im.WARN)
  end
  local items: { State.Item } = if shown.sealed then {} else listed(game, view, shown)
  local volume, worth = 0, 0
  for _, item in items do
    local info = typeInfo(item.type)
    volume += if item.id < 0 then 0 else item.quantity * info.volume
    worth += item.quantity * info.basePrice
  end
  local foot = y + h - 28
  local bodyHeight = foot - top - 4
  table.clear(drawnStacks)
  overStack = false
  local bodyTop = top
  if view.icons then
    local across = math.max(1, (w - 16) // CELL)
    local down = math.max(1, bodyHeight // CELL)
    local lines = math.ceil(#items / across)
    local first = Im.Scroll(`{window.id}:icons`, x + 4, top, w - 8, down * CELL, lines, down)
    for line = 1, down do
      for column = 1, across do
        local item = items[(line - 1 + first) * across + column]
        if item then
          local cx, cy = left + (column - 1) * CELL, top + (line - 1) * CELL
          stack(session, window, view, shown, places, items, item, cx, cy, CELL - 4, CELL - 4)
          ItemIcon.Draw(item.type, cx + (CELL - 4 - 36) / 2, cy + 4, 36)
          local ship = shipOf(game, item)
          if ship == nil then
            Im.TextRight(Format.Whole(item.quantity), cx + CELL - 8, cy + 30, 11, Im.TEXT)
          elseif ship.id == game.state.player.ship then
            Im.TextRight("aboard", cx + CELL - 8, cy + 30, 11, Theme.GOOD)
          end
          local name = shorten(nameOf(game, item), 11)
          Im.Text(name, cx + (CELL - 4 - Im.TextWidth(name, 11)) / 2, cy + 50, 11, if ship then Im.ACCENT else Im.DIM)
        end
      end
    end
  else
    -- (the columns: a click on one's name sets the list in its order, and again the other way)
    -- (a narrow one has the name and how many, and no more)
    local narrow = w < 290
    local valueAt, volumeAt = right - 4, right - 64
    local quantityAt = if narrow then right - 4 else right - 108
    local columns: { { any } } = { { "name", "Name", left + 26, false }, { "quantity", "Qty", quantityAt, true } }
    if not narrow then
      table.insert(columns, { "volume", "m3", volumeAt, true } :: { any })
      table.insert(columns, { "value", "Est. worth", valueAt, true } :: { any })
    end
    for _, column in columns do
      local key, title, at, rightward = column[1] :: string, column[2] :: string, column[3] :: number, column[4] :: boolean
      local label = if view.sort == key then title .. (if view.down then " ^" else " v") else title
      local cx = if rightward then at - Im.TextWidth(label, 11) else at
      if Im.Link(label, cx, top, 11, if view.sort == key then Im.ACCENT else Im.DIM, `{prefix}:sort:{key}`) then
        if view.sort == key then
          if view.down then
            view.sort, view.down = "", false
          else
            view.down = true
          end
        else
          view.sort, view.down = key, false
        end
      end
    end
    top += 18
    local visible = math.max(1, (foot - top - 4) // ROW)
    local first = Im.Scroll(`{window.id}:items`, x + 4, top, w - 8, visible * ROW, #items, visible)
    for row = 1, visible do
      local item = items[row + first]
      if item == nil then
        break
      end
      local info = typeInfo(item.type)
      local ry = top + (row - 1) * ROW
      stack(session, window, view, shown, places, items, item, x + 4, ry, w - 12, ROW - 2)
      ItemIcon.Draw(item.type, left, ry + 1, 20)
      -- (the name has the row up to what its count takes, cut by how wide it is drawn, the owner, 2026-11-23)
      -- (a ship: its name and its hull's, and where its count would be whether it is the one flown)
      local ship = shipOf(game, item)
      local count = if ship then (if ship.id == game.state.player.ship then "aboard" else "") else Format.Whole(item.quantity)
      local holder = if ship and ship.member then game.state.membership.members[ship.member] else nil
      local label = if ship then `{ship.name}  ({info.name})` .. (if holder then `, {holder.name}'s` else "") else info.name
      Im.Text(List.Cut(label, quantityAt - Im.TextWidth(count, 12) - 10 - (left + 26), 13, false), left + 26, ry + 3, 13,
        if ship then Im.ACCENT else Im.TEXT)
      Im.TextRight(count, quantityAt, ry + 4, 12, if ship then Theme.GOOD else Im.TEXT)
      if not narrow and ship == nil then
        Im.TextRight(string.format("%.1f", item.quantity * info.volume), volumeAt, ry + 4, 12, Im.DIM)
        Im.TextRight(Format.Whole(item.quantity * info.basePrice), valueAt, ry + 4, 12, Im.DIM)
      elseif not narrow then
        Im.TextRight(Format.Whole(info.basePrice), valueAt, ry + 4, 12, Im.DIM)
      end
    end
  end
  if #items == 0 and not shown.sealed then
    Im.Text(if view.filter ~= "" then "nothing by that name" else "nothing here", left + 4, top + 6, 13, Im.DIM, 0.7)
  end
  -- (a click on one of several picked, let go without carrying them: that one alone)
  if view.pending then
    if Im.Carried() ~= nil then
      view.pending = nil
    elseif not Mouse_LeftDown() then
      view.chosen = { [view.pending :: number] = true }
      view.anchor = view.pending
      view.pending = nil
    end
  end
  -- Ctrl+A: everything shown, in the window in front, while nothing is being typed.
  if Windows.Front() == window.id and (Key_Down(Key_LControl()) or Key_Down(Key_RControl())) and Key_Pressed(Key_A()) and not Im.Typing() then
    view.chosen = {}
    for _, item in items do
      view.chosen[item.id] = true
    end
  end
  -- A box dragged out from where there is no stack picks all it touches
  -- (with Ctrl held, beside what was picked already).
  local cursor = Im.Cursor()
  local box = view.box
  if box == nil and Im.Pressed() and not overStack and Im.Inside(x + 4, bodyTop, w - 20, foot - bodyTop) then
    local ctrl = Key_Down(Key_LControl()) or Key_Down(Key_RControl())
    view.box = { x = cursor.x, y = cursor.y, kept = if ctrl then table.clone(view.chosen) else {} }
    if not ctrl then
      view.chosen = {}
    end
  elseif box then
    if not Mouse_LeftDown() then
      view.box = nil
    else
      local bx, by = math.min(box.x, cursor.x), math.min(box.y, cursor.y)
      local bw, bh = math.abs(cursor.x - box.x), math.abs(cursor.y - box.y)
      local picked = table.clone(box.kept)
      for _, at in drawnStacks do
        if at.x < bx + bw and at.x + at.w > bx and at.y < by + bh and at.y + at.h > by then
          picked[at.id] = true
        end
      end
      view.chosen = picked
      Im.Flat(bx, by, bw, bh, Im.ACCENT, 0.12)
      Im.Edge(bx, by, bw, bh, Im.ACCENT, 0.8)
    end
  end
  -- Under it: what it comes to, and for a wreck or a container the taking of all of it.
  Im.Text(string.format("%d %s   %s m3   est. worth %s", #items, if #items == 1 then "stack" else "stacks",
    Format.Whole(math.floor(volume + 0.5)), Format.Whole(worth)), left, foot + 6, 12, Im.DIM)
  if shown.kind == "wreck" or shown.kind == "can" then
    local all: State.Command = { kind = "Loot", actor = 0, target = shown.holder }
    if Im.Button("Loot all", right - 88, foot + 1, 76, 24, (Session.CanDo(session, all)), `{prefix}:lootall`) then
      Session.Do(session, all)
    end
  end
  -- (what is let go anywhere on it goes into the place shown)
  local dropped = Im.Drop(`{prefix}:onto:contents`, x, y, w, h)
  if dropped and dropped.items then
    local one = if #dropped.items == 1 then game.state.items[dropped.items[1]] else nil
    if Key_Down(Key_LShift()) and one and one.quantity > 1 and not (one.holder == shown.holder and one.place == shown.place) then
      view.split = { item = one.id, to = shown.key, most = one.quantity, quantity = 1 }
    else
      move(session, dropped.items, shown)
    end
  end
end

-- A move that is asking how many: over the foot of the window.
local function drawSplit(session: Session.Session, window: Windows.Window, view: View, places: { Core.PlaceInfo }, x: number, y: number,
  w: number, h: number)
  local split = view.split
  if split == nil then
    return
  end
  local item = session.game.state.items[split.item]
  local to = placeOf(places, split.to)
  if item == nil or to == nil then
    view.split = nil
    return
  end
  local prefix = prefixOf(window)
  local top = y + h - 64
  Im.Panel(x + 4, top, w - 8, 60)
  Im.Text(shorten(`How many {typeInfo(item.type).name} to {to.name}? ({Format.Whole(item.quantity)} at most)`, math.max(20, (w - 24) // 7)),
    x + 14, top + 8, 13, Im.TEXT)
  split.quantity = math.clamp(math.floor(Im.Number(`{prefix}:some`, split.quantity, x + 14, top + 30, 90, 24)), 0, item.quantity)
  if Im.Button("Move", x + 112, top + 30, 60, 24, split.quantity >= 1, `{prefix}:move`) then
    move(session, { item.id }, to, split.quantity)
    view.split = nil
  end
  if Im.Button("Cancel", x + 178, top + 30, 64, 24, true, `{prefix}:cancel`) then
    view.split = nil
  end
end

-- A ship being given a name: over the foot of the window.
local function drawRename(session: Session.Session, window: Windows.Window, view: View, x: number, y: number, w: number, h: number)
  local rename = view.rename
  if rename == nil then
    return
  end
  local ship = session.game.state.ships[rename.ship]
  if ship == nil then
    view.rename = nil
    return
  end
  local prefix = prefixOf(window)
  local top = y + h - 64
  Im.Panel(x + 4, top, w - 8, 60)
  Im.Text(shorten(`A name for the {ship.name}:`, math.max(20, (w - 24) // 7)), x + 14, top + 8, 13, Im.TEXT)
  rename.name = Im.Words(`{prefix}:rename`, rename.name, x + 14, top + 30, math.max(80, w - 180), 24, 32, "name")
  local command: State.Command = { kind = "RenameShip", actor = 0, target = ship.id, name = rename.name }
  if Im.Button("Rename", x + w - 156, top + 30, 70, 24, (Session.CanDo(session, command)), `{prefix}:renamego`) then
    Session.Do(session, command)
    view.rename = nil
  end
  if Im.Button("Cancel", x + w - 80, top + 30, 64, 24, true, `{prefix}:renamecancel`) then
    view.rename = nil
  end
end

local function draw(window: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local view = window.state :: View
  local places = Core.Query.Places(game)
  local found = placeOf(places, view.place)
  if found == nil then
    -- (a window of a place's own is gone with its place)
    if not view.tree then
      Windows.Close(window.id)
      return
    end
    found = places[1]
    if found == nil then
      Im.Text("nothing in reach", x + 14, y + 12, 13, Im.DIM)
      return
    end
    view.place, view.chosen = found.key, {}
  end
  local shown: Core.PlaceInfo = found :: Core.PlaceInfo
  window.title = if view.tree then "Inventory" else shown.name
  -- What was picked from this window's menu.
  local pick = Im.Picked(window.id)
  if pick and view.menu and view.menu[pick] then
    view.menu[pick].run()
  end
  if not Im.MenuOpen() then
    view.menu = nil
  end
  -- (for a script, in the first window: what a menu would offer for anything in reach, by name)
  if Host.scripted and window.id == Inventory.MAIN then
    -- (the ships here, and the one flown wherever it is: what their menus offer)
    local ships: { State.Ship } = {}
    local mine = game.state.ships[game.state.player.ship]
    if mine and State.At(mine) == 0 then
      table.insert(ships, mine)
    end
    for _, place in places do
      for _, ship in shipsIn(game, place) do
        table.insert(ships, ship)
      end
    end
    for _, ship in ships do
      for _, action in shipActions(session, view, ship, places) do
        if action.hook and Im.Hook(action.hook, action.can) then
          action.run()
        end
      end
    end
    for _, place in places do
      if not place.sealed and place.kind ~= "wreck" and place.kind ~= "can" then
        for _, item in Core.Query.Items(game, place.holder, place.place) do
          if item.slot == 0 then
            for _, action in actionsFor(session, nil, item, place, places) do
              if action.hook and Im.Hook(action.hook, action.can) then
                action.run()
              end
            end
          end
        end
      end
    end
  end
  local treeWidth = if view.tree then math.clamp(math.floor(w * 0.3), 130, 190) else 0
  if view.tree then
    drawTree(session, window, view, places, x, y, treeWidth, h)
  end
  drawContents(session, window, view, shown, places, x + treeWidth, y, w - treeWidth, h)
  drawSplit(session, window, view, places, x + treeWidth, y, w - treeWidth, h)
  drawRename(session, window, view, x + treeWidth, y, w - treeWidth, h)
end

Windows.Kind(KIND, draw)
Windows.Make(Inventory.MAIN, KIND, "Inventory", 60, 130, 470, 560, 380, 240, newView("", true))
Windows.Icon(Inventory.MAIN, "inventory")

-- Whether the assets window has been asked for (once: it is whoever
-- draws that window that opens it).
function Inventory.WantsAssets(): boolean
  local was = wantsAssets
  wantsAssets = false
  return was
end

function Inventory.IsOpen(): boolean
  return Windows.IsOpen(Inventory.MAIN)
end

function Inventory.Open()
  Windows.Open(Inventory.MAIN)
end

function Inventory.Close()
  Windows.Close(Inventory.MAIN)
end

-- Open the first window on a place, by whose it is and which of its
-- stores (a wreck's is its id and nothing): what looting a wreck does.
function Inventory.Show(holder: number, place: string?)
  local window = Windows.Get(Inventory.MAIN)
  if window then
    local view = window.state :: View
    view.place = if place then `ship:{holder}:{place}` else `wreck:{holder}`
    view.chosen = {}
    Windows.Open(Inventory.MAIN)
  end
end

-- A window of a place's own, beside the first: the one there is for
-- it, brought to the front, or a new one.
function Inventory.Beside(key: string)
  for _, window in Windows.Of(KIND) do
    local view = window.state :: View
    if not view.tree and view.place == key then
      Windows.Open(window.id)
      return
    end
  end
  windowCount += 1
  local first = Windows.Get(Inventory.MAIN)
  local x, y = if first then first.x + first.w + 8 else 500, if first then first.y + 30 * ((windowCount - 2) % 6) else 130
  local window = Windows.Make(`{Inventory.MAIN}:{windowCount}`, KIND, "", x, y, 360, 420, 260, 200, newView(key, false))
  Windows.Open(window.id)
end
beside = Inventory.Beside

-- How many inventory windows are open, and what the first one shows:
-- the kind of place, how many stacks of it are listed, and whether as
-- icons. (For a script to look at.)
function Inventory.Showing(): (number, string, number, boolean)
  local open = 0
  for _, window in Windows.Of(KIND) do
    open += if window.open then 1 else 0
  end
  local session = current
  local first = Windows.Get(Inventory.MAIN)
  if session == nil or first == nil then
    return open, "", 0, false
  end
  local view = first.state :: View
  local shown = placeOf(Core.Query.Places(session.game), view.place)
  if shown == nil then
    return open, "", 0, view.icons
  end
  return open, shown.kind, #listed(session.game, view, shown), view.icons
end

-- How many stacks are picked out in the first window.
function Inventory.Chosen(): number
  local first = Windows.Get(Inventory.MAIN)
  if first == nil then
    return 0
  end
  local count = 0
  for _ in (first.state :: View).chosen do
    count += 1
  end
  return count
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked. The first window is open or shut as it
-- was left the last time the pilot was docked, or in space: and the
-- first time docked, open, since it is what a ship is fitted from.
function Inventory.Frame(session: Session.Session, docked: boolean)
  current = session
  local now = if docked then "docked" else "space"
  if now ~= mode then
    if mode ~= "" then
      openIn[mode] = Windows.IsOpen(Inventory.MAIN)
    elseif openIn.docked == nil then
      local was = Windows.WasOpen(Inventory.MAIN)
      openIn.docked = if was ~= nil then was else true
    end
    mode = now
    if openIn[now] then
      Windows.Open(Inventory.MAIN)
    else
      Windows.Close(Inventory.MAIN)
    end
    -- (and the windows of places' own are of where the pilot was)
    for _, window in Windows.Of(KIND) do
      if window.id ~= Inventory.MAIN then
        Windows.Forget(window.id)
      end
    end
  end
  for _, window in Windows.Of(KIND) do
    if window.id ~= Inventory.MAIN and not window.open then
      Windows.Forget(window.id)
    end
  end
end

return Inventory
