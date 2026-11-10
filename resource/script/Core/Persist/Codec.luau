--!strict
-- Binary encoding of plain game state.
--
-- The game's state is plain data: booleans, numbers, strings, and tables
-- of those keyed by numbers or strings. Codec turns such a value into
-- bytes and back. The same bytes are what a save file stores and what the
-- state hash is computed from, so "these two states are equal" and "this
-- state saves and loads unchanged" are one question.
--
-- The encoding is canonical: equal values give equal bytes, whatever
-- order their tables were filled in. Map keys are written in sorted order
-- (numbers ascending, then strings in byte order).
--
-- What it refuses, with the path to the offending value:
--   - functions, userdata, threads, vectors and buffers;
--   - keys that are not numbers or strings;
--   - a table reachable twice. Decoding would give two copies, silently
--     breaking whatever relied on them being one table, so state must
--     refer to shared things by id.
--
-- Layout: the magic "LTV1", then one value.
--   value  = 0x01 (false) | 0x02 (true)
--          | 0x03 i32            a whole number that fits 32 bits
--          | 0x04 f64            any other number
--          | 0x05 len bytes      a string seen for the first time
--          | 0x06 index          a string seen before (0-based, in order
--                                of first appearance)
--          | 0x07 n value*n      a table with exactly the keys 1..n
--          | 0x08 n (key value)*n  any other table
--   len, index and n are unsigned LEB128.

local Codec = {}

local MAGIC = "LTV1"

local T_FALSE = 1
local T_TRUE = 2
local T_INT = 3
local T_NUM = 4
local T_STR = 5
local T_REF = 6
local T_ARRAY = 7
local T_MAP = 8

local INT_MIN = -2147483648
local INT_MAX = 2147483647

-- ---------------------------------------------------------------------
-- Writer

type Writer = {
  buf: buffer,
  len: number,
  cap: number,
  strings: { [string]: number },
  stringCount: number,
  -- Tables already written, by identity. Only this module may key a table
  -- by a table: it is never iterated.
  seen: { [any]: boolean },
  -- The keys leading to the value being written, for error messages.
  -- Kept as a stack so that no path string is built unless one is needed.
  keys: { any },
  depth: number,
  root: any,
}

local function reserve(w: Writer, extra: number)
  local need = w.len + extra
  if need > w.cap then
    local cap = w.cap * 2
    while cap < need do
      cap *= 2
    end
    local grown = buffer.create(cap)
    buffer.copy(grown, 0, w.buf, 0, w.len)
    w.buf = grown
    w.cap = cap
  end
end

local function writeByte(w: Writer, byte: number)
  reserve(w, 1)
  buffer.writeu8(w.buf, w.len, byte)
  w.len += 1
end

local function writeVarint(w: Writer, n: number)
  reserve(w, 10)
  while n >= 128 do
    buffer.writeu8(w.buf, w.len, n % 128 + 128)
    w.len += 1
    n //= 128
  end
  buffer.writeu8(w.buf, w.len, n)
  w.len += 1
end

local function writeNumber(w: Writer, x: number)
  -- 1 / x tells 0 from -0, which must stay an f64 to survive the trip.
  if x % 1 == 0 and x >= INT_MIN and x <= INT_MAX and (x ~= 0 or 1 / x > 0) then
    reserve(w, 5)
    buffer.writeu8(w.buf, w.len, T_INT)
    buffer.writei32(w.buf, w.len + 1, x)
    w.len += 5
  else
    reserve(w, 9)
    buffer.writeu8(w.buf, w.len, T_NUM)
    buffer.writef64(w.buf, w.len + 1, x)
    w.len += 9
  end
end

