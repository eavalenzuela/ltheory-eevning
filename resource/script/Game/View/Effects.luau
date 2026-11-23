--!strict
-- Effects: what weapons look like when they fire, as things in the
-- scene. Nothing here decides anything: the Core has already said what
-- was fired at what and how it went, and this draws it.
--
-- Each weapon fires what it is:
--   pulse laser    a short red beam
--   beam laser     a long blue one
--   autocannon     a burst of tracer rounds
--   artillery      one heavy shell
--   blaster        a slug of plasma
--   railgun        a line that is there at once and thins away
--   launcher       a missile: a small body with its motor's flame at its
--                  tail, and a trail behind it
--   mining laser   a green beam for as long as it works
-- and what it hits flashes: blue with a ring on a shield, orange on
-- armour, white on the hull; a missile bursts.
--
-- An effect runs between two bodies of the scene, by their ids, and is
-- placed afresh each frame from where they are then (Effects.Update).
-- Every piece is a square of light on a scenery object, turned to face
-- the eye by its vertex shader (fx_streak.jsl, fx_square.jsl).

local Plates = require("@lt/Game/View/Plates")

local Effects = {}

type Piece = { object: Object, shader: ShaderInstance, pool: string }

type Look = {
  kind: "beam" | "bolt" | "rail" | "missile",
  color: { number },
  width: number,          -- half-width of its glow, metres, for a small weapon (the bright
                          -- line down the middle is a twentieth of that)
  life: number?,          -- beam, rail: seconds it lasts
  length: number?,        -- bolt, missile: metres
  speed: number?,         -- bolt: metres a second
  burst: number?,         -- bolt: how many, one after another
  gap: number?,           -- and how long between them
  blunt: number?,         -- bolt: 0 a needle, 1 a ball
  held: boolean?,         -- beam: it stays for as long as its module runs, not for a shot
}

