--!strict
-- A shape from a file, by what kind of file its name says it is: a
-- Wavefront .obj (with the .mtl beside it, if there is one) or a binary
-- glTF .glb. Nil and why, if it cannot be read.

local Glb = require("@lt/Tool/Mesh/Glb")
local Obj = require("@lt/Tool/Mesh/Obj")
local Shape = require("@lt/Tool/Mesh/Shape")

local File = {}

function File.Read(path: string): (Shape.Shape?, string?)
  local data = Host.ReadFile(path)
  if data == nil then
    return nil, `there is no {path}`
  end
  local kind = string.lower(string.match(path, "%.([%w]+)$") or "")
  local ok, result: any
  if kind == "obj" then
    local materials = Host.ReadFile((string.gsub(path, "%.[%w]+$", ".mtl")))
    ok, result = pcall(Obj.Parse, buffer.tostring(data), if materials then buffer.tostring(materials) else nil)
  elseif kind == "glb" then
    ok, result = pcall(Glb.Parse, data)
  else
    return nil, `{path} is not a kind of file that is read: .obj or .glb`
  end
  if not ok then
    return nil, `{path}: {tostring(result)}`
  end
  return result, nil
end

return File
