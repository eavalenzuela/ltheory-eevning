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
local Motion = require("@lt/Core/Tactical/Motion")
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
  screen: { [number]: vector },       -- where each drawn body is in the scene, this frame
  focus: Object?,
  yaw: number,
  pitch: number,
  zoom: number,                       -- camera distance, in focus radii
  zoomTarget: number,
  warp: number,                       -- 0 out of warp, rising to 1 in the middle of one
  warpLeft: number,                   -- metres still to go
  warpSeconds: number,                -- and seconds
  time: number,                       -- seconds the scene has been running, for effects
  fx: Effects.Fx?,                    -- weapon fire and the like, in this system's container
  mining: { [number]: number },       -- when each mining module's beam was last begun, by its item
  wreckage: { [number]: Wrecked },    -- the pieces of each wreck on the grid
  works: { [number]: { Object } },    -- what stands round each station's tower: its modules, their guns, its field
  arms: { [number]: Armed },          -- what is on the hardpoints of each ship of our own design
  armsTick: number,                   -- the tick the arms were last checked against the fits
  armsTime: number,                   -- when (scene time) the turrets were last swung
}

-- A shot to show: who at whom, how it went, and when (scene time). A
-- missile takes 'flight' seconds to arrive; anything else is instant.



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
    proxies = {}, celestials = {}, screen = {}, focus = nil,
    yaw = 0.6, pitch = 1.25, zoom = 6, zoomTarget = 6,
    warp = 0, warpLeft = 0, warpSeconds = 0, time = 0, fx = nil, mining = {},
    wreckage = {}, works = {}, arms = {}, armsTick = -1, armsTime = 0,
  }
end

-- Scale an object so its bounding radius is 'radius' metres.
local function fit(object: Object, radius: number)
  local current = object:GetRadius()
  if current > 0 then
    object:SetScale(object:GetScale() * (radius / current))
  end
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

local function makeShip(type: string, radius: number): Object
  local built = Hull.Build(type)
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
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or 55, 1, 1, 1, 1, 1, 1)
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
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or 55, 1, 1, 1, 1, 1, 1)
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
    -- Gates, until they have a model of their own. (A station is a
    -- tower and what is anchored round it: makeStation.)
    made = Item_StationType(1000000, object.seed, 1, 1, 1, 1):Instantiate()
    fit(made, object.radius)
    made:SetName(object.name)
  end
  return made
end

-- A station: its tower, which is the station's own object, with its
-- modules and its field round it, at 'at'. The station's radius is the
-- radius of its field.
local function makeStation(scene: Scene, object: SystemData.Object, at: vector, container: Object): Object
  local raised = Starbase.Raise(Starbase.Layout(object.variety, object.radius, object.seed), container, at, 1)
  local tower = table.remove(raised, 1) :: Object
  tower:SetName(object.name)
  scene.works[object.id] = raised
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
  if scene.container then
    Object_Delete(scene.container)
  end
  if scene.fx then
    Effects.Clear(scene.fx, true)
  end
  table.clear(scene.mining)
  scene.focus = nil
  scene.star = nil
  scene.key = ""
  scene.system = system

  local container = Object_System(vector.create(0, 0, 0), game.state.galaxySeed * 7919 + system)
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
        body = Planet.New(kind, object.seed, if object.kind == "moon" then MOON_MAP else WORLD_MAP).body
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

