--!strict
-- One running game as the view sees it: the Core game, the clock that
-- drives it, what the player has selected, and the events of this frame.
-- Everything the UI does to the game goes through Session.Order.

local Clock = require("@lt/Game/Clock")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Factions = require("@lt/Core/Data/Factions")
local Format = require("@lt/Game/Format")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Boosters = require("@lt/Core/Data/Boosters")
local Types = require("@lt/Core/Data/Types")

local Session = {}

export type Session = {
  game: Core.Game,
  clock: Clock.Clock,
  selected: number,           -- id of the selected body, or 0
  -- The pilot's target: of the things their ship has locked or is
  -- locking, the one they are at (Session.Aim keeps it). What a weapon
  -- switched on fires at, and what the camera follows. 0 with nothing
  -- locked. 'aimed' and 'aimedAt' are what was locked and what was
  -- selected when it was last looked at, to tell what has changed.
  target: number,
  aimed: { [number]: boolean },
  aimedAt: number,
  events: { Space.Event },    -- the events of the ticks taken this frame
  message: string,            -- the last thing worth telling the player
  messageTick: number,
  -- Where the pilot means to go: a system, or 0. With 'autopilot' the
  -- ship flies there itself, gate by gate, by the fewest jumps or (with
  -- 'safest') the least dangerous way (Galaxy.Route).
  destination: number,
  autopilot: boolean,
  safest: boolean,
  -- Which game this is, counting from 1: it goes up when the running
  -- game is replaced by a save or by a new one, so that whoever keeps
  -- something made for the last game (the scene) knows to make it again.
  epoch: number,
}

-- Where saves are kept. A script's saves go somewhere of their own, so
-- that a test never writes over a save somebody is playing from.
local SAVE_DIR = if Host.scripted then "cache/test-saves" else "save"

-- How far above its surface a warp to a planet, a moon or the sun ends
-- when the order gives no range, in the body's radii. (The Core takes a
-- range of 0 at its word, and a warp to the surface of a planet ends
-- with the planet a wall across the view. At one radius up, a planet
-- spans a third of the sky.)
local STANDOFF: { [string]: number } = { planet = 1, moon = 1.5, sun = 4 }

function Session.New(galaxySeed: number, historySeed: number): Session
  return {
    game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed, traffic = true, wars = true }),
    clock = Clock.New(), selected = 0, target = 0, aimed = {}, aimedAt = 0, events = {}, message = "", messageTick = 0, epoch = 1,
    destination = 0, autopilot = false, safest = false,
  }
end

function Session.Say(session: Session, text: string)
  session.message = text
  session.messageTick = session.game.state.tick
end

