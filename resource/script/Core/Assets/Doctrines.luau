--!strict
-- Doctrines: what the corporation's fleet flies (the owner, 2026-11-23:
-- "everyone in the fleet gets this hull and this saved fit ... as long
-- as I can then override it on a per-member level to e.g. switch some of
-- them to logi, tackling"; docs/design/corp-ships.md, phase 5).
--
-- A doctrine has a name and roles, each a name and a saved fit
-- (Assets/SavedFits: a hull and its modules). The first role is the one
-- everybody takes; a member can be set to another of its roles by name
-- (Member.doctrineRole), which holds for any doctrine with a role of
-- that name.
--
-- Applied to the fleet, docked: each member of it is given a ship of the
-- corporation's at the station whose hull and modules are their role's
-- fit, exactly (theirs already, or nobody's). Where none is ready, one is
-- put together there out of the corporation's hangar: the packaged hull
-- and every module of the fit, or nothing ("If any module is missing, it
-- won't fit. Keep it as simple as possible while allowing for quick
-- outfitting of larger fleets"). What there was not enough of is said.
-- Charges are not loaded: members buy their own.

local Corporation = require("@lt/Core/Assets/Corporation")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Doctrines = {}

export type Event = { [string]: any }

Doctrines.COMMANDS = { NewDoctrine = true, DeleteDoctrine = true, AddDoctrineRole = true, RemoveDoctrineRole = true,
  MainDoctrineRole = true, SetDoctrineRole = true, ApplyDoctrine = true } :: { [string]: boolean }
-- How many doctrines there may be, roles one may have, and how long a name is at most.
Doctrines.MOST, Doctrines.ROLES, Doctrines.NAME = 20, 8, 32

function Doctrines.List(state: State.State): { State.Doctrine }
  state.membership.doctrines = state.membership.doctrines or {}
  return state.membership.doctrines :: { State.Doctrine }
end

function Doctrines.Get(state: State.State, id: number): State.Doctrine?
  for _, doctrine in Doctrines.List(state) do
    if doctrine.id == id then
      return doctrine
    end
  end
  return nil
end

-- The role of a doctrine a member flies in: the one of the name they are
-- set to, where it has one; else its first.
function Doctrines.RoleFor(doctrine: State.Doctrine, member: State.Member?): (State.DoctrineRole?, number)
  local want = if member then member.doctrineRole or "" else ""
  for index, role in doctrine.roles do
    if want ~= "" and string.lower(role.name) == string.lower(want) then
      return role, index
    end
  end
  return doctrine.roles[1], 1
end

-- How many of each module type a list has.
local function counted(types: { string }): { [string]: number }
  local found: { [string]: number } = {}
  for _, type in types do
    found[type] = (found[type] or 0) + 1
  end
  return found
end

-- The module types of a saved fit, one for each fitted.
local function fitTypes(fit: State.SavedFit): { string }
  local found: { string } = {}
  for _, module in fit.modules do
    table.insert(found, module.type)
  end
  return found
end

-- Whether a ship is as a saved fit is: its hull, and its modules, no more
-- and no fewer of each.
function Doctrines.Matches(state: State.State, ship: State.Ship, fit: State.SavedFit): boolean
  if ship.type ~= fit.hull then
    return false
  end
  local have: { string } = {}
  for _, item in Items.Fitted(state, ship.id) do
    table.insert(have, item.type)
  end
  if #have ~= #fit.modules then
    return false
  end
  local want = counted(fitTypes(fit))
  for type, count in counted(have) do
    if want[type] ~= count then
      return false
    end
  end
  return true
end

-- A ship of the corporation's at a station as a fit is, that a member may
-- be given: nobody's, or theirs ('member'), nobody flying it but them, not
-- the pilot's own ship; and not one given already ('taken').
local function ready(state: State.State, station: number, fit: State.SavedFit, member: number, taken: { [number]: boolean }): State.Ship?
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.corporate and ship.owner == "player" and ship.docked == station and ship.id ~= state.player.ship and not taken[ship.id]
      and (ship.member == nil or ship.member == member) and Doctrines.Matches(state, ship, fit) then
      return ship
    end
  end
  return nil
end

-- What the corporation's hangar at a station has of each type, for a fit
-- to be made of ('stock', worked out once and drawn down as fits are
-- counted against it): whether it has the packaged hull and every module
-- of the fit, and if so, drawn down by them.
local function stockOf(state: State.State, station: number): { [string]: number }
  local found: { [string]: number } = {}
  for _, item in Items.In(state, station, "corporate") do
    found[item.type] = (found[item.type] or 0) + item.quantity
  end
  return found
end
local function draw(stock: { [string]: number }, fit: State.SavedFit, short: { [string]: number }): boolean
  local want = counted(fitTypes(fit))
  want[fit.hull] = (want[fit.hull] or 0) + 1
  local enough = true
  for type, count in want do
    if (stock[type] or 0) < count then
      enough = false
      short[type] = (short[type] or 0) + count - (stock[type] or 0)
    end
  end
  if enough then
    for type, count in want do
      stock[type] -= count
    end
  end
  return enough
end

-- A ship of the corporation's put together at a station out of its
-- hangar there: the packaged hull and the fit's modules (there: draw).
local function assemble(state: State.State, station: number, fit: State.SavedFit, events: { Event }): State.Ship
  local function take(type: string)
    for _, item in Items.In(state, station, "corporate") do
      if item.type == type then
        Items.Take(state, item, 1)
        return
      end
    end
  end
  take(fit.hull)
  local hull = Ships.byId[fit.hull]
  local ship = Space.NewShip(state, hull.id, hull.name, "player", station)
  ship.corporate = true
  table.insert(events, { kind = "ShipAssembled", ship = ship.id, hull = hull.id })
  for _, module in fit.modules do
    take(module.type)
    Items.Equip(state, ship.id, module.type, nil)
  end
  return ship
end

-- What applying a doctrine to the fleet at a station would come to (and,
-- 'events' given, does): for each member of the fleet, the ship they
-- are given (one ready, or one put together); how many were given ships;
-- how many fly what their role is already; who could not be given one, and
-- why; and what there was not enough of in the corporation's hangar to
-- put the rest together, by type.
export type Outcome = { given: number, already: number, missed: { { name: string, why: string } }, short: { [string]: number } }
function Doctrines.Plan(state: State.State, doctrine: State.Doctrine, station: number, events: { Event }?): Outcome
  local outcome: Outcome = { given = 0, already = 0, missed = {}, short = {} }
  local taken: { [number]: boolean } = {}
  local stock = stockOf(state, station)
  for _, id in table.clone(state.fleetIds) do
    local wing = state.fleet[id]
    local member = if wing.member ~= 0 then state.membership.members[wing.member] else nil
    local role = Doctrines.RoleFor(doctrine, member)
    local fit = if role then state.fits[role.fit] else nil
    local flying = state.ships[wing.ship]
    if fit == nil then
      table.insert(outcome.missed, { name = wing.name, why = "its fit is no longer saved" })
    elseif flying and flying.corporate and Doctrines.Matches(state, flying, fit) then
      outcome.already += 1
      taken[flying.id] = true
    elseif (Fleet.GRADE[Ships.byId[fit.hull].class] or 1) > wing.skill and not (member and member.skills) then
      table.insert(outcome.missed, { name = wing.name, why = `grade {wing.skill} cannot fly a {Ships.byId[fit.hull].class}` })
    else
      local ship = ready(state, station, fit, if member then member.id else 0, taken)
      if ship == nil and draw(stock, fit, outcome.short) then
        -- (a ship to be put together: done, if this is the doctrine applied)
        ship = if events then assemble(state, station, fit, events) else nil
        if events == nil then
          outcome.given += 1
          continue
        end
      end
      if ship == nil then
        table.insert(outcome.missed, { name = wing.name, why = `no {fit.name} ready, and not the parts for one` })
      else
        taken[ship.id] = true
        local give: State.Command = { kind = "AssignShip", actor = state.player.ship, pilot = wing.id, target = ship.id }
        local ok, why = Fleet.Validate(state, give)
        if not ok then
          table.insert(outcome.missed, { name = wing.name, why = why or "cannot be given it" })
        else
          if events then
            Fleet.Apply(state, give, events)
          end
          outcome.given += 1
        end
      end
    end
  end
  return outcome
end

local function trimmed(name: string?): string
  return string.match(name or "", "^%s*(.-)%s*$") or ""
end

function Doctrines.Validate(state: State.State, command: State.Command): (boolean, string?)
  local kind = command.kind
  local ship = state.ships[command.actor]
  if not Corporation.Founded(state) then
    return false, "there is no corporation: found one first"
  elseif kind == "NewDoctrine" then
    local name = trimmed(command.name)
    if name == "" then
      return false, "give the doctrine a name"
    elseif #name > Doctrines.NAME then
      return false, `a name is {Doctrines.NAME} letters at most`
    elseif #Doctrines.List(state) >= Doctrines.MOST then
      return false, `{Doctrines.MOST} doctrines at most`
    end
    for _, doctrine in Doctrines.List(state) do
      if string.lower(doctrine.name) == string.lower(name) then
        return false, "there is a doctrine of that name"
      end
    end
    return true
  elseif kind == "SetDoctrineRole" then
    -- (a member set to a role by name, or "" for the first of any doctrine)
    local member = state.membership.members[command.target or 0]
    if member == nil then
      return false, "no such member"
    elseif #trimmed(command.name) > Doctrines.NAME then
      return false, `a name is {Doctrines.NAME} letters at most`
    end
    return true
  end
  local doctrine = Doctrines.Get(state, command.target or 0)
  if doctrine == nil then
    return false, "no such doctrine"
  elseif kind == "DeleteDoctrine" then
    return true
  elseif kind == "AddDoctrineRole" then
    local name = trimmed(command.name)
    local fit = state.fits[command.item or 0]
    if fit == nil then
      return false, "pick a saved fit for it"
    elseif name == "" then
      return false, "give the role a name"
    elseif #name > Doctrines.NAME then
      return false, `a name is {Doctrines.NAME} letters at most`
    elseif #doctrine.roles >= Doctrines.ROLES then
      return false, `{Doctrines.ROLES} roles at most`
    end
    for _, role in doctrine.roles do
      if string.lower(role.name) == string.lower(name) then
        return false, "it has a role of that name"
      end
    end
    return true
  elseif kind == "RemoveDoctrineRole" or kind == "MainDoctrineRole" then
    return doctrine.roles[command.quantity or 0] ~= nil, "no such role"
  end
  -- ApplyDoctrine
  if #doctrine.roles == 0 then
    return false, "it has no roles yet"
  elseif ship == nil or ship.docked == 0 then
    return false, "dock where the fleet's ships are to be had"
  elseif #state.fleetIds == 0 then
    return false, "nobody is in your fleet"
  end
  return true
end

function Doctrines.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  local doctrines = Doctrines.List(state)
  if kind == "NewDoctrine" then
    table.insert(doctrines, { id = State.NewId(state), name = trimmed(command.name), roles = {} })
    return
  elseif kind == "SetDoctrineRole" then
    local member = state.membership.members[command.target :: number]
    local name = trimmed(command.name)
    member.doctrineRole = if name ~= "" then name else nil
    return
  end
  local doctrine = Doctrines.Get(state, command.target :: number) :: State.Doctrine
  if kind == "DeleteDoctrine" then
    table.remove(doctrines, table.find(doctrines, doctrine) :: number)
  elseif kind == "AddDoctrineRole" then
    table.insert(doctrine.roles, { name = trimmed(command.name), fit = command.item :: number })
  elseif kind == "RemoveDoctrineRole" then
    table.remove(doctrine.roles, command.quantity :: number)
  elseif kind == "MainDoctrineRole" then
    local role = table.remove(doctrine.roles, command.quantity :: number) :: State.DoctrineRole
    table.insert(doctrine.roles, 1, role)
  else
    local station = state.ships[command.actor].docked
    local outcome = Doctrines.Plan(state, doctrine, station, events)
    local short: { string } = {}
    for type, count in outcome.short do
      table.insert(short, `{count} x {Types.Info(type).name}`)
    end
    table.sort(short)
    state.membership.fleetDoctrine = doctrine.id
    table.insert(events, { kind = "DoctrineApplied", doctrine = doctrine.id, name = doctrine.name, given = outcome.given,
      already = outcome.already, missed = #outcome.missed, short = table.concat(short, ", ") })
  end
end

return Doctrines
