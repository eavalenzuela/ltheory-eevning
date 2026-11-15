--!strict
-- The game: the Core (resource/script/Core) shown by the engine.
--
--   bin/launch game
--
-- Flight is by command. Left-drag turns the camera, the wheel zooms.
-- F9 saves, F10 loads, P pauses, + and - change the speed of time.
--
-- GameDebug (a global) is for the console and scripted runs:
--   bin/launch game --console
--   bin/launch game --do "lua GameDebug.Order('Undock'); until GameDebug.InSpace(); ..."

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Audio = require("@lt/Game/View/Audio")
local Colors = require("@lt/Colors")
local Colony = require("@lt/Game/UI/Colony")
local Context = require("@lt/Game/UI/Context")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Hacking = require("@lt/Core/Tactical/Hacking")
local Keeps = require("@lt/Core/Tactical/Keeps")
local Map = require("@lt/Game/UI/Map")
local Members = require("@lt/Core/Assets/Members")
local Planets = require("@lt/Core/Data/Planets")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Attributes = require("@lt/Core/Attributes")
local Hud = require("@lt/Game/UI/Hud")
local Icons = require("@lt/Icons")
local Hull = require("@lt/Game/View/Hull")
local Im = require("@lt/Game/UI/Im")
local Reactions = require("@lt/Core/Data/Reactions")
local Scanner = require("@lt/Game/UI/Scanner")
local Planet = require("@lt/Game/View/Planet")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local Settings = require("@lt/Game/Settings")
local Starbases = require("@lt/Core/Assets/Starbases")
local Station = require("@lt/Game/UI/Station")
local Info = require("@lt/Game/UI/Info")
local Menu = require("@lt/Game/UI/Menu")
local Corporation = require("@lt/Core/Assets/Corporation")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Keys = require("@lt/Game/UI/Keys")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Skills = require("@lt/Core/Data/Skills")
local Fits = require("@lt/Core/Fits")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")
local Waypoints = require("@lt/Game/Waypoints")
local Wormholes = require("@lt/Core/Tactical/Wormholes")
local Wars = require("@lt/Core/Strategic/Wars")
local Windows = require("@lt/Game/UI/Windows")
local Inventory = require("@lt/Game/UI/Inventory")

local App = {}

local session: Session.Session
local scene: Scene.Scene
local audio: Audio.Audio
local settings: Settings.Settings
local ui: Interface

-- The nearest thing on the overview of a kind ("belt", "station", ...)
-- or whose name contains the text; "home" is the pilot's home station.
local function find(what: string): Core.Entry?
  local entries = Core.Query.Overview(session.game)
  for _, entry in entries do
    if entry.kind == what or (what == "home" and entry.id == session.game.state.player.home) then
      return entry
    end
  end
  -- A whole name before a part of one: "Merear II" is the planet, not
  -- its asteroid belt.
  for _, entry in entries do
    if string.lower(entry.name) == string.lower(what) then
      return entry
    end
  end
  for _, entry in entries do
    if string.find(string.lower(entry.name), string.lower(what), 1, true) then
      return entry
    end
  end
  return nil
end

local Debug = {}

-- Whether the pointer is drawn (App:Initialize says: it is, for a person).
local pointer = false

-- Have the pointer drawn, or not: for a script, which has none unless
-- it asks.
function Debug.Pointer(on: boolean)
  pointer = on
end

-- GameDebug.Order("Undock"), GameDebug.Order("WarpTo", "belt"),
-- GameDebug.Order("Orbit", "asteroid", 5000)
function Debug.Order(kind: string, what: string?, range: number?): boolean
  local target: number? = nil
  if what then
    local entry = find(what)
    if entry == nil then
      print(`GameDebug.Order: nothing matches '{what}'`)
      return false
    end
    target = entry.id
    session.selected = entry.id
  end
  return Session.Order(session, kind, target, range)
end

-- Bring up the menu a right click on something would (Game/UI/Context),
-- with it picked out. False if nothing matches. With nothing named: the
-- menu a right click on empty space brings up.
function Debug.Context(what: string?): boolean
  if what == nil then
    Context.OpenSpace(700, 300)
    return true
  end
  local entry = find(what)
  if entry == nil then
    return false
  end
  session.selected = entry.id
  Context.Open(entry.id, 700, 300)
  return true
end

-- The distance the plain order of a kind is given at ("Orbit",
-- "KeepAtRange", "WarpTo"): what was last picked from a menu. And what
-- menu is up now: "" (none), "thing", "space" or "set".
function Debug.Range(kind: string): (number, string)
  return Context.Range(kind), Context.Kind()
end

function Debug.Select(what: string): boolean
  local entry = find(what)
  session.selected = if entry then entry.id else 0
  return entry ~= nil
end

-- The name of what is selected, or "".
function Debug.Selected(): string
  local body = Core.Query.Body(session.game, session.selected)
  return if body then body.name else ""
end

-- What the ship is doing: its mode, or "warp", "align", "docked".
function Debug.Doing(): string
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  if ball == nil then
    return "docked"
  elseif ball.warp then
    return ball.warp.stage
  end
  return ball.mode
end

function Debug.InSpace(): boolean
  return Core.Query.Player(session.game).docked == 0
end

function Debug.Docked(): boolean
  return Core.Query.Player(session.game).docked ~= 0
end

function Debug.InWarp(): boolean
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  return ball ~= nil and ball.warp ~= nil and ball.warp.stage == "warp"
end

-- True when the ship is in space, out of warp and has nothing left to do
-- (no dock or jump pending).
function Debug.Idle(): boolean
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  return ball ~= nil and ball.warp == nil and ball.intent == nil
end

-- Metres between the ship and whatever it is approaching, orbiting or
-- keeping at range; a huge number if nothing.
function Debug.TargetGap(): number
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  local target = if ball then Core.Query.Body(session.game, ball.target) else nil
  if ball == nil or target == nil then
    return math.huge
  end
  local centres = math.sqrt((ball.x - target.x) ^ 2 + (ball.y - target.y) ^ 2 + (ball.z - target.z) ^ 2)
  return math.max(0, centres - ball.radius - target.radius)
end

function Debug.System(): number
  return Core.Query.Player(session.game).system
end

-- Distance to the nearest thing matching 'what', in metres.
function Debug.Distance(what: string): number
  local entry = find(what)
  return if entry then entry.distance else math.huge
end

-- How many of the system's standing bodies (rocks, stations, gates) are
-- drawn in the scene now, and the seconds of the warp the ship is in
-- that are left (0 out of warp): for checking that what a ship leaves
-- and comes to is there to be seen at the ends of a warp.
function Debug.Bodies(): (number, number)
  local count = 0
  for _ in scene.statics do
    count += 1
  end
  return count, if scene.warp > 0 then scene.warpSeconds else 0
end

-- How much of the view a jump through a gate has whited out, 0 to 1
-- (0 when none is under way), and the system the scene is showing:
-- behind the Core's by a moment while a jump is leaving.
function Debug.Veil(): (number, number)
  return scene.veil, scene.system
end

-- The engine objects in the scene, with their sizes: for checking the view.
function Debug.Proxies()
  for id, object in scene.proxies do
    local body = Core.Query.Body(session.game, id)
    print(string.format("%d %-40s wanted radius %.0f, engine radius %.1f, scale %s, pos %s",
      id, object:GetName(), if body then body.radius else -1, object:GetRadius(), tostring(object:GetScale()),
      tostring(object:GetPos())))
  end
end

function Debug.Camera()
  local focus = scene.focus
  print(`camera at {tostring(scene.camera:GetPos())} looking {tostring(scene.camera:GetLook())}; `
    .. `focus {if focus then focus:GetName() else "none"} centre {if focus then tostring(focus:GetCenter()) else "-"} `
    .. `pos {if focus then tostring(focus:GetPos()) else "-"} radius {if focus then focus:GetRadius() else 0}; `
    .. `zoom {scene.zoom} yaw {scene.yaw} pitch {scene.pitch}`)
end

-- Camera distance in focus radii, and its direction.
function Debug.Zoom(zoom: number, yaw: number?, pitch: number?)
  scene.zoom, scene.zoomTarget = zoom, zoom
  scene.yaw = yaw or scene.yaw
  scene.pitch = pitch or scene.pitch
end

-- Swing the camera round to look past the ship at something:
-- GameDebug.LookAt('sun'), GameDebug.LookAt('planet'). False if there is
-- no such thing in view of the overview.
function Debug.LookAt(what: string, zoom: number?, over: number?): boolean
  local entry = find(what)
  local at = if entry then scene.screen[entry.id] else nil
  local focus = scene.focus
  if at == nil or focus == nil then
    return false
  end
  -- The camera sits on the far side of the ship from what it looks at.
  local away = vector.normalize(focus:GetPos() - at)
  -- (a little above the line through the ship, or the ship would hide it)
  -- ('over': how far above it, in radians, where that is not enough)
  scene.pitch = math.clamp(math.acos(math.clamp(away.y, -1, 1)) - (over or 0.16), 0.05, math.pi - 0.05)
  scene.yaw = math.atan2(away.z, away.x)
  if zoom then
    scene.zoom, scene.zoomTarget = zoom, zoom
  end
  return true
end

-- The other way about: look at the ship from the side something is on,
-- GameDebug.LookFrom('sun') for the lit side of it. 'turn' swings the
-- camera round from there, in radians.
function Debug.LookFrom(what: string, zoom: number?, turn: number?): boolean
  if not Debug.LookAt(what, zoom) then
    return false
  end
  scene.pitch = math.clamp(math.pi - scene.pitch - 0.5, 0.05, math.pi - 0.05)
  scene.yaw += math.pi + (turn or 0)
  return true
end

-- Remember the state's hash under a name; Same compares two of them.
-- A scripted run uses these to prove that a reloaded save plays out to
-- the same state.
local marks: { [string]: string } = {}

function Debug.Mark(name: string)
  marks[name] = `{Core.Hash(session.game)} at tick {session.game.state.tick}`
  print(`mark {name}: {marks[name]}`)
end

function Debug.Same(a: string, b: string): boolean
  return marks[a] ~= nil and marks[a] == marks[b]
end

-- Megabytes of memory the process holds (resident set), from /proc.
function Debug.Memory(): number
  local statm = Host.ReadFile("/proc/self/statm")
  if statm == nil then
    return 0
  end
  local pages = tonumber(string.match(buffer.tostring(statm), "^%d+ (%d+)"))
  return if pages then pages * 4096 / 1e6 else 0
end

-- Megabytes of video memory in use on each graphics card, as the driver
-- reports it (all processes, not only this one), highest first.
function Debug.Vram(): (number, number)
  local used: { number } = {}
  for card = 0, 3 do
    local data = Host.ReadFile(`/sys/class/drm/card{card}/device/mem_info_vram_used`)
    if data then
      table.insert(used, (tonumber(string.match(buffer.tostring(data), "%d+")) or 0) / 1e6)
    end
  end
  table.sort(used, function(a: number, b: number): boolean
    return a > b
  end)
  return used[1] or 0, used[2] or 0
end

-- Jump through the nearest gate 'count' times, one after another, to
-- exercise leaving and entering systems. JumpsLeft counts down to 0.
local jumpsLeft = 0
local jumpFrom = 0

function Debug.Jumps(count: number)
  jumpsLeft = count
  jumpFrom = 0
end

function Debug.JumpsLeft(): number
  return jumpsLeft
end

local function autopilot()
  if jumpsLeft <= 0 then
    return
  end
  local player = Core.Query.Player(session.game)
  if player.docked ~= 0 then
    Session.Order(session, "Undock")
    return
  end
  if jumpFrom ~= 0 and player.system ~= jumpFrom then
    jumpsLeft -= 1
    jumpFrom = 0
    local vram = Debug.Vram()
    print(string.format("jumped to system %d; %d to go; memory %.0f MB; video memory %.0f MB",
      player.system, jumpsLeft, Debug.Memory(), vram))
  end
  if jumpsLeft > 0 and jumpFrom == 0 and Debug.Idle() and #session.game.state.queue == 0 then
    local gate = find("gate")
    if gate then
      jumpFrom = player.system
      Session.Order(session, "Jump", gate.id)
    end
  end
end

-- Lock the nearest thing matching 'what'.
function Debug.Lock(what: string): boolean
  return Debug.Order("LockTarget", what)
end

