--!strict
-- Components: the middle of manufacture. Minerals are made into these,
-- and these (with more minerals) into modules and hulls. A hull is
-- plating on a frame around a reactor; nobody builds one straight from
-- ore.
--
-- A unit is small (a plate, a board, a cell), so that even a cheap
-- module takes several and a hull takes thousands. 'mix' is how a
-- component's material cost is split between minerals.
-- (Planetary materials join these recipes when planets are worked.)

export type Component = {
  id: string,
  name: string,
  volume: number,       -- m3 per unit
  basePrice: number,
  mix: { [string]: number },
}

local Components = {}

Components.list = {
  { id = "component.plating", name = "Hull Plating", volume = 1, basePrice = 100,
    mix = { ["mineral.iron"] = 0.8, ["mineral.titanium"] = 0.2 } },
  { id = "component.frame", name = "Structural Frame", volume = 2, basePrice = 300,
    mix = { ["mineral.iron"] = 0.6, ["mineral.titanium"] = 0.4 } },
  { id = "component.thruster", name = "Thruster Assembly", volume = 2, basePrice = 400,
    mix = { ["mineral.iron"] = 0.5, ["mineral.copper"] = 0.5 } },
  { id = "component.electronics", name = "Electronics", volume = 0.5, basePrice = 300,
    mix = { ["mineral.silicon"] = 0.6, ["mineral.copper"] = 0.4 } },
  { id = "component.capacitor", name = "Capacitor Cell", volume = 0.5, basePrice = 250,
    mix = { ["mineral.copper"] = 0.6, ["mineral.silicon"] = 0.4 } },
  { id = "component.weapon", name = "Weapon Assembly", volume = 1, basePrice = 500,
    mix = { ["mineral.iron"] = 0.5, ["mineral.copper"] = 0.3, ["mineral.titanium"] = 0.2 } },
  { id = "component.emitter", name = "Shield Emitter", volume = 1, basePrice = 600,
    mix = { ["mineral.silicon"] = 0.4, ["mineral.copper"] = 0.3, ["mineral.titanium"] = 0.3 } },
  { id = "component.reactor", name = "Reactor Core", volume = 4, basePrice = 1500,
    mix = { ["mineral.copper"] = 0.4, ["mineral.titanium"] = 0.4, ["mineral.cobalt"] = 0.2 } },
} :: { Component }

Components.byId = {} :: { [string]: Component }
for _, component in Components.list do
  Components.byId[component.id] = component
end

-- What a hull is made of, as shares of the part of its cost that goes
-- on components.
Components.HULL = {
  { "component.plating", 0.30 }, { "component.frame", 0.20 }, { "component.reactor", 0.15 }, { "component.thruster", 0.15 },
  { "component.electronics", 0.10 }, { "component.emitter", 0.05 }, { "component.capacitor", 0.05 },
} :: { { any } }

return Components
