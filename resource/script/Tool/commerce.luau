--!strict
-- A look at the galaxy's economy (Core/Strategic/Commerce), run by
-- itself: bin/ltcore Tool/commerce [systems] [days] [seed] [hours a step]
--
-- It builds a galaxy and its economy, lets so many game days go by, and
-- prints what the goods go for across the map (the lowest, the middle
-- and the highest price of each, as shares of its normal price, and how
-- many systems have it pinned at the floor or the ceiling), how much of
-- everything came through the homeworlds' dealings with the world
-- beyond (a healthy economy barely uses them), how well people's needs
-- were met, and what a step costs.

local Commerce = require("@lt/Core/Strategic/Commerce")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")

return { Main = function(args: { string }): number
  local systems, days, seed = tonumber(args[1]) or 400, tonumber(args[2]) or 30, tonumber(args[3]) or 1
  -- (a sixth of an hour is the game's own step; a new game's economy is settled in longer ones)
  local hours = tonumber(args[4]) or 1 / 6
  local galaxy = Galaxy.Describe(seed, systems)
  local started = os.clock()
  local econ = Commerce.New(galaxy)
  print(string.format("%d systems, %d gates, %d goods, %d stages of industry: built in %.2f s", #econ.nodes, #econ.edges,
    #econ.classes, #econ.recipes, os.clock() - started))
  local steps = math.ceil(days * 24 / hours)
  started = os.clock()
  for _ = 1, steps do
    Economy.Step(econ, hours)
  end
  local took = os.clock() - started
  print(string.format("%d days in %.2f s: %.2f ms a step", days, took, 1000 * took / steps))
  local worst = 0
  for class, residual in Economy.Residual(econ) do
    worst = math.max(worst, math.abs(residual) * econ.classes[class].par)
  end
  local met = 0
  for _, node in econ.nodes do
    met += node.met
  end
  print(string.format("from beyond: %.1f%% of all that came into any stock; needs met: %.1f%%; books out by %.0f credits",
    100 * Economy.AnchorShare(econ), 100 * met / #econ.nodes, worst))
  print("  goods                      lowest  middle highest   floor  ceiling")
  for class, info in econ.classes do
    local ratios: { number } = {}
    local low, high = 0, 0
    for id = 1, #econ.nodes do
      local ratio = Economy.Price(econ, id, class) / info.par
      table.insert(ratios, ratio)
      low += if ratio <= 0.2501 then 1 else 0
      high += if ratio >= 3.999 then 1 else 0
    end
    table.sort(ratios)
    print(string.format("  %-26s %6.2f  %6.2f  %6.2f  %5d  %5d", info.id, ratios[1], ratios[(#ratios + 1) // 2], ratios[#ratios], low, high))
  end
  return 0
end }
