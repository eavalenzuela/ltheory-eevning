--!strict
-- Drones: the kinds there are. A drone is an item in a hold until it is
-- launched, and then a ship of its own (Tactical/Drones has the rules):
-- this says what item, what hull it flies as (Data/Ships), and what it
-- is armed with.

-- A drone is for one thing: a "combat" drone fights, a "mining" drone
-- cuts the rock its owner is working and brings the ore back, and a
-- "repair" drone mends whoever of its owner's side is worst hurt.
-- 'gun' is the one module it carries, and 'charge' what that is loaded
-- with ("" for a module that is loaded with nothing).
-- 'level' is the Drones skill it takes to have one out. A tech 2 drone
-- is the improved make of the drone 'base' (below).
--
-- A fighter and a bomber are drones to the rules ('craft' says which):
-- launched, recalled and sent at a target as drones are, and counted
-- with them. But only a hull with a bay for them launches one
-- (Data/Ships' CRAFT: a carrier fighters, a supercarrier and an
-- ultracapital bombers too), and it is the Fighters skill it takes
-- ('skill'), which is also what lets a pilot have more out than the
-- Drones skill does (Tactical/Drones).
export type DroneType = {
  id: string, name: string, volume: number, basePrice: number,
  hull: string, role: "combat" | "mining" | "repair", gun: string, charge: string,
  level: number, tech: number?, base: string?,
  craft: string?,       -- "fighter" or "bomber"; nil for a drone
  skill: string?,       -- the skill 'level' is of: "drones" if not said
  pylon: boolean?,      -- launched only from a Fighter Pylon (Data/Modules), never from a bay
  sentry: boolean?,     -- does not move: fights from where it was put out (Tactical/Drones)
}

local Drones = {}

Drones.list = {
  { id = "drone.light", name = "Light Combat Drone", volume = 5, basePrice = 12000, hull = "drone.hull.light",
    role = "combat", gun = "drone.gun.light", charge = "ammo.fusion", level = 1 },
  { id = "drone.medium", name = "Medium Combat Drone", volume = 10, basePrice = 45000, hull = "drone.hull.medium",
    role = "combat", gun = "drone.gun.medium", charge = "ammo.fusion.medium", level = 1 },
  -- (2026-11-24, the owner: "there are no heavy attack drones ... Also,
  -- sentry drones would be good". A heavy drone is slow and hits hard
  -- with a battleship's rounds; a sentry does not move at all, and hits
  -- from far off. Each is 25 m3, a battleship's bay holds five. Figures
  -- mine.)
  { id = "drone.heavy", name = "Heavy Combat Drone", volume = 25, basePrice = 150000, hull = "drone.hull.heavy",
    role = "combat", gun = "drone.gun.heavy", charge = "ammo.fusion.large", level = 3 },
  { id = "drone.sentry", name = "Sentry Drone", volume = 25, basePrice = 200000, hull = "drone.hull.sentry",
    role = "combat", gun = "drone.gun.sentry", charge = "ammo.fusion.large", level = 3, sentry = true },
  { id = "drone.mining", name = "Mining Drone", volume = 10, basePrice = 30000, hull = "drone.hull.mining",
    role = "mining", gun = "miner.drone", charge = "", level = 1 },
  { id = "drone.repair", name = "Armor Repair Drone", volume = 10, basePrice = 60000, hull = "drone.hull.repair",
    role = "repair", gun = "remote.armor.drone", charge = "", level = 1 },
} :: { DroneType }

-- Tech 2: the improved make of each. It flies the tougher, quicker make
-- of the drone's hull (Data/Ships) and carries the tech 2 make of what
-- the plain one carries (Data/Modules), and it takes Drones 4 to have
-- one out. Nobody sells one: its blueprint is invented from the plain
-- drone's, and it is built of the plain drone (Data/Blueprints).
Drones.TECH2 = { price = 5, level = 4 }
for _, base in table.clone(Drones.list) do
  table.insert(Drones.list, {
    id = base.id .. ".ii", name = base.name .. " II", volume = base.volume, basePrice = base.basePrice * Drones.TECH2.price,
    hull = base.hull .. ".ii", role = base.role, gun = base.gun .. ".ii", charge = base.charge,
    level = Drones.TECH2.level, tech = 2, base = base.id, sentry = base.sentry,
  })
end

-- Fighters and bombers (they have no tech 2 make). A fighter is four
-- medium drones' worth of gun on a hull that takes some killing, for
-- ships of any size; a bomber throws the heaviest missiles there are at
-- what is big, and takes Fighters 3. (First figures.)
table.insert(Drones.list, { id = "drone.fighter", name = "Fighter", volume = 150, basePrice = 4000000, hull = "drone.hull.fighter",
  role = "combat", gun = "fighter.cannon", charge = "ammo.fusion.medium", level = 1, craft = "fighter", skill = "fighters" })
table.insert(Drones.list, { id = "drone.bomber", name = "Bomber", volume = 300, basePrice = 12000000, hull = "drone.hull.bomber",
  role = "combat", gun = "bomber.rack", charge = "missile.siege.explosive", level = 3, craft = "bomber", skill = "fighters" })

-- The Drowned's Trident (the owner, 2026-11-19): "a specially-designed
-- one, that has fighter-like damage, but can only be launched via" the
-- Fighter Pylon, which carries one on the hull. Drones 5. (Its price
-- mine.)
table.insert(Drones.list, { id = "drone.trident", name = "Trident", volume = 150, basePrice = 6000000, hull = "drone.hull.trident",
  role = "combat", gun = "fighter.cannon", charge = "ammo.fusion.medium", level = 5, pylon = true })

Drones.byId = {} :: { [string]: DroneType }
for _, drone in Drones.list do
  Drones.byId[drone.id] = drone
end

-- The tech 2 make of a drone, if it has one.
function Drones.Improved(id: string): DroneType?
  local better = Drones.byId[id .. ".ii"]
  return if better and better.tech == 2 then better else nil
end

return Drones
