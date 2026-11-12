--!strict
-- JSON, read: enough of it for the files other programs write (a glTF's
-- account of itself). An object is a table by key, an array a table by
-- place, and null is nil, so a null in an array ends it, as Luau has it.
-- What is not JSON is an error that says where.

local Json = {}

local ESCAPES: { [string]: string } = {
  n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"',
}

function Json.Decode(text: string): any
  local at = 1
  local length = #text

  local function fail(what: string): never
    error(`Json: {what} at byte {at}`, 0)
  end

  local function skip()
    while at <= length do
      local c = string.byte(text, at)
      if c == 32 or c == 9 or c == 10 or c == 13 then
        at += 1
      else
        break
      end
    end
  end

  -- (at the quote it opens with)
  local function str(): string
    at += 1
    local parts: { string } = {}
    local from = at
    while true do
      if at > length then
        fail("a string that does not end")
      end
      local c = string.byte(text, at)
      if c == 34 then
        table.insert(parts, string.sub(text, from, at - 1))
        at += 1
        return table.concat(parts)
      elseif c == 92 then
        table.insert(parts, string.sub(text, from, at - 1))
        local escape = string.sub(text, at + 1, at + 1)
        if escape == "u" then
          local code = tonumber(string.sub(text, at + 2, at + 5), 16)
          if code == nil then
            fail("a \\u that is not four hex digits")
          end
          table.insert(parts, utf8.char(code :: number))
          at += 6
        else
          local plain = ESCAPES[escape]
          if plain == nil then
            fail("an escape that is not one")
          end
          table.insert(parts, plain)
          at += 2
        end
        from = at
      else
        at += 1
      end
    end
  end

  local value: () -> any

  local function array(): { any }
    at += 1
    local out: { any } = {}
    skip()
    if string.byte(text, at) == 93 then
      at += 1
      return out
    end
    while true do
      out[#out + 1] = value()
      skip()
      local c = string.byte(text, at)
      at += 1
      if c == 93 then
        return out
      elseif c ~= 44 then
        at -= 1
        fail("an array with no comma or end")
      end
    end
  end

  local function object(): { [string]: any }
    at += 1
    local out: { [string]: any } = {}
    skip()
    if string.byte(text, at) == 125 then
      at += 1
      return out
    end
    while true do
      skip()
      if string.byte(text, at) ~= 34 then
        fail("a key that is not a string")
      end
      local key = str()
      skip()
      if string.byte(text, at) ~= 58 then
        fail("a key with no colon after it")
      end
      at += 1
      out[key] = value()
      skip()
      local c = string.byte(text, at)
      at += 1
      if c == 125 then
        return out
      elseif c ~= 44 then
        at -= 1
        fail("an object with no comma or end")
      end
    end
  end

  value = function(): any
    skip()
    local c = string.byte(text, at)
    if c == nil then
      fail("nothing where a value should be")
    elseif c == 123 then
      return object()
    elseif c == 91 then
      return array()
    elseif c == 34 then
      return str()
    elseif string.sub(text, at, at + 3) == "true" then
      at += 4
      return true
    elseif string.sub(text, at, at + 4) == "false" then
      at += 5
      return false
    elseif string.sub(text, at, at + 3) == "null" then
      at += 4
      return nil
    end
    local number = string.match(text, "^-?%d+%.?%d*[eE]?[+-]?%d*", at)
    local parsed = if number then tonumber(number) else nil
    if number == nil or parsed == nil then
      fail("what is not a value")
    end
    at += #(number :: string)
    return parsed
  end

  local out = value()
  skip()
  if at <= length then
    fail("more after the end")
  end
  return out
end

return Json
