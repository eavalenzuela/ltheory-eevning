--!strict
-- Harmonic lattice (Luau port of App/life.lts): a 128x128 parity automaton
-- driven by four fixed points. Space pauses / resumes (it starts paused);
-- Ctrl+S saves to organism.txt and Ctrl+L loads it.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Graph = require("@lt/Life/Graph")
local Icons = require("@lt/Icons")
local Organism = require("@lt/Life/Organism")

local SAVE_PATH = "organism.txt"

local function create(): Organism.Organism
  local organism = Organism.New()
  Graph.AddLatticeGrid(organism.graph, 128, 128)
  local rng = RNG_MTG(Int_Random())
  -- Fixed points: 0-based grid indices and their value sequences
  local function fix(index: number, sequence: { number })
    table.insert(organism.points, { index = index + 1, sequence = sequence })
  end
  fix(64, { 1, 0 })
  fix(64 * 128 + 0, { 0 })
  fix(64 * 128 + 64, { 1, 0, 0 })
  fix(rng:Int(#organism.graph.nodes), { 0 })
  return organism
end

return AppShell.Create(function(): Widget
  local organism = create()
  local pause = true
  local dot = Glyph_Circle(0, 1, 1, 1)

  local view = Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
    PreUpdate = function()
      if Key_Pressed(Key_Space()) then
        pause = not pause
      end
      if not pause then
        Organism.Step(organism)
      end
      if Key_Control() and Key_Pressed(Key_S()) then
        print(if Organism.Save(organism, SAVE_PATH) then `saved {SAVE_PATH}` else `could not save {SAVE_PATH}`)
      end
      if Key_Control() and Key_Pressed(Key_L()) then
        local loaded = Organism.Load(SAVE_PATH)
        if loaded then
          organism = loaded
        else
          print(`no organism in {SAVE_PATH}`)
        end
      end
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 1, 1, 1, 0)
      WidgetRenderer_DrawText(Fonts.Default(), "HARMONIC LATTICE", w:TopLeft() + vector.create(16, 32), 32, 0, 1, false)
      if pause then
        WidgetRenderer_DrawText(Fonts.Default(), "(PAUSED)", w:TopLeft() + vector.create(16, 64), 24,
          vector.create(1, 0, 0), 1, false)
      end
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)

      local s = 0.5 * math.min(w.size.x, w.size.y * math.sqrt(2))
      local scale = vector.create(s, s)
      local center = 0.5 * w.size - 0.5 * scale
      local nodes = organism.graph.nodes
      for _, fp in organism.points do
        Glyph_Draw(dot, center + scale * nodes[fp.index].p, 16, Colors.Primary, 1)
      end
      local lineColor = -1 * vector.create(1.0, 0.5, 0.3)
      for _, edge in organism.graph.edges do
        local n1, n2 = nodes[edge.src], nodes[edge.dst]
        if not edge.boundary and n1.value == 1 and n2.value == 1 then
          Glyph_Draw(Glyph_Line(center + scale * n1.p, center + scale * n2.p, 1, 1), 0, 1, lineColor, 0.5)
        end
      end
    end,
  }))
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Components.Padding(16, 16, view))
end)
