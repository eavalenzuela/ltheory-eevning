--!strict
-- Names for systems, from syllables, and the survey marks of the systems
-- that have no name. Deterministic from the stream given.

local Rng = require("@lt/Core/Kernel/Rng")

local Names = {}

local ONSETS = { "al", "ar", "bel", "cor", "dra", "el", "fen", "gal", "hal", "ir", "jor", "kes",
  "lor", "mer", "nor", "or", "per", "quil", "ras", "sel", "tal", "ul", "ves", "zan" }
local MIDDLES = { "a", "e", "i", "o", "u", "an", "en", "ir", "or", "eth", "ar", "is" }
local ENDINGS = { "a", "ar", "en", "ia", "is", "on", "or", "os", "um", "us", "yn", "eth" }

local function pick(rng: Rng.Rng, list: { string }): string
  return list[Rng.Int(rng, #list) + 1]
end

-- (the middles that have a consonant to them: what a longer name is
-- drawn out with, so that it is not a run of vowels)
local DRAWN = { "an", "en", "ir", "or", "eth", "ar", "is" }

-- There are some 3,700 of these names and no more. A galaxy that wants
-- more asks for them 'longer': so many syllables more in the middle,
-- each of which makes seven times as many.
function Names.System(rng: Rng.Rng, longer: number?): string
  local name = pick(rng, ONSETS)
  if Rng.Chance(rng, 0.6) or (longer or 0) > 0 then
    name ..= pick(rng, MIDDLES)
  end
  for _ = 1, longer or 0 do
    name ..= pick(rng, DRAWN)
  end
  name ..= pick(rng, ENDINGS)
  return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- A name that is not among those 'used', which it then is. Eight taken
-- in a row, and the names of that length are running out: the next are
-- a syllable longer.
function Names.Unused(rng: Rng.Rng, used: { [string]: boolean }): string
  local name = Names.System(rng)
  local tries = 0
  while used[name] do
    tries += 1
    name = Names.System(rng, tries // 8)
  end
  used[name] = true
  return name
end

-- A survey mark: what a system is known by that nobody has named,
-- since nobody lives there. Five letters and figures with a stroke
-- among them, as the surveys wrote them down: "K7-RDX", "4QVM-2".
-- (No vowels, so that a mark never spells anything and is never taken
-- for a name.)
local MARKS = "BCDFGHJKLMNPQRSTVWXYZ0123456789"
local MARK_LENGTH = 5

function Names.Mark(rng: Rng.Rng): string
  local stroke = 1 + Rng.Int(rng, MARK_LENGTH - 1)
  local mark = ""
  for at = 1, MARK_LENGTH do
    local which = Rng.Int(rng, #MARKS) + 1
    mark ..= string.sub(MARKS, which, which)
    if at == stroke then
      mark ..= "-"
    end
  end
  return mark
end

-- A mark that is not among those 'used', which it then is.
function Names.UnusedMark(rng: Rng.Rng, used: { [string]: boolean }): string
  local mark = Names.Mark(rng)
  while used[mark] do
    mark = Names.Mark(rng)
  end
  used[mark] = true
  return mark
end

-- Whether a system's name is a survey mark, and not a name.
function Names.IsMark(name: string): boolean
  return string.find(name, "-", 1, true) ~= nil
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
