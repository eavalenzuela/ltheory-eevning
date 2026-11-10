--!strict
-- One running game as the view sees it: the Core game, the clock that
-- drives it, what the player has selected, and the events of this frame.
-- Everything the UI does to the game goes through Session.Order.

local Clock = require("@lt/Game/Clock")
local Core = require("@lt/Core/Api")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Session = {}

export type Session = {
  game: Core.Game,
  clock: Clock.Clock,
  selected: number,           -- id of the selected body, or 0
  events: { Space.Event },    -- the events of the ticks taken this frame
  message: string,            -- the last thing worth telling the player
  messageTick: number,
}

local SAVE_DIR = "save"

function Session.New(galaxySeed: number, historySeed: number): Session
  return {
    game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed }),
    clock = Clock.New(), selected = 0, events = {}, message = "", messageTick = 0,
  }
end

function Session.Say(session: Session, text: string)
  session.message = text
  session.messageTick = session.game.state.tick
end

-- Take the ticks that are due this frame.
function Session.Update(session: Session, frameSeconds: number)
  session.events = {}
  for _ = 1, Clock.Advance(session.clock, frameSeconds) do
    Core.Step(session.game)
    for _, event in Core.TakeEvents(session.game) do
      table.insert(session.events, event)
      if event.kind == "CommandRejected" then
        Session.Say(session, `{event.command}: {tostring(event.reason)}`)
      end
    end
  end
end

-- Give the player's ship an order. Returns whether it was accepted; if
-- not, the reason is shown.
function Session.Order(session: Session, kind: string, target: number?, range: number?): boolean
  local command: State.Command = { kind = kind, actor = session.game.state.player.ship, target = target, range = range }
  local ok, reason = Core.Submit(session.game, command)
  if not ok then
    Session.Say(session, `{kind}: {tostring(reason)}`)
  end
  return ok
end

-- Whether an order would be accepted now, and if not, why not.
function Session.Can(session: Session, kind: string, target: number?, range: number?): (boolean, string?)
  return Core.Validate(session.game, { kind = kind, actor = session.game.state.player.ship, target = target, range = range })
end

-- Save to save/<slot>/state.bin, by way of a temporary file so a crash
-- cannot leave half a save.
function Session.Save(session: Session, slot: string): boolean
  local dir = `{SAVE_DIR}/{slot}`
  if not Host.MakeDir(dir) then
    return false
  end
  local data, length = Core.Save(session.game)
  local ok = Host.WriteFile(dir .. "/state.tmp", data, length) and Host.Rename(dir .. "/state.tmp", dir .. "/state.bin")
  Session.Say(session, if ok then `Saved to {dir}` else `Could not save to {dir}`)
  return ok
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
  session.clock.pending = 0
  Session.Say(session, `Loaded {SAVE_DIR}/{slot}`)
  return true
end

return Session
