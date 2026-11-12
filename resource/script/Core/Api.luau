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
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Careers = require("@lt/Core/Character/Careers")
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
local Training = require("@lt/Core/Character/Training")
local Types = require("@lt/Core/Data/Types")

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
Core.SAVE_VERSION = 56

-- MIGRATIONS[n] turns the state of a version n save into version n + 1.
-- Load applies them in turn, so a save from any version listed here
-- still opens.
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
    trades = {},
    starbases = {},
    starbaseIds = {},
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
local COMBAT_COMMANDS = { LockTarget = true, UnlockTarget = true, ActivateModule = true, DeactivateModule = true }
local AFTERMATH_COMMANDS = { Loot = true, Repair = true }
local INDUSTRY_COMMANDS = { Reprocess = true, StartJob = true, StartResearch = true }
local TRAINING_COMMANDS = { LearnSkill = true, TrainSkill = true, CancelTraining = true }
local MARKET_COMMANDS = { BuyNow = true, SellNow = true, PlaceOrder = true, CancelOrder = true }
local HANGAR_COMMANDS = { Assemble = true, BoardShip = true }
local STARBASE_COMMANDS = { AnchorTower = true, Fuel = true, AnchorModule = true, UnanchorModule = true }
local SITE_COMMANDS = { Scan = true, LaunchProbe = true, RecallProbes = true }
local HACK_COMMANDS = { StartHack = true, HackNode = true, AbandonHack = true }
local DRONE_COMMANDS = { LaunchDrones = true, RecallDrones = true, EngageDrones = true }
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
  Traffic.Step(state, game.events)
  Pirates.Think(state, game.events)
  Drones.Step(state, game.events)
  Fleet.Step(state, game.events)
  Space.Decide(state, game.events)
  Aftermath.Step(state, game.events)
  Mining.Step(state)
  Market.Step(state, game.events)
  Starbases.Step(state, game.events)
  Raids.Step(state, game.events)
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
    local site = state.sites[object.id]
    if site and not onGrid and Sites.Hidden(state, object.id) then
      gone = true
    end
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
        hostile = state.ships[id].owner == "pirates" or state.pilots[id] ~= nil, own = state.ships[id].owner == "player" }
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
  for _, item in Items.Fitted(game.state, ship) do
    local module = Modules.byId[item.type]
    cpu += module.cpu
    powergrid += module.powergrid
  end
  return cpu, powergrid
end

function Query.CargoUsed(game: Game, ship: number): number
  return Items.CargoUsed(game.state, ship)
end

-- What repairing the player's docked ship would cost.
function Query.RepairCost(game: Game): number
  return Aftermath.RepairCost(game.state, game.state.ships[game.state.player.ship])
end

-- Whether a ship is cloaked: nobody can target it.
function Query.Cloaked(game: Game, ship: number): boolean
  return Combat.Cloaked(game.state, ship)
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
export type CorporationInfo = {
  founded: boolean, name: string, since: number, wallet: number, journal: { State.Entry }, earned: number, spent: number,
  fee: number, staff: number, wages: number,
}
function Query.Corporation(game: Game): CorporationInfo
  local state = game.state
  local corporation = state.corporation
  -- (what its pilots are paid a day, all told)
  local wages = 0
  for _, id in state.fleetIds do
    wages += state.fleet[id].wage
  end
  return {
    founded = Corporation.Founded(state), name = corporation.name, since = corporation.founded, wallet = corporation.wallet,
    journal = corporation.journal, earned = corporation.earned, spent = corporation.spent, fee = Corporation.FEE,
    staff = Corporation.STAFF, wages = wages,
  }
end

function Query.Orders(game: Game, station: number?): { State.Order }
  return Market.Orders(game.state, station)
end

function Query.History(game: Game, station: number, type: string): { State.TradeDay }
  return Market.History(game.state, station, type)
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
        ships = {}, items = {}, volume = 0, worth = 0,
      }
      places[station] = place
      table.insert(order, station)
    end
    return place
  end
  for _, id in state.itemIds do
    local item = state.items[id]
    local hold = item.holder == me.id and item.place == "cargo"
    if hold or (item.place == "hangar" and Space.Object(state, item.holder) ~= nil) then
      local place = at(if hold then 0 else item.holder)
      local info = Types.Info(item.type)
      table.insert(place.items, item)
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

