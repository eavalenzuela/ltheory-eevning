--!strict
-- Moving parts of a hull (Game/View/Hull's Mover; the owner's, 2026-11-20):
-- each a thing of its own on the hull, posed every frame from what the
-- ship is doing. Only what is seen: the rules know nothing of them.
--
--   local pieces = Movers.Make(built.movers, add)      -- once
--   Movers.Animate(pieces, place, time, dt, state)     -- every frame
--
-- 'state' says what the ship is doing: in warp (or spooling for it),
-- scanning, aiming electronic warfare at something (the way to it, in
-- the hull's own axes), and running a mode (its name: "siege", "triage",
-- "core", "jump"; a mode part opens for its own). 'place' says where the
-- hull is: the point its model's origin is at, its axes, and how big one
-- of its model's units is.
--
-- How each kind moves:
--   antenna   its mast leans back by the ship's lean on a knuckle on its
--             foot, which stays flat on the hull; folds flat in warp;
--             while scanning stands upright and is drawn out half as long
--             again
--   dish      sweeps slowly at rest, quickly while scanning; points at
--   lattice   what electronic warfare is aimed at; parked flat facing
--             ahead in warp
--   radar     turns slowly at rest, fast while scanning; turned to what
--             electronic warfare is aimed at; parked facing ahead in warp
--   ring, drum, collar
--             turn steadily about the hull's length
--   spar      turns steadily about its face's upright
--   fin       a blade swept back on its root by its lean; folds back flat
--             along the hull in warp (a wing's blades closing into a stack)
--   vane      lies aft along the hull; fans out while its mode runs, a
--             lit strip on it while it is open
--   telescope stands straight out, drawn right back into the hull in
--             warp; its tip blinks red, then white, slowly
-- Every rate here is mine.

local Hull = require("@lt/Game/View/Hull")

local Movers = {}

-- How far a segmented antenna's sections are out: in warp, at rest and
-- scanning (0: nested all but a little, 1: drawn right out).
local EXTEND = { warp = 0, rest = 0.3, scan = 1 }

-- A telescope's lamps: the seconds of a blink (red, dark, white, dark),
-- and the parts of it each is lit (the owner's "slow blinking,
-- alternating between red and white on each antenna", 2026-11-25).
local BLINK = 4
local RED_FROM, RED_TO, WHITE_FROM, WHITE_TO = 0, 0.3, 0.5, 0.8

-- Where each of a telescope's sections stands up it, out so far (0: all
-- drawn into the hull, the lamp too; 1: right out), and where its tip is.
local function telescopeAt(sections: { { model: Model, length: number } }, extend: number, lamp: number): ({ number }, number)
  local at: { number } = {}
  local out = 0
  local top = 0
  for index, section in sections do
    local inside = -section.length - lamp * 2
    at[index] = inside + (out - inside) * extend
    top = at[index] + section.length
    out += section.length * 0.92
  end
  return at, top
end

-- Where each of a segmented antenna's sections stands up its mast, out so
-- far: each starts a little way up the one below, and further as it
-- slides out of it.
local function sectionsAt(sections: { { model: Model, length: number } }, extend: number): { number }
  local at: { number } = {}
  local y = 0
  for index, section in sections do
    at[index] = y
    y += section.length * (0.12 + 0.75 * extend)
  end
  return at
end

export type State = { warp: boolean, scan: boolean, aim: vector?, mode: string? }
export type Place = { at: vector, right: vector, up: vector, look: vector, unit: number }
export type Piece = {
  mover: Hull.Mover,
  object: Object,
  head: Object?,
  glow: Object?,
  -- (how far each eased thing is now)
  lean: number,
  stretch: number,
  yaw: number,
  tilt: number,
  open: number,
  -- (an antenna's: a whip's curl now, and which of its drawings is shown;
  -- a segmented one's sections and how far they are out, 0 to 1)
  curl: number,
  shown: number,
  parts: { Object },
  extend: number,
}

-- Make the objects of a hull's moving parts ('add' makes a thing of a
-- model, in the scene).
function Movers.Make(movers: { Hull.Mover }?, add: (model: Model) -> Object): { Piece }
  local pieces: { Piece } = {}
  local list: { Hull.Mover } = movers or {}
  for _, mover in list do
    table.insert(pieces, {
      mover = mover, object = add(mover.model), head = if mover.head then add(mover.head) else nil,
      glow = if mover.glow then add(mover.glow) else nil,
      lean = mover.lean or 0, stretch = 1, yaw = 0, tilt = 0.45, open = 0, curl = mover.curl or 0, shown = 1,
      parts = (function(): { Object }
        local made: { Object } = {}
        local sections: { { model: Model, length: number } } = mover.sections or {}
        for _, section in sections do
          table.insert(made, add(section.model))
        end
        return made
      end)(), extend = if mover.kind == "telescope" then 1 else EXTEND.rest,
    })
  end
  return pieces
end

-- (a way turned so far about another: Rodrigues' rule)
local function about(p: vector, k: vector, angle: number): vector
  local c, s = math.cos(angle), math.sin(angle)
  return p * c + vector.cross(k, p) * s + k * (vector.dot(k, p) * (1 - c))
end

-- (so far toward a figure, at most 'rate' a second)
local function toward(now: number, wanted: number, rate: number, dt: number): number
  return now + math.clamp(wanted - now, -rate * dt, rate * dt)
end

-- (an angle's nearest likeness to another, so easing goes the short way round)
local function near(angle: number, to: number): number
  return to + ((angle - to + math.pi) % (2 * math.pi) - math.pi)
end

function Movers.Animate(pieces: { Piece }, place: Place, time: number, dt: number, state: State)
  local function world(p: vector): vector
    return place.right * p.x + place.up * p.y + place.look * p.z
  end
  local function stand(object: Object, at: vector, look: vector, up: vector, size: number?, long: number?)
    object:SetPos(place.at + world(at) * place.unit)
    Object_SetAxes(object, world(look), world(up))
    local s = place.unit * (size or 1)
    object:SetScale(vector.create(s, s * (long or 1), s))
  end
  for _, piece in pieces do
    local m = piece.mover
    local kind = m.kind
    local n, d = m.up, m.fore
    if kind == "antenna" then
      -- (lean: its own, flat in warp, upright scanning; drawn out scanning)
      local wanted = if state.warp then math.pi / 2 * 0.97 elseif state.scan then 0 else (m.lean or 0)
      piece.lean = toward(piece.lean, wanted, 1.4, dt)
      piece.stretch = toward(piece.stretch, if state.scan and not state.warp then 1.5 else 1, 0.9, dt)
      local up = n * math.cos(piece.lean) + d * math.sin(piece.lean)
      local look = d * math.cos(piece.lean) - n * math.sin(piece.lean)
      -- (its foot stays flat on the hull; its mast leans on the knuckle)
      stand(piece.object, m.at, d, n)
      local hinge = m.at + n * (m.headAt or 0)
      local mast = piece.head
      local heads, sections = m.heads, m.sections
      if heads and mast then
        -- (a whip leans by its curl alone: back along the hull in warp, straight up scanning)
        piece.curl = toward(piece.curl, if state.warp then 1 elseif state.scan then 0 else (m.curl or 0), 0.7, dt)
        local step = math.clamp(math.floor(piece.curl * (#heads - 1) + 0.5) + 1, 1, #heads)
        if step ~= piece.shown then
          piece.shown = step
          Object_SetRenderable(mast, heads[step])
        end
        -- (and it leans back on its knuckle by the ship's lean as the other antennas do, further over in warp, upright
        -- scanning: the owner's, of whips that stood up while the rest leaned back)
        piece.lean = toward(piece.lean, if state.warp then math.pi / 2 * 0.85 elseif state.scan then 0 else (m.lean or 0), 1.2, dt)
        local over = piece.lean
        stand(mast, hinge, d * math.cos(over) - n * math.sin(over), n * math.cos(over) + d * math.sin(over))
      elseif sections then
        -- (its sections slide out of one another: drawn right out scanning, nested in warp)
        piece.extend = toward(piece.extend, if state.warp then EXTEND.warp elseif state.scan then EXTEND.scan else EXTEND.rest, 0.6, dt)
        local at = sectionsAt(sections, piece.extend)
        for index, part in piece.parts do
          stand(part, hinge + up * at[index], look, up)
        end
      elseif mast then
        stand(mast, hinge, look, up, 1, piece.stretch)
      end
    elseif kind == "telescope" then
      piece.extend = toward(piece.extend, if state.warp then 0 else 1, 0.7, dt)
      -- (its foot is not drawn: the rod comes straight out of the hull)
      stand(piece.object, m.at, d, n, 0.001)
      local lamp = m.headAt or 0
      local sections: { { model: Model, length: number } } = m.sections or {}
      local at, top = telescopeAt(sections, piece.extend, lamp)
      -- (what is drawn right into the hull is not drawn at all: in warp
      -- the eye's depth is too coarse for a thing three metres across,
      -- and it showed through)
      for index, part in piece.parts do
        stand(part, m.at + n * at[index], d, n, if at[index] + sections[index].length > 0 then 1 else 0.001)
      end
      local t = (time * m.pace / BLINK + m.phase) % 1
      local tip = m.at + n * (top + lamp * 0.7)
      local out = top + lamp * 1.7 > 0
      local red, white = piece.head, piece.glow
      if red then
        stand(red, tip, d, n, if out and t >= RED_FROM and t < RED_TO then 1 else 0.001)
      end
      if white then
        stand(white, tip, d, n, if out and t >= WHITE_FROM and t < WHITE_TO then 1 else 0.001)
      end
    elseif kind == "dish" or kind == "lattice" or kind == "radar" then
      stand(piece.object, m.at, d, n)
      local side = vector.cross(n, d)
      local pace, phase = m.pace, m.phase
      local yaw, tilt, rate = piece.yaw, piece.tilt, 1.5
      if state.warp then
        yaw, tilt = toward(piece.yaw, near(0, piece.yaw), 2, dt), toward(piece.tilt, 0, 1, dt)
      elseif state.aim then
        local w = vector.normalize(state.aim)
        local wantYaw = math.atan2(vector.dot(w, side), vector.dot(w, d))
        local wantTilt = if kind == "radar" then 0 else math.clamp(math.asin(math.clamp(vector.dot(w, n), -1, 1)), -0.25, 1.4)
        yaw, tilt = toward(piece.yaw, near(wantYaw, piece.yaw), 2, dt), toward(piece.tilt, wantTilt, 1, dt)
      elseif kind == "radar" then
        -- (round and round: slowly, or fast while scanning)
        yaw, tilt = piece.yaw + (if state.scan then 4 else 0.6) * pace * dt, toward(piece.tilt, 0, 1, dt)
      else
        local fast = state.scan
        rate = if fast then 3 else 1.5
        local wantYaw = if fast then 1.3 * math.sin(time * 1.7 * pace + phase) else 0.9 * math.sin(time * 0.35 * pace + phase)
        local wantTilt = if fast then 0.5 + 0.35 * math.sin(time * 1.2 * pace + phase) else 0.45 + 0.15 * math.sin(time * 0.25 * pace + phase)
        yaw, tilt = toward(piece.yaw, near(wantYaw, piece.yaw), rate, dt), toward(piece.tilt, wantTilt, rate * 0.6, dt)
      end
      piece.yaw, piece.tilt = yaw, tilt
      local head = piece.head
      if head then
        local facing = d * math.cos(yaw) + side * math.sin(yaw)
        local look = facing * math.cos(tilt) + n * math.sin(tilt)
        local up = n * math.cos(tilt) - facing * math.sin(tilt)
        stand(head, m.at + n * (m.headAt or 0), look, up)
      end
    elseif kind == "fin" then
      -- (a blade swept back by its lean on its root, folded back flat along the hull in warp: a wing's blades so close
      -- into one stack)
      -- (a stabiliser stays as it is: the owner's, "make the stabilizers not fold in warp")
      local folds = state.warp and m.design ~= "stabiliser"
      piece.lean = toward(piece.lean, if folds then math.pi / 2 * 0.96 else (m.lean or 0), 1.2, dt)
      stand(piece.object, m.at, d, n)
      local blade = piece.head
      if blade then
        stand(blade, m.at + n * (m.headAt or 0), d * math.cos(piece.lean) - n * math.sin(piece.lean),
          n * math.cos(piece.lean) + d * math.sin(piece.lean))
      end
    elseif kind == "ring" or kind == "drum" or kind == "collar" then
      local angle = time * (m.rate or 0) + m.phase
      stand(piece.object, m.at, d, about(n, d, angle))
    elseif kind == "spar" then
      local angle = time * (m.rate or 0) + m.phase
      stand(piece.object, m.at, about(d, n, angle), n)
    elseif kind == "vane" then
      -- (open while its mode runs: eased, slow at either end)
      piece.open = toward(piece.open, if state.mode ~= nil and state.mode == m.mode then 1 else 0, 0.5, dt)
      local t = piece.open * piece.open * (3 - 2 * piece.open)
      local outboard = m.out or vector.create(if m.at.x >= 0 then 1 else -1, 0, 0)
      local swing = t * (m.open or 1)
      local look = d * math.cos(swing) + outboard * math.sin(swing)
      -- (its hinge post fixed on the hull's face, and the fin turning on its end)
      local pivot = m.at + outboard * (m.headAt or 0)
      local fin = piece.head
      if fin then
        stand(piece.object, m.at, d, n)
        stand(fin, pivot, look, n)
      else
        stand(piece.object, pivot, look, n)
      end
      local glow = piece.glow
      if glow then
        stand(glow, pivot, look, n, if piece.open > 0.7 then 1 else 0.001)
      end
    end
  end
end

-- A hull's moving parts at rest, for a still picture of it (the fitting
-- and information windows): each model, and where it stands and which
-- way it looks, in the hull model's own units and axes.
export type Rest = { model: Model, at: vector, look: vector, up: vector }
function Movers.Rest(movers: { Hull.Mover }?): { Rest }
  local out: { Rest } = {}
  local list: { Hull.Mover } = movers or {}
  for _, m in list do
    local n, d = m.up, m.fore
    if m.kind == "antenna" or m.kind == "fin" then
      local lean = m.lean or 0
      table.insert(out, { model = m.model, at = m.at, look = d, up = n })
      local hinge = m.at + n * (m.headAt or 0)
      local look, up = d * math.cos(lean) - n * math.sin(lean), n * math.cos(lean) + d * math.sin(lean)
      local heads, sections = m.heads, m.sections
      if heads then
        local step = math.clamp(math.floor((m.curl or 0) * (#heads - 1) + 0.5) + 1, 1, #heads)
        table.insert(out, { model = heads[step], at = hinge, look = look, up = up })
      elseif sections then
        local at = sectionsAt(sections, EXTEND.rest)
        for index, section in sections do
          table.insert(out, { model = section.model, at = hinge + up * at[index], look = look, up = up })
        end
      elseif m.head then
        table.insert(out, { model = m.head :: Model, at = hinge, look = look, up = up })
      end
    elseif m.kind == "telescope" then
      -- (right out, its red lamp lit; its foot not drawn)
      local lamp = m.headAt or 0
      local sections: { { model: Model, length: number } } = m.sections or {}
      local at, top = telescopeAt(sections, 1, lamp)
      for index, section in sections do
        table.insert(out, { model = section.model, at = m.at + n * at[index], look = d, up = n })
      end
      if m.head then
        table.insert(out, { model = m.head :: Model, at = m.at + n * (top + lamp * 0.7), look = d, up = n })
      end
    elseif m.kind == "vane" and m.head then
      -- (its post on the hull, and the fin closed on its end)
      table.insert(out, { model = m.model, at = m.at, look = d, up = n })
      table.insert(out, { model = m.head :: Model, at = m.at + (m.out or vector.create(1, 0, 0)) * (m.headAt or 0), look = d, up = n })
    else
      table.insert(out, { model = m.model, at = m.at, look = d, up = n })
      local head = m.head
      if head then
        local tilt = if m.kind == "radar" then 0 else 0.45
        table.insert(out, { model = head, at = m.at + n * (m.headAt or 0), look = d * math.cos(tilt) + n * math.sin(tilt),
          up = n * math.cos(tilt) - d * math.sin(tilt) })
      end
    end
  end
  return out
end

return Movers