-- Tell the player about an event that concerns them.
function Session.Notice(session: Session, event: Space.Event)
  local mine = session.game.state.player.ship
  local kind = event.kind
  if kind == "CommandRejected" then
    Session.Say(session, `{event.command}: {tostring(event.reason)}`)
  elseif kind == "PiratesArrived" and event.wave then
    Session.Say(session, `Wave {event.wave} of {event.of}: ` .. (if event.chief then "the camp's chief is out"
      .. (if event.count > 1 then `, with {event.count - 1} more` else "")
      elseif event.convoy then `{event.count} {if event.count == 1 then "pirate was" else "pirates were"} waiting for the tender where it landed`
      elseif event.hold or event.escort then `{event.count} {if event.count == 1 then "pirate has" else "pirates have"} come for the `
        .. (if event.escort then "tender" else "rig")
      else `{event.count} {if event.count == 1 then "ship" else "ships"} of the camp's`))
  elseif kind == "PiratesArrived" and event.away then
    -- (somewhere else, for a hired pilot: they say so themselves when they are gone for)
    return
  elseif kind == "PiratesArrived" then
    Session.Say(session, (if event.count == 1 then "A pirate has arrived" else `{event.count} pirates have arrived`)
      .. (if (event.captains or 0) > 0 then (if event.count == 1 then ": a captain" else ", a captain among them") else ""))
  elseif kind == "FleetAttacked" then
    Session.Say(session, `{event.name} is under attack at {event.where}`)
  elseif kind == "PatrolRetired" then
    Session.Say(session, `{event.name} is going in to mend`)
  elseif kind == "WaveDown" then
    Session.Say(session, `Wave {event.wave} of {event.of} is down: the next is coming`)
  elseif kind == "AssaultCleared" then
    local body = Core.Query.Body(session.game, event.station)
    local aim: string = event.aim
    Session.Say(session, `{if aim == "chief" then "The chief is destroyed" elseif aim == "raze" then "The camp is razed"
      elseif aim == "hold" then "The rig is held" elseif aim == "escort" then "The tender is through, and gone"
      elseif aim == "convoy" then (if event.through then "The tender is through the gate" else "The tender is in")
      else "The camp is cleared"}: `
      .. `{if body then body.name else "the station"} will pay for it`)
  elseif kind == "WardSighted" then
    Session.Say(session, if event.escort then "The tender is here, and setting off: keep it flying until it is clear"
      else "The survey rig is here: keep it standing, and destroy whoever comes for it")
  elseif kind == "WardAway" then
    local body = Core.Query.Body(session.game, event.to or event.station)
    Session.Say(session, `The tender is clear, and away to {if body then body.name else "the station"}: follow it, and see it in`)
  elseif kind == "WardLost" then
    Session.Say(session, if event.escort then "The tender is destroyed" else "The survey rig is destroyed")
  elseif kind == "MissionFailed" then
    Session.Say(session, `A job is lost: {event.title}`)
  elseif kind == "CorporationFounded" then
    Session.Say(session, `{event.name} is founded: your hired pilots work for it from now on`)
  elseif kind == "WorksSighted" then
    Session.Say(session, if event.count == 1 then "The camp's store is here: destroy it"
      else `What the camp is built of is here: {event.count} works to destroy`)
  elseif kind == "RoomOpen" then
    Session.Say(session, if (event.gate or 0) ~= 0 then `The room is cleared: its gate is open, and leads on to {event.name}`
      else `The way on is found: {event.name} is on the overview`)
  elseif kind == "PassageTaken" and event.ship == mine then
    Session.Say(session, `Through the gate: on to {event.name}`)
  elseif kind == "WalletChanged" then
    local sign = if event.amount >= 0 then "+" else "-"
    Session.Say(session, `{sign}{math.abs(event.amount)} credits ({event.reason})`)
  elseif kind == "Ejected" then
    Session.Say(session, "Your ship is lost. You are in your capsule: warp to a station")
  elseif kind == "Respawned" then
    -- (at home: the station the pilot keeps a berth at)
    local home = Core.Query.Body(session.game, event.station)
    Session.Say(session, `You wake at home, {if home then home.name else "your station"}, and have been given a new ship`)
  elseif kind == "HomeMoved" then
    local home = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if home then home.name else "This station"} is your home now: lose your capsule, and you wake here`)
  elseif kind == "ShipGranted" then
    Session.Say(session, "You have been given a new ship")
  elseif kind == "ModuleStopped" and event.ball == mine and event.reason ~= "switched off" then
    Session.Say(session, `A module stopped: {event.reason}`)
  elseif kind == "Looted" and event.ship == mine then
    Session.Say(session, if event.left > 0 then `Looted {event.taken}; {event.left} would not fit` else `Looted {event.taken}`)
  elseif kind == "Mined" and event.ball == mine then
    -- (ore, off a rock; or gas, off a cloud)
    Session.Say(session, if string.sub(event.ore, 1, 4) == "gas." then `Drew off {event.units} units of {Types.Info(event.ore).name}`
      else `Mined {event.units} units of ore`)
  elseif kind == "Reprocessed" and event.ship == mine then
    Session.Say(session, `Refined {event.units} units of ore`)
  elseif kind == "LockLost" and event.ball == mine and tostring(event.reason) ~= "unlocked" then
    Session.Say(session, `Lock lost: {event.reason}`)
  elseif kind == "SkillTrained" then
    Session.Say(session, `{Skills.byId[event.skill].name} trained to level {event.level}`)
  elseif kind == "SkillLearned" then
    Session.Say(session, `Learned {Skills.byId[event.skill].name}: it can be trained now`)
  elseif kind == "OrderChanged" then
    Session.Say(session, `The order for {Types.Info(event.type).name} is at {event.price} credits now, from {event.was}`
      .. (if event.fee > 0 then `: the broker took {event.fee}` else ""))
  elseif kind == "JobCancelled" then
    -- (of a copy, the runs not used come back: 'back' is how many)
    local copy = (event.back or 0) > 0
    Session.Say(session, if event.research == "copy" then `Called off: {event.made} of {event.quantity} runs were copied. The blueprint is back in the hangar`
      elseif event.research ~= "" then `Called off: the {Types.Info(event.blueprint).name} is back in the hangar`
      elseif event.made > 0 then `Called off: {event.made} of {event.quantity} {Types.Info(event.product).name} were made. What went into the rest is lost`
        .. (if copy then `, and the copy has its {event.back} runs not used` else "")
      else `Called off: nothing was made yet, and what went into it is lost. The {if copy then "copy" else "blueprint"} is back in the hangar`)
  elseif kind == "JobDone" then
    Session.Say(session, `Built: {event.quantity} x {Types.Info(event.product).name}`)
  elseif kind == "ResearchDone" then
    Session.Say(session, `Research done: {Types.Info(event.blueprint).name}, {event.what} level {event.level}`)
  elseif kind == "InventionDone" then
    Session.Say(session, if event.success then `Invented: {Types.Info(event.product).name} is in the hangar`
      elseif event.used then "The invention came to nothing, and the run of the copy it was worked from is used up"
      else `The invention came to nothing: {Types.Info(event.blueprint).name} is back in the hangar`)
  elseif kind == "FleetFightOver" and not event.joined then
    -- (one the pilot was not at: how it came out, and where to read the rest)
    local came = if event.lost > 0 then (if event.lost == 1 then "a ship was lost" else `{event.lost} ships were lost`)
      elseif event.held then "your pilots held it" else "your pilots are gone from it"
    Session.Say(session, `The fight at {event.where} is over: {came}, {event.destroyed} destroyed`
      .. (if event.fled > 0 then `, {event.fled} got away` else "") .. ". The Crew tab's log has it")
  elseif kind == "FleetWarpCalled" then
    Session.Say(session, if event.expect == 0 then "Fleet warp: nobody is here to go with you"
      elseif event.expect == 1 then "Fleet warp: one pilot is forming up on you" else `Fleet warp: {event.expect} pilots are forming up on you`)
  elseif kind == "PirateFleeing" or kind == "PirateFled" then
    -- (only of a fight the pilot is at: a hired pilot's, somewhere else, is theirs to watch)
    local me = Core.Query.Ball(session.game, mine)
    if me and me.system == event.system and me.grid == event.grid then
      Session.Say(session, if kind == "PirateFleeing" then `The {event.name} is breaking off: hold it or finish it, or it is gone`
        else `The {event.name} got away`)
    end
  elseif kind == "ContractAccepted" then
    Session.Say(session, `Bought by contract: {event.title}. It is in the hangar`)
  elseif kind == "ContractFilled" then
    Session.Say(session, `Delivered by contract: {event.title}`)
  elseif kind == "ContractListed" then
    Session.Say(session, `Up on the board: {event.quantity} x {Types.Info(event.type).name}, for {event.price} credits`)
  elseif kind == "ContractSold" then
    local where = Core.Query.Body(session.game, event.station)
    Session.Say(session, `Sold by contract at {if where then where.name else "a station"}: {event.quantity} x {Types.Info(event.type).name}`)
  elseif kind == "ContractExpired" then
    local where = Core.Query.Body(session.game, event.station)
    Session.Say(session, `Nobody took {event.quantity} x {Types.Info(event.type).name} at {if where then where.name else "a station"}: it is back in the hangar there`)
  elseif kind == "ContractCancelled" then
    Session.Say(session, `Taken down: {event.quantity} x {Types.Info(event.type).name} is back in the hangar`)
  elseif kind == "CopyDone" then
    Session.Say(session, `Copied: {Types.Info(event.blueprint).name}, a copy good for {event.runs} {if event.runs == 1 then "run" else "runs"}`)
  elseif kind == "ShipAssembled" then
    Session.Say(session, "The hull is assembled: board it from the Ships tab")
  elseif kind == "StarbaseAnchored" then
    local status = Core.Query.Starbase(session.game, event.station)
    Session.Say(session, `The tower is anchoring: it can be moored at in {if status then status.wait else 0} s`)
  elseif kind == "StarbaseFuelled" and event.hangar then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has taken {event.fuel} fuel blocks from its hangar`)
  elseif kind == "StarbaseFuelled" then
    Session.Say(session, `The tower has {event.fuel} fuel blocks aboard`)
  elseif kind == "FleetOrdered" and event.what == "stock" then
    local body = Core.Query.Body(session.game, event.target)
    Session.Say(session, `{event.name} will keep {event.quantity} {Types.Info(event.type).name} in the hangar here, bought at `
      .. `{if body then body.name else "the market"} for no more than {event.price} credits each`)
  elseif kind == "StockShort" then
    Session.Say(session, `{event.name} could not buy all the {Types.Info(event.type).name} that is wanted: {event.reason}. They will try again`)
  elseif kind == "ModuleAnchored" then
    Session.Say(session, `{Types.Info(event.module).name} anchored: it will be online shortly`)
  elseif kind == "ModuleUnanchored" then
    Session.Say(session, `{Types.Info(event.module).name} unanchored: it is in the hangar`)
  elseif kind == "TowerUnanchored" then
    Session.Say(session, `The tower is down, and in the hold`
      .. (if event.fuel > 0 then `, with {event.fuel} blocks of its fuel` else "")
      .. (if event.left > 0 then `: {event.left} blocks there was no room for are left behind` else ""))
  elseif kind == "FleetUnposted" then
    Session.Say(session, `{event.name} has no post there any more, and waits`)
  elseif kind == "Jumped" and event.ship == mine and event.drive then
    local system = session.game.state.galaxy.systems[event.to]
    Session.Say(session, string.format("Jump drive: %s, %.1f light years, out at %s", if system then system.name else "there",
      event.distance or 0, tostring(event.beacon or "the beacon")))
  elseif kind == "Jumped" and event.ship == mine and event.wormhole then
    -- (through a wormhole: into uncharted space, or out of it)
    local node = session.game.state.galaxy.systems[event.to]
    Session.Say(session, if node.uncharted then `Through the wormhole: {node.name}, on no map. Depth {node.depth or 1} of {#Galaxy.DEPTHS}`
      else `Through the wormhole: {node.name}, back on the map`)
  elseif kind == "WormholeClosed" and event.found and event.system == Core.Query.Player(session.game).system then
    Session.Say(session, `{event.name} has closed`)
  elseif kind == "JumpFailed" and event.ship == mine then
    Session.Say(session, `No way through: {event.why}`)
  elseif kind == "Jumped" and event.ship == mine then
    -- (say so when the kind of space changes: what waits at a belt does)
    local _, was = Core.Query.Security(session.game, event.from)
    local _, now = Core.Query.Security(session.game, event.to)
    if now and now ~= was then
      Session.Say(session, if now == "lawless" then "Lawless space: nobody keeps order here"
        elseif now == "low" then "Low security: order is thin here"
        else "Secure space")
    end
  elseif kind == "BatteryFired" and event.to == mine then
    Session.Say(session, "The station's batteries are firing on you")
  elseif kind == "RigDestroyed" then
    Session.Say(session, `{Types.Info(event.type).name} taken out: it is destroyed`)
  elseif kind == "Salvaged" and event.ball == mine then
    Session.Say(session, `Salvaged: {event.pieces} {if event.pieces == 1 then "piece" else "pieces"} brought off`)
  elseif kind == "DroneLost" and event.owner == mine then
    Session.Say(session, if event.destroyed then `A {Types.Info(event.type).name} has been destroyed`
      else `A {Types.Info(event.type).name} was left behind: it is lost`)
  elseif kind == "PilotHired" then
    Session.Say(session, `{event.name} is hired: give them a ship on the Crew tab`)
  elseif kind == "ShipAssigned" then
    local ship = session.game.state.ships[event.ship]
    Session.Say(session, if ship then `{event.name} flies the {ship.name} and goes where you go` else `{event.name} has no ship now`)
  elseif kind == "LessonTaken" then
    Session.Say(session, `{event.agent}: "{event.title}". The Guide has what it wants, under Lessons`)
  elseif kind == "LessonReady" then
    Session.Say(session, `"{event.title}" is done: report to {event.agent} for it`)
  elseif kind == "LessonDone" then
    Session.Say(session, if event.finished then `{event.name}: the last lesson is done. +{event.credits} credits, and what is in the hangar`
      elseif event.gifts > 0 then `Lesson done: +{event.credits} credits, and something in the hangar`
      else `Lesson done: +{event.credits} credits`)
  elseif kind == "Guided" then
    Session.Say(session, `Guide: "{event.title}" is done ({event.done} of {event.of})`)
  elseif kind == "ImplantPlugged" then
    Session.Say(session, `{Types.Info(event.implant).name} is plugged in`)
  elseif kind == "ImplantDestroyed" then
    Session.Say(session, `{Types.Info(event.implant).name} taken out: it is destroyed`)
  elseif kind == "ImplantsLost" then
    Session.Say(session, `Your capsule is destroyed, and your {if event.count == 1 then "implant" else `{event.count} implants`} with it`)
  elseif kind == "Bookmarked" then
    Session.Say(session, `Marked: {event.name}. It is on the overview, to warp back to`)
  elseif kind == "FleetCannotJump" then
    Session.Say(session, `{event.name} cannot jump after you ({event.why}), and is coming by the gates`)
  elseif kind == "OreHandedOver" then
    Session.Say(session, `{event.name} put {event.units} units of {if event.gas then "gas" else "ore"} aboard {event.aboard}`)
  elseif kind == "OreDelivered" or kind == "HaulDelivered" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{event.name} brought in {event.units} units{if kind ~= "OreDelivered" then "" elseif event.gas then " of gas" else " of ore"} to `
      .. `{if body then body.name else "the station"}` .. (if (event.revenue or 0) > 0 then `, sold for {event.revenue} credits` else ""))
  elseif kind == "FleetOrdered" and event.what == "buy" then
    local body = Core.Query.Body(session.game, event.target)
    Session.Say(session, `{event.name} is off to buy {event.quantity} {Types.Info(event.type).name} at `
      .. `{if body then body.name else "the market"}, for no more than {event.price} credits each`)
  elseif kind == "BuyDelivered" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{event.name} brought {event.units} {Types.Info(event.type).name} to {if body then body.name else "the station"}`
      .. (if event.left > 0 then `, and is going back for {event.left} more` else ": that is all of it"))
  elseif kind == "BuyEnded" then
    Session.Say(session, `{event.name} could not buy {event.short} of the {Types.Info(event.type).name}: {event.reason}`)
  elseif kind == "KitReplaced" then
    Session.Say(session, `{event.agent} has handed it over again: it is in the hangar. There is no third time`)
  elseif kind == "TradeShock" or kind == "TradeShockOver" then
    -- (what is happening to the trade of a part of the map: Core/Strategic/Commerce)
    local galaxy = session.game.state.galaxy
    local constellation = galaxy.constellations[event.constellation]
    local where = `{constellation.name}, {galaxy.regions[constellation.region].name}`
    local what = Types.Info(event.type).name
    Session.Say(session, if kind == "TradeShockOver" then `NEWS: the {if event.shortage then "shortage" else "glut"} of {what} in {where} is over`
      elseif event.shortage then `NEWS: {what} is short in {where}, and dear there, for {event.days} days or so`
      else `NEWS: a glut of {what} in {where}: cheap there for {event.days} days or so`)
  elseif kind == "WarDeclared" or kind == "PeaceMade" then
    -- (the factions: Core/Strategic/Wars)
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    -- (with the pilot's own corporation: Core/Assets/Sovereignty)
    if kind == "WarDeclared" and event.by == "player" then
      Session.Say(session, `NEWS: your corporation has declared war on the {named(event.on)}: they are your enemies from now`)
      return
    end
    if (kind == "WarDeclared" and event.on == "player") or (kind == "PeaceMade" and event.b == "player") then
      Session.Say(session, if kind == "WarDeclared" then `NEWS: the {named(event.by)} have declared war on you: they will come for what you hold next to them`
        else `NEWS: the {named(event.a)} have made a truce with you`)
      return
    end
    local terms = ""
    if kind == "PeaceMade" and event.winner ~= "" then
      local ceded = session.game.state.galaxy.systems[event.ceded]
      terms = `. The {named(event.winner)} have the better of it` .. (if ceded then `, and {ceded.name}` else "")
    end
    Session.Say(session, if kind == "WarDeclared" then `NEWS: the {named(event.by)} have declared war on the {named(event.on)}`
      else `NEWS: the {named(event.a)} and the {named(event.b)} have made a truce, after {event.hours} hours of war{terms}`)
  elseif kind == "CoalitionJoined" then
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    Session.Say(session, `NEWS: the {named(event.by)} have joined the {named(event.beside)} against the {named(event.against)}`)
  elseif kind == "Blockaded" or kind == "SystemTaken" then
    -- (said when it is near enough to matter: within a few jumps)
    local here = Core.Query.Player(session.game).system
    local way = Session.Way(session, here, event.system)
    local name = session.game.state.galaxy.systems[event.system].name
    local whose = if kind == "Blockaded" then event.against else event.from
    if event.by == "player" then
      Session.Say(session, `{name} is yours: the claim stands, and order is kept there`)
    elseif whose == "player" then
      local by = if Factions.byId[event.by] then Factions.byId[event.by].name else event.by
      Session.Say(session, if kind == "Blockaded" then `NEWS: the {by} are blockading {name}, which is yours: its lines are a place to fight at`
        else `NEWS: the {by} have taken {name} from you`)
    elseif event.system == here or (#way > 0 and #way - 1 <= 6) then
      local by = if Factions.byId[event.by] then Factions.byId[event.by].name else event.by
      local from = if Factions.byId[whose] then Factions.byId[whose].name else ""
      Session.Say(session, if kind == "Blockaded" then `NEWS: the {by} are blockading {name}` .. (if from ~= "" then `, which the {from} hold` else "")
        elseif from ~= "" then `NEWS: the {by} have taken {name} from the {from}`
        else `NEWS: the {by} have claimed {name}`)
    end
  elseif kind == "FrontFound" or kind == "FrontCrossed" then
    -- (the factions' forces where the pilot is: Core/Tactical/Fronts)
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    Session.Say(session, if kind == "FrontCrossed" then `You have fired on the {named(event.side)}: their ships here are your enemies now`
      elseif event.by == "player" then `Your siege: the {named(event.against)} garrison is at the lines on the overview. Bring it down and the system is yours`
      elseif event.against == "player" then `The {named(event.by)} are besieging this system of yours: their lines are on the overview`
      elseif event.siege then `The {named(event.by)} are besieging this system, which the {named(event.against)} hold: the lines are on the overview`
      else `The {named(event.by)} are claiming this system: their blockade is on the overview`)
  elseif kind == "MemberApplied" then
    Session.Say(session, `{event.name}, a {event.trade}, has applied to join the corporation: Wallet, Corporation, Members`)
  elseif kind == "MemberJoined" then
    Session.Say(session, `{event.name} has joined the corporation, and is off to {session.game.state.galaxy.systems[event.system].name}`)
  elseif kind == "MemberLeft" then
    Session.Say(session, `{event.name} has left the corporation: {event.why}`)
  elseif kind == "MemberLost" and event.hull ~= "" then
    -- (one the pilot's own side destroyed says so by leaving: the line after this)
    local where = session.game.state.galaxy.systems[event.system]
    Session.Say(session, `{event.name} has lost their {Types.Info(event.was).name}{if where then ` in {where.name}` else ""}: `
      .. (if event.hull == event.was then "they have the price of another" else `a {Types.Info(event.hull).name} is what they can afford`))
  elseif kind == "MemberUpgraded" then
    Session.Say(session, `{event.name} has bought a {Types.Info(event.hull).name} out of their own earnings`)
  elseif kind == "LevyPaid" then
    Session.Say(session, `The levy is in: {event.amount} credits from {event.systems} {if event.systems == 1 then "system" else "systems"} of yours`)
  elseif kind == "ClaimLapsed" and event.by == "player" then
    Session.Say(session, `Your claim on {session.game.state.galaxy.systems[event.system].name} has lapsed: no beacon of yours stood lit there`)
  elseif kind == "HaulLost" then
    -- (a hauler that carried the economy's goods is gone: where it was going goes without)
    local node = session.game.state.galaxy.systems[event.system]
    Session.Say(session, `A hauler is lost with {event.amount} {Types.Info(event.type).name}: {if node then node.name else "where it was going"} goes without`)
  elseif kind == "SurgeBegan" then
    local name = session.game.state.galaxy.systems[event.system].name
    Session.Say(session, `PIRATE SURGE: pirates are massing ` .. (if event.jumps == 0 then `here in {name}`
      elseif event.jumps == 1 then `in {name}, a jump off` else `in {name}, {event.jumps} jumps off`)
      .. `. For two hours what is on their heads is doubled there`)
  elseif kind == "SurgeEnded" then
    local name = session.game.state.galaxy.systems[event.system].name
    Session.Say(session, `The surge in {name} is over` .. (if event.kills > 0 then `: {event.kills} pirates were destroyed there` else ""))
  elseif kind == "TowerRaided" then
    local body = Core.Query.Body(session.game, event.station)
    local name = if body then body.name else "your tower"
    if event.outcome == "robbed" then
      Session.Say(session, `RAIDED: pirates got in at {name}`
        .. (if event.taken > 0 then ` and carried off {event.taken} units of what its drill brought up` else "")
        .. `. Its defence was {event.defence} against {event.strength}`)
    elseif event.outcome == "beaten" then
      Session.Say(session, `Pirates came for {name} and were beaten off: its defence was {event.defence} against {event.strength}`)
    elseif event.outcome == "siege" then
      Session.Say(session, if event.back then `SIEGE: they are back for {name}, {event.strength} strong against its {event.defence}`
        else `SIEGE: pirates have come to bring {name} down, {event.strength} strong against its {event.defence}`)
    elseif event.outcome == "lost" then
      -- (said by the loss itself)
      return
    else
      Session.Say(session, `Pirates have come for {name}`)
    end
  elseif kind == "TowerSealed" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your tower"} has SEALED itself for {event.hours} {if event.hours == 1 then "hour" else "hours"}: `
      .. `nothing can touch it, and they will be back when it opens`)
  elseif kind == "TowerOpened" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your tower"} has opened` .. (if event.siege then ": they are coming back for it" else ""))
  elseif kind == "TowerLost" then
    Session.Say(session, `LOST: {event.name} has been brought down, with what was anchored on it and what was in its hangars`)
  elseif kind == "SiegeBroken" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `The siege of {if body then body.name else "your tower"} is broken: nobody of them is left`)
  elseif kind == "StarbaseCharged" then
    Session.Say(session, `Sealing charges aboard: {event.charges}`)
  elseif kind == "ReactionSet" then
    Session.Say(session, if event.type == "" then "The reactor is making nothing" else `The reactor is making {Types.Info(event.type).name}`)
  elseif kind == "ReactorIdle" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has not the {Types.Info(event.want).name} for more {Types.Info(event.type).name}: `
      .. `its reactor stands idle`)
  elseif kind == "KeepSighted" then
    local moon = Core.Query.Body(session.game, event.moon)
    Session.Say(session, `Pirates hold {if moon then moon.name else "a moon here"} with a tower of their own: nobody anchors there until it is brought down`)
  elseif kind == "KeepCalled" then
    Session.Say(session, `{event.name} is calling for help: a pack is coming`)
  elseif kind == "KeepSealed" then
    Session.Say(session, `{event.name} has SEALED itself for {event.hours} {if event.hours == 1 then "hour" else "hours"}: `
      .. `nothing can touch it until it opens, and a day after that it is resupplied`)
  elseif kind == "KeepOpened" then
    Session.Say(session, `{event.name} has opened: it has nothing to seal with again until it is resupplied`)
  elseif kind == "KeepRestocked" then
    Session.Say(session, `{event.name} has been resupplied: it is whole again`)
  elseif kind == "KeepLost" then
    Session.Say(session, `{event.name} is brought down: {event.moonName} is nobody's now, and takes a tower`)
  elseif kind == "MoonDrilled" and event.full then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has no room for more {Types.Info(event.type).name}: its drill stands idle`)
  elseif kind == "PilotPromoted" then
    Session.Say(session, `{event.name} is a grade {event.skill} pilot now, and is paid as one`)
  elseif kind == "WingmanLost" then
    Session.Say(session, `{event.name}'s ship has been destroyed: they got out, and are without one`)
  elseif kind == "PilotLeft" then
    Session.Say(session, if (event.reason :: string) == "unpaid" then `{event.name} could not be paid and has left: their ship is at your home station`
      elseif (event.reason :: string) == "lost" then `{event.name} has lost one ship too many under you, and has left`
      else `{event.name} has been let go`)
  elseif kind == "PilotUnpaid" then
    Session.Say(session, `{event.name} could not be paid today: they stay, and think the less of it ({Fleet.Mood(event.loyalty)})`)
  elseif kind == "ColonyShipMoved" then
    Session.Say(session, `{event.name} has gone on to {session.game.state.galaxy.systems[event.to].name}, and you with it`)
  elseif kind == "Cloaked" and event.ball == mine then
    Session.Say(session, "Cloaked: nobody can target you, and you can target nobody")
  elseif kind == "Decloaked" and event.ball == mine then
    Session.Say(session, if event.by == "" then "Decloaked" else `Decloaked: too near {event.by}`)
  elseif kind == "Jammed" and event.ball == mine then
    Session.Say(session, "Jammed: your locks are broken")
  elseif kind == "Held" and event.ball == mine then
    Session.Say(session, if event.scrambled and event.entangle < 1 then "Entangled and warp scrambled: you are held"
      elseif event.scrambled then "Warp scrambled: you cannot warp"
      elseif event.entangle < 1 then "Entangled: your speed is cut"
      else "You are free of them")
  elseif kind == "TrailFound" then
    Session.Say(session, `The den's records give away a stronghold: {event.name}, in {session.game.state.galaxy.systems[event.system].name}`)
  elseif kind == "Scanned" and event.ball == mine then
    Session.Say(session, if event.found > 0 then `Scan: {event.found} found` .. (if event.signals > 0 then `, {event.signals} still to resolve` else "")
      elseif event.signals > 0 and (event.faint or 0) >= event.signals then "Scan: too faint from here. The scanner says where to take a probe"
      elseif event.signals > 0 then `Scan: {event.signals} {if event.signals == 1 then "signal" else "signals"}, nearer`
      else "Scan: nothing new")
  elseif kind == "ProbeLaunched" and event.ball == mine then
    Session.Say(session, `Probe out: {event.out} of {4}. It lasts an hour`)
  elseif kind == "ProbesRecalled" and event.ball == mine then
    Session.Say(session, `{event.count} {if event.count == 1 then "probe is" else "probes are"} back in the hold`)
  elseif kind == "HackStarted" then
    Session.Say(session, "Hacking: pick codes from the matrix to get the keys into the buffer")
  elseif kind == "HackKey" then
    Session.Say(session, `The key of the {string.lower(event.name)} is in`)
  elseif kind == "HackDone" then
    local reason = event.reason :: string
    local wreck = session.game.state.wrecks[event.wreck]
    -- (a vault's lock is its own: on a clock, and all or nothing)
    local vault = wreck ~= nil and wreck.lock == "vault"
    local late = if reason == "out of time" then " The time ran out." else ""
    Session.Say(session, if reason == "left" then `The lock is left as it was: the {if vault then "vault" else "hold"} is still sealed`
      elseif wreck ~= nil and wreck.locked then `Too far off: the hack is dropped, and the {if vault then "vault" else "hold"} still sealed`
      elseif event.success then `The {if vault then "vault" else "hold"} is open, whole: {event.keys} of 3 keys were in.{late}`
      elseif vault then `The vault has wiped itself: the key of the safeguards was not in.{late}`
      else "The hold is open with half of what was in it burnt: the key of the safeguards was not in")
  elseif kind == "BoosterTaken" then
    local booster = Boosters.byId[event.booster]
    local minutes = math.floor((event.seconds or Boosters.SECONDS) / 60 + 0.5)
    Session.Say(session, `{booster.name}: at work for {minutes} minutes. `
      .. (if event.wrong then `It sits badly: {string.lower(string.sub(booster.cost, 1, 1))}{string.sub(booster.cost, 2)}` else "It sits well: no ill effect."))
  elseif kind == "BoosterSpent" then
    Session.Say(session, `{Types.Info(event.booster).name} has worn off`)
  elseif kind == "TrainingCredited" then
    -- (said only where there was training for the time to go to)
    if event.trained > 0 or event.queued > 0 then
      Session.Say(session, `Away {Format.Duration(event.seconds)}: `
        .. (if event.trained == 0 then "your training went on" elseif event.trained == 1 then "a skill level was trained"
          else `{event.trained} skill levels were trained`))
    end
  elseif kind == "ProbeLost" then
    Session.Say(session, "A probe has run down, and is gone")
  elseif kind == "StandingChanged" and event.by < 0 then
    local faction = Factions.byId[event.faction]
    Session.Say(session, string.format("%s standing %.1f: now %.1f%s", if faction then faction.name else "?", event.by, event.standing,
      if event.standing <= -5 then " (their patrols will fire on you)" else ""))
  elseif kind == "MissionAccepted" then
    Session.Say(session, `Job taken: {event.title}`)
  elseif kind == "MissionCompleted" then
    -- (and what whoever gave it thinks of the pilot now, where it was somebody)
    local thinks = if event.agent and event.agent ~= "" and (event.regard or 0) ~= 0
      then string.format("; %s %.1f", event.agent, event.regard) else ""
    Session.Say(session, string.format("Job done: +%d credits, +%d loyalty points, standing %.1f%s", event.reward, event.loyalty or 0,
      event.standing, thinks))
  elseif kind == "MissionExpired" then
    Session.Say(session, `A job has lapsed: {event.title}. It was kept too long`)
  elseif kind == "LoyaltyRedeemed" then
    Session.Say(session, `{Types.Info(event.type).name} is in the hangar: {event.left} loyalty points left`)
  elseif kind == "PoliceArrived" then
    Session.Say(session, "The police are here, and they are here for you")
  elseif kind == "ColonyFleetArrived" then
    Session.Say(session, `{event.name} has come through the gate, with {event.ships - 1} ships of its fleet`)
  elseif kind == "Marked" then
    Session.Say(session, "You have fired on a ship that is no pirate's: the patrols will fire on you")
  elseif kind == "ColonyDeployed" then
    local body = Core.Query.Body(session.game, event.planet)
    Session.Say(session, `A colony is founded on {if body then body.name else "the planet"}`)
  elseif kind == "ExtractionEnded" then
    local body = Core.Query.Body(session.game, event.planet)
    Session.Say(session, `{if body then body.name else "A colony"}: an extractor has finished its programme`)
  elseif kind == "Exported" then
    Session.Say(session, `Took up {event.quantity} x {Types.Info(event.type).name}: {event.tax} credits export tax`)
  elseif kind == "StarbaseDark" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your starbase"} is out of fuel: it is dark`)
  end
end

-- Take the ticks that are due this frame.
function Session.Update(session: Session, frameSeconds: number)
  session.events = {}
  -- (time runs faster only at a station: out of one, it is as it is)
  local clock = session.clock
  if clock.scale > 1 and not clock.forced and Core.Query.Player(session.game).docked == 0 then
    clock.scale = 1
  end
  for _ = 1, Clock.Advance(session.clock, frameSeconds) do
    Core.Step(session.game)
    for _, event in Core.TakeEvents(session.game) do
      table.insert(session.events, event)
      Session.Notice(session, event)
    end
  end
end

-- The way from one system to another (Galaxy.Route), which is not to be
-- changed by who asks. The map and the readouts ask for the same few
-- ways every frame, and in a large galaxy a way is some work to find:
-- one found is kept for the tick it was found in.
local ways: { [string]: { number } } = {}
local waysOf = ""

function Session.Way(session: Session, from: number, to: number, safest: boolean?): { number }
  local stamp = `{session.epoch}:{session.game.state.tick}`
  if stamp ~= waysOf then
    ways, waysOf = {}, stamp
  end
  local key = `{from}:{to}:{safest == true}`
  local way = ways[key]
  if way == nil then
    way = Galaxy.Route(session.game.state.galaxy, from, to, safest)
    ways[key] = way
  end
  return way
end

-- The way from where the pilot is to where they mean to go: the systems
-- in order, the first the one they are in. Empty with nowhere to go.
function Session.Route(session: Session): { number }
  local galaxy = session.game.state.galaxy
  if session.destination == 0 or galaxy.systems[session.destination] == nil then
    return {}
  end
  return Session.Way(session, Core.Query.Player(session.game).system, session.destination, session.safest)
end

-- The autopilot's turn, once a frame: when the ship has nothing to do,
-- it is sent through the next gate of the route. It undocks to set off,
-- and stops when it is there. Any order the pilot gives by hand takes
-- the ship back (Session.Order).
function Session.Autopilot(session: Session)
  if not session.autopilot then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  if session.destination == 0 or player.system == session.destination then
    if session.destination ~= 0 then
      Session.Say(session, `Autopilot: arrived in {player.systemName}`)
    end
    session.autopilot, session.destination = false, 0
    return
  end
  if #game.state.queue > 0 then
    return
  end
  local command: State.Command? = nil
  if player.docked ~= 0 then
    command = { kind = "Undock", actor = player.ship }
  else
    local ball = Core.Query.Ball(game, player.ship)
    if ball and ball.warp == nil and ball.intent == nil then
      local next = Session.Route(session)[2]
      for _, object in Core.Query.Objects(game, player.system) do
        if object.kind == "gate" and object.to == next then
          command = { kind = "Jump", actor = player.ship, target = object.id }
        end
      end
      if command == nil then
        session.autopilot = false
        Session.Say(session, "Autopilot: no gate leads that way")
      end
    end
  end
  if command then
    local ok, reason = Core.Submit(game, command)
    if not ok then
      session.autopilot = false
      Session.Say(session, `Autopilot: {tostring(reason)}`)
    end
  end
end

-- Give the player's ship an order. Returns whether it was accepted; if
-- not, the reason is shown. (An order given by hand takes the ship back
-- from the autopilot.)
function Session.Order(session: Session, kind: string, target: number?, range: number?): boolean
  session.autopilot = false
  if (kind == "WarpTo" or kind == "FleetWarp") and target then
    -- (a world or a sun is warped to from well off it: a distance asked
    -- for is that much farther off again)
    local body = Core.Query.Body(session.game, target)
    local standoff = if body then STANDOFF[body.kind] else nil
    if body and standoff then
      range = standoff * body.radius + (range or 0)
    end
  end
  local command: State.Command = { kind = kind, actor = session.game.state.player.ship, target = target, range = range }
  local ok, reason = Core.Submit(session.game, command)
  if not ok then
    Session.Say(session, `{kind}: {tostring(reason)}`)
  end
  return ok
end

-- Give any command; the player's ship is filled in as the actor.
function Session.Do(session: Session, command: State.Command): boolean
  command.actor = session.game.state.player.ship
  local ok, reason = Core.Submit(session.game, command)
  if not ok then
    Session.Say(session, `{command.kind}: {tostring(reason)}`)
  end
  return ok
end

-- Whether a command would be accepted now.
function Session.CanDo(session: Session, command: State.Command): (boolean, string?)
  command.actor = session.game.state.player.ship
  return Core.Validate(session.game, command)
end

-- Whether an order would be accepted now, and if not, why not.
function Session.Can(session: Session, kind: string, target: number?, range: number?): (boolean, string?)
  return Core.Validate(session.game, { kind = kind, actor = session.game.state.player.ship, target = target, range = range })
end

-- What a save says of itself without being opened: where the pilot was,
-- in what, with how much, how far into the game, and when it was made
-- (seconds since 1970; 0 if the save does not say).
export type SaveInfo = {
  slot: string, system: string, ship: string, docked: boolean, wallet: number, tick: number, time: number,
}

-- Save to save/<slot>/state.bin, by way of a temporary file so a crash
-- cannot leave half a save, with a few lines beside it (meta.txt) for
-- the list of saves to show. 'quiet' says nothing to the player.
function Session.Save(session: Session, slot: string, quiet: boolean?): boolean
  local dir = `{SAVE_DIR}/{slot}`
  if not (Host.MakeDir(SAVE_DIR) and Host.MakeDir(dir)) then
    return false
  end
  local data, length = Core.Save(session.game)
  local ok = Host.WriteFile(dir .. "/state.tmp", data, length) and Host.Rename(dir .. "/state.tmp", dir .. "/state.bin")
  if ok then
    local player = Core.Query.Player(session.game)
    local meta = `system={player.systemName}\nship={player.hull.name}\ndocked={if player.docked ~= 0 then 1 else 0}\n`
      .. `wallet={session.game.state.wallet}\ntick={session.game.state.tick}\ntime={math.floor(Host.Time())}\n`
    Host.WriteFile(dir .. "/meta.txt", meta)
  end
  if not quiet then
    Session.Say(session, if ok then `Saved to {dir}` else `Could not save to {dir}`)
  end
  return ok
end

-- The saves there are, the newest first.
function Session.Saves(): { SaveInfo }
  local found: { SaveInfo } = {}
  for _, name in Host.ListDir(SAVE_DIR) do
    if string.sub(name, -1) == "/" then
      local slot = string.sub(name, 1, -2)
      if Host.Exists(`{SAVE_DIR}/{slot}/state.bin`) then
        local info: SaveInfo = { slot = slot, system = "", ship = "", docked = false, wallet = 0, tick = 0, time = 0 }
        local meta = Host.ReadFile(`{SAVE_DIR}/{slot}/meta.txt`)
        if meta then
          for key: string, value: string in string.gmatch(buffer.tostring(meta), "(%w+)=([^\n]*)") :: any do
            if key == "system" then
              info.system = value
            elseif key == "ship" then
              info.ship = value
            elseif key == "docked" then
              info.docked = value == "1"
            elseif key == "wallet" then
              info.wallet = tonumber(value) or 0
            elseif key == "tick" then
              info.tick = tonumber(value) or 0
            elseif key == "time" then
              info.time = tonumber(value) or 0
            end
          end
        end
        table.insert(found, info)
      end
    end
  end
  table.sort(found, function(a: SaveInfo, b: SaveInfo): boolean
    if a.time ~= b.time then
      return a.time > b.time
    end
    return a.slot < b.slot
  end)
  return found
end

-- Throw a save away.
function Session.Delete(slot: string): boolean
  Host.Remove(`{SAVE_DIR}/{slot}/meta.txt`)
  return Host.Remove(`{SAVE_DIR}/{slot}/state.bin`)
end

-- The pilot's target (the project owner's, 2026-11-13: "you should be
-- able to lock multiple targets at once (ship class defines max, along
-- with skills), and then click to choose which one you are actively
-- targeting. The camera would track to the targeted one."). A ship has
-- as many things locked as its hull and its pilot's skill allow; one of
-- them is the pilot's target. It is the one they pick out: a locked
-- thing they select, by a click on it or on its panel in the row of
-- targets, or by a key. Until they pick, it is the first thing they
-- locked; and when it is locked no longer (destroyed, gone, let go) it
-- is the selected thing, if that is locked, else the one locked last.
-- Called once a frame; says what the target is now.
function Session.Aim(session: Session): number
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  if ball == nil then
    session.target, session.aimed, session.aimedAt = 0, {}, session.selected
    return 0
  end
  local now: { [number]: boolean } = {}
  local last, fresh = 0, 0
  for _, lock in ball.vitals.locks do
    now[lock.target] = true
    last = lock.target
    if not session.aimed[lock.target] then
      fresh = lock.target
    end
  end
  if not now[session.target] then
    session.target = 0
  end
  if session.selected ~= session.aimedAt and now[session.selected] then
    session.target = session.selected
  elseif session.target == 0 then
    session.target = if fresh ~= 0 then fresh elseif now[session.selected] then session.selected else last
  end
  session.aimed, session.aimedAt = now, session.selected
  return session.target
end

-- Replace the running game with a new one, of so many systems (three,
-- if nobody says).
function Session.Restart(session: Session, galaxySeed: number, historySeed: number, systems: number?)
  -- (a galaxy that has been going a while: its prices have come apart across the map)
  session.game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed, systems = systems, traffic = true,
    settled = Commerce.SETTLED, wars = true })
  session.selected = 0
  session.target, session.aimed, session.aimedAt = 0, {}, 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.destination, session.autopilot = 0, false
  session.clock.pending = 0
  session.clock.paused = false
  session.clock.scale = 1
  session.message = ""
end

-- When a save was made (seconds since 1970); 0 if it does not say.
local function savedAt(slot: string): number
  local meta = Host.ReadFile(`{SAVE_DIR}/{slot}/meta.txt`)
  local time = if meta then string.match(buffer.tostring(meta), "time=(%d+)") else nil
  return tonumber(time) or 0
end

-- Replace the running game with a save. Returns false if there is none
-- or it cannot be read.
--
-- The time since the save was made is given to the pilot's training
-- (Core.Away): 'away' says how long that is, for a script; without it,
-- it is the real time since, and none in a scripted run (which has to
-- play out the same every time).
function Session.Load(session: Session, slot: string, away: number?): boolean
  local data = Host.ReadFile(`{SAVE_DIR}/{slot}/state.bin`)
  if data == nil then
    Session.Say(session, `No save in {SAVE_DIR}/{slot}`)
    return false
  end
  local ok, loaded = pcall(Core.Load, data)
  if not ok then
    Session.Say(session, tostring(loaded))
    return false
  end
  session.game = loaded
  session.selected = 0
  session.target, session.aimed, session.aimedAt = 0, {}, 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.destination, session.autopilot = 0, false
  session.clock.pending = 0
  Session.Say(session, `Loaded {SAVE_DIR}/{slot}`)
  local made = savedAt(slot)
  local gone = away or (if Host.scripted or made == 0 then 0 else math.max(0, Host.Time() - made))
  if gone >= 1 then
    Core.Away(session.game, gone)
    for _, event in Core.TakeEvents(session.game) do
      table.insert(session.events, event)
      Session.Notice(session, event)
    end
  end
  return true
end

return Session
