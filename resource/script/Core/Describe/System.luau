--!strict
-- One solar system as data: the star, planets, moons, asteroid belts and
-- their rocks, stations and stargates, at astronomical scale.
--
-- Describe is a pure function of the galaxy seed and the system's place
-- in the galaxy. Its result is stored in the game state (and so in the
-- save): once a game has seen a system, changing this generator cannot
-- move anything in it. Only what the player sees is regenerated, from the
-- seeds kept on each object.
--
-- Positions are metres with the star at the origin; the orbital plane is
-- x-z and y is "up". An object's id is system * STRUCTURE_ID_SPAN + its
-- index in 'objects', so objects[id % STRUCTURE_ID_SPAN] finds it.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")

local System = {}

export type Kind = "sun" | "planet" | "moon" | "belt" | "asteroid" | "station" | "gate"

export type Object = {
  id: number,
  kind: Kind,
  name: string,
  x: number,
  y: number,
  z: number,
  radius: number,     -- m; 0 for a belt, which is only a place
  seed: number,       -- for whatever the view generates to show it
  parent: number,     -- id of the body it belongs to; 0 for the star
  -- The grid anchor it sits on: itself for a station, gate or belt, its
  -- belt for an asteroid, 0 for the sun, planets and moons.
  site: number,
  variety: string,    -- planet type, station type, star class; "" if none
  to: number,         -- a gate's destination system; 0 otherwise
}

export type Description = {
  id: number,
  name: string,
  objects: { Object },
}

local AU = Constants.AU

local INNER = { "barren", "lava", "temperate", "ocean" }
local MIDDLE = { "temperate", "ocean", "barren", "gas" }
local OUTER = { "gas", "ice", "gas", "barren" }
local STATIONS = { "trade hub", "shipyard", "refinery", "habitat", "outpost" }
local STARS = { "yellow", "orange", "red", "white", "blue" }

function System.Describe(galaxy: Galaxy.Galaxy, id: number): Description
  local node = galaxy.systems[id]
  local rng = Rng.For(galaxy.seed, id, 2001)
  local objects: { Object } = {}

  local function add(kind: Kind, name: string, x: number, y: number, z: number, radius: number,
    parent: number, variety: string): Object
    local object: Object = {
      id = id * Constants.STRUCTURE_ID_SPAN + #objects + 1,
      kind = kind, name = name, x = x, y = y, z = z, radius = radius,
      seed = Rng.Int(rng, 2 ^ 31), parent = parent, site = 0, variety = variety, to = 0,
    }
    table.insert(objects, object)
    return object
  end

  -- A point at 'distance' from (x, z), in a random direction near the plane.
  local function around(x: number, y: number, z: number, distance: number): (number, number, number)
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local lift = Rng.Float(rng, -0.08, 0.08)
    return x + distance * math.cos(angle), y + distance * lift, z + distance * math.sin(angle)
  end

  local sun = add("sun", node.name, 0, 0, 0, Rng.Float(rng, 4e8, 1.2e9), 0, STARS[Rng.Int(rng, #STARS) + 1])

  local planets: { Object } = {}
  local hosts: { Object } = {} -- bodies a station can sit near
  local orbit = Rng.Float(rng, 0.3, 0.6) * AU
  local planetCount = 4 + Rng.Int(rng, 5)
  for p = 1, planetCount do
    local au = orbit / AU
    local variety = (if au < 2 then INNER elseif au < 6 then MIDDLE else OUTER)[Rng.Int(rng, 4) + 1]
    local gas = variety == "gas"
    local radius = if gas then Rng.Float(rng, 2.5e7, 7e7) else Rng.Float(rng, 2e6, 7e6)
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local tilt = Rng.Float(rng, -0.05, 0.05)
    local planet = add("planet", `{node.name} {Names.Roman(p)}`,
      orbit * math.cos(angle), orbit * tilt, orbit * math.sin(angle), radius, sun.id, variety)
    table.insert(planets, planet)
    table.insert(hosts, planet)

    local moonCount = if gas then 1 + Rng.Int(rng, 4) else Rng.Int(rng, 3)
    local moonOrbit = radius * Rng.Float(rng, 12, 20)
    for m = 1, moonCount do
      local x, y, z = around(planet.x, planet.y, planet.z, moonOrbit)
      local moon = add("moon", `{planet.name} - Moon {m}`, x, y, z, Rng.Float(rng, 2e5, 1.8e6), planet.id,
        if Rng.Chance(rng, 0.3) then "ice" else "barren")
      table.insert(hosts, moon)
      moonOrbit *= Rng.Float(rng, 1.5, 2.2)
    end

    local beltCount = if Rng.Chance(rng, 0.6) then 1 + Rng.Int(rng, 2) else 0
    for b = 1, beltCount do
      local x, y, z = around(planet.x, planet.y, planet.z, radius * Rng.Float(rng, 4, 9))
      local belt = add("belt", `{planet.name} - Asteroid Belt {b}`, x, y, z, 0, planet.id, "")
      belt.site = belt.id
      -- Rocks along an arc 10 to 20 km out from the belt's centre, which
      -- is where a ship warping to the belt arrives.
      local start = Rng.Float(rng, 0, 2 * math.pi)
      local rocks = 24 + Rng.Int(rng, 17)
      for r = 1, rocks do
        local along = start + (r / rocks) * math.pi * Rng.Float(rng, 0.9, 1.1)
        local out = Rng.Float(rng, 10000, 20000)
        local rock = add("asteroid", `Asteroid {r}`,
          x + out * math.cos(along), y + Rng.Float(rng, -4000, 4000), z + out * math.sin(along),
          Rng.Float(rng, 150, 900), belt.id, "rock")
        rock.site = belt.id
      end
    end

    orbit *= Rng.Float(rng, 1.5, 2.1)
  end

  local stationCount = 1 + Rng.Int(rng, 3)
  for s = 1, stationCount do
    local host = hosts[Rng.Int(rng, #hosts) + 1]
    local x, y, z = around(host.x, host.y, host.z, host.radius * Rng.Float(rng, 2.5, 4))
    local variety = STATIONS[Rng.Int(rng, #STATIONS) + 1]
    local station = add("station", `{host.name} - {string.upper(string.sub(variety, 1, 1))}{string.sub(variety, 2)} {s}`,
      x, y, z, Rng.Float(rng, 2000, 8000), host.id, variety)
    station.site = station.id
  end

  -- A gate for each neighbour, out past the last planet, on the side of
  -- the system that faces its destination on the galaxy map.
  local edge = 0
  for _, planet in planets do
    edge = math.max(edge, math.sqrt(planet.x ^ 2 + planet.z ^ 2))
  end
  for _, neighbor in node.neighbors do
    local other = galaxy.systems[neighbor]
    local angle = math.atan2(other.y - node.y, other.x - node.x) + Rng.Float(rng, -0.05, 0.05)
    local distance = edge * Rng.Float(rng, 1.1, 1.3)
    local gate = add("gate", `Stargate ({other.name})`,
      distance * math.cos(angle), distance * Rng.Float(rng, -0.02, 0.02), distance * math.sin(angle),
      1500, sun.id, "")
    gate.site = gate.id
    gate.to = neighbor
  end

  assert(#objects < Constants.STRUCTURE_ID_SPAN, "a system has outgrown its id range")
  return { id = id, name = node.name, objects = objects }
end

-- The gate in 'description' that leads to 'destination', if there is one.
function System.GateTo(description: Description, destination: number): Object?
  for _, object in description.objects do
    if object.kind == "gate" and object.to == destination then
      return object
    end
  end
  return nil
end

return System
