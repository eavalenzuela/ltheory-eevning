--!strict
-- A box-plate model editor (Luau port of Widget/ModelEditor.lts): pieces
-- seen from above, with X / Y / Z symmetry toggles. Tab switches to a 3D
-- preview of the plate mesh and back.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Editor = require("@lt/Widget/ModelEditor/Editor")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Preview = require("@lt/Widget/ModelEditor/Preview")
local ToggleButton = require("@lt/Widget/ToggleButton")
local Types = require("@lt/Widget/ModelEditor/Types")
local Widgets = require("@lt/Widgets")

local ModelEditor = {}

local function v3(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

local function startingModel(): Types.ModelT
  local pm = Model_Create()
  pm:Add(Mesh_BoxRounded(16, 0.125), Material_Metal())
  local pieces: { Types.Piece } = {}
  local function piece(center: vector, scale: vector, bevel: number)
    table.insert(pieces, { center = center, scale = scale, bevel = bevel, model = pm })
  end
  piece(v3(0.0, 0, 0.25), v3(0.25, 0.1, 0.5), 0.125)
  piece(v3(0.15, 0, 0.2), v3(0.1, 0.1, 0.8), 0.125)
  piece(v3(0, 0, 0), v3(0.1, 0.1, 1.7), 0.125)
  piece(v3(0, 0, 0.65), v3(0.15, 0.05, 0.05), 0.25)
  piece(v3(0, 0, 0.75), v3(0.15, 0.05, 0.05), 0.25)
  piece(v3(0.125, 0, -0.65), v3(0.2, 0.01, 0.15), 0.125)
  piece(v3(0, 0, -0.6), v3(0.2, 0.125, 0.6), 0.25)
  piece(v3(0.25, 0, -0.6), v3(0.1, 0.05, 0.3), 0.25)
  for i = 0, 7 do
    local t = i / 4
    piece(v3(0.225, 0, 0.5 - 0.6 * t), v3(0.0625, 0.125, 0.125), 0.25)
    piece(v3(0.10, 0, 0.5 - 0.6 * t), v3(0.125, 0.25, 0.125), 0.25)
  end
  return { pieces = pieces }
end

-- The plate mesh the pieces describe, with the mirrored copies
local function build(model: Types.ModelT, options: Types.Options): Renderable
  local pm = PlateMesh_Create(16)
  local scale = 15
  local zero = vector.create(0, 0, 0)
  for _, piece in model.pieces do
    local size = 0.5 * scale * piece.scale
    local function add(mirror: vector)
      pm:Add(scale * mirror * piece.center, size, zero, piece.bevel)
    end
    local x, y, z = options.symmetryX, options.symmetryY, options.symmetryZ
    add(v3(1, 1, 1))
    if x and math.abs(piece.center.x) > 0 then add(v3(-1, 1, 1)) end
    if y and math.abs(piece.center.y) > 0 then add(v3(1, -1, 1)) end
    if z and math.abs(piece.center.z) > 0 then add(v3(1, 1, -1)) end
    if x and y then add(v3(-1, -1, 1)) end
    if x and z then add(v3(-1, 1, -1)) end
    if y and z then add(v3(1, -1, -1)) end
    if x and y and z then add(v3(-1, -1, -1)) end
  end
  local mesh = pm:GetMesh()
  Mesh_Center(mesh)
  Mesh_ComputeOcclusion(mesh)
  local result = Model_Create()
  result:Add(mesh, Material_Metal())
  return result :: any
end

function ModelEditor.Create(): Widget
  local model = startingModel()
  local options: Types.Options = { symmetryX = false, symmetryY = false, symmetryZ = false }
  local toggles = options :: any
  local previewWindow: Widget? = nil
  local mainWindow: Widget

  local editor = Widget_ListVertical(0, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local title = Components.Expand(Components.Padding(vector.create(24, 12), vector.create(24, 12),
        Components.AlignCenter(Widgets.ListH(16,
          Components.AlignCenter(Widgets.Text(Fonts.Medium(), "MODEL EDITOR", 20, vector.create(1, 1, 1))),
          Components.AlignCenter(Components.MinSize(32, Widgets.Icon(Icons.Comm(), 1.5 * Colors.Primary)))))))
      local toolbar = Widget_ListVertical(4, Widget_Luau(Widget_Create(), {
        CreateChildren = function(): { Widget }
          return {
            Components.Expand(ToggleButton.Create(toggles, "symmetryX", "X SYMMETRY")),
            Components.Expand(ToggleButton.Create(toggles, "symmetryY", "Y SYMMETRY")),
            Components.Expand(ToggleButton.Create(toggles, "symmetryZ", "Z SYMMETRY")),
          }
        end,
      }))
      mainWindow = Components.GreedyY(Components.Expand(Widgets.Stack(Components.Expand(Widgets.ListH(0,
        Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.75, 1, 0,
          Components.Expand(Components.MinSize(vector.create(196, 0), toolbar))),
        Components.BackdropGrid(Colors.Primary, 0.25, Editor.Create(options, model)))))))
      return { title, mainWindow }
    end,
    PostUpdate = function()
      if Key_Pressed(Key_Tab()) then
        local shown = previewWindow
        if shown then
          mainWindow:RemoveChild(shown)
          previewWindow = nil
        else
          local preview = Preview.Create(build(model, options))
          mainWindow:AddChild(preview)
          previewWindow = preview
        end
      end
    end,
  }))
  return Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.95, 1, 0, Components.Expand(editor))
end

return ModelEditor
