--!strict
-- Names for systems, from syllables. Deterministic from the stream given.

local Rng = require("@lt/Core/Kernel/Rng")

local Names = {}

local ONSETS = { "al", "ar", "bel", "cor", "dra", "el", "fen", "gal", "hal", "ir", "jor", "kes",
  "lor", "mer", "nor", "or", "per", "quil", "ras", "sel", "tal", "ul", "ves", "zan" }
local MIDDLES = { "a", "e", "i", "o", "u", "an", "en", "ir", "or", "eth", "ar", "is" }
local ENDINGS = { "a", "ar", "en", "ia", "is", "on", "or", "os", "um", "us", "yn", "eth" }

local function pick(rng: Rng.Rng, list: { string }): string
  return list[Rng.Int(rng, #list) + 1]
end

function Names.System(rng: Rng.Rng): string
  local name = pick(rng, ONSETS)
  if Rng.Chance(rng, 0.6) then
    name ..= pick(rng, MIDDLES)
  end
  name ..= pick(rng, ENDINGS)
  return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- A person's name: a given name and a family's.
local GIVEN = { "Ada", "Bren", "Cato", "Dara", "Edrin", "Fal", "Garet", "Hana", "Ilse", "Joran", "Kessa", "Lio",
  "Mara", "Nico", "Orla", "Pell", "Quin", "Rhea", "Soren", "Tamsin", "Ulla", "Varo", "Wren", "Yara" }

function Names.Person(rng: Rng.Rng): string
  return pick(rng, GIVEN) .. " " .. Names.System(rng)
end

local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }

function Names.Roman(n: number): string
  return NUMERALS[n] or tostring(n)
end

return Names
