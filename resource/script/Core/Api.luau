--!strict
-- The Core's front door. The view, the UI and the tests go through this
-- and nothing else:
--
--   local game = Core.New({ galaxySeed = 1, historySeed = 1 })
--   Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })
--   Core.Step(game)                      -- one tick
--   for _, event in Core.TakeEvents(game) do ... end
--   local data, length = Core.Save(game)
--
-- A Game is the state plus what is not state: the events of the ticks
-- since they were last taken. Commands are queued in the state and take
-- effect at the start of the next tick.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Assault = require("@lt/Core/Tactical/Assault")
local Batteries = require("@lt/Core/Tactical/Batteries")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Attributes = require("@lt/Core/Attributes")
local Drones = require("@lt/Core/Tactical/Drones")
local Dscan = require("@lt/Core/Tactical/Dscan")
local Factions = require("@lt/Core/Data/Factions")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Keeps = require("@lt/Core/Tactical/Keeps")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Careers = require("@lt/Core/Character/Careers")
local Contracts = require("@lt/Core/Assets/Contracts")
local Corporation = require("@lt/Core/Assets/Corporation")
local Guide = require("@lt/Core/Character/Guide")
local Hacking = require("@lt/Core/Tactical/Hacking")
local Hangar = require("@lt/Core/Assets/Hangar")
local Implanting = require("@lt/Core/Character/Implants")
local Boosters = require("@lt/Core/Data/Boosters")
local Boosting = require("@lt/Core/Character/Boosters")
local Implants = require("@lt/Core/Data/Implants")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Moons = require("@lt/Core/Data/Moons")
local Mining = require("@lt/Core/Tactical/Mining")
local Ores = require("@lt/Core/Data/Ores")
local Missions = require("@lt/Core/Assets/Missions")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Raids = require("@lt/Core/Tactical/Raids")
local Surges = require("@lt/Core/Tactical/Surges")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Colonies = require("@lt/Core/Assets/Colonies")
local Planets = require("@lt/Core/Data/Planets")
local Starbases = require("@lt/Core/Assets/Starbases")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Training = require("@lt/Core/Character/Training")
local Types = require("@lt/Core/Data/Types")
local Vapour = require("@lt/Core/Tactical/Vapour")

local Core = {}

export type Game = {
  state: State.State,
  events: { Space.Event },
}

export type Options = {
  galaxySeed: number,
  historySeed: number,
  systems: number?,   -- default 3
  peaceful: boolean?, -- no pirates; default false
  -- Other ships about (Tactical/Traffic); default false. The game turns
  -- it on. A test that is about one ship has the galaxy to itself.
  traffic: boolean?,
}

-- The shape of the state. Raise it, and add a migration, whenever a
-- change would make an old save unreadable.
Core.SAVE_VERSION = 72

-- MIGRATIONS[n] turns the state of a version n save into version n + 1.
-- Load applies them in turn, so a save from any version listed here
-- still opens.
-- Hulls that are gone, and the hull each has become: whatever a save has
-- of one, anywhere in it (a ship, a packed hull, a blueprint, an order,
-- a job), it has of the other.
local function rehulled(state: any, RENAMED: { [string]: string })
  local function renamed(value: any): any
    if type(value) ~= "string" then
      return value
    end
    local now = RENAMED[value]
    if now then
      return now
    elseif string.sub(value, 1, 10) == "blueprint." and RENAMED[string.sub(value, 11)] then
      return "blueprint." .. RENAMED[string.sub(value, 11)]
    end
    return value
  end
  local function walk(node: any)
    local moved: { [any]: any } = {}
    for key, value in node do
      if type(value) == "table" then
        walk(value)
      elseif type(value) == "string" then
        node[key] = renamed(value)
      end
      if renamed(key) ~= key then
        moved[key] = renamed(key)
      end
    end
    for key, now in moved do
      if node[now] == nil then
        node[now] = node[key]
      end
      node[key] = nil
    end
  end
  walk(state)
end

