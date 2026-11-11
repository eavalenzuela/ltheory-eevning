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
export type DroneType = {
  id: string, name: string, volume: number, basePrice: number,
  hull: string, role: "combat" | "mining" | "repair", gun: string, charge: string,
}

local Drones = {}

Drones.list = {
  { id = "drone.light", name = "Light Combat Drone", volume = 5, basePrice = 12000, hull = "drone.hull.light",
    role = "combat", gun = "autocannon.small", charge = "ammo.fusion" },
  { id = "drone.medium", name = "Medium Combat Drone", volume = 10, basePrice = 45000, hull = "drone.hull.medium",
    role = "combat", gun = "autocannon.medium", charge = "ammo.fusion.medium" },
  { id = "drone.mining", name = "Mining Drone", volume = 10, basePrice = 30000, hull = "drone.hull.mining",
    role = "mining", gun = "miner.drone", charge = "" },
  { id = "drone.repair", name = "Armor Repair Drone", volume = 10, basePrice = 60000, hull = "drone.hull.repair",
    role = "repair", gun = "remote.armor.drone", charge = "" },
} :: { DroneType }

Drones.byId = {} :: { [string]: DroneType }
for _, drone in Drones.list do
  Drones.byId[drone.id] = drone
end

return Drones
