--!strict
-- Shows the Core's space with engine objects. The Core is the truth; this
-- module only mirrors it, and could be thrown away and rebuilt from the
-- state at any moment.
--
-- What is drawn:
--   - everything on the player's grid, as real objects at real size and
--     distance: ships, the station, gate or asteroids of the grid;
--   - the system's planets and moons, in scaled space: each is drawn in
--     its true direction at a distance the renderer can reach, shrunk by
--     the same factor, so it covers exactly the right part of the sky;
--   - the sun, as the direction light comes from;
--   - a station as what it is made of (Game/View/Starbase): its control
--     tower, the modules anchored round it, and its field;
--   - on a hull of our own design, what is fitted to its hardpoints
--     (Game/View/Arms): the turrets turn to what they are shooting at,
--     and their shots leave from their mouths.
--
-- The engine's positions lose precision far from zero, and its far plane
-- is at 1e6. So the scene's origin is the anchor of the player's grid
-- (or, in warp, the ship itself), and everything is placed relative to
-- that, worked out in doubles first.
--
-- Between ticks ships are drawn where the Core's own formulas put them
-- (Tactical/Motion): the state at a tick fixes the next second of flight.

local Arms = require("@lt/Game/View/Arms")
local Clock = require("@lt/Game/Clock")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Effects = require("@lt/Game/View/Effects")
local Hull = require("@lt/Game/View/Hull")
local Planet = require("@lt/Game/View/Planet")
local Star = require("@lt/Game/View/Star")
local Starbase = require("@lt/Game/View/Starbase")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Motion = require("@lt/Core/Tactical/Motion")
local Ores = require("@lt/Core/Data/Ores")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local SystemData = require("@lt/Core/Describe/System")

local Scene = {}

export type Placed = { object: Object, x: number, y: number, z: number, radius: number }

-- What stands on one mount of a ship.
type Arm = {
  piece: Arms.Piece?,       -- nil for the cover on an empty hardpoint
  base: Object?,
  gun: Object,
  mount: Hull.Mount,
  yaw: number,              -- where a turret has swung to: radians round from rest,
  lift: number,             -- and up from level
}

-- A hardpoint and what is fitted to it: the same weapon on each of its
-- two mounts, on opposite sides of the hull (Game/View/Hull).
type Point = {
  item: number,             -- the fitted module, or 0 if the hardpoint is empty
  arms: { Arm },
  off: number,              -- how far the gun that faces the target is from pointing at it, in radians (-1 with none)
}

-- And all of a ship's. 'key' is the fit they were made for.
type Armed = { key: string, points: { Point }, built: Hull.Built }

-- A wreck as drawn: the pieces of the hull it was (Hull.Wreck), each
-- turning slowly about its own middle as they drift apart.
type Wrecked = {
  pieces: { { object: Object, middle: vector, away: vector, axis: vector, spin: number } },
  right: vector,            -- the way the ship lay when it died
  up: vector,
  look: vector,
  scale: number,            -- metres to one of the hull's own units
  seen: number,             -- when (scene time) it was first drawn
}

export type Scene = {
  camera: Camera,
  system: number,                     -- the system shown; 0 before the first frame
  container: Object?,
  star: Object?,
  key: string,                        -- which grid the scene is built for
  ox: number,                         -- the scene origin, in system space
  oy: number,
  oz: number,
  eyeX: number,                       -- where the player is, in system space
  eyeY: number,
  eyeZ: number,
  proxies: { [number]: Object },      -- on-grid bodies by id
  celestials: { [number]: Object },   -- planets and moons by id
  worlds: { [number]: Planet.World }, -- those of them that turn (Planet.Turn), by id
  passing: number,                    -- ships drawn this frame that are in warp, coming or going
  screen: { [number]: vector },       -- where each drawn body is in the scene, this frame
  focus: Object?,
  yaw: number,
  pitch: number,
  zoom: number,                       -- camera distance, in focus radii
  zoomTarget: number,
  -- What the camera keeps in view past the ship (the id of something on
  -- the grid), or 0: it looks where it was last left.
  tracking: number,
  warp: number,                       -- 0 out of warp, rising to 1 in the middle of one
  warpLeft: number,                   -- metres still to go
  warpSeconds: number,                -- and seconds
  time: number,                       -- seconds the scene has been running, for effects
  fx: Effects.Fx?,                    -- weapon fire and the like, in this system's container
  mining: { [number]: number },       -- when each mining module's beam was last begun, by its item
  wreckage: { [number]: Wrecked },    -- the pieces of each wreck on the grid
  works: { [number]: { Object } },    -- what stands round each station's tower: its modules, their guns, its field
  -- Where each of those stands from the station's middle, in the order
  -- of 'works' and after the tower's own (the first): to move them by.
  offsets: { [number]: { vector } },
  -- The described bodies there are proxies of (rocks, stations, gates), by id.
  statics: { [number]: SystemData.Object },
  -- The clouds of gas among them: how big each puff of one is when the
  -- cloud is whole (the cloud's own first), and how much of the cloud
  -- was left when it was last sized.
  clouds: { [number]: { sizes: { number }, shown: number } },
  -- Whose bodies are in the scene: the grid the ship is on, or in warp
  -- the one it left and the one it is coming to (the ids, as one word).
  sites: string,
  left: number,                       -- the grid the ship was last on in this system; 0: none yet
  -- A jump through a gate, as it is shown. The Core has the ship in the
  -- next system at once; the scene holds the one it left for a moment
  -- while the view rushes and whites out ('jump': when that began, in
  -- scene time, or -1), makes the next one behind the white, and comes
  -- out of it there ('arrived': when, or -1).
  jump: number,
  arrived: number,
  lit: boolean,                       -- the gate the pilot came out of has had its light (once an arrival)
  gates: number,                      -- how many times a gate has been lit by somebody going through it
  veil: number,                       -- how much of the view is whited out, 0 to 1 (the interface draws it)
  rush: number,                       -- how far the view is opened out by a jump, 0 to 1
  standing: { [number]: string },     -- what a pilot's starbase was made of when it was put up here
  epoch: number,                      -- the game (Session's 'epoch') the scene was made for
  volleys: number,                    -- shots of a station's batteries shown so far
  docked: boolean,                    -- the pilot is docked: the camera is on the station
  zoomAway: number,                   -- the zoom there was before docking, to go back to
  arms: { [number]: Armed },          -- what is on the hardpoints of each ship of our own design
  armsTick: number,                   -- the tick the arms were last checked against the fits
  ghosts: { [number]: boolean },      -- the ships drawn cloaked now (Hull.Ghost in place of the hull)
  armsTime: number,                   -- when (scene time) the turrets were last swung
}

-- A shot to show: who at whom, how it went, and when (scene time). A
-- missile takes 'flight' seconds to arrive; anything else is instant.



-- A ship in warp is on no grid, and is drawn all the same while it is
-- within this of the pilot: so that one leaving is seen to go, drawing
-- its trail out behind it, and one arriving is seen to come in. (A
-- frigate is this far off two or three seconds into its warp, and is
-- that long again and more coming down from it at the other end. The
-- far plane cuts the ship itself off long before: what is seen out
-- there is its trail.)
local PASSING = 20000000
-- The seconds of its way a ship in warp trails behind it, at least, and
-- the colour of the trail of one whose hull has no engines to give it one.
local WAKE = 1.4
local WAKE_COLOR = vector.create(0.55, 0.78, 1.0)

-- In warp, what is on the grid the ship has left, and on the one it is
-- coming to, is drawn as it is while it is nearer than this: so that a
-- belt's rocks fall away behind and come up ahead, and are not there
-- one moment and gone the next. (Under FAR: past that a place is only
-- a mark in its direction.)
local NEAR = 550000

-- Bodies beyond the renderer's reach are drawn this far away, or a
-- little farther to stand behind a nearer one, but never past FARTHEST
-- (the renderer draws nothing beyond a million).
local FAR = 600000
local FARTHEST = 950000

-- The sun has its flare while its disc spans less than this (the sine of
-- the angle its radius spans: about a degree and a half).
local FLARE_UNDER = 0.026

-- The size of a living world's cube map in the game: smaller than the
-- viewer's, since a system may hold several (about 28 MB each).
local WORLD_MAP = 768
local MOON_MAP = 512

-- How a hull type looks, until hulls have their own generator specs: the
-- seed of the old generator. Its size comes from the hull's radius. The
-- generator sizes a hull by its "value" (radius grows as the square root;
-- 0.0675 m per root-credit, measured), and an instance must not be
-- rescaled afterwards: the engine stops drawing a ship whose scale has
-- been changed.
local HULL_SEED: { [string]: number } = {
  ["frigate.courier"] = 55,
  ["industrial.hauler"] = 77,
}
local hullItems: { [string]: Item } = {}

function Scene.New(camera: Camera): Scene
  return {
    camera = camera, system = 0, container = nil, star = nil, key = "",
    ox = 0, oy = 0, oz = 0, eyeX = 0, eyeY = 0, eyeZ = 0,
    proxies = {}, celestials = {}, worlds = {}, passing = 0, screen = {}, focus = nil,
    yaw = 0.6, pitch = 1.25, zoom = 6, zoomTarget = 6, tracking = 0,
    warp = 0, warpLeft = 0, warpSeconds = 0, time = 0, fx = nil, mining = {},
    wreckage = {}, works = {}, offsets = {}, statics = {}, clouds = {}, sites = "", left = 0, jump = -1, arrived = -1, lit = true, gates = 0, veil = 0, rush = 0,
    standing = {}, epoch = 1, volleys = 0, docked = false, zoomAway = 6, arms = {}, armsTick = -1, armsTime = 0, ghosts = {},
  }
end

-- Put an object so that the middle of its bounds is at 'at'. A generated
-- model's own origin can be well off-centre (a station's is at one end),
-- and the Core's position for a body is the centre of its sphere.
local function place(object: Object, at: vector)
  object:SetPos(at)
  object:SetPos(at + (at - object:GetCenter()))
end

-- The proxies that are hulls of our own design (Game/View/Hull), which
-- are scenery and are turned by Object_SetAxes; the rest are the
-- engine's ships.
local designed: { [Object]: Hull.Built } = setmetatable({} :: any, { __mode = "k" })

-- ('pirate': it is a pirate's, and looks it.)
local function makeShip(type: string, radius: number, pirate: boolean, rank: number?): Object
  local built = Hull.Build(type, pirate, rank)
  if built then
    local object = Object_Scenery({})
    Object_SetRenderable(object, built.model)
    local size = radius / built.radius
    object:SetScale(vector.create(size, size, size))
    designed[object] = built
    return object
  end
  local item: Item? = hullItems[type]
  if not item then
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or HULL_SEED[(string.gsub(type, "%.ii$", ""))] or 55, 1, 1, 1, 1, 1, 1)
    hullItems[type] = made
    return made:Instantiate()
  end
  return item:Instantiate()
end

-- The model of a hull type of this radius, for the interface to draw.
function Scene.Preview(type: string, radius: number): Renderable | Model
  local built = Hull.Build(type)
  if built then
    return built.model
  end
  local item: Item? = hullItems[type]
  if not item then
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or HULL_SEED[(string.gsub(type, "%.ii$", ""))] or 55, 1, 1, 1, 1, 1, 1)
    hullItems[type] = made
    item = made
  end
  return (item :: Item):GetRenderable()
