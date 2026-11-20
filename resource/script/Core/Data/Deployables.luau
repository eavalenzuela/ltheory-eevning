--!strict
-- Deployables: what a pilot puts out into space from the hold and picks
-- up again (the owner, 2026-11-20: "start taking a look into deployables
-- ... We're missing almost all of those"). Each is a container in space
-- of the pilot's (Tactical/Deploy), with a use of its own:
--
--   depot     a hold of its own out where the pilot works, and a ship
--             within reach of it may be refitted there, from its hold
--             and the depot's
--   tractor   draws in the wrecks within its reach, one at a time, and
--             takes what is in them into its hold; it lasts two days
--   beacon    a lit beacon for the pilot's jump drives (Tactical/
--             Jumping), for an hour
--   bubble    an interdiction field (Tactical/Combat) where it stands,
--             until it is picked up: nobody warps out of it, nor through
--             it. Not where order is kept.
--
-- The holds, reaches, lives and field sizes are the reference's; the
-- names, prices and the rest are mine.

export type Deployable = {
  id: string,
  name: string,
  kind: string,      -- "depot", "tractor", "beacon" or "bubble"
  volume: number,    -- m3, packed
  basePrice: number,
  hold: number,      -- m3 it holds (0: nothing)
  life: number?,     -- seconds it lasts once put out (nil: until it is picked up)
  reach: number?,    -- m: a tractor's reach, a field's radius
  every: number?,    -- s: a tractor's time for each wreck
  model: string,     -- what it is drawn as (Game/View/Starbase's modules)
  size: number,      -- m, its radius in space
  note: string,
}

local Deployables = {}

Deployables.list = {
  { id = "deploy.depot", name = "Field Depot", kind = "depot", volume = 50, basePrice = 250000, hold = 3000, model = "array.storage",
    size = 40, note = "Put out in space, it holds what you leave in it until you pick it up again, and a ship within reach of it can be refitted there, from its own hold and the depot's." },
  { id = "deploy.tractor", name = "Salvage Tractor Post", kind = "tractor", volume = 100, basePrice = 1500000, hold = 27000,
    life = 2 * 86400, reach = 125000, every = 30, model = "array.hangar", size = 50,
    note = "Put out where you fight, it draws in the wrecks within 125 km, one every 30 seconds, and takes what is in them into its hold. It lasts two days." },
  { id = "deploy.beacon", name = "Jump Beacon Buoy", kind = "beacon", volume = 400, basePrice = 3000000, hold = 0, life = 3600,
    model = "array.beacon", size = 60,
    note = "A lit beacon for your ships' jump drives, where you put it out, for an hour." },
  { id = "deploy.bubble.small", name = "Small Interdiction Buoy", kind = "bubble", volume = 65, basePrice = 1000000, hold = 0, reach = 5000,
    model = "battery", size = 25,
    note = "An interdiction field 5 km across where you put it out: nothing in it warps out, until you pick it up again. Not where order is kept." },
  { id = "deploy.bubble.medium", name = "Medium Interdiction Buoy", kind = "bubble", volume = 195, basePrice = 3000000, hold = 0,
    reach = 11500, model = "battery", size = 35,
    note = "An interdiction field 11.5 km across where you put it out: nothing in it warps out, until you pick it up again. Not where order is kept." },
  { id = "deploy.bubble.large", name = "Large Interdiction Buoy", kind = "bubble", volume = 585, basePrice = 8000000, hold = 0,
    reach = 26500, model = "battery", size = 50,
    note = "An interdiction field 26.5 km across where you put it out: nothing in it warps out, until you pick it up again. Not where order is kept." },
} :: { Deployable }

Deployables.byId = {} :: { [string]: Deployable }
for _, each in Deployables.list do
  Deployables.byId[each.id] = each
end

-- How near a ship has to be to put one out, pick it up, or use it (a
-- depot's refit): as near as it is to loot (Tactical/Aftermath).
Deployables.REACH = 2500
-- How far from a station or a gate one has to be put out (mine).
Deployables.CLEAR = 5000

return Deployables
