--!strict
-- The rail between two warp nodes: an invisible object that streams
-- particles from one node to the other (Luau port of Object/WarpRail.lts).

local WarpRail = {}

local COLOR = vector.create(1.0, 1.5, 2.0)

function WarpRail.Create(node1: Object, node2: Object): Object
  local rng = RNG_MTG(512)
  local self = Object_Custom({
    Update = function(_, rail: Object): boolean
      if Camera_CanSee(rail, 40000) then
        local ps = ParticleSystem_Get()
        local particle = Particle_Firefly()
        local p1, p2 = node1:GetPos(), node2:GetPos()
        local look = vector.normalize(p2 - p1)
        for _ = 1, 16 do
          local dir = rng:Float(-1, 1) * 50 * look
          local energy = 1 + 0.5 * rng:Exp() ^ 2
          ps:Add(particle, p1 + (p2 - p1) * rng:Float(), energy * dir, 50 * rng:Float(), rng:Float(1, 5), energy * COLOR)
        end
      end
      return true
    end,
  })

  local p1, p2 = node1:GetPos(), node2:GetPos()
  self:SetScale(vector.create(1, 1, 0.5 * vector.magnitude(p1 - p2)))
  self:SetLook(vector.normalize(p1 - p2))
  self:SetPos(0.5 * (p1 + p2))

  node1:Send(MessageLink(node2))
  node2:Send(MessageLink(node1))
  return self
end

return WarpRail