end

-- Which weapon goes on which hardpoint: a ship's fitted weapons in the
-- order of their slots, each on the next hardpoint of its kind, and
-- nothing (nil) on every hardpoint left over. 'each' is told of every
-- hardpoint the hull has.
local function assign(fitted: { State.Item }, built: Hull.Built, each: (hardpoint: Hull.Hardpoint, item: State.Item?) -> ())
  local turrets, launchers = 0, 0
  for _, item in fitted do
    local module = Modules.byId[item.type]
    if module and item.place == "high" and module.hardpoint == "turret" then
      turrets += 1
      if built.turrets[turrets] then
        each(built.turrets[turrets], item)
      end
    elseif module and item.place == "high" and module.hardpoint == "launcher" then
      launchers += 1
      if built.launchers[launchers] then
        each(built.launchers[launchers], item)
      end
    end
  end
  for at = turrets + 1, #built.turrets do
    each(built.turrets[at], nil)
  end
  for at = launchers + 1, #built.launchers do
    each(built.launchers[at], nil)
  end
end

-- One thing to draw of a ship shown in the interface: a model, and how
-- it stands on the hull, in the hull's own units.
export type Part = { model: Renderable | Model, transform: Transform }

local dressed: { key: string, parts: { Part } }? = nil

-- A ship as it is fitted, for the interface to draw: its hull, and on a
-- hull of our own design what stands on its hardpoints, at rest, with a
-- cover on each one left empty. 'radius' is the hull's, in metres. (The
-- last one asked for is kept, and made again only when the fit changes.)
function Scene.Dressed(game: Core.Game, ship: number, type: string, radius: number): { Part }
  local built = Hull.Build(type)
  if built == nil then
    return { { model = Scene.Preview(type, radius), transform = Transform_Identity() } }
  end
  local fitted = Core.Query.Fitted(game, ship)
  local key = `{ship}:{type}`
  for _, item in fitted do
    if item.place == "high" then
      key ..= ` {item.id}:{item.type}`
    end
  end
  if dressed and dressed.key == key then
    return dressed.parts
  end
  local parts: { Part } = { { model = built.model, transform = Transform_Identity() } }
  local unit = built.radius / radius      -- one metre, in the hull's own units
  local function stand(model: Model, at: vector, look: vector, up: vector, size: number)
    local transform = Transform_LookUp(at, look, up)
    transform.scale = vector.create(size, size, size)
    table.insert(parts, { model = model, transform = transform })
  end
  assign(fitted, built, function(hardpoint: Hull.Hardpoint, item: State.Item?)
    local piece = if item then Arms.Build(item.type) else nil
    for _, mount in hardpoint do
      local fore = mount.fore or vector.create(0, 0, 1)
      local level = fore - mount.up * vector.dot(fore, mount.up)
      level = if vector.magnitude(level) > 1e-4 then vector.normalize(level) else vector.normalize(vector.cross(mount.up, vector.create(1, 0, 0)))
      if piece then
        local size = piece.scale * unit
        if piece.base then
          stand(piece.base, mount.at, level, mount.up, size)
        end
        local right = vector.cross(mount.up, level)
        stand(piece.gun, mount.at + (right * piece.pivot.x + mount.up * piece.pivot.y + level * piece.pivot.z) * size, level, mount.up, size)
      else
        stand(Arms.Blank(), mount.at, level, mount.up, (Arms.SIZE[Arms.SizeOf(built.fit[1] or "")] or 1) * unit)
      end
    end
  end)
  dressed = { key = key, parts = parts }
  return parts
end

-- Take what is on a ship's hardpoints away.
local function dropArms(scene: Scene, id: number)
  local armed = scene.arms[id]
  if armed then
    for _, point in armed.points do
      for _, arm in point.arms do
        if arm.base then
          Object_Delete(arm.base)
        end
        Object_Delete(arm.gun)
      end
    end
    scene.arms[id] = nil
  end
end

-- Take a wreck's pieces away.
local function dropWreck(scene: Scene, id: number)
  local wrecked = scene.wreckage[id]
  if wrecked then
    for _, piece in wrecked.pieces do
      Object_Delete(piece.object)
    end
    scene.wreckage[id] = nil
  end
end

-- Take away what stands round a station's tower.
local function dropWorks(scene: Scene, id: number)
  local works = scene.works[id]
  if works then
    for _, object in works do
      Object_Delete(object)
    end
    scene.works[id] = nil
  end
  scene.offsets[id] = nil
  scene.standing[id] = nil
end

-- A number from 0 to 1 that follows from 'n'.
local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- 'v' turned by 'angle' about the axis 'k' (of length 1).
local function about(v: vector, k: vector, angle: number): vector
  local c, s = math.cos(angle), math.sin(angle)
  return v * c + vector.cross(k, v) * s + k * (vector.dot(k, v) * (1 - c))
