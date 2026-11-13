--!strict
-- Reactions: what is made of what comes up out of the moons.
--
-- What a drill brings up (Data/Moons) is not built with as it is. A
-- tower with a reactor anchored on it (the "Reactor Array" of
-- Data/Structures; Assets/Starbases has the rules) makes a composite of
-- it: one of each grade, made of that grade's two materials, a unit of
-- each to a unit of the composite, a batch an hour. So no moon makes a
-- composite by itself: the other material is drilled at another moon,
-- or bought.
--
-- The composites are what the tech 2 make of anything is built with
-- (Data/Blueprints): small things of the common one, cruiser-sized
-- things of the middle one, and the largest of the rare. Stations trade
-- in them, thinly, as they do in the materials: nobody needs a reactor
-- to begin.
--
-- (Every figure here is a first proposal, to be played and judged.)

local Moons = require("@lt/Core/Data/Moons")

local Reactions = {}

export type Composite = {
  id: string,           -- "composite.saltglass"
  name: string,
  grade: number,        -- 1 common, 2 middle, 3 rare: the grade of what it is made of
  from: { string },     -- the two materials, a unit of each to a unit of it
  volume: number,       -- m3 a unit
  basePrice: number,    -- credits a unit
}

-- Units a reactor makes in an hour, of as many of each material.
Reactions.BATCH = 100
-- What a composite is worth above what went into it: the reactor's
-- keep, and its owner's.
Reactions.MARGIN = 0.25

local NAMES = { { "composite.saltglass", "Saltglass" }, { "composite.cadvan", "Cadvan Alloy" }, { "composite.prodyne", "Prodyne Lattice" } }

Reactions.composites = {} :: { Composite }
Reactions.byId = {} :: { [string]: Composite }
for grade, named in NAMES do
  local from: { string } = {}
  local worth = 0
  for _, material in Moons.materials do
    if material.grade == grade then
      table.insert(from, material.id)
      worth += material.basePrice
    end
  end
  local composite: Composite = { id = named[1], name = named[2], grade = grade, from = from, volume = 1,
    basePrice = math.floor(worth * (1 + Reactions.MARGIN) + 0.5) }
  table.insert(Reactions.composites, composite)
  Reactions.byId[composite.id] = composite
end

-- The composite the tech 2 make of something is built with, by how big
-- the thing is (1 small: a frigate, a destroyer, a small module or a
-- drone; 2 medium; 3 large).
function Reactions.For(size: number): Composite
  return Reactions.composites[math.clamp(size, 1, #Reactions.composites)]
end

-- The composite a material goes into.
function Reactions.Of(material: string): Composite?
  for _, composite in Reactions.composites do
    if table.find(composite.from, material) then
      return composite
    end
  end
  return nil
end

return Reactions
