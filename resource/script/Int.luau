--!strict
-- 32-bit integer wraparound (and float rounding). LTSL ints overflow and convert between int
-- and uint silently; the Luau binder rejects out-of-range values instead,
-- so ports that must reproduce LTSL's numbers wrap explicitly.

local Int = {}

local TWO32 = 4294967296
local TWO31 = 2147483648

-- As a C++ int: wraps into [-2^31, 2^31)
function Int.Signed(x: number): number
  return (x + TWO31) % TWO32 - TWO31
end

-- As a C++ uint: wraps into [0, 2^32)
function Int.Unsigned(x: number): number
  return x % TWO32
end

-- Rounded to a C++ float, for LTSL Float arithmetic that is truncated to an
-- integer afterwards (Luau vectors are single precision)
function Int.Float32(x: number): number
  return vector.create(x, 0, 0).x
end

return Int
