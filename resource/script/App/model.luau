--!strict
-- Model viewer (Luau port of App/model.lts): a random ship, a station, a
-- planet and 1024 asteroids. R generates new ones. Scroll to zoom,
-- right-drag to orbit, WASD / QE to move the focus. F3 shows frame
-- statistics.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Icons = require("@lt/Icons")
local Int = require("@lt/Int")
local SceneView = require("@lt/SceneView")

type Orbit = { setRadius: (radius: number) -> () }

-- Camera controls; returns the widget and a way to reset the zoom
local function controller(camera: Camera): (Widget, Orbit)
  local offset = vector.create(0, 0, 0)
  local radius, radiusT = 10, 10
  local pitch = -0.9 * math.pi / 2
  local yaw = 1.5
  local widget = Components.CaptureScroll(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 8, Colors.Primary, 1)
      if Key_Down(Key_F3()) then
        FrameInfo.Draw(w)
      end
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusScroll then
        radiusT *= 1 - 0.1 * Mouse_GetScrollDelta()
      end
      if Mouse_RightDown() then
        local delta = Cursor_GetDelta()
        yaw -= 0.01 * delta.x
        pitch += 0.01 * delta.y
      end
      local dt = FrameTimer_Get()
      radius += (radiusT - radius) * (1 - Float_ExpDecay(dt, 0.1))

      local look = vector.create(math.sin(pitch) * math.cos(yaw), math.cos(pitch), math.sin(pitch) * math.sin(yaw))
      camera:SetRelativePos(radius * look + offset)
      camera:SetRelativeLookAt(offset)
      camera:SetRigidity(8)

      local forward = -1 * radius * vector.normalize(vector.create(look.x, 0, look.z))
      local right = radius * vector.normalize(vector.cross(vector.create(0, 1, 0), forward))
      local up = radius * vector.create(0, 1, 0)
      if Key_Down(Key_W()) then offset += forward * dt end
      if Key_Down(Key_S()) then offset -= forward * dt end
      if Key_Down(Key_A()) then offset -= right * dt end
      if Key_Down(Key_D()) then offset += right * dt end
      if Key_Down(Key_Q()) then offset -= up * dt end
      if Key_Down(Key_E()) then offset += up * dt end
    end,
  }))
  local orbit: Orbit = {
    setRadius = function(r: number)
      radius, radiusT = r, r
      offset = vector.create(0, 0, 0)
    end,
  }
  return widget, orbit
end

return AppShell.Create(function(): Widget
  local camera = Camera_Create()
  camera:Push()
  local control, orbit = controller(camera)
  local ui = Widget_Layer(Compositor_None(), Mesh_Quad(), 1, control)
  local view = SceneView.Rendered(camera)
  local system = Object_System(vector.create(8.012, 8.012, 8.012), 31)
  local scene: { Object } = {}

  local function generate()
    local rng = RNG_MTG(Int_Random())
    for _, object in scene do
      Object_Delete(object)
    end
    scene = {}

    local value = 10 ^ Int_Random(5, 7)
    table.insert(scene, Item_ShipType(value, Int.Unsigned(Int_Random()), 1, 1, 1, 1, 1, 1):Instantiate())

    local station = Item_StationType(1000000, Int.Unsigned(Int_Random()), 1, 1, 1, 1):Instantiate()
    station:SetPos(vector.create(1000, 0, 0))
    table.insert(scene, station)

    local planet = Item_PlanetType(155):Instantiate()
    planet:SetScale(vector.create(1000, 1000, 1000))
    planet:SetPos(vector.create(-4000, 0, 0))
    table.insert(scene, planet)

    for _ = 1, 1024 do
      local asteroid = Object_Asteroid(Int.Unsigned(rng:Int()))
      local scale = 50 * rng:Exp()
      asteroid:SetScale(vector.create(scale, scale, scale))
      asteroid:SetPos(10000 * rng:Sphere())
      table.insert(scene, asteroid)
    end

    for _, object in scene do
      system:AddInterior(object)
    end
    camera:SetTarget(scene[1])
    orbit.setRadius(1.5 * scene[1]:GetRadius())
  end
  generate()

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view, ui }
    end,
    PreUpdate = function()
      if Key_Pressed(Key_R()) then
        generate()
      end
      system:Update(FrameTimer_Get())
    end,
  }))
end)