local function writeString(w: Writer, s: string)
  local index = w.strings[s]
  if index then
    writeByte(w, T_REF)
    writeVarint(w, index)
    return
  end
  w.strings[s] = w.stringCount
  w.stringCount += 1
  writeByte(w, T_STR)
  writeVarint(w, #s)
  reserve(w, #s)
  buffer.writestring(w.buf, w.len, s)
  w.len += #s
end

local function formatPath(keys: { any }, depth: number): string
  if depth == 0 then
    return "the root"
  end
  local parts = table.create(depth)
  for i = 1, depth do
    local k = keys[i]
    parts[i] = if type(k) == "number" then `[{k}]` else `.{tostring(k)}`
  end
  return table.concat(parts)
end

-- The keys of 't' in the order they are written. For a table with exactly
-- the keys 1..n (an array) it returns nil and n; otherwise the keys, with
-- numbers ascending and then strings, and their count. Raises on any
-- other kind of key.
local function orderedKeys(w: Writer, t: { [any]: any }): ({ any }?, number)
  local n = #t
  local count = 0
  local isArray = true
  for k in t do
    count += 1
    if isArray and not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
      isArray = false
    end
  end
  if isArray and count == n then
    return nil, n
  end

  local numbers: { any } = {}
  local strings: { any } = {}
  for k in t do
    local kind = type(k)
    if kind == "number" then
      if k ~= k then
        error(`Codec: NaN used as a key in {formatPath(w.keys, w.depth)}`, 0)
      end
      table.insert(numbers, k)
    elseif kind == "string" then
      table.insert(strings, k)
    else
      error(`Codec: a {kind} used as a key in {formatPath(w.keys, w.depth)}; `
        .. "keys must be numbers or strings", 0)
    end
  end
  table.sort(numbers)
  table.sort(strings)
  table.move(strings, 1, #strings, #numbers + 1, numbers)
  return numbers, count
end

-- Where 'target' is first reached from the root, in writing order. Only
-- used to explain a refusal, so it may be slow.
local function firstPath(w: Writer, target: any): string
  local keys: { any } = {}
  local visited: { [any]: boolean } = {}
  local function search(t: any, depth: number): string?
    if t == target then
      return formatPath(keys, depth)
    end
    if visited[t] then
      return nil
    end
    visited[t] = true
    local scratch: Writer = table.clone(w)
    scratch.keys, scratch.depth = keys, depth
    local ordered, n = orderedKeys(scratch, t)
    for i = 1, n do
      local k = if ordered then ordered[i] else i
      local v = t[k]
      if type(v) == "table" then
        keys[depth + 1] = k
        local found = search(v, depth + 1)
        if found then
          return found
        end
      end
    end
    return nil
  end
  return search(w.root, 0) or "an earlier place"
end

local writeValue: (w: Writer, v: any) -> ()

local function writeTable(w: Writer, t: { [any]: any })
  if w.seen[t] then
    error(`Codec: the table at {formatPath(w.keys, w.depth)} is also at {firstPath(w, t)}; `
      .. "state must refer to shared things by id", 0)
  end
  w.seen[t] = true

  local keys, n = orderedKeys(w, t)
  local depth = w.depth + 1
  w.depth = depth
  if keys == nil then
    writeByte(w, T_ARRAY)
    writeVarint(w, n)
    for i = 1, n do
      w.keys[depth] = i
      writeValue(w, t[i])
    end
  else
    writeByte(w, T_MAP)
    writeVarint(w, n)
    for _, k in keys do
      w.keys[depth] = k
      if type(k) == "number" then
        writeNumber(w, k)
      else
        writeString(w, k)
      end
      writeValue(w, t[k])
    end
  end
  w.depth = depth - 1
end

function writeValue(w: Writer, v: any)
  local kind = type(v)
  if kind == "number" then
    writeNumber(w, v)
  elseif kind == "string" then
    writeString(w, v)
  elseif kind == "boolean" then
    writeByte(w, if v then T_TRUE else T_FALSE)
  elseif kind == "table" then
    writeTable(w, v)
  else
    error(`Codec: cannot encode the {kind} at {formatPath(w.keys, w.depth)}`, 0)
  end
end

-- Encode 'value'. Returns a buffer and how many of its bytes are used
-- (the buffer is usually larger).
function Codec.Encode(value: any): (buffer, number)
  local w: Writer = {
    buf = buffer.create(4096),
    len = 0,
    cap = 4096,
    strings = {},
    stringCount = 0,
    seen = {},
    keys = {},
    depth = 0,
    root = value,
  }
  buffer.writestring(w.buf, 0, MAGIC)
  w.len = #MAGIC
  writeValue(w, value)
  return w.buf, w.len
end

-- ---------------------------------------------------------------------
-- Reader

type Reader = {
  buf: buffer,
  pos: number,
  len: number,
  strings: { string },
}

local function readVarint(r: Reader): number
  local n = 0
  local scale = 1
  while true do
    local byte = buffer.readu8(r.buf, r.pos)
    r.pos += 1
    if byte < 128 then
      return n + byte * scale
    end
    n += (byte - 128) * scale
    scale *= 128
  end
end

local function readValue(r: Reader): any
  local tag = buffer.readu8(r.buf, r.pos)
  r.pos += 1
  if tag == T_INT then
    local x = buffer.readi32(r.buf, r.pos)
    r.pos += 4
    return x
  elseif tag == T_NUM then
    local x = buffer.readf64(r.buf, r.pos)
    r.pos += 8
    return x
  elseif tag == T_REF then
    return r.strings[readVarint(r) + 1]
  elseif tag == T_STR then
    local size = readVarint(r)
    local s = buffer.readstring(r.buf, r.pos, size)
    r.pos += size
    table.insert(r.strings, s)
    return s
  elseif tag == T_TRUE then
    return true
  elseif tag == T_FALSE then
    return false
  elseif tag == T_ARRAY then
    local n = readVarint(r)
    local t = table.create(n)
    for i = 1, n do
      t[i] = readValue(r)
    end
    return t
  elseif tag == T_MAP then
    local n = readVarint(r)
    local t: { [any]: any } = {}
    for _ = 1, n do
      local k = readValue(r)
      t[k] = readValue(r)
    end
    return t
  end
  error(`Codec: unknown tag {tag} at byte {r.pos - 1}; the data is damaged or not Codec data`, 0)
end

-- Decode the first 'length' bytes of 'data' (all of it by default).
-- Raises if the data is not what Encode wrote.
function Codec.Decode(data: buffer, length: number?): any
  local len = length or buffer.len(data)
  if len < #MAGIC or buffer.readstring(data, 0, #MAGIC) ~= MAGIC then
    error("Codec: the data does not start with " .. MAGIC, 0)
  end
  local r: Reader = { buf = data, pos = #MAGIC, len = len, strings = {} }
  -- A read past the end of the buffer raises by itself; a read past
  -- 'length' but inside the buffer is caught here.
  local ok, value = pcall(readValue, r)
  if not ok then
    error(`Codec: the data is damaged ({tostring(value)})`, 0)
  end
  if r.pos ~= len then
    error(`Codec: {len - r.pos} byte(s) left over after the value; the data is damaged`, 0)
  end
  return value
end

-- ---------------------------------------------------------------------
-- Hash

local TWO32 = 4294967296

-- 32-bit multiply without losing precision in doubles.
local function imul(a: number, b: number): number
  local ah, al = a // 65536, a % 65536
  return ((ah * b % TWO32) * 65536 + al * b) % TWO32
end

-- A 64-bit fingerprint of the first 'length' bytes, as 16 hex digits.
-- Two FNV-1a style lanes over 32-bit words; for telling states apart, not
-- for security.
function Codec.Hash(data: buffer, length: number): string
  local h1, h2 = 2166136261, 0x9E3779B9
  local words = length // 4
  local bxor, rshift, readu32 = bit32.bxor, bit32.rshift, buffer.readu32
  for i = 0, words - 1 do
    local word = readu32(data, i * 4)
    h1 = imul(bxor(h1, word), 16777619)
    h2 = imul(bxor(h2, word), 0x85EBCA6B)
    h2 = bxor(h2, rshift(h2, 13))
  end
  for i = words * 4, length - 1 do
    local byte = buffer.readu8(data, i)
    h1 = imul(bxor(h1, byte), 16777619)
    h2 = imul(bxor(h2, byte), 0x85EBCA6B)
    h2 = bxor(h2, rshift(h2, 13))
  end
  h1 = bxor(h1, length % TWO32)
  h1 = imul(bxor(h1, rshift(h1, 16)), 0x85EBCA6B)
  h2 = imul(bxor(h2, rshift(h2, 15)), 0xC2B2AE35)
  return string.format("%08x%08x", bxor(h1, rshift(h1, 13)), bxor(h2, rshift(h2, 16)))
end

-- The hash of a value's encoding: equal for equal states.
function Codec.HashOf(value: any): string
  local data, length = Codec.Encode(value)
  return Codec.Hash(data, length)
end

return Codec
