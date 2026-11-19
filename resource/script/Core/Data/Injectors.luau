--!strict
-- Training injectors: banked training time, as an item (the owner,
-- 2026-11-17: "the time-increase now does not speed up skill accrual
-- ... we need to have a replacement"; asked, they chose "Banked
-- training time", from station markets, loyalty stores, and loot and
-- exploration). A character trains by real time
-- only (Character/Characters); one of these, used, gives its queue so
-- many seconds at once, as if that much real time had gone by
-- (Character/Training's Inject). The three sizes, their seconds and
-- their prices are mine. (Since training went ten times faster,
-- 2026-11-18, an hour banked trains ten times what it did, at the same
-- price.)

local Injectors = {}

export type Injector = { id: string, name: string, seconds: number, price: number }

Injectors.list = {
  { id = "injector.training.hour", name = "Training Injector (1 hour)", seconds = 3600, price = 1500000 },
  { id = "injector.training.six", name = "Training Injector (6 hours)", seconds = 6 * 3600, price = 8000000 },
  { id = "injector.training.day", name = "Training Injector (24 hours)", seconds = 24 * 3600, price = 30000000 },
} :: { Injector }

Injectors.byId = {} :: { [string]: Injector }
for _, injector in Injectors.list do
  Injectors.byId[injector.id] = injector
end

-- How much room one takes, m3.
Injectors.VOLUME = 0.1

return Injectors
