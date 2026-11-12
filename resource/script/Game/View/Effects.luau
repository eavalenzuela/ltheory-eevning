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
--   launcher       a missile, a light with a trail behind it
--   mining laser   a green beam for as long as it works
-- and what it hits flashes: blue with a ring on a shield, orange on
-- armour, white on the hull; a missile bursts.
--
-- An effect runs between two bodies of the scene, by their ids, and is
-- placed afresh each frame from where they are then (Effects.Update).
-- Every piece is a square of light on a scenery object, turned to face
-- the eye by its vertex shader (fx_streak.jsl, fx_square.jsl).

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
}

Effects.looks = {
  ["laser.pulse"] = { kind = "beam", color = { 1.0, 0.22, 0.10 }, width = 5, life = 0.28 },
  ["laser.beam"] = { kind = "beam", color = { 0.30, 0.62, 1.0 }, width = 7, life = 0.85 },
  ["autocannon"] = { kind = "bolt", color = { 1.0, 0.80, 0.38 }, width = 3, length = 70, speed = 4200, burst = 4, gap = 0.06, blunt = 0 },
  ["artillery"] = { kind = "bolt", color = { 1.0, 0.56, 0.22 }, width = 7, length = 130, speed = 2600, burst = 1, gap = 0, blunt = 0.2 },
  ["blaster"] = { kind = "bolt", color = { 0.30, 1.0, 0.72 }, width = 11, length = 70, speed = 1900, burst = 1, gap = 0, blunt = 1 },
  ["railgun"] = { kind = "rail", color = { 0.55, 0.80, 1.0 }, width = 5, life = 0.55 },
  ["launcher"] = { kind = "missile", color = { 1.0, 0.62, 0.26 }, width = 7, length = 180 },
  ["miner"] = { kind = "beam", color = { 0.35, 1.0, 0.55 }, width = 5, life = 0.5, held = true },
  -- (what draws gas off a cloud: wider and paler, into the cloud's middle)
  ["miner.gas"] = { kind = "beam", color = { 0.80, 0.88, 1.0 }, width = 9, life = 0.5, held = true },
  -- What runs on another ship or a wreck for as long as it is on (the
  -- scene begins each beam again while the module runs): thin, and each
  -- its own colour.
  ["salvager"] = { kind = "beam", color = { 1.0, 0.70, 0.30 }, width = 3, life = 0.5, held = true },
  ["projector."] = { kind = "beam", color = { 0.90, 0.80, 0.30 }, width = 3, life = 0.5, held = true },
  ["disruptor."] = { kind = "beam", color = { 0.70, 0.40, 1.0 }, width = 3, life = 0.5, held = true },
  ["painter."] = { kind = "beam", color = { 1.0, 0.30, 0.30 }, width = 2, life = 0.5, held = true },
  ["damper."] = { kind = "beam", color = { 0.50, 0.60, 0.80 }, width = 2, life = 0.5, held = true },
  ["neutraliser."] = { kind = "beam", color = { 0.80, 0.60, 1.0 }, width = 4, life = 0.5, held = true },
  ["jammer."] = { kind = "beam", color = { 0.70, 0.90, 1.0 }, width = 2, life = 0.5, held = true },
  ["remote.shield"] = { kind = "beam", color = { 0.40, 0.75, 1.0 }, width = 4, life = 0.5, held = true },
  ["remote.armor"] = { kind = "beam", color = { 1.0, 0.75, 0.35 }, width = 4, life = 0.5, held = true },
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
  return { container = container, effects = {}, flashes = {}, burns = {}, frame = 0, pools = {}, made = {}, seed = 0 }
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
function Effects.Fire(fx: Fx, type: string, from: number, to: number, fromRadius: number, toRadius: number,
  outcome: string, flight: number, struck: string, now: number, origin: number?)
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
      struck = if outcome == "miss" then "" else struck, landed = false, pieces = {},
    }
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
      local finish = if effect.miss then to + effect.miss + d * (effect.toRadius * 6 + 200) else to - d * (effect.toRadius * 0.6)
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
        if t >= 1 then
          done = true
          if not effect.landed then
            land(fx, effect, finish, where, now)
          end
        else
          local head = start + (finish - start) * t
          local length = math.min((look.length or 30) * SIZE[effect.size], span * t)
          lay(piece, head - d * length, head, width)
          paint(piece, color, 1, age)
        end
      end
    end
    if done then
      for _, piece in effect.pieces do
        give(fx, piece)
      end
      table.remove(fx.effects, index)
    end
  end

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
end

return Effects
