--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Codec")

local function roundTrip(value: any): any
  local data, length = Codec.Encode(value)
  return Codec.Decode(data, length)
end

suite:Case("values survive a round trip", function(t)
  local samples: { any } = {
    true, false, 0, 1, -1, 2147483647, -2147483648, 2147483648, 1e300, 0.1, -0.5,
    math.huge, -math.huge, "", "text", string.rep("x", 1000), "\0\255 bytes",
    {}, { 1, 2, 3 }, { a = 1, b = { c = { 1, { d = false } :: any } } },
    { [10] = "sparse", [20] = "keys" }, { 1, 2, x = "mixed" } :: any,
    { [-1] = 1, [0] = 2, [1.5] = 3 },
  }
  for i, sample in samples do
    t.eq(roundTrip(sample), sample, `sample {i}`)
  end
end)

suite:Case("NaN and negative zero survive", function(t)
  local back = roundTrip({ 0 / 0, -0 })
  t.ok(back[1] ~= back[1], "NaN")
  t.eq(1 / back[2], -math.huge, "negative zero keeps its sign")
end)

suite:Case("equal values give equal bytes whatever the insertion order", function(t)
  local a: { [any]: any } = {}
  for i = 1, 200 do
    a["key" .. i] = i
    a[i * 7] = { name = "n" .. i }
  end
  local b: { [any]: any } = {}
  for i = 200, 1, -1 do
    b[i * 7] = { name = "n" .. i }
    b["key" .. i] = i
  end
  t.eq(Codec.HashOf(a), Codec.HashOf(b))
  -- and a table that was filled, emptied and refilled
  local c: { [any]: any } = {}
  for i = 1, 1000 do
    c["junk" .. i] = true
  end
  for i = 1, 1000 do
    c["junk" .. i] = nil
  end
  for k, v in a do
    c[k] = v
  end
  t.eq(Codec.HashOf(c), Codec.HashOf(a))
end)

suite:Case("different values give different hashes", function(t)
  local seen: { [string]: string } = {}
  local samples: { [string]: any } = {
    one = 1, onePointFive = 1.5, str1 = "1", yes = true, no = false,
    empty = {}, list1 = { 1 }, list2 = { 1, 2 }, map = { a = 1 }, map2 = { a = 2 }, map3 = { b = 1 },
    nested = { { 1 } }, zero = 0, negZero = -0,
  }
  for name, sample in samples do
    local h = Codec.HashOf(sample)
    t.ok(seen[h] == nil, `{name} collides with {tostring(seen[h])}`)
    seen[h] = name
  end
end)

suite:Case("the hash is stable across runs", function(t)
  -- A golden value: if this changes, every stored state hash is invalid.
  t.eq(Codec.HashOf({ tick = 42, names = { "a", "b" }, stock = { ore = 10.5 } }), "62b992a35984eaed")
end)

suite:Case("a table with holes is not mistaken for an array", function(t)
  local holes: { [any]: any } = { 1, 2, 3, 4 }
  holes[2] = nil
  t.eq(roundTrip(holes), { [1] = 1, [3] = 3, [4] = 4 })
end)

suite:Case("what is not plain data is refused, with its path", function(t)
  local function message(value: any): string
    local ok, err = pcall(function()
      Codec.Encode(value)
    end)
    t.ok(not ok, "expected a refusal")
    return tostring(err)
  end
  t.eq(message({ a = { print } }), "Codec: cannot encode the function at .a[1]")
  t.eq(message({ [true] = 1 }), "Codec: a boolean used as a key in the root; keys must be numbers or strings")
  local shared = { 1 }
  t.eq(message({ x = shared, y = { shared } }),
    "Codec: the table at .y[1] is also at .x; state must refer to shared things by id")
  local cycle: { [string]: any } = {}
  cycle.self = cycle
  t.eq(message(cycle), "Codec: the table at .self is also at the root; state must refer to shared things by id")
  t.eq(message({ vector.create(1, 2, 3) }), "Codec: cannot encode the vector at [1]")
end)

suite:Case("damaged data is refused", function(t)
  local data, length = Codec.Encode({ a = { 1, 2, 3 }, b = "text" })
  t.fails(function()
    Codec.Decode(data, length - 1)
  end, "truncated")
  t.fails(function()
    Codec.Decode(buffer.fromstring("nope"))
  end, "wrong magic")
  local extra = buffer.create(length + 1)
  buffer.copy(extra, 0, data, 0, length)
  t.fails(function()
    Codec.Decode(extra)
  end, "trailing bytes")
end)

suite:Case("a megabyte encodes and hashes quickly", function(t)
  local big = {}
  for i = 1, 20000 do
    big[i] = { id = i, name = "entity" .. i, x = i * 0.5, tags = { "a", "b" }, stock = { ore = i, fuel = 0.25 } }
  end
  local started = Host.Clock()
  local data, length = Codec.Encode(big)
  local encoded = Host.Clock() - started
  local hash = Codec.Hash(data, length)
  local hashed = Host.Clock() - started - encoded
  local back = Codec.Decode(data, length)
  local decoded = Host.Clock() - started - encoded - hashed
  t.eq(#back, 20000)
  t.eq(Codec.HashOf(back), hash)
  print(string.format("     codec: %d bytes; encode %.0f ms, hash %.0f ms, decode %.0f ms",
    length, encoded * 1000, hashed * 1000, decoded * 1000))
  t.ok(encoded < 2 and hashed < 2 and decoded < 2, "the codec is unexpectedly slow")
end)

return suite
