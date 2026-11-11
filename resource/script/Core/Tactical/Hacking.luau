--!strict
-- Hacking: getting into the sealed hold of a derelict.
--
-- A derelict's hull (Tactical/Sites) has its hold sealed: it is not
-- looted until it has been hacked, by a ship with a Data Analyzer
-- fitted, from within five kilometres.
--
-- A hack is a board of nodes, six by five, nearly all of them hidden.
-- The pilot's way in begins at a node on one edge, and somewhere on the
-- board is the core: destroy that and the hold is open. A node can be
-- tried if it is next to one already cleared. What is found there:
--   - nothing, which clears it, and it then says how many steps off
--     the core is;
--   - a repair node, which clears and gives back some coherence;
--   - a firewall, or the core itself: it has to be attacked, a blow at
--     a time. Each blow takes the pilot's strength off it; if it is
--     still standing it answers, and takes its own strength off the
--     pilot's coherence. (So does the way past a firewall stay shut
--     until it is down.)
-- With the core destroyed the hold is open. With the pilot's coherence
-- gone, the hold's safeguards fire: it opens, with half of everything
-- in it burnt. A hack can be given up, and is dropped if the ship goes
-- a kilometre out of the analyzer's reach; the board is the same next time.
--
-- (EVE's hacking, cut down. Not yet: other kinds of node, utilities to
-- pick up and use, a second kind of lock.)

local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Hacking = {}

export type Event = { [string]: any }

Hacking.WIDTH, Hacking.HEIGHT = 6, 5
Hacking.LEASH = 1000        -- m: how much farther off than it began before the hack is dropped
Hacking.ANALYZER = "analyzer.data"
-- (What a board is made of is set against how often a pilot wins it:
-- the spec plays three hundred boards a level, carefully, and holds a
-- pilot new to it to about half of them and a practised one to nearly
-- all. A core is 60 to 110 strong, a board to a board.)
local FIREWALLS, REPAIRS = 10, 2
local REPAIR = 25
local CORE_HP, CORE_SPREAD, CORE_STRENGTH = 60, 6, 20

-- The pilot's coherence and strength at the start of a hack: more of
-- each for every level of the Hacking skill.
function Hacking.Virus(state: State.State): (number, number)
  local level = math.max(0, state.skills.hacking or 0)
  return 60 + 10 * level, 20 + 5 * level
end