end

-- Make the pieces of a wreck, lying as the ship lay ('look' and 'up').
local function makeWreck(scene: Scene, id: number, wreck: State.Wreck, look: vector, up: vector, container: Object)
  local wreckage = Hull.Wreck(wreck.hull)
  local scale = wreck.radius / wreckage.radius
  local wrecked: Wrecked = { pieces = {}, right = vector.cross(up, look), up = up, look = look, scale = scale, seen = scene.time }
  for index, piece in wreckage.pieces do
    local object = Object_Scenery({})
    Object_SetRenderable(object, piece.model)
    object:SetScale(vector.create(scale, scale, scale))
    container:AddInterior(object)
    local n = id * 7 + index * 31
    -- (each goes off the way it was already out from the middle, more
    -- or less, and turns about an axis of its own)
    local out = piece.middle + vector.create(dice(n) - 0.5, dice(n + 1) - 0.5, dice(n + 2) - 0.5) * 0.6
    local axis = vector.create(dice(n + 3) - 0.5, dice(n + 4) - 0.5, dice(n + 5) - 0.5)
    table.insert(wrecked.pieces, {
      object = object, middle = piece.middle,
      away = if vector.magnitude(out) > 1e-3 then vector.normalize(out) else vector.create(0, 1, 0),
      axis = if vector.magnitude(axis) > 1e-3 then vector.normalize(axis) else vector.create(0, 1, 0),
      spin = (0.02 + 0.05 * dice(n + 6)) * (if dice(n + 7) < 0.5 then -1 else 1),
    })
  end
  scene.wreckage[id] = wrecked
end

-- Put a wreck's pieces where they have got to: 'at' is the wreck, and
-- 'radius' the radius of the ship it was.
local function placeWreck(scene: Scene, wrecked: Wrecked, at: vector, radius: number)
  local since = scene.time - wrecked.seen
  -- (they part quickly at first and all but stop within a minute)
  local spread = radius * (0.05 + 0.30 * (1 - math.exp(-since / 20)))
  for _, piece in wrecked.pieces do
    local m = piece.middle
    local middle = at + (wrecked.right * m.x + wrecked.up * m.y + wrecked.look * m.z) * wrecked.scale
      + (wrecked.right * piece.away.x + wrecked.up * piece.away.y + wrecked.look * piece.away.z) * spread
    local angle = piece.spin * since
    local look = about(wrecked.look, piece.axis, angle)
    local up = about(wrecked.up, piece.axis, angle)
    local right = vector.cross(up, look)
    -- (the object is placed by its own origin: its middle is that far from it, turned as it now is)
    piece.object:SetPos(middle - (right * m.x + up * m.y + look * m.z) * wrecked.scale)
    Object_SetAxes(piece.object, look, up)
  end
end

-- Put on a ship's hardpoints what is fitted to it (on both mounts of
-- each hardpoint), and covers on every hardpoint left empty. Nothing is
-- done if they are there already.
local function armShip(scene: Scene, game: Core.Game, id: number, built: Hull.Built, container: Object)
  local fitted = Core.Query.Fitted(game, id)
  local key = ""
  for _, item in fitted do
    if item.place == "high" then
      key ..= `{item.id}:{item.type} `
    end
  end
  local armed = scene.arms[id]
  if armed and armed.key == key then
    return
  end
  dropArms(scene, id)
  local points: { Point } = {}
  local function fill(hardpoint: Hull.Hardpoint, item: State.Item?)
    local piece = if item then Arms.Build(item.type) else nil
    local arms: { Arm } = {}
    for _, mount in hardpoint do
      local base: Object? = nil
      if piece and piece.base then
        local made = Object_Scenery({})
        Object_SetRenderable(made, piece.base)
        container:AddInterior(made)
        base = made
      end
      local gun = Object_Scenery({})
      Object_SetRenderable(gun, if piece then piece.gun else Arms.Blank())
      container:AddInterior(gun)
      table.insert(arms, { piece = piece, base = base, gun = gun, mount = mount, yaw = 0, lift = 0 })
    end
    table.insert(points, { item = if piece and item then item.id else 0, arms = arms, off = -1 })
  end
  assign(fitted, built, fill)
  scene.arms[id] = { key = key, points = points, built = built }
end

local FORE = vector.create(0, 0, 1)

