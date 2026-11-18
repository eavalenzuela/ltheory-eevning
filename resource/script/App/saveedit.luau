--!strict
-- The save editor (the owner, 2026-11-17: "let's build a save editor, so
-- I can tweak and test stuff"): a window of its own, run as
--
--   bin/launch saveedit
--
-- Down the left, the saved games in save/ (one a character, and "quick"
-- for a game nobody plays as). Pick one, change it on the pages at the
-- right, and Save:
--
--   Pilot           credits, every skill's level, the training queue,
--                   standing and loyalty points with each faction
--   Ships & items   every hangar and ship of the pilot's: what is in it,
--                   how many, taken away or given (any item, any hull)
--   World           systems (who holds one, its pirate pressure),
--                   structures (fuel, built at once), wormholes (size,
--                   made fresh, closed), markets (what a station holds)
--   Raw             anything else in the game, by its path of keys: a
--                   number, a word or a flag set where it is
--
-- The work is Tool/SaveEdit's. Nothing is written that the game could
-- not go on from (SaveEdit.Check), and the first time a save is written
-- over in a run of the editor, what it was is kept beside it
-- (state.bin.bak, and the character's file .bak). Skills and the queue
-- are written to the pilot's character as well, or a level taken down
-- would come back on load. Close the game before editing its save: it
-- saves when it docks, and would write over the editor's.
--
-- For a script: _G.SaveEdit (Dir, Make, Open, Tab, World, Save, Status,
-- Game, Press, Type).

local AppShell = require("@lt/AppShell")
local Characters = require("@lt/Core/Character/Characters")
local Components = require("@lt/Widget/Components")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Im = require("@lt/Game/UI/Im")
local SaveEdit = require("@lt/Tool/SaveEdit")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Wars = require("@lt/Core/Strategic/Wars")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local ROW = 24
local GAP = 12

type Slot = { slot: string, meta: { [string]: string } }

local function readMeta(path: string): { [string]: string }
  local meta: { [string]: string } = {}
  local data = Host.ReadFile(path)
  if data then
    for line in string.gmatch(buffer.tostring(data), "[^\n]+") do
      local key, value = string.match(line, "^([^=]+)=(.*)$")
      if key and value then
        meta[key] = value
      end
    end
  end
  return meta
end

-- Credits as they are read: 1,234,567.
local function credits(n: number): string
  local s = tostring(math.floor(n))
  local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
  return (string.gsub(out, "^(%-?),", "%1"))
end

local function short(v: any): string
  local kind = type(v)
  if kind == "table" then
    local n = 0
    for _ in v do
      n += 1
    end
    return `\{{n}\}`
  elseif kind == "string" then
    return `"{v}"`
  end
  return tostring(v)
end

return AppShell.Create(function(): Widget
  local dir = "save"
  local slots: { Slot } = {}
  local slot: string? = nil
  local game: Core.Game? = nil
  local dirty = false
  local pilotTouched = false     -- skills or queue changed: the character is written too
  local backedUp: { [string]: boolean } = {}
  local status, statusBad = "Pick a saved game on the left.", false
  local discard: string? = nil   -- a slot clicked while there are changes: click it again to drop them
  local tab = "pilot"
  local world = "systems"
  local placeAt = 1
  local systemAt = 0
  local marketAt = 0
  local rawPath: { SaveEdit.Key } = {}
  local search = { give = "", systems = "", raw = "" }
  local giveType = ""
  local giveCount = 1
  local drafts: { [string]: string } = {}

  local function say(text: string, bad: boolean?)
    status, statusBad = text, bad == true
  end

  local function refresh()
    table.clear(slots)
    for _, name in Host.ListDir(dir) do
      if string.sub(name, -1) == "/" then
        local s = string.sub(name, 1, -2)
        if Host.Exists(`{dir}/{s}/state.bin`) then
          table.insert(slots, { slot = s, meta = readMeta(`{dir}/{s}/meta.txt`) })
        end
      end
    end
  end

  local function open(s: string): boolean
    local data = Host.ReadFile(`{dir}/{s}/state.bin`)
    if data == nil then
      say(`No save in {dir}/{s}`, true)
      return false
    end
    local loaded, why = SaveEdit.Open(data)
    if loaded == nil then
      say(`Could not read {dir}/{s}: {why}`, true)
      return false
    end
    slot, game, dirty, pilotTouched, discard = s, loaded, false, false, nil
    placeAt, systemAt, marketAt, rawPath = 1, 0, 0, {}
    table.clear(drafts)
    say(`Opened {dir}/{s}.`)
    return true
  end

  local function changed(pilot: boolean?)
    dirty = true
    if pilot then
      pilotTouched = true
    end
  end

  -- A copy of a file beside it, the first time it is written over.
  local function keep(path: string)
    if backedUp[path] then
      return
    end
    local data = Host.ReadFile(path)
    if data then
      Host.WriteFile(path .. ".bak", data)
    end
    backedUp[path] = true
  end

  local function write(): boolean
    local g = game
    if g == nil or slot == nil then
      return false
    end
    local ok, why = SaveEdit.Check(g)
    if not ok then
      say(`Not saved: {why}`, true)
      return false
    end
    local base = `{dir}/{slot}`
    keep(`{base}/state.bin`)
    local data, length = Core.Save(g)
    if not (Host.WriteFile(`{base}/state.tmp`, data, length) and Host.Rename(`{base}/state.tmp`, `{base}/state.bin`)) then
      say(`Could not write {base}/state.bin`, true)
      return false
    end
    -- (the list of saves says the credits)
    local meta = Host.ReadFile(`{base}/meta.txt`)
    if meta then
      local text = string.gsub(buffer.tostring(meta), "wallet=[^\n]*", `wallet={g.state.wallet}`)
      Host.WriteFile(`{base}/meta.txt`, text)
    end
    local also = ""
    local id = g.state.character
    if pilotTouched and id and id ~= "" then
      local path = `{dir}/characters/{id}.txt`
      local text = Host.ReadFile(path)
      local character = if text then Characters.Decode(buffer.tostring(text)) else nil
      if character then
        keep(path)
        local out = Characters.Encode(SaveEdit.CharacterOf(g, character))
        if Host.WriteFile(path .. ".tmp", out) and Host.Rename(path .. ".tmp", path) then
          also = `, and the character {character.name}`
        else
          also = `; the character's file could not be written`
        end
      end
    end
    dirty, pilotTouched = false, false
    refresh()
    say(`Saved {base}{also}. (What it was is kept as state.bin.bak.)`)
    return true
  end

  -- A field of a number, set when Return is pressed or it is left.
  local function numberField(name: string, value: number, x: number, y: number, w: number, apply: (number) -> ())
    local shown = drafts[name] or tostring(value)
    local now = Im.Words(name, shown, x, y, w, ROW, 20)
    if now ~= shown then
      drafts[name] = now
    end
    if drafts[name] and Im.Focus() ~= name then
      local typed = drafts[name]
      drafts[name] = nil
      local n = tonumber((string.gsub(typed, ",", "")))
      if n and n == n and math.abs(n) ~= math.huge then
        if n ~= value then
          apply(n)
        end
      else
        say(`"{typed}" is not a number`, true)
      end
    end
  end

  -- -------------------------------------------------------------------
  -- Pilot

  local function pilotPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    Im.Strong("CREDITS", x, y, 13, Theme.DIM)
    numberField("wallet", state.wallet, x, y + 20, 220, function(n)
      SaveEdit.SetWallet(g, n)
      changed()
    end)
    local bx = x + 230
    local ADD_AMOUNTS = { 1e6, 1e8, 1e9, 1e11 }
    for index, label in { "+1M", "+100M", "+1B", "+100B" } do
      if Im.Button(label, bx, y + 20, 70, ROW, true, `wallet{label}`) then
        SaveEdit.SetWallet(g, state.wallet + ADD_AMOUNTS[index])
        changed()
      end
      bx += 76
    end
    Im.Text(credits(state.wallet), bx + 10, y + 24, 15, Theme.TEXT)

    -- Skills, by group, in columns.
    local top = y + 64
    Im.Strong("SKILLS", x, top, 13, Theme.DIM)
    local qx = x + 80
    local SET_LEVELS = { 5, 4, 1, -1 }
    for index, label in { "All to 5", "All to 4", "All to 1", "As a new pilot" } do
      local wide = Im.StrongWidth(label, 13) + 24
      if Im.Button(label, qx, top - 4, wide, ROW, true, `skills:{label}`) then
        SaveEdit.AllSkills(g, SET_LEVELS[index])
        changed(true)
      end
      qx += wide + 6
    end
    Im.Text(`queue: {#state.training} level{if #state.training == 1 then "" else "s"}`, qx + 20, top, 14, Theme.DIM)
    if Im.Button("Clear queue", qx + 140, top - 4, 110, ROW, #state.training > 0, "skills:clear") then
      SaveEdit.ClearTraining(g)
      changed(true)
    end
    local columns = 4
    local colW = math.floor((w - 360) / columns)
    local cx, cy = x, top + 30
    local bottom = y + h
    local col = 0
    for _, group in Skills.GROUPS do
      local need = (#group.skills + 1) * (ROW - 2) + 8
      if cy + need > bottom and col < columns - 1 then
        col += 1
        cx, cy = x + col * colW, top + 30
      end
      Im.Strong(string.upper(group.name), cx, cy, 12, Theme.ACCENT)
      cy += ROW - 2
      for _, id in group.skills do
        local skill = Skills.byId[id]
        if skill and cy + ROW <= bottom then
          local level = state.skills[id] or -1
          Im.Text(skill.name, cx, cy + 3, 13, if level >= 0 then Theme.TEXT else Theme.FAINT)
          local px = cx + colW - 7 * 19 - 12
          for at = -1, Skills.MAX_LEVEL do
            local label = if at < 0 then "-" else tostring(at)
            local on = at == level
            if Im.Toggle(label, px, cy, 18, ROW - 4, on, `skill:{id}:{at}`) and not on then
              SaveEdit.SetSkill(g, id, at)
              changed(true)
            end
            px += 19
          end
          cy += ROW - 2
        end
      end
      cy += 8
    end

    -- Standings and loyalty points.
    local sx = x + w - 340
    Im.Strong("STANDING", sx, top, 13, Theme.DIM)
    Im.Strong("LOYALTY", sx + 240, top, 13, Theme.DIM)
    local sy = top + 30
    for _, faction in Factions.list do
      local standing = state.standings[faction.id] or 0
      Im.Text(faction.name, sx, sy + 3, 13, Theme.TEXT)
      local set = Im.Slider(`standing:{faction.id}`, math.floor(standing + 0.5), -10, 10, sx + 80, sy, 110, ROW - 4, true)
      if set ~= math.floor(standing + 0.5) then
        SaveEdit.SetStanding(g, faction.id, set)
        changed()
      end
      Im.TextRight(string.format("%.1f", standing), sx + 230, sy + 3, 13, Theme.DIM)
      numberField(`loyalty:{faction.id}`, state.loyalty[faction.id] or 0, sx + 240, sy, 100, function(n)
        SaveEdit.SetLoyalty(g, faction.id, n)
        changed()
      end)
      sy += ROW + 4
    end
  end

  -- -------------------------------------------------------------------
  -- Ships and items

  local function itemsPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    local places = SaveEdit.Places(g)
    placeAt = math.clamp(placeAt, 1, math.max(1, #places))
    -- Where: hangars and ships.
    local lw = 420
    Im.Strong("WHERE", x, y, 13, Theme.DIM)
    local visible = math.floor((h - 30) / ROW)
    local first = Im.Scroll("places", x, y + 24, lw, visible * ROW, #places, visible)
    for row = 1, math.min(visible, #places - first) do
      local index = first + row
      local ry = y + 24 + (row - 1) * ROW
      local _, click = Im.Row(x, ry, lw - 8, ROW, index == placeAt, `place:{index}`)
      if click then
        placeAt = index
      end
      Im.Text(places[index].label, x + 8, ry + 4, 13, Theme.TEXT)
    end
    local place = places[placeAt]
    if place == nil then
      return
    end
    -- What is there.
    local mx = x + lw + GAP
    local mw = w - lw - 360 - 2 * GAP
    Im.Strong(string.upper(place.label), mx, y, 13, Theme.DIM)
    local ty = y + 24
    if place.ship then
      local ship = state.ships[place.ship]
      if ship then
        Im.Text(`armour damage {math.floor(ship.armorDamage)}, hull damage {math.floor(ship.hullDamage)}`, mx, ty + 4, 13, Theme.DIM)
        if Im.Button("Repair", mx + 300, ty, 90, ROW, ship.armorDamage > 0 or ship.hullDamage > 0, "ship:repair") then
          SaveEdit.Repair(g, ship.id)
          changed()
        end
        Im.Tone("danger")
        if Im.Button("Remove ship", mx + 400, ty, 120, ROW, place.ship ~= state.player.ship, "ship:remove") then
          local ok, why = SaveEdit.RemoveShip(g, ship.id)
          if ok then
            changed()
            say(`Removed {ship.name}.`)
          else
            say(`Not removed: {why}`, true)
          end
        end
        ty += ROW + 8
      end
    end
    local items = SaveEdit.Contents(g, place)
    local rows = math.floor((y + h - ty) / ROW)
    local top = Im.Scroll("contents", mx, ty, mw, rows * ROW, #items, rows)
    for row = 1, math.min(rows, #items - top) do
      local item = items[top + row]
      local ry = ty + (row - 1) * ROW
      local info = Types.Get(item.type)
      Im.Text(if info then info.name else item.type, mx + 4, ry + 4, 13, Theme.TEXT)
      Im.Text(if item.slot > 0 then `{item.place} {item.slot}` else item.place, mx + mw - 330, ry + 4, 12, Theme.DIM)
      if item.slot == 0 then
        numberField(`qty:{item.id}`, item.quantity, mx + mw - 220, ry, 110, function(n)
          SaveEdit.SetQuantity(g, item.id, n)
          changed()
        end)
      end
      if Im.Button("Remove", mx + mw - 100, ry, 90, ROW - 2, true, `remove:{item.id}`) then
        SaveEdit.SetQuantity(g, item.id, 0)
        changed()
      end
    end
    if #items == 0 then
      Im.Text("nothing here", mx + 4, ty + 4, 13, Theme.FAINT)
    end
    -- Give.
    local gx = x + w - 360
    Im.Strong("GIVE", gx, y, 13, Theme.DIM)
    search.give = Im.Words("give:search", search.give, gx, y + 20, 360, ROW + 4, 40, "search items and hulls")
    local found: { string } = {}
    local words = string.lower(search.give)
    for _, id in Types.Ids() do
      local info = Types.Info(id)
      if words == "" or string.find(string.lower(info.name), words, 1, true) or string.find(id, words, 1, true) then
        table.insert(found, id)
      end
    end
    local listY = y + 56
    local listRows = math.floor((h - 56 - 4 * ROW) / ROW)
    local gfirst = Im.Scroll("give:list", gx, listY, 360, listRows * ROW, #found, listRows)
    for row = 1, math.min(listRows, #found - gfirst) do
      local id = found[gfirst + row]
      local ry = listY + (row - 1) * ROW
      local _, click = Im.Row(gx, ry, 352, ROW, id == giveType, `give:{id}`)
      if click then
        giveType = id
      end
      local info = Types.Info(id)
      Im.Text(info.name, gx + 6, ry + 4, 13, Theme.TEXT)
      Im.TextRight(info.category, gx + 346, ry + 5, 11, Theme.DIM)
    end
    local by = listY + listRows * ROW + 8
    local into: string = if place.ship then "cargo" else "hangar"
    Im.Text(if giveType ~= "" then Types.Info(giveType).name else "pick something", gx, by + 4, 13,
      if giveType ~= "" then Theme.TEXT else Theme.FAINT)
    numberField("give:count", giveCount, gx, by + ROW + 4, 100, function(n)
      giveCount = math.max(1, math.floor(n))
    end)
    Im.Tone("primary")
    if Im.Button(`Give into {into}`, gx + 110, by + ROW + 4, 160, ROW, giveType ~= "", "give") then
      SaveEdit.Give(g, giveType, giveCount, place.holder, into)
      changed()
      say(`Gave {giveCount} {Types.Info(giveType).name}.`)
    end
    -- (a hull, assembled, at the station the place is at)
    local station = if place.ship then (state.ships[place.ship] and state.ships[place.ship].docked or 0) else place.holder
    local hull = Ships.byId[giveType]
    if hull then
      if Im.Button("Give assembled ship", gx, by + 2 * ROW + 10, 200, ROW, station ~= 0, "give:ship") then
        local ship = SaveEdit.GiveShip(g, giveType, station)
        changed()
        say(`Gave a {hull.name}, docked at {SaveEdit.PlaceName(g, station)} (ship {ship.id}).`)
      end
    end
  end

  -- -------------------------------------------------------------------
  -- World

  local OWNERS: { string } = { "" }
  for _, faction in Factions.list do
    table.insert(OWNERS, faction.id)
  end
  table.insert(OWNERS, Wars.PILOT)
  local function ownerName(id: string): string
    if id == "" then
      return "nobody"
    elseif id == Wars.PILOT then
      return "the pilot"
    end
    local faction = Factions.byId[id]
    return if faction then faction.name else id
  end

  local function systemsPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    search.systems = Im.Words("systems:search", search.systems, x, y, 360, ROW + 4, 40, "search systems, or an owner")
    local words = string.lower(search.systems)
    local found: { number } = {}
    for id, node in state.galaxy.systems do
      if not node.uncharted and (words == "" or string.find(string.lower(node.name), words, 1, true)
        or string.find(string.lower(ownerName(node.owner)), words, 1, true)) then
        table.insert(found, id)
      end
    end
    local listY = y + 36
    local rows = math.floor((h - 36) / ROW)
    local first = Im.Scroll("systems", x, listY, 560, rows * ROW, #found, rows)
    for row = 1, math.min(rows, #found - first) do
      local id = found[first + row]
      local node = state.galaxy.systems[id]
      local ry = listY + (row - 1) * ROW
      local _, click = Im.Row(x, ry, 552, ROW, id == systemAt, `system:{id}`)
      if click then
        systemAt = id
      end
      Im.Text(node.name, x + 6, ry + 4, 13, Theme.TEXT)
      Im.Text(ownerName(node.owner), x + 220, ry + 4, 13, Theme.DIM)
      Im.TextRight(string.format("%.1f", node.security), x + 440, ry + 4, 13, Theme.DIM)
      Im.TextRight(string.format("%.2f", state.happenings.pressure[id] or 0), x + 540, ry + 4, 13, Theme.DIM)
    end
    Im.Text(`{#found} systems   (name, owner, security, pirate pressure)`, x + 380, y + 6, 13, Theme.FAINT)
    local node = state.galaxy.systems[systemAt]
    if node == nil then
      return
    end
    local dx = x + 600
    Im.Strong(string.upper(node.name), dx, listY, 15, Theme.TEXT)
    Im.Text("held by", dx, listY + 32, 13, Theme.DIM)
    local oy = listY + 52
    for _, owner in OWNERS do
      local on = node.owner == owner
      if Im.Toggle(ownerName(owner), dx, oy, 160, ROW, on, `owner:{owner}`) and not on then
        SaveEdit.SetOwner(g, systemAt, owner)
        changed()
      end
      oy += ROW + 4
    end
    Im.Text("pirate pressure, in hundredths", dx + 200, listY + 32, 13, Theme.DIM)
    local pressure = math.floor((state.happenings.pressure[systemAt] or 0) * 100 + 0.5)
    local set = Im.Slider("pressure", pressure, 0, 100, dx + 200, listY + 52, 260, ROW, true)
    if set ~= pressure then
      SaveEdit.SetPressure(g, systemAt, set / 100)
      changed()
    end
  end

  local function structuresPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    if #state.starbaseIds == 0 then
      Im.Text("no structures anchored", x, y + 4, 14, Theme.FAINT)
      return
    end
    Im.Text("structure, owner, fuel blocks", x, y, 13, Theme.FAINT)
    local ry = y + 28
    for _, id in state.starbaseIds do
      local starbase = state.starbases[id]
      if ry + ROW > y + h then
        break
      end
      Im.Text(SaveEdit.StructureName(g, id), x, ry + 4, 13, Theme.TEXT)
      Im.Text(starbase.owner, x + 520, ry + 4, 13, Theme.DIM)
      numberField(`fuel:{id}`, starbase.fuel, x + 620, ry, 110, function(n)
        SaveEdit.SetFuel(g, id, n)
        changed()
      end)
      local building = starbase.ready > state.tick
      for _, module in starbase.modules do
        building = building or module.ready > state.tick
      end
      if Im.Button("Finish building", x + 740, ry, 150, ROW - 2, building, `finish:{id}`) then
        SaveEdit.FinishBuilding(g, id)
        changed()
      end
      ry += ROW + 2
    end
  end

  local function wormholesPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    if #state.wormholeIds == 0 then
      Im.Text("no wormholes open", x, y + 4, 14, Theme.FAINT)
      return
    end
    Im.Text("wormhole, where, leads to, hours left, mass", x, y, 13, Theme.FAINT)
    local ry = y + 28
    for _, id in table.clone(state.wormholeIds) do
      local hole = state.wormholes[id]
      if hole == nil or ry + ROW > y + h then
        continue
      end
      local from, to = state.galaxy.systems[hole.from], state.galaxy.systems[hole.to]
      Im.Text(hole.code, x, ry + 4, 13, Theme.TEXT)
      Im.Text(from and from.name or "?", x + 90, ry + 4, 13, Theme.DIM)
      Im.Text(`{to and to.name or "?"}{if to and to.uncharted then ` (depth {to.depth})` else ""}`, x + 250, ry + 4, 13, Theme.DIM)
      Im.TextRight(string.format("%.1f", math.max(0, hole.closes - state.tick) / 3600), x + 470, ry + 4, 13, Theme.DIM)
      Im.TextRight(Wormholes.Strain(hole), x + 560, ry + 4, 13, Theme.DIM)
      local sx = x + 580
      for size, name in Wormholes.SIZE_NAMES do
        local on = hole.size == size
        if Im.Toggle(name, sx, ry, 76, ROW - 2, on, `hole:{id}:{name}`) and not on then
          SaveEdit.SetWormholeSize(g, id, size)
          changed()
        end
        sx += 80
      end
      if Im.Button("Fresh", sx + 10, ry, 70, ROW - 2, true, `hole:{id}:fresh`) then
        SaveEdit.FreshenWormhole(g, id)
        changed()
      end
      Im.Tone("danger")
      if Im.Button("Close", sx + 86, ry, 70, ROW - 2, true, `hole:{id}:close`) then
        SaveEdit.CloseWormhole(g, id)
        changed()
      end
      ry += ROW + 2
    end
  end

  local function marketsPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local state = g.state
    if #state.marketIds == 0 then
      Im.Text("no markets yet: a station's is made when somebody first trades there", x, y + 4, 14, Theme.FAINT)
      return
    end
    local rows = math.floor(h / ROW)
    local first = Im.Scroll("markets", x, y, 360, rows * ROW, #state.marketIds, rows)
    for row = 1, math.min(rows, #state.marketIds - first) do
      local id = state.marketIds[first + row]
      local ry = y + (row - 1) * ROW
      local _, click = Im.Row(x, ry, 352, ROW, id == marketAt, `market:{id}`)
      if click then
        marketAt = id
      end
      Im.Text(SaveEdit.PlaceName(g, id), x + 6, ry + 4, 13, Theme.TEXT)
    end
    local stock = SaveEdit.Stock(g, marketAt)
    if #stock == 0 then
      return
    end
    local sx = x + 380
    Im.Text("good, holds, holds when left alone", sx, y, 13, Theme.FAINT)
    local srows = math.floor((h - 24) / ROW)
    local sfirst = Im.Scroll("stock", sx, y + 24, 600, srows * ROW, #stock, srows)
    for row = 1, math.min(srows, #stock - sfirst) do
      local good = stock[sfirst + row]
      local ry = y + 24 + (row - 1) * ROW
      local info = Types.Get(good.type)
      Im.Text(if info then info.name else good.type, sx, ry + 4, 13, Theme.TEXT)
      numberField(`stock:{marketAt}:{good.index}`, math.floor(good.stock), sx + 330, ry, 120, function(n)
        SaveEdit.SetStock(g, marketAt, good.index, n)
        changed()
      end)
      Im.TextRight(tostring(math.floor(good.target)), sx + 560, ry + 4, 13, Theme.DIM)
    end
  end

  local function worldPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local tx = x
    for _, page in { { "systems", "Systems" }, { "structures", "Structures" }, { "wormholes", "Wormholes" }, { "markets", "Markets" } } do
      local clicked, wide = Im.Tab(page[2], tx, y, 30, world == page[1], `world:{page[1]}`)
      if clicked then
        world = page[1]
      end
      tx += wide + 4
    end
    local top, rest = y + 44, h - 44
    if world == "systems" then
      systemsPage(g, x, top, w, rest)
    elseif world == "structures" then
      structuresPage(g, x, top, w, rest)
    elseif world == "wormholes" then
      wormholesPage(g, x, top, w, rest)
    else
      marketsPage(g, x, top, w, rest)
    end
  end

  -- -------------------------------------------------------------------
  -- Raw

  local function rawPage(g: Core.Game, x: number, y: number, w: number, h: number)
    local root: any = g.state
    local at = SaveEdit.At(root, rawPath)
    if type(at) ~= "table" then
      rawPath = {}
      at = root
    end
    -- The path, each step of it a way back.
    local px = x
    if Im.Link("state", px, y, 15, Theme.ACCENT, "raw:up:0") then
      rawPath = {}
    end
    px += Im.TextWidth("state", 15)
    for index, key in rawPath do
      local label = ` / {key}`
      if Im.Link(label, px, y, 15, Theme.ACCENT, `raw:up:{index}`) then
        rawPath = table.move(rawPath, 1, index, 1, {})
      end
      px += Im.TextWidth(label, 15)
    end
    search.raw = Im.Words("raw:search", search.raw, x + w - 300, y - 4, 300, ROW + 4, 40, "filter keys")
    local keys = SaveEdit.Keys(at)
    if search.raw ~= "" then
      local words = string.lower(search.raw)
      local kept: { SaveEdit.Key } = {}
      for _, key in keys do
        if string.find(string.lower(tostring(key)), words, 1, true) then
          table.insert(kept, key)
        end
      end
      keys = kept
    end
    local listY = y + 32
    local rows = math.floor((h - 32) / ROW)
    local first = Im.Scroll("raw", x, listY, w, rows * ROW, #keys, rows)
    for row = 1, math.min(rows, #keys - first) do
      local key = keys[first + row]
      local value = at[key]
      local ry = listY + (row - 1) * ROW
      Im.Text(tostring(key), x + 6, ry + 4, 13, Theme.TEXT)
      if type(value) == "table" then
        if Im.Link(short(value) .. "  >", x + 300, ry + 4, 13, Theme.ACCENT, `raw:in:{key}`) then
          table.insert(rawPath, key)
          Im.ScrollTo("raw", 0)
        end
      else
        local path = table.clone(rawPath)
        table.insert(path, key)
        local name = `raw:{table.concat(path :: { any }, "/")}`
        local shown = drafts[name] or tostring(value)
        local now = Im.Words(name, shown, x + 300, ry, math.min(500, w - 300), ROW - 2, 60)
        if now ~= shown then
          drafts[name] = now
        end
        if drafts[name] and Im.Focus() ~= name then
          local typed = drafts[name]
          drafts[name] = nil
          if typed ~= tostring(value) then
            local ok, why = SaveEdit.SetRaw(root, path, typed)
            if ok then
              changed(rawPath[1] == "skills" or rawPath[1] == "training")
              say(`Set {table.concat(path :: { any }, " / ")} to {typed}.`)
            else
              say(`Not set: {why}`, true)
            end
          end
        end
        Im.Text(type(value), x + math.min(500, w - 300) + 310, ry + 4, 12, Theme.FAINT)
      end
    end
  end

  -- -------------------------------------------------------------------
  -- The window

  local PAGES = { { "pilot", "Pilot" }, { "items", "Ships & items" }, { "world", "World" }, { "raw", "Raw" } }

  local function draw(w: Widget)
    Im.Begin()
    local was = Im.Plain(true)
    local W, H = w.size.x / Theme.scale, w.size.y / Theme.scale
    Im.Flat(0, 0, W, H, Theme.PANEL, 1)
    -- The saves.
    local lw = 300
    Im.Flat(0, 0, lw, H, Theme.RAISED, 1)
    Im.Strong("SAVED GAMES", GAP, GAP + 4, 13, Theme.DIM)
    Im.Text(dir .. "/", GAP, GAP + 24, 12, Theme.FAINT)
    if Im.Button("Refresh", lw - 90, GAP, 78, ROW, true, "refresh") then
      refresh()
    end
    local sy = GAP + 48
    for _, each in slots do
      local meta = each.meta
      local _, click = Im.Row(0, sy, lw, 58, each.slot == slot, `slot:{each.slot}`)
      if click then
        if dirty and each.slot ~= slot and discard ~= each.slot then
          discard = each.slot
          say(`There are changes not saved. Click {each.slot} again to drop them.`, true)
        elseif each.slot ~= slot or discard == each.slot then
          open(each.slot)
        end
      end
      local who = if meta.pilot and meta.pilot ~= "" then meta.pilot else each.slot
      Im.Strong(who, GAP, sy + 6, 14, Theme.TEXT)
      Im.Text(`{meta.ship or "?"} in {meta.system or "?"}`, GAP, sy + 24, 12, Theme.DIM)
      Im.Text(`{credits(tonumber(meta.wallet) or 0)} cr   {each.slot}`, GAP, sy + 40, 12, Theme.FAINT)
      sy += 62
    end
    if #slots == 0 then
      Im.Text("no saved games here", GAP, sy, 13, Theme.FAINT)
    end
    -- The top: what is open, and saving it.
    local x = lw + 2 * GAP
    local cw = W - x - 2 * GAP
    local g = game
    if g then
      Im.Strong(`{slot}{if dirty then "  (changed)" else ""}`, x, GAP + 4, 16, if dirty then Theme.CAUTION else Theme.TEXT)
      Im.Tone("primary")
      if Im.Button("Save", W - 2 * GAP - 200, GAP, 96, ROW + 4, dirty, "save") then
        write()
      end
      if Im.Button("Revert", W - 2 * GAP - 96, GAP, 96, ROW + 4, dirty, "revert") and slot then
        open(slot)
        say("Changes dropped.")
      end
    end
    Im.Text(status, x, GAP + 36, 13, if statusBad then Theme.BAD else Theme.DIM)
    if g == nil then
      Im.Text("Close the game before editing its save: it saves when it docks.", x, GAP + 60, 13, Theme.FAINT)
      Im.Plain(was)
      return
    end
    local tx = x
    for _, page in PAGES do
      local clicked, wide = Im.Tab(page[2], tx, GAP + 62, 32, tab == page[1], `tab:{page[1]}`)
      if clicked then
        tab = page[1]
      end
      tx += wide + 4
    end
    local top = GAP + 110
    local ch = H - top - GAP
    if tab == "pilot" then
      pilotPage(g, x, top, cw, ch)
    elseif tab == "items" then
      itemsPage(g, x, top, cw, ch)
    elseif tab == "world" then
      worldPage(g, x, top, cw, ch)
    else
      rawPage(g, x, top, cw, ch)
    end
    Im.Plain(was)
  end

  refresh()

  -- For a script (test/scenario/saveedit.txt).
  _G.SaveEdit = {
    -- Edit the saves in another folder (a script's own).
    Dir = function(path: string)
      dir = path
      local made = ""
      for _, part in string.split(path, "/") do
        made = if made == "" then part else `{made}/{part}`
        Host.MakeDir(made)
      end
      refresh()
    end,
    -- A new game saved in the folder, as a slot.
    Make = function(name: string): boolean
      local made = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true, starter = true })
      Core.Step(made)
      local data, length = Core.Save(made)
      local ok = Host.MakeDir(`{dir}/{name}`) and Host.WriteFile(`{dir}/{name}/state.bin`, data, length)
        and Host.WriteFile(`{dir}/{name}/meta.txt`, `system=home\nship=a ship\nwallet={made.state.wallet}\npilot={name}\n`)
      refresh()
      return ok
    end,
    Open = function(name: string): boolean
      return open(name)
    end,
    Tab = function(name: string)
      tab = name
    end,
    World = function(name: string)
      world = name
    end,
    Save = function(): boolean
      return write()
    end,
    Status = function(): (string, boolean, boolean)
      return status, statusBad, dirty
    end,
    Game = function(): Core.Game?
      return game
    end,
    -- A button or row pressed by its name, and words typed into a field.
    Press = function(name: string): boolean
      return Im.Press(name)
    end,
    Type = function(name: string, text: string)
      Im.Say(name, text)
    end,
  }

  local hud = Components.Expand(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      draw(w)
    end,
  }))
  return hud
end)
