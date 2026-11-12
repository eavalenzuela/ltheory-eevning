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
export type DroneType = {
  id: string, name: string, volume: number, basePrice: number,
  hull: string, role: "combat" | "mining" | "repair", gun: string, charge: string,
  level: number, tech: number?, base: string?,
}

local Drones = {}

Drones.list = {
  { id = "drone.light", name = "Light Combat Drone", volume = 5, basePrice = 12000, hull = "drone.hull.light",
    role = "combat", gun = "autocannon.small", charge = "ammo.fusion", level = 1 },
  { id = "drone.medium", name = "Medium Combat Drone", volume = 10, basePrice = 45000, hull = "drone.hull.medium",
    role = "combat", gun = "autocannon.medium", charge = "ammo.fusion.medium", level = 1 },
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
    level = Drones.TECH2.level, tech = 2, base = base.id,
  })
end

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
