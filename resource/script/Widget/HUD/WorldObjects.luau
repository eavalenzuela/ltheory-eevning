--!strict
-- Markers for the objects in view (Luau port of
-- Widget/HUD/WorldObjects.lts). G toggles them.

local Messages = require("@lt/Widget/Messages")
local WorldObject = require("@lt/Widget/HUD/WorldObject")

local WorldObjects = {}

local VIEW_DISTANCE = 1000          -- in object radii
local MINEABLE_VIEW_DISTANCE = 20000 -- asteroids are too many to mark system-wide

local function isMarked(object: Object, camera: Camera): boolean
  if object:HasComponentMineable() then
    return vector.magnitude(camera:GetPos() - object:GetPos()) < MINEABLE_VIEW_DISTANCE
  end
  return object:HasComponentInterior() or object:HasComponentNavigable()
    or object:HasComponentPilotable() or object:HasComponentResources() or object:IsCustom()
end

function WorldObjects.Create(player: Player): Widget
  local visible = true
  return Widget_Dynamic(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local markers = {}
      local camera = Camera_Get()
      if not visible or not camera then
        return markers
      end
      local objects = player:GetSystem():GetInteriorObjects()
      while objects:HasMore() do
        local object = objects:Get()
        if isMarked(object, camera) and Camera_CanSee(object, VIEW_DISTANCE * object:GetRadius()) then
          table.insert(markers, WorldObject.Create(player, object))
          if object:IsPlanet() then
            local children = object:GetChildren()
            while children:HasMore() do
              table.insert(markers, WorldObject.Create(player, children:Get()))
              children:Advance()
            end
          end
        end
        objects:Advance()
      end
      return markers
    end,
    PostPosition = function(_, w: Widget)
      local camera = Camera_Get()
      local children = w:GetChildren()
      while children:HasMore() do
        local marker = children:Get()
        local object = Messages.GetObject(marker)
        if object and camera then
          local projected = Camera_Project(camera, object:GetPos())
          local distance = vector.magnitude(camera:GetPos() - object:GetPos())
          local viewDistance = VIEW_DISTANCE * object:GetRadius()
          if projected.z > 0 and distance < viewDistance then
            local size = 32
            local framed = Position_Frame(projected)
            marker.alpha = 1 - distance / viewDistance
            marker.pos = vector.clamp(framed, vector.create(4, 4), w.size - vector.create(8, 8)) - vector.create(size / 2, size / 2)
            marker.size = vector.create(size, size)
          else
            marker.alpha = 0
            marker.pos = vector.create(0, 0)
            marker.size = vector.create(0, 0)
          end
        end
        children:Advance()
      end
    end,
    PreUpdate = function(_, w: Widget)
      if Key_Pressed(Key_G()) then
        visible = not visible
        w:Rebuild()
      end
    end,
  }))
end

return WorldObjects
