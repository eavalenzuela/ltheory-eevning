--!strict
-- Deterministic random numbers for the universe simulation (mulberry32).
-- Pure Luau, so a seed gives the same universe everywhere. Rng.For mixes
-- several integers (universe seed, tick, action id, ...) into an
-- independent stream, so one roll never depends on how many rolls came
-- before it.

local Rng = {}

export type Rng = { state: number }

local TWO32 = 4294967296

-- 32-bit multiply without losing precision in doubles
local function imul(a: number, b: number): number
  local ah, al = a // 65536, a % 65536
  return ((ah * b % TWO32) * 65536 + al * b) % TWO32
end

function Rng.New(seed: number): Rng
  return { state = seed % TWO32 }
end

-- A stream seeded from several integers
function Rng.For(...: number): Rng
  local h = 2166136261
  for i = 1, select("#", ...) do
    local x = (select(i, ...) :: number) % TWO32
    h = imul(bit32.bxor(h, x), 16777619)
    h = bit32.bxor(h, bit32.rshift(h, 15))
  end
  return { state = h }
end

-- Uniform in [0, 1)
function Rng.Next(r: Rng): number
  r.state = (r.state + 0x6D2B79F5) % TWO32
  local t = r.state
  t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
  t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
  return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
end

function Rng.Float(r: Rng, lo: number, hi: number): number
  return lo + (hi - lo) * Rng.Next(r)
end

-- An integer in [0, n)
function Rng.Int(r: Rng, n: number): number
  return math.floor(Rng.Next(r) * n)
end

function Rng.Chance(r: Rng, p: number): boolean
  return Rng.Next(r) < p
end

-- n scaled with stochastic rounding, so fractions aren't always lost
function Rng.Round(r: Rng, x: number): number
  local whole = math.floor(x)
  return whole + (if Rng.Next(r) < x - whole then 1 else 0)
end

return Rng
