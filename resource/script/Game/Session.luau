--!strict
-- One running game as the view sees it: the Core game, the clock that
-- drives it, what the player has selected, and the events of this frame.
-- Everything the UI does to the game goes through Session.Order.

local Clock = require("@lt/Game/Clock")
local Core = require("@lt/Core/Api")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Session = {}

export type Session = {
  game: Core.Game,
  clock: Clock.Clock,
  selected: number,           -- id of the selected body, or 0
  events: { Space.Event },    -- the events of the ticks taken this frame
  message: string,            -- the last thing worth telling the player
  messageTick: number,
  -- Which game this is, counting from 1: it goes up when the running
  -- game is replaced by a save or by a new one, so that whoever keeps
  -- something made for the last game (the scene) knows to make it again.
  epoch: number,
}

-- Where saves are kept. A script's saves go somewhere of their own, so
-- that a test never writes over a save somebody is playing from.
local SAVE_DIR = if Host.scripted then "cache/test-saves" else "save"

-- How far above its surface a warp to a planet, a moon or the sun ends
-- when the order gives no range, in the body's radii. (The Core takes a
-- range of 0 at its word, and a warp to the surface of a planet ends
-- with the planet a wall across the view. At one radius up, a planet
-- spans a third of the sky.)
local STANDOFF: { [string]: number } = { planet = 1, moon = 1.5, sun = 4 }

function Session.New(galaxySeed: number, historySeed: number): Session
  return {
    game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed }),
    clock = Clock.New(), selected = 0, events = {}, message = "", messageTick = 0, epoch = 1,
  }
end

function Session.Say(session: Session, text: string)
  session.message = text
  session.messageTick = session.game.state.tick
end

-- Tell the player about an event that concerns them.
function Session.Notice(session: Session, event: Space.Event)
  local mine = session.game.state.player.ship
  local kind = event.kind
  if kind == "CommandRejected" then
    Session.Say(session, `{event.command}: {tostring(event.reason)}`)
  elseif kind == "PiratesArrived" then
    Session.Say(session, if event.count == 1 then "A pirate has arrived" else `{event.count} pirates have arrived`)
  elseif kind == "WalletChanged" then
    local sign = if event.amount >= 0 then "+" else "-"
    Session.Say(session, `{sign}{math.abs(event.amount)} credits ({event.reason})`)
  elseif kind == "Ejected" then
    Session.Say(session, "Your ship is lost. You are in your capsule: warp to a station")
  elseif kind == "ShipGranted" or kind == "Respawned" then
    Session.Say(session, "You have been given a new ship")
  elseif kind == "ModuleStopped" and event.ball == mine and event.reason ~= "switched off" then
    Session.Say(session, `A module stopped: {event.reason}`)
  elseif kind == "Looted" and event.ship == mine then
    Session.Say(session, if event.left > 0 then `Looted {event.taken}; {event.left} would not fit` else `Looted {event.taken}`)
  elseif kind == "Mined" and event.ball == mine then
    Session.Say(session, `Mined {event.units} units of ore`)
  elseif kind == "Reprocessed" and event.ship == mine then
    Session.Say(session, `Refined {event.units} units of ore`)
  elseif kind == "LockLost" and event.ball == mine and tostring(event.reason) ~= "unlocked" then
    Session.Say(session, `Lock lost: {event.reason}`)
  elseif kind == "SkillTrained" then
    Session.Say(session, `{Skills.byId[event.skill].name} trained to level {event.level}`)
  elseif kind == "SkillLearned" then
    Session.Say(session, `Learned {Skills.byId[event.skill].name}: it can be trained now`)
  elseif kind == "JobDone" then
    Session.Say(session, `Built: {event.quantity} x {Types.Info(event.product).name}`)
  elseif kind == "ShipAssembled" then
    Session.Say(session, "The hull is assembled: board it from the Ships tab")
  elseif kind == "StarbaseAnchored" then
    local status = Core.Query.Starbase(session.game, event.station)
    Session.Say(session, `The tower is anchoring: it can be moored at in {if status then status.wait else 0} s`)
  elseif kind == "StarbaseFuelled" then
    Session.Say(session, `The tower has {event.fuel} fuel blocks aboard`)
  elseif kind == "ModuleAnchored" then
    Session.Say(session, `{Types.Info(event.module).name} anchored: it will be online shortly`)
  elseif kind == "ModuleUnanchored" then
    Session.Say(session, `{Types.Info(event.module).name} unanchored: it is in the hangar`)
  elseif kind == "Jumped" and event.ship == mine then
    -- (say so when the kind of space changes: what waits at a belt does)
    local _, was = Core.Query.Security(session.game, event.from)
    local _, now = Core.Query.Security(session.game, event.to)
    if now and now ~= was then
      Session.Say(session, if now == "lawless" then "Lawless space: nobody keeps order here"
        elseif now == "low" then "Low security: order is thin here"
        else "Secure space")
    end
  elseif kind == "ColonyDeployed" then
    local body = Core.Query.Body(session.game, event.planet)
    Session.Say(session, `A colony is founded on {if body then body.name else "the planet"}`)
  elseif kind == "ExtractionEnded" then
    local body = Core.Query.Body(session.game, event.planet)
    Session.Say(session, `{if body then body.name else "A colony"}: an extractor has finished its programme`)
  elseif kind == "Exported" then
    Session.Say(session, `Took up {event.quantity} x {Types.Info(event.type).name}: {event.tax} credits export tax`)
  elseif kind == "StarbaseDark" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your starbase"} is out of fuel: it is dark`)
  end
end

