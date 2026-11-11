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
local Core = require("@lt/Core/Api")
local Dogma = require("@lt/Core/Dogma")
local Hud = require("@lt/Game/UI/Hud")
local Hull = require("@lt/Game/View/Hull")
local Im = require("@lt/Game/UI/Im")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local Station = require("@lt/Game/UI/Station")
local Info = require("@lt/Game/UI/Info")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Wallet = require("@lt/Core/Assets/Wallet")

local App = {}

local session: Session.Session
local scene: Scene.Scene
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
function Debug.LookAt(what: string, zoom: number?): boolean
  local entry = find(what)
  local at = if entry then scene.screen[entry.id] else nil
  local focus = scene.focus
  if at == nil or focus == nil then
    return false
  end
  -- The camera sits on the far side of the ship from what it looks at.
  local away = vector.normalize(focus:GetPos() - at)
  -- (a little above the line through the ship, or the ship would hide it)
  scene.pitch = math.clamp(math.acos(math.clamp(away.y, -1, 1)) - 0.16, 0.05, math.pi - 0.05)
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
          if item.type == "miner.small"
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

-- No pirates come while this is on.
function Debug.Peaceful(on: boolean)
  session.game.state.peaceful = on
end

function Debug.TimeScale(scale: number)
  session.clock.scale = scale
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

-- Open the market at an item type, or the industry tab at a blueprint.
-- Open the information window on a type of item ("frigate.lancer").
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

function Debug.Orders(): number
  return #Core.Query.Orders(session.game, nil)
end

-- How full the hold is, as a share.
function Debug.HoldFull(): number
  local ship = session.game.state.player.ship
  return Core.Query.CargoUsed(session.game, ship) / math.max(1, Core.Query.Stats(session.game, ship).cargo)
end

-- A cheat, for scripted runs that test something other than earning:
-- credits from nowhere, entered in the journal as such.
function Debug.Grant(credits: number)
  Wallet.Pay(session.game.state, credits, "cheat", session.game.events)
end

-- Another cheat, for looking at hulls: while docked, a hull of a type
-- from nowhere, boarded whatever the pilot's skills, and fitted with
-- what its design is shown with (Game/View/Hull), loaded, as far as
-- that fits. The ship stepped out of stays in the hangar. False if not
-- docked, or there is no such hull.
function Debug.Fly(type: string): boolean
  local state = session.game.state
  local old = state.ships[state.player.ship]
  local hull = Ships.byId[type]
  if old == nil or old.docked == 0 or hull == nil then
    return false
  end
  local ship = Space.NewShip(state, hull.id, hull.name, "player", old.docked)
  local built = Hull.Build(type)
  local types: { string } = {}
  local wanted: { string } = if built then built.fit else {}
  for _, module in wanted do
    table.insert(types, module)
    if Dogma.Check(hull, types) then
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
    else
      table.remove(types)
    end
  end
  state.player.ship = ship.id
  return true
end

-- The weapons standing on the hardpoints of the pilot's ship, and how
-- far round from its target the worst-pointed turret still is (radians,
-- or -1 if no turret has a target).
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

function Debug.Load(slot: string): boolean
  return Session.Load(session, slot)
end

function App:Initialize()
  local camera = Camera_Create()
  camera:Push()
  session = Session.New(1, 1)
  scene = Scene.New(camera)
  _G.GameDebug = Debug

  local root = Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local passes = New.Vector_Reference_RenderPassT()
      passes:Append(RenderPass_Clear(0))
      passes:Append(RenderPass_Camera(camera))
      passes:Append(RenderPass_SMAA())
      passes:Append(RenderPass_PostFilter("post/dither.jsl"))
      return { Widget_Rendered(passes), Hud.Create(session, scene) }
    end,
    PreUpdate = function()
      local frame = math.min(0.1, FrameTimer_Get())
      if Key_Pressed(Key_P()) and not Im.Typing() then
        session.clock.paused = not session.clock.paused
      end
      if Key_Pressed(Key_F9()) then
        Session.Save(session, "quick")
      end
      if Key_Pressed(Key_F10()) then
        Session.Load(session, "quick")
      end
      autopilot()
      Session.Update(session, frame)
      Scene.Sync(scene, session)
      Scene.UpdateCamera(scene, frame, not Hud.CursorOverInterface())
      Scene.Update(scene, frame)
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
