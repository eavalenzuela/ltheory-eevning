--!strict
-- The balance report: every hull there is, on the same standard fit
-- (Core/Fits: its faction's guns on every hardpoint, and a plain tank),
-- flown by a pilot with no skills, with what that comes to: how much it
-- takes to destroy, what it does, whether its capacitor holds, how it
-- moves and what it costs. And what is out of line: a hull that cannot
-- carry its own weapons, or has not the CPU or the powergrid for a
-- plain tank beside them; a plain hull that does far more or far less
-- than the plain hulls of its class, or whose capacitor runs dry far
-- sooner than theirs; and hulls that are the same as one another in
-- everything the rules count. (A tech 2 hull, a combat hauler and the
-- like are meant to be out of line with the plain hulls: they are
-- listed, and not flagged for it.)
--
--   bin/ltcore Tool/balance [--out DIR]
--
-- Prints the flags, and a line a hull. With --out DIR, writes
-- DIR/balance.csv and DIR/balance.html too (script/balance does, into
-- cache/balance). Nothing here decides anything about a hull: it reads
-- the data and the rules and says what they come to.
--
-- (The standard fit is nobody's recommended fit. It is the same recipe
-- for every hull, which is what makes two hulls' figures comparable.)

local Attributes = require("@lt/Core/Attributes")
local Factions = require("@lt/Core/Data/Factions")
local Fits = require("@lt/Core/Fits")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")

-- How far from the middle of its class a hull's figure may be before it
-- is said: four tenths, more or less.
local OUT = 0.4
-- A capacitor that is dry in under a minute with everything running is
-- said, and one that lasts less than this share of what the middle of
-- its class does. (Nearly every hull's runs dry in a few minutes on
-- this fit, with nothing ever switched off: that it does is not news.)
local DRY = 60
local SOON = 0.6

export type Row = {
  id: string, name: string, faction: string, class: string, tech: number, plain: boolean,
  what: string,           -- what it is beside a hull of its class ("black ops", "mends"), or ""
  holds: string,          -- what holds it has beside its cargo hold, for telling two hulls apart
  price: number,
  slots: string, hardpoints: string,
  weapons: number, wanted: number, fitted: number, refused: { Fits.Refused },
  cpu: number, cpuMax: number, powergrid: number, powergridMax: number,
  shield: number, armor: number, hull: number, ehp: number,
  mend: number,           -- HP a second it gets back by itself (a shield at its best, and a hull that mends)
  repair: number,         -- and with its repairer running
  dps: number, volley: number, range: number,
  capacitor: number, recharge: number, use: number, lasts: number,   -- 'lasts' is math.huge for one that holds
  speed: number, burn: number, align: number, warp: number,
  signature: number, lock: number, scan: number, targets: number, cargo: number,
  flags: { string },
}

local ORDER: { string } = table.clone(Factions.CLASSES)
table.insert(ORDER, "ultracapital")
table.insert(ORDER, "barge")
table.insert(ORDER, "freighter")

local function mean(stats: Attributes.Stats, layer: string): number
  local sum = 0
  for index = 1, 4 do
    sum += stats[`{layer}Resonance.{index}`]
  end
  return sum / 4
end

local function whatOf(hull: Ships.ShipType): string
  local said: { string } = {}
  if hull.role then
    table.insert(said, hull.role)
  end
  if hull.cloak then
    table.insert(said, "own cloak")
  end
  if hull.stealth then
    table.insert(said, "black ops")
  end
  if hull.explorer then
    table.insert(said, "explorer")
  end
  if hull.jump then
    table.insert(said, "jump")
  end
  if (hull.armorMend or 0) > 0 then
    table.insert(said, "mends")
  end
  if hull.donor then
    table.insert(said, "made over")
  end
  return table.concat(said, ", ")
end

-- A hull on its standard fit.
local function measure(hull: Ships.ShipType): Row
  local on, off = Fits.Standard(hull)
  local wanted = #Fits.Weapons(hull)
  local idle: { Attributes.Fitted } = {}
  local burning: { Attributes.Fitted } = {}
  local cpu, powergrid = 0, 0
  for _, type in on do
    local module = Modules.byId[type]
    local tf, mw = Attributes.Needs(hull, module)
    cpu += tf
    powergrid += mw
    table.insert(idle, { type = type, running = false })
    -- (everything that runs, running: its afterburner, for how fast it goes)
    table.insert(burning, { type = type, running = module.boost ~= nil and module.cloak == nil })
  end
  local stats = Attributes.Ship(hull, idle, nil)
  local fast = Attributes.Ship(hull, burning, nil)

  -- What it does, and what that and the rest of it draw from the capacitor.
  local dps, volley, range, use, repair, weapons = 0, 0, 0, 0, 0, 0
  for _, type in on do
    local module = Modules.byId[type]
    -- (what stands on a hardpoint: a weapon, or a mining turret)
    weapons += if module.hardpoint ~= "" then 1 else 0
    if module.weapon then
      local weapon = Attributes.Weapon(idle, type, nil)
      -- (loaded with the kind of damage the hull leans to, where it leans to one, and doing more of it)
      local charge = Fits.Charge(type, hull)
      local loaded = if charge then Modules.chargeById[charge] else nil
      if loaded then
        local hit = 0
        for index = 1, 4 do
          hit += loaded.damage[index] * weapon.damageMultiplier * Ships.Dealt(hull, index)
        end
        volley += hit
        dps += hit / weapon.duration
        range = math.max(range, if weapon.optimal > 0 then weapon.optimal * loaded.rangeMultiplier + weapon.falloff
          else loaded.velocity * loaded.flightTime)
      end
      use += weapon.capacitor / weapon.duration
    elseif module.repair then
      repair += module.repair.amount / module.repair.duration
      use += module.repair.capacitor / module.repair.duration
    elseif module.boost and module.cloak == nil then
      use += (module.boostCapacitor or 0) / (module.boostDuration or 1)
    end
  end

  -- How long its capacitor lasts with all of that running, from full:
  -- a second at a time, for ten minutes.
  local level, lasts = stats.capacitor, math.huge
  for second = 1, 600 do
    level = Gunnery.Recharge(level, stats.capacitor, stats.capacitorRecharge, 1) - use
    if level <= 0 then
      lasts = second
      break
    end
  end

  local shield, armor, structure = stats.shield, stats.armor, stats.hull
  local ehp = (if shield > 0 then shield / mean(stats, "shield") else 0) + armor / mean(stats, "armor") + structure / mean(stats, "hull")
  local mend = (if shield > 0 then 2.5 * shield / stats.shieldRecharge else 0) + armor * stats.armorMend + structure * stats.hullMend
  local faction = Factions.byId[hull.lineage]
  return {
    id = hull.id, name = hull.name, faction = if faction then faction.name else "nobody's", class = hull.class,
    tech = hull.tech or 1, plain = hull.tech ~= 2 and hull.role == nil and hull.donor == nil and faction ~= nil,
    what = whatOf(hull), holds = `{hull.ore or 0}/{hull.shipbay or 0}/{hull.bay or 0}`, price = hull.basePrice,
    slots = `{hull.highs}/{hull.mids}/{hull.lows}`, hardpoints = `{hull.turrets}/{hull.launchers}`,
    weapons = weapons, wanted = wanted, fitted = #on, refused = off,
    cpu = cpu, cpuMax = stats.cpu, powergrid = powergrid, powergridMax = stats.powergrid,
    shield = shield, armor = armor, hull = structure, ehp = ehp, mend = mend, repair = repair,
    dps = dps, volley = volley, range = range,
    capacitor = stats.capacitor, recharge = stats.capacitorRecharge, use = use, lasts = lasts,
    speed = stats.maxVelocity, burn = fast.maxVelocity, align = stats.tau * 1.386, warp = stats.warpSpeed,
    signature = stats.signature, lock = stats.lockRange, scan = stats.scanResolution,
    targets = math.floor(stats.maxTargets + 1e-6), cargo = stats.cargo,
    flags = {},
  }
end

local function median(values: { number }): number
  table.sort(values)
  local count = #values
  if count == 0 then
    return 0
  end
  return if count % 2 == 1 then values[(count + 1) // 2] else (values[count // 2] + values[count // 2 + 1]) / 2
end

-- Every hull that is flown, measured and flagged, in the order of
-- classes and, within a class, of factions.
local function report(): { Row }
  local rows: { Row } = {}
  local rank: { [string]: number } = {}
  for index, class in ORDER do
    rank[class] = index
  end
  local place: { [string]: number } = {}
  for index, faction in Factions.list do
    place[faction.name] = index
  end
  for _, hull in Ships.list do
    if rank[hull.class] then
      table.insert(rows, measure(hull))
    end
  end
  table.sort(rows, function(a: Row, b: Row): boolean
    if a.class ~= b.class then
      return rank[a.class] < rank[b.class]
    elseif a.faction ~= b.faction then
      return (place[a.faction] or 99) < (place[b.faction] or 99)
    elseif a.tech ~= b.tech then
      return a.tech < b.tech
    end
    return a.id < b.id
  end)

  -- The middle of each class: of its plain hulls, the human factions'
  -- and the aliens' alike.
  local of: { [string]: { dps: { number }, ehp: { number }, speed: { number }, lasts: { number } } } = {}
  for _, row in rows do
    if row.plain then
      local class = of[row.class] or { dps = {}, ehp = {}, speed = {}, lasts = {} }
      of[row.class] = class
      table.insert(class.dps, row.dps)
      table.insert(class.ehp, row.ehp)
      table.insert(class.speed, row.speed)
      table.insert(class.lasts, math.min(row.lasts, 600))
    end
  end
  local middle: { [string]: { dps: number, ehp: number, speed: number, lasts: number, count: number } } = {}
  for class, values in of do
    middle[class] = { dps = median(values.dps), ehp = median(values.ehp), speed = median(values.speed), lasts = median(values.lasts),
      count = #values.dps }
  end

  local alike: { [string]: { Row } } = {}
  for _, row in rows do
    local flags = row.flags
    -- What of its standard fit it cannot carry.
    local guns, short = 0, 0
    local why = ""
    for _, refused in row.refused do
      if Modules.byId[refused.type] and Modules.byId[refused.type].hardpoint ~= "" then
        guns += 1
        why = refused.why
      elseif string.sub(refused.why, 1, 10) == "not enough" then
        -- (for want of CPU or powergrid, that is: a hull with no slot
        -- left for a thing is simply a hull with few slots)
        short += 1
      end
    end
    if guns > 0 then
      table.insert(flags, `cannot carry {guns} of its {row.wanted} weapons ({why})`)
    end
    if short >= 3 then
      table.insert(flags, `has the slots for {short} more of a plain tank, and not the CPU or the powergrid`)
    end
    -- A plain hull out of line with the plain hulls of its class.
    local mid = middle[row.class]
    if row.plain and mid and mid.count >= 3 then
      local figures: { { any } } = { { "to destroy", row.ehp, mid.ehp }, { "speed", row.speed, mid.speed } }
      if row.wanted > 0 then
        table.insert(figures, 1, { "damage", row.dps, mid.dps } :: { any })
      end
      for _, figure in figures do
        local value: number, usual: number = figure[2], figure[3]
        if usual > 0 and math.abs(value / usual - 1) > OUT then
          table.insert(flags, string.format("%s %+.0f%% for its class", figure[1], 100 * (value / usual - 1)))
        end
      end
      if row.lasts < SOON * mid.lasts then
        table.insert(flags, string.format("capacitor dry in %d s, where its class's lasts %.0f", row.lasts, mid.lasts))
      end
    end
    -- A capacitor that is dry almost at once, whoever's it is.
    if row.lasts < DRY then
      table.insert(flags, `capacitor dry in {row.lasts} s with everything running`)
    end
    -- The same as another in everything the rules count.
    local key = string.format("%s|%s|%s|%s|%.0f|%.0f|%.0f|%.1f|%.0f|%.0f|%.2f|%.0f|%.0f|%.0f|%s", row.faction, row.class, row.slots,
      row.hardpoints, row.shield, row.armor, row.hull, row.dps, row.cpuMax, row.powergridMax, row.align, row.speed, row.cargo,
      row.price, row.what .. row.holds)
    alike[key] = alike[key] or {}
    table.insert(alike[key], row)
  end
  for _, same in alike do
    if #same > 1 then
      for _, row in same do
        local others: { string } = {}
        for _, other in same do
          if other ~= row then
            table.insert(others, other.name)
          end
        end
        table.insert(row.flags, `the same to the rules as {table.concat(others, ", ")}`)
      end
    end
  end
  return rows
end

-- ---------------------------------------------------------------------
-- Saying it

local function whole(n: number): string
  local s = string.format("%.0f", n)
  local out = string.gsub(string.reverse(s), "(%d%d%d)", "%1,")
  out = string.reverse(out)
  return (string.gsub(out, "^,", ""))
end

local function lastsFor(row: Row): string
  return if row.lasts == math.huge then "holds" else `{row.lasts} s`
end

local COLUMNS: { { any } } = {
  { "Hull", function(r: Row): string return r.name end },
  { "Faction", function(r: Row): string return r.faction end },
  { "Class", function(r: Row): string return r.class end },
  { "Tech", function(r: Row): string return tostring(r.tech) end },
  { "What", function(r: Row): string return r.what end },
  { "Price", function(r: Row): string return string.format("%.0f", r.price) end },
  { "Slots H/M/L", function(r: Row): string return r.slots end },
  { "Turrets/launchers", function(r: Row): string return r.hardpoints end },
  { "Weapons fitted", function(r: Row): string return `{r.weapons} of {r.wanted}` end },
  { "CPU used", function(r: Row): string return string.format("%.0f of %.0f", r.cpu, r.cpuMax) end },
  { "Powergrid used", function(r: Row): string return string.format("%.0f of %.0f", r.powergrid, r.powergridMax) end },
  { "Shield", function(r: Row): string return string.format("%.0f", r.shield) end },
  { "Armour", function(r: Row): string return string.format("%.0f", r.armor) end },
  { "Hull HP", function(r: Row): string return string.format("%.0f", r.hull) end },
  { "Effective HP", function(r: Row): string return string.format("%.0f", r.ehp) end },
  { "Mends HP/s", function(r: Row): string return string.format("%.1f", r.mend) end },
  { "Repairer HP/s", function(r: Row): string return string.format("%.1f", r.repair) end },
  { "Damage/s", function(r: Row): string return string.format("%.1f", r.dps) end },
  { "Volley", function(r: Row): string return string.format("%.0f", r.volley) end },
  { "Reach m", function(r: Row): string return string.format("%.0f", r.range) end },
  { "Capacitor GJ", function(r: Row): string return string.format("%.0f", r.capacitor) end },
  { "Capacitor use GJ/s", function(r: Row): string return string.format("%.1f", r.use) end },
  { "Capacitor", function(r: Row): string return lastsFor(r) end },
  { "Speed m/s", function(r: Row): string return string.format("%.0f", r.speed) end },
  { "With afterburner", function(r: Row): string return string.format("%.0f", r.burn) end },
  { "Aligns s", function(r: Row): string return string.format("%.1f", r.align) end },
  { "Signature m", function(r: Row): string return string.format("%.0f", r.signature) end },
  { "Lock range m", function(r: Row): string return string.format("%.0f", r.lock) end },
  { "Targets", function(r: Row): string return tostring(r.targets) end },
  { "Cargo m3", function(r: Row): string return string.format("%.0f", r.cargo) end },
  { "Flags", function(r: Row): string return table.concat(r.flags, "; ") end },
}

local function csv(rows: { Row }): string
  local lines: { string } = {}
  local head: { string } = {}
  for _, column in COLUMNS do
    table.insert(head, column[1])
  end
  table.insert(lines, table.concat(head, ","))
  for _, row in rows do
    local cells: { string } = {}
    for _, column in COLUMNS do
      local text: string = column[2](row)
      if string.find(text, "[,\"]") then
        text = `"{string.gsub(text, "\"", "\"\"")}"`
      end
      table.insert(cells, text)
    end
    table.insert(lines, table.concat(cells, ","))
  end
  return table.concat(lines, "\n") .. "\n"
end

local function escape(text: string): string
  return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local STYLE = [[
:root { --bg:#f6f5f2; --panel:#ffffff; --ink:#1b1c1e; --dim:#63666b; --line:#dcdad4; --flag:#8a4b00; --flagbg:#fbefd9; --head:#efeee9; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#15171a; --panel:#1c1f23; --ink:#e8e6e1; --dim:#9a9da3; --line:#2e3238; --flag:#f0b45a; --flagbg:#3a2a12; --head:#22262b; } }
:root[data-theme="dark"] { --bg:#15171a; --panel:#1c1f23; --ink:#e8e6e1; --dim:#9a9da3; --line:#2e3238; --flag:#f0b45a; --flagbg:#3a2a12; --head:#22262b; }
* { box-sizing: border-box; }
body { margin:0; padding:24px 16px 60px; background:var(--bg); color:var(--ink); font:14px/1.45 system-ui, sans-serif; }
h1 { font-size:22px; margin:0 0 4px; }
h2 { font-size:16px; margin:28px 0 8px; }
p { margin:4px 0; color:var(--dim); max-width:70em; }
.bar { margin:14px 0 4px; display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
.bar button { font:inherit; padding:4px 10px; border:1px solid var(--line); background:var(--panel); color:var(--ink); border-radius:6px; cursor:pointer; }
.bar button[aria-pressed="true"] { border-color:var(--ink); }
.wrap { overflow-x:auto; border:1px solid var(--line); border-radius:8px; background:var(--panel); }
table { border-collapse:collapse; width:100%; font-variant-numeric:tabular-nums; }
th, td { padding:5px 9px; text-align:right; white-space:nowrap; border-bottom:1px solid var(--line); }
th { background:var(--head); position:sticky; top:0; cursor:pointer; font-weight:600; user-select:none; }
th:first-child, td:first-child, td.t, th.t { text-align:left; }
tr:last-child td { border-bottom:none; }
td.what { color:var(--dim); }
td.who { white-space:normal; min-width:17em; max-width:30em; }
.flag { display:inline-block; margin:3px 4px 1px 0; padding:1px 8px; border-radius:10px; background:var(--flagbg); color:var(--flag); font-size:12.5px; }
tr.flagged td.who > div::before { content:"\25B2  "; color:var(--flag); }
]]

local SCRIPT = [[
const only = { flagged: false, faction: "" };
function apply() {
  document.querySelectorAll("tbody tr").forEach(tr => {
    const show = (!only.flagged || tr.classList.contains("flagged")) && (!only.faction || tr.dataset.faction === only.faction);
    tr.style.display = show ? "" : "none";
  });
  document.querySelectorAll("section").forEach(s => {
    s.style.display = [...s.querySelectorAll("tbody tr")].some(tr => tr.style.display !== "none") ? "" : "none";
  });
}
document.querySelectorAll(".bar button").forEach(b => b.addEventListener("click", () => {
  if (b.dataset.flagged) { only.flagged = !only.flagged; b.setAttribute("aria-pressed", only.flagged); }
  else { only.faction = only.faction === b.dataset.faction ? "" : b.dataset.faction;
    document.querySelectorAll("[data-faction-button]").forEach(o => o.setAttribute("aria-pressed", o.dataset.faction === only.faction && only.faction !== "")); }
  apply();
}));
document.querySelectorAll("th").forEach(th => th.addEventListener("click", () => {
  const table = th.closest("table"), index = [...th.parentNode.children].indexOf(th), body = table.tBodies[0];
  const down = th.dataset.down !== "1"; th.dataset.down = down ? "1" : "0";
  const value = tr => { const t = tr.children[index].dataset.v ?? tr.children[index].textContent; const n = parseFloat(t); return isNaN(n) ? t : n; };
  [...body.rows].sort((a, b) => { const x = value(a), y = value(b); return (x > y ? 1 : x < y ? -1 : 0) * (down ? -1 : 1); }).forEach(r => body.appendChild(r));
}));
]]

local function html(rows: { Row }): string
  local out: { string } = {}
  local function put(text: string)
    table.insert(out, text)
  end
  local flagged = 0
  local factions: { string } = {}
  local seen: { [string]: boolean } = {}
  for _, row in rows do
    flagged += if #row.flags > 0 then 1 else 0
    if not seen[row.faction] then
      seen[row.faction] = true
      table.insert(factions, row.faction)
    end
  end
  put(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Hull balance</title><style>{STYLE}</style></head><body>`)
  put(`<h1>Hull balance</h1>`)
  put(`<p>{#rows} hulls, each on the same standard fit (its faction's guns on every hardpoint, an afterburner, two shield extenders, two plates, a repairer and a damage control, of its size, as far as they fit) and flown with no skills. {flagged} of them are flagged. A flag says a figure is out of line; it does not say the figure is wrong.</p>`)
  put(`<p>Effective HP is against damage spread evenly over the four kinds. "Mends" is what comes back by itself: a shield at its best rate, and the armour and hull of a hull that mends. Capacitor is with every weapon, the repairer and the afterburner running, from full: "holds" if it lasts ten minutes. A class's middle is the median of its plain hulls.</p>`)
  put(`<div class="bar"><button data-flagged="1" aria-pressed="false">Flagged only</button>`)
  for _, faction in factions do
    put(`<button data-faction-button="1" data-faction="{escape(faction)}" aria-pressed="false">{escape(faction)}</button>`)
  end
  put(`</div>`)
  local class = ""
  local function close()
    if class ~= "" then
      put(`</tbody></table></div></section>`)
    end
  end
  for _, row in rows do
    if row.class ~= class then
      close()
      class = row.class
      local called = Ships.CLASS_NAMES[class]
      put(`<section><h2>{escape(if called then called[2] else class)}</h2><div class="wrap"><table><thead><tr>`)
      for _, head in { "Hull", "Faction", "What", "Price", "Slots", "Guns fit", "CPU", "Grid", "Effective HP", "Shield", "Armour", "Hull HP",
        "Mends /s", "Damage /s", "Volley", "Reach km", "Capacitor", "Speed", "Burning", "Aligns s", "Cargo" } do
        put(`<th{if head == "Hull" or head == "Faction" or head == "What" then ' class="t"' else ""}>{head}</th>`)
      end
      put(`</tr></thead><tbody>`)
    end
    put(`<tr{if #row.flags > 0 then ' class="flagged"' else ""} data-faction="{escape(row.faction)}">`)
    -- (what is out of line is said under the hull's name, where it is
    -- seen however narrow the window)
    put(`<td class="who" data-v="{escape(row.name)}"><div>{escape(row.name)}{if row.tech == 2 then " (tech 2)" else ""}</div>`)
    for _, flag in row.flags do
      put(`<span class="flag">{escape(flag)}</span>`)
    end
    put(`</td><td class="t">{escape(row.faction)}</td><td class="t what">{escape(row.what)}</td>`)
    put(`<td data-v="{string.format("%.0f", row.price)}">{whole(row.price)}</td><td>{row.slots}</td>`)
    put(`<td data-v="{row.weapons}">{row.weapons} of {row.wanted}</td>`)
    put(string.format(`<td data-v="%.3f">%.0f%%</td><td data-v="%.3f">%.0f%%</td>`, row.cpu / math.max(1, row.cpuMax), 100 * row.cpu / math.max(1, row.cpuMax),
      row.powergrid / math.max(1, row.powergridMax), 100 * row.powergrid / math.max(1, row.powergridMax)))
    put(`<td data-v="{string.format("%.0f", row.ehp)}">{whole(row.ehp)}</td><td data-v="{string.format("%.0f", row.shield)}">{whole(row.shield)}</td>`)
    put(`<td data-v="{string.format("%.0f", row.armor)}">{whole(row.armor)}</td><td data-v="{string.format("%.0f", row.hull)}">{whole(row.hull)}</td>`)
    put(string.format(`<td>%.1f</td><td>%.1f</td><td data-v="%.0f">%s</td><td>%.1f</td>`, row.mend, row.dps, row.volley, whole(row.volley), row.range / 1000))
    put(`<td data-v="{if row.lasts == math.huge then 9999 else row.lasts}">{lastsFor(row)}</td>`)
    put(string.format(`<td>%.0f</td><td>%.0f</td><td>%.1f</td><td data-v="%.0f">%s</td>`, row.speed, row.burn, row.align, row.cargo, whole(row.cargo)))
    put(`</tr>`)
  end
  close()
  put(`<script>{SCRIPT}</script></body></html>`)
  return table.concat(out, "\n")
end

local Balance = {}

Balance.Report = report

function Balance.Main(args: { string }): number
  local out = ""
  for index, arg in args do
    if arg == "--out" then
      out = args[index + 1] or ""
    end
  end
  local rows = report()
  local flagged = 0
  print(string.format("%-34s %-11s %-18s %9s %9s %8s %7s %7s  %s", "hull", "faction", "class", "eff. HP", "damage/s", "speed", "guns", "cap", "flags"))
  for _, row in rows do
    flagged += if #row.flags > 0 then 1 else 0
    print(string.format("%-34s %-11s %-18s %9.0f %9.1f %8.0f %3d/%-3d %7s  %s", row.name .. (if row.tech == 2 then " (t2)" else ""), row.faction,
      row.class, row.ehp, row.dps, row.speed, row.weapons, row.wanted, lastsFor(row), table.concat(row.flags, "; ")))
  end
  print(`balance: {#rows} hulls on the standard fit, {flagged} flagged`)
  if out ~= "" then
    local sheet, page = csv(rows), html(rows)
    Host.WriteFile(out .. "/balance.csv", sheet, #sheet)
    Host.WriteFile(out .. "/balance.html", page, #page)
    print(`balance: wrote {out}/balance.csv and {out}/balance.html`)
  end
  return 0
end

return Balance
