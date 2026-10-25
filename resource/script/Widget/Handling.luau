--!strict
-- Flight controls for the piloted ship (Luau port of Widget/Handling.lts).
--
-- Two parts: a script on the ship that steers it and drives the chase
-- camera every frame, and a full-screen input widget that turns the mouse
-- and keys into steering, thrust, aim and fire. Space toggles mouse
-- steering, WASD thrusts, Q/E roll, Tab boosts, the right button fires,
-- the wheel zooms the camera, +/- cycle which turret the camera follows.
-- While the ship runs a task (docking, approaching a rock) the controls
-- stand aside; thrusting takes back control.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")

local Handling = {}

local ROTATION_SPEED = 0.03

local function lerp(a: vector, b: vector, t: number): vector
  return a + (b - a) * t
end

local function decay(dt: number, rate: number): number
  return 1 - Float_ExpDecay(dt, rate)
end

-- Whether 'module' (a socket's turret) holds a transfer unit
local function holdsTransferUnit(module: Object): boolean
  local children = module:GetChildren()
  while children:HasMore() do
    if children:Get():IsTransferUnit() then
      return true
    end
    children:Advance()
  end
  return false
end

------------------------------------------------------------- Ship script

type ShipScript = {
  thrust: vector,
  look: vector,
  lookTarget: vector,
  up: vector,
  upTarget: vector,
  noise: vector,
  noiseTarget: vector,
  targetPos: vector,
  targetObject: Object?,
  distance: number,
  distanceTarget: number,
  boosting: boolean,
  firing: boolean,
  rng: RNG,
  targetIndex: number,
  Rotate: (self: ShipScript, rotation: vector) -> (),
  Thrust: (self: ShipScript, dir: vector) -> (),
  Update: (self: ShipScript, object: Object) -> boolean,
}

local function newShipScript(): ShipScript
  local script = {
    thrust = vector.create(0, 0, 0),
    look = vector.create(0, 0, 1),
    lookTarget = vector.create(0, 0, 1),
    up = vector.create(0, 1, 0),
    upTarget = vector.create(0, 1, 0),
    noise = vector.create(0, 0, 0),
    noiseTarget = vector.create(0, 0, 0),
    targetPos = vector.create(0, 0, 0),
    targetObject = nil :: Object?,
    distance = 2,
    distanceTarget = 2,
    boosting = false,
    firing = false,
    rng = RNG_MTG(0),
    targetIndex = 0,
  }

  -- Turn the camera's target orientation by 'rotation' (pitch, yaw, roll)
  function script.Rotate(self: ShipScript, rotation: vector)
    local transform = Transform_LookUp(vector.create(0, 0, 0), self.lookTarget, self.upTarget)
    transform:Rotate(ROTATION_SPEED * rotation)
    self.lookTarget = transform.look
    self.upTarget = transform.up
  end

  -- Thrust along 'dir' (right, up, forward) relative to the view
  function script.Thrust(self: ShipScript, dir: vector)
    local transform = Transform_LookUp(vector.create(0, 0, 0), self.look, self.up)
    self.thrust = transform.right * dir.x + transform.up * dir.y + transform.look * dir.z
  end

  function script.Update(self: ShipScript, object: Object): boolean
    local dt = FrameTimer_Get()

    -- The camera follows the ship, or its targetIndex-th turret
    local target = object
    local sockets = object:GetSockets()
    local turrets = 0
    while sockets:HasMore() and turrets < self.targetIndex do
      local socket = sockets:Get()
      if socket and socket:IsTurret() then
        target = socket
        turrets += 1
      end
      sockets:Advance()
    end

    self.distanceTarget = math.clamp(self.distanceTarget - 0.5 * Mouse_GetScrollDelta(), 1, 8)
    self.distance += (self.distanceTarget - self.distance) * decay(dt, 0.1)
    self.noise = lerp(self.noise, self.noiseTarget, decay(dt, 2))
    self.up = vector.normalize(lerp(self.up, self.upTarget, decay(dt, 0.05)))
    self.look = vector.normalize(lerp(self.look, self.lookTarget, decay(dt, 0.5)))

    -- Autopilot: while the ship runs a task, leave flying to the task;
    -- manual thrust takes back control
    local autopilot = object:HasTask()
    if autopilot and vector.magnitude(self.thrust) > 0 then
      object:ClearTasks()
      autopilot = false
    end
    if autopilot then
      self.look = object:GetLook()
      self.lookTarget = self.look
    else
      object:Broadcast(MessageThrustLinear(self.thrust))
      object:SetLook(lerp(object:GetLook(), self.look, decay(dt, 0.5)))
    end

    -- Camera shake grows with speed
    local shake = 1 - Float_ExpDecay(object:GetSpeed(), 1000)
    self.noiseTarget = 0.1 * shake * self.rng:Sphere()

    local cam = Camera_Get()
    cam:SetTarget(target)
    local radius = self.distance * target:GetRadius()
    local pos = target:GetPos()
    local lookAt
    if self.distance < 1.5 then
      pos += radius * self.look
      lookAt = pos + 1000 * self.look + self.noise
    else
      pos += 0.2 * radius * self.up - radius * self.look
      lookAt = target:GetPos() + 1000 * self.look + self.noise
    end
    cam:SetRelativePos(pos)
    cam:SetRelativeUp(self.up)
    cam:SetRelativeLookAt(lookAt)
    cam:SetRigidity(1000)

    -- Aim weapons at the cursor; transfer units are aimed by whatever is
    -- using them (e.g. mining)
    if target == object then
      local mounts = object:GetSockets()
      while mounts:HasMore() do
        local module = mounts:Get()
        if module and not holdsTransferUnit(module) then
          module:Broadcast(MessageTargetPosition(self.targetPos))
        end
        mounts:Advance()
      end
    else
      target:Broadcast(MessageTargetPosition(self.targetPos))
    end

    if self.boosting then
      object:Broadcast(MessageBoost())
    end
    if self.firing then
      target:Broadcast(MessageFire())
    end

    if Key_Pressed(Key_Equal()) then
      self.targetIndex += 1
    end
    if Key_Pressed(Key_Dash()) then
      self.targetIndex -= 1
    end
    return true
  end

  return script
end

-- One script per ship, however often the HUD is rebuilt
local shipScripts: { [number]: ShipScript } = {}

local function scriptFor(object: Object): ShipScript
  local id = object:GetID()
  local script = shipScripts[id]
  if not script then
    script = newShipScript()
    shipScripts[id] = script
    object:AddScript(script)
  end
  return script
end

------------------------------------------------------------ Input widget

-- Projectile speed of the ship's weapons, for lead indicators
local function weaponSpeed(object: Object): number
  local speed = 1000
  local sockets = object:GetSockets()
  while sockets:HasMore() do
    local socket = sockets:Get()
    if socket and socket:IsTurret() and socket:GetSockets():HasMore() then
      local mount = socket:GetSockets():Get()
      local mountType = mount and mount:GetSupertype()
      if mountType and mountType:HasSpeed() then
        speed = mountType:GetSpeed()
      end
    end
    sockets:Advance()
  end
  return speed
end

function Handling.Create(object: Object): Widget
  local script = scriptFor(object)
  local active = false
  local hasTarget = false
  local targetObject: Object? = nil
  local targetPos = vector.create(0, 0, 0)
  local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)
  Camera_Get():SetTarget(object)

  local handler = Widget_Luau(Widget_Create(), {
    -- Lead indicators: where to aim to hit each target; hovering one aims
    -- at it
    PostDraw = function(_, w: Widget)
      hasTarget = false
      targetObject = nil
      local cam = Camera_Get()
      if not cam then
        return
      end
      local cursor = Cursor_Get()
      local speed = weaponSpeed(object)
      local targets = object:GetTargets()
      while targets:HasMore() do
        local target = targets:Get()
        local impact = GetImpact(object:GetPos(), target:GetPos(), object:GetVelocity(), target:GetVelocity(), speed)
        if impact.t > 0 then
          local projected = cam:Project(impact.position)
          if projected.z > 0 then
            local screen = Position_Frame(projected)
            Icon_Draw(Icons.Cancel(), screen, 8, Colors.Hostile, 1)
            local d = cursor - screen
            if math.abs(d.x) <= 32 and math.abs(d.y) <= 32 then
              Glyph_Draw(ring, screen, 16, Colors.Secondary, 1)
              hasTarget = true
              targetObject = target
              targetPos = impact.position
            end
          end
        end
        targets:Advance()
      end
    end,

    PostUpdate = function(_, w: Widget)
      w.focusKey = true
      w.focusMouse = true
      w.focusScroll = true

      if Key_Pressed(Key_Space()) then
        active = not active
      end

      if active then
        local delta = 2 * (Mouse_GetPos() - w:Center()) / w.size
        local roll = 0
        if Key_Down(Key_Q()) then roll += 2 end
        if Key_Down(Key_E()) then roll -= 2 end
        script:Rotate(vector.create(delta.y, delta.x, roll))
      end

      local thrust = vector.create(0, 0, 0)
      if Key_Down(Key_A()) then thrust = vector.create(-1, thrust.y, thrust.z) end
      if Key_Down(Key_D()) then thrust = vector.create(1, thrust.y, thrust.z) end
      if Key_Down(Key_W()) then thrust = vector.create(thrust.x, thrust.y, 1) end
      if Key_Down(Key_S()) then thrust = vector.create(thrust.x, thrust.y, -1) end
      script:Thrust(thrust)

      if hasTarget then
        script.targetObject = targetObject
        script.targetPos = targetPos
      else
        script.targetObject = nil
        script.targetPos = Camera_Get():GetRay(Mouse_GetPos()):GetPoint(1000)
      end

      script.boosting = Key_Down(Key_Tab())
      script.firing = Mouse_RightDown()
    end,
  })
  return Components.Expand(handler)
end

return Handling
