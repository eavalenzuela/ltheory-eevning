--!strict
-- Saved fittings (the owner, 2026-11-18: "need saved fittings in the
-- fitting window (new tab, next to fitting and appearance)"): a ship's
-- fit kept under a name, for its hull, to be put on another of the same
-- hull, or this one again, at any station with a fitting service.
--
-- Loading one takes off what is fitted (into the hangar, its charges
-- with it) and fits what of the saved fit is at hand there, in its
-- order, loading the charges it had where they are at hand too. What is
-- not at hand is said (the owner, the same day: "Fit what you have +
-- buy rest": the fitting window offers to buy what is missing on the
-- station's market first, Game/UI/Fitting). Rigs are never taken off,
-- since a rig taken off is destroyed: a saved rig goes into an empty rig
-- slot, if there is one and the rig is at hand.

local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local SavedFits = {}

export type Event = { [string]: any }

SavedFits.COMMANDS = { SaveFit = true, DeleteFit = true, LoadFit = true }
-- How many fits are kept, and how long a name is at most.
SavedFits.MOST = 200
SavedFits.NAME = 40

-- The fits kept for a hull, by name.
function SavedFits.For(state: State.State, hull: string): { State.SavedFit }
  local out: { State.SavedFit } = {}
  for _, id in state.fitIds do
    local fit = state.fits[id]
    if fit.hull == hull then
      table.insert(out, fit)
    end
  end
  table.sort(out, function(a: State.SavedFit, b: State.SavedFit): boolean
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.id < b.id
  end)
  return out
end

-- What of a fit is not at hand for a ship where it is docked: each
-- module type, with how many it wants and how many there are (in the
-- hangar here, and fitted to the ship now, which comes off into it).
-- Rigs already fitted count for themselves.
function SavedFits.Missing(state: State.State, ship: number, fit: State.SavedFit): { { type: string, want: number, have: number } }
  local record = state.ships[ship]
  local here: { [string]: number } = {}
  if record and record.docked ~= 0 then
    for _, item in Items.In(state, record.docked, "hangar") do
      here[item.type] = (here[item.type] or 0) + item.quantity
    end
  end
  for _, item in Items.Fitted(state, ship) do
    here[item.type] = (here[item.type] or 0) + 1
  end
  local want: { [string]: number } = {}
  local order: { string } = {}
  for _, entry in fit.modules do
    if want[entry.type] == nil then
      table.insert(order, entry.type)
    end
    want[entry.type] = (want[entry.type] or 0) + 1
  end
  local out: { { type: string, want: number, have: number } } = {}
  for _, type in order do
    if (here[type] or 0) < want[type] then
      table.insert(out, { type = type, want = want[type], have = here[type] or 0 })
    end
  end
  return out
end

local function trimmed(name: string?): string
  return string.match(name or "", "^%s*(.-)%s*$") or ""
end

function SavedFits.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  if command.kind == "SaveFit" then
    local name = trimmed(command.name)
    if name == "" then
      return false, "give the fit a name"
    elseif #name > SavedFits.NAME then
      return false, `a name is {SavedFits.NAME} letters at most`
    elseif #state.fitIds >= SavedFits.MOST then
      return false, `{SavedFits.MOST} fits are kept at most: delete one first`
    elseif #Items.Fitted(state, ship.id) == 0 then
      return false, "nothing is fitted to save"
    end
    return true
  end
  local fit = state.fits[command.target or 0]
  if fit == nil then
    return false, "no such fit"
  end
  if command.kind == "DeleteFit" then
    return true
  elseif command.kind == "LoadFit" then
    if ship.docked == 0 then
      return false, "a fit is put on docked"
    elseif fit.hull ~= ship.type then
      return false, `that is a fit for a {Ships.byId[fit.hull] and Ships.byId[fit.hull].name or fit.hull}`
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

-- Do a fitting command as the pilot would, if it may be done.
local function try(state: State.State, command: State.Command, events: { Event }): boolean
  if Items.Validate(state, command) then
    Items.Apply(state, command, events)
    return true
  end
  return false
end

function SavedFits.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "SaveFit" then
    local modules: { State.FitModule } = {}
    for _, item in Items.Fitted(state, ship.id) do
      table.insert(modules, { type = item.type, charge = item.charge })
    end
    -- (a fit of the same name for the same hull is written over)
    local name = trimmed(command.name)
    for _, id in state.fitIds do
      local old = state.fits[id]
      if old.hull == ship.type and old.name == name then
        old.modules = modules
        table.insert(events, { kind = "FitSaved", fit = id, name = name })
        return
      end
    end
    local fit: State.SavedFit = { id = State.NewId(state), name = name, hull = ship.type, modules = modules }
    state.fits[fit.id] = fit
    table.insert(state.fitIds, fit.id)
    table.insert(events, { kind = "FitSaved", fit = fit.id, name = name })
    return
  end
  local fit = state.fits[command.target :: number]
  if command.kind == "DeleteFit" then
    state.fits[fit.id] = nil
    State.RemoveId(state.fitIds, fit.id)
    table.insert(events, { kind = "FitDeleted", fit = fit.id, name = fit.name })
    return
  end
  -- Load: off with what is fitted (but rigs), then on with the fit.
  local station = ship.docked
  for _, item in Items.Fitted(state, ship.id) do
    if Modules.byId[item.type] == nil or Modules.byId[item.type].slot ~= "rig" then
      try(state, { kind = "Unfit", actor = ship.id, item = item.id }, events)
    end
  end
  local rigs: { [string]: number } = {}
  for _, item in Items.Fitted(state, ship.id) do
    rigs[item.type] = (rigs[item.type] or 0) + 1
  end
  local missing: { string } = {}
  for _, entry in fit.modules do
    local module = Modules.byId[entry.type]
    if module and module.slot == "rig" and (rigs[entry.type] or 0) > 0 then
      rigs[entry.type] -= 1
      continue
    end
    local stack: State.Item? = nil
    for _, item in Items.In(state, station, "hangar") do
      if stack == nil and item.type == entry.type then
        stack = item
      end
    end
    local fitted = false
    if stack then
      local before = #Items.Fitted(state, ship.id)
      fitted = try(state, { kind = "Fit", actor = ship.id, item = stack.id }, events) and #Items.Fitted(state, ship.id) > before
    end
    if not fitted then
      table.insert(missing, entry.type)
    elseif entry.charge ~= "" then
      -- (the weapon just fitted is the newest of its type)
      local weapon: State.Item? = nil
      for _, item in Items.Fitted(state, ship.id) do
        if item.type == entry.type and item.charge == "" and (weapon == nil or item.id > (weapon :: State.Item).id) then
          weapon = item
        end
      end
      local charge: State.Item? = nil
      for _, item in Items.In(state, station, "hangar") do
        if charge == nil and item.type == entry.charge then
          charge = item
        end
      end
      if weapon and charge then
        try(state, { kind = "LoadCharge", actor = ship.id, item = weapon.id, other = charge.id }, events)
      end
    end
  end
  local names: { string } = {}
  for _, type in missing do
    table.insert(names, Types.Info(type).name)
  end
  table.insert(events, { kind = "FitLoaded", fit = fit.id, name = fit.name, missing = missing, said = table.concat(names, ", ") })
end

return SavedFits
