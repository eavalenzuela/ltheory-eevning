--!strict
-- Careers: the agents who show a new pilot the ropes.
--
-- At the station a new pilot starts at there are seven agents, one for
-- each way of making a living: flying, industry, trade, fighting,
-- surveying, command (drones, and pilots who fly for you) and planets
-- (a colony, and what it makes). Each has a short run of lessons, to be
-- done in order. A
-- lesson is one thing to do, said plainly. What it needs is handed over
-- when it is taken (into the station's hangar); when it is done the
-- pilot reports back to the agent, docked there, and is paid: some
-- credits, often something to use in the next lesson, and at the end of
-- a career something worth having (a mining frigate, a combat frigate
-- of the faction's, a cloak).
--
-- A lesson is done by doing the thing while the lesson is in hand. It is
-- the Core's own events that are counted, as the guide's steps are
-- (Character/Guide), so what was done before the lesson was taken does
-- not count; except where the lesson is to have something (a skill at a
-- level) or to bring something. A lesson does not lapse, cannot be
-- failed and costs nothing to leave alone, and one from each agent can
-- be in hand at once.
--
-- Two of the surveying lessons want something to find, and the agent
-- sees to it: while one is in hand there is a hidden belt, or a derelict
-- with a sealed hold, in the agents' system (Tactical/Sites).
--
-- Finishing a lesson raises the pilot's standing a little with the
-- faction whose station it is.

local Items = require("@lt/Core/Assets/Items")
local Missions = require("@lt/Core/Assets/Missions")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Careers = {}

export type Event = { [string]: any }
export type Stack = { type: string, quantity: number }

-- A lesson. What does it is one of three things: so many of an event
-- ('on', which has to be the pilot's own ship's where 'mine' names the
-- field that says whose it is, and has to pass 'also'; each counts for
-- one, or for what 'worth' says); a skill at a level; or something
-- brought, which is handed over.
export type Lesson = {
  title: string,
  aim: string,          -- what is to be done, in a few words
  says: string,         -- what the agent says of it
  kit: { Stack },       -- handed over when it is taken
  on: string,
  mine: string?,
  also: ((event: Event, state: State.State) -> boolean)?,
  worth: ((event: Event) -> number)?,
  need: number,
  skill: { id: string, level: number }?,
  bring: Stack?,
  site: string?,        -- the kind of site there is to be for it
  credits: number,      -- what is paid for it
  gifts: { Stack },     -- and given
  frigate: boolean?,    -- and the faction's combat frigate with them
}

export type Career = { id: string, name: string, about: string, lessons: { Lesson } }

-- Standing gained with the station's faction for a lesson.
Careers.STANDING = 0.05
-- Ticks between one look and the next at whether a lesson's site is
-- still there to be found.
Careers.CHECK = 600

-- The station the agents are at: where a new pilot starts.
function Careers.Station(state: State.State): number
  return Stations.Starter(state)
end

local function elsewhere(_event: Event, state: State.State): boolean
  local ship = state.ships[state.player.ship]
  return ship ~= nil and ship.docked ~= 0 and ship.docked ~= Careers.Station(state)
end

Careers.list = {
  {
    id = "flight", name = "Flight school", about = "Getting about: warping, marking places, gates, other stations.",
    lessons = {
      { title = "Out and back", aim = "Warp somewhere", on = "WarpEnded", mine = "ball", need = 1, kit = {}, credits = 2000, gifts = {},
        says = "Undock, pick any place on the overview and warp to it (S). When the warp ends, pick this station and dock (D). "
          .. "That is most of what flying is." },
      { title = "A place of your own", aim = "Mark a place in space", on = "Bookmarked", need = 1, kit = {}, credits = 2500,
        gifts = { { type = "nanofiber", quantity = 1 } },
        says = "Mark, at the top of the overview, keeps the spot your ship is at. It is on the overview from then on, to warp "
          .. "back to: a quiet corner of a belt, a way out of trouble." },
      { title = "Next door", aim = "Jump to another system, and back", on = "Jumped", mine = "ship", need = 2, kit = {}, credits = 5000,
        gifts = { { type = "overdrive", quantity = 1 } },
        says = "Pick a stargate on the overview and jump (D): the ship warps to it first. Then come back the same way. "
          .. "The map (M) plans longer ways, and the autopilot flies them." },
      { title = "Another harbour", aim = "Dock at another station", on = "Docked", mine = "ship", need = 1, kit = {}, credits = 8000,
        also = function(event: Event, state: State.State): boolean
          return event.station ~= Careers.Station(state)
        end,
        gifts = { { type = "book.evasive.maneuvering", quantity = 1 } },
        says = "Dock somewhere that is not here. Every station keeps its own market and its own agents, and what is cheap "
          .. "at one is dear at another." },
    },
  },
  {
    id = "industry", name = "Industry", about = "Making things: mining, refining, building from blueprints.",
    lessons = {
      { title = "Rock to ore", aim = "Mine 400 units of ore", on = "Mined", mine = "ball", need = 400, credits = 3000, gifts = {},
        worth = function(event: Event): number
          return event.units
        end,
        kit = { { type = "miner.small", quantity = 1 } },
        says = "Fit this Mining Laser (Fitting tab: a gun can come out to make room; then right-click the laser in the "
          .. "inventory's hangar, Fit). At a belt, lock a rock (L) and switch "
          .. "the laser on. The ore comes into the hold a load a minute." },
      { title = "Ore to minerals", aim = "Refine ore", on = "Reprocessed", mine = "ship", need = 1, kit = {}, credits = 3000, gifts = {},
        says = "Ore is bulky and cheap. Refined, it is the minerals everything is built from. Industry tab, here: refine "
          .. "what you mined." },
      { title = "Minerals to goods", aim = "Build something from a blueprint", on = "JobDone", need = 1, kit = {}, credits = 5000,
        gifts = { { type = "blueprint.miner.small", quantity = 1 } },
        says = "Your hangar has a blueprint for rounds. Industry tab: pick it, see what minerals it wants, and start the job. "
          .. "It takes a little while: come back when it is done." },
      { title = "An order to fill", aim = "Bring 1,000 Ferrite", on = "", need = 0, kit = {}, credits = 12000, gifts = {},
        bring = { type = "ore.ferrite", quantity = 1000 },
        says = "A yard here wants a thousand units of Ferrite, and I said you would bring it. It is the commonest rock in "
          .. "these belts. Have it in your hold or in the hangar here when you report." },
      -- (a second laser since 2026-11-18, when the Prospector it gave was taken out of the game with the other hulls
      -- nobody's yards built: Data/Ships)
      { title = "Two lasers to the work", aim = "Train Mining to level 2", on = "", need = 1, kit = {}, credits = 10000,
        skill = { id = "mining", level = 2 },
        gifts = { { type = "miner.small", quantity = 1 } },
        says = "Two mining lasers cut twice the rock. Train Mining to level 2 (Skills tab; a few minutes, and it goes on "
          .. "while you do other things), and there is a second laser here for you: fit it beside the first." },
    },
  },
  {
    id = "trade", name = "Commerce", about = "Buying and selling: the market, orders, a station's jobs.",
    lessons = {
      { title = "Something to sell", aim = "Sell something on the market", on = "Sold", need = 1, kit = {}, credits = 2000, gifts = {},
        says = "Market tab: pick something you have, and sell it. You have rounds and ore, if nothing else. What the "
          .. "station pays is the price shown, less a tax." },
      { title = "A standing order", aim = "Place an order on the market", on = "OrderPlaced", need = 1, kit = {}, credits = 3000,
        gifts = { { type = "book.broker.relations", quantity = 1 } },
        says = "Selling at once takes what the station pays. An order asks more and waits for a buyer: set a price above "
          .. "the station's and place it. An order costs a broker's fee, and can be taken back." },
      { title = "Work for the station", aim = "Finish a job from the Missions tab", on = "MissionCompleted", need = 1, kit = {},
        credits = 6000, gifts = { { type = "cargo.expander", quantity = 1 } },
        says = "The Missions tab has what the station wants done today. A courier run or a supply order is a trader's "
          .. "work: take one and see it through. It pays, and the faction remembers." },
      { title = "Buy here, sell there", aim = "Sell something at another station", on = "Sold", need = 1, kit = {}, credits = 15000,
        also = elsewhere,
        gifts = { { type = "book.accounting", quantity = 1 }, { type = "cargo.expander", quantity = 1 } },
        says = "Prices differ from station to station, and the market shows what each pays. Carry something to another "
          .. "station and sell it there. Minerals and components travel well." },
    },
  },
  {
    id = "combat", name = "Enforcement", about = "Fighting: fitting a ship, pirates, wrecks and what is in them.",
    lessons = {
      { title = "Fit for it", aim = "Fit a module", on = "Fitted", need = 1, kit = {}, credits = 2000,
        gifts = { { type = "ammo.emp", quantity = 500 } },
        says = "A ship is what is fitted to it. In the inventory, right-click the Small Shield Extender in your hangar and "
          .. "Fit: it goes into a free mid slot. If it is in already, take it out (Fitting tab) and put it back: I want to "
          .. "see that you can." },
      { title = "First pirate", aim = "Destroy a pirate", on = "WalletChanged", need = 1, kit = {}, credits = 6000,
        also = function(event: Event): boolean
          return event.reason == "bounty"
        end,
        gifts = { { type = "shield.booster.small", quantity = 1 } },
        says = "Pirates come to the belts. Warp to one and wait. <next> picks a pirate out, <lock> locks it, <rack1> and <rack2> fire. Orbit "
          .. "it (W) while you shoot: a moving ship is harder to hit. If your shield goes, warp out." },
      { title = "What they leave", aim = "Loot a wreck", on = "Looted", mine = "ship", need = 1, kit = {}, credits = 4000,
        gifts = { { type = "book.salvaging", quantity = 1 }, { type = "salvager.small", quantity = 1 } },
        says = "A destroyed ship leaves a wreck, and what it carried is in it. Approach the wreck (<approach>) and Loot: it "
          .. "opens in the inventory, and Loot all takes it. Pirate "
          .. "tags sell, and so does the rest." },
      { title = "Nothing wasted", aim = "Salvage a wreck", on = "Salvaged", mine = "ball", need = 1, kit = {}, credits = 6000,
        gifts = { { type = "armor.plate.200mm", quantity = 1 } },
        says = "Learn Salvaging from the book I gave you and train it to level 1 (Skills tab: three minutes). Fit the "
          .. "Salvager, lock a wreck and run it. The pieces it brings off build rigs, and sell well." },
      { title = "A patrol", aim = "Destroy 5 pirates", on = "WalletChanged", need = 5, kit = {}, credits = 20000, gifts = {},
        also = function(event: Event): boolean
          return event.reason == "bounty"
        end,
        frigate = true,
        says = "Five more pirates, and you are no longer new at this. A bounty job from the Missions tab pays for the same "
          .. "kills twice. There is another frigate of ours here for you when it is done: a second hull is a ship to lose." },
    },
  },
  {
    id = "survey", name = "Survey", about = "Finding things: the scanner, probes, derelicts and their locks.",
    lessons = {
      { title = "Listen", aim = "Run a scan", on = "Scanned", mine = "ball", need = 1, kit = {}, credits = 2000, gifts = {},
        says = "Scan, at the top of the overview, opens the scanner. Undock and run one. It shows the signals in this "
          .. "system that are on no chart: pirate dens at once, the rest a little nearer each time." },
      { title = "A belt on no chart", aim = "Find a hidden site", on = "Scanned", mine = "ball", need = 1, kit = {}, credits = 5000,
        also = function(event: Event): boolean
          return (event.found or 0) > 0
        end,
        site = "ore", gifts = {},
        says = "There is a belt in this system that no chart has. Keep scanning until it is found: three scans, fewer as "
          .. "Astrometrics is trained. A found site is on the overview to warp to, and its rocks are bigger than any belt's." },
      { title = "Probes", aim = "Put out scan probes", on = "ProbeLaunched", mine = "ball", need = 1, credits = 4000,
        kit = { { type = "scanner.probe", quantity = 1 }, { type = "probe.scan", quantity = 8 } },
        gifts = { { type = "book.hacking", quantity = 1 } },
        says = "Probes find what the ship's scanner cannot. Train Astrometrics to level 1 (Skills tab), fit this Probe "
          .. "Launcher to a mid slot, and take the probes into your hold. Undock, open the System map and Launch: they "
          .. "fly out round you. Drag them over a signal, set their reach small, and Scan. They last an hour; Recall "
          .. "brings them back." },
      { title = "The sealed hold", aim = "Hack a derelict's hold open, whole", on = "HackDone", need = 1, credits = 15000,
        also = function(event: Event): boolean
          return event.success == true
        end,
        site = "relic",
        kit = { { type = "analyzer.data", quantity = 1 }, { type = "analyzer.relic", quantity = 1 }, { type = "probe.scan", quantity = 2 } },
        gifts = { { type = "cloak.device", quantity = 1 }, { type = "book.cloaking", quantity = 1 } },
        says = "A derelict is adrift in this system. The ship's scanner gets it half way and says which planet it is by: "
          .. "on the System map, send your probes there and scan, closer and smaller each time. Its hold is sealed. Train Hacking (it wants CPU Management 2), fit the Data "
          .. "Analyzer, and Hack from within five kilometres: get the key of the safeguards in." },
    },
  },
  {
    id = "command", name = "Command", about = "Others to do the work: drones, and pilots who fly for you.",
    lessons = {
      { title = "A drone of your own", aim = "Launch a drone", on = "DroneLaunched", mine = "owner", need = 1, credits = 3000,
        kit = { { type = "drone.light", quantity = 1 } }, gifts = {},
        says = "A drone is a small ship that works beside yours. Train Drones to level 1 (Skills tab: two minutes). Fitting "
          .. "tab: put this one in the drone bay. Undock and Launch (the drones' row, bottom left). It fights whoever "
          .. "comes for you, and whoever you point it at." },
      { title = "Call it home", aim = "Take a drone back aboard", on = "DroneScooped", mine = "owner", need = 1, kit = {},
        -- (since 2026-11-21 what is paid founds a corporation: the fleet is its members)
        credits = 260000, gifts = { { type = "drone.mining", quantity = 1 } },
        says = "A drone left behind when you warp or dock is lost, unless it is close by. Recall brings it in. Launch, "
          .. "recall, and wait until it is aboard. What I pay for this one is for the next: it founds your corporation." },
      { title = "Somebody to fly with", aim = "Ask a member into your fleet", on = "PilotHired", need = 1, kit = {},
        credits = 12000,
        -- (the plain Courier, which anybody can fly: a new member of grade
        -- 1 has not the skill for a people's own frigate, which the pilot
        -- themselves begins in)
        gifts = { { type = "frigate.courier", quantity = 1 }, { type = "miner.small", quantity = 1 } },
        -- (since 2026-11-21 nobody is hired: the fleet is the corporation's members)
        says = "Those who fly with you are members of your corporation. Corporation window: found one here (it costs "
          .. "250,000). Its Members page lists pilots at this station open to joining: the first here always joins. Invite "
          .. "them, then on the Crew window ask them into your fleet. It has room for ten, and ten more a level of Leadership." },
      { title = "A ship for them", aim = "Give your pilot a ship", on = "ShipAssigned", need = 1, kit = {}, credits = 8000,
        gifts = {},
        says = "A pilot flies a ship of yours. Ships tab: assemble the Courier hull I gave you and board it. Fitting tab: "
          .. "fit the mining laser. Board your own ship again, and on the Crew tab give them the new one. They undock "
          .. "when you do, and go where you go." },
      { title = "Earn their keep", aim = "Have your pilot bring ore in", on = "OreDelivered", need = 1, kit = {},
        credits = 30000, gifts = { { type = "drone.light", quantity = 2 }, { type = "drone.mining", quantity = 1 } },
        says = "Warp to a belt, your pilot beside you. Mine here (the fleet's panel, bottom left) sets them to it: they "
          .. "fill the hold, take it in to the nearest station and go back, wherever you go after. Report in when the "
          .. "first hold is in." },
    },
  },
  {
    id = "planets", name = "Planets", about = "A planet's worth: a colony, what it digs up and what it makes.",
    lessons = {
      { title = "Ground", aim = "Put a colony down on a planet", on = "ColonyDeployed", mine = "by", need = 1, credits = 50000,
        kit = { { type = "colony.command", quantity = 1 } }, gifts = {},
        says = "Planets have what stations pay for. Put this command centre in your hold, warp to a planet, select it and "
          .. "press Colony: it shows what is in the ground there. Deploy puts the centre down, and the colony is yours." },
      { title = "Digging", aim = "Raise an extractor", on = "FacilityBuilt", need = 1, kit = {}, credits = 80000, gifts = {},
        also = function(event: Event): boolean
          return event.type == "extractor"
        end,
        says = "The Colonies window (bottom left, from anywhere) raises facilities, for credits. Raise an extractor on "
          .. "something in the ground and give it a programme: the longer it runs, the less it brings up an hour." },
      { title = "Make", aim = "Raise a processor", on = "FacilityBuilt", need = 1, kit = {}, credits = 30000, gifts = {},
        also = function(event: Event): boolean
          return event.type == "processor"
        end,
        says = "A processor turns what the extractor brings up into something worth carrying. Raise the one that takes "
          .. "what you are digging. What I paid you for the extractor covers it." },
      { title = "Bring it up", aim = "Fetch what the colony has made", on = "Exported", mine = "ship", need = 1, kit = {},
        credits = 40000, gifts = { { type = "colony.command", quantity = 1 } },
        says = "What a colony digs and makes waits in its store: the first is there a quarter of an hour after the "
          .. "programme begins. From orbit, in the Colonies window, take it up into your hold (there is a little tax), "
          .. "and sell it. A colony goes on working while you are away. Here is a second centre for another planet." },
    },
  },
} :: { Career }

Careers.byId = {} :: { [string]: Career }
for _, career in Careers.list do
  Careers.byId[career.id] = career
end

-- How far the pilot has got with a career (not begun, if nothing says).
function Careers.Of(state: State.State, id: string): State.Career
  return state.careers[id] or { done = 0, taken = false, count = 0, again = false }
end

-- Who a career's agent is: the same person for as long as the galaxy lasts.
function Careers.Agent(state: State.State, id: string): string
  local slot = 0
  for index, career in Careers.list do
    slot = if career.id == id then index else slot
  end
  return Names.Person(Rng.For(state.galaxySeed, Careers.Station(state), slot, 113))
end

-- The lesson of a career that is in hand, or is the next to take; nil
-- when the agent has nothing more to teach.
function Careers.Lesson(state: State.State, id: string): Lesson?
  local career = Careers.byId[id]
  return if career then career.lessons[Careers.Of(state, id).done + 1] else nil
end

-- Whose station the agents are at.
local function faction(state: State.State): string
  return Stations.People(state, Careers.Station(state))
end

-- The combat frigate that faction builds (the plain one, if it builds none).
function Careers.Frigate(state: State.State): string
  -- (the one a pilot begins in: Data/Ships)
  return Ships.Starter(faction(state))
end

-- What finishing a lesson gives beside its credits.
function Careers.Gifts(state: State.State, lesson: Lesson): { Stack }
  local gifts = table.clone(lesson.gifts)
  if lesson.frigate then
    table.insert(gifts, { type = Careers.Frigate(state), quantity = 1 })
  end
  return gifts
end

-- How a lesson in hand stands: how much of what it wants there is, of
-- how much. (What is to be brought is what could be handed over, docked
-- at the agents' station: in the hold and in the hangar there. Anywhere
-- else it is what is in the hold.)
function Careers.Progress(state: State.State, id: string): (number, number)
  local lesson = Careers.Lesson(state, id)
  local mine = Careers.Of(state, id)
  if lesson == nil or not mine.taken then
    return 0, 0
  elseif lesson.bring then
    local ship = state.ships[state.player.ship]
    local have = 0
    if ship and ship.docked == Careers.Station(state) then
      have = Missions.ToHand(state, ship, lesson.bring.type)
    elseif ship then
      for _, item in Items.In(state, ship.id, "cargo") do
        have += if item.type == lesson.bring.type then item.quantity else 0
      end
    end
    return math.min(have, lesson.bring.quantity), lesson.bring.quantity
  end
  return math.min(mine.count, lesson.need), lesson.need
end

-- Whether a lesson in hand can be reported done by a ship docked at the
-- agents' station; if not, why not.
function Careers.Ready(state: State.State, ship: State.Ship, id: string): (boolean, string?)
  local lesson = Careers.Lesson(state, id)
  local mine = Careers.Of(state, id)
  if lesson == nil or not mine.taken then
    return false, "no lesson of theirs is in hand"
  elseif lesson.bring then
    local have = Missions.ToHand(state, ship, lesson.bring.type)
    if have < lesson.bring.quantity then
      return false, `{lesson.bring.quantity - have} more {Types.Info(lesson.bring.type).name} to bring`
    end
  elseif mine.count < lesson.need then
    return false, if lesson.need == 1 then "still to do" else `{mine.count} of {lesson.need} so far`
  end
  return true
end

-- Whether there is, in the agents' system, what a lesson wants found: a
-- hidden belt not found yet, or a derelict with a hold still sealed.
local function provided(state: State.State, system: number, kind: string): boolean
  for _, site in Sites.In(state, system) do
    if site.kind == kind and kind == "ore" and site.strength < 1 then
      return true
    elseif site.kind == kind and kind == "relic" then
      for _, id in state.wreckIds do
        local wreck = state.wrecks[id]
        if wreck.system == system and wreck.grid == site.id and wreck.locked then
          return true
        end
      end
    end
  end
  return false
end

-- See to it that there is.
local function provide(state: State.State, kind: string, events: { Event })
  local system = Space.SystemOf(state, Careers.Station(state))
  if not provided(state, system, kind) then
    Sites.Plant(state, system, kind, Rng.For(state.historySeed, state.tick, system, 131), events)
  end
end

-- How many of a type the pilot has, anywhere: in any hangar, and aboard
-- or fitted to any ship of theirs.
local function owned(state: State.State, type: string): number
  local have = 0
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.type == type then
      local ship = state.ships[item.holder]
      if ship == nil or ship.owner == "player" then
        -- (a hangar's, or one of their ships': not a wreck's, nor anybody else's)
        if ship ~= nil or Space.Object(state, item.holder) ~= nil then
          have += item.quantity
        end
      end
    end
  end
  return have
end

-- What of a lesson's kit the pilot no longer has: the stacks it would
-- take to make it whole again. (A thing used up in doing the lesson is
-- not lost: once the lesson is done there is nothing to hand over.)
function Careers.Lost(state: State.State, id: string): { Stack }
  local lesson = Careers.Lesson(state, id)
  local mine = Careers.Of(state, id)
  local lost: { Stack } = {}
  local have, need = Careers.Progress(state, id)
  if lesson and mine.taken and have < need then
    for _, stack in lesson.kit do
      local short = stack.quantity - owned(state, stack.type)
      if short > 0 then
        table.insert(lost, { type = stack.type, quantity = short })
      end
    end
  end
  return lost
end

function Careers.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local career = Careers.byId[command.what or ""]
  if ship == nil then
    return false, "no such ship"
  elseif career == nil then
    return false, "no such career"
  end
  local station = Careers.Station(state)
  if ship.docked ~= station then
    local object = Space.Object(state, station)
    return false, `the career agents are at {if object then object.name else "the first station"}`
  end
  local mine = Careers.Of(state, career.id)
  if command.kind == "AcceptLesson" then
    if mine.taken then
      return false, "that lesson is in hand already"
    elseif mine.done >= #career.lessons then
      return false, `{Careers.Agent(state, career.id)} has nothing more to teach`
    end
    return true
  elseif command.kind == "CompleteLesson" then
    return Careers.Ready(state, ship, career.id)
  elseif command.kind == "ReplaceKit" then
    -- What a lesson handed over, handed over again to a pilot who has
    -- lost it: once a lesson, and only what is really gone.
    local lesson = Careers.Lesson(state, career.id)
    if not mine.taken or lesson == nil then
      return false, "no lesson of theirs is in hand"
    elseif #lesson.kit == 0 then
      return false, "that lesson handed nothing over"
    elseif mine.again then
      return false, `{Careers.Agent(state, career.id)} has handed it over twice already`
    elseif #Careers.Lost(state, career.id) == 0 then
      return false, "you still have what was handed over"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Careers.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local career = Careers.byId[command.what :: string]
  local station = Careers.Station(state)
  local mine = state.careers[career.id]
  if mine == nil then
    mine = { done = 0, taken = false, count = 0, again = false }
    state.careers[career.id] = mine
  end
  local lesson = career.lessons[mine.done + 1]
  local agent = Careers.Agent(state, career.id)
  if command.kind == "ReplaceKit" then
    local lost = Careers.Lost(state, career.id)
    for _, stack in lost do
      Items.Add(state, stack.type, stack.quantity, station, "hangar")
    end
    mine.again = true
    table.insert(events, { kind = "KitReplaced", career = career.id, agent = agent, stacks = #lost })
    return
  end
  if command.kind == "AcceptLesson" then
    mine.taken, mine.count, mine.again = true, 0, false
    for _, stack in lesson.kit do
      Items.Add(state, stack.type, stack.quantity, station, "hangar")
    end
    if lesson.site then
      provide(state, lesson.site, events)
    end
    table.insert(events, { kind = "LessonTaken", career = career.id, lesson = mine.done + 1, title = lesson.title, agent = agent })
    return
  end
  if lesson.bring then
    Missions.Hand(state, ship, lesson.bring.type, lesson.bring.quantity)
  end
  Wallet.Pay(state, lesson.credits, "career agent", events)
  local gifts = Careers.Gifts(state, lesson)
  for _, stack in gifts do
    Items.Add(state, stack.type, stack.quantity, station, "hangar")
  end
  Standings.Change(state, faction(state), Careers.STANDING)
  mine.done += 1
  mine.taken, mine.count, mine.again = false, 0, false
  table.insert(events, { kind = "LessonDone", career = career.id, lesson = mine.done, title = lesson.title, agent = agent,
    credits = lesson.credits, gifts = #gifts, finished = mine.done >= #career.lessons, name = career.name })
end

-- Once a tick: what the events since 'first' (the place in the list
-- this tick's begin at) do for the lessons in hand; and, now and then,
-- that what a lesson wants found is still there to find.
function Careers.Step(state: State.State, events: { Event }, first: number)
  local last = #events
  for _, career in Careers.list do
    local mine = state.careers[career.id]
    local lesson = if mine and mine.taken then career.lessons[mine.done + 1] else nil
    if mine == nil or lesson == nil then
      continue
    end
    local before = mine.count
    if lesson.skill then
      if (state.skills[lesson.skill.id] or -1) >= lesson.skill.level then
        mine.count = lesson.need
      end
    elseif lesson.on ~= "" and mine.count < lesson.need then
      for at = first, last do
        local event = events[at]
        if event.kind == lesson.on and (lesson.mine == nil or event[lesson.mine] == state.player.ship)
          and (lesson.also == nil or lesson.also(event, state)) then
          mine.count = math.min(lesson.need, mine.count + (if lesson.worth then lesson.worth(event) else 1))
        end
      end
    end
    if before < lesson.need and mine.count >= lesson.need then
      table.insert(events, { kind = "LessonReady", career = career.id, lesson = mine.done + 1, title = lesson.title,
        agent = Careers.Agent(state, career.id) })
    end
    if lesson.site and state.tick % Careers.CHECK == 0 then
      provide(state, lesson.site, events)
    end
  end
end

return Careers
