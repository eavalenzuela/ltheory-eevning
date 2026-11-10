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
--   - the sun, as the direction light comes from.
--
-- The engine's positions lose precision far from zero, and its far plane
-- is at 1e6. So the scene's origin is the anchor of the player's grid
-- (or, in warp, the ship itself), and everything is placed relative to
-- that, worked out in doubles first.
--
-- Between ticks ships are drawn where the Core's own formulas put them
-- (Tactical/Motion): the state at a tick fixes the next second of flight.

local Clock = require("@lt/Game/Clock")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Planet = require("@lt/Game/View/Planet")
local Motion = require("@lt/Core/Tactical/Motion")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local SystemData = require("@lt/Core/Describe/System")

local Scene = {}

export type Placed = { object: Object, x: number, y: number, z: number, radius: number }

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
  shots: { Shot },                    -- recent shots, for the interface to draw
}

-- A shot to show: who at whom, how it went, and when (scene time). A
-- missile takes 'flight' seconds to arrive; anything else is instant.
export type Shot = { from: number, to: number, family: string, outcome: string, born: number, flight: number }

-- How long a shot stays on screen after it lands, in seconds.
Scene.SHOT_SECONDS = 0.35


-- Bodies beyond the renderer's reach are drawn this far away.
local FAR = 600000

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
    warp = 0, warpLeft = 0, warpSeconds = 0, time = 0, shots = {},
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

local function makeShip(type: string, radius: number): Object
  local item: Item? = hullItems[type]
  if not item then
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or 55, 1, 1, 1, 1, 1, 1)
    hullItems[type] = made
    return made:Instantiate()
  end
  return item:Instantiate()
end

local function makeStatic(object: SystemData.Object): Object
  local made: Object
  if object.kind == "asteroid" then
    -- (An asteroid cannot be named: the engine object has no such part.)
    made = Object_Asteroid(object.seed)
    made:SetScale(vector.create(object.radius, object.radius, object.radius))
  else
    -- Stations, and gates until they have a model of their own.
    made = Item_StationType(1000000, object.seed, 1, 1, 1, 1):Instantiate()
    fit(made, object.radius)
    made:SetName(object.name)
  end
  return made
end

local function clear(scene: Scene, objects: { [number]: Object })
  for _, object in objects do
    Object_Delete(object)
  end
  table.clear(objects)
end

-- Throw away everything and start a container for 'system'.
local function enterSystem(scene: Scene, game: Core.Game, system: number)
  clear(scene, scene.proxies)
  clear(scene, scene.celestials)
  if scene.container then
    Object_Delete(scene.container)
  end
  scene.focus = nil
  scene.star = nil
  scene.key = ""
  scene.system = system

  local container = Object_System(vector.create(0, 0, 0), game.state.galaxySeed * 7919 + system)
  scene.container = container
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
      local kind = if object.kind == "moon" then (if object.variety == "barren" then "moon" else "")
        elseif Planet.kinds[object.variety] then object.variety
        else ""
      if kind ~= "" then
        body = Planet.New(kind, object.seed, if object.kind == "moon" then MOON_MAP else WORLD_MAP).body
      else
        body = Item_PlanetType(object.seed):Instantiate()
      end
      body:SetName(object.name)
      container:AddInterior(body)
      scene.celestials[object.id] = body
    end
  end
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
    for id, object in scene.proxies do
      if state.balls[id] == nil then
        Object_Delete(object)
        scene.proxies[id] = nil
      end
    end
    if grid ~= 0 then
      for _, object in objects do
        if object.site == grid and object.kind ~= "belt" then
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
        proxy:SetLook(vector.create(vx / speed, vy / speed, vz / speed))
      end
      scene.screen[id] = at
    elseif existing then
      Object_Delete(existing)
      scene.proxies[id] = nil
    end
  end
  -- Wrecks on the grid: a lump of rubble, until wrecks have a look of
  -- their own.
  if grid ~= 0 then
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      if wreck.system == player.system and wreck.grid == grid then
        local at = vector.create(wreck.x - scene.ox, wreck.y - scene.oy, wreck.z - scene.oz)
        if not scene.proxies[id] then
          local rubble = Object_Asteroid(id % 100000)
          local size = wreck.radius * 0.6
          rubble:SetScale(vector.create(size, size, size))
          container:AddInterior(rubble)
          rubble:SetPos(at)
          scene.proxies[id] = rubble
        end
        scene.screen[id] = at
      end
    end
  end
  for id, proxy in scene.proxies do
    if id >= Constants.FIRST_DYNAMIC_ID and state.balls[id] == nil and state.wrecks[id] == nil then
      Object_Delete(proxy)
      scene.proxies[id] = nil
    end
  end

  -- What just happened, as effects.
  for _, event in session.events do
    if event.kind == "Shot" then
      table.insert(scene.shots, { from = event.from, to = event.to, family = event.family, outcome = event.outcome,
        born = scene.time, flight = event.flight or 0 })
    elseif event.kind == "BallDestroyed" and event.system == player.system and grid ~= 0 then
      local boom = Object_Explosion(0, 0, 3)
      container:AddInterior(boom)
      boom:SetPos(vector.create(event.x - scene.ox, event.y - scene.oy, event.z - scene.oz))
    end
  end
  for index = #scene.shots, 1, -1 do
    local shot = scene.shots[index]
    if scene.time - shot.born > shot.flight + Scene.SHOT_SECONDS then
      table.remove(scene.shots, index)
    end
  end

  -- Planets and moons in scaled space; the sun as a direction.
  local ex, ey, ez = scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz
  for _, object in objects do
    local dx, dy, dz = object.x - scene.eyeX, object.y - scene.eyeY, object.z - scene.eyeZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if object.kind == "planet" or object.kind == "moon" then
      local shrink = math.min(1, FAR / distance)
      local body = scene.celestials[object.id]
      local at = vector.create(ex + dx * shrink, ey + dy * shrink, ez + dz * shrink)
      body:SetPos(at)
      local radius = object.radius * shrink
      body:SetScale(vector.create(radius, radius, radius))
      scene.screen[object.id] = at
    elseif object.kind == "sun" then
      local star = scene.star
      if star and distance > 0 then
        local out = 60000000 / distance
        star:SetPos(vector.create(ex + dx * out, ey + dy * out, ez + dz * out))
      end
      local shrink = FAR / math.max(distance, FAR)
      scene.screen[object.id] = vector.create(ex + dx * shrink, ey + dy * shrink, ez + dz * shrink)
    elseif not scene.screen[object.id] and object.kind ~= "asteroid" then
      -- Somewhere to warp to: a station, gate or belt on another grid.
      local shrink = FAR / math.max(distance, FAR)
      scene.screen[object.id] = vector.create(ex + dx * shrink, ey + dy * shrink, ez + dz * shrink)
    end
  end

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