local MIGRATIONS: { [number]: (state: any) -> () } = {
  -- 9: a market keeps count of goods lost to piracy (none, in a station).
  [8] = function(state: any)
    for _, market in state.markets do
      market.lost = table.create(#market.classes, 0)
      for _, edge in market.edges do
        edge.loss = 0
      end
    end
  end,
  -- 10: the Kethri took lasers and armour and the Vessari missiles, so
  -- the Kethri's frigate is the Lancer (the same hull as before under
  -- another flag) and the missile frigate, which was the Kethri Spindle,
  -- is the Vessari Javelin. A Spindle in a save becomes a Javelin, and
  -- its blueprint likewise. (The Javelin has a mid slot fewer and a low
  -- slot more: a Spindle with every mid slot filled comes through with a
  -- module the fitting screen has no row for.)
  [9] = function(state: any)
    local renamed = { ["frigate.spindle"] = "frigate.javelin", ["blueprint.frigate.spindle"] = "blueprint.frigate.javelin" }
    local function walk(t: any)
      local moved: { any } = {}
      for key, value in t do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" and renamed[value] then
          t[key] = renamed[value]
        end
        if type(key) == "string" and renamed[key] then
          table.insert(moved, key)
        end
      end
      for _, key in moved do
        t[renamed[key]], t[key] = t[key], nil
      end
    end
    walk(state)
  end,
  -- 11: a wreck remembers what hull it was, for the view to draw it as
  -- that hull broken. One from before is drawn as plain wreckage.
  [10] = function(state: any)
    for _, wreck in state.wrecks do
      wreck.hull = wreck.hull or ""
    end
  end,
  -- 12: pilots can put up starbases. A save from before has none.
  [11] = function(state: any)
    state.starbases = state.starbases or {}
    state.starbaseIds = state.starbaseIds or {}
  end,
  -- 13: planets can be worked. A save from before has no colonies.
  [12] = function(state: any)
    state.colonies = state.colonies or {}
    state.colonyIds = state.colonyIds or {}
  end,
  -- 14: a system has a security, and a pirate's bounty is its own. The
  -- galaxy of an older save is given its securities, and its pirates
  -- the bounty they had by the old rule (a fifth of the hull's price).
  -- (Its belts are as they were described: the rare ores are in the
  -- lawless belts of a new game.)
  [13] = function(state: any)
    Galaxy.Claim(state.galaxy)
    for _, pilot in state.pilots do
      local ship = state.ships[pilot.ship]
      local hull = if ship then Ships.byId[ship.type] else nil
      pilot.bounty = pilot.bounty or (if hull then math.floor(hull.basePrice * 0.2) else 0)
      pilot.tags = pilot.tags or 1
    end
  end,
  -- 15: a system is somebody's, or nobody's, and its security follows
  -- from that. The galaxy of an older save is shared out as a new one's
  -- is. (The stations of a system far from the first homeworld become
  -- its own faction's.)
  [14] = function(state: any)
    Galaxy.Claim(state.galaxy)
  end,
  -- 16: there are other ships about, and a pilot can be marked for
  -- firing on them. A save from before has none, and nobody is marked.
  [15] = function(state: any)
    state.traffic = state.traffic or {}
    state.trafficIds = state.trafficIds or {}
    state.trafficDue = state.trafficDue or 0
    -- (a save from before was somebody's game, and a game has traffic)
    if state.trafficOn == nil then
      state.trafficOn = true
    end
    state.player.marked = state.player.marked or 0
  end,
  -- 17: blueprints can be researched. A save from before has learned
  -- nothing, and its jobs all build.
  [16] = function(state: any)
    state.research = state.research or {}
    for _, job in state.jobs do
      job.research = job.research or ""
    end
  end,
  -- 18: stations have jobs for a pilot, and a pilot has a standing with
  -- each faction. A save from before has none in hand and stands at 0.
  [17] = function(state: any)
    state.missions = state.missions or {}
    state.missionIds = state.missionIds or {}
    state.missionsTaken = state.missionsTaken or {}
    state.missionsDone = state.missionsDone or 0
    state.standings = state.standings or {}
  end,
  -- 19: systems have sites to find. A save from before has found none
  -- (and is given its first when the game goes on).
  [18] = function(state: any)
    state.sites = state.sites or {}
    state.siteIds = state.siteIds or {}
    state.sitesDue = state.sitesDue or {}
    state.sitesSeen = state.sitesSeen or {}
    state.scanReady = state.scanReady or 0
  end,
  -- 20: a ship can be held by another's entanglement projector or warp disruptor. No
  -- ship of a save from before is.
  [19] = function(state: any)
    for _, ball in state.balls do
      -- (the field was 'web' then: 43 gives it the name it has now)
      ball.vitals.web = ball.vitals.web or 1
      if ball.vitals.scrambled == nil then
        ball.vitals.scrambled = false
      end
    end
  end,
  -- 21: a wreck can be salvaged, once. No wreck of a save from before
  -- has been.
  [20] = function(state: any)
    for _, wreck in state.wrecks do
      if wreck.salvaged == nil then
        wreck.salvaged = false
      end
    end
  end,
  -- 22: a ship can be painted or dampened by another. No ship of a save
  -- from before is.
  [21] = function(state: any)
    for _, ball in state.balls do
      ball.vitals.paint = ball.vitals.paint or 1
      ball.vitals.damp = ball.vitals.damp or 1
    end
  end,
  -- 23: there are drones. A save from before has none out.
  [22] = function(state: any)
    state.drones = state.drones or {}
    state.droneIds = state.droneIds or {}
  end,
  -- 24: pilots can be hired to fly the player's other ships. A save from
  -- before has hired nobody, and nobody flies any ship but the player.
  [23] = function(state: any)
    state.fleet = state.fleet or {}
    state.fleetIds = state.fleetIds or {}
    state.hired = state.hired or {}
    state.hiredDay = state.hiredDay or 0
    for _, ship in state.ships do
      ship.pilot = ship.pilot or 0
    end
    if state.skills.leadership == nil then
      state.skills.leadership = 1
    end
  end,
  -- 25: a hired pilot can be set to mine a belt. None of a save from
  -- before has been.
  [24] = function(state: any)
    for _, wing in state.fleet do
      wing.post = wing.post or 0
      wing.base = wing.base or 0
      wing.hauled = wing.hauled or 0
    end
  end,
  -- 26: a pilot can mark places in space. A save from before has none.
  [25] = function(state: any)
    state.bookmarks = state.bookmarks or {}
    state.bookmarkIds = state.bookmarkIds or {}
  end,
  -- 27: there is a guide. A save from before has ticked nothing off
  -- (what was done before is done again soon enough).
  [26] = function(state: any)
    state.guide = state.guide or {}
  end,
  -- 28: the galaxy has regions and constellations. An older save's is
  -- given the ones it would have had.
  [27] = function(state: any)
    Galaxy.Regions(state.galaxy)
  end,
  -- 29: a pilot can have implants. One of a save from before has none.
  [28] = function(state: any)
    state.implants = state.implants or {}
  end,
  -- 30: jobs have agents and earn loyalty points, and lapse after three
  -- days. A job of a save from before is from nobody and earns none,
  -- and its three days begin now.
  [29] = function(state: any)
    state.loyalty = state.loyalty or {}
    for _, mission in state.missions do
      mission.agent = mission.agent or ""
      mission.loyalty = mission.loyalty or 0
      mission.taken = state.tick
    end
  end,
  -- 31: hired pilots learn. Those of a save from before have learned
  -- nothing yet.
  [30] = function(state: any)
    for _, wing in state.fleet do
      wing.experience = wing.experience or 0
    end
  end,
  -- 32: a den's stores may lead on to a stronghold. The sites of a save
  -- from before are none of them strongholds, and have led nowhere yet.
  [31] = function(state: any)
    for _, site in state.sites do
      site.depth = site.depth or 0
      if site.led == nil then
        site.led = false
      end
    end
  end,
  -- 41: a station's fifth agent has mining contracts. No agent of a
  -- save from before has given any.
  [40] = function(state: any)
    state.digs = state.digs or {}
  end,
  -- 50: a station's sixth agent has courier contracts. No agent of a
  -- save from before has given any.
  [49] = function(state: any)
    state.couriers = state.couriers or {}
  end,
  -- 59: a corporation keeps its books by head, and a tower keeps count
  -- of its running. A save from before has what was earned and spent
  -- under no head, and its towers begin their count now.
  -- 70: the Kethri's ships are the project owner's list of them, the
  -- last of the four human factions'. The hulls they had are gone, and
  -- each is the hull of their line that stands where it stood. (They
  -- build no cruiser, attack battlecruiser, dreadnought, siege
  -- dreadnought or supercarrier now: a cruiser of theirs is their
  -- battlecruiser, which is worth more and wants its own skill; the
  -- others their battlecruiser, their battleship and their carrier.)
  -- (And their colony ships roam: Tactical/Nomads.)
  -- 71: the second of the alien factions is the Nimia (Data/Factions),
  -- who were a stand-in called the Skarn until the project owner said
  -- who they are. Whatever a save has of the Skarn (whose a system is,
  -- what they think of the pilot, a ship of theirs about) it has of the
  -- Nimia; and their hulls are the Nimia's of the owner's list, each
  -- the one that stands where it stood (they build no attack
  -- battlecruiser and no dreadnought but the siege one).
  -- 72: stations have boards, where lots change hands by contract
  -- (Assets/Contracts). A save from before has nothing up on any.
  [71] = function(state: any)
    state.contracts = state.contracts or {}
    state.contractIds = state.contractIds or {}
    state.contractsTaken = state.contractsTaken or {}
    state.contractsHad = state.contractsHad or {}
  end,
  [70] = function(state: any)
    rehulled(state, {
      skarn = "nimia",
      ["frigate.stinger"] = "frigate.oon", ["destroyer.render"] = "destroyer.kri", ["cruiser.broodguard"] = "cruiser.hon",
      ["battleship.leviathan"] = "battleship.rru", ["industrial.gorger"] = "industrial.rikn",
      ["attackbattlecruiser.mauler"] = "battlecruiser.hoku", ["battlecruiser.carapace"] = "battlecruiser.hoku",
      ["carrier.broodmother"] = "carrier.takk", ["dreadnought.kraken"] = "siegedreadnought.zzk",
      ["siegedreadnought.devourer"] = "siegedreadnought.zzk", ["capitalindustrial.glutton"] = "capitalindustrial.zzna",
      ["supercarrier.hivequeen"] = "supercarrier.yuln",
    })
  end,
  [69] = function(state: any)
    state.nomads = state.nomads or {}
    rehulled(state, {
      ["frigate.lancer"] = "frigate.battleaxe", ["destroyer.gantry"] = "destroyer.sentry", ["cruiser.trellis"] = "battlecruiser.extremis",
      ["battleship.spire"] = "battleship.teardrop", ["industrial.lighter"] = "industrial.porter",
      ["attackbattlecruiser.stanchion"] = "battlecruiser.extremis", ["battlecruiser.buttress"] = "battlecruiser.extremis",
      ["carrier.concourse"] = "carrier.tennit", ["supercarrier.arcade"] = "carrier.tennit",
      ["dreadnought.colonnade"] = "battleship.teardrop", ["siegedreadnought.obelisk"] = "battleship.teardrop",
      ["capitalindustrial.derrick"] = "capitalindustrial.piton",
    })
  end,
  -- 69: the Orun's ships are the project owner's list of them
  -- (Data/Factions), as the Talmar's and the Vessari's became theirs.
  -- The hulls they had are gone, and each is the hull of their line
  -- that stands where it stood (they build no attack battlecruiser,
  -- dreadnought or supercarrier now: those are their battlecruiser,
  -- their siege dreadnought and their carrier), wherever a save has one.
  [68] = function(state: any)
    rehulled(state, {
      ["frigate.mastiff"] = "frigate.skinner", ["destroyer.boar"] = "destroyer.scythe", ["cruiser.aurochs"] = "cruiser.armer",
      ["battleship.mammoth"] = "battleship.claymore", ["industrial.ox"] = "industrial.pill",
      ["attackbattlecruiser.wolverine"] = "battlecruiser.zweihander", ["battlecruiser.bison"] = "battlecruiser.zweihander",
      ["carrier.roost"] = "carrier.katana", ["supercarrier.rookery"] = "carrier.katana",
      ["dreadnought.behemoth"] = "siegedreadnought.sword", ["siegedreadnought.tusker"] = "siegedreadnought.sword",
      ["capitalindustrial.dromedary"] = "capitalindustrial.stag",
    })
  end,
  -- 68: the map has a height (Describe/Galaxy): each system lies a
  -- little above or below its plane. A galaxy of a save from before is
  -- given the heights it would have had.
  [67] = function(state: any)
    if state.galaxy and state.galaxy.systems and state.galaxy.systems[1] and state.galaxy.systems[1].z == nil then
      Galaxy.Heights(state.galaxy)
    end
  end,
  -- 67: the Vessari's ships are the project owner's list of them
  -- (Data/Factions), as the Talmar's became theirs: the hulls they had
  -- are gone, and each is the hull of their line that stands where it
  -- stood, wherever a save has one.
  [66] = function(state: any)
    local RENAMED: { [string]: string } = {
      ["frigate.javelin"] = "frigate.akashi", ["destroyer.halberd"] = "destroyer.nozomi", ["cruiser.cuirass"] = "cruiser.ouyou",
      ["battleship.bastion"] = "battleship.owari", ["industrial.caravan"] = "industrial.mizumushi",
      ["attackbattlecruiser.glaive"] = "battlecruiser.naishou", ["battlecruiser.pavise"] = "battlecruiser.naishou",
      ["carrier.citadel"] = "carrier.azayake", ["supercarrier.stronghold"] = "carrier.azayake",
      ["dreadnought.rampart"] = "battleship.owari", ["siegedreadnought.trebuchet"] = "battleship.owari",
      ["capitalindustrial.emporium"] = "capitalindustrial.okami",
    }
    local function renamed(value: any): any
      if type(value) ~= "string" then
        return value
      end
      local now = RENAMED[value]
      if now then
        return now
      elseif string.sub(value, 1, 10) == "blueprint." and RENAMED[string.sub(value, 11)] then
        return "blueprint." .. RENAMED[string.sub(value, 11)]
      end
      return value
    end
    local function walk(node: any)
      local moved: { [any]: any } = {}
      for key, value in node do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" then
          node[key] = renamed(value)
        end
        if renamed(key) ~= key then
          moved[key] = renamed(key)
        end
      end
      for key, now in moved do
        if node[now] == nil then
          node[now] = node[key]
        end
        node[key] = nil
      end
    end
    walk(state)
  end,
  -- 66: a ship has no "II" (the owner's ruling: a tech 2 ship is a hull
  -- of its own, where a faction's line names one). What a save has of
  -- the tech 2 make of a hull that every hull had, it has of the plain
  -- hull: a ship of one is the plain ship, with what was fitted to it in
  -- its hold (the plain hull has not the slots or the fitting for it
  -- all), and a blueprint of one is the plain hull's.
  [65] = function(state: any)
    local function plain(value: any): any
      if type(value) ~= "string" or string.sub(value, -3) ~= ".ii" then
        return value
      end
      local base = string.sub(value, 1, -4)
      local named = if string.sub(base, 1, 10) == "blueprint." then string.sub(base, 11) else base
      -- (a hull's, by the class its name begins with, and not a drone's
      -- or a module's: those have their "II" still. By the name, and not
      -- by the hulls there are now: a hull of then may have another name
      -- since, which the migrations after this one give it.)
      local class = string.match(named, "^(%a+)%.")
      local HULLS = { frigate = true, destroyer = true, cruiser = true, battlecruiser = true, attackbattlecruiser = true,
        battleship = true, industrial = true, barge = true, freighter = true, capitalindustrial = true }
      return if class and HULLS[class] and Ships.byId[value] == nil then base else value
    end
    local refitted: { [number]: boolean } = {}
    for id, ship in state.ships or {} do
      if plain(ship.type) ~= ship.type then
        refitted[id] = true
      end
    end
    for _, item in state.items or {} do
      if refitted[item.holder] and (item.place == "high" or item.place == "mid" or item.place == "low") then
        item.place, item.slot, item.charge, item.rounds = "cargo", 0, "", 0
      end
    end
    local function walk(node: any)
      local moved: { [any]: any } = {}
      for key, value in node do
        if type(value) == "table" then
          walk(value)
        elseif plain(value) ~= value then
          node[key] = plain(value)
        end
        if plain(key) ~= key then
          moved[key] = plain(key)
        end
      end
      for key, now in moved do
        if node[now] == nil then
          node[now] = node[key]
        end
        node[key] = nil
      end
    end
    walk(state)
  end,
  -- 65: the Talmar's ships were gone through by the project owner
  -- (Data/Factions): the hulls they had are gone, and each is the hull
  -- of their new line that stands where it stood. (And the hulls of the
  -- classes above the battleship that were theirs for a day under names
  -- of mine.) Whatever a save has of one, anywhere in it (a ship, a
  -- packed hull, a blueprint, an order, a job), it has of the other.
  [64] = function(state: any)
    local RENAMED: { [string]: string } = {
      ["frigate.harrier"] = "frigate.carvarro", ["destroyer.sabre"] = "destroyer.meseolo", ["cruiser.falchion"] = "cruiser.paestro",
      ["battleship.claymore"] = "battleship.phaeto", ["industrial.packet"] = "industrial.sunfish",
      ["frigate.harrier.ii"] = "frigate.carvarro.ii", ["destroyer.sabre.ii"] = "destroyer.meseolo.ii",
      ["cruiser.falchion.ii"] = "cruiser.paestro.ii", ["battleship.claymore.ii"] = "battleship.phaeto.ii",
      ["industrial.packet.ii"] = "industrial.tarantula",
      ["attackbattlecruiser.estoc"] = "battlecruiser.sopholto", ["attackbattlecruiser.estoc.ii"] = "battlecruiser.sopholto.ii",
      ["battlecruiser.scimitar"] = "battlecruiser.sopholto", ["battlecruiser.scimitar.ii"] = "battlecruiser.sopholto.ii",
      ["carrier.scabbard"] = "carrier.scoppo", ["dreadnought.zweihander"] = "dreadnought.concorso",
      ["siegedreadnought.flamberge"] = "dreadnought.concorso", ["capitalindustrial.argosy"] = "capitalindustrial.jaguar",
      ["supercarrier.armoury"] = "supercarrier.nullo", ["siegedreadnought.rhino"] = "siegedreadnought.tusker",
    }
    local function renamed(value: any): any
      if type(value) ~= "string" then
        return value
      end
      local now = RENAMED[value]
      if now then
        return now
      elseif string.sub(value, 1, 10) == "blueprint." and RENAMED[string.sub(value, 11)] then
        return "blueprint." .. RENAMED[string.sub(value, 11)]
      end
      return value
    end
    local function walk(node: any)
      local moved: { [any]: any } = {}
      for key, value in node do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" then
          node[key] = renamed(value)
        end
        if renamed(key) ~= key then
          moved[key] = renamed(key)
        end
      end
      for key, now in moved do
        -- (two old hulls that are one new one: what was kept by either is kept, the first found)
        if node[now] == nil then
          node[now] = node[key]
        end
        node[key] = nil
      end
    end
    walk(state)
  end,
  -- 64: a tower can have a reactor, which makes a composite of what
  -- drills bring up. One of a save from before is making nothing.
  [63] = function(state: any)
    for _, starbase in state.starbases do
      starbase.reaction = starbase.reaction or ""
      starbase.reacted = starbase.reacted or state.tick
      starbase.composed = starbase.composed or 0
      starbase.starved = starbase.starved or false
    end
  end,
  -- 63: pirates hold the rarest moons where nobody keeps order, with
  -- towers of their own. A save from before has none up yet: they are
  -- put up as the pilot comes to each system again.
  [62] = function(state: any)
    state.keeps = state.keeps or {}
    state.keepIds = state.keepIds or {}
    state.keepsSeen = state.keepsSeen or {}
  end,
  -- 62: a tower can be shot at, seals itself and can be lost. One of a
  -- save from before has nothing to seal with and nobody after it, and
  -- is given what stands for it under fire as the game goes on.
  [61] = function(state: any)
    for _, starbase in state.starbases do
      starbase.core = starbase.core or 0
      starbase.charges = starbase.charges or 0
      starbase.sealed = starbase.sealed or 0
      starbase.siege = starbase.siege or 0
    end
  end,
  -- 61: a hauler's round can carry to several stations. None of a save
  -- from before does.
  [60] = function(state: any)
    for _, wing in state.fleet do
      wing.drops = wing.drops or {}
      wing.turn = wing.turn or 0
    end
  end,
  -- 60: a hired pilot has a loyalty. Those of a save from before stand
  -- where one newly signed on does.
  [59] = function(state: any)
    for _, wing in state.fleet do
      wing.loyalty = wing.loyalty or 40
    end
  end,
  [58] = function(state: any)
    state.corporation.books = state.corporation.books or {}
    for _, starbase in state.starbases do
      starbase.used = starbase.used or 0
      starbase.raised = starbase.raised or 0
      starbase.robbed = starbase.robbed or 0
    end
  end,
  -- 58: a station's seventh agent has defence jobs. No agent of a save
  -- from before has given any.
  [57] = function(state: any)
    state.holds = state.holds or {}
  end,
  -- 57: a hired pilot can be set to keep a thing in stock. Nobody of a
  -- save from before has been.
  [56] = function(state: any)
    for _, wing in state.fleet do
      wing.keep = wing.keep or 0
      wing.retry = wing.retry or 0
    end
  end,
  -- 56: a lesson's kit is handed over again, once, to a pilot who has
  -- lost it. Nobody of a save from before has asked.
  [55] = function(state: any)
    for _, career in state.careers do
      if career.again == nil then
        career.again = false
      end
    end
  end,
  -- 55: pirates mass in a system now and then. A save from before has
  -- had none, and the first comes in its time.
  [54] = function(state: any)
    state.surge = state.surge or { system = 0, ends = 0, next = state.tick + 3600, kills = 0, count = 0 }
  end,
  -- 54: a booster sits badly only some of the time. One at work in a
  -- save from before did, as they all did.
  [53] = function(state: any)
    for _, boosted in state.boosters do
      if boosted.wrong == nil then
        boosted.wrong = true
      end
    end
  end,
  -- 53: pirates raid a pilot's tower where order is thin. Nobody has
  -- raided one of a save from before, and the first comes in its time.
  [52] = function(state: any)
    for _, starbase in state.starbases do
      starbase.raid = starbase.raid or 0
      starbase.raids = starbase.raids or 0
    end
  end,
  -- 52: a tower can drill its moon. One of a save from before has not
  -- begun.
  -- (And Anchoring is a skill, which a pilot has from the start and
  -- one of a save from before has at nothing: the towers they have,
  -- they keep.)
  [51] = function(state: any)
    for _, starbase in state.starbases do
      starbase.drilled = starbase.drilled or state.tick
    end
    if state.skills.anchoring == nil then
      state.skills.anchoring = 0
    end
  end,
  -- 51: a hired pilot can be sent to buy. Nobody of a save from before
  -- has been.
  [50] = function(state: any)
    for _, wing in state.fleet do
      wing.want = wing.want or ""
      wing.need = wing.need or 0
      wing.limit = wing.limit or 0
    end
  end,
  -- 49: a haul can be a round of several stations. One of a save from
  -- before collects at the one station it did.
  [48] = function(state: any)
    for _, wing in state.fleet do
      wing.stops = wing.stops or (if wing.order == "haul" then { wing.post } else {})
      wing.leg = wing.leg or 0
    end
  end,
  -- 48: a rig is made for a size of hull. The rigs there were are the
  -- small ones now. One worked into a bigger hull in a save from before
  -- is the rig of that hull's size from now on: nobody loses what they
  -- had fitted.
  [47] = function(state: any)
    for _, item in state.items do
      local ship = state.ships[item.holder]
      local hull = if ship then Ships.byId[ship.type] else nil
      if item.place == "rig" and item.slot > 0 and hull and Modules.byId[item.type] then
        local size = Ships.RigSize(hull)
        local sized = item.type .. (if size == 2 then ".medium" elseif size == 3 then ".large" else "")
        if Modules.byId[sized] then
          item.type = sized
        end
      end
    end
  end,
  -- 47: an agent has a regard of their own for the pilot. In a save from
  -- before, nobody has any, and a job in hand is from nobody in
  -- particular.
  [46] = function(state: any)
    state.regard = state.regard or {}
    for _, mission in state.missions do
      mission.slot = mission.slot or 0
    end
  end,
  -- 46: a pilot takes boosters, and there are vaults, whose lock is on a
  -- clock. In a save from before, no booster is at work, every sealed
  -- thing is a hold, and a hack under way is not on a clock.
  [45] = function(state: any)
    state.boosters = state.boosters or {}
    for _, wreck in state.wrecks do
      wreck.lock = wreck.lock or ""
    end
    if state.hack then
      state.hack.ends = state.hack.ends or 0
    end
  end,
  -- 45: a pilot may found a corporation. In a save from before, nobody has.
  [44] = function(state: any)
    state.corporation = state.corporation or Corporation.None()
  end,
  -- 44: there are career agents. A save from before has begun with none
  -- of them.
  [43] = function(state: any)
    state.careers = state.careers or {}
  end,
  -- 43: the module that slows another ship is the Gravitic Entanglement
  -- Projector, and what it does is to entangle. A save from before has
  -- it under its old id, and each ship's share of its speed under the
  -- old name of that.
  [42] = function(state: any)
    local OLD, NEW = "web.stasis", "projector.entanglement"
    local function walk(tab: any)
      local keys: { string } = {}
      for key, value in tab do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" and string.find(value, OLD, 1, true) then
          tab[key] = (string.gsub(value, "web%.stasis", NEW))
        end
        if type(key) == "string" and string.find(key, OLD, 1, true) then
          table.insert(keys, key)
        end
      end
      table.sort(keys)
      for _, key in keys do
        local to = (string.gsub(key, "web%.stasis", NEW))
        local had, has = tab[key], tab[to]
        tab[key] = nil
        tab[to] = if type(had) == "number" and type(has) == "number" then had + has elseif has ~= nil then has else had
      end
      -- (a ship's vitals: the share of its speed it is left with)
      if type(tab.web) == "number" and tab.scrambled ~= nil then
        tab.entangle, tab.web = tab.web, nil
      end
    end
    for name, part in state do
      if name ~= "markets" and name ~= "galaxy" and name ~= "systems" and type(part) == "table" then
        walk(part)
      end
    end
  end,
  -- 42: the Kethri are nomads. They build no towers, and where they had
  -- a station they have a colony ship. In a save from before, a Kethri
  -- tower (in a hold, in a job, anchored at a moon) is a Vessari one of
  -- its size, which is the same but for whose it is; and the stations
  -- among the Kethri, in the systems that have been seen, are colony
  -- ships. (The markets drop what there no longer is by themselves:
  -- Market.Reconcile.)
  [41] = function(state: any)
    local OLD, NEW = "tower.kethri.", "tower.vessari."
    local function walk(tab: any)
      local keys: { string } = {}
      for key, value in tab do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" and string.find(value, OLD, 1, true) then
          tab[key] = (string.gsub(value, "tower%.kethri%.", NEW))
        end
        if type(key) == "string" and string.find(key, OLD, 1, true) then
          table.insert(keys, key)
        end
      end
      table.sort(keys)
      for _, key in keys do
        local to = (string.gsub(key, "tower%.kethri%.", NEW))
        local had, has = tab[key], tab[to]
        tab[key] = nil
        tab[to] = if type(had) == "number" and type(has) == "number" then had + has elseif has ~= nil then has else had
      end
    end
    for name, part in state do
      if name ~= "markets" and name ~= "galaxy" and name ~= "systems" and type(part) == "table" then
        walk(part)
      end
    end
    for id, description in state.systems do
      local ship = Structures.ColonyShip(state.galaxy.systems[id].nearest)
      if ship then
        for _, object in description.objects do
          if object.kind == "station" and state.starbases[object.id] == nil then
            local host, number = string.match(object.name, "^(.*) %- .- (%d+)$")
            if host then
              object.name = `{host} - Colony ship {number}`
            end
            object.variety, object.radius = System.COLONY_SHIP, ship.length / 2
          end
        end
      end
    end
  end,
  -- 40: a hired pilot can be set to patrol a place or to guard another
  -- pilot, and says when they are attacked with the player elsewhere.
  -- The pilots of a save from before guard nobody.
  [39] = function(state: any)
    for _, wing in state.fleet do
      wing.ward = wing.ward or 0
      if wing.alarm == nil then
        wing.alarm = false
      end
    end
  end,
  -- 39: a hold's lock is a matrix of codes and keys to find in it, not
  -- a board of nodes. A hack that was under way in a save from before
  -- is dropped: the hold is as sealed as it was.
  [38] = function(state: any)
    state.hack = nil
  end,
  -- 38: a camp can be of more than one room, and an assault can be to
  -- destroy its chief or to bring back what it took. The assaults of a
  -- save from before are on camps of one room, to be cleared.
  [37] = function(state: any)
    for _, mission in state.missions do
      local assault = mission.kind == "assault"
      mission.rooms = mission.rooms or (if assault and mission.site ~= 0 then { mission.site } else {})
      mission.ends = mission.ends or (if assault then { #mission.waves } else {})
      mission.aim = mission.aim or (if assault then "clear" else "")
      mission.mark = mission.mark or 0
    end
  end,
  -- 37: a station's fourth agent has assaults on pirate camps. The jobs
  -- of a save from before are none of them that, and no agent has given
  -- any.
  [36] = function(state: any)
    state.assaults = state.assaults or {}
    for _, mission in state.missions do
      mission.level = mission.level or 0
      mission.waves = mission.waves or {}
      mission.wave = mission.wave or 0
      mission.site = mission.site or 0
    end
  end,
  -- 36: a hired pilot can be set to haul, and to sell what they bring
  -- in. The pilots of a save from before carry nothing and sell nothing.
  [35] = function(state: any)
    for _, wing in state.fleet do
      wing.cargo = wing.cargo or ""
      wing.earned = wing.earned or 0
      if wing.sell == nil then
        wing.sell = false
      end
    end
  end,
  -- 35: a derelict's hold is sealed until it is hacked. The hulls of a
  -- save from before are as open as they were.
  [34] = function(state: any)
    for _, wreck in state.wrecks do
      if wreck.locked == nil then
        wreck.locked = false
      end
    end
  end,
  -- 34: there are scan probes. A save from before has none out. (Its
  -- derelicts half found stay as far found as they were.)
  [33] = function(state: any)
    state.probes = state.probes or {}
    state.probeIds = state.probeIds or {}
  end,
  -- 33: a ship has a drone bay, and its drones are launched from there.
  -- The drones in the hold of a ship of a save from before are put in
  -- its bay, as many as it has room for.
  [32] = function(state: any)
    local used: { [number]: number } = {}
    for _, id in state.itemIds do
      local item = state.items[id]
      local ship = state.ships[item.holder]
      local hull = if ship then Ships.byId[ship.type] else nil
      local info = Types.Get(item.type)
      if hull and info and info.category == "drone" and item.place == "cargo" then
        local room = (hull.bay or 0) - (used[ship.id] or 0)
        if item.quantity * info.volume <= room + 1e-9 then
          item.place = "dronebay"
          used[ship.id] = (used[ship.id] or 0) + item.quantity * info.volume
        end
      end
    end
  end,
}

-- A new game: a galaxy, and the player's first ship docked at a station
-- in system 1.
function Core.New(options: Options): Game
  local galaxy = Galaxy.Describe(options.galaxySeed, options.systems or 3)
  local state: State.State = {
    galaxySeed = options.galaxySeed,
    historySeed = options.historySeed,
    tick = 0,
    nextId = Constants.FIRST_DYNAMIC_ID,
    galaxy = galaxy,
    systems = {},
    ships = {},
    shipIds = {},
    items = {},
    itemIds = {},
    skills = Skills.Starting(),
    training = {},
    trainingStarted = 0,
    jobs = {},
    research = {},
    missions = {},
    missionIds = {},
    missionsTaken = {},
    missionsDone = 0,
    assaults = {},
    digs = {},
    couriers = {},
    holds = {},
    standings = {},
    loyalty = {},
    regard = {},
    sites = {},
    siteIds = {},
    sitesDue = {},
    sitesSeen = {},
    scanReady = 0,
    probes = {},
    probeIds = {},
    drones = {},
    droneIds = {},
    fleet = {},
    fleetIds = {},
    hired = {},
    hiredDay = 0,
    bookmarks = {},
    bookmarkIds = {},
    guide = {},
    careers = {},
    corporation = Corporation.None(),
    implants = {},
    boosters = {},
    jobIds = {},
    wallet = 0,
    journal = {},
    markets = {},
    marketIds = {},
    orders = {},
    orderIds = {},
    contracts = {}, contractIds = {}, contractsTaken = {}, contractsHad = {},
    trades = {},
    starbases = {},
    starbaseIds = {},
    keeps = {}, keepIds = {}, keepsSeen = {},
    colonies = {},
    colonyIds = {},
    balls = {},
    ballIds = {},
    missiles = {},
    wrecks = {},
    wreckIds = {},
    pilots = {},
    pilotIds = {},
    spawned = {},
    surge = { system = 0, ends = 0, next = 0, kills = 0, count = 0 },
    peaceful = options.peaceful == true,
    rocks = {},
    rockIds = {},
    grids = {},
    gridIds = {},
    player = { ship = 0, home = 0, marked = 0 },
    traffic = {},
    trafficIds = {},
    trafficDue = 0,
    nomads = {},
    trafficOn = options.traffic == true,
    queue = {},
  }
  -- (the starter station: the one that has a module for everything)
  local home = Space.Object(state, Stations.Starter(state))
  assert(home, "the first system has no station")
  local ship = Space.NewShip(state, "frigate.courier", "Courier", "player", home.id)
  state.player.ship = ship.id
  state.player.home = home.id
  state.wallet = 5000
  state.surge = Surges.None(state)

  -- A starter fit and a few things to try in the hangar: some of them
  -- need a skill trained first, and the blueprint needs minerals.
  Items.Equip(state, ship.id, "autocannon.small", "ammo.emp")
  Items.Equip(state, ship.id, "autocannon.small", "ammo.emp")
  for _, kit in { { "ammo.emp", 600 }, { "ammo.fusion", 400 }, { "shield.extender.small", 1 }, { "afterburner.1mn", 1 },
    { "armor.repairer.small", 1 }, { "laser.pulse.small", 1 }, { "crystal.multifrequency", 1 },
    { "miner.small", 1 }, { "blueprint.ammo.emp", 1 } } :: { { any } } do
    Items.Add(state, kit[1], kit[2], home.id, "hangar")
  end
  return { state = state, events = {} }
end

-- Which module carries out a kind of command.
local ASSET_COMMANDS = { Fit = true, Unfit = true, LoadCharge = true, MoveItems = true }
local COMBAT_COMMANDS = { LockTarget = true, UnlockTarget = true, ActivateModule = true, DeactivateModule = true,
  Cloak = true, Uncloak = true }
local AFTERMATH_COMMANDS = { Loot = true, Repair = true }
local INDUSTRY_COMMANDS = { Reprocess = true, StartJob = true, StartResearch = true, CancelJob = true }
local TRAINING_COMMANDS = { LearnSkill = true, TrainSkill = true, CancelTraining = true }
local MARKET_COMMANDS = { BuyNow = true, SellNow = true, PlaceOrder = true, CancelOrder = true, ModifyOrder = true }
local CONTRACT_COMMANDS = { AcceptContract = true, FillContract = true, ListContract = true, CancelContract = true }
local HANGAR_COMMANDS = { Assemble = true, BoardShip = true, SetHome = true }
local STARBASE_COMMANDS = { AnchorTower = true, Fuel = true, AnchorModule = true, UnanchorModule = true, UnanchorTower = true,
  SetReaction = true }
local SITE_COMMANDS = { Scan = true, LaunchProbe = true, RecallProbes = true }
local HACK_COMMANDS = { StartHack = true, HackNode = true, AbandonHack = true }
local DRONE_COMMANDS = { LaunchDrones = true, RecallDrones = true, EngageDrones = true }
local JUMP_COMMANDS = { JumpDrive = true }
local IMPLANT_COMMANDS = { PlugImplant = true, UnplugImplant = true }
local FLEET_COMMANDS = { HirePilot = true, AssignShip = true, DismissPilot = true, FleetOrder = true }
local MISSION_COMMANDS = { AcceptMission = true, CompleteMission = true, AbandonMission = true, RedeemLoyalty = true }
local CAREER_COMMANDS = { AcceptLesson = true, CompleteLesson = true, ReplaceKit = true }
local CORPORATION_COMMANDS = { FoundCorporation = true, CorporationDeposit = true, CorporationWithdraw = true }
local BOOSTER_COMMANDS = { TakeBooster = true }
local COLONY_COMMANDS = { DeployColony = true, BuildFacility = true, RemoveFacility = true, StartExtraction = true, Export = true }

local function validate(state: State.State, command: State.Command): (boolean, string?)
  -- (first, whether the station it is given at has the module for it)
  local served, lacking = Stations.Validate(state, command)
  if not served then
    return false, lacking
  end
  if ASSET_COMMANDS[command.kind] then
    return Items.Validate(state, command)
  elseif COMBAT_COMMANDS[command.kind] then
    return Combat.Validate(state, command)
  elseif AFTERMATH_COMMANDS[command.kind] then
    return Aftermath.Validate(state, command)
  elseif INDUSTRY_COMMANDS[command.kind] then
    return Industry.Validate(state, command)
  elseif MARKET_COMMANDS[command.kind] then
    return Market.Validate(state, command)
  elseif CONTRACT_COMMANDS[command.kind] then
    return Contracts.Validate(state, command)
  elseif HANGAR_COMMANDS[command.kind] then
    return Hangar.Validate(state, command)
  elseif STARBASE_COMMANDS[command.kind] then
    return Starbases.Validate(state, command)
  elseif COLONY_COMMANDS[command.kind] then
    return Colonies.Validate(state, command)
  elseif MISSION_COMMANDS[command.kind] then
    return Missions.Validate(state, command)
  elseif CAREER_COMMANDS[command.kind] then
    return Careers.Validate(state, command)
  elseif CORPORATION_COMMANDS[command.kind] then
    return Corporation.Validate(state, command)
  elseif SITE_COMMANDS[command.kind] then
    return Sites.Validate(state, command)
  elseif DRONE_COMMANDS[command.kind] then
    return Drones.Validate(state, command)
  elseif JUMP_COMMANDS[command.kind] then
    return Jumping.Validate(state, command)
  elseif FLEET_COMMANDS[command.kind] then
    return Fleet.Validate(state, command)
  elseif IMPLANT_COMMANDS[command.kind] then
    return Implanting.Validate(state, command)
  elseif BOOSTER_COMMANDS[command.kind] then
    return Boosting.Validate(state, command)
  elseif HACK_COMMANDS[command.kind] then
    return Hacking.Validate(state, command)
  elseif TRAINING_COMMANDS[command.kind] then
    return Training.Validate(state, command)
  end
  local ok, why = Space.Validate(state, command)
  -- (through a camp's gate, only when the camp says it is open: Tactical/Assault)
  if ok and command.kind == "Jump" then
    local gate = Space.Object(state, command.target or 0)
    if gate and gate.variety == Assault.GATE then
      return Assault.Passable(state, gate)
    end
  end
  return ok, why
end

-- Whether a command could be carried out now, and if not, why not. Does
-- not change anything; the UI uses it to grey out actions.
function Core.Validate(game: Game, command: State.Command): (boolean, string?)
  return validate(game.state, command)
end

-- Queue a command for the next tick. Returns false and a reason if it
-- cannot be carried out now (it is then not queued).
function Core.Submit(game: Game, command: State.Command): (boolean, string?)
  local ok, reason = validate(game.state, command)
  if ok then
    table.insert(game.state.queue, command)
  end
  return ok, reason
end

-- Advance one tick: fly every ship through the second that just passed,
-- resolve the fighting of that second (Tactical/Combat) and what follows
-- from it (Tactical/Aftermath), apply the queued commands in order, let
-- the pirates give theirs, then steer every ship for the second to come
-- (Tactical/Space). A queued command that has stopped
-- being valid (an earlier one docked the ship, say) is dropped with a
-- CommandRejected event.
function Core.Step(game: Game)
  local state = game.state
  state.tick += 1
  local first = #game.events + 1
  Space.Integrate(state, game.events)
  -- (a hull that mends by itself mends in a hangar too)
  Vitals.Mend(state)
  local killers = Combat.Step(state, game.events, Batteries.Fire(state, game.events))
  for _, id in table.clone(state.ballIds) do
    local by = killers[id]
    if by then
      -- (what a drone destroys is its owner's doing, and what a hired
      -- pilot destroys their employer's)
      local killer = state.ships[by]
      local ours = killer ~= nil and killer.owner == "player"
      local ball, victim = state.balls[id], state.pilots[id]
      local system, grid, bounty = ball.system, ball.grid, if victim and state.ships[id].owner == "pirates" then victim.bounty else 0
      Aftermath.Destroy(state, id, if ours then state.player.ship else by, game.events)
      -- (and the hired pilots who were there learn from it: Tactical/Fleet)
      if ours and bounty > 0 then
        Fleet.Credit(state, system, grid, bounty, game.events)
      end
    end
  end
  local queue = state.queue
  state.queue = {}
  for _, command in queue do
    local ok, reason = validate(state, command)
    if ok and ASSET_COMMANDS[command.kind] then
      Items.Apply(state, command, game.events)
    elseif ok and COMBAT_COMMANDS[command.kind] then
      Combat.Apply(state, command, game.events)
    elseif ok and AFTERMATH_COMMANDS[command.kind] then
      Aftermath.Apply(state, command, game.events)
    elseif ok and INDUSTRY_COMMANDS[command.kind] then
      Industry.Apply(state, command, game.events)
    elseif ok and MARKET_COMMANDS[command.kind] then
      Market.Apply(state, command, game.events)
    elseif ok and CONTRACT_COMMANDS[command.kind] then
      Contracts.Apply(state, command, game.events)
    elseif ok and HANGAR_COMMANDS[command.kind] then
      Hangar.Apply(state, command, game.events)
    elseif ok and STARBASE_COMMANDS[command.kind] then
      Starbases.Apply(state, command, game.events)
    elseif ok and COLONY_COMMANDS[command.kind] then
      Colonies.Apply(state, command, game.events)
    elseif ok and MISSION_COMMANDS[command.kind] then
      Missions.Apply(state, command, game.events)
    elseif ok and CAREER_COMMANDS[command.kind] then
      Careers.Apply(state, command, game.events)
    elseif ok and CORPORATION_COMMANDS[command.kind] then
      Corporation.Apply(state, command, game.events)
    elseif ok and SITE_COMMANDS[command.kind] then
      Sites.Apply(state, command, game.events)
    elseif ok and DRONE_COMMANDS[command.kind] then
      Drones.Apply(state, command, game.events)
    elseif ok and JUMP_COMMANDS[command.kind] then
      Jumping.Apply(state, command, game.events)
    elseif ok and FLEET_COMMANDS[command.kind] then
      Fleet.Apply(state, command, game.events)
    elseif ok and IMPLANT_COMMANDS[command.kind] then
      Implanting.Apply(state, command, game.events)
    elseif ok and BOOSTER_COMMANDS[command.kind] then
      Boosting.Apply(state, command, game.events)
    elseif ok and HACK_COMMANDS[command.kind] then
      Hacking.Apply(state, command, game.events)
    elseif ok and TRAINING_COMMANDS[command.kind] then
      Training.Apply(state, command, game.events)
    elseif ok then
      Space.Apply(state, command, game.events)
    else
      table.insert(game.events, { kind = "CommandRejected", command = command.kind, actor = command.actor, reason = reason })
    end
  end
  Boosting.Step(state, game.events)
  Sites.Step(state, game.events)
  Hacking.Step(state, game.events)
  Missions.Step(state, game.events)
  Standings.Step(state)
  Assault.Step(state, game.events)
  Surges.Step(state, game.events)
  Pirates.Populate(state, game.events)
  -- (a pilot docked in a colony ship of the nomads goes where it goes:
  -- it has gone on to its next system, and they are there with it)
  local berth = state.ships[state.player.ship]
  local carrier = if berth and berth.docked ~= 0 then Nomads.FleetOf(state.galaxy, berth.docked) else nil
  if carrier then
    local now, from = Nomads.At(carrier, state.tick)
    -- (and the system they are in is one that has been seen, whether or
    -- not they have ever flown into it)
    Space.Describe(state, now)
    if state.tick % Nomads.STAY == 0 and now ~= from then
      table.insert(game.events, { kind = "ColonyShipMoved", station = berth.docked, name = carrier.name, from = from, to = now })
    end
  end
  Traffic.Step(state, game.events)
  Pirates.Think(state, game.events)
  Drones.Step(state, game.events)
  Fleet.Step(state, game.events)
  Space.Decide(state, game.events)
  Aftermath.Step(state, game.events)
  Mining.Step(state)
  Market.Step(state, game.events)
  Contracts.Step(state, game.events)
  Starbases.Step(state, game.events)
  Raids.Step(state, game.events)
  Keeps.Step(state, game.events)
  Colonies.Step(state, game.events)
  Industry.Step(state, game.events)
  Training.Step(state, game.events)
  Guide.Step(state, game.events, first)
  Careers.Step(state, game.events, first)
end

-- The events since the last call, oldest first.
-- The pilot has been away so many seconds, with the game not running:
-- their training has gone on for that long (Character/Training), and
-- nothing else has moved. Returns how many levels it finished.
function Core.Away(game: Game, seconds: number): number
  local trained = Training.Credit(game.state, seconds, game.events)
  table.insert(game.events, { kind = "TrainingCredited", seconds = seconds, trained = trained, queued = #game.state.training })
  return trained
end

function Core.TakeEvents(game: Game): { Space.Event }
  local events = game.events
  game.events = {}
  return events
end

-- ---------------------------------------------------------------------
-- Saving

-- The game as bytes: a buffer and how much of it is used.
function Core.Save(game: Game): (buffer, number)
  return Codec.Encode({ format = "ltheory-eevning save", saveVersion = Core.SAVE_VERSION, state = game.state })
end

-- A game from bytes written by Save. Raises if they are not a save this
-- version can read.
function Core.Load(data: buffer, length: number?): Game
  local file = Codec.Decode(data, length)
  if type(file) ~= "table" or file.format ~= "ltheory-eevning save" then
    error("Core.Load: this is not a save file", 0)
  end
  local version = file.saveVersion
  while type(version) == "number" and version < Core.SAVE_VERSION and MIGRATIONS[version] do
    MIGRATIONS[version](file.state)
    version += 1
  end
  if version ~= Core.SAVE_VERSION then
    error(`Core.Load: the save is version {tostring(file.saveVersion)}; this build reads version {Core.SAVE_VERSION}`, 0)
  end
  -- (whatever its version, it may be from before an item type was added)
  Market.Reconcile(file.state)
  return { state = file.state, events = {} }
end

-- The fingerprint of the state. Two games with the same hash are in the
-- same state.
function Core.Hash(game: Game): string
  return Codec.HashOf(game.state)
end

-- ---------------------------------------------------------------------
-- Questions the view asks. These read the state and never change it.

local Query = {}
Core.Query = Query

export type PlayerInfo = {
  ship: number,
  shipName: string,
  hull: Ships.ShipType,
  docked: number,     -- station id, or 0
  system: number,
  systemName: string,
  security: number,   -- of the system: 1 at a homeworld, 0 where nobody keeps order
  owner: string,      -- the name of the faction whose system it is; "" if nobody's
  region: string,     -- the names of the region and the constellation it is in
  constellation: string,
}

function Query.Player(game: Game): PlayerInfo
  local state = game.state
  local ship = state.ships[state.player.ship]
  local system = if ship.docked ~= 0 then Space.SystemOf(state, ship.docked) else state.balls[ship.id].system
  return {
    ship = ship.id, shipName = ship.name, hull = Ships.byId[ship.type], docked = ship.docked,
    system = system, systemName = state.galaxy.systems[system].name, security = state.galaxy.systems[system].security,
    owner = if Factions.byId[state.galaxy.systems[system].owner] then Factions.byId[state.galaxy.systems[system].owner].name else "",
    region = state.galaxy.regions[state.galaxy.systems[system].region].name,
    constellation = state.galaxy.constellations[state.galaxy.systems[system].constellation].name,
  }
end

-- How safe a system is, and which of the three kinds of space that
-- makes it ("secure", "low" or "lawless"). Nothing for no such system.
function Query.Security(game: Game, system: number): (number?, Galaxy.Band?)
  local node = game.state.galaxy.systems[system]
  if node == nil then
    return nil, nil
  end
  return node.security, Galaxy.Band(node.security)
end

export type Entry = {
  id: number,
  kind: string,
  name: string,
  distance: number,   -- metres between surfaces, from the player's ship
  onGrid: boolean,
  variety: string,
  hostile: boolean,   -- a ship that will fire on the pilot: a pirate, or a patrol that has taken them for a criminal
  own: boolean,       -- a ship of the pilot's side: a drone of theirs, or a hired pilot's
  veiled: boolean?,   -- a ship in a cloud of gas: locked only from close in (Tactical/Vapour)
}

-- What the player's ship can see: everything on its grid, and every
-- place in the system it could warp to. Nearest first. Empty while docked.
function Query.Overview(game: Game): { Entry }
  local state = game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return {}
  end
  local entries: { Entry } = {}
  for _, object in Space.Describe(state, me.system).objects do
    local onGrid = me.grid ~= 0 and object.site == me.grid
    local gone = object.kind == "asteroid" and Mining.Left(state, object) <= 0
    -- (a site is on the overview once it has been found, and while the
    -- pilot is at it: Tactical/Sites)
    -- (the place of a tower the pirates held is gone with the tower,
    -- whoever is there: its wreck says where it was)
    local site = state.sites[object.id]
    if site and (not onGrid or site.kind == "keep") and Sites.Hidden(state, object.id) then
      gone = true
    end
    -- (and where a tower was taken down there is nothing)
    gone = gone or object.kind == "gone"
    if (onGrid or object.kind ~= "asteroid") and not gone then
      local entry: Entry = { id = object.id, kind = if site then "site" else object.kind :: string, name = object.name,
        distance = Space.Gap(me :: any, object :: any), onGrid = onGrid, variety = object.variety, hostile = false, own = false }
      table.insert(entries, entry)
    end
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if id ~= me.id and ball.system == me.system and ball.grid == me.grid and me.grid ~= 0 then
      local entry: Entry = { id = id, kind = ball.kind :: string, name = ball.name,
        distance = Space.Gap(me :: any, ball :: any), onGrid = true, variety = state.ships[id].type,
        -- (what stands for the pilot's tower under fire is theirs, as their ships are)
        hostile = state.ships[id].owner == "pirates" or state.pilots[id] ~= nil,
        own = state.ships[id].owner == "player" or state.ships[id].owner == "starbase",
        veiled = Vapour.In(state, ball) }
      table.insert(entries, entry)
    end
  end
  -- (the places the pilot has marked in this system: somewhere to warp to)
  for _, id in state.bookmarkIds do
    local mark = state.bookmarks[id]
    if mark.system == me.system then
      local entry: Entry = { id = id, kind = "bookmark", name = mark.name,
        distance = math.max(0, math.sqrt((mark.x - me.x) ^ 2 + (mark.y - me.y) ^ 2 + (mark.z - me.z) ^ 2) - me.radius),
        onGrid = false, variety = "", hostile = false, own = false }
      table.insert(entries, entry)
    end
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.system == me.system and wreck.grid == me.grid and me.grid ~= 0 then
      local entry: Entry = { id = id, kind = "wreck", name = wreck.name,
        distance = Space.Gap(me :: any, wreck :: any), onGrid = true,
        -- (a vault is no wreck to the pilot: Tactical/Sites)
        variety = if wreck.lock == "vault" then (if wreck.locked then "vault.locked" else "vault.open")
          elseif wreck.locked then "sealed" else "",
        hostile = false, own = false }
      table.insert(entries, entry)
    end
  end
  table.sort(entries, function(a: Entry, b: Entry): boolean
    if a.distance ~= b.distance then
      return a.distance < b.distance
    end
    return a.id < b.id
  end)
  return entries
end

-- What a holder (a ship, a station's hangar, a wreck) has, optionally in
-- one place only.
function Query.Items(game: Game, holder: number, place: string?): { State.Item }
  return Items.In(game.state, holder, place)
end

-- A ship's fitted modules, rack by rack.
function Query.Fitted(game: Game, ship: number): { State.Item }
  return Items.Fitted(game.state, ship)
end

-- A ship's attributes with its present fit (nothing running).
function Query.Stats(game: Game, ship: number): Attributes.Stats
  return Items.ShipStats(game.state, ship)
end

-- What a ship's weapons come to with what is loaded in them.
function Query.Offence(game: Game, ship: number): Items.Offence
  return Items.Offence(game.state, ship)
end

-- CPU and powergrid a ship's fit uses.
function Query.FittingUse(game: Game, ship: number): (number, number)
  local cpu, powergrid = 0, 0
  local hull = Ships.byId[game.state.ships[ship].type]
  for _, item in Items.Fitted(game.state, ship) do
    local tf, mw = Attributes.Needs(hull, Modules.byId[item.type])
    cpu += tf
    powergrid += mw
  end
  return cpu, powergrid
end

function Query.CargoUsed(game: Game, ship: number): number
  return Items.CargoUsed(game.state, ship)
end

-- A ship's ore hold: how big it is, m3 (0: its hull has none), and the
-- cubic metres in it. (What is in it: Query.Items(game, ship, "orehold").)
function Query.OreHold(game: Game, ship: number): (number, number)
  return Items.OreHold(game.state, ship)
end

-- A ship's bay for ships: how big it is, m3 (0: its hull has none: a
-- logistics capital has one), and the cubic metres of packed hulls in
-- it. (What is in it: Query.Items(game, ship, "shipbay").)
function Query.ShipBay(game: Game, ship: number): (number, number)
  return Items.ShipBay(game.state, ship)
end

-- What repairing the player's docked ship would cost.
function Query.RepairCost(game: Game): number
  return Aftermath.RepairCost(game.state, game.state.ships[game.state.player.ship])
end

-- Whether a ship is cloaked: nobody can target it.
function Query.Cloaked(game: Game, ship: number): boolean
  return Combat.Cloaked(game.state, ship)
end

-- A hull's own cloak (one built in: Data/Ships 'cloak'): whether a
-- ship in space has one, and whether it is on. (On with "Cloak", off
-- with "Uncloak".)
function Query.OwnCloak(game: Game, ship: number): (boolean, boolean)
  local ball = game.state.balls[ship]
  return Combat.HasCloak(game.state, ship), ball ~= nil and ball.vitals.cloaked == true
end

-- Whether a ship is in a cloud of gas (Tactical/Vapour): it is locked,
-- and locks, only from close in. And how close that is, in metres.
function Query.Veiled(game: Game, ship: number): (boolean, number)
  local ball = game.state.balls[ship]
  return ball ~= nil and Vapour.In(game.state, ball), Vapour.SIGHT
end

-- The chance a fitted turret would hit a target now, or nil.
function Query.HitChance(game: Game, ship: number, item: number, target: number): number?
  return Combat.HitChance(game.state, ship, item, target)
end

-- What a station's market asks and bids for a type, and how many it has.
function Query.Quote(game: Game, station: number, type: string): Market.Quote
  return Market.Quote(game.state, station, type)
end

-- What buying a quantity at once would cost (nil if the station has not
-- that many), and what selling it at once would bring after tax.
function Query.BuyCost(game: Game, station: number, type: string, quantity: number): number?
  return Market.BuyCost(game.state, station, type, quantity)
end

function Query.SellValue(game: Game, station: number, type: string, quantity: number): number
  return Market.SellValue(game.state, station, type, quantity)
end

-- The sales tax and broker's fee the pilot pays, as shares.
function Query.Fees(game: Game): (number, number)
  -- (as the station the pilot is docked at charges them, if they are docked)
  local docked = game.state.ships[game.state.player.ship].docked
  local station: number? = if docked ~= 0 then docked else nil
  return Market.Tax(game.state, station), Market.Fee(game.state, station)
end

-- The wallet's journal, oldest first.
function Query.Journal(game: Game): { State.Entry }
  return game.state.journal
end

-- The pilot's corporation (Assets/Corporation): whether there is one,
-- and what it is called; its account and that account's journal, oldest
-- first; all it has earned and spent; what founding one costs; and how
-- many more pilots than Leadership commands it has places for (as it
-- is, and as it would be).
-- ('heads': its books by head, what has come in under each and what has
-- gone out, in the books' own order and only the heads with anything
-- under them; the last, "Earlier", is whatever a save from before the
-- books were kept by head had earned and spent. 'towers': the pilot's
-- towers, each with where it is and how its running stands, which are
-- the pilot's whether or not there is a corporation.)
export type HeadRow = { name: string, amount: number }
export type TowerRow = { id: number, name: string, system: string, lit: boolean, running: Starbases.Running }
export type CorporationInfo = {
  founded: boolean, name: string, since: number, wallet: number, journal: { State.Entry }, earned: number, spent: number,
  fee: number, staff: number, wages: number, heads: { HeadRow }, towers: { TowerRow },
}
function Query.Corporation(game: Game): CorporationInfo
  local state = game.state
  local corporation = state.corporation
  -- (what its pilots are paid a day, all told)
  local wages = 0
  for _, id in state.fleetIds do
    wages += Fleet.Due(state.fleet[id])
  end
  local heads: { HeadRow } = {}
  local earned, spent = 0, 0
  for _, head in Corporation.HEADS do
    local amount = corporation.books[head.reason] or 0
    if amount ~= 0 then
      table.insert(heads, { name = head.name, amount = amount })
      earned += math.max(0, amount)
      spent += math.max(0, -amount)
    end
  end
  -- (a head takes money one way: so what is under no head is the rest of each)
  if corporation.earned - earned > 0 then
    table.insert(heads, { name = "Earlier earnings", amount = corporation.earned - earned })
  end
  if corporation.spent - spent > 0 then
    table.insert(heads, { name = "Earlier spending", amount = -(corporation.spent - spent) })
  end
  local towers: { TowerRow } = {}
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local body = Space.Object(state, id)
    if starbase.owner == "player" and body then
      table.insert(towers, { id = id, name = body.name, system = state.galaxy.systems[Space.SystemOf(state, id)].name,
        lit = Starbases.Lit(state, starbase), running = Starbases.Running(state, starbase) })
    end
  end
  return {
    founded = Corporation.Founded(state), name = corporation.name, since = corporation.founded, wallet = corporation.wallet,
    journal = corporation.journal, earned = corporation.earned, spent = corporation.spent, fee = Corporation.FEE,
    staff = Corporation.STAFF, wages = wages, heads = heads, towers = towers,
  }
end

function Query.Orders(game: Game, station: number?): { State.Order }
  return Market.Orders(game.state, station)
end

function Query.History(game: Game, station: number, type: string): { State.TradeDay }
  return Market.History(game.state, station, type)
end

-- A station's board (Assets/Contracts): the lots it has for sale today
-- and the lots it wants, each with how much of it is in the pilot's
-- hangar there; the pilot's own listings everywhere, each with what it
-- is worth where it is up and the chance an hour that it is taken; and
-- how many listings a pilot can have up.
export type BoardLot = { lot: Contracts.Lot, have: { number } }
export type BoardListing = { listing: State.Listing, worth: number, chance: number, left: number, here: boolean }
export type Board = { lots: { BoardLot }, listings: { BoardListing }, limit: number }
function Query.Contracts(game: Game, station: number): Board
  local state = game.state
  local lots: { BoardLot } = {}
  for _, lot in Contracts.Board(state, station) do
    table.insert(lots, { lot = lot, have = Contracts.Have(state, station, lot.stacks) })
  end
  local listings: { BoardListing } = {}
  for _, listing in Contracts.Listings(state) do
    local worth = Contracts.Worth(state, listing.station, listing.type, listing.quantity)
    table.insert(listings, { listing = listing, worth = worth, chance = Contracts.Chance(listing.price, worth),
      left = math.max(0, listing.ends - state.tick) * Constants.TICK, here = listing.station == station })
  end
  return { lots = lots, listings = listings, limit = Contracts.LISTINGS }
end

-- What a lot of so many of a type would be worth on a station's board,
-- what putting it up at a price would cost, and the chance an hour that
-- somebody takes it at that price.
function Query.ContractWorth(game: Game, station: number, type: string, quantity: number, price: number): (number, number, number)
  if Space.Object(game.state, station) == nil or Types.Get(type) == nil or quantity < 1 then
    return 0, 0, 0
  end
  local worth = Contracts.Worth(game.state, station, type, quantity)
  return worth, Contracts.Fee(game.state, station, price), Contracts.Chance(price, worth)
end

-- The pilot's home: the station they wake at when their capsule is
-- destroyed, its name and the system it is in, how many jumps off that
-- is from where the pilot is (0 in the same system, -1 if there is no
-- way), whether the pilot is docked there, and what a station charges
-- to be made home.
export type HomeInfo = { station: number, name: string, system: string, jumps: number, here: boolean, fee: number }
function Query.Home(game: Game): HomeInfo
  local state = game.state
  local home = state.player.home
  local object = Space.Object(state, home)
  local system = Space.SystemOf(state, home)
  local ship = state.ships[state.player.ship]
  local ball = state.balls[state.player.ship]
  local at = if ship.docked ~= 0 then Space.SystemOf(state, ship.docked) elseif ball then ball.system else system
  local route = Galaxy.Route(state.galaxy, at, system)
  return { station = home, name = if object then object.name else "?", system = state.galaxy.systems[system].name,
    jumps = #route - 1, here = ship.docked == home, fee = Hangar.HOME_FEE }
end

-- A type's going price at a station day by day, with what was traded in
-- it each day, for the last so many days and today (30 if not said).
-- Nothing for a type no market deals in.
function Query.PriceHistory(game: Game, station: number, type: string, span: number?): { Market.ChartDay }
  if Space.Object(game.state, station) == nil or Market.Index(type) == nil then
    return {}
  end
  return Market.Chart(game.state, station, type, span or 30)
end

-- The player's ships docked at a station.
function Query.Ships(game: Game, station: number): { State.Ship }
  return Hangar.Ships(game.state, station)
end

-- What the player owns, place by place: the hold of the ship flown
-- (station 0), then every station with something of the pilot's in its
-- hangar, the one docked at first and the rest by system and station.
export type AssetsAt = {
  station: number,      -- 0 for the hold
  name: string,
  system: number,
  systemName: string,
  here: boolean,        -- the pilot is docked there (or it is the hold)
  ships: { State.Ship },
  items: { State.Item },
  -- (what is in the hangar the pilot's corporation has there)
  business: { State.Item },
  volume: number,       -- of the items, m3
  worth: number,        -- of items and hulls, at base prices
}
function Query.Assets(game: Game): { AssetsAt }
  local state = game.state
  local me = state.ships[state.player.ship]
  local places: { [number]: AssetsAt } = {}
  local order: { number } = {}
  local function at(station: number): AssetsAt
    local place = places[station]
    if place == nil then
      local object = Space.Object(state, station)
      local system = if object then Space.SystemOf(state, station) else Query.Player(game).system
      place = {
        station = station, name = if object then object.name else `{me.name}: hold`, system = system,
        systemName = state.galaxy.systems[system].name, here = station == 0 or station == me.docked,
        ships = {}, items = {}, business = {}, volume = 0, worth = 0,
      }
      places[station] = place
      table.insert(order, station)
    end
    return place
  end
  for _, id in state.itemIds do
    local item = state.items[id]
    local hold = item.holder == me.id and (item.place == "cargo" or item.place == "orehold")
    if hold or (Items.IsStore(item.place) and Space.Object(state, item.holder) ~= nil) then
      local place = at(if hold then 0 else item.holder)
      local info = Types.Info(item.type)
      table.insert(if item.place == "corporate" then place.business else place.items, item)
      place.volume += item.quantity * info.volume
      place.worth += item.quantity * info.basePrice
    end
  end
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.owner == me.owner and ship.docked ~= 0 then
      local place = at(ship.docked)
      table.insert(place.ships, ship)
      place.worth += Ships.byId[ship.type].basePrice
    end
  end
  table.sort(order, function(a: number, b: number): boolean
    local pa, pb = places[a], places[b]
    if pa.here ~= pb.here then
      return pa.here
    elseif (a == 0) ~= (b == 0) then
      return a == 0
    end
    return a < b
  end)
  local found: { AssetsAt } = {}
  for _, station in order do
    table.insert(found, places[station])
  end
  return found
end

export type SkillInfo = {
  skill: Skills.Skill,
  level: number,      -- -1 if the pilot has not learned it
  queued: number,     -- the level it will reach when the queue is done
}

-- Every skill, in the order the data lists them, with what the pilot
-- knows of it.
function Query.Skills(game: Game): { SkillInfo }
  local found: { SkillInfo } = {}
  for _, skill in Skills.list do
    table.insert(found, { skill = skill, level = game.state.skills[skill.id] or -1,
      queued = Training.QueuedLevel(game.state, skill.id) })
  end
  return found
end

-- The training queue with its times; the first entry is in training.
function Query.Training(game: Game): { Training.Queued }
  return Training.Queue(game.state)
end

-- Why the pilot cannot use a hull or module yet ("needs Frigates 2"), or
-- nil if they can.
function Query.Untrained(game: Game, type: string): string?
  local missing = Skills.Missing(Skills.Needs(type), game.state.skills)
  return if missing then Skills.Describe(missing) else nil
end

-- The manufacturing jobs running, optionally at one station.
function Query.Jobs(game: Game, station: number?): { State.Job }
  return Industry.Jobs(game.state, station)
end

function Query.JobSlots(game: Game): number
  return Industry.JobSlots(game.state)
end

-- What running a blueprint (or a copy of one) so many times at a station
-- would take, or nil if the type is neither.
function Query.JobPlan(game: Game, station: number, type: string, runs: number): Industry.Plan?
  local blueprint = Blueprints.Of(type)
  return if blueprint then Industry.Plan(game.state, station, blueprint, runs) else nil
end

-- What copying so many runs of a blueprint would take, or nil if the
-- type is not a blueprint (a copy is not: it cannot be copied).
function Query.CopyPlan(game: Game, type: string, runs: number): Industry.CopyPlan?
  local blueprint = Blueprints.byId[type]
  return if blueprint then Industry.CopyPlan(blueprint, runs) else nil
end

-- A body by id (a ship in space or a described object), or nil.
function Query.Body(game: Game, id: number): Space.Body?
  -- (a place the pilot has marked counts, to whoever only wants its name
  -- and where it is)
  return Space.Body(game.state, id) or Space.Marked(game.state, id)
end

-- The career agents: each career in order, with who its agent is, how
-- far the pilot has got, the lesson in hand or next to take (nil when
-- there is none left), what finishing it gives, how much of what it
-- wants is done, and whether it can be taken or reported done now (and
-- if not, why not). And the station the agents are at, with whether the
-- pilot is docked there.
-- ('again': whether what the lesson in hand handed over can be handed
-- over again now, to a pilot who has lost it; and why not, if not.)
export type CareerRow = { career: Careers.Career, agent: string, done: number, taken: boolean, lesson: Careers.Lesson?,
  gifts: { Careers.Stack }, have: number, need: number, can: boolean, why: string, again: boolean, whyNot: string }
export type CareersStatus = { rows: { CareerRow }, station: number, here: boolean, begun: boolean }
function Query.Careers(game: Game): CareersStatus
  local state = game.state
  local ship = state.ships[state.player.ship]
  local station = Careers.Station(state)
  local rows: { CareerRow } = {}
  local begun = false
  for _, career in Careers.list do
    local mine = Careers.Of(state, career.id)
    local lesson = Careers.Lesson(state, career.id)
    local have, need = Careers.Progress(state, career.id)
    local can, why = false, nil :: string?
    if lesson then
      can, why = validate(state, { kind = if mine.taken then "CompleteLesson" else "AcceptLesson", actor = ship.id, what = career.id })
    end
    begun = begun or mine.taken or mine.done > 0
    local again, whyNot = validate(state, { kind = "ReplaceKit", actor = ship.id, what = career.id })
    table.insert(rows, { career = career, agent = Careers.Agent(state, career.id), done = mine.done, taken = mine.taken, lesson = lesson,
      gifts = if lesson then Careers.Gifts(state, lesson) else {}, have = have, need = need, can = can, why = why or "",
      again = again, whyNot = whyNot or "" })
  end
  return { rows = rows, station = station, here = ship.docked == station, begun = begun }
end

-- The guide: every step there is, in order, with whether the pilot has
-- done it; and how many they have.
export type GuideRow = { step: Guide.Step, done: boolean }
function Query.Guide(game: Game): ({ GuideRow }, number)
  local rows: { GuideRow } = {}
  for _, step in Guide.steps do
    table.insert(rows, { step = step, done = Guide.Done(game.state, step.id) })
  end
  return rows, #game.state.guide
end

-- The pilot's implants: the five places in order, each with what is in
-- it (nothing, for an empty one), and how many places their
-- Cybernetics opens.
export type ImplantPlace = { slot: number, implant: Implants.Implant? }
function Query.Implants(game: Game): ({ ImplantPlace }, number)
  local places: { ImplantPlace } = {}
  for slot = 1, Implants.SLOTS do
    table.insert(places, { slot = slot, implant = Implanting.In(game.state, slot) })
  end
  return places, math.clamp(game.state.skills.cybernetics or 0, 0, Implants.SLOTS)
end

-- How much is left in a rock or a cloud, as a share of what it holds
-- whole (1 for anything that is neither).
function Query.Left(game: Game, id: number): number
  local object = Space.Object(game.state, id)
  if object == nil or object.kind ~= "asteroid" then
    return 1
  end
  local whole = Ores.Units(object.variety, object.radius)
  return if whole > 0 then Mining.Left(game.state, object) / whole else 0
end

-- The pilot's boosters: those at work, each with the seconds it has
-- left; and those to hand (in the hold of the ship they fly, and in the
-- hangar where they are docked), each with the item to take, how many
-- there are of it, and why it cannot be taken now, if it cannot.
-- ('wrong': it sat badly, and its ill effect is at work too; 'whole':
-- the seconds one taken now would last.)
export type BoosterAtWork = { booster: Boosters.Booster, left: number, wrong: boolean, whole: number }
export type BoosterToHand = { booster: Boosters.Booster, item: number, quantity: number, refused: string? }
function Query.Boosters(game: Game): ({ BoosterAtWork }, { BoosterToHand })
  local state = game.state
  local working: { BoosterAtWork } = {}
  for _, boosted in state.boosters do
    table.insert(working, { booster = Boosters.byId[boosted.type], left = math.max(0, boosted.ends - state.tick) * Constants.TICK,
      wrong = boosted.wrong, whole = (Boosting.Odds(state)) * Constants.TICK })
  end
  local hand: { BoosterToHand } = {}
  local ship = state.ships[state.player.ship]
  if ship then
    local stacks = Items.In(state, ship.id, "cargo")
    if ship.docked ~= 0 then
      for _, item in Items.In(state, ship.docked, "hangar") do
        table.insert(stacks, item)
      end
    end
    for _, item in stacks do
      local booster = Boosters.byId[item.type]
      if booster then
        local ok, why = Boosting.Validate(state, { kind = "TakeBooster", actor = ship.id, item = item.id })
        table.insert(hand, { booster = booster, item = item.id, quantity = item.quantity, refused = if ok then nil else why })
      end
    end
  end
  return working, hand
end

-- The sites the pilot knows of in a system (found, and still there), by
-- name: for the map, which has no overview to show them on.
function Query.KnownSites(game: Game, system: number): { string }
  local names: { string } = {}
  for _, site in Sites.In(game.state, system) do
    local place = Space.Object(game.state, site.id)
    if site.strength >= 1 and place then
      table.insert(names, place.name)
    end
  end
  return names
end

-- The hack under way, as the pilot sees it, or nil: the lock's matrix
-- (each cell's code, whether it has been picked, and whether it can be
-- picked now), the buffer and its room, the keys (each with its codes,
-- whether it is in, and how many of its codes the end of the buffer has
-- begun it with), and the row or column the next pick has to be in.
export type HackCell = { code: string, used: boolean, open: boolean }
-- ('what': a key's use in a few words. 'clock': the seconds the lock
-- allows from the first pick, 0 for one that is on no clock; 'left':
-- the seconds there are left of them, once it is begun.)
export type HackKey = { name: string, codes: { string }, done: boolean, begun: number, what: string }
export type HackStatus = { wreck: number, name: string, size: number, cells: { HackCell }, buffer: { string }, room: number,
  keys: { HackKey }, along: string, line: number, clock: number, left: number }
function Query.Hack(game: Game): HackStatus?
  local hack = game.state.hack
  if hack == nil then
    return nil
  end
  local wreck = game.state.wrecks[hack.wreck]
  local open = Hacking.Open(hack)
  local cells: { HackCell } = {}
  for index, code in hack.cells do
    table.insert(cells, { code = code, used = hack.used[index], open = table.find(open, index) ~= nil })
  end
  local kind = if wreck then Hacking.LockOf(wreck) else Hacking.LOCKS.hold
  local keys: { HackKey } = {}
  for index, key in hack.keys do
    table.insert(keys, { name = key.name, codes = table.clone(key.codes), done = key.done,
      begun = if key.done then #key.codes else Hacking.Begun(hack.buffer, key.codes),
      what = if kind.keys[index] then kind.keys[index].what else "" })
  end
  return { wreck = hack.wreck, name = if wreck then wreck.name else "", size = hack.size, cells = cells,
    buffer = table.clone(hack.buffer), room = hack.room, keys = keys, along = hack.along, line = hack.line,
    clock = kind.clock * Constants.TICK,
    left = if hack.ends > 0 then math.max(0, hack.ends - game.state.tick) * Constants.TICK else kind.clock * Constants.TICK }
end

-- The directional scanner (Tactical/Dscan): the ships, wrecks and
-- structures within 'range' metres of the pilot's ship, all round
-- ('angle' 360) or in a cone of 'angle' degrees pointed along the line
-- 'along' (x, y and z of it) or, with no line, at 'toward'; and whether
-- the scan could be made, with why not if it could not.
export type Sighting = Dscan.Sighting
function Query.Directional(game: Game, toward: number?, angle: number, range: number, along: { number }?): ({ Sighting }, boolean, string?)
  local ship = game.state.player.ship
  local ok, why = Dscan.Can(game.state, ship, toward, angle, along)
  return Dscan.Scan(game.state, ship, toward, angle, range, along), ok, why
end

-- Whether a site is one the pilot can see on the overview: found, and
-- still there.
function Query.Found(game: Game, site: number): boolean
  return game.state.sites[site] ~= nil and not Sites.Hidden(game.state, site)
end

-- The places the pilot has marked, in the order they were.
function Query.Bookmarks(game: Game): { State.Bookmark }
  local found: { State.Bookmark } = {}
  for _, id in game.state.bookmarkIds do
    table.insert(found, game.state.bookmarks[id])
  end
  return found
end

-- A pilot's starbase, by the id of its station: how it stands. Nil if
-- the station is not one.
export type StarbaseStatus = {
  tower: Structures.Tower,
  mine: boolean,          -- it is the player's
  anchored: boolean,      -- its anchoring is done
  wait: number,           -- seconds until it is, if it is not
  lit: boolean,           -- and it has fuel
  fuel: number,           -- blocks aboard
  hours: number,          -- that they will last
  powergrid: number,      -- drawn by its modules
  cpu: number,
  -- (a module is online when its own anchoring is done and the tower is lit)
  modules: { { type: string, online: boolean, wait: number } },
  -- The moon it is anchored at, by name, and how its drilling stands
  -- (Assets/Starbases): what is under the moon, whether a drill is
  -- anchored and online, what it brings up an hour, how much of it is
  -- in the hangar and how much the tower holds; and the seconds until
  -- the drill's next hour is up (0 when it is not drilling).
  moon: string,
  drilling: Starbases.Drilling,
  next: number,
  -- How its reactor stands (Assets/Starbases): whether one is anchored
  -- and online, what it is set to make, how much of what that is made
  -- of is in the hangars, and whether it stood idle last for want of
  -- it; and the seconds until its next batch (0 when it is making
  -- nothing).
  reacting: Starbases.Reacting,
  reacts: number,
  -- What it has against a raid (Tactical/Raids): its strength, how
  -- many batteries of it are online and how many hired pilots hold the
  -- place; and how strong the raids that come there are, at least and
  -- at most (0 and 0 where order is kept, and nobody comes).
  defence: number, batteries: number, patrol: number,
  raidLeast: number, raidMost: number,
  -- Its running since it was anchored, priced (Starbases.Running).
  running: Starbases.Running,
  -- Under fire (Tactical/Raids): how much of its shield, armour and
  -- structure is left, each 0 to 1; the sealing charges aboard and how
  -- many its bay holds; the seconds it stays sealed (0 when it is not);
  -- how strong those are who have come to bring it down (0 when nobody
  -- has); the ship that stands for it where it is shot at (0 before it
  -- is anchored); and whether a raid nobody meets would be a siege (it
  -- is where nobody keeps order).
  shield: number, armor: number, hull: number,
  charges: number, bay: number, sealed: number, siege: number, core: number, besieged: boolean,
}
function Query.Starbase(game: Game, id: number): StarbaseStatus?
  local state = game.state
  local starbase = state.starbases[id]
  if starbase == nil then
    return nil
  end
  local powergrid, cpu = Starbases.Draw(starbase)
  local lit = Starbases.Lit(state, starbase)
  local modules = {}
  for _, module in starbase.modules do
    table.insert(modules, { type = module.type, online = lit and state.tick >= module.ready,
      wait = math.max(0, module.ready - state.tick) * Constants.TICK })
  end
  local ship = state.ships[state.player.ship]
  local moon = Space.Object(state, Starbases.Moon(state, starbase))
  local drilling = Starbases.Drilling(state, starbase)
  local reacting = Starbases.Reacting(state, starbase)
  local defence, batteries, patrol = Raids.Defence(state, starbase)
  local raids = Raids.STRENGTH[Raids.Band(state, starbase)]
  return {
    tower = Structures.towerById[starbase.tower], mine = ship ~= nil and ship.owner == starbase.owner,
    anchored = Starbases.Anchored(state, starbase), wait = math.max(0, starbase.ready - state.tick) * Constants.TICK, lit = lit,
    fuel = starbase.fuel, hours = Starbases.Hours(starbase), powergrid = powergrid, cpu = cpu, modules = modules,
    moon = if moon then moon.name else "", drilling = drilling, reacting = reacting,
    reacts = if reacting.online and reacting.making then math.max(0, starbase.reacted + 3600 / Constants.TICK - state.tick) * Constants.TICK
      else 0,
    next = if drilling.online and drilling.deposit then math.max(0, starbase.drilled + 3600 / Constants.TICK - state.tick) * Constants.TICK
      else 0,
    defence = defence, batteries = batteries, patrol = patrol,
    raidLeast = if raids then raids[1] else 0, raidMost = if raids then raids[2] else 0,
    running = Starbases.Running(state, starbase),
    shield = (select(1, Starbases.Health(state, starbase))), armor = (select(2, Starbases.Health(state, starbase))),
    hull = (select(3, Starbases.Health(state, starbase))),
    charges = starbase.charges, bay = Structures.towerById[starbase.tower].bay,
    sealed = if Starbases.Sealed(state, starbase) then (starbase.sealed - state.tick) * Constants.TICK else 0,
    siege = starbase.siege, core = starbase.core, besieged = Raids.Band(state, starbase) == "lawless",
  }
end

-- Where pirates are massing (Tactical/Surges), if anywhere: the system
-- and its name, how many jumps from the pilot it is, the seconds the
-- surge has left, and how many pirates have been destroyed there
-- since it began. Nil with none on.
export type SurgeInfo = { system: number, name: string, jumps: number, left: number, kills: number }
-- (How far off it is, is worked out when the surge or the pilot's
-- system changes, not every time it is asked: a screen asks every frame.)
local surgeFar = { galaxy = nil :: any, from = 0, to = 0, jumps = 0 }
function Query.Surge(game: Game): SurgeInfo?
  local state = game.state
  local surge = state.surge
  if surge.system == 0 then
    return nil
  end
  local here = Query.Player(game).system
  if surgeFar.galaxy ~= state.galaxy or surgeFar.from ~= here or surgeFar.to ~= surge.system then
    surgeFar.galaxy, surgeFar.from, surgeFar.to = state.galaxy, here, surge.system
    surgeFar.jumps = math.max(0, #Galaxy.Route(state.galaxy, here, surge.system) - 1)
  end
  return { system = surge.system, name = state.galaxy.systems[surge.system].name, jumps = surgeFar.jumps,
    left = math.max(0, surge.ends - state.tick) * Constants.TICK, kills = surge.kills }
end

-- What is under a moon, by the moon's id (Data/Moons): the material and
-- how rich the deposit is, or nil for a moon with nothing worth a
-- drill (and for what is no moon).
function Query.Deposit(game: Game, moon: number): Moons.Deposit?
  return Starbases.Deposit(game.state, moon)
end

-- The pilot's jump drive (Tactical/Jumping): nil for a hull with none.
-- How far it reaches, the fuel blocks in the hold and the seconds until
-- it is ready (0: now); and, for a system, how far that is, what fuel
-- it would take, and whether the jump can be made now ('why': why not).
-- And the beacons lit for the pilot, wherever they are: each one's
-- system, whose it is ("tower" or "ship") and its name, how far off its
-- system is, and whether that is within the drive's reach.
export type JumpBeacon = { system: number, kind: string, name: string, distance: number, reached: boolean }
export type JumpDriveStatus = { range: number, held: number, cooling: number, distance: number, fuel: number, ready: boolean, why: string,
  beacons: { JumpBeacon } }
function Query.JumpDrive(game: Game, system: number?): JumpDriveStatus?
  local state = game.state
  local ship = state.player.ship
  if not Jumping.Fitted(state, ship) then
    return nil
  end
  local ball = state.balls[ship]
  local here = if ball then ball.system else Space.SystemOf(state, state.ships[ship].docked)
  local to = system or 0
  local known = state.galaxy.systems[to] ~= nil and to ~= here
  local distance = if known then Jumping.Distance(state, here, to) else 0
  local ok, why = Jumping.Validate(state, { kind = "JumpDrive", actor = ship, target = to })
  local range = Jumping.Range(state, ship)
  local beacons: { JumpBeacon } = {}
  for _, beacon in Jumping.Beacons(state, ship) do
    local far = Jumping.Distance(state, here, beacon.system)
    table.insert(beacons, { system = beacon.system, kind = beacon.kind :: string, name = beacon.name, distance = far,
      reached = beacon.system ~= here and far <= range })
  end
  return { range = range, held = Jumping.Held(state, ship), cooling = Jumping.Cooling(state, ship),
    distance = distance, fuel = if known then Jumping.Fuel(state, ship, distance) else 0, ready = ok, why = why or "",
    beacons = beacons }
end

-- A tower the pirates hold a moon with (Tactical/Keeps), asked for by
-- its place, by the moon, or by the tower itself; nil for anything
-- else. 'sealed': the seconds until it opens (0 while it is open);
-- 'charged': whether it has anything to seal with; 'resupplied': the
-- seconds until it is whole again and has (0 if nothing is on its way);
-- 'batteries': how many of them stand.
export type KeepStatus = {
  site: number, moon: number, core: number, name: string,
  sealed: number, charged: boolean, resupplied: number, batteries: number,
}
function Query.Keep(game: Game, id: number): KeepStatus?
  local state = game.state
  local keep = state.keeps[id] or Keeps.At(state, id) or Keeps.Of(state, id)
  if keep == nil then
    return nil
  end
  local place = Space.Object(state, keep.id)
  return {
    site = keep.id, moon = keep.moon, core = keep.core, name = if place then place.name else "Pirate Tower",
    sealed = if Keeps.Sealed(state, keep) then (keep.sealed - state.tick) * Constants.TICK else 0,
    charged = keep.charges > 0,
    resupplied = if keep.charges == 0 and keep.restock > state.tick then (keep.restock - state.tick) * Constants.TICK else 0,
    batteries = Keeps.Batteries(state, keep),
  }
end

-- The pilot's drones: how many are in the drone bay, how many are out,
-- how many could be out at once, how many of those out have been
-- called back or pointed at something, and the bay: how much of it is
-- used, m3, of how much.
export type DronesStatus = { carried: number, out: number, max: number, returning: number, engaged: number, bayUsed: number, bay: number }
function Query.Drones(game: Game): DronesStatus
  local state = game.state
  local ship = state.player.ship
  local carried = 0
  for _, item in Items.In(state, ship, "dronebay") do
    carried += item.quantity
  end
  local returning, engaged = 0, 0
  local out = Drones.Out(state, ship)
  for _, drone in out do
    returning += if drone.returning then 1 else 0
    engaged += if drone.target ~= 0 and not drone.returning then 1 else 0
  end
  return { carried = carried, out = #out, max = Drones.Max(state, ship), returning = returning, engaged = engaged,
    bayUsed = Items.BayUsed(state, ship), bay = Ships.byId[state.ships[ship].type].bay or 0 }
end

-- The pilots the player has hired, in the order they were: who, what
-- they fly and where it is, and how it is holding up (shares of its
-- shield, armour and hull; whole for a ship that is docked).
export type FleetRow = {
  -- ('wage' is what they are paid a day, which for a devoted one is less
  -- than their grade's; 'loyalty' is 0 to 100, and 'mood' the word for it)
  id: number, name: string, skill: number, wage: number, loyalty: number, mood: string, order: string, target: number,
  ship: number, shipName: string, hull: string,   -- 0 and "" for a pilot with no ship
  where: string,      -- "no ship", "docked at ...", "with you", or the system it is in
  -- "no ship", "following", "fighting", "waiting"; for a pilot set to
  -- mine: "mining", "taking ore in", "unloading", "going to the belt";
  -- for one set to haul: "loading", "waiting for cargo", "carrying",
  -- "unloading", "going back for more"; for one set to patrol:
  -- "patrolling", "fighting", "going in to mend", "mending", "going to
  -- their post"; and for one set to guard: "guarding", "fighting"
  doing: string,
  post: string,       -- for one set to patrol: the name of the place they hold
  ward: string,       -- for one set to guard: the name of the pilot they go with
  hunted: boolean,    -- somebody is after them, with the player somewhere else
  hauled: number,     -- units a pilot set to mine or to haul has brought in
  cargo: string,      -- for one set to haul: what kind they carry,
  from: string,       -- the name of the station it is carried from (the first, of a round of several),
  to: string,         -- and of the one it is carried to
  stops: { string },  -- the names of every station collected at, in order
  drops: number,      -- how many stations it carries to, a load to each in turn (1: the one)
  -- for one sent to buy ('from' is the market's name and 'to' that of
  -- the station it is brought to): the name of the thing, and how many
  -- are still to be bought; and for one who keeps it in stock, how many
  -- are kept
  want: string, need: number, keep: number,
  sells: boolean,     -- they sell what they bring in,
  earned: number,     -- and this is what that has made
  experience: number, -- what they have learned toward the next grade,
  needed: number,     -- and what that takes (0 for one who is as good as they get)
  near: boolean,      -- on the pilot's grid
  distance: number,   -- from the pilot's ship, when near
  shield: number, armor: number, structure: number,
}
function Query.Fleet(game: Game): { FleetRow }
  local state = game.state
  local lead = state.balls[state.player.ship]
  local rows: { FleetRow } = {}
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ship = state.ships[wing.ship]
    local row: FleetRow = {
      id = wing.id, name = wing.name, skill = wing.skill, wage = Fleet.Due(wing), loyalty = wing.loyalty,
      mood = Fleet.Mood(wing.loyalty), order = wing.order, target = wing.target,
      ship = 0, shipName = "", hull = "", where = "no ship", near = false, distance = 0, shield = 1, armor = 1, structure = 1,
      doing = "no ship", hauled = wing.hauled, experience = wing.experience,
      cargo = wing.cargo, from = "", to = "", stops = {}, drops = 1, sells = wing.sell, earned = wing.earned,
      want = "", need = 0, keep = 0,
      post = "", ward = "", hunted = wing.alarm,
      needed = if wing.skill >= Fleet.BEST then 0 else Fleet.Needed(wing.skill),
    }
    if ship then
      row.ship, row.shipName, row.hull = ship.id, ship.name, ship.type
      local ball = state.balls[ship.id]
      if ball then
        local vitals = ball.vitals
        row.shield = if vitals.shieldMax > 0 then vitals.shield / vitals.shieldMax else 0
        row.armor = if vitals.armorMax > 0 then vitals.armor / vitals.armorMax else 0
        row.structure = if vitals.hullMax > 0 then vitals.hull / vitals.hullMax else 0
        row.near = lead ~= nil and lead.system == ball.system and lead.grid ~= 0 and lead.grid == ball.grid
        row.distance = if row.near and lead then Space.Gap(lead :: any, ball :: any) else 0
        row.where = if row.near then "with you" elseif ball.warp and ball.warp.stage == "warp" then "in warp"
          else state.galaxy.systems[ball.system].name
      else
        local station = Space.Object(state, ship.docked)
        row.where = `docked at {if station then station.name else "a station"}`
      end
      if wing.order == "mine" then
        row.doing = if ball == nil then "unloading" elseif ball.intent and ball.intent.kind == "dock" then "taking ore in"
          elseif ball.grid == wing.post then "mining" else "going to the belt"
      elseif wing.order == "haul" then
        -- ('to': where the load they have, or the next, is going)
        local from, to = Space.Object(state, wing.post), Space.Object(state, Fleet.Drop(wing))
        row.from, row.to = if from then from.name else "?", if to then to.name else "?"
        for _, stop in wing.stops do
          local object = Space.Object(state, stop)
          table.insert(row.stops, if object then object.name else "?")
        end
        row.drops = 1 + #wing.drops
        local laden = false
        for _, item in Items.In(state, ship.id, "cargo") do
          laden = laden or Fleet.Carries(wing.cargo, item.type)
        end
        -- (out flying: on the way to deliver, to the next station of the round, or back to the first)
        local _, why = Fleet.HaulGoal(state, wing, ship)
        row.doing = if ball then (if why == "collect" and laden then "collecting" elseif laden then "carrying" else "going back for more")
          elseif ship.docked == Fleet.Drop(wing) then "unloading"
          elseif laden then "loading" else "waiting for cargo"
      elseif wing.order == "buy" or wing.order == "stock" then
        local from, to = Space.Object(state, wing.post), Space.Object(state, wing.base)
        local info = Types.Get(wing.want)
        row.from, row.to = if from then from.name else "?", if to then to.name else "?"
        row.want, row.need, row.keep = if info then info.name else "?", wing.need, wing.keep
        local aboard = Fleet.Bought(state, wing, ship) > 0
        row.doing = if ball then (if aboard then "bringing it in" elseif wing.need > 0 then "going to buy" else "coming back")
          elseif ship.docked ~= wing.base then "buying"
          elseif wing.order == "stock" then "keeping stock" else "unloading"
      elseif wing.order == "patrol" then
        local post = Space.Object(state, wing.post)
        row.post = if post then post.name else "?"
        row.doing = if ball == nil then "mending" elseif ball.intent and ball.intent.kind == "dock" then "going in to mend"
          elseif ball.grid ~= wing.post then "going to their post"
          elseif #ball.vitals.locks > 0 then "fighting" else "patrolling"
      elseif wing.order == "guard" then
        local ward = state.fleet[wing.ward]
        row.ward = if ward then ward.name else "?"
        row.doing = if ball and #ball.vitals.locks > 0 then "fighting" else "guarding"
      elseif wing.order == "stay" then
        row.doing = "waiting"
      else
        row.doing = if ball and #ball.vitals.locks > 0 then "fighting" else "following"
      end
    end
    table.insert(rows, row)
  end
  return rows
end

-- Where a hired pilot whose ship is docked could be set to haul to:
-- the pilot's home station, the other stations of the system the ship
-- is in, the player's own starbases, and the stations of one more
-- system if one is named (where the map's destination is). Each with
-- its name, its system's, how many jumps off it is, and whether it has
-- a market to sell at. Home first, then the nearest: by jumps, and in
-- the ship's own system by how far from where it is docked.
export type HaulTarget = { id: number, name: string, system: string, jumps: number, market: boolean }
function Query.HaulTargets(game: Game, pilot: number, also: number?): { HaulTarget }
  local state = game.state
  local wing = state.fleet[pilot]
  local ship = if wing then state.ships[wing.ship] else nil
  local found: { HaulTarget } = {}
  if ship == nil or ship.docked == 0 then
    return found
  end
  local here = Space.SystemOf(state, ship.docked)
  local origin = Space.Object(state, ship.docked)
  local seen: { [number]: boolean } = { [ship.docked] = true }
  local far: { [number]: number } = {}
  local function add(id: number)
    local object = Space.Object(state, id)
    local starbase = state.starbases[id]
    if object == nil or object.kind ~= "station" or seen[id] or (starbase ~= nil and starbase.ready > state.tick) then
      return
    end
    seen[id] = true
    local system = Space.SystemOf(state, id)
    local route = Galaxy.Route(state.galaxy, here, system)
    if #route > 0 then
      far[id] = if system == here and origin then Space.Distance(origin :: any, object :: any) else 0
      table.insert(found, { id = id, name = object.name, system = state.galaxy.systems[system].name, jumps = #route - 1,
        market = Stations.Has(state, id, "market") })
    end
  end
  add(state.player.home)
  local rest = #found + 1
  for _, system in { here, also or here } do
    for _, object in Space.Describe(state, system).objects do
      if object.kind == "station" then
        add(object.id)
      end
    end
  end
  for _, id in state.starbaseIds do
    add(id)
  end
  -- (home stays first: the others by how far, then as they were found)
  local order: { [number]: number } = {}
  for at, target in found do
    order[target.id] = at
  end
  local tail: { HaulTarget } = {}
  for at = rest, #found do
    table.insert(tail, found[at])
  end
  table.sort(tail, function(a: HaulTarget, b: HaulTarget): boolean
    if a.jumps ~= b.jumps then
      return a.jumps < b.jumps
    elseif far[a.id] ~= far[b.id] then
      return far[a.id] < far[b.id]
    end
    return order[a.id] < order[b.id]
  end)
  for at = rest, #found do
    found[at] = tail[at - rest + 1]
  end
  return found
end

-- Where else a thing can be bought: the markets within a few jumps
-- (Fleet.SHOPS) of a station that have any, the best first. For each,
-- its name and its system's, how many jumps off, how many it would
-- sell of the 'quantity' asked for (all it has, if that is fewer), and
-- what those would cost there now, in all and each. The best is one
-- that has them all before one that has not, then the cheapest for
-- one, then the nearest. (Nothing is opened or kept by asking.)
export type Source = { id: number, name: string, system: string, jumps: number, units: number, cost: number, each: number }
function Query.Sources(game: Game, station: number, type: string, quantity: number): { Source }
  local state = game.state
  local found: { Source } = {}
  if Space.Object(state, station) == nil or Market.Index(type) == nil or quantity < 1 then
    return found
  end
  -- (the systems within reach, nearest first)
  local systems = state.galaxy.systems
  local here = Space.SystemOf(state, station)
  local jumps: { [number]: number } = { [here] = 0 }
  local queue = { here }
  local at = 1
  while at <= #queue do
    local system = queue[at]
    at += 1
    for _, object in Space.Glance(state, system).objects do
      if object.kind == "station" and object.id ~= station and Stations.Has(state, object.id, "market") then
        local units, cost = Market.Asks(state, object.id, type, quantity)
        if units > 0 then
          table.insert(found, { id = object.id, name = object.name, system = systems[system].name, jumps = jumps[system],
            units = units, cost = cost, each = cost / units })
        end
      end
    end
    if jumps[system] < Fleet.SHOPS then
      for _, neighbor in systems[system].neighbors do
        if jumps[neighbor] == nil then
          jumps[neighbor] = jumps[system] + 1
          table.insert(queue, neighbor)
        end
      end
    end
  end
  table.sort(found, function(a: Source, b: Source): boolean
    local wholeA, wholeB = a.units >= quantity, b.units >= quantity
    if wholeA ~= wholeB then
      return wholeA
    elseif a.each ~= b.each then
      return a.each < b.each
    elseif a.jumps ~= b.jumps then
      return a.jumps < b.jumps
    end
    return a.id < b.id
  end)
  return found
end

-- Who is looking for work at a station today, and how many pilots the
-- player can command.
function Query.Candidates(game: Game, station: number): ({ Fleet.Candidate }, number)
  return Fleet.Candidates(game.state, station), Fleet.Max(game.state)
end

-- Why a hired pilot cannot fly a ship as it is fitted, or nil if they
-- can.
function Query.CanFly(game: Game, pilot: number, ship: number): string?
  local wing = game.state.fleet[pilot]
  local record = game.state.ships[ship]
  if wing == nil or record == nil then
    return "no such pilot"
  end
  return Fleet.Cannot(game.state, wing, record)
end

-- What the ship's scanner shows of the system the pilot is in: every
-- site still there, found or not. One not found is a signal with a
-- code and no more. And the seconds until the scanner can be used again.
-- (And for one not found: the planet it is by, once the scanner has got
-- a quarter of the way with it; how many probes are near enough to
-- help; and whether it is too faint to get further with from here, with
-- no probe by it.) Last, the probes: how many are out in this system,
-- how many in all, how many there can be, and how many are in the hold.
export type SiteStatus = {
  id: number, name: string, kind: string,   -- kind is "" until it is found
  strength: number, found: boolean, distance: number,
  near: string, probes: number, faint: boolean,
}
export type ProbeStatus = { here: number, out: number, max: number, carried: number }
function Query.Sites(game: Game): ({ SiteStatus }, number, ProbeStatus)
  local state = game.state
  local player = Query.Player(game)
  local me = state.balls[player.ship]
  local found: { SiteStatus } = {}
  for _, site in Sites.In(state, player.system) do
    local object = Space.Object(state, site.id) :: System.Object
    local known = site.strength >= 1
    -- (a part of a camp that a job has not opened yet is not a signal)
    local unopened = string.sub(site.kind, 1, 7) == "mission" and not known
    if unopened then
      continue
    end
    local kind: string = site.kind
    local by = Space.Object(state, object.parent)
    local probes, near = Sites.Covered(state, site, me)
    table.insert(found, {
      id = site.id, name = if known then object.name else `Signal {site.code}`, kind = if known then kind else "",
      strength = site.strength, found = known, distance = if me then Space.Gap(me :: any, object :: any) else 0,
      near = if by and site.strength >= 0.25 then by.name else "", probes = probes,
      faint = not known and not near and site.strength >= (Sites.ALONE[kind] or 1),
    })
  end
  local carried = 0
  for _, item in Items.In(state, player.ship, "cargo") do
    carried += if item.type == Sites.PROBE then item.quantity else 0
  end
  return found, math.max(0, state.scanReady - state.tick) * Constants.TICK,
    { here = #Sites.Probes(state, player.system), out = #state.probeIds, max = Sites.PROBES, carried = carried }
end

-- The nomads' colony fleets, and where each is now (Tactical/Nomads):
-- whose it is, what its colony ship is called, the system it is in, the
-- one it goes to next, and in how many seconds it goes.
export type NomadStatus = { faction: string, name: string, system: number, next: number, leaves: number }
function Query.Nomads(game: Game): { NomadStatus }
  local found: { NomadStatus } = {}
  for _, sighting in Nomads.Where(game.state) do
    table.insert(found, { faction = sighting.faction, name = sighting.name, system = sighting.system, next = sighting.next,
      leaves = (sighting.leaves - game.state.tick) * Constants.TICK })
  end
  return found
end

-- A colony ship of the nomads is a ship in space and a station
-- (Tactical/Nomads, Tactical/Space). The station a ship in space is, if
-- it is one of theirs: nil for any other ship. (To dock at the ship is
-- to dock at the station.)
function Query.Berth(game: Game, ship: number): number?
  return Nomads.Berth(game.state, ship)
end

-- And the other way: whether a station is a colony ship, and the ship
-- it is in space (0 when it is not there to be seen: nobody of the
-- pilot's is in its system, or it is gone); and, for a pilot aboard, the
-- system it goes to next and in how many seconds.
function Query.Carrier(game: Game, station: number): (boolean, number, number, number)
  local fleet = Nomads.FleetOf(game.state.galaxy, station)
  if fleet == nil then
    return false, 0, 0, 0
  end
  local ball = Nomads.Ball(game.state, fleet)
  local _, _, next, _, goes = Nomads.At(fleet, game.state.tick)
  return true, if ball then ball.id else 0, next, (goes - game.state.tick) * Constants.TICK
end

-- What each human faction thinks of the pilot, in the order of the
-- factions: from -10 to 10, and whether its patrols fight them on sight.
export type StandingStatus = { faction: string, name: string, standing: number, hostile: boolean }
function Query.Standings(game: Game): { StandingStatus }
  local found: { StandingStatus } = {}
  local holds = Galaxy.Holders(game.state.galaxy)
  for _, faction in Factions.list do
    -- (the human factions always; and any other that keeps order in
    -- space of its own, once it thinks anything of the pilot)
    if faction.kind == "human" or (Galaxy.KeepsOrder(faction.id) and table.find(holds, faction.id) ~= nil
      and Standings.Of(game.state, faction.id) ~= 0) then
      table.insert(found, { faction = faction.id, name = faction.name, standing = Standings.Of(game.state, faction.id),
        hostile = Standings.Hostile(game.state, faction.id) })
    end
  end
  return found
end

-- The jobs to be had and in hand: what the station the pilot is docked
-- at offers (none in space), the jobs the pilot has taken, each with
-- whether it can be finished where they are now (and if not, why not),
-- and their standing with the faction whose station it is.
-- (And a job in hand's seconds left; the pilot's loyalty points with
-- that faction; and what its store has, with whether each can be had
-- now and if not, why not.)
-- ('regard': what the agent who gives it thinks of the pilot. 'jumps':
-- for a courier job, how far its cargo is to be carried. 'line': whose
-- line of work it is, Missions.Line. 'ward': for a defence job whose
-- rig stands, how much of the rig is left, 0 to 1; -1 for any other,
-- and until the pilot has been there.)
export type MissionStatus = { mission: State.Mission, title: string, ready: boolean, why: string, left: number, regard: number,
  jumps: number, line: string, ward: number }
export type StoreRow = { stock: Missions.Stock, name: string, can: boolean, why: string }
export type MissionsStatus = { offers: { MissionStatus }, inHand: { MissionStatus }, faction: string, standing: number, done: number,
  loyalty: number, store: { StoreRow } }
function Query.Missions(game: Game): MissionsStatus
  local state = game.state
  local ship = state.ships[state.player.ship]
  local offers: { MissionStatus } = {}
  local faction, standing, loyalty = "", 0, 0
  local store: { StoreRow } = {}
  if ship.docked ~= 0 then
    for _, offer in Missions.Offers(state, ship.docked) do
      table.insert(offers, { mission = offer, title = Missions.Title(offer), ready = false, why = "", left = 0,
        regard = Missions.Regard(state, offer.station, offer.slot),
        jumps = if offer.kind == "courier" then Missions.Jumps(state, offer) else 0, line = Missions.Line(offer), ward = -1 })
    end
    local node = state.galaxy.systems[Space.SystemOf(state, ship.docked)]
    faction = if Factions.byId[node.nearest] then Factions.byId[node.nearest].name else ""
    standing = Missions.Standing(state, node.nearest)
    loyalty = state.loyalty[node.nearest] or 0
    if state.starbases[ship.docked] == nil then
      for _, stock in Missions.Store(node.nearest) do
        local can, why = validate(state, { kind = "RedeemLoyalty", actor = ship.id, type = stock.type, quantity = 1 })
        table.insert(store, { stock = stock, name = Types.Info(stock.type).name, can = can, why = why or "" })
      end
    end
  end
  local inHand: { MissionStatus } = {}
  for _, mission in Missions.InHand(state) do
    local ready, why = Missions.Ready(state, ship, mission)
    local line = Missions.Line(mission)
    -- (what is left of the rig a defence job is to hold: of all it has, shield, armour and hull)
    local rig = if line == "defence" then state.balls[mission.mark] else nil
    local ward = -1
    if rig then
      local vitals = rig.vitals
      ward = (vitals.shield + vitals.armor + vitals.hull) / math.max(1, vitals.shieldMax + vitals.armorMax + vitals.hullMax)
    end
    table.insert(inHand, { mission = mission, title = Missions.Title(mission), ready = ready, why = why or "",
      left = Missions.Left(state, mission), regard = Missions.Regard(state, mission.station, mission.slot),
      jumps = if mission.kind == "courier" then Missions.Jumps(state, mission) else 0, line = line, ward = ward })
  end
  return { offers = offers, inHand = inHand, faction = faction, standing = standing, done = state.missionsDone,
    loyalty = loyalty, store = store }
end

-- What the pilot has researched of a blueprint (levels of material and
-- of time saving), and what the next level of each would take (nil when
-- there is none). Nothing for no such blueprint.
-- And what inventing the tech 2 make of what it builds would take (nil
-- when there is none to invent).
export type ResearchStatus = { material: number, time: number, nextMaterial: Industry.ResearchPlan?, nextTime: Industry.ResearchPlan?,
  invention: Industry.InventionPlan? }
function Query.Research(game: Game, type: string): ResearchStatus?
  local blueprint = Blueprints.byId[type]
  if blueprint == nil then
    return nil
  end
  local material, time = Industry.Researched(game.state, type)
  return {
    material = material, time = time,
    nextMaterial = Industry.ResearchPlan(game.state, blueprint, "material"),
    nextTime = Industry.ResearchPlan(game.state, blueprint, "time"),
    invention = Industry.InventionPlan(game.state, blueprint),
  }
end

-- What a planet has to take, and how rich it is in each: for any planet
-- of a described system, colony or none. None for anything else.
function Query.Deposits(game: Game, planet: number): { Planets.Deposit }
  local object = Space.Object(game.state, planet)
  return if object and object.kind == "planet" then Planets.Deposits(object.variety, object.seed) else {}
end

-- The planets the player has a colony on, in the order of their ids.
function Query.Colonies(game: Game): { number }
  local state = game.state
  local ship = state.ships[state.player.ship]
  local found: { number } = {}
  for _, id in state.colonyIds do
    if ship and state.colonies[id].owner == ship.owner then
      table.insert(found, id)
    end
  end
  return found
end

-- A colony, by the id of its planet: how it stands. Nil if the planet
-- has none.
export type FacilityStatus = {
  id: number,
  kind: string,
  what: string,
  working: boolean,   -- an extractor on a programme, a processor with a batch in hand
  left: number,       -- seconds its programme has to run, or its batch
  rate: number,       -- units an extractor's next cycle brings up
}
export type ColonyStatus = {
  planet: number,
  name: string,
  variety: string,
  mine: boolean,
  powergrid: number,  -- drawn by its facilities
  cpu: number,
  room: number,       -- of its store, m3
  used: number,
  near: boolean,      -- the player's ship is near enough to take goods up
  deposits: { Planets.Deposit },
  facilities: { FacilityStatus },
  -- (what the player's ship could take of each now: Colonies.Fits)
  store: { { type: string, quantity: number, fits: number } },
}
function Query.Colony(game: Game, planet: number): ColonyStatus?
  local state = game.state
  local colony = state.colonies[planet]
  local object = Space.Object(state, planet)
  if colony == nil or object == nil then
    return nil
  end
  local ship = state.ships[state.player.ship]
  local powergrid, cpu = Colonies.Draw(colony)
  local room, used = Colonies.Room(colony)
  local near = ship ~= nil and Colonies.Near(state, ship.id, planet)
  local facilities: { FacilityStatus } = {}
  for _, pin in colony.pins do
    local extractor = pin.kind == "extractor"
    local working = if extractor then pin.ends > 0 else pin.next > 0
    table.insert(facilities, {
      id = pin.id, kind = pin.kind, what = pin.what, working = working,
      left = if working then math.max(0, (if extractor then pin.ends else pin.next) - state.tick) * Constants.TICK else 0,
      rate = if extractor and working then Planets.Yield(Planets.Richness(object.seed, pin.what), pin.cycle) else 0,
    })
  end
  local store = {}
  for _, stored in colony.store do
    table.insert(store, { type = stored.type, quantity = stored.quantity,
      fits = if near and ship then Colonies.Fits(state, ship.id, colony, stored.type) else 0 })
  end
  return {
    planet = planet, name = object.name, variety = object.variety, mine = ship ~= nil and ship.owner == colony.owner,
    powergrid = powergrid, cpu = cpu, room = room, used = used, near = near,
    deposits = Planets.Deposits(object.variety, object.seed), facilities = facilities, store = store,
  }
end

-- The station a new pilot starts at: the one that has everything.
function Query.Starter(game: Game): number
  return Stations.Starter(game.state)
end

-- What a station is made of (its tower and modules), and the services
-- its modules give. Nil and none if 'id' is not a station.
function Query.Station(game: Game, id: number): (Structures.Makeup?, { Structures.Service })
  return Stations.Makeup(game.state, id), Stations.Services(game.state, id)
end

-- A ship's ball, or nil if it is docked.
function Query.Ball(game: Game, ship: number): State.Ball?
  return game.state.balls[ship]
end

-- The described objects of a system, or nothing if the game has not been
-- there yet.
function Query.Objects(game: Game, system: number): { System.Object }
  local description = game.state.systems[system]
  return if description then description.objects else {}
end

return Core
