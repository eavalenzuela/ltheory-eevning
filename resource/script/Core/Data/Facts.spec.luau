--!strict
-- The facts shown about each type of item (Data/Facts).

local Blueprints = require("@lt/Core/Data/Blueprints")
local Facts = require("@lt/Core/Data/Facts")
local Ships = require("@lt/Core/Data/Ships")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Facts")

local function find(sheet: Facts.Sheet, label: string): string?
  for _, section in sheet.sections do
    for _, row in section.rows do
      if row.label == label then
        return row.value
      end
    end
  end
  return nil
end

suite:Case("every type of item has something said about it", function(t)
  local count = 0
  for _, id in Types.Ids() do
    local sheet = Facts.Of(id)
    t.ok(sheet ~= nil, `nothing for {id}`)
    if sheet then
      count += 1
      t.ok(sheet.name ~= "" and sheet.kind ~= "", `{id} has no name or no kind`)
      t.ok(#sheet.sections > 0, `{id} has no sections`)
      for _, section in sheet.sections do
        t.ok(section.title ~= "" and #section.rows > 0, `{id}: an empty section '{section.title}'`)
        for _, row in section.rows do
          t.ok(row.label ~= "" and row.value ~= "", `{id}: an empty row in '{section.title}'`)
          t.ok(string.find(row.value, "nan", 1, true) == nil and string.find(row.value, "inf", 1, true) == nil,
            `{id}: '{row.label}' is not a number: {row.value}`)
        end
      end
    end
  end
  t.ok(count > 200, `only {count} types`)
end)

suite:Case("a copy of a blueprint has the blueprint's sheet, and says it is a copy", function(t)
  -- (no market lists a copy, so the case above does not come to them)
  for _, blueprint in Blueprints.list do
    local id = Blueprints.Copy(blueprint)
    t.eq(table.find(Types.Ids(), id), nil, id)
    local sheet = assert(Facts.Of(id), id)
    local whole = assert(Facts.Of(blueprint.id), blueprint.id)
    t.eq({ sheet.kind, whole.kind, #sheet.sections } :: { any }, { "Blueprint copy", "Blueprint", #whole.sections } :: { any }, id)
    t.ok(string.find(sheet.note, "No market deals in copies", 1, true) ~= nil, id)
    for index, section in sheet.sections do
      t.eq({ section.title, #section.rows } :: { any }, { whole.sections[index].title, #whole.sections[index].rows } :: { any }, id)
    end
  end
  local sheet = assert(Facts.Of("copy.ammo.emp"))
  t.eq({ sheet.name, find(sheet, "Small Shock Canister"), find(sheet, "Base price") } :: { any },
    { "Small Shock Canister Blueprint Copy", "100 a run", `{Types.Info("copy.ammo.emp").basePrice} cr a run` } :: { any })
end)

suite:Case("every hull has a sheet, the ones nobody sells too", function(t)
  for _, hull in Ships.list do
    local sheet = Facts.Of(hull.id)
    t.ok(sheet ~= nil, `nothing for {hull.id}`)
  end
  t.eq(Facts.Of("no.such.thing"), nil)
end)

suite:Case("a hull's sheet says what the data says", function(t)
  local hull = Ships.byId["frigate.battleaxe"]
  local sheet = assert(Facts.Of("frigate.battleaxe"))
  t.eq(sheet.kind, "Kethri frigate")
  t.eq(find(sheet, "Slots (high / mid / low)"), `{hull.highs} / {hull.mids} / {hull.lows}`)
  t.eq(find(sheet, "Top speed"), `{hull.maxVelocity} m/s`)
  t.ok(find(sheet, "Frigates") ~= nil, "it should say which skill flies it")
  t.ok(find(sheet, "Base price") ~= nil, "it is sold, so it has a price")
end)

suite:Case("a weapon's sheet gives its range, and a charge's its damage", function(t)
  local gun = assert(Facts.Of("autocannon.small"))
  t.eq(gun.kind, "Small turret")
  t.ok(find(gun, "Optimal range") ~= nil)
  t.eq(find(gun, "Takes"), "small projectile charges")
  local launcher = assert(Facts.Of("launcher.light"))
  t.eq(launcher.kind, "Small launcher")
  t.eq(find(launcher, "Range"), "its missile's")
  local missile = assert(Facts.Of("missile.light.kinetic"))
  t.ok(string.find(assert(find(missile, "Damage")), "kinetic", 1, true) ~= nil)
  t.ok(find(missile, "Range") ~= nil)
end)

suite:Case("a pirate hull says what it was made from and that nobody sells it", function(t)
  local pirate: Ships.ShipType? = nil
  for _, hull in Ships.list do
    if hull.donor then
      pirate = hull
      break
    end
  end
  local hull = assert(pirate, "no pirate hull in the data")
  local sheet = assert(Facts.Of(hull.id))
  t.ok(string.find(sheet.note, "Made over from", 1, true) ~= nil, sheet.note)
  t.ok(find(sheet, "Sold") ~= nil)
  t.eq(find(sheet, "Base price"), nil)
end)

return suite
