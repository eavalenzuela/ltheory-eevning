--!strict
local Constants = require("@lt/Core/Data/Constants")
local Motion = require("@lt/Core/Tactical/Motion")
local Ships = require("@lt/Core/Data/Ships")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Motion")
local AU = Constants.AU

suite:Case("a step is exact: many small steps equal one large one", function(t)
  local tau = 3.52
  local x, y, z, vx, vy, vz = 0, 0, 0, 10, -5, 2
  for _ = 1, 100 do
    x, y, z, vx, vy, vz = Motion.Step(x, y, z, vx, vy, vz, 360, 40, 0, tau, 0.05)
  end
  local X, Y, Z, VX, VY, VZ = Motion.Step(0, 0, 0, 10, -5, 2, 360, 40, 0, tau, 5)
  t.near(x, X, 1e-6)
  t.near(y, Y, 1e-6)
  t.near(z, Z, 1e-6)
  t.near(vx, VX, 1e-9)
  t.near(vy, VY, 1e-9)
  t.near(vz, VZ, 1e-9)
end)

suite:Case("time to align is 1.386 time constants", function(t)
  local courier = Ships.byId["frigate.courier"]
  local tau = Ships.TimeConstant(courier)
  t.near(tau, 3.52, 1e-12, "1.1e6 kg at inertia 3.2")
  local align = Motion.TimeToSpeed(tau, Constants.WARP_ALIGN_SPEED)
  t.near(align, 1.3862944 * 3.52, 1e-6)
  local _, _, _, vx = Motion.Step(0, 0, 0, 0, 0, 0, courier.maxVelocity, 0, 0, tau, align)
  t.near(vx, 0.75 * courier.maxVelocity, 1e-9, "stepping for that long reaches 75%")
end)

suite:Case("a frigate warps 20 AU in 22 s and 50 AU in 28 s", function(t)
  local plan = Motion.PlanWarp(20 * AU, 5, 360)
  t.near(plan.tAccel, 5.146243, 1e-5, "ln(AU) / 5")
  t.near(plan.tCruise, 3.2, 1e-6, "16 AU at 5 AU/s")
  t.near(plan.tDecel, 13.641291, 1e-5, "ln(5 AU / 100) / (5/3)")
  t.near(plan.total, 21.987534, 1e-5)
  t.near(Motion.PlanWarp(50 * AU, 5, 360).total, 27.987534, 1e-5)
end)

suite:Case("a slower hull takes longer over the same distance", function(t)
  local frigate = Motion.PlanWarp(20 * AU, 5, 360).total
  local hauler = Motion.PlanWarp(20 * AU, 4.5, 130).total
  t.ok(hauler > frigate + 1, `hauler {hauler} s, frigate {frigate} s`)
  t.eq(Motion.PlanWarp(20 * AU, 4.5, 130).dropout, 65, "drops out at half its top speed")
end)

suite:Case("a short warp never reaches full speed and still covers the distance", function(t)
  local plan = Motion.PlanWarp(150000, 5, 360)
  t.eq(plan.dCruise, 0)
  t.near(plan.peak, 187576.25, 1e-6)
  t.near(plan.total, 6.6286, 1e-3)
  t.near(plan.dAccel + (plan.peak - plan.dropout) / plan.j, 150000, 1e-6)
end)

suite:Case("distance along a warp is continuous, increasing and ends on target", function(t)
  for _, distance in { 150000, 5e9, 0.9 * AU, 4 * AU, 20 * AU } do
    local plan = Motion.PlanWarp(distance, 5, 360)
    local lastD = 0
    local steps = 4000
    for i = 0, steps do
      local d, v = Motion.WarpAt(plan, plan.total * i / steps)
      t.ok(d >= lastD, `distance went backwards at step {i} of a {distance} m warp`)
      t.ok(v > 0)
      -- no step may jump further than the peak speed allows
      t.ok(d - lastD <= plan.peak * plan.total / steps * 1.0001 + 1e-6, `jump at step {i}`)
      lastD = d
    end
    local d, v = Motion.WarpAt(plan, plan.total)
    t.near(d, distance, distance * 1e-12 + 1e-6)
    t.eq(v, plan.dropout)
    t.eq(select(1, Motion.WarpAt(plan, plan.total + 100)), distance, "and stays there")
  end
end)

return suite
