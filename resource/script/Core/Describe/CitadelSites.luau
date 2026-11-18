--!strict
-- Where the factions' citadels stand in a system (Assets/Citadels), as
-- a pure function of the galaxy and the system's description: so a
-- system has the same ones whenever it is first looked at.
--
-- How many (the owner, 2026-11-18: "they should be MUCH more common,
-- especially in a faction's *core* space, but also, the higher a
-- system's security rating is, the more stations there should be in
-- general. A 1.0 system should probably have a citadel or station at
-- every other planet"): in a held system, half its planets, times its
-- security, are to have a station or a citadel at them (or at a moon of
-- theirs); where its own stations (Describe/System, which may stand
-- several to a planet) do not make that up, citadels do, each at a
-- planet of its own with nothing at it. And a held system with enough
-- already has one citadel all the same, as likely as its security is
-- high. Open space has none standing: now and then the hulk of one.
--
-- Of what kind: an alien people's one of their own four; any other
-- people's one of the standard kinds, at a size by dice. Every figure
-- here is mine but the half.

local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

local CitadelSites = {}

export type Site = { tower: string, fallen: boolean, body: System.Object }

-- The share of a system's planets that has a station or a citadel, at
-- the highest security.
CitadelSites.SHARE = 0.5
-- One system of open space in so many has the hulk of one; of those
-- hulks, one in so many is an alien people's.
CitadelSites.OPEN = 40
CitadelSites.ALIEN_HULK = 5
-- How likely each kind is, and each size, of a human people's citadel
-- (a generator station is only ever large or extra-large).
CitadelSites.KINDS = { { kind = "habitation", weight = 3 }, { kind = "tradehub", weight = 2 }, { kind = "refinery", weight = 2 },
  { kind = "research", weight = 2 }, { kind = "shipyard", weight = 2 }, { kind = "generator", weight = 1 } }
CitadelSites.SIZES = { 0.3, 0.3, 0.2, 0.12, 0.08 }
-- (the system a game begins in has none: what is there is what a new
-- pilot is shown)
CitadelSites.START = 1

local function weighted(rng: Rng.Rng, weights: { number }): number
  local total = 0
  for _, weight in weights do
    total += weight
  end
  local roll = Rng.Float(rng, 0, total)
  for index, weight in weights do
    roll -= weight
    if roll <= 0 then
      return index
    end
  end
  return #weights
end

-- A citadel of a people's, by dice.
function CitadelSites.Pick(rng: Rng.Rng, people: string): string
  if table.find(Structures.CITADEL_ALIEN_PEOPLES, people) then
    local each = Structures.CITADEL_ALIEN[Rng.Int(rng, #Structures.CITADEL_ALIEN) + 1]
    return `citadel.{people}.{each.kind}.{Structures.CITADEL_SIZES[each.size]}`
  end
  local weights: { number } = {}
  for _, each in CitadelSites.KINDS do
    table.insert(weights, each.weight)
  end
  local kind = CitadelSites.KINDS[weighted(rng, weights)].kind
  local size = weighted(rng, CitadelSites.SIZES)
  local sizes = Structures.CITADEL_KIND_SIZES[kind]
  if sizes and not table.find(sizes, size) then
    size = if size > sizes[#sizes] then sizes[#sizes] else sizes[1]
  end
  return `citadel.{kind}.{Structures.CITADEL_SIZES[size]}`
end

-- Whether a people builds citadels: those who hold stations, but the
-- pirates, who keep towers of their own (Tactical/Keeps).
function CitadelSites.Builds(people: string): boolean
  local faction = Factions.byId[people]
  return faction ~= nil and table.find(Structures.TOWER_PEOPLES, people) ~= nil and faction.kind ~= "pirate"
end

-- The citadels of a system, as its description first is: in order,
-- each at a body (a planet, or a moon of one) of its own.
function CitadelSites.Of(galaxy: Galaxy.Galaxy, description: System.Description): { Site }
  local id = description.id
  local node = galaxy.systems[id]
  local out: { Site } = {}
  if node == nil or node.uncharted or id == CitadelSites.START then
    return out
  end
  -- The planets, and which have a station at them or at a moon of theirs.
  local planets: { System.Object } = {}
  local moons: { [number]: { System.Object } } = {}
  local byId: { [number]: System.Object } = {}
  for _, object in description.objects do
    byId[object.id] = object
    if object.kind == "planet" then
      table.insert(planets, object)
      moons[object.id] = {}
    end
  end
  for _, object in description.objects do
    if object.kind == "moon" and moons[object.parent] then
      table.insert(moons[object.parent], object)
    end
  end
  local busy: { [number]: boolean } = {}
  for _, object in description.objects do
    if object.kind == "station" then
      local host = byId[object.parent]
      if host then
        busy[if host.kind == "moon" then host.parent else host.id] = true
      end
    end
  end
  local free: { System.Object } = {}
  for _, planet in planets do
    if not busy[planet.id] then
      table.insert(free, planet)
    end
  end
  local rng = Rng.For(galaxy.seed, id, 7001)
  -- (the free planets in an order of the system's own)
  for index = #free, 2, -1 do
    local other = Rng.Int(rng, index) + 1
    free[index], free[other] = free[other], free[index]
  end
  local function at(planet: System.Object): System.Object
    local round = moons[planet.id]
    if #round > 0 and Rng.Chance(rng, 0.5) then
      return round[Rng.Int(rng, #round) + 1]
    end
    return planet
  end
  local owner = node.owner
  if owner ~= "" and CitadelSites.Builds(owner) then
    local wanted = math.floor(#planets * CitadelSites.SHARE * node.security + 0.5)
    local count = math.max(0, wanted - (#planets - #free))
    if count == 0 and Rng.Chance(rng, node.security) then
      count = 1
    end
    for index = 1, math.min(count, #free) do
      table.insert(out, { tower = CitadelSites.Pick(rng, owner), fallen = false, body = at(free[index]) })
    end
  elseif owner == "" and #free > 0 and Rng.Chance(rng, 1 / CitadelSites.OPEN) then
    local alien = Rng.Chance(rng, 1 / CitadelSites.ALIEN_HULK)
    local people = if alien then Structures.CITADEL_ALIEN_PEOPLES[Rng.Int(rng, #Structures.CITADEL_ALIEN_PEOPLES) + 1] else node.nearest
    table.insert(out, { tower = CitadelSites.Pick(rng, people), fallen = true, body = at(free[1]) })
  end
  return out
end

return CitadelSites
