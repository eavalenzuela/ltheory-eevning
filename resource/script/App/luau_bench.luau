--!strict
-- Micro-benchmark of the Luau engine bindings, run with `bin/launch luau_bench`.
-- Prints the cost of each kind of engine call, then quits.

local App = {}

local N = 200000

local function time(label: string, f: () -> ())
  local t0 = os.clock()
  f()
  local dt = os.clock() - t0
  print(string.format("%-34s %7.1f ms  %6.3f us/op", label, dt * 1000, dt * 1e6 / N))
end

function App:Initialize()
  local ship = Item_ShipType(20000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
  local pos = vector.create(1, 2, 3)
  local v = New.Vec2()
  v.x = 3

  time("method, no args (GetRadius)", function()
    local sum = 0
    for _ = 1, N do
      sum += ship:GetRadius()
    end
  end)

  time("method, vector arg (SetPos)", function()
    for _ = 1, N do
      ship:SetPos(pos)
    end
  end)

  time("method returning vector (GetPos)", function()
    for _ = 1, N do
      local _p = ship:GetPos()
    end
  end)

  time("global, int arg (Int_Random)", function()
    for _ = 1, N do
      local _r = Int_Random()
    end
  end)

  time("field read (Vec2.x)", function()
    local sum = 0
    for _ = 1, N do
      sum += v.x
    end
  end)

  time("operator (Vec2 + Vec2)", function()
    for _ = 1, N do
      local _w = v + v
    end
  end)

  time("pure Luau arithmetic", function()
    local sum = 0
    for i = 1, N do
      sum += i * 0.5
    end
  end)
end

function App:Update()
  error("done", 0)
end

return App