-- The board a hull's lock is: the same every time it is asked for.
local function board(state: State.State, wreck: number): ({ State.HackNode }, number)
  local rng = Rng.For(state.historySeed, wreck, 61)
  local count = Hacking.WIDTH * Hacking.HEIGHT
  local nodes: { State.HackNode } = {}
  for index = 1, count do
    nodes[index] = { kind = "empty", hp = 0, strength = 0, seen = false, cleared = false }
  end
  -- (the way in: the middle of the first column. The core: somewhere in the last.)
  local start = (Hacking.HEIGHT // 2) * Hacking.WIDTH + 1
  local core = Rng.Int(rng, Hacking.HEIGHT) * Hacking.WIDTH + Hacking.WIDTH
  nodes[core].kind, nodes[core].hp, nodes[core].strength = "core", CORE_HP + 10 * Rng.Int(rng, CORE_SPREAD), CORE_STRENGTH
  local function place(kind: string, hp: number, strength: number)
    for _ = 1, 40 do
      local at = Rng.Int(rng, count) + 1
      if at ~= start and nodes[at].kind == "empty" then
        nodes[at].kind, nodes[at].hp, nodes[at].strength = kind, hp, strength
        return
      end
    end
  end
  for _ = 1, FIREWALLS do
    place("firewall", 30 + 10 * Rng.Int(rng, 4), 10 + 5 * Rng.Int(rng, 3))
  end
  for _ = 1, REPAIRS do
    place("repair", 0, 0)
  end
  nodes[start].seen, nodes[start].cleared = true, true
  return nodes, start
end

-- The nodes next to one, by their places on the board.
function Hacking.Beside(index: number): { number }
  local column, row = (index - 1) % Hacking.WIDTH, (index - 1) // Hacking.WIDTH
  local found: { number } = {}
  if column > 0 then
    table.insert(found, index - 1)
  end
  if column < Hacking.WIDTH - 1 then
    table.insert(found, index + 1)
  end
  if row > 0 then
    table.insert(found, index - Hacking.WIDTH)
  end
  if row < Hacking.HEIGHT - 1 then
    table.insert(found, index + Hacking.WIDTH)
  end
  return found
end

-- Whether a node can be tried: it is not cleared, and is next to one
-- that is.
function Hacking.Open(hack: State.Hack, index: number): boolean
  local node = hack.nodes[index]
  if node == nil or node.cleared then
    return false
  end
  for _, beside in Hacking.Beside(index) do
    if hack.nodes[beside].cleared then
      return true
    end
  end
  return false
end

-- How many steps a node is from the core.
function Hacking.Steps(hack: State.Hack, index: number): number
  for at, node in hack.nodes do
    if node.kind == "core" then
      return math.abs((at - 1) % Hacking.WIDTH - (index - 1) % Hacking.WIDTH)
        + math.abs((at - 1) // Hacking.WIDTH - (index - 1) // Hacking.WIDTH)
    end
  end
  return 0
end

-- How far the ship's analyzer reaches (the best fitted); 0 with none.
function Hacking.Reach(state: State.State, ship: number): number
  local reach = 0
  for _, item in Items.Fitted(state, ship) do
    local analyzer = Modules.byId[item.type].analyzer
    if analyzer then
      reach = math.max(reach, analyzer.range)
    end
  end
  return reach
end

function Hacking.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local ball = state.balls[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  local kind = command.kind
  if kind == "StartHack" then
    local wreck = state.wrecks[command.target or 0]
    if wreck == nil then
      return false, "not a wreck"
    elseif not wreck.locked then
      return false, "its hold is not sealed"
    elseif state.hack then
      return false, "a hack is under way already"
    end
    local reach = Hacking.Reach(state, ship.id)
    if reach <= 0 then
      return false, `needs a {Modules.byId[Hacking.ANALYZER].name} fitted`
    elseif wreck.system ~= ball.system or Space.Gap(ball :: any, wreck :: any) > reach then
      return false, "too far away"
    end
    return true
  end
  local hack = state.hack
  if hack == nil then
    return false, "no hack is under way"
  elseif kind == "AbandonHack" then
    return true
  elseif kind == "HackNode" then
    if not Hacking.Open(hack, command.pin or 0) then
      return false, "that node cannot be reached yet"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- The hack is over: the hold is open; and if it was lost, half of what
-- was in it is burnt.
local function finish(state: State.State, hack: State.Hack, won: boolean, events: { Event })
  local wreck = state.wrecks[hack.wreck]
  if wreck then
    wreck.locked = false
    if not won then
      for _, item in Items.In(state, wreck.id, "cargo") do
        Items.Take(state, item, math.ceil(item.quantity / 2))
      end
    end
  end
  state.hack = nil
  table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = won, reason = if won then "core destroyed" else "coherence lost" })
end

function Hacking.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  if kind == "StartHack" then
    local nodes, start = board(state, command.target :: number)
    local coherence, strength = Hacking.Virus(state)
    state.hack = { wreck = command.target :: number, width = Hacking.WIDTH, height = Hacking.HEIGHT, nodes = nodes,
      coherence = coherence, most = coherence, strength = strength, start = start }
    table.insert(events, { kind = "HackStarted", wreck = command.target })
    return
  end
  local hack = state.hack :: State.Hack
  if kind == "AbandonHack" then
    state.hack = nil
    table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = false, reason = "given up" })
    return
  end
  local node = hack.nodes[command.pin :: number]
  if not node.seen then
    -- Found: nothing and a repair node clear at once; anything that
    -- fights back only shows itself.
    node.seen = true
    if node.kind == "empty" then
      node.cleared = true
    elseif node.kind == "repair" then
      node.cleared = true
      hack.coherence = math.min(hack.most, hack.coherence + REPAIR)
    end
    return
  end
  -- A blow at it; and its answer, if it is still standing.
  node.hp -= hack.strength
  if node.hp <= 0 then
    node.hp = 0
    node.cleared = true
    if node.kind == "core" then
      finish(state, hack, true, events)
    end
    return
  end
  hack.coherence -= node.strength
  if hack.coherence <= 0 then
    hack.coherence = 0
    finish(state, hack, false, events)
  end
end

-- Once a tick: a hack whose ship has gone off, or whose hull has, is
-- dropped.
function Hacking.Step(state: State.State, events: { Event })
  local hack = state.hack
  if hack == nil then
    return
  end
  local wreck = state.wrecks[hack.wreck]
  local ball = state.balls[state.player.ship]
  local reach = Hacking.Reach(state, state.player.ship)
  if wreck == nil or ball == nil or ball.system ~= wreck.system or reach <= 0
    or Space.Gap(ball :: any, wreck :: any) > reach + Hacking.LEASH then
    state.hack = nil
    table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = false, reason = "out of reach" })
  end
end

return Hacking
