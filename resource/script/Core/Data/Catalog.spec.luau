--!strict
-- How types are set out for reading (Data/Catalog).

local Catalog = require("@lt/Core/Data/Catalog")
local Factions = require("@lt/Core/Data/Factions")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Catalog")

suite:Case("a listing has every type of its category once, under headings", function(t)
  for _, category in Catalog.CATEGORIES do
    local wanted = 0
    for _, id in Types.Ids() do
      if Types.Info(id).category == category then
        wanted += 1
      end
    end
    local seen: { [string]: boolean } = {}
    local count = 0
    local headings: { [string]: boolean } = {}
    for index, entry in Catalog.Listing(category) do
      if entry.info then
        t.ok(not seen[entry.info.id], `{entry.info.id} is listed twice`)
        seen[entry.info.id] = true
        t.eq(entry.info.category, category)
        count += 1
      else
        local header = assert(entry.header, "an entry is a heading or a type")
        t.ok(not headings[header], `the heading '{header}' comes twice in {category}`)
        headings[header] = true
        local following = Catalog.Listing(category)[index + 1]
        t.ok(following ~= nil and following.info ~= nil, `the heading '{header}' has nothing under it`)
      end
    end
    t.eq(count, wanted, `{category}: types listed`)
  end
end)

suite:Case("hulls are set out by faction, frigate first", function(t)
  local listing = Catalog.Listing("ship")
  t.eq(listing[1].header, Factions.list[1].name)
  local first = assert(listing[2].info)
  t.eq(first.id, "frigate.akashi")
  local headings: { string } = {}
  for _, entry in listing do
    if entry.header then
      table.insert(headings, entry.header)
    end
  end
  -- the four human factions, then the hulls that are nobody's design
  t.eq(headings, { "Vessari", "Talmar", "Orun", "Kethri", "Civilian" })
end)

suite:Case("modules go by what they are, small before large", function(t)
  t.eq({ Catalog.Group("laser.beam.medium") }, { "Lasers", 1, 2 } :: { any })
  t.eq({ Catalog.Group("launcher.cruise") }, { "Launchers", 4, 3 } :: { any })
  t.ok(Catalog.Before("laser.pulse.small", "laser.pulse.medium"))
  t.ok(Catalog.Before("laser.pulse.large", "shield.extender.small"), "lasers come before shields")
  t.ok(Catalog.Before("shield.extender.small", "ammo.emp"), "modules come before charges")
  t.eq((Catalog.Group("missile.heavy.em")), "Heavy missiles")
  t.eq((Catalog.Group("blueprint.frigate.lancer")), "Hulls")
  t.eq((Catalog.Group("mineral.iron")), "")
end)

return suite