-- What running a blueprint so many times at a station would take, or nil
-- if the type is not a blueprint.
function Query.JobPlan(game: Game, station: number, type: string, runs: number): Industry.Plan?
  local blueprint = Blueprints.byId[type]
  return if blueprint then Industry.Plan(game.state, station, blueprint, runs) else nil
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
  -- What it has against a raid (Tactical/Raids): its strength, how
  -- many batteries of it are online and how many hired pilots hold the
  -- place; and how strong the raids that come there are, at least and
  -- at most (0 and 0 where order is kept, and nobody comes).
  defence: number, batteries: number, patrol: number,
  raidLeast: number, raidMost: number,
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
  local defence, batteries, patrol = Raids.Defence(state, starbase)
  local raids = Raids.STRENGTH[Raids.Band(state, starbase)]
  return {
    tower = Structures.towerById[starbase.tower], mine = ship ~= nil and ship.owner == starbase.owner,
    anchored = Starbases.Anchored(state, starbase), wait = math.max(0, starbase.ready - state.tick) * Constants.TICK, lit = lit,
    fuel = starbase.fuel, hours = Starbases.Hours(starbase), powergrid = powergrid, cpu = cpu, modules = modules,
    moon = if moon then moon.name else "", drilling = drilling,
    next = if drilling.online and drilling.deposit then math.max(0, starbase.drilled + 3600 / Constants.TICK - state.tick) * Constants.TICK
      else 0,
    defence = defence, batteries = batteries, patrol = patrol,
    raidLeast = if raids then raids[1] else 0, raidMost = if raids then raids[2] else 0,
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
  id: number, name: string, skill: number, wage: number, order: string, target: number,
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
  -- for one sent to buy ('from' is the market's name and 'to' that of
  -- the station it is brought to): the name of the thing, and how many
  -- are still to be bought
  want: string, need: number,
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
      id = wing.id, name = wing.name, skill = wing.skill, wage = wing.wage, order = wing.order, target = wing.target,
      ship = 0, shipName = "", hull = "", where = "no ship", near = false, distance = 0, shield = 1, armor = 1, structure = 1,
      doing = "no ship", hauled = wing.hauled, experience = wing.experience,
      cargo = wing.cargo, from = "", to = "", stops = {}, sells = wing.sell, earned = wing.earned,
      want = "", need = 0,
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
        local from, to = Space.Object(state, wing.post), Space.Object(state, wing.base)
        row.from, row.to = if from then from.name else "?", if to then to.name else "?"
        for _, stop in wing.stops do
          local object = Space.Object(state, stop)
          table.insert(row.stops, if object then object.name else "?")
        end
        local laden = false
        for _, item in Items.In(state, ship.id, "cargo") do
          laden = laden or Fleet.Carries(wing.cargo, item.type)
        end
        -- (out flying: on the way to deliver, to the next station of the round, or back to the first)
        local _, why = Fleet.HaulGoal(state, wing, ship)
        row.doing = if ball then (if why == "collect" and laden then "collecting" elseif laden then "carrying" else "going back for more")
          elseif ship.docked == wing.base then "unloading"
          elseif laden then "loading" else "waiting for cargo"
      elseif wing.order == "buy" then
        local from, to = Space.Object(state, wing.post), Space.Object(state, wing.base)
        local info = Types.Get(wing.want)
        row.from, row.to = if from then from.name else "?", if to then to.name else "?"
        row.want, row.need = if info then info.name else "?", wing.need
        local aboard = Fleet.Bought(state, wing, ship) > 0
        row.doing = if ball then (if aboard then "bringing it in" elseif wing.need > 0 then "going to buy" else "coming back")
          elseif ship.docked == wing.base then "unloading" else "buying"
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

-- What each human faction thinks of the pilot, in the order of the
-- factions: from -10 to 10, and whether its patrols fight them on sight.
export type StandingStatus = { faction: string, name: string, standing: number, hostile: boolean }
function Query.Standings(game: Game): { StandingStatus }
  local found: { StandingStatus } = {}
  for _, faction in Factions.list do
    if faction.kind == "human" then
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
-- for a courier job, how far its cargo is to be carried.)
export type MissionStatus = { mission: State.Mission, title: string, ready: boolean, why: string, left: number, regard: number,
  jumps: number }
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
        jumps = if offer.kind == "courier" then Missions.Jumps(state, offer) else 0 })
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
    table.insert(inHand, { mission = mission, title = Missions.Title(mission), ready = ready, why = why or "",
      left = Missions.Left(state, mission), regard = Missions.Regard(state, mission.station, mission.slot),
      jumps = if mission.kind == "courier" then Missions.Jumps(state, mission) else 0 })
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