-- Stand a ship's arms on its hull where the hull now is, and swing its
-- turrets (for 'seconds', at their own rates). Of the two on a
-- hardpoint, each turns to the target if it can see it, and one that
-- has the hull in the way goes back to rest; the one that faces the
-- target the more squarely is the one that fires, and where its shots
-- leave from is noted: scene.screen holds that under the module's item
-- id, negated.
local function placeArms(scene: Scene, armed: Armed, proxy: Object, at: vector, radius: number, running: { State.Running }, seconds: number)
  local right, up, look = proxy:GetRight(), proxy:GetUp(), proxy:GetLook()
  local unit = radius / armed.built.radius
  -- (an empty hardpoint's cover is the size of the weapons the hull is drawn for)
  local cover = Arms.SIZE[Arms.SizeOf(armed.built.fit[1] or "")] or 1
  for _, point in armed.points do
    local target: vector? = nil
    if point.item ~= 0 then
      for _, run in running do
        if run.item == point.item and run.target ~= 0 then
          target = scene.screen[run.target]
        end
      end
    end
    local best = -2
    point.off = -1
    for index, arm in point.arms do
      local mount = arm.mount
      local fore = mount.fore or FORE
      local origin = at + (right * mount.at.x + up * mount.at.y + look * mount.at.z) * unit
      local mountUp = right * mount.up.x + up * mount.up.y + look * mount.up.z
      local mountFore = right * fore.x + up * fore.y + look * fore.z
      local piece = arm.piece
      if piece then
        local aim: vector? = nil
        local facing = 0
        if target and vector.magnitude(target - origin) > 1 then
          local toward = vector.normalize(target - origin)
          facing = vector.dot(toward, mountUp)
          if Arms.Sees(facing) then
            aim = toward
          end
        end
        local direction: vector
        arm.yaw, arm.lift, direction = Arms.Swing(piece, mountUp, mountFore, aim, arm.yaw, arm.lift, seconds)
        local muzzle = Arms.Place(piece, arm.base, arm.gun, origin, mountUp, mountFore, direction, 1)
        if (target ~= nil and facing > best) or (target == nil and index == 1) then
          best = facing
          scene.screen[-point.item] = muzzle
          point.off = if aim and piece.turns then math.acos(math.clamp(vector.dot(direction, aim), -1, 1)) else -1
        end
      else
        local level = mountFore - mountUp * vector.dot(mountFore, mountUp)
        arm.gun:SetPos(origin)
        Object_SetAxes(arm.gun, if vector.magnitude(level) > 1e-4 then level else right, mountUp)
        arm.gun:SetScale(vector.create(cover, cover, cover))
      end
    end
  end
end

-- For checking (GameDebug.Arms): how many weapon models stand on a
-- ship's mounts (two to a fitted weapon), and how far from its target
-- the worst-pointed of its firing turrets still is, in radians (-1 if
-- none has a target).
function Scene.Arms(scene: Scene, ship: number): (number, number)
  local armed = scene.arms[ship]
  local count, off = 0, -1
  if armed then
    for _, point in armed.points do
      for _, arm in point.arms do
        if arm.piece then
          count += 1
        end
      end
      off = math.max(off, point.off)
    end
  end
  return count, off
end

local function makeStatic(object: SystemData.Object): Object
  local made: Object
  if object.kind == "asteroid" then
    -- (An asteroid cannot be named: the engine object has no such part.)
    made = Object_Asteroid(object.seed)
    made:SetScale(vector.create(object.radius, object.radius, object.radius))
  else
    -- A gate: a ring, facing out of the system, the way its jump goes.
    -- (A station is a tower and what is anchored round it: makeStation.)
    local gate = Starbase.Gate()
    made = Object_Scenery({})
    Object_SetRenderable(made, gate.model)
    local size = object.radius / gate.radius
    made:SetScale(vector.create(size, size, size))
    local out = vector.create(object.x, 0, object.z)
    if vector.magnitude(out) > 1 then
      Object_SetAxes(made, vector.normalize(out), vector.create(0, 1, 0))
    end
    made:SetName(object.name)
  end
  return made
end

-- What a puff of each gas is drawn with: a unit sphere, to be scaled.
local puffs: { [string]: Model } = {}
local TINTS: { [string]: vector } = {
  ["gas.amber"] = vector.create(1.0, 0.62, 0.22), ["gas.verdant"] = vector.create(0.40, 0.95, 0.50),
  ["gas.azure"] = vector.create(0.35, 0.62, 1.0),
}
local function puff(gas: string): Model
  local kept: Model? = puffs[gas]
  if kept then
    return kept
  end
  local made: Model
  do
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "cloud.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "cloudTint", TINTS[gas] or vector.create(0.7, 0.7, 0.7))
    ShaderInstance_SetFloat(shader, "cloudGlow", 0.26)
    ShaderInstance_Link(shader)
    made = Model_Create()
    Model_AddShell(made, Mesh_SetU(Mesh_BoxSphere(24, true), 1), shader)
    puffs[gas] = made
  end
  return made
end

-- A cloud of gas (Core/Data/Ores): a big puff the size of the cloud,
-- which is the cloud's own object, and lesser ones laid over it and
-- hanging off it, each a little different, the same every time for the
-- same cloud. (A grey box of a cloud: nothing drifts in it.)
local PUFFS = 6
local function makeCloud(scene: Scene, object: SystemData.Object, at: vector, container: Object): Object
  local model = puff(object.variety)
  local roll = object.seed % 2147483647
  local function next(): number
    roll = (roll * 48271 + 11) % 2147483647
    return roll / 2147483647
  end
  local function one(size: number, offset: vector): Object
    local made = Object_Scenery({})
    Object_SetRenderable(made, model)
    container:AddInterior(made)
    made:SetScale(vector.create(size, size, size))
    made:SetPos(at + offset)
    return made
  end
  local middle = one(object.radius, vector.zero)
  local lobes: { Object } = {}
  local sizes: { number } = { object.radius }
  local offsets: { vector } = { vector.zero }
  for _ = 1, PUFFS do
    local angle, lift = next() * 2 * math.pi, (next() - 0.5) * 0.9
    local out = (0.35 + 0.45 * next()) * object.radius
    local size = (0.45 + 0.35 * next()) * object.radius
    local offset = vector.create(math.cos(angle) * out, lift * out, math.sin(angle) * out)
    table.insert(lobes, one(size, offset))
    table.insert(sizes, size)
    table.insert(offsets, offset)
  end
  scene.works[object.id] = lobes
  scene.offsets[object.id] = offsets
  scene.clouds[object.id] = { sizes = sizes, shown = 1 }
  return middle
end

-- A station: its tower, which is the station's own object, with its
-- modules and its field round it, at 'at'. The station's radius is the
-- radius of its field.
--
-- A pilot's own starbase is not always what it was: its modules come
-- and go, and its field with its fuel. What stands there is written
-- down ('standing'), so that it is put up again when that changes.
local function standing(game: Core.Game, id: number): string?
  local status = Core.Query.Starbase(game, id)
  if status == nil then
    return nil
  end
  local parts = { status.tower.id, if status.lit then "lit" else "dark" }
  for _, module in status.modules do
    table.insert(parts, module.type)
  end
  return table.concat(parts, " ")
end

local function makeStation(scene: Scene, game: Core.Game, object: SystemData.Object, at: vector, container: Object): Object
  local makeup = Core.Query.Station(game, object.id)
  local status = Core.Query.Starbase(game, object.id)
  local dark = status ~= nil and not status.lit
  local raised = Starbase.Raise(Starbase.Layout(object.variety, object.radius, object.seed, nil, makeup, dark), container, at, 1)
  local tower = table.remove(raised, 1) :: Object
  tower:SetName(object.name)
  scene.works[object.id] = raised
  local offsets: { vector } = { tower:GetPos() - at }
  for _, work in raised do
    table.insert(offsets, work:GetPos() - at)
  end
  scene.offsets[object.id] = offsets
  scene.statics[object.id] = object
  local made = standing(game, object.id)
  if made then
    scene.standing[object.id] = made
  end
  return tower
end

local function clear(scene: Scene, objects: { [number]: Object })
  for _, object in objects do
    Object_Delete(object)
  end
  table.clear(objects)
end

-- Throw away everything and start a container for 'system'.
local function enterSystem(scene: Scene, game: Core.Game, system: number)
  for id in scene.arms do
    dropArms(scene, id)
  end
  for id in scene.wreckage do
    dropWreck(scene, id)
  end
  for id in scene.works do
    dropWorks(scene, id)
  end
  clear(scene, scene.proxies)
  clear(scene, scene.celestials)
  table.clear(scene.worlds)
  if scene.container then
    Object_Delete(scene.container)
  end
  if scene.fx then
    Effects.Clear(scene.fx, true)
  end
  table.clear(scene.mining)
  table.clear(scene.statics)
  table.clear(scene.offsets)
  table.clear(scene.clouds)
  scene.focus = nil
  scene.star = nil
  scene.key = ""
  scene.sites = ""
  scene.left = 0
  scene.system = system

  local container = Object_System(vector.create(0, 0, 0), game.state.galaxySeed * 7919 + system)
  -- (the camera goes into the new system now, while the old one is still
  -- there to be left: the engine moves it only when it next draws, and
  -- by then the old one may have been thrown away under it)
  container:AddInterior(scene.camera)
  scene.container = container
  scene.fx = Effects.New(container)
  local interior = container:GetInteriorObjects()
  while interior:HasMore() do
    if interior:Get():IsStar() then
      scene.star = interior:Get()
    end
    interior:Advance()
  end

  for _, object in Core.Query.Objects(game, system) do
    if object.kind == "planet" or object.kind == "moon" then
      local body: Object
      -- The kinds built from their own heights (Game/View/Planet); the
      -- rest are still the engine's old planet.
      local kind = Planet.KindOf(object.kind, object.variety)
      if kind then
        local world = Planet.New(kind, object.seed, if object.kind == "moon" then MOON_MAP else WORLD_MAP)
        scene.worlds[object.id] = world
        body = world.body
      else
        body = Item_PlanetType(object.seed):Instantiate()
      end
      body:SetName(object.name)
      container:AddInterior(body)
      scene.celestials[object.id] = body
    elseif object.kind == "sun" then
      -- The sun's disc and corona. Its light, and the flare drawn for
      -- that, are the engine's star, which takes the colour of the
      -- star's class.
      local body = Star.New(object.variety, object.seed)
      body:SetName(object.name)
      container:AddInterior(body)
      scene.celestials[object.id] = body
      if scene.star then
        Star_SetColor(scene.star, Star.Light(object.variety))
      end
    end
  end
end

-- What to draw for a shot whose weapon is not known, by its family.
local FALLBACK: { [string]: string } = { laser = "laser.pulse", projectile = "autocannon", hybrid = "blaster", missile = "launcher" }

-- Which of a ship's layers a shot lands on.
local function struck(ball: State.Ball): string
  local vitals = ball.vitals
  return if vitals.shield > 1 then "shield" elseif vitals.armor > 1 then "armor" else "hull"
end

-- Where a ball is 'since' seconds after the state's tick, and its velocity.
local function ballAt(ball: State.Ball, tick: number, since: number): (number, number, number, number, number, number)
  local warp = ball.warp
  if warp and warp.stage == "warp" then
    local plan = warp.plan :: Motion.WarpPlan
    local d, speed = Motion.WarpAt(plan, (tick - warp.startTick) * Constants.TICK + since)
    return warp.fx + warp.ux * d, warp.fy + warp.uy * d, warp.fz + warp.uz * d,
      warp.ux * speed, warp.uy * speed, warp.uz * speed
  end
  return Motion.Step(ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz,
    ball.tvx, ball.tvy, ball.tvz, ball.tau, since)
end

-- Docked, the camera stands this many of the tower's radii off, and
-- looks this far to one side of it (as a share of that distance): the
-- station's screens fill the middle of the window, and the tower is to
-- stand in the clear beside them.
local DOCKED_ZOOM = 2.3
local DOCKED_ASIDE = 0.62

-- A jump takes this long to leave by, and this long to come out of
-- (seconds, of the clock on the wall: time run faster does not hurry it).
-- (The leaving is as long as a gate's sound takes to come to its clap:
-- resource/sound/made/gate/jump.)
local JUMP_OUT = 1.12
local JUMP_IN = 1.5
local JUMP_LIGHT = vector.create(0.72, 0.90, 1.0)

-- A gate lights when a ship goes through it, either way: a flash at it
-- as big as the gate, and a ring thrown out from it.
local function lightGate(scene: Scene, fx: Effects.Fx, id: number, life: number)
  local at: vector? = scene.screen[id]
  local gate = scene.statics[id]
  if at and gate and gate.kind == "gate" then
    Effects.Burst(fx, at, JUMP_LIGHT, 2.2 * gate.radius, 0, life, scene.time)
    Effects.Burst(fx, at, JUMP_LIGHT, 7 * gate.radius, 1, life * 1.4, scene.time)
    scene.gates += 1
  end
end

-- The gate of the scene nearest a place in it, within 'reach' (0: none).
local function gateNear(scene: Scene, at: vector, reach: number): number
  local found, least = 0, reach
  for id, object in scene.statics do
    local where: vector? = scene.screen[id]
    if object.kind == "gate" and where then
      local far = vector.magnitude(where - at)
      if far < least or (far == least and id < found) then
        found, least = id, far
      end
    end
  end
  return found
end

-- Bring the engine's objects into line with the Core for this frame.
function Scene.Sync(scene: Scene, session: Session.Session)
  local game = session.game
  local state = game.state
  local since = Clock.SinceTick(session.clock)
  local player = Core.Query.Player(game)
  -- (another game, from a save or begun anew: nothing made for the last
  -- one stands, though it be the same system by number)
  if session.epoch ~= scene.epoch then
    scene.epoch = session.epoch
    scene.system = 0
    scene.key = ""
    scene.docked = false
    scene.jump, scene.arrived, scene.veil, scene.rush = -1, -1, 0, 0
  end
  if player.system ~= scene.system then
    -- Flown through a gate (and not put somewhere else by a save, a new
    -- game or a new clone): the system left stands a moment longer,
    -- with a flash where the ship was and the view rushing into it.
    local through = scene.system ~= 0 and state.balls[player.ship] ~= nil and scene.fx ~= nil
    if through and scene.jump < 0 then
      scene.jump = scene.time
      local at: vector? = scene.screen[player.ship]
      local radius = state.balls[player.ship].radius
      if at and scene.fx then
        Effects.Burst(scene.fx, at, JUMP_LIGHT, 60 * radius, 0, JUMP_OUT * 1.2, scene.time)
        Effects.Burst(scene.fx, at, JUMP_LIGHT, 220 * radius, 1, JUMP_OUT * 1.2, scene.time)
        -- (and the gate it went through lights)
        lightGate(scene, scene.fx, gateNear(scene, at, 50000), JUMP_OUT)
      end
    end
    if through and scene.time - scene.jump < JUMP_OUT then
      local t = (scene.time - scene.jump) / JUMP_OUT
      scene.veil, scene.rush = t * t, t * t
      if scene.fx then
        Effects.Update(scene.fx, scene.time, scene.screen)
      end
      return
    end
    -- (the next system is made behind the white)
    scene.arrived = if through then scene.time else -1
    scene.lit = not through
    scene.jump = -1
    enterSystem(scene, game, player.system)
  end
  if scene.arrived >= 0 then
    -- Out of it on the far side: the white clears and the view closes in.
    local t = (scene.time - scene.arrived) / JUMP_IN
    if t >= 1 then
      scene.arrived, scene.veil, scene.rush = -1, 0, 0
    else
      scene.veil, scene.rush = (1 - t) ^ 2, (1 - t) ^ 3
    end
  elseif scene.jump < 0 then
    scene.veil, scene.rush = 0, 0
  end
  local container = scene.container :: Object
  local objects = Core.Query.Objects(game, player.system)
  local me = state.balls[player.ship]

  -- Where the player is, and which grid to show.
  local grid = 0
  -- (docked in a colony ship: what it lies by, for the camera to be on
  -- until the ship itself is there to be on)
  local beside = 0
  scene.warp = 0
  if me then
    scene.eyeX, scene.eyeY, scene.eyeZ = ballAt(me, state.tick, since)
    grid = me.grid
    local warp = me.warp
    if warp and warp.stage == "warp" then
      -- How deep into the warp, for the camera: eased in over the first
      -- second and a half and out over the last two.
      local plan = warp.plan :: Motion.WarpPlan
      local elapsed = (state.tick - warp.startTick) * Constants.TICK + since
      local travelled = Motion.WarpAt(plan, elapsed)
      scene.warp = math.clamp(math.min(elapsed / 1.5, (plan.total - elapsed) / 2), 0, 1)
      scene.warpLeft = plan.distance - travelled
      scene.warpSeconds = math.max(0, plan.total - elapsed)
    end
  else
    -- (a colony ship of the nomads is a station of no system's list: it
    -- is where its ship is, on whatever grid that is)
    local roaming = Core.Query.Carrier(game, player.docked)
    local station = if roaming then Core.Query.Body(game, player.docked) :: any else objects[player.docked % Constants.STRUCTURE_ID_SPAN]
    scene.eyeX, scene.eyeY, scene.eyeZ = station.x, station.y, station.z
    grid = if roaming then station.site else station.id
    beside = if roaming then station.parent else 0
    if not scene.docked then
      -- Just docked (or the game has begun docked): bring the camera in
      -- on the tower, from the side the sun is on and a little round
      -- from it, so that it is seen lit and in the round.
      scene.docked = true
      scene.zoomAway = scene.zoomTarget
      scene.zoom, scene.zoomTarget = DOCKED_ZOOM, DOCKED_ZOOM
      scene.pitch = 1.32
      for _, object in objects do
        if object.kind == "sun" then
          scene.yaw = math.atan2(object.z - station.z, object.x - station.x) + 0.7
        end
      end
    end
  end
  if me and scene.docked then
    scene.docked = false
    scene.zoom, scene.zoomTarget = scene.zoomAway, scene.zoomAway
  end

  -- The origin: the grid's anchor, or the ship itself in warp.
  local key = tostring(grid)
  if grid == 0 then
    scene.ox, scene.oy, scene.oz = scene.eyeX, scene.eyeY, scene.eyeZ
  elseif key ~= scene.key then
    local open = state.grids[grid]
    if open then
      scene.ox, scene.oy, scene.oz = open.x, open.y, open.z
    else
      local anchor = objects[grid % Constants.STRUCTURE_ID_SPAN]
      scene.ox, scene.oy, scene.oz = anchor.x, anchor.y, anchor.z
    end
  end

  -- Whose bodies are in the scene: the grid the ship is on. In warp, the
  -- grid it has left and the one it is coming to (the one its landing
  -- place belongs to, as the Core will find: Space.AssignGrid), each
  -- for as long as it is near enough to be drawn.
  local inScene: { [number]: boolean } = {}
  local sites = ""
  if grid ~= 0 then
    inScene[grid] = true
    sites = `{grid} `
    scene.left = grid
  elseif me and me.warp and me.warp.stage == "warp" then
    local warp = me.warp
    local coming, nearest = 0, Constants.GRID_RADIUS
    for _, object in objects do
      if object.site == object.id then
        local d = math.sqrt((object.x - warp.tx) ^ 2 + (object.y - warp.ty) ^ 2 + (object.z - warp.tz) ^ 2)
        if d < nearest then
          coming, nearest = object.id, d
        end
      end
    end
    if coming == 0 then
      for _, id in state.gridIds do
        local open = state.grids[id]
        if open.system == player.system then
          local d = math.sqrt((open.x - warp.tx) ^ 2 + (open.y - warp.ty) ^ 2 + (open.z - warp.tz) ^ 2)
          if d < nearest then
            coming, nearest = id, d
          end
        end
      end
    end
    for _, id in { scene.left, coming } do
      if id ~= 0 and not inScene[id] then
        local open = state.grids[id]
        local anchor: { x: number, y: number, z: number }? = open
        if anchor == nil and id < Constants.FIRST_DYNAMIC_ID then
          anchor = objects[id % Constants.STRUCTURE_ID_SPAN]
        end
        if anchor and (anchor.x - scene.eyeX) ^ 2 + (anchor.y - scene.eyeY) ^ 2 + (anchor.z - scene.eyeZ) ^ 2 < NEAR ^ 2 then
          inScene[id] = true
          sites ..= `{id} `
        end
      end
    end
  end

  -- Another grid, or another origin: every trail has had the origin
  -- moved under it.
  local moved = key ~= scene.key
  if moved then
    scene.key = key
    if scene.fx then
      Effects.Still(scene.fx)
    end
  end
  -- Other bodies than were there: take away what is no longer wanted,
  -- and make what is. Ships are kept, since a hull is costly to make
  -- and the player's comes along.
  if sites ~= scene.sites then
    scene.sites = sites
    local gone: { number } = {}
    for id in scene.proxies do
      if state.balls[id] == nil then
        local static = scene.statics[id]
        local wreck = state.wrecks[id]
        local site = if static then static.site elseif wreck then wreck.grid else 0
        if not inScene[site] then
          table.insert(gone, id)
        end
      end
    end
    for _, id in gone do
      dropArms(scene, id)
      dropWreck(scene, id)
      dropWorks(scene, id)
      Object_Delete(scene.proxies[id])
      scene.proxies[id] = nil
      scene.statics[id] = nil
    end
    for _, object in objects do
      if inScene[object.site] and not scene.proxies[object.id] then
        if object.kind == "station" then
          scene.proxies[object.id] = makeStation(scene, game, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
        elseif object.kind == "asteroid" and Ores.gasById[object.variety] then
          scene.proxies[object.id] = makeCloud(scene, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
          scene.statics[object.id] = object
        elseif object.kind ~= "belt" then
          local made = makeStatic(object)
          container:AddInterior(made)
          place(made, vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz))
          scene.proxies[object.id] = made
          scene.statics[object.id] = object
        end
      end
    end
    moved = true
  end
  -- In warp the origin is the ship, and goes with it: everything that
  -- stands still is somewhere else each frame. (And once more when the
  -- origin is a grid's again.)
  if moved or grid == 0 then
    for id, object in scene.statics do
      local at = vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz)
      local proxy = scene.proxies[id]
      local offsets = scene.offsets[id]
      if offsets then
        proxy:SetPos(at + offsets[1])
        for index, work in scene.works[id] do
          work:SetPos(at + offsets[index + 1])
        end
      else
        place(proxy, at)
      end
    end
  end

  -- A cloud is as big as what is left in it: it thins as it is drawn
  -- off, and with nothing left there is nothing to see.
  for id, cloud in scene.clouds do
    local proxy: Object? = scene.proxies[id]
    local lobes = scene.works[id]
    if not proxy or lobes == nil then
      scene.clouds[id] = nil
    else
      local left = Core.Query.Left(game, id)
      if left ~= cloud.shown then
        cloud.shown = left
        local share = if left <= 0 then 0.001 else 0.4 + 0.6 * left
        proxy:SetScale(vector.create(cloud.sizes[1] * share, cloud.sizes[1] * share, cloud.sizes[1] * share))
        for index, lobe in lobes do
          local size = cloud.sizes[index + 1] * share
          lobe:SetScale(vector.create(size, size, size))
        end
      end
    end
  end

  -- A starbase that is not what it was when it was put up here.
  local changed: { number } = {}
  for id, was in scene.standing do
    if standing(game, id) ~= was then
      table.insert(changed, id)
    end
  end
  for _, id in changed do
    local object = objects[id % Constants.STRUCTURE_ID_SPAN]
    local old = scene.proxies[id]
    dropWorks(scene, id)
    if old then
      Object_Delete(old)
    end
    scene.proxies[id] = makeStation(scene, game, object,
      vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
  end

  table.clear(scene.screen)
  if next(inScene) then
    for _, object in objects do
      if inScene[object.site] then
        scene.screen[object.id] = vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz)
      end
    end
  end

  -- Ships on the grid (in warp, the player's own, and those where it
  -- has been and is going while they are near).
  scene.passing = 0
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local shown = ball.system == player.system and (id == player.ship or inScene[ball.grid] == true)
    -- (a cloaked ship is seen by nobody but its own pilot)
    local cloaked = Core.Query.Cloaked(game, id)
    if cloaked and id ~= player.ship then
      shown = false
    end
    -- (and those in warp that are near, going or coming; not while the
    -- pilot's own ship is in warp, when the scene goes with it. A ship
    -- that has gone unseen stays so.)
    if not shown and grid ~= 0 and ball.system == player.system and ball.warp and ball.warp.stage == "warp"
      and not cloaked then
      local x, y, z = ballAt(ball, state.tick, since)
      if (x - scene.eyeX) ^ 2 + (y - scene.eyeY) ^ 2 + (z - scene.eyeZ) ^ 2 < PASSING ^ 2 then
        shown = true
        scene.passing += 1
      end
    end
    local existing: Object? = scene.proxies[id]
    if shown then
      local proxy: Object
      if existing then
        proxy = existing
      else
        -- (a pirate's is in the pirates' paint, and a veteran's or a captain's in their own)
        local theirs = state.ships[id].owner == "pirates"
        proxy = makeShip(state.ships[id].type, ball.radius, theirs, if theirs then Pirates.Rank(state.ships[id].name) else nil)
        proxy:SetName(ball.name)
        container:AddInterior(proxy)
        scene.proxies[id] = proxy
        scene.ghosts[id] = nil
      end
      -- (to its own pilot a cloaked hull is the light bending round it:
      -- the same shape, drawn another way, with nothing mounted on it)
      local made = designed[proxy]
      if made and cloaked ~= (scene.ghosts[id] == true) then
        Object_SetRenderable(proxy, if cloaked then Hull.Ghost(made) else made.model)
        scene.ghosts[id] = if cloaked then true else nil :: any
        dropArms(scene, id)
      end
      local x, y, z, vx, vy, vz = ballAt(ball, state.tick, since)
      local at = vector.create(x - scene.ox, y - scene.oy, z - scene.oz)
      proxy:SetPos(at)
      local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
      if speed > 1 then
        local heading = vector.create(vx / speed, vy / speed, vz / speed)
        if designed[proxy] then
          Object_SetAxes(proxy, heading, if math.abs(heading.y) < 0.98 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
        else
          proxy:SetLook(heading)
        end
      end
      scene.screen[id] = at
    elseif existing then
      dropArms(scene, id)
      Object_Delete(existing)
      scene.proxies[id] = nil
      scene.ghosts[id] = nil
    end
  end
  -- Wrecks on the grid: the hull each was, in pieces (Hull.Wreck). The
  -- wreck's own object is a bare point for the rest to refer to.
  if next(inScene) then
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      if wreck.system == player.system and inScene[wreck.grid] then
        local at = vector.create(wreck.x - scene.ox, wreck.y - scene.oy, wreck.z - scene.oz)
        if scene.proxies[id] then
          scene.proxies[id]:SetPos(at)
        else
          local anchor = Object_Scenery({})
          container:AddInterior(anchor)
          anchor:SetPos(at)
          scene.proxies[id] = anchor
          -- It lies as the ship lay, if the ship is still here to ask
          -- (it is, on the frame it dies); else any way up.
          local look = vector.normalize(vector.create(dice(id) - 0.5, (dice(id + 1) - 0.5) * 0.4, dice(id + 2) - 0.5))
          local up = vector.create(0, 1, 0)
          for other, proxy in scene.proxies do
            if other >= Constants.FIRST_DYNAMIC_ID and state.balls[other] == nil and state.wrecks[other] == nil
              and vector.magnitude(proxy:GetPos() - at) < wreck.radius then
              look, up = proxy:GetLook(), proxy:GetUp()
            end
          end
          up = vector.normalize(up - look * vector.dot(up, look))
          makeWreck(scene, id, wreck, look, up, container)
        end
        placeWreck(scene, scene.wreckage[id], at, wreck.radius)
        scene.screen[id] = at
      end
    end
  end
  for id, proxy in scene.proxies do
    if id >= Constants.FIRST_DYNAMIC_ID and state.balls[id] == nil and state.wrecks[id] == nil then
      dropArms(scene, id)
      dropWreck(scene, id)
      Object_Delete(proxy)
      scene.proxies[id] = nil
    end
  end

  -- Their engines: a glare at each mouth and fire behind it, by how
  -- fast the ship means to go of what it can (so they light when it
  -- sets off, before it has got anywhere), and a little by how fast it
  -- is going.
  local fx = scene.fx :: Effects.Fx
  -- How hard the engines of a ship in warp are seen to burn, by how far
  -- off it is: the fire dims with every tenfold of distance, from all of
  -- it within a thousandth of as far as such a ship is drawn to none at
  -- the end of that. A ship's distance in warp grows and shrinks tenfold
  -- in equal times, so it fades out as it goes and in as it comes, and
  -- does not blink.
  local eye = vector.create(scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz)
  local function wake(at: vector): number
    return math.clamp(1 - math.log10(math.max(vector.magnitude(at - eye), 1) / (PASSING / 1000)) / 3, 0, 1)
  end
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local built = if proxy then designed[proxy] else nil
    local at: vector? = scene.screen[id]
    -- (a cloaked ship shows no fire)
    if proxy and built and at and not scene.ghosts[id] then
      local ball = state.balls[id]
      local warp = ball.warp
      local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
      local wanted = math.sqrt(ball.tvx * ball.tvx + ball.tvy * ball.tvy + ball.tvz * ball.tvz)
      local throttle = if warp and warp.stage == "warp" then 1 else (0.65 * wanted + 0.35 * speed) / math.max(ball.maxVelocity, 1)
      local right, up, look = proxy:GetRight(), proxy:GetUp(), proxy:GetLook()
      local unit = ball.radius / built.radius
      local color = vector.create(built.glow[1], built.glow[2], built.glow[3])
      -- (a trail three ship-lengths long at full speed; none in warp,
      -- where the scene goes with the ship and it has not moved)
      local trail: number? = math.clamp(6 * ball.radius / math.max(ball.maxVelocity, 1), 0.8, 20)
      -- (And none behind a carrier or anything bigger: the project
      -- owner's, 2026-11-13. A hull that size is too slow to draw one out
      -- behind it, and what was drawn was where its stern had swung as
      -- it turned, kilometres off to one side. Its engines glow, and
      -- that is all.)
      local flown = state.ships[id]
      local hull = if flown then Ships.byId[flown.type] else nil
      if hull and Ships.Capital(hull.class) then
        trail = nil
      end
      -- (a ship of somebody else's in warp draws its trail out behind it
      -- for a second and more, however small it is, and however big:
      -- that is what is seen of it going)
      if warp and warp.stage == "warp" and id ~= player.ship then
        trail = math.max(trail or 0, WAKE)
        throttle = wake(at)
      end
      for index, engine in built.engines do
        -- (and none while the pilot's own ship is in warp: the scene goes
        -- with that ship then, and every other one is somewhere else in
        -- it each frame)
        Effects.Thrust(fx, id * 16 + index, at + (right * engine.at.x + up * engine.at.y + look * engine.at.z) * unit, -look,
          engine.radius * unit, throttle, color, scene.time, if grid == 0 then nil else trail)
      end
    end
  end

  -- (A hull that is not of our own design has no engines to show, and
  -- one of ours may have none: in warp it draws a trail all the same,
  -- from its stern.)
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local at: vector? = scene.screen[id]
    local ball = state.balls[id]
    if proxy and at and id ~= player.ship and grid ~= 0 and ball.warp and ball.warp.stage == "warp" then
      local built = designed[proxy]
      if built == nil or #built.engines == 0 then
        local look = proxy:GetLook()
        Effects.Thrust(fx, id * 16 + 15, at - look * ball.radius, -look, 0.3 * ball.radius, wake(at), WAKE_COLOR, scene.time, WAKE)
      end
    end
  end

  -- What is on the hardpoints of the hulls of our own design. (After
  -- every ship has been placed: a turret points at where its target is
  -- this frame. The fits are looked at once a tick, and when a ship is
  -- first seen.)
  local seconds = math.clamp(scene.time - scene.armsTime, 0, 0.25)
  scene.armsTime = scene.time
  local check = scene.armsTick ~= state.tick
  scene.armsTick = state.tick
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local built = if proxy then designed[proxy] else nil
    local at: vector? = scene.screen[id]
    -- (nor anything on its hardpoints)
    if proxy and built and at and not scene.ghosts[id] then
      if check or scene.arms[id] == nil then
        armShip(scene, game, id, built, container)
      end
      local ball = state.balls[id]
      placeArms(scene, scene.arms[id], proxy, at, ball.radius, ball.vitals.running, seconds)
    end
  end

  -- The gate the pilot has just come out of lights, as the white clears.
  if not scene.lit then
    local at: vector? = scene.screen[player.ship]
    if at then
      scene.lit = true
      lightGate(scene, fx, gateNear(scene, at, 50000), JUMP_IN)
    end
  end

  -- What just happened, as effects (Game/View/Effects).
  for _, event in session.events do
    if event.kind == "Jumped" and event.ship ~= player.ship and grid ~= 0 then
      -- Somebody else through a gate that is in sight: out of this
      -- system by one of its gates, or into it by one.
      if event.from == player.system then
        lightGate(scene, fx, event.gate, 0.7)
      end
      if event.to == player.system then
        lightGate(scene, fx, event.arrival, 0.7)
      end
    elseif (event.kind == "BallAdded" or event.kind == "BallRemoved") and event.gate and grid ~= 0 then
      -- (and the system's own traffic, which comes in by a gate and goes
      -- out by one as far as anybody can see: Tactical/Traffic)
      lightGate(scene, fx, event.gate, 0.7)
    elseif event.kind == "Shot" then
      local from, to = state.balls[event.from], state.balls[event.to]
      if from and to then
        local item = state.items[event.item]
        -- (from the mouth of the gun, if it is one that is shown)
        Effects.Fire(fx, if item then item.type else FALLBACK[event.family] or "autocannon", from.id, to.id, from.radius, to.radius,
          event.outcome, event.flight or 0, struck(to), scene.time, if scene.screen[-event.item] then -event.item else nil)
      end
    elseif event.kind == "BatteryFired" then
      -- (from the station's side of its field toward what it fires on:
      -- which battery it was is not followed yet)
      local to = state.balls[event.to]
      local station = objects[event.station % Constants.STRUCTURE_ID_SPAN]
      if to and station and scene.screen[event.station] then
        scene.volleys += 1
        Effects.Fire(fx, if event.missile then "launcher.cruise" else "artillery.large", event.station, event.to, station.radius * 0.35,
          to.radius, "hit", 0, struck(to), scene.time, nil)
      end
    elseif (event.kind == "WarpStarted" or event.kind == "WarpEnded") and event.ball ~= player.ship and grid ~= 0 then
      -- Somebody else going into warp, or coming out of it, where it can
      -- be seen: a flash where they are (and a ring, coming out).
      local at: vector? = scene.screen[event.ball]
      local ball = state.balls[event.ball]
      if at and ball then
        Effects.Burst(fx, at, WAKE_COLOR, 5 * ball.radius, if event.kind == "WarpEnded" then 1 else 0, 0.5, scene.time)
      end
    elseif event.kind == "BallDestroyed" and event.system == player.system and grid ~= 0 then
      local at = vector.create(event.x - scene.ox, event.y - scene.oy, event.z - scene.oz)
      local boom = Object_Explosion(0, 0, 3)
      container:AddInterior(boom)
      boom:SetPos(at)
      Effects.Explode(fx, at, event.radius or 25, scene.time)
    end
  end
  -- A mining laser's beam, a salvager's, and that of whatever runs on
  -- another ship, for as long as the module runs: begun again each time
  -- the last one is nearly out.
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if scene.screen[id] and ball.system == player.system then
      for _, running in ball.vitals.running do
        local item = state.items[running.item]
        local rock = if running.target ~= 0 then Core.Query.Body(game, running.target) else nil
        if item and rock and Effects.Held(item.type) and scene.screen[running.target]
          and scene.time - (scene.mining[running.item] or -1) > 0.42 then
          scene.mining[running.item] = scene.time
          Effects.Fire(fx, item.type, id, running.target, ball.radius, rock.radius, "hit", 0, "", scene.time,
            if scene.screen[-running.item] then -running.item else nil)
        end
      end
    end
  end

  -- The sun, the planets and the moons in scaled space: each drawn in
  -- its true direction, near enough for the renderer to reach, and
  -- shrunk to span the angle it truly spans.
  --
  -- They cannot all be drawn at one distance: of two that overlap on the
  -- screen the larger would then hide the smaller whichever was in
  -- front, and a moon crossing the face of its planet would vanish. So
  -- they are taken nearest first, and each is put far enough out that
  -- the side of it facing the eye lies beyond the limb of the one
  -- before.
  local ex, ey, ez = scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz
  local bodies: { { object: SystemData.Object, distance: number } } = {}
  for _, object in objects do
    local dx, dy, dz = object.x - scene.eyeX, object.y - scene.eyeY, object.z - scene.eyeZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if object.kind == "planet" or object.kind == "moon" or object.kind == "sun" then
      table.insert(bodies, { object = object, distance = distance })
      if object.kind == "sun" and scene.star and distance > 0 then
        -- (the light itself, far off in the sun's direction, so that it
        -- falls on every body from nearly the right side)
        local out = 60000000 / distance
        scene.star:SetPos(vector.create(ex + dx * out, ey + dy * out, ez + dz * out))
      end
    elseif not scene.screen[object.id] and object.kind ~= "asteroid" then
      -- Somewhere to warp to: a station, gate or belt on another grid.
      local shrink = FAR / math.max(distance, FAR)
      scene.screen[object.id] = vector.create(ex + dx * shrink, ey + dy * shrink, ez + dz * shrink)
    end
  end
  table.sort(bodies, function(a, b)
    if a.distance ~= b.distance then
      return a.distance < b.distance
    end
    return a.object.id < b.object.id
  end)
  local limb = 0      -- how far off the limb of the body before lies
  for _, placed in bodies do
    local object, distance = placed.object, math.max(placed.distance, 1)
    -- (the sine of the angle its radius spans)
    local sine = math.min(object.radius / distance, 0.999)
    local out = math.min(math.max(math.min(distance, FAR), limb / (1 - sine)), FARTHEST)
    limb = out * math.sqrt(1 - sine * sine) * 1.002
    local shrink = out / distance
    local at = vector.create(ex + (object.x - scene.eyeX) * shrink, ey + (object.y - scene.eyeY) * shrink,
      ez + (object.z - scene.eyeZ) * shrink)
    local body = scene.celestials[object.id]
    body:SetPos(at)
    local radius = object.radius * shrink
    body:SetScale(vector.create(radius, radius, radius))
    -- (a world turns on its axis, as far as the game's time says)
    local world = scene.worlds[object.id]
    if world then
      Planet.Turn(world, state.tick * Constants.TICK + since)
    end
    scene.screen[object.id] = at
    if object.kind == "sun" and scene.star then
      -- The flare is the glare of a star too small to show a face. It
      -- is taken to lie just this side of the disc, so that a planet in
      -- front of the sun hides it and the disc does not; once the disc
      -- is big enough to see, the flare is left behind it, and goes.
      Star_SetFlareDepth(scene.star, if sine < FLARE_UNDER then out * (1 - sine) * 0.98 else 0)
    end
  end

  Effects.Update(fx, scene.time, scene.screen)

  -- (docked in a colony ship, it is that ship the camera is on)
  -- (the ship itself, when it is in space to be seen: until then, and
  -- the moment a pilot is put aboard one, the gate it lies by. The
  -- camera is never left on something of a system that is gone.)
  local _, carrier = Core.Query.Carrier(game, player.docked)
  scene.focus = scene.proxies[if me then player.ship elseif carrier ~= 0 then carrier else player.docked]
    or (if me == nil then scene.proxies[beside] else nil)
end

-- Have the camera keep something in view past the ship (by its id),
-- or with 0 or nothing, stop.
function Scene.Track(scene: Scene, id: number?)
  scene.tracking = id or 0
end

-- Orbit the camera around the focus. 'input' is false while the cursor is
-- over the interface.
function Scene.UpdateCamera(scene: Scene, frameSeconds: number, input: boolean)
  local focus = scene.focus
  if focus == nil then
    return
  end
  if input then
    scene.zoomTarget = math.clamp(scene.zoomTarget * (1 - 0.12 * Mouse_GetScrollDelta()), 2.5, 4000)
    if Mouse_LeftDown() then
      local delta = Cursor_GetDelta()
      scene.yaw -= 0.008 * delta.x
      scene.pitch = math.clamp(scene.pitch - 0.008 * delta.y, 0.08, math.pi - 0.08)
      -- (a hand on the camera takes it back from whatever it was following)
      if delta.x ~= 0 or delta.y ~= 0 then
        scene.tracking = 0
      end
    end
  end
  -- Following something: the camera swings round, a little each frame,
  -- to sit on the far side of the ship from it, a little above the line
  -- through the two so that the ship does not hide it.
  local followed: vector? = if scene.tracking ~= 0 then scene.screen[scene.tracking] else nil
  if followed then
    local away = focus:GetPos() - followed
    if vector.magnitude(away) > 1 then
      away = vector.normalize(away)
      local pitch = math.clamp(math.acos(math.clamp(away.y, -1, 1)) - 0.16, 0.05, math.pi - 0.05)
      local yaw = math.atan2(away.z, away.x)
      local ease = 1 - Float_ExpDecay(frameSeconds, 0.25)
      -- (round the short way)
      local turn = (yaw - scene.yaw + math.pi) % (2 * math.pi) - math.pi
      scene.yaw += turn * ease
      scene.pitch += (pitch - scene.pitch) * ease
    end
  elseif scene.tracking ~= 0 then
    -- (it has gone from the grid, or the ship has)
    scene.tracking = 0
  end
  scene.zoom += (scene.zoomTarget - scene.zoom) * (1 - Float_ExpDecay(frameSeconds, 0.12))
  local look = vector.create(
    math.sin(scene.pitch) * math.cos(scene.yaw), math.cos(scene.pitch), math.sin(scene.pitch) * math.sin(scene.yaw))
  -- The engine camera's "relative" positions are in fact scene
  -- coordinates (src/liblt/Game/Camera.cpp), so orbit the focus's own
  -- position. It eases toward where it is told to be; with a ship moving
  -- at hundreds of metres a second that would trail behind, so the easing
  -- is made effectively instant and the smoothing done on the zoom above.
  local camera = scene.camera
  local center = focus:GetCenter()
  local distance = scene.zoom * focus:GetRadius()
  if scene.docked then
    -- (the eye and what it looks at go aside together, and the tower
    -- goes the other way across the window)
    local across = vector.cross(look, vector.create(0, 1, 0))
    if vector.magnitude(across) > 1e-3 then
      center += vector.normalize(across) * (distance * DOCKED_ASIDE)
    end
  end
  camera:SetTarget(focus)
  camera:SetRelativePos(center + look * distance)
  camera:SetRelativeLookAt(center)
  camera:SetRigidity(100000)
  -- In warp the view opens out; and through a gate, farther.
  local eased = scene.warp * scene.warp * (3 - 2 * scene.warp)
  camera:SetFov(62 + 30 * eased + 44 * scene.rush)
end

-- Advance the engine's own effects (lights, trails, particles).
function Scene.Update(scene: Scene, frameSeconds: number)
  scene.time += frameSeconds
  local container = scene.container
  if container then
    container:Update(frameSeconds)
  end
end

return Scene