-- The pilot's target (Session.Aim): its name ("" with none), how many
-- things the ship has locked or is locking, and how many it can have.
function Debug.Target(): (string, number, number)
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  local body = if session.target ~= 0 then Core.Query.Body(session.game, session.target) else nil
  return if body then body.name else "", if ball then #ball.vitals.locks else 0, if ball then ball.vitals.maxTargets else 0
end

-- How many targets are locked (not merely being locked).
function Debug.Locked(): number
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  local count = 0
  if ball then
    for _, lock in ball.vitals.locks do
      if lock.locked then
        count += 1
      end
    end
  end
  return count
end

-- Open fire with every weapon on the first locked target. Returns how
-- many were switched on.
function Debug.Fire(): number
  local ship = session.game.state.player.ship
  local ball = Core.Query.Ball(session.game, ship)
  local started = 0
  if ball then
    for _, lock in ball.vitals.locks do
      if lock.locked then
        for _, item in Core.Query.Fitted(session.game, ship) do
          if Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = lock.target }) then
            started += 1
          end
        end
        break
      end
    end
  end
  return started
end

-- Start every mining laser on the first locked target. Returns how many
-- were switched on.
function Debug.Mine(): number
  local ship = session.game.state.player.ship
  local ball = Core.Query.Ball(session.game, ship)
  local started = 0
  if ball then
    for _, lock in ball.vitals.locks do
      if lock.locked then
        for _, item in Core.Query.Fitted(session.game, ship) do
          -- (a laser, on a rock; a harvester, on a cloud)
          if Modules.byId[item.type].miner
            and Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = lock.target }) then
            started += 1
          end
        end
        break
      end
    end
  end
  return started
end

-- How many modules are running.
function Debug.Running(): number
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  return if ball then #ball.vitals.running else 0
end

-- How many ships the pilot keeps at the station docked at.
function Debug.Ships(): number
  local player = Core.Query.Player(session.game)
  return if player.docked ~= 0 then #Core.Query.Ships(session.game, player.docked) else 0
end

-- How many things of a kind are on the overview ("ship", "wreck", ...).
function Debug.Count(kind: string): number
  local count = 0
  for _, entry in Core.Query.Overview(session.game) do
    if entry.kind == kind then
      count += 1
    end
  end
  return count
end

function Debug.Wallet(): number
  return session.game.state.wallet
end

-- The id of the hull the player is flying: "frigate.courier", "capsule", ...
function Debug.Hull(): string
  return Core.Query.Player(session.game).hull.id
end

-- How many of an item type are in the hold.
function Debug.Hold(type: string): number
  for _, item in Core.Query.Items(session.game, session.game.state.player.ship, "cargo") do
    if item.type == type then
      return item.quantity
    end
  end
  return 0
end

-- The ship's shield, armour and hull as shares of full, or nothing docked.
function Debug.Condition(): (number, number, number)
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  if ball == nil then
    return 1, 1, 1
  end
  local v = ball.vitals
  return v.shield / v.shieldMax, v.armor / v.armorMax, v.hull / v.hullMax
end

-- How many modules of a type are fitted.
function Debug.Fitted(type: string): number
  local count = 0
  for _, item in Core.Query.Fitted(session.game, session.game.state.player.ship) do
    if item.type == type then
      count += 1
    end
  end
  return count
end

-- Destroy the player's own ship, as if it had been shot down.
function Debug.SelfDestruct()
  local ship = session.game.state.player.ship
  if Core.Query.Ball(session.game, ship) then
    Aftermath.Destroy(session.game.state, ship, 0, session.game.events)
  end
end

-- How the overview is listed: the column it is listed by ("distance",
-- "name" or "type") and whether the other way round; and the name on
-- its nth row as it is listed (the first, if not said). The columns'
-- heads are "Overview:sort:<column>": a press lists by that column, and
-- another turns it round.
function Debug.Listed(row: number?): (string, boolean, string)
  local by, down = Hud.Sort()
  return by, down, Hud.Listed(session)[row or 1] or ""
end

-- Whether the pilot's ship is in a cloud of gas (where it is locked,
-- and locks, only from close in), how close that is in metres, and how
-- many of the other ships on the overview are in one.
function Debug.Veiled(): (boolean, number, number)
  local veiled, sight = Core.Query.Veiled(session.game, session.game.state.player.ship)
  local others = 0
  for _, entry in Core.Query.Overview(session.game) do
    others += if entry.veiled then 1 else 0
  end
  return veiled, sight, others
end

-- No pirates come while this is on.
function Debug.Peaceful(on: boolean)
  session.game.state.peaceful = on
end