type Effect = {
  look: Look,
  from: number,
  to: number,
  origin: number?,        -- where in 'where' the mouth of the gun it leaves is, if it is shown
  fromRadius: number,
  toRadius: number,
  miss: vector?,          -- for a miss: where it goes instead, from the target
  born: number,
  life: number,
  flight: number,         -- seconds to reach the target (0: at once)
  size: number,           -- 1 small, 2 medium, 3 large
  struck: string,         -- what it lands on: "shield", "armor", "hull", or "" (nothing to show)
  landed: boolean,
  pieces: { Piece },
  -- A missile of a volley (Core's Data/Modules 'volley'): its path.
  -- Nil for every other.
  path: Path?,
  -- A missile's id in the Core (point defence finds it by that), and,
  -- once it is shot down (Effects.Down), how far through its flight.
  missile: number?,
  downed: number?,
  -- A missile flies after its target in the Core and lands when it
  -- says (Effects.Track, Effects.Land): until then it is held short.
  arrived: boolean?,
  -- A plasma torpedo (the Nimia's): the colour of its ball. Nil for every
  -- other.
  ball: vector?,
  -- A point defence tracer that misses: how far wide it goes, as a part
  -- of the way (its 'miss' then the way, a unit long). Nil for every
  -- other.
  scatter: number?,
  -- A missile's body and the flame of its motor (missileParts), while it
  -- flies. Nil for every other.
  body: Piece?,
  flame: Piece?,
}

-- A volley missile's path: the points it goes by, each (how far along,
-- across, up), as parts of the way from firer to target, in a frame
-- square to that way with 'up' (the firer's, for a vertical launch) as
-- near its up as it can be; and when it is at each (as a part of its
-- flight). It goes straight from one point to the next: a few far apart
-- make a swarm's jinking path, many close together a vertical launch's
-- arc. It leaves from 'cell' (m, along and across) off the launcher's
-- mouth, and lands 'aim' (m) off the middle of its target. Its contrail
-- hangs 'hang' seconds where it has been, 'thick' times the swarm's.
type Path = {
  times: { number },
  points: { vector },
  up: vector?,
  cell: vector,
  aim: vector,
  hang: number,
  thick: number,
}

type Flash = {
  on: number,             -- the body it is on, or 0: 'offset' is then a place in the scene
  offset: vector,         -- and where, from that body's centre
  color: vector,
  size: number,
  ring: number,
  born: number,
  life: number,
  piece: Piece,
}

-- An engine that is burning: a glare at its mouth and the fire behind.
type Burn = {
  glare: Piece,
  plume: Piece,
  frame: number,
  level: number,
  time: number,
  trail: { Piece },       -- the lengths of its trail, newest first (none until one is asked for)
  points: { vector },     -- where its mouth has been, newest first, a step of time apart
  stamp: number,          -- when the newest of those was noted
}

-- How many lengths a trail is drawn in.
local SEGMENTS = 8

export type Fx = {
  container: Object,
  effects: { Effect },
  flashes: { Flash },
  burns: { [number]: Burn },  -- by the key Effects.Thrust was given
  frame: number,              -- counts Effects.Update, to tell which burns were asked for since
  pools: { [string]: { Piece } },
  made: { Piece },        -- every piece there is, in use or put away
  seed: number,
  rush: { Piece },        -- the lines going by the pilot's ship in warp (Effects.Rush)
  heads: { [number]: vector },  -- where each missile in the air was drawn last, by its id in the Core
}

Effects.looks = {
  ["laser.pulse"] = { kind = "beam", color = { 1.0, 0.22, 0.10 }, width = 5, life = 0.28 },
  ["laser.beam"] = { kind = "beam", color = { 0.30, 0.62, 1.0 }, width = 7, life = 0.85 },
  ["autocannon"] = { kind = "bolt", color = { 1.0, 0.80, 0.38 }, width = 3, length = 70, speed = 4200, burst = 4, gap = 0.06, blunt = 0 },
  ["artillery"] = { kind = "bolt", color = { 1.0, 0.56, 0.22 }, width = 7, length = 130, speed = 2600, burst = 1, gap = 0, blunt = 0.2 },
  ["blaster"] = { kind = "bolt", color = { 0.30, 1.0, 0.72 }, width = 11, length = 70, speed = 1900, burst = 1, gap = 0, blunt = 1 },
  ["railgun"] = { kind = "rail", color = { 0.55, 0.80, 1.0 }, width = 5, life = 0.55 },
  ["launcher"] = { kind = "missile", color = { 1.0, 0.62, 0.26 }, width = 7, length = 180 },
  -- (a point defence turret's tracers: Effects.Tracers)
  ["pds"] = { kind = "bolt", color = { 1.0, 0.82, 0.40 }, width = 4, length = 260, speed = 2600, burst = 2, gap = 0.05, blunt = 0 },
  ["miner"] = { kind = "beam", color = { 0.35, 1.0, 0.55 }, width = 5, life = 0.5, held = true },
  -- (what draws gas off a cloud: wider and paler, into the cloud's middle)
  ["miner.gas"] = { kind = "beam", color = { 0.80, 0.88, 1.0 }, width = 9, life = 0.5, held = true },
  -- What runs on another ship or a wreck for as long as it is on (the
  -- scene begins each beam again while the module runs): thin, and each
  -- its own colour.
  ["salvager"] = { kind = "beam", color = { 1.0, 0.70, 0.30 }, width = 3, life = 0.5, held = true },
  -- (a citadel's tether to a ship of its side: like a web, the owner's 2026-11-19)
  ["tether"] = { kind = "beam", color = { 0.45, 0.85, 1.0 }, width = 6, life = 0.5, held = true },
  ["projector."] = { kind = "beam", color = { 0.90, 0.80, 0.30 }, width = 3, life = 0.5, held = true },
  ["disruptor."] = { kind = "beam", color = { 0.70, 0.40, 1.0 }, width = 3, life = 0.5, held = true },
  ["painter."] = { kind = "beam", color = { 1.0, 0.30, 0.30 }, width = 2, life = 0.5, held = true },
  ["damper."] = { kind = "beam", color = { 0.50, 0.60, 0.80 }, width = 2, life = 0.5, held = true },
  ["neutraliser."] = { kind = "beam", color = { 0.80, 0.60, 1.0 }, width = 4, life = 0.5, held = true },
  ["jammer."] = { kind = "beam", color = { 0.70, 0.90, 1.0 }, width = 2, life = 0.5, held = true },
  ["remote.shield"] = { kind = "beam", color = { 0.40, 0.75, 1.0 }, width = 4, life = 0.5, held = true },
  ["remote.armor"] = { kind = "beam", color = { 1.0, 0.75, 0.35 }, width = 4, life = 0.5, held = true },
  ["remote.capacitor"] = { kind = "beam", color = { 1.0, 0.95, 0.45 }, width = 4, life = 0.5, held = true },
  -- (the modules of the expansion of 2026-11-16, made 2026-11-17 at the
  -- owner's asking for the effects the new modules need; the colours
  -- mine: a tractor's pale sea green and wide, a sensor booster's
  -- green, the disruptors of guns and missiles amber, a siphon's
  -- magenta, a scanner's a thread of pale blue)
  ["tractor."] = { kind = "beam", color = { 0.55, 1.0, 0.92 }, width = 6, life = 0.5, held = true },
  ["remote.sensor"] = { kind = "beam", color = { 0.45, 1.0, 0.60 }, width = 2, life = 0.5, held = true },
  ["ewar."] = { kind = "beam", color = { 1.0, 0.62, 0.25 }, width = 2, life = 0.5, held = true },
  ["drain."] = { kind = "beam", color = { 0.95, 0.35, 0.85 }, width = 4, life = 0.5, held = true },
  ["scanner.ship"] = { kind = "beam", color = { 0.60, 0.85, 1.0 }, width = 1.5, life = 0.5, held = true },
  ["scanner.cargo"] = { kind = "beam", color = { 0.60, 0.85, 1.0 }, width = 1.5, life = 0.5, held = true },
} :: { [string]: Look }

-- Whether a module's beam is one that stays for as long as it runs (a
-- mining laser's, a salvager's, and whatever runs on another ship)
-- rather than one shot's.
function Effects.Held(type: string): boolean
  local look = Effects.LookOf(type)
  return look ~= nil and look.held == true
end

-- How much wider a medium or a large weapon's fire is than a small one's.
local SIZE = { 1, 1.8, 3 }

-- A streak's glow is never narrower than this share of its distance
-- from the eye (some six pixels to a side, which leaves the bright line
-- down its middle about a pixel), nor a flash smaller than SMALL of it.
local THIN = 0.006
local SMALL = 0.010
-- An engine's glare and its fire are let go smaller: a point and a thread.
local GLINT = 0.0035
local THREAD = 0.0012

-- The longest a round from a gun is in flight, in seconds.
local BLINK = 0.4

local STRUCK = {
  shield = { color = { 0.35, 0.62, 1.0 }, ring = 1 },
  armor = { color = { 1.0, 0.55, 0.20 }, ring = 0 },
  hull = { color = { 1.0, 0.92, 0.80 }, ring = 0 },
} :: { [string]: { color: { number }, ring: number } }

-- How big the flash at a gun's mouth is, in metres, by the gun's size.
local MUZZLE = { 10, 18, 34 }

local function vec(c: { number }): vector
  return vector.create(c[1], c[2], c[3])
end

-- The look of a weapon by its type ("laser.pulse.medium",
-- "launcher.heavy", "miner.strip"), and its size, 1 to 3.
function Effects.LookOf(type: string): (Look?, number)
  local size = if string.find(type, "large", 1, true) or string.find(type, "cruise", 1, true) then 3
    elseif string.find(type, "medium", 1, true) or string.find(type, "heavy", 1, true) then 2
    else 1
  -- (the longest start of its id that there is a look for: "miner.gas"
  -- before "miner")
  local found: Look? = nil
  local length = 0
  for prefix, look in Effects.looks do
    if #prefix > length and string.sub(type, 1, #prefix) == prefix then
      found, length = look, #prefix
    end
  end
  return found, size
end

function Effects.New(container: Object): Fx
  return { container = container, effects = {}, flashes = {}, burns = {}, frame = 0, pools = {}, made = {}, seed = 0, rush = {},
    heads = {} }
end

local streakMesh: Mesh? = nil
local squareMesh: Mesh? = nil

-- A piece to draw with: a square of light with the fragment shader
-- 'name', as a streak (a strip along the object's z) or a flash. Pieces
-- are kept by shader, or by 'kept' for a use that sets one up its own way.
local function take(fx: Fx, name: string, streak: boolean, kept: string?): Piece
  local pool = fx.pools[kept or name]
  if pool and #pool > 0 then
    return table.remove(pool) :: Piece
  end
  local shader = ShaderInstance_Create(Shader_Create(if streak then "fx_streak.jsl" else "fx_square.jsl", name))
  ShaderInstance_SetState(shader, "BlendModeAdditive")
  ShaderInstance_SetState(shader, "ZWritableOff")
  ShaderInstance_SetState(shader, "CullModeDisabled")
  ShaderInstance_SetFloat(shader, "fxMin", if streak then THIN else SMALL)
  ShaderInstance_Link(shader)
  local mesh: Mesh
  if streak then
    streakMesh = streakMesh or Mesh_Plane(vector.create(-1, 0, 0), vector.create(2, 0, 0), vector.create(0, 0, 1), 2, 2)
    mesh = streakMesh :: Mesh
  else
    squareMesh = squareMesh or Mesh_Plane(vector.create(-1, 0, -1), vector.create(2, 0, 0), vector.create(0, 0, 2), 2, 2)
    mesh = squareMesh :: Mesh
  end
  local model = Model_Create()
  Model_AddShell(model, mesh, shader)
  local object = Object_Scenery({})
  Object_SetRenderable(object, model)
  -- (nothing to see until it is first placed)
  object:SetScale(vector.create(0, 0, 0))
  fx.container:AddInterior(object)
  local piece = { object = object, shader = shader, pool = kept or name }
  table.insert(fx.made, piece)
  return piece
end

local NOWHERE = vector.create(0, 0, 0)

-- A swarm's missiles (Effects.Fire's 'volley', its path "zig"), and the
-- contrail of every volley's: the kick out of the rack
-- (how far along it ends, and how far to the side, as parts of the way to
-- the target), how far the first turns swing, how long the contrail
-- hangs where the missile has been (seconds), and its colour: an orange
-- glow where it is fresh, cooling to pale smoke.
local ZIG_KICK_AT, ZIG_KICK = 0.05, 0.10
local ZIG_REACH = 0.11
local ZIG_HANG = 1.6
local ZIG_GLOW = vector.create(1.0, 0.55, 0.2)
local ZIG_SMOKE = vector.create(0.8, 0.8, 0.85)

-- A vertical launch's missiles (Effects.Fire's 'volley', its path "arc";
-- the owner's, 2026-11-19): straight up out of the cell for the first
-- quarter of the flight, to a quarter of the way to the target high; a
-- sharp turn over at the top, so tight (a part of the way) and so quick
-- (a part of the flight); then down on the target, gathering speed (as
-- the time gone to this power), in so many straight pieces. And how far
-- apart the cells of the launcher's two rows of four are (m, at least).
local ARC_CLIMB = 0.25
local ARC_HIGH = 0.25
local ARC_TURN, ARC_TURNING = 0.04, 0.05
local ARC_SPEEDING = 2
local ARC_PIECES = 10
local ARC_CELL = 4
-- (and its smoke: long-lasting and thick, the owner's 2026-11-19, and
-- spreading as it ages to so many times as wide)
local ARC_HANG = 12
local ARC_THICK = 4
local ARC_SPREAD = 2.5
-- (and at the least so thick for the length of its flight, so that it is
-- a plume to see however far it goes)
local ARC_PLUME = 0.012

-- A plasma torpedo's ball (Effects.Fire's 'volley', its path "plasma"):
-- its colour for each kind, Plasmostatic and Plasmobaric, and how big it
-- is (m, for a small one).
local PLASMA_STATIC = vector.create(0.62, 0.82, 1.0)
local PLASMA_BARIC = vector.create(1.0, 0.45, 0.15)
local PLASMA_SIZE = 40

-- A missile in flight (the owner, 2026-11-21: "there's no missile body or
-- rocket flame to visually track them from launcher to target"): a small
-- body, so long (m) by the launcher's size and pointed the way it flies,
-- and the flame of its motor at its tail, flickering. The flame is never
-- smaller than FLAME_MIN of its distance from the eye (a little more than
-- a flash's SMALL: what is bright in it is the middle of that), so
-- that it can be followed all the way from the launcher to the target,
-- even flying straight away from the eye; the body is there to see close.
local MISSILE_BODY = { 7, 11, 17 }
local FLAME_COLOR = vector.create(1.0, 0.78, 0.45)
local FLAME_MIN = 0.012

-- How wide of the line a point defence tracer that misses may go, as a
-- part of the way (about a degree: the owner's "slight", 2026-11-19).
local TRACER_SCATTER = 0.017

-- A number from 0 to 1 that is always the same for the same 'n'.
local function noise(n: number): number
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

-- Put a piece away for the next effect that wants one like it.
local function give(fx: Fx, piece: Piece)
  piece.object:SetScale(NOWHERE)
  local pool = fx.pools[piece.pool]
  if pool == nil then
    pool = {}
    fx.pools[piece.pool] = pool
  end
  table.insert(pool, piece)
end

-- Lay a streak from a to b, 'width' to a side.
local function lay(piece: Piece, a: vector, b: vector, width: number)
  local d = b - a
  local length = vector.magnitude(d)
  if length < 1e-3 then
    piece.object:SetScale(NOWHERE)
    return
  end
  d /= length
  -- (any direction across it will do for "up": the shader turns the strip)
  local up = vector.cross(d, if math.abs(d.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
  piece.object:SetPos(a)
  Object_SetAxes(piece.object, d, up)
  piece.object:SetScale(vector.create(width, 1, length))
end

local function paint(piece: Piece, color: vector, fade: number, age: number)
  ShaderInstance_SetVec3(piece.shader, "fxColor", color)
  ShaderInstance_SetFloat(piece.shader, "fxFade", fade)
  ShaderInstance_SetFloat(piece.shader, "fxAge", age)
end

-- A missile's body, a unit long along its own z, its nose at +0.5: a
-- slim pale grey cylinder with a pointed nose and a dark tail.
local bodyModel: Model? = nil
local function missileModel(): Model
  local kept = bodyModel
  if kept then
    return kept
  end
  local b = Plates.New(17, 0.01)
  -- (turned about z, from the nose to the tail: Plates.Revolve, clockwise in (out, along))
  local r = 0.07
  local profile = {
    vector.create(1e-4, 0.5, 0), vector.create(r * 0.55, 0.38, 0), vector.create(r, 0.24, 0), vector.create(r, -0.42, 0),
    vector.create(r * 0.8, -0.5, 0), vector.create(1e-4, -0.5, 0),
  }
  Plates.Revolve(b, Plates.PLATING, profile, 14, false)
  -- (and four small fins at its tail)
  for k = 0, 3 do
    local a = k * math.pi / 2
    local out = vector.create(math.cos(a), math.sin(a), 0)
    Plates.Block(b, Plates.FRAME, out * (r * 1.6) + vector.create(0, 0, -0.38), vector.create(r * 0.75, r * 0.06, 0.09),
      vector.create(0, 0, a), 0.1)
  end
  local look: Plates.Look = { plating = { 0.62, 0.63, 0.66 }, patch = { 0.55, 0.55, 0.57 }, frame = { 0.2, 0.2, 0.22 },
    glow = { 1, 0.7, 0.4 }, trim = { 0.7, 0.2, 0.1 }, wear = 0, rust = 0, sheets = 1 }
  local model = Plates.Finish(b, look, nil)
  bodyModel = model
  return model
end

-- A missile's body and its flame, from the pools.
local function missileParts(fx: Fx, effect: Effect)
  local pool = fx.pools["missile.body"]
  local body: Piece
  if pool and #pool > 0 then
    body = table.remove(pool) :: Piece
  else
    local object = Object_Scenery({})
    Object_SetRenderable(object, missileModel())
    object:SetScale(vector.create(0, 0, 0))
    fx.container:AddInterior(object)
    -- (it is never painted: it has its own look)
    body = { object = object, shader = nil :: any, pool = "missile.body" }
    table.insert(fx.made, body)
  end
  local flame = take(fx, "fx_flash.jsl", false, "missile.flame")
  ShaderInstance_SetFloat(flame.shader, "fxMin", FLAME_MIN)
  ShaderInstance_SetFloat(flame.shader, "fxRing", 0)
  ShaderInstance_SetFloat(flame.shader, "fxSeed", fx.seed * 1.7)
  effect.body, effect.flame = body, flame
end

-- A missile's body with its nose at 'head', flying along 'd', and its
-- flame at its tail; or neither, with no 'head'.
local function placeMissile(effect: Effect, head: vector?, d: vector, age: number)
  local body, flame = effect.body, effect.flame
  if body == nil or flame == nil then
    return
  end
  if head == nil or vector.magnitude(d) < 1e-6 then
    body.object:SetScale(NOWHERE)
    flame.object:SetScale(NOWHERE)
    return
  end
  local length = MISSILE_BODY[effect.size]
  local up = vector.cross(d, if math.abs(d.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
  body.object:SetPos(head - d * (length * 0.5))
  Object_SetAxes(body.object, d, vector.normalize(up))
  body.object:SetScale(vector.create(length, length, length))
  local flicker = 1 + 0.18 * math.sin(age * 47) + 0.1 * math.sin(age * 83 + 1.3)
  local size = length * 0.55 * flicker
  flame.object:SetPos(head - d * (length * 1.05))
  flame.object:SetScale(vector.create(size, 1, size))
  paint(flame, FLAME_COLOR, 1, 0.08)
end

-- A flash on a body, 'offset' from its centre. 'fire' makes it a ball of
-- fire in place of a point of light.
function Effects.Flash(fx: Fx, on: number, offset: vector, color: vector, size: number, ring: number, life: number, now: number,
  fire: boolean?)
  local piece = take(fx, if fire then "fx_fire.jsl" else "fx_flash.jsl", false)
  fx.seed += 1
  ShaderInstance_SetFloat(piece.shader, "fxRing", ring)
  ShaderInstance_SetFloat(piece.shader, "fxSeed", fx.seed * 1.7)
  table.insert(fx.flashes, { on = on, offset = offset, color = color, size = size, ring = ring, born = now, life = life, piece = piece })
end

-- A weapon of type 'type' on body 'from' fires at body 'to'. 'outcome'
-- is the Core's: "miss", "hit", "wreck" (a telling hit), or for a missile
-- "launched"; 'flight' is how long a missile takes; 'struck' is what the
-- shot lands on ("shield", "armor", "hull"). 'origin', if given, is what
-- Effects.Update's 'where' will hold the mouth of the gun under, for the
-- shot to leave from there and not from the middle of the ship.
-- 'volley', for a missile of a volley (Core's Data/Modules 'volley'):
-- which of it this is, from 1; its path ("zig" or "arc"); how long after
-- the first it leaves (s); and the firer's up, for a vertical launch.
-- 'missile', for a missile: its id in the Core, for point defence to
-- find it (Effects.Down, Effects.Tracers).
function Effects.Fire(fx: Fx, type: string, from: number, to: number, fromRadius: number, toRadius: number,
  outcome: string, flight: number, struck: string, now: number, origin: number?,
  volley: { n: number, path: string, delay: number, up: vector?, charge: string? }?, missile: number?)
  local look, size = Effects.LookOf(type)
  if look == nil then
    return
  end
  local shots = look.burst or 1
  for shot = 1, shots do
    fx.seed += 1
    local miss: vector? = nil
    if outcome == "miss" then
      -- past the target, to one side of it
      local angle = fx.seed * 2.4
      miss = vector.create(math.cos(angle), math.sin(angle * 1.3), math.sin(angle)) * (toRadius * 2.2 + 12)
    end
    local effect: Effect = {
      look = look, from = from, to = to, origin = origin, fromRadius = fromRadius, toRadius = toRadius, miss = miss,
      born = now + (shot - 1) * (look.gap or 0), life = look.life or 0, flight = flight, size = size,
      struck = if outcome == "miss" then "" else struck, landed = false, pieces = {}, missile = missile,
    }
    if volley and volley.path == "plasma" then
      -- (a plasma torpedo: a ball of its kind's colour, flying straight in)
      effect.ball = if volley.charge and string.find(volley.charge, "static", 1, true) then PLASMA_STATIC else PLASMA_BARIC
    elseif volley then
      local n = volley.n
      local seed = fx.seed * 7.31 + n * 1.17
      local times: { number }, points: { vector } = {}, {}
      local cell = vector.create(0, 0, 0)
      if volley.path == "arc" then
        -- (a vertical launch: out of its cell in the two rows of four, four along one and four back along the
        -- other, straight up, over and down; each a little higher or lower than the next)
        local row = if n <= 4 then 0 else 1
        local column = if row == 0 then n - 1 else 8 - n
        cell = vector.create(row - 0.5, column - 1.5, 0) * math.max(ARC_CELL * SIZE[size], fromRadius * 0.05)
        local high = ARC_HIGH * (0.9 + 0.2 * noise(seed))
        -- up, at an even speed
        for k = 0, 3 do
          table.insert(times, ARC_CLIMB * k / 4)
          table.insert(points, vector.create(0, 0, high * k / 4))
        end
        -- over (a curve from going up to going at the target)
        local top = vector.create(0, 0, high)
        local corner = top + vector.create(0, 0, ARC_TURN)
        local toward = vector.normalize(vector.create(1, 0, 0) - corner)
        local over = corner + toward * ARC_TURN
        for k = 0, 3 do
          local u = k / 4
          table.insert(times, ARC_CLIMB + ARC_TURNING * u)
          table.insert(points, top * ((1 - u) * (1 - u)) + corner * (2 * (1 - u) * u) + over * (u * u))
        end
        -- and down, faster and faster, onto the target
        local rest = 1 - ARC_CLIMB - ARC_TURNING
        for k = 0, ARC_PIECES do
          local f = k / ARC_PIECES
          table.insert(times, ARC_CLIMB + ARC_TURNING + rest * f ^ (1 / ARC_SPEEDING))
          table.insert(points, over + (vector.create(1, 0, 0) - over) * f)
        end
      else
        -- (a swarm's missile: kicked out of the rack to one side, then jinking hard this way and that, the swings
        -- dying as it closes)
        local angle = noise(seed) * 2 * math.pi
        table.insert(points, vector.create(0, 0, 0))
        table.insert(points, vector.create(ZIG_KICK_AT, math.cos(angle) * ZIG_KICK, math.sin(angle) * ZIG_KICK))
        local turns = 5 + math.floor(noise(seed + 1) * 3)
        for k = 1, turns do
          local u = ZIG_KICK_AT + (0.9 - ZIG_KICK_AT) * (k - 0.5 + 0.6 * (noise(seed + k * 3.1) - 0.5)) / turns
          local reach = ZIG_REACH * (1 - u) ^ 0.7
          angle += math.pi * (0.3 + 0.4 * noise(seed + k * 5.7))
          table.insert(points, vector.create(u, math.cos(angle) * reach, math.sin(angle) * reach))
        end
        table.insert(points, vector.create(1, 0, 0))
        for _, point in points do
          table.insert(times, point.x)
        end
      end
      -- (and each lands at a place of its own on the target)
      local angle = noise(seed + 9) * 2 * math.pi
      local aim = vector.create(math.cos(angle), noise(seed + 11) - 0.5, math.sin(angle)) * (toRadius * 0.4)
      local arc = volley.path == "arc"
      effect.path = { times = times, points = points, up = volley.up, cell = cell, aim = aim,
        hang = if arc then ARC_HANG else ZIG_HANG, thick = if arc then ARC_THICK else 1 }
      effect.born += volley.delay
    end
    if look.kind == "beam" or look.kind == "rail" then
      table.insert(effect.pieces, take(fx, "fx_beam.jsl", true))
    elseif look.kind == "bolt" then
      local piece = take(fx, "fx_bolt.jsl", true)
      ShaderInstance_SetFloat(piece.shader, "fxBlunt", look.blunt or 0)
      table.insert(effect.pieces, piece)
    else
      local trail = take(fx, "fx_bolt.jsl", true)
      ShaderInstance_SetFloat(trail.shader, "fxBlunt", 0.3)
      table.insert(effect.pieces, trail)
      -- (a plasma torpedo's ball)
      if effect.ball then
        local ball = take(fx, "fx_flash.jsl", false, "plasma")
        ShaderInstance_SetFloat(ball.shader, "fxRing", 0)
        ShaderInstance_SetFloat(ball.shader, "fxSeed", fx.seed * 1.7)
        table.insert(effect.pieces, ball)
      end
      -- (a missile's body and its motor's flame, but a plasma torpedo's: that is its ball)
      if look.kind == "missile" and effect.ball == nil then
        missileParts(fx, effect)
      end
      -- (a volley's missile: a piece of contrail for every leg of its path)
      for _ = 1, if effect.path then #effect.path.times - 1 else 0 do
        local smoke = take(fx, "fx_bolt.jsl", true)
        ShaderInstance_SetFloat(smoke.shader, "fxBlunt", 0)
        table.insert(effect.pieces, smoke)
      end
    end
    table.insert(fx.effects, effect)
  end
  -- The gun's mouth flashes (a beam's does not: the beam is there to
  -- see). A gun on a big hull is small, and this is what shows where it
  -- is: the flash is never drawn smaller than a few pixels.
  if look.kind == "bolt" or look.kind == "rail" then
    if origin then
      -- (at the mouth itself, and the size of the gun rather than the ship)
      Effects.Flash(fx, origin, vector.create(0, 0, 0), vec(look.color), MUZZLE[size], 0, 0.10, now)
    else
      Effects.Flash(fx, from, vector.create(0, 0, 0), vec(look.color), 0.5 * fromRadius * SIZE[size], 0, 0.10, now)
    end
  elseif look.kind == "missile" and origin then
    -- (a missile leaving its rack: the motor lighting)
    Effects.Flash(fx, origin, vector.create(0, 0, 0), vec(look.color), 0.8 * MUZZLE[size], 0, 0.22, now)
  end
end

-- The flash where an effect lands.
local function land(fx: Fx, effect: Effect, at: vector, where: { [number]: vector }, now: number)
  effect.landed = true
  local centre: vector? = where[effect.to]
  if centre == nil then
    return
  end
  -- (sized to what is struck: a hit on a frigate is not a hit on a
  -- battleship; a heavier weapon makes a somewhat bigger one)
  local scale = effect.toRadius * (0.8 + 0.2 * SIZE[effect.size])
  if effect.look.kind == "missile" and effect.struck ~= "" then
    Effects.Flash(fx, effect.to, at - centre, vec(effect.look.color), 2.5 * scale, 1, 0.55, now)
  end
  local struck = STRUCK[effect.struck]
  if struck then
    Effects.Flash(fx, effect.to, at - centre, vec(struck.color), (if struck.ring > 0 then 1.5 else 0.8) * scale, struck.ring,
      if struck.ring > 0 then 0.40 else 0.22, now)
  end
end

-- A flash at a place in the scene, on no body (something has blown up
-- and is not there to be on).
function Effects.Burst(fx: Fx, at: vector, color: vector, size: number, ring: number, life: number, now: number, fire: boolean?)
  Effects.Flash(fx, 0, at, color, size, ring, life, now, fire)
end

-- Where in Effects.Update's 'where' a missile in the air is (its head,
-- as drawn last), by its id in the Core: for tracers to go at.
local MISSILE_KEYS = 2 ^ 40
function Effects.MissileKey(id: number): number
  return MISSILE_KEYS + id
end

-- A missile shot down by point defence (Core's Tactical/PointDefence):
-- it bursts where it was, and goes no further; its trail hangs there.
-- 'quiet': one whose fuel is spent, which only goes out.
function Effects.Down(fx: Fx, missile: number, now: number, quiet: boolean?)
  for _, effect in fx.effects do
    if effect.missile == missile and effect.downed == nil and not effect.arrived then
      effect.downed = math.clamp((now - effect.born) / math.max(effect.flight, 0.05), 0, 0.999)
      local at = fx.heads[missile]
      if at and not quiet then
        Effects.Burst(fx, at, vector.create(1.0, 0.72, 0.36), 18 * SIZE[effect.size], 0, 0.3, now)
      end
    end
  end
end

-- Where the Core has a missile in its flight (each second, Core's
-- Tactical/Combat): so far through it, and so many seconds from landing
-- if its target stood still. Its drawing is timed again to that.
function Effects.Track(fx: Fx, missile: number, progress: number, eta: number, now: number)
  for _, effect in fx.effects do
    if effect.missile == missile and not effect.arrived and effect.downed == nil then
      local part = math.clamp(progress, 0, 0.98)
      -- (never back along its way: what is drawn only slows, if its target has drawn ahead)
      local was = math.clamp((now - effect.born) / math.max(effect.flight, 0.05), 0, 0.999)
      part = math.max(part, math.min(was, 0.98))
      local flight = math.max(eta, 0.05) / (1 - part)
      effect.flight = flight
      effect.born = now - part * flight
    end
  end
end

-- A missile the Core says has reached its target: it lands now.
function Effects.Land(fx: Fx, missile: number, now: number)
  for _, effect in fx.effects do
    if effect.missile == missile and effect.downed == nil then
      effect.arrived = true
      effect.born = now - effect.flight
    end
  end
end

-- A point defence turret's stream: so many tracers at a missile in the
-- air (its id in the Core) or at a drone (its ball), over the second,
-- the last of them striking if it brought the missile down.
function Effects.Tracers(fx: Fx, from: number, fromRadius: number, missile: number?, drone: number?, rounds: number,
  down: boolean, now: number, origin: number?)
  local to = if missile then Effects.MissileKey(missile) elseif drone then drone else nil
  if to == nil then
    return
  end
  -- (every round of the stream, a tenth of a second apart as it fired them, each drawn as a pair: a steady stream)
  local shown = math.max(1, rounds)
  for k = 1, shown do
    local before = #fx.effects
    Effects.Fire(fx, "pds", from, to, fromRadius, 4, if down and k == shown then "hit" else "miss", 0, "",
      now + (k - 1) * 0.1, origin)
    -- (a slight scatter: a round that misses goes a little wide, by about a degree at the most)
    for index = before + 1, #fx.effects do
      local effect = fx.effects[index]
      if effect.miss then
        effect.miss = vector.normalize(effect.miss)
        effect.scatter = TRACER_SCATTER * (0.3 + 0.7 * noise(fx.seed * 3.7 + index))
      end
    end
  end
end

-- A number from 0 to 1 that follows from 'n' and looks like chance.
local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- A ship of radius 'radius' blows up at 'at': a white flash, a fireball
-- with a ring thrown out from it, smaller blasts through the hull for a
-- moment after, and a glow that lingers. A bigger ship makes a bigger
-- explosion, of more blasts, that takes longer over it.
function Effects.Explode(fx: Fx, at: vector, radius: number, now: number)
  local slow = math.clamp(math.sqrt(radius / 25), 0.8, 2.6)
  -- the flash, and the ring it throws out
  Effects.Burst(fx, at, vector.create(1.0, 0.96, 0.88), 3.0 * radius, 0, 0.20 * slow, now)
  Effects.Burst(fx, at, vector.create(1.0, 0.70, 0.36), 6.0 * radius, 1, 0.70 * slow, now)
  -- the fireball
  Effects.Burst(fx, at, vector.create(1.0, 0.62, 0.22), 4.2 * radius, 0, 1.3 * slow, now, true)
  local blasts = math.clamp(math.floor(2 + radius / 14), 2, 9)
  for blast = 1, blasts do
    fx.seed += 1
    local n = fx.seed
    local offset = vector.create(dice(n) - 0.5, dice(n + 0.31) - 0.5, dice(n + 0.67) - 0.5) * (1.8 * radius)
    local color = if blast % 2 == 0 then vector.create(1.0, 0.78, 0.36) else vector.create(1.0, 0.50, 0.18)
    Effects.Burst(fx, at + offset, color, (1.0 + 1.4 * dice(n + 0.5)) * radius, 0, 0.55 * slow,
      now + (0.06 + 0.60 * dice(n + 0.11)) * slow, true)
  end
  -- and what smoulders after
  Effects.Burst(fx, at, vector.create(0.85, 0.30, 0.10), 3.4 * radius, 0, 2.4 * slow, now + 0.25 * slow, true)
end

-- An engine burns, this frame. 'key' is the engine's own (the same
-- every frame); 'at' is the middle of its mouth, 'aft' the way its fire
-- goes, 'radius' half the mouth's width, 'throttle' how hard it is
-- burning from 0 to 1. It glows a little even at rest. Say so every
-- frame: an engine not heard from by the next Effects.Update is out.
--
-- With 'trail', it also leaves a trail along the way it has come, that
-- many seconds long: a thread from its mouth back through where the
-- mouth has been, fading to nothing. (Places are the scene's: if the
-- scene's origin moves, call Effects.Still, or every trail will leap.)
function Effects.Thrust(fx: Fx, key: number, at: vector, aft: vector, radius: number, throttle: number, color: vector, now: number,
  trail: number?)
  local burn = fx.burns[key]
  if burn == nil then
    local glare = take(fx, "fx_flash.jsl", false, "glare")
    local plume = take(fx, "fx_plume.jsl", true)
    -- (neither is kept as big on the screen as a shot is: far off, a
    -- ship under way is a point of light and a thread)
    ShaderInstance_SetFloat(glare.shader, "fxMin", GLINT)
    ShaderInstance_SetFloat(glare.shader, "fxRing", 0)
    ShaderInstance_SetFloat(glare.shader, "fxSeed", key * 1.7)
    ShaderInstance_SetFloat(plume.shader, "fxMin", THREAD)
    burn = { glare = glare, plume = plume, frame = 0, level = math.clamp(throttle, 0, 1), time = now, trail = {}, points = {}, stamp = now }
    fx.burns[key] = burn
  end
  burn.frame = fx.frame
  -- (an engine does not jump from one setting to another: it comes up
  -- and dies down over half a second or so)
  burn.level += (math.clamp(throttle, 0, 1) - burn.level) * (1 - math.exp(-4 * math.clamp(now - burn.time, 0, 0.1)))
  burn.time = now
  throttle = burn.level
  local size = radius * (2.6 + 2.4 * throttle)
  burn.glare.object:SetPos(at)
  burn.glare.object:SetScale(vector.create(size, 1, size))
  -- (the flash's shader late in its life: a soft glow, its rays nearly gone)
  paint(burn.glare, color, 0.30 + 0.50 * throttle, 0.92)
  if throttle > 0.02 then
    lay(burn.plume, at, at + aft * (radius * (3 + 11 * throttle)), radius * 1.25)
    paint(burn.plume, color, 0.35 + 0.65 * throttle, now)
  else
    burn.plume.object:SetScale(NOWHERE)
  end

  if trail then
    local points = burn.points
    local step = trail / SEGMENTS
    if #points == 0 or now < burn.stamp then
      table.clear(points)
      points[1] = at
      burn.stamp = now
    elseif now - burn.stamp >= step then
      table.insert(points, 1, at)
      burn.stamp = now
      if #points > SEGMENTS then
        table.remove(points)
      end
    end
    if #burn.trail == 0 then
      for _ = 1, SEGMENTS do
        local piece = take(fx, "fx_trail.jsl", true)
        ShaderInstance_SetFloat(piece.shader, "fxMin", THREAD)
        table.insert(burn.trail, piece)
      end
    end
    -- From the mouth back, each length from one noted place to the one
    -- before, as bright at each end as a trail that old is.
    local function glow(age: number): number
      return 0.55 * throttle * math.max(0, 1 - age / trail) ^ 1.5
    end
    local since = now - burn.stamp
    local newer, newerAge = at, 0
    for index = 1, SEGMENTS do
      local piece = burn.trail[index]
      local older: vector? = points[index]
      if older then
        local olderAge = since + (index - 1) * step
        lay(piece, newer, older, radius * 0.5)
        paint(piece, color, glow(newerAge), glow(olderAge))
        newer, newerAge = older, olderAge
      else
        piece.object:SetScale(NOWHERE)
      end
    end
  else
    -- (no trail now: what was drawn of one goes, and where the engine
    -- has been is forgotten. Left as it was, a trail stayed where it was
    -- last laid and went into warp with the pilot's ship, frozen behind
    -- it: a battleship's, twenty seconds long, the owner, 2026-11-23)
    table.clear(burn.points)
    for _, piece in burn.trail do
      piece.object:SetScale(NOWHERE)
    end
  end
end

-- The scene's origin has moved: forget where every engine has been.
function Effects.Still(fx: Fx)
  for _, burn in fx.burns do
    table.clear(burn.points)
  end
end

-- Place everything for this frame. 'where' gives each body's place in
-- the scene; an effect whose ends are not both there is dropped.
function Effects.Update(fx: Fx, now: number, where: { [number]: vector })
  -- (where each missile was drawn last frame, for the tracers going after it: Effects.Tracers)
  for id, head in fx.heads do
    where[Effects.MissileKey(id)] = head
  end
  local heads: { [number]: vector } = {}
  for index = #fx.effects, 1, -1 do
    local effect = fx.effects[index]
    local look = effect.look
    local a: vector?, b: vector? = where[effect.from], where[effect.to]
    local age = now - effect.born
    local done = a == nil or b == nil
    if not done and age >= 0 then
      local from, to = a :: vector, b :: vector
      local color = vec(look.color)
      local width = look.width * SIZE[effect.size]
      local d = vector.normalize(to - from)
      -- From the side of the firer toward the target, to the side of
      -- the target toward the firer (or past it).
      local mouth: vector? = if effect.origin then where[effect.origin] else nil
      local start = mouth or from + d * (effect.fromRadius * 0.7)
      local finish = if effect.miss and effect.scatter then to + effect.miss * (vector.magnitude(to - start) * effect.scatter) + d * 200
        elseif effect.miss then to + effect.miss + d * (effect.toRadius * 6 + 200) else to - d * (effect.toRadius * 0.6)
      -- (the way it flies, which from a gun out on the hull is not quite
      -- the way from one ship to the other)
      if vector.magnitude(finish - start) > 1e-3 then
        d = vector.normalize(finish - start)
      end
      local piece = effect.pieces[1]
      if look.kind == "beam" then
        local t = age / effect.life
        done = t >= 1
        -- quickly on, steady, quickly off
        local fade = math.min(1, t * 12) * math.min(1, (1 - t) * 5)
        lay(piece, start, finish, width)
        paint(piece, color, fade, age)
        if not effect.landed and age > 0.03 then
          land(fx, effect, finish, where, now)
        end
      elseif look.kind == "rail" then
        local t = age / effect.life
        done = t >= 1
        -- there at once, then thinning away
        lay(piece, start, finish, width * (1 - 0.7 * t))
        paint(piece, color, (1 - t) ^ 2, 0)
        if not effect.landed then
          land(fx, effect, finish, where, now)
        end
      else
        -- Something that flies: a bolt at its speed, a missile in the
        -- time the Core gave it.
        local span = vector.magnitude(finish - start)
        -- (the Core's guns hit at once at any range: a round is not let
        -- take longer than a blink, however far it has to go)
        local flight = if look.kind == "missile" then math.max(effect.flight, 0.05)
          else math.min(span / (look.speed or 2000), BLINK)
        local t = age / flight
        -- (a missile of the Core's lands when the Core says it has, and not before: Effects.Land)
        if effect.missile and not effect.arrived and not effect.downed then
          t = math.min(t, 0.999)
        end
        local path = effect.path
        if path then
          -- (a volley's missile: its head along its path, and its contrail hanging where it has been, each part
          -- glowing as the head passes and cooling to smoke, until it is gone; the last of it after the hit)
          -- (one shot down stops where it was, and its trail hangs from there)
          local stopped = effect.downed or 1
          if t >= 1 and not effect.landed and effect.downed == nil then
            land(fx, effect, finish, where, now)
          end
          local hang = path.hang / flight
          done = t >= stopped + hang
          local near = path.up or (if math.abs(d.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
          local side = vector.cross(d, near)
          if vector.magnitude(side) < 1e-3 then
            side = vector.cross(d, if math.abs(d.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
          end
          side = vector.normalize(side)
          local up = vector.cross(side, d)
          local cell = d * path.cell.x + side * path.cell.y
          local times, points = path.times, path.points
          local function at(point: vector, u: number): vector
            return start + cell * (1 - u) + path.aim * u + (d * point.x + side * point.y + up * point.z) * span
          end
          local function along(u: number): vector
            for k = 2, #times do
              if u <= times[k] then
                local f = (u - times[k - 1]) / math.max(times[k] - times[k - 1], 1e-6)
                return at(points[k - 1] + (points[k] - points[k - 1]) * f, u)
              end
            end
            return at(points[#points], 1)
          end
          local head, tail = math.min(t, stopped), math.max(0, t - hang)
          for k = 2, #times do
            local smoke = effect.pieces[k]
            local first, last = math.max(times[k - 1], tail), math.min(times[k], head)
            if last > first then
              local fresh = math.max(0, 1 - (t - (first + last) / 2) / hang)
              local warm = fresh ^ 3
              local spread = if path.thick > 1 then 1 + (ARC_SPREAD - 1) * (1 - fresh) else 1
              local thick = if path.thick > 1 then math.max(width * path.thick, span * ARC_PLUME / 0.35) else width
              lay(smoke, along(first), along(last), thick * spread * (0.35 + 0.25 * warm))
              paint(smoke, ZIG_SMOKE + (ZIG_GLOW - ZIG_SMOKE) * warm, fresh ^ 1.5 * 0.85, age)
            else
              smoke.object:SetScale(NOWHERE)
            end
          end
          if t < stopped then
            lay(piece, along(math.max(0, t - 0.02)), along(t), width * 0.6)
            paint(piece, color, 1, age)
            if effect.missile and t >= 0 then
              heads[effect.missile] = along(t)
            end
            local now_, was = along(t), along(math.max(0, t - 0.01))
            placeMissile(effect, if t >= 0 then now_ else nil,
              if vector.magnitude(now_ - was) > 1e-3 then vector.normalize(now_ - was) else d, age)
          else
            piece.object:SetScale(NOWHERE)
            placeMissile(effect, nil, d, age)
          end
        elseif effect.downed then
          done = true
        elseif t >= 1 then
          done = true
          if not effect.landed then
            land(fx, effect, finish, where, now)
          end
        else
          local head = start + (finish - start) * t
          local length = math.min((look.length or 30) * SIZE[effect.size], span * t)
          if effect.ball then
            -- (a plasma torpedo: a glowing ball, a short shimmering tail behind it)
            local ball = effect.pieces[2]
            local size = PLASMA_SIZE * SIZE[effect.size] * (1 + 0.12 * math.sin(age * 23))
            ball.object:SetPos(head)
            ball.object:SetScale(vector.create(size, 1, size))
            paint(ball, effect.ball, 1, 0.12)
            lay(piece, head - d * length * 0.6, head, width * 1.4)
            paint(piece, effect.ball, 0.7, age)
          else
            -- (the trail behind the missile's body and its flame)
            local back = MISSILE_BODY[effect.size] * 1.05
            lay(piece, head - d * (length + back), head - d * back, width)
            paint(piece, color, 0.8, age)
            placeMissile(effect, head, d, age)
          end
          if effect.missile and t >= 0 then
            heads[effect.missile] = head
          end
        end
      end
    end
    if done then
      for _, piece in effect.pieces do
        give(fx, piece)
      end
      for _, piece in { effect.body, effect.flame } :: { Piece? } do
        if piece then
          give(fx, piece)
        end
      end
      table.remove(fx.effects, index)
    end
  end

  fx.heads = heads

  for index = #fx.flashes, 1, -1 do
    local flash = fx.flashes[index]
    local centre: vector? = if flash.on == 0 then NOWHERE else where[flash.on]
    local t = (now - flash.born) / flash.life
    if centre == nil or t >= 1 then
      give(fx, flash.piece)
      table.remove(fx.flashes, index)
    elseif t >= 0 then
      flash.piece.object:SetPos(centre + flash.offset)
      flash.piece.object:SetScale(vector.create(flash.size, 1, flash.size))
      paint(flash.piece, flash.color, (1 - t) ^ 1.5, t)
    end
  end

  -- The engines nobody has said are still burning go out.
  for key, burn in fx.burns do
    if burn.frame ~= fx.frame then
      give(fx, burn.glare)
      give(fx, burn.plume)
      for _, piece in burn.trail do
        give(fx, piece)
      end
      fx.burns[key] = nil
    end
  end
  fx.frame += 1
end

-- The pilot's own ship in warp: the dust and the light of the place it
-- is crossing, drawn out into lines that go by it, a tunnel of them
-- about the way it goes. (The project owner's go-ahead, 2026-11-13: it
-- was a wider view and a banner, and nothing going by.)
-- 'depth' is how deep into the warp it is, from 0 (not at all: they are
-- put away) to 1; 'at' is the ship in the scene, 'ahead' the way it
-- goes, and 'radius' its own, which everything here is a multiple of:
-- a bigger ship is seen from farther off, and has a wider tunnel.
-- Each line keeps its own place round the ship and its own speed, comes
-- from far ahead and goes far behind, and comes again.
local RUSH = 110
local RUSH_NEAR, RUSH_FAR = 3, 46       -- how far off the ship's way they run, radii
local RUSH_SPAN = 170                   -- how far ahead they come from, and go behind, radii
local RUSH_COLOR = vector.create(0.62, 0.80, 1.0)

local function scatter(index: number, salt: number): number
  local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
  return x - math.floor(x)
end

function Effects.Rush(fx: Fx, depth: number, at: vector, ahead: vector, radius: number, now: number)
  if depth <= 0.001 then
    for _, piece in fx.rush do
      give(fx, piece)
    end
    table.clear(fx.rush)
    return
  end
  while #fx.rush < RUSH do
    table.insert(fx.rush, take(fx, "fx_rush.jsl", true))
  end
  -- (two ways across the way it goes)
  local across = vector.cross(ahead, if math.abs(ahead.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
  across = vector.normalize(across)
  local over = vector.cross(ahead, across)
  local span = RUSH_SPAN * radius
  for index, piece in fx.rush do
    local angle = 2 * math.pi * scatter(index, 1)
    local off = radius * (RUSH_NEAR + (RUSH_FAR - RUSH_NEAR) * scatter(index, 2) ^ 1.4)
    -- (so many spans a second: the nearer lines seem the faster for being near)
    local speed = 0.9 + 1.5 * scatter(index, 3)
    local along = span - ((now * speed + scatter(index, 4)) % 1) * 2 * span
    local length = radius * (10 + 70 * depth) * (0.5 + scatter(index, 5))
    local head = at + across * (off * math.cos(angle)) + over * (off * math.sin(angle)) + ahead * along
    lay(piece, head, head + ahead * length, radius * 0.05)
    -- (dimmest far ahead and far behind, where it comes and goes)
    local ends = 1 - math.abs(along) / span
    paint(piece, RUSH_COLOR, depth * (0.25 + 0.75 * scatter(index, 6)) * math.min(1, 3 * ends), 0)
  end
end

-- Drop every effect. 'gone' says the container has been deleted, and
-- the pieces with it; otherwise they are taken out of it.
function Effects.Clear(fx: Fx, gone: boolean)
  if not gone then
    for _, piece in fx.made do
      Object_Delete(piece.object)
    end
  end
  table.clear(fx.effects)
  table.clear(fx.flashes)
  table.clear(fx.burns)
  table.clear(fx.pools)
  table.clear(fx.made)
  table.clear(fx.rush)
end

return Effects
