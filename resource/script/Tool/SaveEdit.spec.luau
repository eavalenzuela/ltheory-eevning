--!strict
-- Tool/SaveEdit: what the save editor does to a game, and that what it
-- writes the game can go on from.

local Characters = require("@lt/Core/Character/Characters")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Market = require("@lt/Core/Assets/Market")
local Rng = require("@lt/Core/Kernel/Rng")
local SaveEdit = require("@lt/Tool/SaveEdit")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local suite = Test.Suite("SaveEdit")

local function game(): Core.Game
  local made = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  Core.Step(made)
  Core.TakeEvents(made)
  return made
end

-- The game written and read back, as the editor writes it.
local function again(edited: Core.Game): Core.Game
  local ok, why = SaveEdit.Check(edited)
  assert(ok, why)
  local data, length = Core.Save(edited)
  return assert((SaveEdit.Open(data, length)))
end

suite:Case("the pilot's wallet, skills, queue, standings and loyalty are set, and kept", function(t)
  local g = game()
  SaveEdit.SetWallet(g, 123456789.7)
  local skill = Skills.list[1].id
  table.insert(g.state.training, { skill = skill, level = 5 })
  SaveEdit.SetSkill(g, skill, 9)
  SaveEdit.SetSkill(g, "navigation", -1)
  local faction = Factions.list[1].id
  SaveEdit.SetStanding(g, faction, 12)
  SaveEdit.SetLoyalty(g, faction, 5000)
  local back = again(g)
  t.eq(back.state.wallet, 123456789)
  t.eq(back.state.skills[skill], Skills.MAX_LEVEL, "a level is no more than the most there is")
  for _, entry in back.state.training do
    t.ok(entry.skill ~= skill, "a queue to where the skill already is was left")
  end
  t.eq(back.state.skills.navigation, nil)
  t.eq(back.state.standings[faction], 10)
  t.eq(back.state.loyalty[faction], 5000)
  t.fails(function()
    SaveEdit.SetSkill(g, "no-such-skill", 1)
  end)
  SaveEdit.AllSkills(g, 4)
  for _, each in Skills.list do
    t.eq(g.state.skills[each.id], 4, each.id)
  end
  -- (to the character too, and taken down there as well)
  local character = Characters.New("pilot", "Pilot", "badge:1", 0)
  character.skills[skill] = 5
  local written = SaveEdit.CharacterOf(g, character)
  t.eq(written.skills[skill], 4)
  t.eq(character.skills[skill], 5, "the character read was changed")
  local text = Characters.Encode(written)
  t.eq((assert(Characters.Decode(text))).skills[skill], 4)
end)

suite:Case("items are given, counted and taken away; a ship is given, repaired and taken away", function(t)
  local g = game()
  local state = g.state
  local home = state.player.home
  local places = SaveEdit.Places(g)
  t.ok(#places >= 1, "nowhere listed")
  local item = SaveEdit.Give(g, "fuel.block", 30, home, "hangar")
  local hangar: SaveEdit.Place? = nil
  for _, place in SaveEdit.Places(g) do
    if place.holder == home and place.place == "hangar" then
      hangar = place
    end
  end
  local found = SaveEdit.Contents(g, (assert(hangar, "the home hangar is not listed")))
  t.ok(table.find(found, item) ~= nil, "what was given is not in the hangar")
  SaveEdit.SetQuantity(g, item.id, 7)
  t.eq(state.items[item.id].quantity, 7)
  SaveEdit.SetQuantity(g, item.id, 0)
  t.eq(state.items[item.id], nil)
  t.eq(table.find(state.itemIds, item.id), nil)
  -- A ship of another hull than the one flown.
  local hull = ""
  for _, type in Ships.list do
    if hull == "" and type.class == "cruiser" and type.id ~= state.ships[state.player.ship].type then
      hull = type.id
    end
  end
  local ship = SaveEdit.GiveShip(g, hull, home)
  ship.hullDamage = 50
  SaveEdit.Give(g, "fuel.block", 5, ship.id, "cargo")
  SaveEdit.Repair(g, ship.id)
  t.eq(ship.hullDamage, 0)
  local back = again(g)
  t.eq(back.state.ships[ship.id].type, hull)
  t.eq(SaveEdit.RemoveShip(g, state.player.ship), false, "the ship flown was taken away")
  t.eq(SaveEdit.RemoveShip(g, ship.id), true)
  for _, id in state.itemIds do
    t.ok(state.items[id].holder ~= ship.id, "what was aboard the ship taken away is left")
  end
  again(g)
end)

suite:Case("a system changes hands, its pressure is set, a market's stock is set, a wormhole is made over", function(t)
  local g = game()
  local state = g.state
  local system = 0
  for id, node in state.galaxy.systems do
    if system == 0 and not node.uncharted and not node.home and node.owner ~= "" then
      system = id
    end
  end
  local other = ""
  for _, faction in Factions.list do
    if other == "" and faction.kind == "human" and faction.id ~= state.galaxy.systems[system].owner then
      other = faction.id
    end
  end
  SaveEdit.SetOwner(g, system, other)
  t.eq({ state.galaxy.systems[system].owner, state.wars.claims[system] } :: { any }, { other, other } :: { any })
  SaveEdit.SetPressure(g, system, 3)
  t.eq(state.happenings.pressure[system], 1)
  -- (a market there is once somebody has asked of it)
  local home = state.player.home
  Market.For(state, home)
  local stock = SaveEdit.Stock(g, home)
  t.ok(#stock > 0, "the home market has nothing")
  SaveEdit.SetStock(g, home, stock[1].index, 99999)
  t.eq(SaveEdit.Stock(g, home)[1].stock, 99999)
  -- A wormhole, made over and closed.
  local charted = 0
  for id, node in state.galaxy.systems do
    if node.uncharted and charted == 0 then
      charted = id
    end
  end
  local hole = assert(Wormholes.Open(state, Core.Query.Player(g).system, charted, Rng.For(3), g.events, 1, true))
  hole.mass = 1000
  SaveEdit.SetWormholeSize(g, hole.id, 9)
  SaveEdit.FreshenWormhole(g, hole.id)
  t.eq({ hole.size, hole.mass, hole.closes } :: { any }, { #Wormholes.SIZES, nil, state.tick + Wormholes.LIFE[2] } :: { any })
  again(g)
  SaveEdit.CloseWormhole(g, hole.id)
  t.eq(state.wormholes[hole.id], nil)
  again(g)
end)

suite:Case("anything is set by its path, as the kind of value it was", function(t)
  local g = game()
  local root = g.state
  t.eq(SaveEdit.SetRaw(root, { "wallet" }, "42"), true)
  t.eq(root.wallet, 42)
  t.eq((SaveEdit.SetRaw(root, { "wallet" }, "lots")), false)
  t.eq((SaveEdit.SetRaw(root, { "peaceful" }, "no")), true)
  t.eq(root.peaceful, false)
  t.eq((SaveEdit.SetRaw(root, { "galaxy" }, "1")), false, "a table was set from text")
  t.eq((SaveEdit.SetRaw(root, {}, "1")), false)
  local keys = SaveEdit.Keys({ b = 1, [2] = 1, a = 1, [1] = 1 })
  t.eq(keys, { 1, 2, "a", "b" } :: { any })
  t.eq(SaveEdit.At(root, { "player", "home" }), root.player.home)
  -- (and what the game cannot go on from is not written)
  root.items = "broken" :: any
  t.eq((SaveEdit.Check(g)), false)
end)

return suite
