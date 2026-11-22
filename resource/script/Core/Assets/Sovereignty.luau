--!strict
-- Sovereignty: an open system as the pilot's own.
--
-- The project owner's rulings (2026-11-14). A system is claimed with a
-- tower: a Claim Beacon anchored at one of the pilot's lit towers, in
-- an open system that nobody holds. After some hours unchallenged the
-- system is theirs, and stays so while a tower of theirs stands there,
-- lit, with a beacon. Holding it gives their name on it (it is on the
-- star map as theirs, and they can give it a name of their own), order
-- kept there (it is lawless no longer: Strategic/Wars), and a place in
-- the diplomacy: a faction that thinks badly of the pilot and holds
-- space next to it may declare on them and besiege it, as it would an
-- enemy's claim, and the siege is a front to fight at (Tactical/
-- Fronts). What a system's trade would pay its holder is for later.
--
-- A beacon speaks for the system it stands in from the first hour: no
-- faction begins a claim of its own there while it stands. (A faction
-- that has claimed a system already keeps it: taking a faction's claim
-- for the pilot is not built.)
--
-- The next steps (the project owner's go-ahead, the same day):
--
--   - The corporation declares its own wars and makes its own peace
--     (DeclareWar, ProposePeace). A war it declares makes the faction
--     its enemy at once, by what the faction thinks of the pilot; a
--     peace is heard once the war is a day old, and is a truce of two.
--   - A faction's claim can be taken: a claim beacon lit in a claim of a
--     faction the corporation is at war with begins a siege of the
--     pilot's own. Nothing is reckoned for it unseen: after its muster
--     the garrison is at the siege lines (Tactical/Fronts), with
--     whatever its holder sends to its relief, and the pilot and those
--     who fly for them have to bring it down to a fifth. Then, an hour
--     from when the beacon was lit at the soonest, the system is theirs.
--     With the beacon dark, or the war over, the siege is lifted.
--   - Hired pilots who are in a system of the pilot's when it is
--     besieged count toward its defence: so much each, with the tower.
--   - A system of the pilot's pays a levy: so much a day for the people
--     in it, to the corporation (or, with none founded, the pilot),
--     unless its lanes are shut.
--
-- First figures: six hours to claim, and twelve dark before a claim is
-- let go.

local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Members = require("@lt/Core/Assets/Members")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Wallet = require("@lt/Core/Assets/Wallet")
local Wars = require("@lt/Core/Strategic/Wars")

local Sovereignty = {}

export type Event = { [string]: any }

-- Ticks in an hour; the hours a beacon has to stand before the system
-- is its keeper's; and the hours a system of the pilot's can be without
-- one before it is let go.
Sovereignty.HOUR = math.ceil(3600 / Constants.TICK)
Sovereignty.CLAIM, Sovereignty.LAPSE = 6, 12
-- What the pilot's own siege is reckoned to have sent (themselves: it
-- is never the less for what happens unseen); what a hired pilot in the
-- system adds to the defence of a system of the pilot's; and the levy,
-- credits an hour for a unit of the people who live in a system.
Sovereignty.PERSONAL = 1000000
Sovereignty.POSTED = 30
Sovereignty.LEVY = 4000
-- So much more levy a level of the pilot's Stewardship (the owner, 2026-11-16, of the skills for structures and the corporation I put to them: "Yes to all your recs").
Sovereignty.STEWARDSHIP = 0.05
-- And what a system held pays for its trade, beside the levy (the owner,
-- 2026-11-16, of what a held system's trade should pay: "Both"): the
-- sales tax on what its markets sell its people, at the rate a market
-- charges (Assets/Market), and dues on what is carried in and out along
-- its lanes, a share of its worth. (The share mine.)
Sovereignty.SALES_TAX = 0.02
Sovereignty.DUES = 0.005
Sovereignty.DAY = 24 * Sovereignty.HOUR

-- The systems in which the pilot has a lit tower with a claim beacon
-- online.
local function beacons(state: State.State): { [number]: boolean }
  local lit: { [number]: boolean } = {}
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    if starbase.owner == Wars.PILOT and Starbases.Has(state, starbase, "claim") then
      lit[Space.SystemOf(state, id)] = true
    end
  end
  return lit
end

-- How a system stands for the pilot: "held" (theirs), "claiming" (a
-- beacon of theirs is up, with the hours it has stood and the hours it
-- takes), "contested" (a beacon is up, and something is being done to
-- the system by somebody else, or it is somebody's already), or "none".
function Sovereignty.Status(state: State.State, system: number): (string, number, number)
  local node = state.galaxy.systems[system]
  if node == nil then
    return "none", 0, Sovereignty.CLAIM
  elseif node.owner == Wars.PILOT then
    return "held", state.sovereignty.dark[system] or 0, Sovereignty.LAPSE
  elseif not beacons(state)[system] then
    return "none", 0, Sovereignty.CLAIM
  elseif node.owner ~= "" or node.uncharted then
    return "contested", 0, Sovereignty.CLAIM
  end
  return "claiming", state.sovereignty.progress[system] or 0, Sovereignty.CLAIM
end

-- Once a tick; it does something once an hour. A beacon in an open
-- system that nobody holds, and that nobody is doing anything to, has
-- stood an hour more, and when it has stood long enough the system is
-- the pilot's. A system of the pilot's with no beacon lit in it has
-- been dark an hour more, and is let go when it has been dark too long.
function Sovereignty.Step(state: State.State, events: { Event })
  local sovereignty = state.sovereignty
  local lit = beacons(state)
  -- (what the pilot's beacon stands in is spoken for, from the tick it
  -- is lit: no faction begins a claim of it, and one that was only
  -- mustering for it calls that off. Strategic/Wars)
  local spoken: { [number]: boolean } = {}
  for system in lit do
    if state.galaxy.systems[system].owner == "" then
      spoken[system] = true
    end
  end
  state.wars.spoken = spoken
  -- Once a round of the wars: the pilot's own sieges, begun and lifted,
  -- and who of theirs stands with a system of theirs that is besieged.
  if state.tick % Wars.ROUND == 0 and state.tick > 0 and state.wars.on then
    local wars = state.wars
    local at: { [number]: State.Operation } = {}
    for _, operation in wars.operations do
      at[operation.system] = operation
    end
    for system in lit do
      local holder = wars.claims[system]
      if holder and holder ~= Wars.PILOT and at[system] == nil and Wars.AtWar(wars, Wars.PILOT, holder) then
        local operation: State.Operation = { id = Wars.OperationId(wars, state.tick), by = Wars.PILOT, system = system, kind = "siege", began = state.tick,
          force = Sovereignty.PERSONAL, sent = Sovereignty.PERSONAL, against = holder, defence = Wars.GARRISON, defended = Wars.GARRISON,
          stage = "muster", relieved = false }
        table.insert(wars.operations, operation)
        table.insert(events, { kind = "OperationBegan", system = system, by = Wars.PILOT, against = holder, what = "siege" })
      end
    end
    for index = #wars.operations, 1, -1 do
      local operation = wars.operations[index]
      if operation.by == Wars.PILOT and not lit[operation.system] then
        -- (the beacon is dark, or gone: the siege is lifted)
        table.remove(wars.operations, index)
        table.insert(events, { kind = "OperationOver", system = operation.system, by = Wars.PILOT, against = operation.against,
          how = "called off" })
      elseif operation.against == Wars.PILOT and operation.stage ~= "muster" and not operation.relieved then
        local posted = 0
        for _, id in state.fleetIds do
          local ball = state.balls[state.fleet[id].ship]
          posted += if ball and ball.system == operation.system then 1 else 0
        end
        -- (and the corporation's members who fight, and are working there: Assets/Members)
        local _, stands = Members.Watching(state, operation.system)
        local force = posted * Sovereignty.POSTED + stands
        operation.relieved = true
        if force > 0 then
          operation.defence += force
          operation.defended += force
          table.insert(events, { kind = "ReliefSent", system = operation.system, by = Wars.PILOT, against = operation.by, force = force })
        end
      end
    end
  end
  -- Once a day: what the pilot's systems pay.
  if state.tick % Sovereignty.DAY == 0 and state.tick > 0 then
    local shut = Wars.Blocked(state.wars)
    local levy, paying, tax, dues = 0, 0, 0, 0
    for id = 1, Galaxy.Charted(state.galaxy) do
      local node = state.commerce.nodes[id]
      if state.galaxy.systems[id].owner == Wars.PILOT and node and not shut[id] then
        levy += math.floor(Sovereignty.LEVY * node.population * 24 * (1 + Sovereignty.STEWARDSHIP * math.max(0, state.skills.stewardship or 0)))
        tax += math.floor(Sovereignty.SALES_TAX * (node.sales or 0))
        dues += math.floor(Sovereignty.DUES * (node.through or 0))
        paying += 1
      end
      -- (a day's trade is read once: the next day's is counted afresh)
      if node then
        node.sales, node.through = 0, 0
      end
    end
    local function earn(amount: number, reason: string)
      if amount <= 0 then
        return
      elseif Corporation.Founded(state) then
        Corporation.Earn(state, amount, reason, events)
      else
        Wallet.Pay(state, amount, reason, events)
      end
    end
    earn(levy, "levy")
    earn(tax, "sales tax")
    earn(dues, "transit dues")
    if levy > 0 or tax > 0 or dues > 0 then
      table.insert(events, { kind = "LevyPaid", amount = levy, tax = tax, dues = dues, systems = paying })
    end
  end
  if state.tick % Sovereignty.HOUR ~= 0 or state.tick == 0 then
    return
  end
  local busy = Wars.Blocked(state.wars)
  for system in lit do
    local node = state.galaxy.systems[system]
    if node.owner == "" and not node.uncharted and not node.home and not busy[system] then
      local stood = (sovereignty.progress[system] or 0) + 1
      if stood >= Sovereignty.CLAIM then
        sovereignty.progress[system] = nil
        Wars.Take(state.galaxy, state.wars, system, Wars.PILOT)
        table.insert(events, { kind = "SystemTaken", system = system, by = Wars.PILOT, from = "" })
      else
        sovereignty.progress[system] = stood
      end
    end
  end
  for system in sovereignty.progress do
    if not lit[system] then
      sovereignty.progress[system] = nil
    end
  end
  for id = 1, Galaxy.Charted(state.galaxy) do
    if state.galaxy.systems[id].owner == Wars.PILOT then
      if lit[id] then
        sovereignty.dark[id] = nil
      else
        local dark = (sovereignty.dark[id] or 0) + 1
        if dark >= Sovereignty.LAPSE then
          sovereignty.dark[id] = nil
          Wars.Take(state.galaxy, state.wars, id, "")
          table.insert(events, { kind = "ClaimLapsed", system = id, by = Wars.PILOT })
        else
          sovereignty.dark[id] = dark
        end
      end
    elseif sovereignty.dark[id] then
      sovereignty.dark[id] = nil
    end
  end
end

function Sovereignty.Validate(state: State.State, command: State.Command): (boolean, string?)
  if command.kind == "DeclareWar" or command.kind == "ProposePeace" then
    local faction = command.what or ""
    if Factions.byId[faction] == nil or table.find(Galaxy.Holders(state.galaxy), faction) == nil then
      return false, "nobody of that name holds space"
    elseif not state.wars.on then
      return false, "nobody stirs in this galaxy"
    elseif not Corporation.Founded(state) then
      return false, "a war is a corporation's to declare: found one first"
    end
    local feud = Wars.Feud(state.wars, Wars.PILOT, faction)
    if command.kind == "DeclareWar" then
      if feud then
        return false, "you are at war with them already"
      elseif Wars.Truce(state.wars, Wars.PILOT, faction) then
        return false, "there is a truce between you"
      end
      return true
    elseif feud == nil then
      return false, "you are not at war with them"
    elseif state.tick - feud.since < Wars.LEAST then
      return false, `they will not hear of it yet: {math.ceil((Wars.LEAST - (state.tick - feud.since)) / Sovereignty.HOUR)} hours more`
    end
    return true
  elseif command.kind ~= "RenameSystem" then
    return false, `unknown command '{command.kind}'`
  end
  local node = state.galaxy.systems[command.target or 0]
  if node == nil or node.owner ~= Wars.PILOT then
    return false, "that system is not yours to name"
  end
  -- (a name as a marked place's is: letters, figures and spaces, and not too long)
  local name, why = Space.PlaceName(command.what or "")
  if name == nil then
    return false, why
  end
  for id = 1, #state.galaxy.systems do
    if state.galaxy.systems[id].name == name and id ~= node.id then
      return false, "another system has that name"
    end
  end
  return true
end

function Sovereignty.Apply(state: State.State, command: State.Command, events: { Event })
  if command.kind == "DeclareWar" then
    local faction = command.what :: string
    Wars.Declare(state.wars, Wars.PILOT, faction, state.tick)
    -- (they are the pilot's enemies from now, whatever they thought before)
    state.standings[faction] = math.min(Standings.Of(state, faction), Standings.HOSTILE - 1)
    table.insert(events, { kind = "WarDeclared", by = Wars.PILOT, on = faction })
    return
  elseif command.kind == "ProposePeace" then
    local faction = command.what :: string
    local feud = Wars.Settle(state.wars, Wars.PILOT, faction, state.tick)
    -- (and they think no worse of the pilot than of anybody they are not at war with)
    state.standings[faction] = math.max(Standings.Of(state, faction), Standings.HOSTILE + 1)
    table.insert(events, { kind = "PeaceMade", a = faction, b = Wars.PILOT, score = if feud then feud.score else 0,
      hours = if feud then (state.tick - feud.since) // Sovereignty.HOUR else 0, winner = "", paid = 0, ceded = 0 })
    return
  end
  local node = state.galaxy.systems[command.target :: number]
  local was = node.name
  node.name = Space.PlaceName(command.what or "") :: string
  -- (what has been described of it goes by the new name too)
  local described = state.systems[node.id]
  if described then
    described.name = node.name
  end
  table.insert(events, { kind = "SystemRenamed", system = node.id, name = node.name, was = was })
end

return Sovereignty
