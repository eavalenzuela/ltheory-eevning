--!strict
-- Drones: the kinds there are. A drone is an item in a hold until it is
-- launched, and then a ship of its own (Tactical/Drones has the rules):
-- this says what item, what hull it flies as (Data/Ships), and what it
-- is armed with.

export type DroneType = {
  id: string, name: string, volume: number, basePrice: number,
  hull: string, gun: string, charge: string,
}

local Drones = {}

Drones.list = {
  { id = "drone.light", name = "Light Combat Drone", volume = 5, basePrice = 12000, hull = "drone.hull.light",
    gun = "autocannon.small", charge = "ammo.fusion" },
  { id = "drone.medium", name = "Medium Combat Drone", volume = 10, basePrice = 45000, hull = "drone.hull.medium",
    gun = "autocannon.medium", charge = "ammo.fusion.medium" },
} :: { DroneType }

Drones.byId = {} :: { [string]: DroneType }
for _, drone in Drones.list do
  Drones.byId[drone.id] = drone
end

return Drones