function Debug.TimeScale(scale: number)
  -- (a script's cheat: a person runs time faster only at a station)
  session.clock.scale = scale
  session.clock.forced = scale ~= 1
end

-- How fast time is running, as the pilot has it.
function Debug.Clock(): number
  return session.clock.scale
end

-- Press a button of the interface by name, as a click would: its label
-- ("UNDOCK", "Market") or, for one of several alike, its id
-- ("Fit:miner.small", "Train:frigates", "BuyNow"). False if there is no
-- such button on screen yet, or it is greyed out; a scripted run waits
-- for it with "until GameDebug.Press('...')", since the screen is a
-- frame behind the game.
function Debug.Press(name: string): boolean
  return Im.Press(name)
end

-- Why a button cannot be pressed: for a script that has given up waiting.
function Debug.WhyNot(name: string): string
  local there, enabled = Im.Has(name)
  return if enabled then "it can be" elseif there then "greyed out" else "not on screen"
end

-- Whether a button is on screen and can be pressed.
function Debug.CanPress(name: string): boolean
  local _, enabled = Im.Has(name)
  return enabled
end

-- Type a number into a field by name ("Quantity", "SellPrice", "Runs").
function Debug.Enter(name: string, value: number)
  Im.Enter(name, value)
end

-- Put words in a field of words, by its name ('Corporation:name').
function Debug.Type(name: string, text: string)
  Im.Say(name, text)
end

-- A cheat: so many credits in the pilot's wallet.
function Debug.Credits(amount: number)
  session.game.state.wallet = amount
end

-- The pilot's corporation: its name ("" if there is none), what is in
-- its account, all it has earned and all it has spent, and how many
-- pilots can be hired.
function Debug.Corporation(): (string, number, number, number, number)
  local info = Core.Query.Corporation(session.game)
  return info.name, info.wallet, info.earned, info.spent, select(2, Core.Query.Candidates(session.game, session.game.state.player.home))
end

-- The corporation's books: how many heads have anything under them,
-- what the first of them is called and what is under it, and how many
-- towers of the pilot's are on the books.
function Debug.Books(): (number, string, number, number)
  local info = Core.Query.Corporation(session.game)
  local first = info.heads[1]
  return #info.heads, if first then first.name else "", if first then first.amount else 0, #info.towers
end

-- Where else a thing is to be had, from the station the pilot is docked
-- at: how many markets within reach have any, and of the best of them
-- the id, how many jumps off it is, and what one costs there.
function Debug.Sources(type: string, quantity: number?): (number, number, number, number)
  local docked = Core.Query.Player(session.game).docked
  local found = Core.Query.Sources(session.game, docked, type, quantity or 1)
  local best = found[1]
  if best == nil then
    return 0, 0, 0, 0
  end
  return #found, best.id, best.jumps, best.each
end

-- Which of the pilots looking for work at the home station is the first
-- of a grade or better (the number on their Hire button), or 0.
function Debug.Candidate(grade: number): number
  for index, found in (Core.Query.Candidates(session.game, session.game.state.player.home)) do
    if found.skill >= grade then
      return index
    end
  end
  return 0
end

-- Open the market at an item type, or the industry tab at a blueprint.
-- Open the information window on a type of item ("frigate.battleaxe").
function Debug.Info(type: string): boolean
  return Info.Open(type)
end

function Debug.Market(type: string): boolean
  return Station.Choose(type)
end

function Debug.Blueprint(type: string): boolean
  return Station.Blueprint(type)
end

function Debug.Tab(): string
  return Station.Tab()
end

-- How many of an item type are in the hangar of the station docked at
-- (the home station, when in space).
function Debug.Hangar(type: string): number
  local player = Core.Query.Player(session.game)
  local station = if player.docked ~= 0 then player.docked else session.game.state.player.home
  for _, item in Core.Query.Items(session.game, station, "hangar") do
    if item.type == type then
      return item.quantity
    end
  end
  return 0
end

-- How many of a type are in the corporation's hangar at the station
-- docked at (the home station's, in space), and how many stacks it has
-- there in all.
function Debug.CorpHangar(type: string): (number, number)
  local player = Core.Query.Player(session.game)
  local station = if player.docked ~= 0 then player.docked else session.game.state.player.home
  local units, stacks = 0, 0
  for _, item in Core.Query.Items(session.game, station, "corporate") do
    stacks += 1
    units += if item.type == type then item.quantity else 0
  end
  return units, stacks
end

-- How the pilot's newest tower stands under fire: how much of its
-- shield is left (0 to 1), the sealing charges aboard, the seconds it
-- stays sealed (0 when it is not), and how strong those are who have
-- come to bring it down (0 when nobody has). -1 and nothing for no
-- tower.
function Debug.Siege(): (number, number, number, number)
  local state = session.game.state
  local id = state.starbaseIds[#state.starbaseIds]
  local status = if id then Core.Query.Starbase(session.game, id) else nil
  if status == nil then
    return -1, 0, 0, 0
  end
  return status.shield, status.charges, status.sealed, status.siege
end

-- Cheats, for a scripted siege of the pilot's newest tower, wherever it
-- is. Besiege: those who would bring it down come now, so strong.
-- TowerHit: its shield is brought to a share of what it has; with 0,
-- what stands for it is destroyed, and the tower with it. Unseal: a
-- sealed one opens in a moment. Each is false with no tower to do it to.
function Debug.Besiege(strength: number): boolean
  local state = session.game.state
  local starbase = state.starbases[state.starbaseIds[#state.starbaseIds] or 0]
  if starbase == nil then
    return false
  end
  starbase.siege, starbase.raid = strength, state.tick + 1
  return true
end

function Debug.TowerHit(share: number): boolean
  local state = session.game.state
  local starbase = state.starbases[state.starbaseIds[#state.starbaseIds] or 0]
  local core = if starbase then state.balls[starbase.core] else nil
  if core == nil then
    return false
  end
  if share <= 0 then
    Aftermath.Destroy(state, core.id, 0, session.game.events)
  else
    core.vitals.shield = share * core.vitals.shieldMax
  end
  return true
end

function Debug.Unseal(): boolean
  local state = session.game.state
  local starbase = state.starbases[state.starbaseIds[#state.starbaseIds] or 0]
  if starbase == nil or starbase.sealed == 0 then
    return false
  end
  starbase.sealed = state.tick + 2
  return true
end

-- The pirates' tower in the pilot's system (the first, if they hold
-- several moons there): how much of its shield is left (0 to 1), the
-- seconds it stays sealed (0 when it is not), how many of its batteries
-- stand, and whether it has anything to seal with. -1 and nothing for a
-- system with none.
local function keepHere(): State.Keep?
  local state = session.game.state
  local system = Core.Query.Player(session.game).system
  for _, id in state.keepIds do
    if state.keeps[id].system == system then
      return state.keeps[id]
    end
  end
  return nil
end

function Debug.Keep(): (number, number, number, boolean)
  local keep = keepHere()
  local status = if keep then Core.Query.Keep(session.game, keep.id) else nil
  local core = if keep then session.game.state.balls[keep.core] else nil
  if status == nil or core == nil then
    return -1, 0, 0, false
  end
  return core.vitals.shield / math.max(1, core.vitals.shieldMax), status.sealed, status.batteries, status.charged
end

-- Cheats, for a scripted taking of a moon. KeepRaise: pirates hold the
-- nearest moon with something under it, wherever the pilot is (they do
-- it of themselves only where nobody keeps order): the name of their
-- tower's place, "" if no moon would do. KeepHit: its shield is brought
-- to a share of what it has; with 0 the pilot has destroyed it.
-- KeepOpen: a sealed one opens in a moment. Each is false with no keep.
function Debug.KeepRaise(): string
  local state = session.game.state
  for _, entry in Core.Query.Overview(session.game) do
    local moon = if entry.kind == "moon" and Core.Query.Deposit(session.game, entry.id) then Space.Object(state, entry.id) else nil
    local keep = if moon then Keeps.Raise(state, moon, session.game.events) else nil
    if keep then
      local place = Space.Object(state, keep.id)
      return if place then place.name else ""
    end
  end
  return ""
end

function Debug.KeepHit(share: number): boolean
  local state = session.game.state
  local keep = keepHere()
  local core = if keep then state.balls[keep.core] else nil
  if core == nil then
    return false
  end
  if share <= 0 then
    Aftermath.Destroy(state, core.id, state.player.ship, session.game.events)
  else
    core.vitals.shield = share * core.vitals.shieldMax
  end
  return true
end

function Debug.KeepOpen(): boolean
  local state = session.game.state
  local keep = keepHere()
  if keep == nil or keep.sealed == 0 then
    return false
  end
  keep.sealed = state.tick + 2
  return true
end

-- The level of a skill; -1 if it has not been learned.
function Debug.Skill(id: string): number
  return session.game.state.skills[id] or -1
end

-- How many levels are queued to train, jobs are running, orders stand.
function Debug.Training(): number
  return #Core.Query.Training(session.game)
end

function Debug.Jobs(): number
  return #Core.Query.Jobs(session.game, nil)
end

-- The board of the station docked at (the Market tab's Contracts): how
-- many lots it has for sale today, how many it wants, and how many
-- listings the pilot has up anywhere.
function Debug.Board(): (number, number, number)
  local board = Core.Query.Contracts(session.game, Core.Query.Player(session.game).docked)
  local offers, wants = 0, 0
  for _, entry in board.lots do
    offers += if entry.lot.side == "offer" then 1 else 0
    wants += if entry.lot.side == "want" then 1 else 0
  end
  return offers, wants, #board.listings
end

-- A lot of that board, by its side ('offer' or 'want') and place: its
-- title, its price (what it costs, or pays), the type of the first
-- thing in it and how many of that. Nothing and 0 if it is not there.
function Debug.Lot(side: string, slot: number): (string, number, string, number)
  for _, entry in Core.Query.Contracts(session.game, Core.Query.Player(session.game).docked).lots do
    if entry.lot.side == side and entry.lot.slot == slot then
      return entry.lot.title, entry.lot.price, entry.lot.stacks[1].type, entry.lot.stacks[1].quantity
    end
  end
  return "", 0, "", 0
end

-- Open the market's board with a type of the hangar chosen to put up,
-- as clicking its row under New listing would.
function Debug.BoardItem(type: string): boolean
  return Station.Contract(type)
end

-- The pilot's home, where they wake when their capsule is destroyed:
-- the station's name, whether the pilot is docked there, and how many
-- jumps off it is. (It is made of the station docked at with the
-- button 'SetHome', at the foot of the docked screen.)
function Debug.Home(): (string, boolean, number)
  local home = Core.Query.Home(session.game)
  return home.name, home.here, home.jumps
end

-- A cheat: so many game days (or part of one) go by at the markets and
-- nowhere else. The clock is moved on a minute at a time with only the
-- markets stepped, which drift home and close their days; everything
-- else finds that time has passed when it next looks. For a script that
-- wants a month of prices and has not a month.
function Debug.MarketDays(days: number)
  local state = session.game.state
  state.tick -= state.tick % Market.STEP_TICKS
  for _ = 1, math.floor(days * 86400 / Market.STEP_TICKS + 0.5) do
    state.tick += Market.STEP_TICKS
    Market.Step(state, {})
  end
end

-- Which side of the market's chosen type is shown: 'trade' or 'history'.
function Debug.MarketPage(): string
  return Station.MarketPage()
end

-- The price history of a type at the station docked at (the home
-- station's, in space), as the market's History side charts it: how many
-- days it has, the lowest and the highest price among them, the price
-- now, and the units traded over them.
function Debug.PriceHistory(type: string): (number, number, number, number, number)
  local player = Core.Query.Player(session.game)
  local station = if player.docked ~= 0 then player.docked else session.game.state.player.home
  local series = Core.Query.PriceHistory(session.game, station, type)
  local low, high, units = math.huge, 0, 0
  for _, day in series do
    low, high, units = math.min(low, day.price), math.max(high, day.price), units + day.volume
  end
  return #series, if #series > 0 then low else 0, high, if #series > 0 then series[#series].price else 0, units
end

function Debug.Orders(): number
  return #Core.Query.Orders(session.game, nil)
end

-- How full the hold is, as a share.
-- The ore hold of the pilot's ship: how big it is, and how much is in
-- it, m3 (nothing and nothing for a hull with none). Given a type of
-- ore and how many, so many are put in it first.
function Debug.OreHold(type: string?, quantity: number?): (number, number)
  local state = session.game.state
  if type and quantity and Core.Query.OreHold(session.game, state.player.ship) > 0 then
    Items.Add(state, type, quantity, state.player.ship, "orehold")
  end
  return Core.Query.OreHold(session.game, state.player.ship)
end

function Debug.HoldFull(): number
  local ship = session.game.state.player.ship
  return Core.Query.CargoUsed(session.game, ship) / math.max(1, Core.Query.Stats(session.game, ship).cargo)
end

-- The starbase the pilot put up last: how it stands ("none",
-- "anchoring", "dark" or "lit"), the fuel blocks aboard, and how many
-- of its modules are online.
function Debug.Tower(): (string, number, number)
  local state = session.game.state
  local id = state.starbaseIds[#state.starbaseIds]
  local status = if id then Core.Query.Starbase(session.game, id) else nil
  if status == nil then
    return "none", 0, 0
  end
  local online = 0
  for _, module in status.modules do
    online += if module.online then 1 else 0
  end
  return if not status.anchored then "anchoring" elseif status.lit then "lit" else "dark", status.fuel, online
end

-- The nearest moon of the pilot's system with something under it (or,
-- with false, with nothing): its name and the material's id ("" and ""
-- if there is none such).
function Debug.Moon(deposit: boolean?): (string, string)
  for _, entry in Core.Query.Overview(session.game) do
    if entry.kind == "moon" then
      local has = Core.Query.Deposit(session.game, entry.id)
      if (has ~= nil) == (deposit ~= false) then
        return entry.name, if has then has.material.id else ""
      end
    end
  end
  return "", ""
end

-- How the drilling stands at the starbase the pilot put up last:
-- "nothing" (its moon has nothing under it), "none" (no drill),
-- "waiting" (a drill that is not working yet, or has no power),
-- "drilling" or "full"; and the material's id, what the drill brings up
-- an hour, how much of it is in the tower's hangar, and how much the
-- tower holds.
function Debug.Drill(): (string, string, number, number, number)
  local state = session.game.state
  local id = state.starbaseIds[#state.starbaseIds]
  local status = if id then Core.Query.Starbase(session.game, id) else nil
  if status == nil or status.drilling.deposit == nil then
    return "nothing", "", 0, 0, 0
  end
  local drilling = status.drilling
  local deposit = drilling.deposit :: any
  return if not drilling.anchored then "none" elseif not drilling.online then "waiting"
    elseif drilling.stored >= drilling.room then "full" else "drilling", deposit.material.id, drilling.perHour, drilling.stored, drilling.room
end

-- How the reactor stands at the starbase the pilot put up last: "none"
-- (no reactor), "waiting" (one that is not working yet, or has no
-- power), "nothing" (making nothing), "idle" (too little to make it
-- of) or "making"; and what it is set to make ("" for nothing), and how
-- many units it has made since the tower was anchored.
function Debug.Reactor(): (string, string, number)
  local state = session.game.state
  local id = state.starbaseIds[#state.starbaseIds]
  local status = if id then Core.Query.Starbase(session.game, id) else nil
  if status == nil or not status.reacting.anchored then
    return "none", "", 0
  end
  local reacting = status.reacting
  return if not reacting.online then "waiting" elseif reacting.making == nil then "nothing" elseif reacting.starved then "idle" else "making",
    if reacting.making then reacting.making.id else "", state.starbases[id].composed
end

-- What a reactor makes of a moon material: the composite's id, and the
-- other material it is made of ("" and "" for what is no moon material).
function Debug.Composite(material: string): (string, string)
  local composite = Reactions.Of(material)
  if composite == nil then
    return "", ""
  end
  return composite.id, if composite.from[1] == material then composite.from[2] else composite.from[1]
end

-- The running of the starbase the pilot put up last, since it was
-- anchored: the fuel blocks it has burnt, the units its drill has
-- brought up, the units raiders have carried off, and what a day of it
-- costs in fuel and brings up, in credits' worth.
function Debug.Tally(): (number, number, number, number, number)
  local state = session.game.state
  local id = state.starbaseIds[#state.starbaseIds]
  local status = if id then Core.Query.Starbase(session.game, id) else nil
  if status == nil then
    return 0, 0, 0, 0, 0
  end
  local running = status.running
  return running.used, running.raised, running.robbed, running.fuelADay, running.yieldADay
end

-- How safe the system the pilot is in is, and which kind of space that
-- makes it ("secure", "low" or "lawless").
function Debug.Security(): (number, string)
  local player = Core.Query.Player(session.game)
  local _, band = Core.Query.Security(session.game, player.system)
  return player.security, band or ""
end

-- The pirates on the pilot's grid: how many, and how many of them fly
-- a hull of the pirates' own that the scene shows as that hull, with
-- what it has fitted standing on its hardpoints.
function Debug.Pirates(): (number, number)
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local count, drawn = 0, 0
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if me and ball and ball.system == me.system and ball.grid == me.grid then
      count += 1
      local hull = Ships.byId[state.ships[id].type]
      if hull.lineage == "unbound" and Hull.Build(hull.id, true) ~= nil and Scene.Arms(scene, id) > 0 then
        drawn += 1
      end
    end
  end
  return count, drawn
end

-- The other ships about: how many the system has, how many of them are
-- on the pilot's grid, how many ships on the overview would fire on
-- the pilot, how many of the police have come, and how many miners
-- there are (at a belt or going home).
function Debug.Traffic(): (number, number, number, number, number)
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local near, hostile, police, miners = 0, 0, 0, 0
  for _, id in state.trafficIds do
    local ball = state.balls[id]
    local kind = state.traffic[id].kind
    near += if me and ball and ball.grid == me.grid then 1 else 0
    police += if kind == "police" then 1 else 0
    miners += if kind == "miner" or kind == "home" then 1 else 0
  end
  for _, entry in Core.Query.Overview(session.game) do
    hostile += if entry.hostile then 1 else 0
  end
  return #state.trafficIds, near, hostile, police, miners
end

-- Two cheats, for scripted runs that test something other than buying
-- and training: so many of an item from nowhere (into the hangar of the
-- station docked at, else the hold), and a skill at a level.
function Debug.Give(type: string, quantity: number): boolean
  local state = session.game.state
  local ship = state.ships[state.player.ship]
  if Types.Get(type) == nil then
    return false
  end
  Items.Add(state, type, quantity, if ship.docked ~= 0 then ship.docked else ship.id, if ship.docked ~= 0 then "hangar" else "cargo")
  return true
end

-- The other way: every one of a type the pilot has in the hangar of the
-- station docked at is gone (lost, as with a ship). How many went.
function Debug.Lose(type: string): number
  local state = session.game.state
  local ship = state.ships[state.player.ship]
  local gone = 0
  if ship.docked ~= 0 then
    -- ('all': everything there, of whatever type, the corporation's too)
    local stacks: { State.Item } = if type == "all" then Items.Stored(state, ship.docked) else Items.In(state, ship.docked, "hangar")
    for _, item in stacks do
      if item.type == type or type == "all" then
        gone += item.quantity
        Items.Take(state, item, item.quantity)
      end
    end
  end
  return gone
end

function Debug.Train(skill: string, level: number)
  -- ("all": every skill there is)
  if skill == "all" then
    for _, each in Skills.list do
      session.game.state.skills[each.id] = level
    end
    return
  end
  session.game.state.skills[skill] = level
end

-- The pilot's jump drive: how far it reaches, light years (0 for a hull
-- with none), the fuel blocks in the hold and the seconds it is
-- cooling; and, for a system (its number), how far that is, the fuel it
-- would take, whether the jump can be made now, and why not.
function Debug.JumpDrive(system: number?): (number, number, number, number, number, boolean, string)
  local drive = Core.Query.JumpDrive(session.game, system)
  if drive == nil then
    return 0, 0, 0, 0, 0, false, "this hull has no jump drive"
  end
  return drive.range, drive.held, drive.cooling, drive.distance, drive.fuel, drive.ready, drive.why
end

-- The system farthest off that the pilot's jump drive reaches from
-- where they are: its number and its name (0 and "" for none, or for a
-- hull with no drive).
function Debug.JumpReach(): (number, string)
  local drive = Core.Query.JumpDrive(session.game)
  local here = Core.Query.Player(session.game).system
  local systems = session.game.state.galaxy.systems
  local best, most = 0, -1
  for id in systems do
    -- (through space: the map has a height: Describe/Galaxy)
    local far = Galaxy.Apart(session.game.state.galaxy, here, id)
    if drive and id ~= here and far <= drive.range and far > most then
      best, most = id, far
    end
  end
  return best, if best ~= 0 then systems[best].name else ""
end

-- A cheat, for a scripted jump: a tower of the pilot's from nowhere at
-- a moon of a system, lit, with a Jump Beacon anchored and online.
-- False if the system has no moon. (And how many beacons are lit for
-- the pilot: Debug.Beacons.)
function Debug.BeaconAt(system: number): boolean
  local state = session.game.state
  if state.galaxy.systems[system] == nil then
    return false
  end
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "moon" then
      local id = Starbases.Raise(state, system, object, Structures.towerById["tower.vessari.small"], "player",
        object.x + object.radius * 3, object.y, object.z)
      local starbase = state.starbases[id]
      starbase.ready, starbase.fuel, starbase.burnt = state.tick, 5000, state.tick
      table.insert(starbase.modules, { type = Structures.BEACON, ready = state.tick })
      return true
    end
  end
  return false
end

-- The corporation's members (Core/Assets/Members): how many there are,
-- how many there is room for, how many have applied and wait, how many
-- at the station docked at are open to joining, the tax (per cent),
-- And how many calls are posted.
function Debug.Members(): (number, number, number, number, number, number)
  local info = Core.Query.Membership(session.game)
  return #info.members, info.room, #info.applicants, #info.open, math.floor(info.tax * 100 + 0.5), #info.calls
end

-- The nth member: their name, trade, what they are doing, the system
-- they are in by name, and what they have earned in all.
function Debug.Member(n: number): (string, string, string, string, number)
  local member = Core.Query.Membership(session.game).members[n]
  if member == nil then
    return "", "", "", "", 0
  end
  return member.name, member.trade, member.doing, member.system, member.earned
end

-- The inventory (Game/UI/Inventory): how many of its windows are open,
-- and of the first what kind of place it shows ('cargo', 'hangar',
-- 'wreck', ...), how many stacks are listed there, and whether as icons.
function Debug.Inventory(): (number, string, number, boolean)
  return Inventory.Showing()
end

-- Where a window is (Game/UI/Windows), by its id ('inventory'): its
-- corner, its size, and whether it is open. Nothing for no such window.
function Debug.Window(id: string): (number, number, number, number, boolean)
  local window = Windows.Get(id)
  if window == nil then
    return 0, 0, 0, 0, false
  end
  return window.x, window.y, window.w, window.h, window.open
end

-- Carry what is named 'from' to what is named 'to', as a hand with the
-- mouse would (Im.Carry): a stack of the inventory to a place in its
-- tree, GameDebug.Carry('Inv:item:ore.ferrite', 'Inv:onto:hangar').
-- False if either was not drawn last frame.
function Debug.Carry(from: string, to: string): boolean
  return Im.Carry(from, to)
end

-- How many of a type there are in a place of the pilot's: 'cargo',
-- 'hangar', 'dronebay', 'orehold' or 'corporate' (the ship's own, or
-- the station's docked at); or in the wreck or container nearest the
-- ship, 'wreck'.
function Debug.Stacked(type: string, place: string): number
  local state = session.game.state
  local ship = state.ships[state.player.ship]
  local holder, where: string? = ship.id, place
  if place == "hangar" or place == "corporate" then
    holder = ship.docked
  elseif place == "wreck" then
    holder, where = 0, nil
    for _, entry in Core.Query.Places(session.game) do
      if holder == 0 and (entry.kind == "wreck" or entry.kind == "can") then
        holder = entry.holder
      end
    end
  end
  local count = 0
  for _, item in Items.In(state, holder, where) do
    count += if item.type == type then item.quantity else 0
  end
  return count
end

-- A cheat, for the members' ships to look at without waiting for
-- somebody of the right trade: somebody of a trade ('miner', 'fighter',
-- 'hauler' or 'scout') and a name applies to the corporation and is
-- taken, in the hull of a class that trade flies (its first, if none
-- is named). They are a member a tick later. False with no corporation.
function Debug.Enlist(trade: string, name: string, class: string?): boolean
  local state = session.game.state
  if not Corporation.Founded(state) then
    return false
  end
  local home = state.galaxy.systems[Space.SystemOf(state, state.player.home)]
  local people = if home then home.nearest else ""
  local first = { miner = "frigate", fighter = "frigate", hauler = "industrial", scout = "frigate" }
  local hull = Members.HullFor(trade, people, class or first[trade] or "frigate")
  if hull == nil then
    return false
  end
  local key = `cheat:{State.NewId(state)}`
  table.insert(state.membership.applicants, { key = key, name = name, trade = trade, people = people, hull = hull, bears = 0.3,
    until_ = state.tick + Members.DAY })
  return Session.Do(session, { kind = "AcceptMember", actor = 0, what = key })
end

-- The nth member's ship where the pilot is (Core/Tactical/Fellows): the
-- ship (0: none is out), what it is at ('work', 'out', 'home', 'rest',
-- 'away', 'front' or ''), the name of the place that is for, how many
-- ships they have lost, the hull they fly, and what the ship says it
-- is doing ('' with none out).
function Debug.Fellow(n: number): (number, string, string, number, string, string)
  local state = session.game.state
  local member = state.membership.members[state.membership.memberIds[n] or 0]
  if member == nil then
    return 0, "", "", 0, "", ""
  end
  local place = Space.Object(state, member.goal)
  local fellow = Core.Query.Fellow(session.game, member.ship)
  return member.ship, member.task, if place then place.name else "", member.lost, member.hull, if fellow then fellow.doing else ""
end

-- A cheat: the nth member's ship is destroyed, by nobody in particular.
-- False if they have none out.
function Debug.Unship(n: number): boolean
  local state = session.game.state
  local member = state.membership.members[state.membership.memberIds[n] or 0]
  if member == nil or member.ship == 0 or state.balls[member.ship] == nil then
    return false
  end
  Aftermath.Destroy(state, member.ship, 0, session.game.events)
  Members.Lost(state, member, 0, session.game.events)
  return true
end

-- Sovereignty (Core/Assets/Sovereignty). A cheat, for a claim to look
-- at without building a tower: a lit tower of the pilot's with a Claim
-- Beacon online, at a moon of the nearest open system nobody holds (one
-- that has a moon). Returns the system (0 if there is none).
function Debug.ClaimAt(): number
  local state = session.game.state
  local here = Core.Query.Player(session.game).system
  local best, least, at: any = 0, math.huge, nil
  for id = 1, Galaxy.Charted(state.galaxy) do
    local node = state.galaxy.systems[id]
    if node.owner == "" and Galaxy.Apart(state.galaxy, here, id) < least then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "moon" and Galaxy.Apart(state.galaxy, here, id) < least then
          best, least, at = id, Galaxy.Apart(state.galaxy, here, id), object
        end
      end
    end
  end
  if best == 0 then
    return 0
  end
  local id = Starbases.Raise(state, best, at, Structures.towerById["tower.vessari.small"], "player", at.x + at.radius * 3, at.y, at.z)
  local starbase = state.starbases[id]
  starbase.ready, starbase.fuel, starbase.burnt = state.tick, 100000, state.tick
  table.insert(starbase.modules, { type = Structures.CLAIM, ready = state.tick })
  return best
end

-- How the pilot's claim on a system stands ("held", "claiming",
-- "contested" or "none"), the hours gone and the hours it takes, and
-- the system's name. And, given a name, the system is renamed first if
-- it is the pilot's to name.
function Debug.Claim(system: number, name: string?): (string, number, number, string)
  if name then
    Session.Do(session, { kind = "RenameSystem", actor = 0, target = system, what = name })
  end
  local how, gone, takes = Core.Query.Claim(session.game, system)
  return how, gone, takes, session.game.state.galaxy.systems[system].name
end

function Debug.Beacons(): number
  local drive = Core.Query.JumpDrive(session.game)
  return if drive then #drive.beacons else 0
end

-- How the map is looked at: turned so far and tilted so far, radians (a
-- quarter turn of tilt is from straight over it). Given either, it is
-- looked at so. And how many systems the pilot's jump drive reaches.
function Debug.MapView(turn: number?, tilt: number?): (number, number)
  return Map.View(turn, tilt)
end

-- How near the map is looked at (1: all of the galaxy), how many systems
-- are in sight on it, and whether each has its name by it. Given how
-- near, it is looked at so from the next frame; given a system (its
-- number), with that system in the middle.
function Debug.MapZoom(to: number?, system: number?): (number, number, boolean)
  return Map.Zoom(to, system)
end

-- Where a system is on the map, in the window (it may be off the map's
-- edge), or nothing if the map has not been drawn; and the system
-- picked on it (0: none).
function Debug.MapWhere(system: number): (number?, number?)
  local at = Map.Where(system)
  if at then
    return at.x, at.y
  end
  return nil, nil
end

function Debug.MapPicked(): number
  return Map.Picked()
end

function Debug.JumpWithin(): number
  local drive = Core.Query.JumpDrive(session.game)
  local here = Core.Query.Player(session.game).system
  local count = 0
  -- (the systems of the map: no drive goes to the others)
  for id = 1, Galaxy.Charted(session.game.state.galaxy) do
    count += if drive and id ~= here and Galaxy.Apart(session.game.state.galaxy, here, id) <= drive.range then 1 else 0
  end
  return count
end

-- Open the map on a system, as a click on it does (its number).
function Debug.MapOn(system: number): boolean
  if session.game.state.galaxy.systems[system] == nil then
    return false
  end
  Map.Open(system)
  return true
end

-- The pilot's drones: how many are out, how many are in the hold, and
-- how many could be out at once.
function Debug.Drones(): (number, number, number)
  local status = Core.Query.Drones(session.game)
  return status.out, status.carried, status.max
end

-- A cheat, for a wreck to work on without a fight: a pirate scout from
-- nowhere, a kilometre off the pilot's ship, destroyed by nobody.
-- With 'sealed' its hold is sealed, as a derelict's is, and has to be
-- hacked. With 'far' it is that many metres off instead (far enough,
-- and it is off the pilot's grid). Returns false if the pilot is not in
-- space.
function Debug.Wreck(sealed: boolean?, far: number?): boolean
  local state = session.game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return false
  end
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + (far or 1000), me.y, me.z, me.grid)
  Aftermath.Destroy(state, scout.id, 0, session.game.events)
  if sealed then
    state.wrecks[state.wreckIds[#state.wreckIds]].locked = true
  end
  return true
end

-- The hack under way: whether there is one, how many codes are in the
-- buffer and how many it holds, how many of the keys are in, and the
-- seconds its lock allows from the first pick (0: it is on no clock)
-- and has left.
function Debug.Hack(): (boolean, number, number, number, number, number)
  local hack = Core.Query.Hack(session.game)
  if hack == nil then
    return false, 0, 0, 0, 0, 0
  end
  local keys = 0
  for _, key in hack.keys do
    keys += if key.done then 1 else 0
  end
  return true, #hack.buffer, hack.room, keys, hack.clock, hack.left
end

-- The best that can still be made of a hack: the cell to pick next (0
-- if no pick makes it better than it is), and how many keys would be
-- in at the end of it. The safeguards' key counts before any number of
-- the others, and of ways as good the shortest is taken.
local function plan(hack: State.Hack): (number, number)
  local size = hack.size
  local used = table.clone(hack.used)
  local buffer = table.clone(hack.buffer)
  local function worth(): (number, number)
    local score, keys = 0, 0
    for index, key in hack.keys do
      if key.done or Hacking.Holds(buffer, key.codes) then
        keys += 1
        score += if index == 1 then 100 else 10
      end
    end
    return score - 0.01 * #buffer, keys
  end
  local bestScore, bestKeys = worth()
  local bestPick = 0
  local function go(along: string, line: number, first: number)
    if #buffer >= hack.room then
      return
    end
    for at = 1, size do
      local index = if along == "row" then (line - 1) * size + at else (at - 1) * size + line
      if not used[index] then
        used[index] = true
        table.insert(buffer, hack.cells[index])
        local score, keys = worth()
        local pick = if first == 0 then index else first
        if score > bestScore then
          bestScore, bestKeys, bestPick = score, keys, pick
        end
        if along == "row" then
          go("column", at, pick)
        else
          go("row", at, pick)
        end
        table.remove(buffer)
        used[index] = false
      end
    end
  end
  go(hack.along, hack.line, 0)
  return bestPick, bestKeys
end

-- A cheat that plays the hack under way, a pick each time it is asked:
-- the next cell of the best way there is through the matrix (which a
-- pilot has to find by looking), and when no pick would better it, the
-- end. True once no hack is under way. For "until GameDebug.HackOn()".
local planned, plannedTick = "", -1
function Debug.HackOn(): boolean
  local hack = session.game.state.hack
  if hack == nil then
    return true
  end
  -- (worked out once a tick: it is asked every frame)
  if session.game.state.tick ~= plannedTick then
    local pick = plan(hack)
    planned, plannedTick = if pick ~= 0 then `Hack:{pick}` else "Hack:abandon", session.game.state.tick
  end
  Im.Press(planned)
  return false
end

-- How many keys the best way through the lock under way would get in.
function Debug.HackBest(): number
  local hack = session.game.state.hack
  return if hack then select(2, plan(hack)) else 0
end

-- Switch every salvager on, on the nearest wreck. Returns how many started.
function Debug.Salvage(): number
  local wreck = find("wreck")
  local started = 0
  if wreck then
    session.selected = wreck.id
    for _, item in Core.Query.Fitted(session.game, session.game.state.player.ship) do
      if Modules.byId[item.type].salvager and Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = wreck.id }) then
        started += 1
      end
    end
  end
  return started
end

-- How a ship is held (Tactical/Combat): the share of its top speed a
-- entanglement projector leaves it (1 for none), and whether it is kept out of warp.
-- The pilot's own, or with 'target' the first ship they have locked.
function Debug.Held(what: string?): (number, boolean)
  local state = session.game.state
  local ball = state.balls[state.player.ship]
  if what == "target" and ball then
    for _, lock in ball.vitals.locks do
      if lock.locked and state.balls[lock.target] then
        ball = state.balls[lock.target]
        break
      end
    end
  end
  if ball == nil then
    return 1, false
  end
  return ball.vitals.entangle, ball.vitals.scrambled
end

-- What a faction ("vessari", "talmar", ...) thinks of the pilot. Given
-- a number, a cheat: it is set to that.
function Debug.Standing(faction: string, to: number?): number
  if to then
    session.game.state.standings[faction] = math.clamp(to, -10, 10)
  end
  for _, row in Core.Query.Standings(session.game) do
    if row.faction == faction then
      return row.standing
    end
  end
  return 0
end

-- The scan probes: how many are out in this system, and how many are
-- in the hold.
function Debug.Probes(): (number, number)
  local _, _, probes = Core.Query.Sites(session.game)
  return probes.here, probes.carried
end

-- The directional scanner's last scan: how many things it had whose
-- name has 'name' in it (all of them, with no name), how many scans
-- have been made, and how many of those things are off the pilot's grid.
function Debug.Sighted(name: string?): (number, number, number)
  local sightings, scans = Scanner.Sightings()
  local count, off = 0, 0
  for _, sighting in sightings do
    if name == nil or string.find(sighting.name, name, 1, true) then
      count += 1
      off += if sighting.onGrid then 0 else 1
    end
  end
  return count, scans, off
end

-- The scanner: how many sites the system has, how many of them are
-- found, and the name of the first found one of a kind ("ore", "relic",
-- "combat"; "" if there is none).
function Debug.Sites(kind: string?): (number, number, string)
  local sites = Core.Query.Sites(session.game)
  local found, name = 0, ""
  for _, site in sites do
    found += if site.found then 1 else 0
    if site.found and site.kind == kind and name == "" then
      name = site.name
    end
  end
  return #sites, found, name
end

-- Wormholes (Core/Tactical/Wormholes). A cheat, for one to go through
-- without waiting for a day that has one: a wormhole in the system the
-- pilot is in, leading to uncharted space of a depth (1 to 5: 1 if not
-- said; of the nearest depth there is, in a galaxy that has no system
-- of that one), of a size (1 to 3: a great one if not said), found
-- already unless 'hidden'. Returns its place and its name (0 and "" if
-- none could be opened).
function Debug.Wormhole(depth: number?, size: number?, hidden: boolean?): (number, string)
  local state = session.game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return 0, ""
  end
  local to, least = 0, math.huge
  for id = Galaxy.Charted(state.galaxy) + 1, #state.galaxy.systems do
    local off = math.abs((state.galaxy.systems[id].depth or 1) - (depth or 1))
    if id ~= me.system and off < least then
      to, least = id, off
    end
  end
  if to == 0 then
    return 0, ""
  end
  local hole = Wormholes.Open(state, me.system, to, Rng.For(state.historySeed, state.tick, 59), session.game.events, size or 3, not hidden)
  local place = if hole then Space.Object(state, hole.a) else nil
  return if place then place.id else 0, if place then place.name else ""
end

-- The wormholes open in the system the pilot is in: how many, how many
-- of them found, and the place of the first that is found (0 if none).
function Debug.Wormholes(): (number, number, number)
  local state = session.game.state
  local player = Core.Query.Player(session.game)
  local found, first = 0, 0
  local open = Wormholes.In(state, player.system)
  for _, hole in open do
    for _, place in { hole.a, hole.b } do
      local site = state.sites[place]
      if site and site.system == player.system and site.strength >= 1 then
        found += 1
        first = if first == 0 then place else first
      end
    end
  end
  return #open, found, first
end

-- Close every wormhole open in the system the pilot is in, now. Returns how many.
function Debug.CloseWormholes(): number
  local state = session.game.state
  local open = Wormholes.In(state, Core.Query.Player(session.game).system)
  for _, hole in open do
    Wormholes.Close(state, hole, session.game.events)
  end
  return #open
end

-- What a type goes for across the map (Core.Query.Prices): where the
-- pilot is, as a share of its normal price; how many systems within
-- reach have a market; and the lowest and the highest of those.
function Debug.Prices(type: string): (number, number, number, number)
  local here, list = Core.Query.Prices(session.game, type)
  return here, #list, if list[1] then list[1].level else 1, if list[#list] then list[#list].level else 1
end

-- The haulers of the traffic in the pilot's system: how many there
-- are, how many have a hold of the economy's goods, and the name of
-- what the first of those carries ("" if none does). With 'pick', the
-- first of those on the pilot's grid is selected.
function Debug.Hauls(pick: boolean?): (number, number, string)
  local state = session.game.state
  local haulers, laden, first = 0, 0, ""
  for _, id in state.trafficIds do
    local record = state.traffic[id]
    if record.kind == "in" or record.kind == "out" then
      haulers += 1
      local haul = Core.Query.Haul(session.game, id)
      if haul then
        laden += 1
        first = if first == "" then haul.name else first
        local ball, mine = state.balls[id], state.balls[state.player.ship]
        if pick and ball and mine and ball.grid == mine.grid then
          session.selected = id
          pick = false
        end
      end
    end
  end
  return haulers, laden, first
end

-- The factions at war (Core/Strategic/Wars): how many wars there are,
-- how many systems something is being done to, how many open systems
-- are claimed, and how many times a system has changed hands.
function Debug.Wars(): (number, number, number, number)
  local wars = session.game.state.wars
  local claims = 0
  for _ in wars.claims do
    claims += 1
  end
  return #wars.feuds, #wars.operations, claims, wars.version
end

-- The factions' forces where the pilot is (Core/Tactical/Fronts): how
-- many fronts the system has, whether the first is shown as ships, how
-- many ships of the force that came are there and how many of the
-- defence, and how many of all of them count the pilot an enemy.
function Debug.Fronts(): (number, boolean, number, number, number)
  local state = session.game.state
  local front = state.fronts[state.frontIds[1] or 0]
  local came, held, foes = 0, 0, 0
  if front then
    for id, record in front.ships do
      came += if record.attacking then 1 else 0
      held += if record.attacking then 0 else 1
      foes += if state.pilots[id] and state.pilots[id].foe then 1 else 0
    end
  end
  return #state.frontIds, front ~= nil and front.shown, came, held, foes
end

-- A cheat, for a front to look at without waiting for a war: the pilot,
-- in space, is put in the nearest open system (one that is nobody's
-- home), which the second of the galaxy's factions is made to hold and
-- the first to besiege, with forces of so much strength (120 and 90 if
-- not said), the siege past its muster. Returns the system's name ("" if
-- there is nowhere, or the pilot is docked).
function Debug.Front(force: number?, defence: number?): string
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local holders = Galaxy.Holders(state.galaxy)
  if me == nil or #holders < 2 then
    return ""
  end
  local best, least = 0, math.huge
  for id = 1, Galaxy.Charted(state.galaxy) do
    local node = state.galaxy.systems[id]
    local home = node.owner ~= "" and state.wars.claims[id] == nil
    if not home and id ~= me.system and Galaxy.Apart(state.galaxy, me.system, id) < least then
      best, least = id, Galaxy.Apart(state.galaxy, me.system, id)
    end
  end
  if best == 0 then
    return ""
  end
  local by, against = holders[1], holders[2]
  state.galaxy.systems[best].owner = against
  state.wars.claims[best] = against
  state.wars.version += 1
  if not Wars.AtWar(state.wars, by, against) then
    table.insert(state.wars.feuds, { a = by, b = against, since = state.tick, score = 0 })
  end
  table.insert(state.wars.operations, { id = state.tick * 16 + 15, by = by, system = best, kind = "siege", began = state.tick - Wars.STAGE - 1,
    force = force or 120, sent = force or 120, against = against, defence = defence or 90, defended = defence or 90, stage = "blockade",
    relieved = true })
  me.system = best
  me.x, me.y, me.z = 3e9, 0, 0
  me.vx, me.vy, me.vz = 0, 0, 0
  me.warp, me.intent = nil, nil
  Space.AssignGrid(state, me)
  -- (the scene sees that the pilot is somewhere else, and is made again)
  return state.galaxy.systems[best].name
end

-- The last thing the pilot was told (the line under the ship's name), "" if nothing.
function Debug.Said(): string
  return session.message
end

-- Whether the pilot is in uncharted space, and how deep.
function Debug.Uncharted(): (boolean, number)
  local player = Core.Query.Player(session.game)
  return player.uncharted, player.depth
end

-- What the selected-item panel would say of a wormhole: where it leads,
-- its size by name, and whether the pilot's ship fits.
function Debug.WormholeInfo(place: number): (string, string, boolean)
  local info = Core.Query.Wormhole(session.game, place)
  if info == nil then
    return "", "", false
  end
  return info.leads, info.sizeName, info.fits
end

-- A cheat, for a site to work without the finding of it (which is the
-- scanner's work: test/scenario/sites.txt): a site of a kind ("gas",
-- "data", "ore", "relic") in the system the pilot is in, found already,
-- and on the overview. With 'gas', a vapour field's clouds are of that
-- gas. Returns its name ("" if none could be made).
function Debug.Plant(kind: string, gas: string?): string
  local state = session.game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return ""
  end
  local site = Sites.Plant(state, me.system, kind, Rng.For(state.historySeed, state.tick, 57), session.game.events)
  if site == nil then
    return ""
  end
  site.strength = 1
  local made = Ores.gasById[gas or ""]
  if made then
    for _, object in Space.Describe(state, me.system).objects do
      if object.site == site.id and object.kind == "asteroid" then
        object.variety, object.name = made.id, made.name
      end
    end
  end
  local place = Space.Object(state, site.id)
  return if place then place.name else ""
end

-- The pilot's boosters: how many are at work, how many kinds of them
-- are to hand (in the hold, and in the hangar where docked), and the
-- seconds the first at work has left.
function Debug.Boosters(): (number, number, number, boolean)
  local working, hand = Core.Query.Boosters(session.game)
  return #working, #hand, if working[1] then working[1].left else 0, working[1] ~= nil and working[1].wrong
end

-- An attribute of the pilot's ship as it is fitted and flown ("shield",
-- "armor", "maxVelocity", ...), with whatever is at work on the pilot.
function Debug.Stat(name: string): number
  local state = session.game.state
  return Items.ShipStats(state, state.player.ship)[name] or 0
end

-- What the nth agent of the station docked at thinks of the pilot (1
-- to 3 the day's, 4 the assaults', 5 the mining contracts', 6 the
-- courier contracts', 7 the defence jobs'); with
-- 'set', a cheat that makes it so.
function Debug.Regard(agent: number, set: number?): number
  local state = session.game.state
  local station = Core.Query.Player(session.game).docked
  if set then
    state.regard[`{station}:{agent}`] = set
  end
  return state.regard[`{station}:{agent}`] or 0
end

-- Jobs: how many the station docked at offers, how many are in hand,
-- how many have been finished, and the standing with the faction whose
-- station it is.
function Debug.Missions(): (number, number, number, number)
  local status = Core.Query.Missions(session.game)
  return #status.offers, #status.inHand, status.done, status.standing
end

-- Which of the jobs the station docked at offers is the first of a kind
-- ("bounty", "courier", "supply", "assault", "mining", "defence"): its
-- place in the Core's list, or 0 for none. (The day's three are
-- "Accept:<n>" on the screen, by their place among themselves; the
-- four agents whose work has levels have "Accept:assault",
-- "Accept:mining", "Accept:courier" and "Accept:defence", at the level
-- the list shows: "Level:<kind>:up" and "Level:<kind>:down" step it,
-- and GameDebug.Level(kind, n) sets it.)
function Debug.Offer(kind: string): number
  for index, offer in Core.Query.Missions(session.game).offers do
    -- (a defence job is an assault to the rules, and not to anybody asking)
    if offer.line == kind or (offer.mission.kind == kind and offer.line ~= "defence") then
      return index
    end
  end
  return 0
end

-- The first defence job in hand: the name of the place its rig is at
-- ("" with none in hand), the waves that have come and how many there
-- are, the ships destroyed and how many there are, how much of the rig
-- is left, 0 to 1 (-1 until the pilot has been there), the system the
-- place is in, and whether it is an escort: a tender to see through,
-- of which what is done and wanted is 1, the tender getting there (or,
-- for a convoy, 2: the tender getting away from its place, and in to
-- the station; the ninth value says whether it is one).
function Debug.Defence(): (string, number, number, number, number, number, number, boolean, boolean)
  for _, held in Core.Query.Missions(session.game).inHand do
    local mission = held.mission
    if held.line == "defence" then
      local place = Core.Query.Body(session.game, mission.site)
      return if place then place.name else "?", mission.wave, #mission.waves, mission.done, mission.need, held.ward, mission.system,
        mission.aim == "escort" or mission.aim == "convoy", mission.aim == "convoy"
    end
  end
  return "", 0, 0, 0, 0, -1, 0, false, false
end

-- How many defence jobs the seventh agent of the station docked at has
-- given (every third is an escort, and every sixth a convoy); with a
-- number, a cheat that makes it so.
function Debug.Holds(set: number?): number
  local state = session.game.state
  local station = Core.Query.Player(session.game).docked
  if set then
    state.holds[station] = set
  end
  return state.holds[station] or 0
end

-- A cheat, for a scripted loss: the rig of the first defence job in
-- hand is destroyed, as if by whoever came for it. False if no such
-- rig stands.
function Debug.Sink(): boolean
  local state = session.game.state
  for _, held in Core.Query.Missions(session.game).inHand do
    if held.line == "defence" and state.balls[held.mission.mark] then
      Aftermath.Destroy(state, held.mission.mark, 0, session.game.events)
      return true
    end
  end
  return false
end

-- The level of a kind of job ("assault", "mining", "courier",
-- "defence") the Missions tab shows; given one, it is set to that. 0:
-- the hardest there is.
function Debug.Level(kind: string, to: number?): number
  return Station.Level(kind, to)
end

-- The first courier contract in hand (the sixth agent's: one with a
-- level): the cubic metres it wants carried (0 with none in hand), the
-- name of the station they go to, the system that is in, and how many
-- jumps off it is by the way the contract counts.
function Debug.Run(): (number, string, number, number)
  for _, held in Core.Query.Missions(session.game).inHand do
    local mission = held.mission
    if mission.kind == "courier" and mission.level > 0 then
      local to = Core.Query.Body(session.game, mission.to)
      return mission.need, if to then to.name else "?", mission.system, held.jumps
    end
  end
  return 0, "", 0, 0
end

-- The first mining contract in hand: the ore it wants ("" with none in
-- hand), how many units, the name of its pocket, and the system that
-- is in.
function Debug.Contract(): (string, number, string, number)
  for _, held in Core.Query.Missions(session.game).inHand do
    local mission = held.mission
    if mission.kind == "mining" then
      local place = Core.Query.Body(session.game, mission.site)
      return mission.type, mission.need, if place then place.name else "?", mission.system
    end
  end
  return "", 0, "", 0
end

-- A cheat, for a scripted contract: with no mining laser cutting, the
-- nearest rock on the grid is locked and every laser put on it. Asked
-- every frame, it gives an order only once a tick and only where one
-- is wanted. Returns how many units of an ore are in the hold.
local dug = -1
function Debug.Dig(ore: string): number
  local game = session.game
  local state = game.state
  local me = state.balls[state.player.ship]
  if me and state.tick ~= dug then
    dug = state.tick
    local lasers: { State.Item } = {}
    local cutting = false
    for _, item in Core.Query.Fitted(game, me.id) do
      if Modules.byId[item.type].miner then
        table.insert(lasers, item)
        for _, running in me.vitals.running do
          cutting = cutting or running.item == item.id
        end
      end
    end
    local rock = find("asteroid")
    if rock and not cutting then
      local locked, targeted = false, false
      for _, lock in me.vitals.locks do
        if lock.target == rock.id then
          targeted, locked = true, lock.locked
        end
      end
      if not targeted then
        me.vitals.locks = {}
        Session.Order(session, "LockTarget", rock.id)
      elseif locked then
        for _, item in lasers do
          Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = rock.id })
        end
      end
    end
  end
  return Debug.Hold(ore)
end

-- The first assault in hand: the name of its camp ("" with no assault
-- in hand), the waves that have come and how many there are, what the
-- job counts that is done and how many there are of it, the rooms of
-- the camp whose way is found and how many it has, and what the job is
-- to do there ("clear", "raze", "chief" or "fetch").
function Debug.Assault(): (string, number, number, number, number, number, number, string)
  for _, held in Core.Query.Missions(session.game).inHand do
    local mission = held.mission
    if held.line == "assault" then
      local camp = Core.Query.Body(session.game, mission.site)
      local open = 0
      for _, room in mission.rooms do
        open += if Core.Query.Found(session.game, room) then 1 else 0
      end
      return if camp then camp.name else "?", mission.wave, #mission.waves, mission.done, mission.need, open, #mission.rooms, mission.aim
    end
  end
  return "", 0, 0, 0, 0, 0, 0, ""
end

-- A cheat, for a picture or a scripted fight: a pirate of a kind, as
-- Tactical/Pirates names them ('raider', 'battery', ...), so far from
-- the pilot's ship (3 km, if not said) and so far round it (radians).
-- False if there is no such kind, or the pilot is not in space.
function Debug.Pirate(kind: string, far: number?, round: number?): boolean
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local what = Pirates.kindById[kind]
  if me == nil or what == nil then
    return false
  end
  local out, angle = far or 3000, round or 0
  local ball = Pirates.Spawn(state, what, me.system, me.x + out * math.cos(angle), me.y, me.z + out * math.sin(angle), me.grid)
  table.insert(session.game.events, { kind = "BallAdded", ball = ball.id })
  return true
end

-- The fleet's log (the Crew tab's 'Crew:log', and 'Crew:pilots' back):
-- how many fights are on record, and of the latest how many of those
-- who came were destroyed, how many ships of the pilot's were lost,
-- what it paid, and whether it is over.
function Debug.FleetLog(): (number, number, number, number, boolean)
  local log = Core.Query.FleetLog(session.game)
  local last = log[1]
  if last == nil then
    return 0, 0, 0, 0, false
  end
  local destroyed = 0
  for _, entry in last.destroyed do
    destroyed += entry.count
  end
  return #log, destroyed, #last.lost, last.bounty, last.ended ~= 0
end

-- Which side of the Crew tab is shown: 'pilots' or 'log'.
function Debug.CrewPage(): string
  return Station.CrewPage()
end

-- How a fleet's warp stands (the fleet panel's 'Fleet:warp', to what is
-- selected): whether the pilot's ship is in one, forming up or under
-- way; how many hired pilots it called to go with it; and how many of
-- them are in it now, turned for it or in warp with the pilot.
function Debug.FleetWarp(): (boolean, number, number)
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local warp = if me then me.warp else nil
  if me == nil or warp == nil or warp.gang ~= me.id then
    return false, 0, 0
  end
  local with = 0
  for _, id in state.fleetIds do
    local ball = state.balls[state.fleet[id].ship]
    if ball and ball.warp and ball.warp.gang == me.id and ball.warp.stage == warp.stage then
      with += 1
    end
  end
  return true, warp.expect or 0, with
end

-- A cheat: every pirate on the pilot's grid is brought down to a share
-- of all it has (shield first, then armour, then hull), as if it had
-- been shot that far. How many there were.
function Debug.Maul(share: number): number
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local count = 0
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if me and ball and ball.system == me.system and ball.grid == me.grid then
      local v = ball.vitals
      local keep = share * (v.shieldMax + v.armorMax + v.hullMax)
      v.hull = math.min(v.hullMax, keep)
      v.armor = math.min(v.armorMax, keep - v.hull)
      v.shield = math.min(v.shieldMax, keep - v.hull - v.armor)
      count += 1
    end
  end
  return count
end

-- How many of the things a pirate camp is built of (hulls of the class
-- "works") are on the pilot's grid, and how many of them the scene shows
-- with weapons on them.
function Debug.Works(): (number, number)
  local state = session.game.state
  local me = state.balls[state.player.ship]
  local count, armed = 0, 0
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if me and ball and ball.system == me.system and ball.grid == me.grid and Ships.byId[state.ships[id].type].class == "works" then
      count += 1
      armed += if Scene.Arms(scene, id) > 0 then 1 else 0
    end
  end
  return count, armed
end

-- A cheat, for a scripted fight: the pilot's ship goes for the nearest
-- ship on its grid that would fire on it. It orbits it (at 2.5 km, or
-- the range given), locks it, and switches on everything it has for
-- another ship. Asked every frame, it gives an order only once a tick
-- and only where one is wanted. Returns how many such ships are there.
-- 'works': what a camp is built of is gone for first, while any of it
-- stands, whoever else is nearer.
local engaged = -1
function Debug.Engage(range: number?, works: boolean?): number
  local game = session.game
  local state = game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return 0
  end
  local nearest: Core.Entry? = nil
  local built: Core.Entry? = nil
  local count = 0
  for _, entry in Core.Query.Overview(game) do
    if entry.hostile and entry.onGrid then
      count += 1
      nearest = nearest or entry
      local ship = state.ships[entry.id]
      if works and built == nil and ship and Ships.byId[ship.type].class == "works" then
        built = entry
      end
    end
  end
  nearest = built or nearest
  if nearest == nil or state.tick == engaged then
    return count
  end
  engaged = state.tick
  if not (me.mode == "orbit" and me.target == nearest.id) then
    Session.Order(session, "Orbit", nearest.id, range or 2500)
  end
  local targeted, locked = false, false
  for _, lock in me.vitals.locks do
    if lock.target == nearest.id then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    Session.Order(session, "LockTarget", nearest.id)
  elseif locked then
    for _, item in Core.Query.Fitted(game, me.id) do
      local module = Modules.byId[item.type]
      local on = false
      for _, running in me.vitals.running do
        on = on or running.item == item.id
      end
      if not on and (module.weapon or (module.hex and not Modules.Friendly(module))) then
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = nearest.id })
      elseif not on and (module.repair or module.boost) then
        -- (and what it has for itself: a repairer, an afterburner)
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id })
      end
    end
  end
  return count
end

-- How many volleys of a station's batteries the scene has shown.
function Debug.Battery(): number
  return scene.volleys
end

-- Whether the factions' patrols take the pilot for a criminal just now.
function Debug.Marked(): boolean
  return session.game.state.tick < session.game.state.player.marked
end

-- Sound, which a script does not get unless it asks: on or off, and how
-- loud all of it is (0 runs the sound's code without a noise). Returns
-- how many sounds have been started so far.
function Debug.Sound(on: boolean?, master: number?): number
  if on ~= nil then
    Audio.Set(audio, on, master)
  end
  return audio.played
end

-- The nearest planet of the pilot's system that people live on (or,
-- with false, that nobody does): its name, "" if there is none such.
function Debug.World(lived: boolean?): string
  for _, entry in Core.Query.Overview(session.game) do
    if entry.kind == "planet" and Planet.Inhabited(entry.variety) == (lived ~= false) then
      return entry.name
    end
  end
  return ""
end

-- The air of the place the pilot is at, as the sound has it ("gate",
-- "belt", "gas", "relic", "data", "pirates", or where people live, at a
-- station or near a planet of theirs, "chatter.thin", "chatter.light"
-- or "chatter.busy"; "" for none), and how many loops of it are playing
-- (two, while one fades out under another). With the sound off it is
-- always "" and none.
function Debug.Air(): (string, number)
  return audio.airIs, #audio.air
end

-- The hulls whose weapons do not stand wholly on them (Hull.Audit):
-- each is printed, and how many there are is returned.
function Debug.Hulls(): number
  local found = Hull.Audit()
  for _, line in found do
    print("hanging: " .. line)
  end
  return #found
end

-- Draw a hull type from a seed of the old generator's from now on, at
-- a size from 1 to 8 (Hull.Seed: the browser, bin/launch hulls, is where
-- seeds are looked through). A ship already in the scene keeps its
-- looks until it is drawn again: undock, or board another. False, and
-- why, if there is no such hull or the seed has not the room for its
-- hardpoints. 'style' names one of the generator's styles (Hull.STYLES),
-- its own if not said. It is drawn as the generator made it, in bare
-- metal, unless 'painted' is true: then in the hull's own paint, as the
-- game's hulls are drawn. (resource/hull/seeds.txt does the same for good.)
function Debug.HullSeed(type: string, seed: number, size: number, style: string?, painted: boolean?): (boolean, string)
  return Hull.Seed(type, seed, size, style, painted)
end

-- What is set in the menu's options: whether there is sound, and how
-- loud its effects and its music are, of 100. (A script's run stays as
-- silent as it was whatever is set.)
function Debug.Options(): (boolean, number, number)
  return settings.sound, settings.effects, settings.music
end

-- The music: the mood it is in ("docked", "space", "combat"; "" with
-- the sound off), the piece playing, and how many pieces have been begun.
function Debug.Music(): (string, string, number)
  return audio.music.mood, audio.music.file, audio.music.changes
end

-- The levels the pilot has researched of a blueprint: materials, time.
function Debug.Researched(type: string): (number, number)
  local status = Core.Query.Research(session.game, type)
  if status == nil then
    return -1, -1
  end
  return status.material, status.time
end

-- Open the colonies window on a planet (a kind or part of a name, as
-- for Order), or on the pilot's first colony.
function Debug.Colony(what: string?): boolean
  local entry = if what then find(what) else nil
  if what and entry == nil then
    return false
  end
  Colony.Open(if entry then entry.id else nil)
  return true
end

-- The raw material that is the planet in the colonies window's nth
-- deposit, and what a processor makes of it: "" if it has not so many.
function Debug.Deposit(n: number): (string, string)
  local deposit = Core.Query.Deposits(session.game, Colony.Showing())[n]
  return if deposit then deposit.raw else "", if deposit then Planets.productOf[deposit.raw].id else ""
end

-- The colony in the colonies window: how many facilities it has, how
-- many of them are working, and how many of a type are in its store.
-- Nothing (-1) if the planet shown has no colony.
function Debug.Colonised(type: string?): (number, number, number)
  local status = Core.Query.Colony(session.game, Colony.Showing())
  if status == nil then
    return -1, 0, 0
  end
  local working, stored = 0, 0
  for _, facility in status.facilities do
    working += if facility.working then 1 else 0
  end
  for _, held in status.store do
    stored += if held.type == type then held.quantity else 0
  end
  return #status.facilities, working, stored
end

-- The menus: open the opening one or the one in play, as a person would
-- get them (a script starts in the game, not at the menu), and say
-- which page is up ("" for none).
function Debug.Menu(which: string?): string
  if which == "main" then
    Menu.OpenMain(session)
  elseif which == "pause" and not Menu.IsOpen() then
    Menu.Toggle(session)
  end
  return Menu.Page()
end

-- Begin a new game, of a seed and so many systems (three if not said),
-- as the menu's New game does.
function Debug.NewGame(seed: number, systems: number?)
  Session.Restart(session, seed, seed, systems)
end

-- A cheat, for looking at places a long way off: while docked, the
-- pilot and the ship they are aboard are moored at the first station of
-- another system instead. 'what' is the system's number, or a faction's
-- id for the first system whose stations are that faction's; and for a
-- people who have no stations but their colony ships (the Kethri), the
-- first of those, wherever it is. The name of the station; "" if not
-- docked, or there is no such place.
function Debug.Moor(what: number | string): string
  local state = session.game.state
  local ship = state.ships[state.player.ship]
  if ship == nil or ship.docked == 0 then
    return ""
  end
  for index, fleet in Nomads.Fleets(state.galaxy) do
    if fleet.faction == what then
      ship.docked = Nomads.StationId(index)
      -- (the system it is in is seen, as it would be had the pilot flown there)
      Space.Describe(state, Space.SystemOf(state, ship.docked))
      session.selected = 0
      return fleet.name
    end
  end
  for id, node in state.galaxy.systems do
    if id == what or node.nearest == what then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "station" then
          ship.docked = object.id
          session.selected = 0
          return object.name
        end
      end
    end
  end
  return ""
end

-- Set where the pilot means to go: a system by name or number. Returns
-- the jumps there by the way chosen (-1: no such system). With no
-- argument, the jumps left to where they already mean to go (-1: nowhere).
function Debug.Destination(what: (string | number)?, safest: boolean?): number
  local systems = session.game.state.galaxy.systems
  if what ~= nil then
    local found = 0
    for id, system in systems do
      if id == what or (type(what) == "string" and string.lower(system.name) == string.lower(what)) then
        found = id
      end
    end
    if found == 0 then
      return -1
    end
    session.destination = found
    session.safest = safest == true
  end
  return #Session.Route(session) - 1
end

-- Switch the autopilot on or off, and say whether it is on.
function Debug.Autopilot(on: boolean?): boolean
  if on ~= nil then
    session.autopilot = on and session.destination ~= 0
  end
  return session.autopilot
end

-- The system farthest (in jumps, by the safest way) from where the
-- pilot is that is not lawless and has a station in it (the nomads'
-- space has none: their colony ships are their stations, and roam): its
-- name, how many jumps it is, and its number. Somewhere to send an
-- autopilot, and to dock at the end of it.
function Debug.Far(): (string, number, number)
  local galaxy = session.game.state.galaxy
  local here = Core.Query.Player(session.game).system
  local best, most = here, 0
  for id, system in galaxy.systems do
    local moorings = false
    for _, object in Space.Glance(session.game.state, id).objects do
      moorings = moorings or object.kind == "station"
    end
    if system.security >= 0.3 and moorings then
      local jumps = #Galaxy.Route(galaxy, here, id, true) - 1
      if jumps > most then
        best, most = id, jumps
      end
    end
  end
  return galaxy.systems[best].name, most, best
end

-- How many systems the galaxy has, and the name of the faction whose
-- the pilot's is ("" if nobody's).
function Debug.Galaxy(): (number, string)
  -- (the systems of the map: uncharted space is as many again, and is not counted)
  return Galaxy.Charted(session.game.state.galaxy), Core.Query.Player(session.game).owner
end

-- How whole the pilot's ship is, in space: the shares of its shield
-- (-1 for a hull that has none: the Nimia's), its armour and its hull
-- that it has. Given shares of armour and hull, a cheat: it has those
-- (to see a hull that mends by itself mend). Nothing, docked.
function Debug.Layers(armor: number?, hull: number?): (number, number, number)
  local ball = session.game.state.balls[session.game.state.player.ship]
  if ball == nil then
    return 0, 0, 0
  end
  local v = ball.vitals
  if armor then
    v.armor = armor * v.armorMax
  end
  if hull then
    v.hull = hull * v.hullMax
  end
  return if v.shieldMax > 0 then v.shield / v.shieldMax else -1, v.armor / v.armorMax, v.hull / v.hullMax
end

-- The nomads' first colony fleet (or the one of a number): the system
-- it is in, what its colony ship is called, in how many seconds it goes,
-- and the name of the gate it lies off there (the one it will go out
-- by); 0 and "" with no such fleet.
function Debug.Nomads(which: number?): (number, string, number, string)
  local fleet = Core.Query.Nomads(session.game)[which or 1]
  if fleet == nil then
    return 0, "", 0, ""
  end
  local gate = ""
  for _, object in Space.Describe(session.game.state, fleet.system).objects do
    if object.kind == "gate" and object.to == fleet.next then
      gate = object.name
    end
  end
  return fleet.system, fleet.name, fleet.leaves, gate
end

-- The seed of the galaxy being played.
function Debug.Seed(): number
  return session.game.state.galaxySeed
end

-- A cheat, for scripted runs that test something other than earning:
-- credits from nowhere, entered in the journal as such.
function Debug.Grant(credits: number)
  Wallet.Pay(session.game.state, credits, "cheat", session.game.events)
end

-- Another cheat, for looking at hulls: while docked, a hull of a type
-- from nowhere, boarded whatever the pilot's skills, and fitted with
-- what its design is shown with (Game/View/Hull), loaded, as far as
-- that fits, with more of what it fires in the hold; and with 'tank',
-- a plain fit's afterburner, extenders, plates and repairer beside. The
-- ship stepped out of stays in the hangar. False if not docked, or
-- there is no such hull.
function Debug.Fly(type: string, tank: boolean?): boolean
  local state = session.game.state
  local old = state.ships[state.player.ship]
  local hull = Ships.byId[type]
  if old == nil or old.docked == 0 or hull == nil then
    return false
  end
  local ship = Space.NewShip(state, hull.id, hull.name, "player", old.docked)
  local built = Hull.Build(type)
  local types: { string } = {}
  local carried: { [string]: boolean } = {}
  local wanted: { string } = if built then built.fit else {}
  for _, module in wanted do
    table.insert(types, module)
    if Attributes.Check(hull, types) then
      local weapon = Modules.byId[module].weapon
      local charge: string? = nil
      if weapon then
        for _, candidate in Modules.charges do
          if candidate.family == weapon.family and candidate.size == weapon.size then
            charge = candidate.id
            break
          end
        end
      end
      Items.Equip(state, ship.id, module, charge)
      -- (and more of what it fires in the hold, a crystal aside, which lasts)
      local loaded = if charge then Modules.chargeById[charge] else nil
      if charge and loaded and loaded.family ~= "laser" and not carried[charge] then
        carried[charge] = true
        Items.Add(state, charge, if loaded.family == "missile" then 150 else 1500, ship.id, "cargo")
      end
    else
      table.remove(types)
    end
  end
  -- With 'tank', what a plain fit has beside its weapons, as far as it
  -- fits: an afterburner, two shield extenders, a plate, a repairer, a
  -- damage control and another plate, of the hull's size.
  if tank then
    -- (Core/Fits says what a plain tank is: the balance report's is the same)
    for _, module in Fits.Tank(hull) do
      table.insert(types, module)
      if Modules.byId[module] and Attributes.Check(hull, types) then
        Items.Equip(state, ship.id, module, nil)
      else
        table.remove(types)
      end
    end
  end
  state.player.ship = ship.id
  return true
end

-- A cheat, for a hired pilot to have something to fly: while docked, a
-- second ship of a hull type in the hangar, with a module in each of
-- two turrets (or as many as it has): a small autocannon and rounds
-- for it, unless another is named (a mining laser, say).
function Debug.Spare(type: string, module: string?): boolean
  local state = session.game.state
  local mine = state.ships[state.player.ship]
  local hull = Ships.byId[type]
  local fitted = Modules.byId[module or "autocannon.small"]
  if mine == nil or mine.docked == 0 or hull == nil or fitted == nil then
    return false
  end
  local ship = Space.NewShip(state, hull.id, "Spare " .. hull.name, "player", mine.docked)
  for _ = 1, math.min(2, hull.turrets) do
    Items.Equip(state, ship.id, fitted.id, if fitted.weapon then "ammo.emp" else nil)
  end
  if fitted.weapon then
    Items.Add(state, "ammo.emp", 2000, ship.id, "cargo")
  end
  return true
end

-- The pilot's loyalty points with the faction whose station they are
-- docked at (0 in space). Given a number, a cheat: they are set to it.
function Debug.Loyalty(points: number?): number
  local state = session.game.state
  local docked = state.ships[state.player.ship].docked
  if docked == 0 then
    return 0
  end
  local faction = state.galaxy.systems[Core.Query.Player(session.game).system].nearest
  if points then
    state.loyalty[faction] = points
  end
  return state.loyalty[faction] or 0
end

-- The guide: how many of its steps the pilot has done, of how many, and
-- whether a step named ("undock", "kill": Core/Character/Guide) is done.
function Debug.Guide(step: string?): (number, number, boolean)
  local rows, count = Core.Query.Guide(session.game)
  local done = false
  for _, row in rows do
    done = done or (row.step.id == step and row.done)
  end
  return count, #rows, done
end

-- Ships drawn this frame that are in warp, going or coming (not the
-- pilot's own): the scene's count.
function Debug.Passing(): number
  return scene.passing
end

-- A ship on the pilot's grid, not the pilot's own, that is about to
-- leave it (turning to its warp): its name, or "". The camera is set to
-- follow it, so that its going can be watched; and afterwards, whether
-- the ship last named so is still drawn, and in warp.
local leaving = 0
function Debug.Leaving(): (string, boolean)
  local state = session.game.state
  local mine = state.balls[state.player.ship]
  local last = state.balls[leaving]
  local proxy: Object? = scene.proxies[leaving]
  local seen = last ~= nil and last.warp ~= nil and last.warp.stage == "warp" and proxy ~= nil
  if mine then
    for _, id in state.ballIds do
      local ball = state.balls[id]
      if id ~= mine.id and ball.system == mine.system and ball.grid == mine.grid and mine.grid ~= 0 and ball.warp
        and ball.warp.stage == "align" then
        leaving = id
        session.selected = id
        Scene.Track(scene, id)
        return ball.name, seen
      end
    end
  end
  return "", seen
end

-- How far a planet or moon has turned on its axis, in turns, and how
-- many of them there are that turn: the first that 'what' names (a kind,
-- or part of a name).
function Debug.Turned(what: string): (number, number)
  local turned, count = -1, 0
  for _, object in Core.Query.Objects(session.game, Core.Query.Player(session.game).system) do
    local world = scene.worlds[object.id]
    if world then
      count += 1
      if turned < 0 and (object.kind == what or string.find(object.name, what, 1, true)) then
        local look = world.body:GetLook()
        local east = vector.cross(world.axis, world.fore)
        turned = (math.atan2(vector.dot(look, east), vector.dot(look, world.fore)) / (2 * math.pi)) % 1
      end
    end
  end
  return turned, count
end

-- Where the pilot is next to go (Game/Waypoints): how many places of
-- this system are picked out, and the name of the first of a kind of
-- reason ("route", "job", "lesson"; any, if none is said), or "".
function Debug.Next(why: string?): (number, string)
  local count, name = 0, ""
  local marks = Waypoints.Of(session)
  for _, entry in Core.Query.Overview(session.game) do
    if marks[entry.id] then
      count += 1
      if name == "" and (why == nil or marks[entry.id] == why) then
        name = entry.name
      end
    end
  end
  return count, name
end

-- A career agent (Core/Character/Careers: "flight", "industry", "trade",
-- "combat", "survey"): how many of their lessons are done, whether the
-- next is in hand, how much of what that wants is done and of how much,
-- and whether it can be taken or reported now.
function Debug.Career(id: string): (number, boolean, number, number, boolean)
  for _, row in Core.Query.Careers(session.game).rows do
    if row.career.id == id then
      return row.done, row.taken, row.have, row.need, row.can
    end
  end
  return -1, false, 0, 0, false
end

-- What the camera is following (the id of something on the grid, or
-- 0), and where it is looking from: its yaw and pitch.
function Debug.Tracking(): (number, number, number)
  return scene.tracking, scene.yaw, scene.pitch
end

-- Where pirates are massing (Tactical/Surges): the system's id (0 with
-- no surge on), how many jumps off it is, and the seconds it has left.
function Debug.Surge(): (number, number, number)
  local surge = Core.Query.Surge(session.game)
  if surge == nil then
    return 0, 0, 0
  end
  return surge.system, surge.jumps, surge.left
end

-- How many times a gate in sight has been lit by a ship going through
-- it (the pilot's own, or anybody's).
function Debug.GatesLit(): number
  return scene.gates
end

-- Whether the pilot's own ship is drawn cloaked (as light bending round
-- it, not as a hull), and how many things are on its hardpoints in the
-- scene (nothing is, while it is).
function Debug.Ghost(): (boolean, number)
  local id = session.game.state.player.ship
  local armed = scene.arms[id]
  local mounted = 0
  if armed then
    for _, point in armed.points do
      mounted += #point.arms
    end
  end
  return scene.ghosts[id] == true, mounted
end

-- Press a key by its name ("Q", "Space", "Tab", "F1": Game/UI/Keys), as
-- a pilot at the keyboard would. False if there is no such key.
function Debug.Key(name: string): boolean
  return Keys.Press(name)
end

-- Give a thing another key, as the keys page of the menu does ("stop",
-- "X"). False if there is no such thing or no such key.
function Debug.Bind(action: string, key: string): boolean
  return Keys.Bind(action, key)
end

-- The key a thing has ("stop": "Space"), as it is shown; and, for the
-- keys page of the menu, the thing it is listening for a key for ("").
function Debug.KeyOf(action: string): (string, string)
  return Keys.Of(action), Menu.Asking()
end

-- What the nth hired pilot is doing ("following", "mining", "taking
-- ore in", "carrying" and so on: Core.Query.Fleet), the units they have
-- brought in, mined or hauled, what they have learned toward their next
-- grade, their grade, what selling what they bring in has made,
-- whether they are told to sell it, and whether somebody is after them
-- with the player elsewhere; and, for one set to haul, how many
-- stations their round collects at; and, for one sent to buy, how many
-- are still to be bought; how many stations a haul carries to, a load
-- to each in turn; and the word for how they stand toward the pilot
-- ("steady", "devoted" and so on). "" and 0 for nobody.
function Debug.Crew(n: number): (string, number, number, number, number, boolean, boolean, number, number, number, string)
  local row = Core.Query.Fleet(session.game)[n]
  if row == nil then
    return "", 0, 0, 0, 0, false, false, 0, 0, 0, ""
  end
  return row.doing, row.hauled, row.experience, row.skill, row.earned, row.sells, row.hunted, #row.stops, row.need, row.drops, row.mood
end

-- A cheat, for a round of several stations to have something to
-- collect: so much of a type into the player's hangar at the nth place
-- the first hired pilot's haul could be to (the Crew tab's "to" goes
-- round them in this order). False if there is no such place.
function Debug.Stock(n: number, type: string, quantity: number): boolean
  local game = session.game
  local first = Core.Query.Fleet(game)[1]
  local target = if first then Core.Query.HaulTargets(game, first.id, nil)[n] else nil
  if target == nil then
    return false
  end
  -- (where the hired pilots collect: the corporation's hangar, once there is a corporation)
  Items.Add(game.state, type, quantity, target.id, Corporation.Store(game.state))
  return true
end

-- The hired pilots: how many there are, how many are in space on the
-- pilot's grid, how many have a ship that is docked, and how many are
-- pointed at something.
function Debug.Fleet(): (number, number, number, number)
  local near, docked, engaged = 0, 0, 0
  local rows = Core.Query.Fleet(session.game)
  for _, row in rows do
    near += if row.near then 1 else 0
    docked += if row.ship ~= 0 and string.sub(row.where, 1, 6) == "docked" then 1 else 0
    engaged += if row.target ~= 0 then 1 else 0
  end
  return #rows, near, docked, engaged
end

-- The weapon models standing on the mounts of the pilot's ship (two to
-- a fitted weapon), and how far from its target the worst-pointed of
-- the turrets that are firing still is (radians, or -1 if none has a
-- target).
function Debug.Arms(): (number, number)
  return Scene.Arms(scene, session.game.state.player.ship)
end

function Debug.Hash(): string
  return Core.Hash(session.game)
end

function Debug.Tick(): number
  return session.game.state.tick
end

function Debug.Save(slot: string): boolean
  return Session.Save(session, slot)
end

-- (With 'away': as if so many seconds had gone by since the save was
-- made, which is given to the pilot's training. A script's own loads
-- give it none.)
function Debug.Load(slot: string, away: number?): boolean
  return Session.Load(session, slot, away)
end

function App:Initialize()
  local camera = Camera_Create()
  camera:Push()
  session = Session.New(1, 1)
  scene = Scene.New(camera)
  audio = Audio.New()
  -- What a person set last time: sound or none, and how loud. (A script
  -- has no sound unless it asks, whatever anybody has set.)
  settings = Settings.Load()
  if not Host.scripted then
    Audio.Set(audio, settings.sound, settings.effects / 100, settings.music / 100)
  end
  -- (the menu's options: heard at once, and kept when a thing is set)
  Menu.Sound(settings.sound, settings.effects, settings.music, function(on: boolean, effects: number, music: number, done: boolean)
    settings.sound, settings.effects, settings.music = on, effects, music
    if not Host.scripted then
      Audio.Set(audio, on, effects / 100, music / 100)
    end
    if done then
      Settings.Save(settings)
    end
  end)
  -- (and where the windows that are moved about were left: App:OnUpdate keeps it)
  Windows.Restore(settings.windows)
  -- (and the keys a person has changed, kept when one changes hands)
  Keys.Import(settings.keys)
  Menu.Keys(function()
    settings.keys = Keys.Export()
    Settings.Save(settings)
  end)
  _G.GameDebug = Debug
  -- A person is given the menu, over a new game that stands still
  -- behind it. A script goes straight into that game.
  if not Host.scripted then
    Menu.OpenMain(session)
  end
  pointer = not Host.scripted

  local root = Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local passes = New.Vector_Reference_RenderPassT()
      passes:Append(RenderPass_Clear(0))
      passes:Append(RenderPass_Camera(camera))
      passes:Append(RenderPass_SMAA())
      passes:Append(RenderPass_PostFilter("post/dither.jsl"))
      return { Widget_Rendered(passes), Hud.Create(session, scene) }
    end,
    -- The pointer, over everything else: the engine hides the system's
    -- own, and every app draws its own. (Not in a scripted run, whose
    -- pictures must not depend on where the mouse happens to be: a
    -- script that wants it asks, with GameDebug.Pointer.)
    PostDraw = function()
      if pointer then
        local at = Cursor_Get()
        Icon_Draw(Icons.Cursors.Pointer(), at + vector.create(1, 1), 14, vector.create(0, 0, 0), 0.8)
        Icon_Draw(Icons.Cursors.Pointer(), at, 14, 4 * Colors.Primary, 0.9)
      end
    end,
    PreUpdate = function()
      local frame = math.min(0.1, FrameTimer_Get())
      if Key_Pressed(Key_Escape()) then
        Menu.Toggle(session)
      end
      -- (where the windows were left is kept, for the next run)
      if Windows.Changed() and not Host.scripted then
        settings.windows = Windows.Layout()
        Settings.Save(settings)
      end
      if not Menu.IsOpen() then
        if Keys.Did("pause") then
          session.clock.paused = not session.clock.paused
        end
        if Keys.Did("save") then
          Session.Save(session, "quick")
        end
        if Keys.Did("load") then
          Session.Load(session, "quick")
        end
      end
      autopilot()
      Session.Autopilot(session)
      Session.Update(session, frame)
      -- Docking saves the game, for a person: a script's runs are short
      -- and many, and are not anybody's to come back to.
      if not Host.scripted then
        for _, event in session.events do
          if event.kind == "Docked" and event.ship == session.game.state.player.ship then
            Session.Save(session, "auto", true)
          end
        end
      end
      Scene.Sync(scene, session)
      Scene.UpdateCamera(scene, frame, not Hud.CursorOverInterface())
      Scene.Update(scene, frame)
      Audio.Update(audio, session, scene.warp, frame)
    end,
  }))

  ui = Interface_Create("Game")
  ui:Add(root)
end

function App:Update()
  ui:Update()
  ui:Draw()
end

return App
