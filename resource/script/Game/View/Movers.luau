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
--   vane      lies aft along the hull; fans out while its mode runs, a
--             lit strip on it while it is open
-- Every rate here is mine.

local Hull = require("@lt/Game/View/Hull")

local Movers = {}

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
      lean = mover.lean or 0, stretch = 1, yaw = 0, tilt = 0.45, open = 0,
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
      local mast = piece.head
      if mast then
        stand(mast, m.at + n * (m.headAt or 0), look, up, 1, piece.stretch)
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
      stand(piece.object, m.at, look, n)
      local glow = piece.glow
      if glow then
        stand(glow, m.at, look, n, if piece.open > 0.7 then 1 else 0.001)
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
    if m.kind == "antenna" then
      local lean = m.lean or 0
      table.insert(out, { model = m.model, at = m.at, look = d, up = n })
      local mast = m.head
      if mast then
        table.insert(out, { model = mast, at = m.at + n * (m.headAt or 0), look = d * math.cos(lean) - n * math.sin(lean),
          up = n * math.cos(lean) + d * math.sin(lean) })
      end
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
