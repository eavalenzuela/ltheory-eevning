--!strict
-- Warp nodes and the rails between them (Luau port of
-- Object/WarpNode.lts). The engine calls Init for each node, and
-- EjectPassenger / UpdatePassenger for ships riding the rail; systems
-- lay out rails with BuildRail and BuildRailRadial.

local WarpRail = require("@lt/Object/WarpRail")

local WarpNode = {}

local SCALE = vector.create(100, 100, 100)
local SPACING = 15000

local function mix(a: vector, b: vector, t: number): vector
  return a + (b - a) * t
end

local function newNode(p: vector): Object
  local node = Object_WarpNode()
  node:SetPos(p)
  node:SetScale(SCALE)
  return node
end

-- Add a node to the system, joined by a rail to the previous one
local function link(system: Object, node: Object, previous: Object?)
  system:AddInterior(node)
  if previous then
    system:AddInterior(WarpRail.Create(node, previous))
  end
end

-- A straight rail from p1 to p2
function WarpNode.BuildRail(system: Object, p1: vector, p2: vector)
  local nodes = math.max(2, math.ceil(vector.magnitude(p1 - p2) / SPACING))
  local previous: Object? = nil
  for i = 0, nodes - 1 do
    local node = newNode(mix(p1, p2, i / (nodes - 1)))
    node:SetLook(vector.normalize(p2 - p1))
    link(system, node, previous)
    previous = node
  end
end

-- An arc around 'center' from angle1 to angle2 (in turns)
function WarpNode.BuildRailRadial(system: Object, center: vector, radius: number, angle1: number, angle2: number)
  local nodes = math.max(2, math.ceil(2 * math.pi * radius * math.abs(angle2 - angle1) / SPACING))
  local previous: Object? = nil
  for i = 0, nodes - 1 do
    local t = i / (nodes - 1)
    local angle = 2 * math.pi * (angle1 + (angle2 - angle1) * t)
    local node = newNode(center + radius * vector.create(math.cos(angle), 0, math.sin(angle)))
    link(system, node, previous)
    previous = node
  end
end

function WarpNode.EjectPassenger(object: Object)
  Sound_Play("warpnode/exit.wav", object, vector.create(0, 0, 0), 0.2, 0.25 * math.sqrt(object:GetRadius()))
  if not Camera_CanSee(object, 100000) then
    return
  end
  local ps = ParticleSystem_Get()
  if not ps then
    return
  end
  local particle = Particle_Firefly()
  local p = object:GetPos()
  local rng = RNG_MTG(Int_Random())
  for _ = 1, 512 do
    local angle = rng:Angle()
    local v = 2 * object:GetRadius() * (math.cos(angle) * object:GetRight() + math.sin(angle) * object:GetUp())
    local s = Float_Saturate(0.1 * rng:Exp() ^ 2)
    ps:Add(particle, p,
      Float_ExpDecay(s, 0.1) * v + 0.5 * s * object:GetVelocity(),
      0.15 * rng:Exp() * object:GetRadius(),
      rng:Float(1, 2),
      4 * mix(vector.create(1.0, 2.5, 4.0), vector.create(2.0, 3.0, 4.0), rng:Float()))
  end
end

function WarpNode.UpdatePassenger(object: Object)
  if not Camera_CanSee(object, 40000) then
    return
  end
  local ps = ParticleSystem_Get()
  local particle = Particle_Firefly()
  local p = object:GetPos()
  local rng = RNG_MTG(Int_Random())
  for _ = 1, 8 do
    ps:Add(particle, p, 0.25 * rng:Float() * object:GetVelocity(), 40 * rng:Float(), rng:Float(1, 2),
      2 * vector.create(1.0, 2.5, 4.0))
  end
end

-- Droning sounds and a pulsing particle halo
function WarpNode.Init(object: Object)
  local rng = RNG_MTG(Int_Random())
  local drones: { Sound }? = nil
  local t = 10 * Float_Random()
  object:AddScript({
    Update = function(_, self: Object): boolean
      t += FrameTimer_Get()
      if not drones then
        local zero = vector.create(0, 0, 0)
        local sounds = {
          Sound_PlayLooped("warpnode/drone3.ogg", self, zero, 0.9, 5.0),
          Sound_PlayLooped("warpnode/drone1.ogg", self, zero, 0.5, 2.0),
          Sound_PlayLooped("warpnode/drone2.ogg", self, zero, 0.5, 5.0),
        }
        for _, sound in sounds do
          sound:RandomizePosition()
        end
        drones = sounds
      end

      if Camera_CanSee(self, 40000) then
        local ps = ParticleSystem_Get()
        local particle = Particle_Firefly()
        local scale = 0.05 * self:GetRadius()
        local mult = 0.5 + 0.5 * math.sin(t)
        for _ = 1, 64 do
          local dir = rng:Direction()
          local energy = mult * 32 * rng:Exp() ^ 2
          ps:Add(particle,
            self:GetPos() + (1 + 0.3 * energy) * 0.6 * self:GetRadius() * dir,
            scale * (rng:Sphere() - energy * dir),
            1.5 * scale * rng:Exp(),
            rng:Float(2, 3),
            2 * mix(vector.create(1.0, 2.5, 4.0), vector.create(2.0, 1.4, 1.0), 1 - Float_ExpDecay(energy, 2)))
        end
      end
      return true
    end,
  })
end

return WarpNode
