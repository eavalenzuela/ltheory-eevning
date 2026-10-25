--!strict
-- A radar of nearby objects relative to the camera (Luau port of
-- Widget/HUD/Minimap.lts); click to open the system map.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Messages = require("@lt/Widget/Messages")

local Minimap = {}

local Map = require("@lt/Widget/Map")

local VIEW_DISTANCE = 1000   -- in object radii
local DISTANCE_SCALE = 5000

local function shown(object: Object): boolean
  return object:HasComponentInterior() or object:HasComponentNavigable()
    or object:HasComponentPilotable() or object:HasComponentResources() or object:IsCustom()
end

function Minimap.Create(player: Player): Widget
  local time = 0
  local map: Widget? = nil
  local dot = Glyph_Circle(0, 1, 1, 1)
  local ring = Glyph_Arc(0, 1, 0.001, 1, 1, 0, 1)
  local minimap = Widget_Create()
  Widget_Luau(minimap, {
    GetName = function()
      return "Mini-Map"
    end,
    PreDraw = function(_, w: Widget)
      local color = if w.focusMouse then Colors.Secondary else Colors.Primary
      local cam = Camera_Get()
      if cam then
        local pos, look, right = cam:GetPos(), cam:GetLook(), cam:GetRight()
        local ship = player:GetPiloting()
        local objects = player:GetSystem():GetInteriorObjects()
        while objects:HasMore() do
          local object = objects:Get()
          if shown(object) and Camera_CanSee(object, VIEW_DISTANCE * object:GetRadius()) then
            local to = object:GetPos() - pos
            local dir = vector.create(vector.dot(to, right), -vector.dot(to, look))
            local length = vector.magnitude(dir)
            if length > 0 then
              dir = (1 - Float_ExpDecay(length, DISTANCE_SCALE)) * (dir / length)
            end
            dir = vector.create(0.5, 0.5) + 0.5 * dir
            local c = if ship:HasTarget(object) then Colors.Secondary else Colors.Primary
            Glyph_Draw(dot, w.pos + dir * w.size, 16, 2 * c, 1)
          end
          objects:Advance()
        end
      end

      local radius = 0.5 * math.min(w.size.x, w.size.y)
      for i = 0, 7 do
        local r = (i + 1) / 9
        local pulse = math.abs(math.sin(time - 2 * math.pi * r)) ^ 8
        Glyph_Draw(ring, w:Center(), r * radius, color, 0.2 * pulse)
      end
      Glyph_Draw(ring, w:Center(), radius, color, 0.5)
      for _, edge in { w:LeftCenter(), w:RightCenter(), w:TopCenter(), w:BottomCenter() } do
        Glyph_Draw(Glyph_Line(edge, w:Center(), 1, 1), 0, 1, color, 0.1)
      end
    end,
    PostUpdate = function()
      time += FrameTimer_Get()
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Click" then
        if map and map:HasParent() then
          map:Delete()
          map = nil
        else
          local window = Map.Create(player, player:GetPiloting():GetSystem())
          map = window
          w:SendUp(Messages.AddWidget(window))
        end
      end
    end,
  })
  return Components.CaptureMouse(Components.Clickable({ type = "Click" }, minimap, minimap))
end

return Minimap
