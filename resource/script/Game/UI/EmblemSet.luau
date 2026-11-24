--!strict
-- The factions' emblems that are in the game (resource/texture/factions),
-- written by script/artgen emblems: do not edit by hand. A faction's
-- 'accent' says whether its icon has a third layer.

return {
  sizes = { 24, 32, 48, 64, 128 },
  factions = {
    drowned = { accent = false },
    kethri = { accent = false },
    nimia = { accent = false },
    orun = { accent = false },
    talmar = { accent = false },
    unbound = { accent = true },
    vail = { accent = false },
    vessari = { accent = false },
  } :: { [string]: { accent: boolean } },
}