-- Bring the engine's objects into line with the Core for this frame.
function Scene.Sync(scene: Scene, session: Session.Session)
  local game = session.game
  local state = game.state
  local since = Clock.SinceTick(session.clock)
  local player = Core.Query.Player(game)
  if player.system ~= scene.system then
    enterSystem(scene, game, player.system)
  end
  local container = scene.container :: Object
  local objects = Core.Query.Objects(game, player.system)
  local me = state.balls[player.ship]

  -- Where the player is, and which grid to show.
  local grid = 0
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
    local station = objects[player.docked % Constants.STRUCTURE_ID_SPAN]
    scene.eyeX, scene.eyeY, scene.eyeZ = station.x, station.y, station.z
    grid = station.id
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

  -- A different grid: replace the bodies that sit on it. Ships are kept,
  -- since a hull is costly to make and the player's comes along.
  if key ~= scene.key then
    scene.key = key
    -- (the origin has moved under every trail)
    if scene.fx then
      Effects.Still(scene.fx)
    end
    for id, object in scene.proxies do
      if state.balls[id] == nil then
        dropArms(scene, id)
        dropWreck(scene, id)
        dropWorks(scene, id)
        Object_Delete(object)
        scene.proxies[id] = nil
      end
    end
    if grid ~= 0 then
      for _, object in objects do
        if object.site == grid and object.kind == "station" then
          scene.proxies[object.id] = makeStation(scene, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
        elseif object.site == grid and object.kind ~= "belt" then
          local made = makeStatic(object)
          container:AddInterior(made)
          place(made, vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz))
          scene.proxies[object.id] = made
        end
      end
    end
  end

  table.clear(scene.screen)
  if grid ~= 0 then
    for _, object in objects do
      if object.site == grid then
        scene.screen[object.id] = vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz)
      end
    end
  end

  -- Ships on the grid (in warp, only the player's own).
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local shown = ball.system == player.system and (id == player.ship or (grid ~= 0 and ball.grid == grid))
    local existing: Object? = scene.proxies[id]
    if shown then
      local proxy: Object
      if existing then
        proxy = existing
      else
        proxy = makeShip(state.ships[id].type, ball.radius)
        proxy:SetName(ball.name)
        container:AddInterior(proxy)
        scene.proxies[id] = proxy
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
    end
  end
  -- Wrecks on the grid: the hull each was, in pieces (Hull.Wreck). The
  -- wreck's own object is a bare point for the rest to refer to.
  if grid ~= 0 then
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      if wreck.system == player.system and wreck.grid == grid then
        local at = vector.create(wreck.x - scene.ox, wreck.y - scene.oy, wreck.z - scene.oz)
        if not scene.proxies[id] then
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
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local built = if proxy then designed[proxy] else nil
    local at: vector? = scene.screen[id]
    if proxy and built and at then
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
      local trail = math.clamp(6 * ball.radius / math.max(ball.maxVelocity, 1), 0.8, 20)
      for index, engine in built.engines do
        Effects.Thrust(fx, id * 16 + index, at + (right * engine.at.x + up * engine.at.y + look * engine.at.z) * unit, -look,
          engine.radius * unit, throttle, color, scene.time, trail)
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
    if proxy and built and at then
      if check or scene.arms[id] == nil then
        armShip(scene, game, id, built, container)
      end
      local ball = state.balls[id]
      placeArms(scene, scene.arms[id], proxy, at, ball.radius, ball.vitals.running, seconds)
    end
  end

  -- What just happened, as effects (Game/View/Effects).
  for _, event in session.events do
    if event.kind == "Shot" then
      local from, to = state.balls[event.from], state.balls[event.to]
      if from and to then
        local item = state.items[event.item]
        -- (from the mouth of the gun, if it is one that is shown)
        Effects.Fire(fx, if item then item.type else FALLBACK[event.family] or "autocannon", from.id, to.id, from.radius, to.radius,
          event.outcome, event.flight or 0, struck(to), scene.time, if scene.screen[-event.item] then -event.item else nil)
      end
    elseif event.kind == "BallDestroyed" and event.system == player.system and grid ~= 0 then
      local at = vector.create(event.x - scene.ox, event.y - scene.oy, event.z - scene.oz)
      local boom = Object_Explosion(0, 0, 3)
      container:AddInterior(boom)
      boom:SetPos(at)
      Effects.Explode(fx, at, event.radius or 25, scene.time)
    end
  end
  -- A mining laser's beam, for as long as the module runs: begun again
  -- each time the last one is nearly out.
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if scene.screen[id] and ball.system == player.system then
      for _, running in ball.vitals.running do
        local item = state.items[running.item]
        local rock = if running.target ~= 0 then Core.Query.Body(game, running.target) else nil
        if item and rock and string.sub(item.type, 1, 5) == "miner" and scene.screen[running.target]
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

  scene.focus = scene.proxies[if me then player.ship else player.docked]
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
    end
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
  camera:SetTarget(focus)
  camera:SetRelativePos(center + look * (scene.zoom * focus:GetRadius()))
  camera:SetRelativeLookAt(center)
  camera:SetRigidity(100000)
  -- In warp the view opens out.
  local eased = scene.warp * scene.warp * (3 - 2 * scene.warp)
  camera:SetFov(62 + 30 * eased)
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
