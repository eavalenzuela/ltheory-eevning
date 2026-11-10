--!strict
-- Hull types. M1 needs only what movement uses; fitting, tank and the
-- rest arrive with the attribute engine in M2.
--
-- agility: the time constant of the ship's exponential approach to a new
-- velocity is inertia * mass / 1e6 seconds. Time to align for warp (reach
-- 75% of top speed from rest) is 1.386 times that.

export type ShipType = {
  id: string,
  name: string,
  class: string,
  mass: number,          -- kg
  inertia: number,       -- inertia modifier
  maxVelocity: number,   -- m/s
  warpSpeed: number,     -- AU/s
  radius: number,        -- m
}

local types: { ShipType } = {
  { id = "frigate.courier", name = "Kestrel Courier", class = "frigate",
    mass = 1100000, inertia = 3.2, maxVelocity = 360, warpSpeed = 5, radius = 40 },
  { id = "industrial.hauler", name = "Mule Hauler", class = "industrial",
    mass = 11000000, inertia = 1.0, maxVelocity = 130, warpSpeed = 4.5, radius = 180 },
}

local Ships = { list = types, byId = {} :: { [string]: ShipType } }

for _, t in types do
  Ships.byId[t.id] = t
end

-- Seconds; see the note on agility above.
function Ships.TimeConstant(t: ShipType): number
  return t.inertia * t.mass / 1e6
end

return Ships
