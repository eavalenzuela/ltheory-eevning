--!strict
-- Fireworks (Luau port of Object/Firework.lts): a shell rises from an
-- object, bursts into colored sparks, which burst once more.

local Firework = {}

local function toVector(color: Color): vector
  return vector.create(color.x, color.y, color.z)
end

local function spawn(color: vector, life: number, generation: number, rng: RNG): Object
  local age = 0
  local script = {}
  function script.Update(_, self: Object): boolean
    local dt = FrameTimer_Get()
    self:ApplyForce(vector.create(0, -200, 0))
    age += dt

    local particles = ParticleSystem_Get()
    local firefly = Particle_Firefly()
    local opacity = (1 - age / life) ^ 4
    local pos = self:GetPos()
    for i = 0, 15 do
      particles:Add(firefly, pos - (i / 16) * dt * self:GetVelocity(), vector.create(0, 0, 0),
        100 * rng:Float(), rng:Float(1, 2), opacity * (vector.create(1, 1, 1) + 4 * color))
    end

    if age <= life then
      return true
    end

    if generation < 2 then
      local hsl = toVector(ToHSL(color))
      local count = rng:Int(10, 20)
      for i = 1, count do
        local hue = (hsl.x + 0.1 * rng:Float(-1, 1)) % 1
        local sparkColor = toVector(ToRGB(vector.create(hue, hsl.y, hsl.z)))
        local child = spawn(sparkColor, 5 * rng:Float(), generation + 1, RNG_MTG(rng:Int() % 2147483648))
        child:SetPos(self:GetPos())
        child:ApplyForce(20000 * (1 + rng:Exp()) * rng:Direction())
        self:GetContainer():AddInterior(child)
        if i == 1 then
          local sound = Sound_Play("explosion/altsmall3.ogg", child, vector.create(0, 0, 0), 1, 1)
          sound:SetPitch(rng:Float(0.25, 0.5))
        end
      end
    end
    self:Delete()
    return false
  end

  local object = Object_Custom(script)
  object:AddChild(Object_Light(5 * color, 1, false))
  return object
end

-- Launch a firework from above 'source'
function Firework.ShootFrom(source: Object): Object
  local color = toVector(ToRGB(vector.create(Float_Random(), 0.7, 0.5)))
  local shell = spawn(color, 2, 0, RNG_MTG(Int_Random() % 2147483648))
  shell:SetPos(source:GetPos() + source:GetRadius() * vector.create(0, 1, 0))
  shell:ApplyForce(vector.create(0, 100000, 0))
  source:GetContainer():AddInterior(shell)
  return shell
end

return Firework