-- Take the ticks that are due this frame.
function Session.Update(session: Session, frameSeconds: number)
  session.events = {}
  for _ = 1, Clock.Advance(session.clock, frameSeconds) do
    Core.Step(session.game)
    for _, event in Core.TakeEvents(session.game) do
      table.insert(session.events, event)
      Session.Notice(session, event)
    end
  end
end

-- Give the player's ship an order. Returns whether it was accepted; if
-- not, the reason is shown.
function Session.Order(session: Session, kind: string, target: number?, range: number?): boolean
  if kind == "WarpTo" and target and (range or 0) == 0 then
    local body = Core.Query.Body(session.game, target)
    local standoff = if body then STANDOFF[body.kind] else nil
    if body and standoff then
      range = standoff * body.radius
    end
  end
  local command: State.Command = { kind = kind, actor = session.game.state.player.ship, target = target, range = range }
  local ok, reason = Core.Submit(session.game, command)
  if not ok then
    Session.Say(session, `{kind}: {tostring(reason)}`)
  end
  return ok
end

-- Give any command; the player's ship is filled in as the actor.
function Session.Do(session: Session, command: State.Command): boolean
  command.actor = session.game.state.player.ship
  local ok, reason = Core.Submit(session.game, command)
  if not ok then
    Session.Say(session, `{command.kind}: {tostring(reason)}`)
  end
  return ok
end

-- Whether a command would be accepted now.
function Session.CanDo(session: Session, command: State.Command): (boolean, string?)
  command.actor = session.game.state.player.ship
  return Core.Validate(session.game, command)
end

-- Whether an order would be accepted now, and if not, why not.
function Session.Can(session: Session, kind: string, target: number?, range: number?): (boolean, string?)
  return Core.Validate(session.game, { kind = kind, actor = session.game.state.player.ship, target = target, range = range })
end

-- What a save says of itself without being opened: where the pilot was,
-- in what, with how much, how far into the game, and when it was made
-- (seconds since 1970; 0 if the save does not say).
export type SaveInfo = {
  slot: string, system: string, ship: string, docked: boolean, wallet: number, tick: number, time: number,
}

-- Save to save/<slot>/state.bin, by way of a temporary file so a crash
-- cannot leave half a save, with a few lines beside it (meta.txt) for
-- the list of saves to show. 'quiet' says nothing to the player.
function Session.Save(session: Session, slot: string, quiet: boolean?): boolean
  local dir = `{SAVE_DIR}/{slot}`
  if not (Host.MakeDir(SAVE_DIR) and Host.MakeDir(dir)) then
    return false
  end
  local data, length = Core.Save(session.game)
  local ok = Host.WriteFile(dir .. "/state.tmp", data, length) and Host.Rename(dir .. "/state.tmp", dir .. "/state.bin")
  if ok then
    local player = Core.Query.Player(session.game)
    local meta = `system={player.systemName}\nship={player.hull.name}\ndocked={if player.docked ~= 0 then 1 else 0}\n`
      .. `wallet={session.game.state.wallet}\ntick={session.game.state.tick}\ntime={math.floor(Host.Time())}\n`
    Host.WriteFile(dir .. "/meta.txt", meta)
  end
  if not quiet then
    Session.Say(session, if ok then `Saved to {dir}` else `Could not save to {dir}`)
  end
  return ok
end

-- The saves there are, the newest first.
function Session.Saves(): { SaveInfo }
  local found: { SaveInfo } = {}
  for _, name in Host.ListDir(SAVE_DIR) do
    if string.sub(name, -1) == "/" then
      local slot = string.sub(name, 1, -2)
      if Host.Exists(`{SAVE_DIR}/{slot}/state.bin`) then
        local info: SaveInfo = { slot = slot, system = "", ship = "", docked = false, wallet = 0, tick = 0, time = 0 }
        local meta = Host.ReadFile(`{SAVE_DIR}/{slot}/meta.txt`)
        if meta then
          for key: string, value: string in string.gmatch(buffer.tostring(meta), "(%w+)=([^\n]*)") :: any do
            if key == "system" then
              info.system = value
            elseif key == "ship" then
              info.ship = value
            elseif key == "docked" then
              info.docked = value == "1"
            elseif key == "wallet" then
              info.wallet = tonumber(value) or 0
            elseif key == "tick" then
              info.tick = tonumber(value) or 0
            elseif key == "time" then
              info.time = tonumber(value) or 0
            end
          end
        end
        table.insert(found, info)
      end
    end
  end
  table.sort(found, function(a: SaveInfo, b: SaveInfo): boolean
    if a.time ~= b.time then
      return a.time > b.time
    end
    return a.slot < b.slot
  end)
  return found
end

-- Throw a save away.
function Session.Delete(slot: string): boolean
  Host.Remove(`{SAVE_DIR}/{slot}/meta.txt`)
  return Host.Remove(`{SAVE_DIR}/{slot}/state.bin`)
end

-- Replace the running game with a new one.
function Session.Restart(session: Session, galaxySeed: number, historySeed: number)
  session.game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed })
  session.selected = 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.clock.pending = 0
  session.clock.paused = false
  session.clock.scale = 1
  session.message = ""
end

-- Replace the running game with a save. Returns false if there is none
-- or it cannot be read.
function Session.Load(session: Session, slot: string): boolean
  local data = Host.ReadFile(`{SAVE_DIR}/{slot}/state.bin`)
  if data == nil then
    Session.Say(session, `No save in {SAVE_DIR}/{slot}`)
    return false
  end
  local ok, loaded = pcall(Core.Load, data)
  if not ok then
    Session.Say(session, tostring(loaded))
    return false
  end
  session.game = loaded
  session.selected = 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.clock.pending = 0
  Session.Say(session, `Loaded {SAVE_DIR}/{slot}`)
  return true
end

return Session
