--!strict
-- How much ore is left in each asteroid. A rock is whole until someone
-- mines it; six hours after mining began it is whole again (the belt has
-- "grown back"), so a pilot who strips a belt has somewhere else to be.
--
-- A cloud of gas (Data/Ores) is a rock to this: a thing of a system's
-- description of the kind "asteroid", whose variety is a gas and not an
-- ore, with what a cloud of its size holds.

local Ores = require("@lt/Core/Data/Ores")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Mining = {}

-- Ticks after mining began on a rock before it is whole again.
Mining.REGROW = 21600

-- Whether a thing of a system's description is a cloud of gas, for a
-- harvester; and whether it is a rock, for a laser.
function Mining.Cloud(object: System.Object?): boolean
  return object ~= nil and object.kind == "asteroid" and Ores.gasById[object.variety] ~= nil
end

function Mining.Rock(object: System.Object?): boolean
  return object ~= nil and object.kind == "asteroid" and Ores.gasById[object.variety] == nil and not Ores.Ice(object.variety)
end

-- An ice chunk: what an ice harvester cuts, and nothing else does.
function Mining.Ice(object: System.Object?): boolean
  return object ~= nil and object.kind == "asteroid" and Ores.Ice(object.variety)
end

-- Units of ore left in an asteroid.
function Mining.Left(state: State.State, rock: System.Object): number
  local mined = state.rocks[rock.id]
  return if mined then mined.left else Ores.Units(rock.variety, rock.radius)
end

-- Take up to 'units' out of an asteroid; returns how many came.
function Mining.Take(state: State.State, rock: System.Object, units: number): number
  local mined = state.rocks[rock.id]
  if mined == nil then
    mined = { left = Ores.Units(rock.variety, rock.radius), since = state.tick }
    state.rocks[rock.id] = mined
    -- keep the id list ascending
    local at = #state.rockIds + 1
    while at > 1 and state.rockIds[at - 1] > rock.id do
      at -= 1
    end
    table.insert(state.rockIds, at, rock.id)
  end
  local taken = math.min(units, mined.left)
  mined.left -= taken
  return taken
end

-- Rocks whose time has come grow back.
function Mining.Step(state: State.State)
  for index = #state.rockIds, 1, -1 do
    local id = state.rockIds[index]
    if state.tick - state.rocks[id].since >= Mining.REGROW then
      state.rocks[id] = nil
      table.remove(state.rockIds, index)
    end
  end
end

return Mining
