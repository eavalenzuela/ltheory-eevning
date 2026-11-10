--!strict
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Gunnery")

suite:Case("a frigate's scanner locks a frigate in under four seconds", function(t)
  -- asinh(35) = 4.24868, squared 18.0513; 40000 / (600 * 18.0513)
  t.near(Gunnery.LockTime(600, 35), 3.6932, 1e-3)
  t.ok(Gunnery.LockTime(600, 180) < Gunnery.LockTime(600, 35), "a bigger target locks faster")
  t.ok(Gunnery.LockTime(150, 35) > 4 * Gunnery.LockTime(600, 35) - 1e-9, "a hauler's scanner is four times slower")
end)

suite:Case("range: certain inside optimal, a half at one falloff, a sixteenth at two", function(t)
  t.eq(Gunnery.HitChance(0, 370, 35, 3000, 5200, 2500), 1)
  t.eq(Gunnery.HitChance(0, 370, 35, 5200, 5200, 2500), 1)
  t.near(Gunnery.HitChance(0, 370, 35, 7700, 5200, 2500), 0.5, 1e-12)
  t.near(Gunnery.HitChance(0, 370, 35, 10200, 5200, 2500), 0.0625, 1e-12)
  t.eq(Gunnery.HitChance(0, 370, 35, 9000, 5200, 0), 0, "no falloff: nothing past optimal")
end)

suite:Case("tracking: a target crossing as fast as the gun can turn is hit half the time", function(t)
  -- angular * 40000 / (tracking * signature) = 1 when angular = 370 * 35 / 40000
  local matched = 370 * 35 / 40000
  t.near(Gunnery.HitChance(matched, 370, 35, 1000, 5200, 2500), 0.5, 1e-12)
  t.near(Gunnery.HitChance(2 * matched, 370, 35, 1000, 5200, 2500), 0.0625, 1e-12)
  -- a bigger target is easier to follow
  t.ok(Gunnery.HitChance(matched, 370, 180, 1000, 5200, 2500) > 0.97)
  -- and the two penalties add in the exponent
  t.near(Gunnery.HitChance(matched, 370, 35, 7700, 5200, 2500), 0.25, 1e-12)
end)

suite:Case("shot quality: wrecking under 1%, then the roll plus 0.49, else a miss", function(t)
  t.eq(Gunnery.Quality(0.005, 0.8), 3)
  t.near(Gunnery.Quality(0.5, 0.8), 0.99, 1e-12)
  t.near(Gunnery.Quality(0.79, 0.8), 1.28, 1e-12)
  t.eq(Gunnery.Quality(0.8, 0.8), 0)
  t.eq(Gunnery.Quality(0.005, 0), 0, "no chance, no wrecking hit")
  -- the average over many even rolls: 1% wrecking, the rest of the hits at roll + 0.49
  local total, n = 0, 100000
  for i = 0, n - 1 do
    total += Gunnery.Quality((i + 0.5) / n, 1)
  end
  t.near(total / n, 0.01 * 3 + (0.99 * (0.01 + 1) / 2 + 0.99 * 0.49), 1e-3)
end)

suite:Case("a missile does less to a small target and less again to a fast one", function(t)
  t.near(Gunnery.MissileFactor(35, 0, 40, 170), 0.875, 1e-12)
  t.eq(Gunnery.MissileFactor(180, 0, 40, 170), 1)
  -- (35/40 * 170/360) ^ 0.68
  t.near(Gunnery.MissileFactor(35, 360, 40, 170), 0.5483, 1e-3)
  t.near(Gunnery.MissileFactor(35, 100, 40, 170), 0.875, 1e-12, "a slow target takes the size-limited share")
end)

suite:Case("damage passes through the layers by their resonances", function(t)
  local shield, armor, hull = { 1.0, 0.8, 0.6, 0.5 }, { 0.5, 0.65, 0.75, 0.9 }, { 0.67, 0.67, 0.67, 0.67 }
  -- 100 EM into 60 shield: the shield takes 60% of it, 40 EM goes on to armour at 0.5
  local layers = { shield = 60, armor = 500, hull = 300 }
  t.eq({ Gunnery.Apply(layers, shield, armor, hull, { 100, 0, 0, 0 }) }, { 60, 20, 0 })
  t.eq(layers, { shield = 0, armor = 480, hull = 300 })
  -- explosive is the shield's strong side and the armour's weak one
  layers = { shield = 100, armor = 100, hull = 300 }
  Gunnery.Apply(layers, shield, armor, hull, { 0, 0, 0, 100 })
  t.eq(layers, { shield = 50, armor = 100, hull = 300 })
  -- a hit that goes through everything
  layers = { shield = 10, armor = 9, hull = 6.7 }
  local s, a, h = Gunnery.Apply(layers, shield, armor, hull, { 0, 0, 0, 100 })
  -- shield takes 10 of 50 (20%); armour sees 80 * 0.9 = 72, takes 9 (12.5% of that);
  -- hull sees 70 * 0.67 = 46.9, takes all 6.7
  t.near(s, 10, 1e-12)
  t.near(a, 9, 1e-12)
  t.near(h, 6.7, 1e-12)
  t.eq(layers, { shield = 0, armor = 0, hull = 0 })
  -- mixed damage types
  layers = { shield = 1000, armor = 1, hull = 1 }
  Gunnery.Apply(layers, shield, armor, hull, { 10, 10, 10, 10 })
  t.near(layers.shield, 1000 - (10 + 8 + 6 + 5), 1e-12)
end)

suite:Case("recharge is fastest at a quarter full and never overfills", function(t)
  -- from 25%: (1 + (0.5 - 1) * exp(-5 * 10 / 190))^2 of 400
  t.near(Gunnery.Recharge(100, 400, 190, 10), 400 * (1 - 0.5 * math.exp(-50 / 190)) ^ 2, 1e-9)
  t.ok(Gunnery.Recharge(0, 400, 190, 1) > 0, "it climbs out of empty")
  t.eq(Gunnery.Recharge(400, 400, 190, 10), 400)
  local gain = function(x: number): number
    return Gunnery.Recharge(400 * x, 400, 190, 1) - 400 * x
  end
  t.ok(gain(0.25) > gain(0.1) and gain(0.25) > gain(0.5) and gain(0.5) > gain(0.9))
  -- many small steps equal one large one
  local c = 37
  for _ = 1, 60 do
    c = Gunnery.Recharge(c, 400, 190, 0.5)
  end
  t.near(c, Gunnery.Recharge(37, 400, 190, 30), 1e-9)
end)

return suite
