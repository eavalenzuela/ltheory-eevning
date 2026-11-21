--!strict
-- One running game as the view sees it: the Core game, the clock that
-- drives it, what the player has selected, and the events of this frame.
-- Everything the UI does to the game goes through Session.Order.

local Clock = require("@lt/Game/Clock")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Factions = require("@lt/Core/Data/Factions")
local Format = require("@lt/Game/Format")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Paints = require("@lt/Core/Data/Paints")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Boosters = require("@lt/Core/Data/Boosters")
local Characters = require("@lt/Core/Character/Characters")
local Types = require("@lt/Core/Data/Types")

local Session = {}

export type Session = {
  game: Core.Game,
  clock: Clock.Clock,
  selected: number,           -- id of the selected body, or 0
  -- The pilot's target: of the things their ship has locked or is
  -- locking, the one they are at (Session.Aim keeps it). What a weapon
  -- switched on fires at, and what the camera follows. 0 with nothing
  -- locked. 'aimed' and 'aimedAt' are what was locked and what was
  -- selected when it was last looked at, to tell what has changed.
  target: number,
  aimed: { [number]: boolean },
  aimedAt: number,
  events: { Space.Event },    -- the events of the ticks taken this frame
  message: string,            -- the last thing worth telling the player
  heard: { string },
  -- What a scanner read last (module expansion, 2026-11-16: Game/UI/Scans):
  -- what was scanned, a word on it, and what was found; 'serial' counts up
  -- with each reading.
  scanned: { serial: number, title: string, note: string, rows: { { type: string?, label: string, value: string } } }?,          -- and the last few before it, the newest last (for a script: GameDebug.Heard)
  messageTick: number,
  -- What kind of thing it is, for the colour it is said in: "good" (a
  -- gain, a thing done), "warn" (a thing to look to), "bad" (a loss, a
  -- refusal) or "plain".
  messageKind: string,
  -- Where the pilot means to go: a system, or 0. With 'autopilot' the
  -- ship flies there itself, gate by gate, by the fewest jumps or (with
  -- 'safest') the least dangerous way (Galaxy.Route).
  destination: number,
  autopilot: boolean,
  safest: boolean,
  -- A place the pilot marked that the way ends at (Game/UI/Places), or
  -- 0: in its system the autopilot goes on to it, docking where it is a
  -- station and warping to it where it is not.
  goal: number,
  -- Which game this is, counting from 1: it goes up when the running
  -- game is replaced by a save or by a new one, so that whoever keeps
  -- something made for the last game (the scene) knows to make it again.
  epoch: number,
  -- A paint and a design being tried on the ship the fitting screen
  -- shows, before either is bought (Session.Try): nothing of either,
  -- when the ship is shown as it is.
  trying: { paint: string?, design: string? },
  -- The player's character, whose game this is (Core/Character/
  -- Characters): its id, "" for none; and when real time was last given
  -- to its training (Host.Clock).
  character: string,
  credited: number,
}

-- Where saves are kept. A script's saves go somewhere of their own, so
-- that a test never writes over a save somebody is playing from.
-- (a script's run saves in a place of its own, which no other run that
-- is going at the same time can write over: a character's game is its
-- own slot, and every run's pilot is the same Pilot. A run's place is
-- cleared away by the runs an hour after it.)
local TEST_SAVES = "cache/test-saves"
local function testSaves(): string
  local now = math.floor(Host.Time())
  if Host.MakeDir(TEST_SAVES) then
    for _, name in Host.ListDir(TEST_SAVES) do
      local made = tonumber(string.match(name, "^run%-(%d+)%-%d+/$") or "")
      if made and made < now - 3600 then
        local run = `{TEST_SAVES}/{string.sub(name, 1, -2)}`
        for _, slot in Host.ListDir(run) do
          if string.sub(slot, -1) == "/" then
            local dir = `{run}/{string.sub(slot, 1, -2)}`
            for _, file in Host.ListDir(dir) do
              Host.Remove(`{dir}/{file}`)
            end
            Host.Remove(dir)
          else
            Host.Remove(`{run}/{slot}`)
          end
        end
        Host.Remove(run)
      end
    end
  end
  return `{TEST_SAVES}/run-{now}-{math.floor((Host.Clock() % 1) * 1000000)}`
end
local SAVE_DIR = if Host.scripted then testSaves() else "save"
-- (the mark a character's slot has once it has been its game:
-- Session.TakeUpOld)
local TAKEN = "taken.txt"
local function markTaken(id: string)
  local dir = `{SAVE_DIR}/{Session.SlotOf(id)}`
  if Host.MakeDir(SAVE_DIR) and Host.MakeDir(dir) then
    Host.WriteFile(`{dir}/{TAKEN}`, "1\n")
  end
end

-- How far above its surface a warp to a planet, a moon or the sun ends
-- when the order gives no range, in the body's radii. (The Core takes a
-- range of 0 at its word, and a warp to the surface of a planet ends
-- with the planet a wall across the view. At one radius up, a planet
-- spans a third of the sky.)
local STANDOFF: { [string]: number } = { planet = 1, moon = 1.5, sun = 4 }

-- ---------------------------------------------------------------------
-- Characters (the owner's rulings of 2026-11-17: Core/Character/
-- Characters): one file each in save/characters, with a picture beside
-- one that has its own, and the one last played as named in 'chosen'.
-- A script's run keeps its characters in memory, so that a test neither
-- writes over a player's nor finds what another run left; and trains
-- them by the game's ticks, so that it plays out the same every time.

local CHARACTER_DIR = `{SAVE_DIR}/characters`
local kept: { [string]: string } = {}

local function readText(name: string): string?
  if Host.scripted then
    return kept[name]
  end
  local data = Host.ReadFile(`{CHARACTER_DIR}/{name}`)
  return if data then buffer.tostring(data) else nil
end

local function writeText(name: string, text: string): boolean
  if Host.scripted then
    kept[name] = text
    return true
  end
  return Host.MakeDir(SAVE_DIR) and Host.MakeDir(CHARACTER_DIR) and Host.WriteFile(`{CHARACTER_DIR}/{name}.tmp`, text)
    and Host.Rename(`{CHARACTER_DIR}/{name}.tmp`, `{CHARACTER_DIR}/{name}`)
end

local function names(): { string }
  local found: { string } = {}
  if Host.scripted then
    for name in kept do
      table.insert(found, name)
    end
    table.sort(found)
    return found
  end
  for _, name in Host.ListDir(CHARACTER_DIR) do
    table.insert(found, name)
  end
  return found
end

-- The time now, for a character (seconds since 1970). (A script's run
-- gives no real time to training: Session.Load's 'away' says how much.)
local function now(): number
  return math.floor(Host.Time())
end

-- A character by its id, its training caught up to now; nil if there is none.
function Session.Character(id: string): Characters.Character?
  local text = if id ~= "" then readText(`{id}.txt`) else nil
  local character = if text then (Characters.Decode(text)) else nil
  if character and not Host.scripted then
    Characters.CatchUp(character, now())
  end
  return character
end

-- Keep a character.
function Session.KeepCharacter(character: Characters.Character): boolean
  return writeText(`{character.id}.txt`, Characters.Encode(character))
end

-- Every character there is, their training caught up, in the order of their names.
function Session.Characters(): { Characters.Character }
  local list: { Characters.Character } = {}
  for _, name in names() do
    local id = string.match(name, "^(.+)%.txt$")
    local character = if id then Session.Character(id) else nil
    if character then
      table.insert(list, character)
    end
  end
  table.sort(list, function(a: Characters.Character, b: Characters.Character): boolean
    return if a.name ~= b.name then a.name < b.name else a.id < b.id
  end)
  return list
end

-- The character last played as ("" for none, or one that is gone).
function Session.Chosen(): string
  local id = readText("chosen")
  return if id and readText(`{id}.txt`) then id else ""
end

-- Play as a character from now on (the next game, new or loaded, is theirs).
function Session.Choose(session: Session, id: string)
  session.character = id
  writeText("chosen", id)
end

-- A new character, kept: or why not. Its id is made from its name, and
-- made different from any there is.
function Session.MakeCharacter(name: string, portrait: string): (Characters.Character?, string?)
  local ok, why = Characters.NameOk(name)
  if not ok then
    return nil, why
  end
  name = string.match(name, "^%s*(.-)%s*$") or name
  local base = Characters.Slug(name)
  local id, n = base, 1
  while readText(`{id}.txt`) do
    n += 1
    id = `{base}-{n}`
  end
  local character = Characters.New(id, name, portrait, now())
  if not Session.KeepCharacter(character) then
    return nil, "the character could not be kept"
  end
  return character, nil
end

-- Throw a character away (their games stay: opened, each gives its
-- pilot to a new character again).
function Session.DeleteCharacter(session: Session, id: string)
  local character = Session.Character(id)
  if character and string.sub(character.portrait, 1, 5) == "file:" and not Host.scripted then
    Host.Remove(`{CHARACTER_DIR}/{string.sub(character.portrait, 6)}`)
  end
  if Host.scripted then
    kept[`{id}.txt`] = nil
  else
    Host.Remove(`{CHARACTER_DIR}/{id}.txt`)
  end
  if session.character == id then
    Session.Choose(session, "")
  end
  -- (and its game with it: a character is its game)
  Session.Delete(Session.SlotOf(id))
end

-- Where a character's own picture is, to be drawn (Game/UI/Portrait);
-- nil for a badge.
function Session.PictureOf(portrait: string): string?
  return if string.sub(portrait, 1, 5) == "file:" then `{CHARACTER_DIR}/{string.sub(portrait, 6)}` else nil
end

-- A picture of the player's own, from a file anywhere, made a
-- character's: it is copied beside them. Returns its portrait, or nil
-- and why not.
function Session.ImportPicture(character: Characters.Character, path: string): (string?, string?)
  local ext = string.lower(string.match(path, "%.(%w+)%s*$") or "")
  if ext ~= "png" and ext ~= "jpg" and ext ~= "jpeg" and ext ~= "bmp" and ext ~= "tga" then
    return nil, "a picture is a .png, .jpg, .bmp or .tga file"
  end
  local data = Host.ReadFile((string.match(path, "^%s*(.-)%s*$") or path))
  if data == nil then
    return nil, "no file there"
  end
  local name = `{character.id}.{ext}`
  if Host.scripted then
    return `file:{name}`, nil
  end
  if not (Host.MakeDir(SAVE_DIR) and Host.MakeDir(CHARACTER_DIR) and Host.WriteFile(`{CHARACTER_DIR}/{name}`, data)) then
    return nil, "the picture could not be kept"
  end
  return `file:{name}`, nil
end

-- The game's pilot made their character, and their character's (the
-- next thing a game does after it is made or opened): the skills of
-- both, the character's queue, trained by real time; and the player's
-- other characters who are members have their skills brought up to date.
local function embody(session: Session, character: Characters.Character)
  local state = session.game.state
  Characters.Into(state, character)
  -- (a script's run trains by the game's ticks, as it always did)
  if Host.scripted then
    state.trainingByClock = nil
  end
  Characters.From(state, character, now())
  Session.KeepCharacter(character)
  session.credited = Host.Clock()
  for _, id in state.membership.memberIds do
    local member = state.membership.members[id]
    local alt = if member.alt then Session.Character(member.alt :: string) else nil
    if alt then
      Core.AltSkills(session.game, alt.id, alt.skills)
    end
  end
end

-- What the game has made of its pilot, back into their character.
local function keepPilot(session: Session)
  local state = session.game.state
  local character = if state.character then Session.Character(state.character :: string) else nil
  if character then
    Characters.From(state, character, now())
    Session.KeepCharacter(character)
  end
end

-- Ask another of the player's characters into the corporation, at a
-- trade (Core/Assets/Members): whether they are, and why not.
function Session.AskAlt(session: Session, id: string, trade: string): (boolean, string?)
  local alt = Session.Character(id)
  if alt == nil then
    return false, "no such character"
  end
  local ok, why = Core.CanJoinAlt(session.game, id, trade)
  if not ok then
    return false, why
  end
  Core.JoinAlt(session.game, id, alt.name, trade, alt.skills)
  for _, event in Core.TakeEvents(session.game) do
    table.insert(session.events, event)
    Session.Notice(session, event)
  end
  return true
end

function Session.New(galaxySeed: number, historySeed: number): Session
  local session: Session = {
    game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed, traffic = true, wars = true, starter = true }),
    clock = Clock.New(), selected = 0, target = 0, aimed = {}, aimedAt = 0, events = {}, message = "", heard = {}, messageTick = 0, messageKind = "plain", epoch = 1,
    destination = 0, autopilot = false, safest = false, goal = 0, trying = {}, character = Session.Chosen(), credited = Host.Clock(),
  }
  -- (a script's run plays as a character from the first: one is made for
  -- it, as a player is asked to make one before their first game)
  if Host.scripted then
    if session.character == "" then
      local made = Session.MakeCharacter("Pilot", "portrait:1")
      if made then
        Session.Choose(session, made.id)
      end
    end
    local character = Session.Character(session.character)
    if character then
      embody(session, character)
    end
  end
  return session
end

-- Try a paint or a design on the ship the fitting screen shows, before
-- it is bought (Core/Data/Paints): the ship is shown in it, and is not
-- painted. With nothing named, the trying is over.
function Session.Try(session: Session, type: string?)
  if type == nil then
    session.trying = {}
  elseif Paints.paintById[type] then
    session.trying.paint = type
  elseif Paints.designById[type] then
    session.trying.design = type
  end
end

-- Say something to the player: the last thing said is on the screen for
-- a few seconds. 'kind' is what kind of thing it is ("good", "warn",
-- "bad" or "plain"); not given, credits coming in are good news and
-- anything else is plain.
function Session.Say(session: Session, text: string, kind: string?)
  session.message = text
  table.insert(session.heard, text)
  if #session.heard > 30 then
    table.remove(session.heard, 1)
  end
  session.messageTick = session.game.state.tick
  session.messageKind = kind or (if string.sub(text, 1, 1) == "+" then "good" else "plain")
end

-- Tell the player about an event that concerns them.
function Session.Notice(session: Session, event: Space.Event)
  local mine = session.game.state.player.ship
  local kind = event.kind
  if kind == "CommandRejected" then
    Session.Say(session, `{event.command}: {tostring(event.reason)}`, "bad")
  elseif kind == "PiratesArrived" and event.wave then
    Session.Say(session, `Wave {event.wave} of {event.of}: ` .. (if event.chief then "the camp's chief is out"
      .. (if event.count > 1 then `, with {event.count - 1} more` else "")
      elseif event.convoy then `{event.count} {if event.count == 1 then "pirate was" else "pirates were"} waiting for the tender where it landed`
      elseif event.hold or event.escort then `{event.count} {if event.count == 1 then "pirate has" else "pirates have"} come for the `
        .. (if event.escort then "tender" else "rig")
      else `{event.count} {if event.count == 1 then "ship" else "ships"} of the camp's`))
  elseif kind == "PiratesArrived" and event.away then
    -- (somewhere else, for a hired pilot: they say so themselves when they are gone for)
    return
  elseif kind == "PiratesArrived" then
    Session.Say(session, (if event.count == 1 then "A pirate has arrived" else `{event.count} pirates have arrived`)
      .. (if (event.captains or 0) > 0 then (if event.count == 1 then ": a captain" else ", a captain among them") else ""))
  elseif kind == "FleetAttacked" then
    Session.Say(session, `{event.name} is under attack at {event.where}`, "warn")
  elseif kind == "PatrolRetired" then
    Session.Say(session, `{event.name} is going in to mend`)
  elseif kind == "WaveDown" then
    Session.Say(session, `Wave {event.wave} of {event.of} is down: the next is coming`)
  elseif kind == "AssaultCleared" then
    local body = Core.Query.Body(session.game, event.station)
    local aim: string = event.aim
    Session.Say(session, `{if aim == "chief" then "The chief is destroyed" elseif aim == "raze" then "The camp is razed"
      elseif aim == "hold" then "The rig is held" elseif aim == "escort" then "The tender is through, and gone"
      elseif aim == "convoy" then (if event.through then "The tender is through the gate" else "The tender is in")
      else "The camp is cleared"}: `
      .. `{if body then body.name else "the station"} will pay for it`)
  elseif kind == "WardSighted" then
    Session.Say(session, if event.escort then "The tender is here, and setting off: keep it flying until it is clear"
      else "The survey rig is here: keep it standing, and destroy whoever comes for it")
  elseif kind == "WardAway" then
    local body = Core.Query.Body(session.game, event.to or event.station)
    Session.Say(session, `The tender is clear, and away to {if body then body.name else "the station"}: follow it, and see it in`)
  elseif kind == "WardLost" then
    Session.Say(session, if event.escort then "The tender is destroyed" else "The survey rig is destroyed")
  elseif kind == "MissionFailed" then
    Session.Say(session, `A job is lost: {event.title}`, "bad")
  elseif kind == "CorporationFounded" then
    Session.Say(session, `{event.name} is founded: your hired pilots work for it from now on`)
  elseif kind == "WorksSighted" then
    Session.Say(session, if event.count == 1 then "The camp's store is here: destroy it"
      else `What the camp is built of is here: {event.count} works to destroy`)
  elseif kind == "RoomOpen" then
    Session.Say(session, if (event.gate or 0) ~= 0 then `The room is cleared: its gate is open, and leads on to {event.name}`
      else `The way on is found: {event.name} is on the overview`)
  elseif kind == "PassageTaken" and event.ship == mine then
    Session.Say(session, `Through the gate: on to {event.name}`)
  elseif kind == "WalletChanged" then
    local sign = if event.amount >= 0 then "+" else "-"
    Session.Say(session, `{sign}{math.abs(event.amount)} credits ({event.reason})`)
  elseif kind == "Ejected" then
    Session.Say(session, "Your ship is lost. You are in your capsule: warp to a station", "bad")
  elseif kind == "Respawned" then
    -- (at home: the station the pilot keeps a berth at)
    local home = Core.Query.Body(session.game, event.station)
    Session.Say(session, `You wake at home, {if home then home.name else "your station"}, and have been given a new ship`)
  elseif kind == "HomeMoved" then
    local home = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if home then home.name else "This station"} is your home now: lose your capsule, and you wake here`)
  elseif kind == "ShipGranted" then
    Session.Say(session, "You have been given a new ship")
  elseif kind == "ModuleStopped" and event.ball == mine and event.reason ~= "switched off" then
    Session.Say(session, `A module stopped: {event.reason}`, "warn")
  elseif kind == "Looted" and event.ship == mine then
    Session.Say(session, if event.left > 0 then `Looted {event.taken}; {event.left} would not fit` else `Looted {event.taken}`)
  elseif kind == "Mined" and event.ball == mine then
    -- (ore, off a rock; or gas, off a cloud)
    Session.Say(session, if string.sub(event.ore, 1, 4) == "gas." then `Drew off {event.units} units of {Types.Info(event.ore).name}`
      else `Mined {event.units} units of ore`)
  elseif kind == "Reprocessed" and event.ship == mine then
    Session.Say(session, `Refined {event.units} units of ore`)
  elseif kind == "LockLost" and event.ball == mine and tostring(event.reason) ~= "unlocked" then
    Session.Say(session, `Lock lost: {event.reason}`, "warn")
  elseif kind == "SkillTrained" then
    Session.Say(session, `{Skills.byId[event.skill].name} trained to level {event.level}`, "good")
  elseif kind == "SkillLearned" then
    Session.Say(session, `Learned {Skills.byId[event.skill].name}: it can be trained now`)
  elseif kind == "OrderChanged" then
    Session.Say(session, `The order for {Types.Info(event.type).name} is at {event.price} credits now, from {event.was}`
      .. (if event.fee > 0 then `: the broker took {event.fee}` else ""))
  elseif kind == "JobCancelled" then
    -- (of a copy, the runs not used come back: 'back' is how many)
    local copy = (event.back or 0) > 0
    Session.Say(session, if event.research == "copy" then `Called off: {event.made} of {event.quantity} runs were copied. The blueprint is back in the hangar`
      elseif event.research ~= "" then `Called off: the {Types.Info(event.blueprint).name} is back in the hangar`
      elseif event.made > 0 then `Called off: {event.made} of {event.quantity} {Types.Info(event.product).name} were made. What went into the rest is lost`
        .. (if copy then `, and the copy has its {event.back} runs not used` else "")
      else `Called off: nothing was made yet, and what went into it is lost. The {if copy then "copy" else "blueprint"} is back in the hangar`)
  elseif kind == "JobDone" then
    Session.Say(session, `Built: {event.quantity} x {Types.Info(event.product).name}`, "good")
  elseif kind == "ResearchDone" then
    Session.Say(session, `Research done: {Types.Info(event.blueprint).name}, {event.what} level {event.level}`)
  elseif kind == "InventionDone" then
    Session.Say(session, if event.success then `Invented: {Types.Info(event.product).name} is in the hangar`
      elseif event.used then "The invention came to nothing, and the run of the copy it was worked from is used up"
      else `The invention came to nothing: {Types.Info(event.blueprint).name} is back in the hangar`)
  elseif kind == "FleetFightOver" and not event.joined then
    -- (one the pilot was not at: how it came out, and where to read the rest)
    local came = if event.lost > 0 then (if event.lost == 1 then "a ship was lost" else `{event.lost} ships were lost`)
      elseif event.held then "your pilots held it" else "your pilots are gone from it"
    Session.Say(session, `The fight at {event.where} is over: {came}, {event.destroyed} destroyed`
      .. (if event.fled > 0 then `, {event.fled} got away` else "") .. ". The Crew tab's log has it")
  elseif kind == "FleetWarpCalled" then
    Session.Say(session, if event.expect == 0 then "Fleet warp: nobody is here to go with you"
      elseif event.expect == 1 then "Fleet warp: one pilot is forming up on you" else `Fleet warp: {event.expect} pilots are forming up on you`)
  elseif kind == "PirateFleeing" or kind == "PirateFled" then
    -- (only of a fight the pilot is at: a hired pilot's, somewhere else, is theirs to watch)
    local me = Core.Query.Ball(session.game, mine)
    if me and me.system == event.system and me.grid == event.grid then
      Session.Say(session, if kind == "PirateFleeing" then `The {event.name} is breaking off: hold it or finish it, or it is gone`
        else `The {event.name} got away`)
    end
  elseif kind == "ContractAccepted" then
    Session.Say(session, `Bought by contract: {event.title}. It is in the hangar`)
  elseif kind == "ContractFilled" then
    Session.Say(session, `Delivered by contract: {event.title}`)
  elseif kind == "ContractListed" then
    Session.Say(session, `Up on the board: {event.quantity} x {Types.Info(event.type).name}, for {event.price} credits`)
  elseif kind == "ContractSold" then
    local where = Core.Query.Body(session.game, event.station)
    Session.Say(session, `Sold by contract at {if where then where.name else "a station"}: {event.quantity} x {Types.Info(event.type).name}`)
  elseif kind == "ContractExpired" then
    local where = Core.Query.Body(session.game, event.station)
    Session.Say(session, `Nobody took {event.quantity} x {Types.Info(event.type).name} at {if where then where.name else "a station"}: it is back in the hangar there`)
  elseif kind == "ContractCancelled" then
    Session.Say(session, `Taken down: {event.quantity} x {Types.Info(event.type).name} is back in the hangar`)
  elseif kind == "CopyDone" then
    Session.Say(session, `Copied: {Types.Info(event.blueprint).name}, a copy good for {event.runs} {if event.runs == 1 then "run" else "runs"}`)
  elseif kind == "ShipRepackaged" then
    local hull = Types.Get(event.hull)
    Session.Say(session, `{event.name} is packaged: the {if hull then Types.Info(event.hull).name else event.hull} is in the hangar, and what it carried beside it`, "good")
  elseif kind == "ShipAssembled" then
    Session.Say(session, "The hull is assembled: board it from the Ships window")
  elseif kind == "StarbaseAnchored" then
    local status = Core.Query.Starbase(session.game, event.station)
    Session.Say(session, `The tower is anchoring: it can be moored at in {if status then status.wait else 0} s`)
  elseif kind == "StarbaseFuelled" and event.hangar then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has taken {event.fuel} fuel blocks from its hangar`)
  elseif kind == "StarbaseFuelled" then
    Session.Say(session, `The tower has {event.fuel} fuel blocks aboard`)
  elseif kind == "FleetOrdered" and event.what == "stock" then
    local body = Core.Query.Body(session.game, event.target)
    Session.Say(session, `{event.name} will keep {event.quantity} {Types.Info(event.type).name} in the hangar here, bought at `
      .. `{if body then body.name else "the market"} for no more than {event.price} credits each`)
  elseif kind == "StockShort" then
    Session.Say(session, `{event.name} could not buy all the {Types.Info(event.type).name} that is wanted: {event.reason}. They will try again`)
  elseif kind == "ModuleAnchored" then
    Session.Say(session, `{Types.Info(event.module).name} anchored: it will be online shortly`)
  elseif kind == "ModuleUnanchored" then
    Session.Say(session, `{Types.Info(event.module).name} unanchored: it is in the hangar`)
  elseif kind == "TowerUnanchored" then
    Session.Say(session, `The tower is down, and in the hold`
      .. (if event.fuel > 0 then `, with {event.fuel} blocks of its fuel` else "")
      .. (if event.left > 0 then `: {event.left} blocks there was no room for are left behind` else ""))
  elseif kind == "FleetUnposted" then
    Session.Say(session, `{event.name} has no post there any more, and waits`)
  elseif kind == "Jumped" and event.ship == mine and event.drive then
    local system = session.game.state.galaxy.systems[event.to]
    -- (by its own drive, with whoever its field took; or in the field of another's)
    local with = if event.along then ", in another ship's field"
      elseif (event.took or 0) > 0 then `, with {event.took} {if event.took == 1 then "ship" else "ships"} in its field` else ""
    Session.Say(session, string.format("Jump drive: %s, %.1f light years, out at %s%s", if system then system.name else "there",
      event.distance or 0, tostring(event.beacon or "the beacon"), with))
  elseif kind == "Jumped" and event.ship == mine and event.wormhole then
    -- (through a wormhole: into uncharted space, or out of it)
    local node = session.game.state.galaxy.systems[event.to]
    Session.Say(session, if node.uncharted then `Through the wormhole: {node.name}, on no map. Depth {node.depth or 1} of {#Galaxy.DEPTHS}`
      else `Through the wormhole: {node.name}, back on the map`)
  elseif kind == "WormholeClosed" and event.found and event.system == Core.Query.Player(session.game).system then
    Session.Say(session, `{event.name} has closed`)
  elseif kind == "Shot" and event.spinal and event.from == mine then
    Session.Say(session, if event.outcome == "miss" then "The bow gun fires, and misses"
      else string.format("The bow gun fires: %s for %d", if event.outcome == "wreck" then "a wrecking hit" else "a hit", event.damage))
  elseif kind == "SpinalOff" and event.ball == mine then
    Session.Say(session, "The bow gun stands down: the shot is called off")
  elseif kind == "FleetSpooling" or kind == "FleetJumped" then
    -- A mining fleet's jumpship (Core/Tactical/Traffic): said to a
    -- pilot who is there to see it.
    local me = session.game.state.balls[mine]
    if me and me.system == event.system and me.grid == event.grid and me.grid ~= 0 then
      if kind == "FleetSpooling" then
        Session.Say(session, `{event.name} is making its jump drive ready: {event.seconds} s`)
      elseif event.jumped then
        Session.Say(session, `{event.name} has jumped`
          .. (if event.took > 0 then `, and {event.took} of its fleet with it` else "")
          .. (if event.left > 0 then `: {event.left} left behind` else ""))
      end
    end
  elseif kind == "JumpFailed" and event.ship == mine then
    Session.Say(session, `No way through: {event.why}`)
  elseif kind == "Jumped" and event.ship == mine then
    -- (say so when the kind of space changes: what waits at a belt does)
    local _, was = Core.Query.Security(session.game, event.from)
    local _, now = Core.Query.Security(session.game, event.to)
    if now and now ~= was then
      Session.Say(session, if now == "lawless" then "Lawless space: nobody keeps order here"
        elseif now == "low" then "Low security: order is thin here"
        else "Secure space")
    end
  elseif kind == "BatteryFired" and event.to == mine then
    Session.Say(session, "The station's batteries are firing on you")
  elseif kind == "FieldEntered" then
    Session.Say(session, "Inside the station's field: nothing outside it can lock you, nor you anything outside")
  elseif kind == "FieldLeft" then
    Session.Say(session, "Out of the station's field")
  elseif kind == "BatteryLost" and event.own then
    Session.Say(session, "A battery of your tower has been destroyed: it will be built again")
  elseif kind == "RigDestroyed" then
    Session.Say(session, `{Types.Info(event.type).name} taken out: it is destroyed`)
  elseif kind == "Salvaged" and event.ball == mine then
    Session.Say(session, `Salvaged: {event.pieces} {if event.pieces == 1 then "piece" else "pieces"} brought off`)
  elseif kind == "DroneLost" and event.owner == mine then
    Session.Say(session, if event.destroyed then `A {Types.Info(event.type).name} has been destroyed`
      else `A {Types.Info(event.type).name} was left behind: it is lost`)
  elseif kind == "PilotHired" then
    Session.Say(session, `{event.name} is hired: give them a ship on the Crew tab`)
  elseif kind == "ShipAssigned" then
    local ship = session.game.state.ships[event.ship]
    Session.Say(session, if ship then `{event.name} flies the {ship.name} and goes where you go` else `{event.name} has no ship now`)
  elseif kind == "LessonTaken" then
    Session.Say(session, `{event.agent}: "{event.title}". The Guide has what it wants, under Lessons`)
  elseif kind == "LessonReady" then
    Session.Say(session, `"{event.title}" is done: report to {event.agent} for it`)
  elseif kind == "LessonDone" then
    Session.Say(session, if event.finished then `{event.name}: the last lesson is done. +{event.credits} credits, and what is in the hangar`
      elseif event.gifts > 0 then `Lesson done: +{event.credits} credits, and something in the hangar`
      else `Lesson done: +{event.credits} credits`)
  elseif kind == "Guided" then
    Session.Say(session, `Guide: "{event.title}" is done ({event.done} of {event.of})`)
  elseif kind == "ImplantPlugged" then
    Session.Say(session, `{Types.Info(event.implant).name} is plugged in`)
  elseif kind == "ImplantDestroyed" then
    Session.Say(session, `{Types.Info(event.implant).name} taken out: it is destroyed`)
  elseif kind == "ImplantsLost" then
    Session.Say(session, `Your capsule is destroyed, and your {if event.count == 1 then "implant" else `{event.count} implants`} with it`)
  elseif kind == "Bookmarked" then
    Session.Say(session, `Marked: {event.name}. It is on the overview, to warp back to`)
  elseif kind == "FleetCannotJump" then
    Session.Say(session, `{event.name} cannot jump after you ({event.why}), and is coming by the gates`)
  elseif kind == "OreHandedOver" then
    Session.Say(session, `{event.name} put {event.units} units of {if event.gas then "gas" else "ore"} aboard {event.aboard}`)
  elseif kind == "OreDelivered" or kind == "HaulDelivered" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{event.name} brought in {event.units} units{if kind ~= "OreDelivered" then "" elseif event.gas then " of gas" else " of ore"} to `
      .. `{if body then body.name else "the station"}` .. (if (event.revenue or 0) > 0 then `, sold for {event.revenue} credits` else ""))
  elseif kind == "FleetOrdered" and event.what == "buy" then
    local body = Core.Query.Body(session.game, event.target)
    Session.Say(session, `{event.name} is off to buy {event.quantity} {Types.Info(event.type).name} at `
      .. `{if body then body.name else "the market"}, for no more than {event.price} credits each`)
  elseif kind == "BuyDelivered" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{event.name} brought {event.units} {Types.Info(event.type).name} to {if body then body.name else "the station"}`
      .. (if event.left > 0 then `, and is going back for {event.left} more` else ": that is all of it"))
  elseif kind == "BuyEnded" then
    Session.Say(session, `{event.name} could not buy {event.short} of the {Types.Info(event.type).name}: {event.reason}`)
  elseif kind == "KitReplaced" then
    Session.Say(session, `{event.agent} has handed it over again: it is in the hangar. There is no third time`)
  elseif kind == "TradeShock" or kind == "TradeShockOver" then
    -- (what is happening to the trade of a part of the map: Core/Strategic/Commerce)
    local galaxy = session.game.state.galaxy
    local constellation = galaxy.constellations[event.constellation]
    local where = `{constellation.name}, {galaxy.regions[constellation.region].name}`
    local what = Types.Info(event.type).name
    Session.Say(session, if kind == "TradeShockOver" then `NEWS: the {if event.shortage then "shortage" else "glut"} of {what} in {where} is over`
      elseif event.shortage then `NEWS: {what} is short in {where}, and dear there, for {event.days} days or so`
      else `NEWS: a glut of {what} in {where}: cheap there for {event.days} days or so`)
  elseif kind == "WarDeclared" or kind == "PeaceMade" then
    -- (the factions: Core/Strategic/Wars)
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    -- (with the pilot's own corporation: Core/Assets/Sovereignty)
    if kind == "WarDeclared" and event.by == "player" then
      Session.Say(session, `NEWS: your corporation has declared war on the {named(event.on)}: they are your enemies from now`)
      return
    end
    if (kind == "WarDeclared" and event.on == "player") or (kind == "PeaceMade" and event.b == "player") then
      Session.Say(session, if kind == "WarDeclared" then `NEWS: the {named(event.by)} have declared war on you: they will come for what you hold next to them`
        else `NEWS: the {named(event.a)} have made a truce with you`)
      return
    end
    local terms = ""
    if kind == "PeaceMade" and event.winner ~= "" then
      local ceded = session.game.state.galaxy.systems[event.ceded]
      terms = `. The {named(event.winner)} have the better of it` .. (if ceded then `, and {ceded.name}` else "")
    end
    Session.Say(session, if kind == "WarDeclared" then `NEWS: the {named(event.by)} have declared war on the {named(event.on)}`
      else `NEWS: the {named(event.a)} and the {named(event.b)} have made a truce, after {event.hours} hours of war{terms}`)
  elseif kind == "CoalitionJoined" then
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    Session.Say(session, `NEWS: the {named(event.by)} have joined the {named(event.beside)} against the {named(event.against)}`)
  elseif kind == "Blockaded" or kind == "SystemTaken" then
    -- (said when it is near enough to matter: within a few jumps)
    local here = Core.Query.Player(session.game).system
    local way = Session.Way(session, here, event.system)
    local name = session.game.state.galaxy.systems[event.system].name
    local whose = if kind == "Blockaded" then event.against else event.from
    if event.by == "player" then
      Session.Say(session, `{name} is yours: the claim stands, and order is kept there`)
    elseif whose == "player" then
      local by = if Factions.byId[event.by] then Factions.byId[event.by].name else event.by
      Session.Say(session, if kind == "Blockaded" then `NEWS: the {by} are blockading {name}, which is yours: its lines are a place to fight at`
        else `NEWS: the {by} have taken {name} from you`)
    elseif event.system == here or (#way > 0 and #way - 1 <= 6) then
      local by = if Factions.byId[event.by] then Factions.byId[event.by].name else event.by
      local from = if Factions.byId[whose] then Factions.byId[whose].name else ""
      Session.Say(session, if kind == "Blockaded" then `NEWS: the {by} are blockading {name}` .. (if from ~= "" then `, which the {from} hold` else "")
        elseif from ~= "" then `NEWS: the {by} have taken {name} from the {from}`
        else `NEWS: the {by} have claimed {name}`)
    end
  elseif kind == "SideTaken" then
    -- (the pilot has served a side in a war: Core/Tactical/Sides)
    local side = Factions.byId[event.faction]
    Session.Say(session, `You are on the {if side then side.name else event.faction}' books now: whoever they are at war with counts you an enemy, `
      .. "in their space, at the front and at their stations, while the war lasts or until they think better of you", "warn")
  elseif kind == "PicketArrived" then
    local side = Factions.byId[event.faction]
    Session.Say(session, `{if side then side.name else event.faction} pickets at the gate: they hold it against those on their enemy's books`, "bad")
  elseif kind == "FrontFound" or kind == "FrontCrossed" then
    -- (the factions' forces where the pilot is: Core/Tactical/Fronts)
    local function named(id: string): string
      return if Factions.byId[id] then Factions.byId[id].name else id
    end
    Session.Say(session, if kind == "FrontCrossed" then `You have fired on the {named(event.side)}: their ships here are your enemies now`
      elseif event.by == "player" then `Your siege: the {named(event.against)} garrison is at the lines on the overview. Bring it down and the system is yours`
      elseif event.against == "player" then `The {named(event.by)} are besieging this system of yours: their lines are on the overview`
      elseif event.siege then `The {named(event.by)} are besieging this system, which the {named(event.against)} hold: the lines are on the overview`
      else `The {named(event.by)} are claiming this system: their blockade is on the overview`)
  elseif kind == "MemberApplied" then
    Session.Say(session, `{event.name}, a {event.trade}, has applied to join the corporation: Wallet, Corporation, Members`)
  elseif kind == "MemberJoined" then
    Session.Say(session, `{event.name} has joined the corporation, and is off to {session.game.state.galaxy.systems[event.system].name}`)
  elseif kind == "MemberLeft" then
    Session.Say(session, `{event.name} has left the corporation: {event.why}`)
  elseif kind == "MemberLost" and event.hull ~= "" then
    -- (one the pilot's own side destroyed says so by leaving: the line after this)
    local where = session.game.state.galaxy.systems[event.system]
    Session.Say(session, `{event.name} has lost their {Types.Info(event.was).name}{if where then ` in {where.name}` else ""}: `
      .. (if event.hull == event.was then "they have the price of another" else `a {Types.Info(event.hull).name} is what they can afford`))
  elseif kind == "MemberUpgraded" then
    Session.Say(session, `{event.name} has bought a {Types.Info(event.hull).name} out of their own earnings`)
  elseif kind == "LevyPaid" then
    local trade = (event.tax or 0) + (event.dues or 0)
    Session.Say(session, `The levy is in: {Format.Whole(event.amount)} credits from {event.systems} {if event.systems == 1 then "system" else "systems"} of yours`
      .. (if trade > 0 then `, and {Format.Whole(trade)} from their trade ({Format.Whole(event.tax or 0)} sales tax, {Format.Whole(event.dues or 0)} transit dues)` else ""),
      "good")
  elseif kind == "ClaimLapsed" and event.by == "player" then
    Session.Say(session, `Your claim on {session.game.state.galaxy.systems[event.system].name} has lapsed: no beacon of yours stood lit there`)
  elseif kind == "HaulLost" then
    -- (a hauler that carried the economy's goods is gone: where it was going goes without)
    local node = session.game.state.galaxy.systems[event.system]
    Session.Say(session, `A hauler is lost with {event.amount} {Types.Info(event.type).name}: {if node then node.name else "where it was going"} goes without`)
  elseif kind == "HappeningBegan" and event.jumps >= 0 then
    -- (what begins within a few jumps is said: Core/Strategic/Happenings. The rest is in the events window.)
    local name = session.game.state.galaxy.systems[event.system].name
    local where = if event.jumps == 0 then `here in {name}` elseif event.jumps == 1 then `in {name}, a jump off`
      else `in {name}, {event.jumps} jumps off`
    if event.happening == "surge" then
      Session.Say(session, `PIRATE SURGE: pirates are massing {where}. For two hours what is on their heads is doubled there`)
    elseif event.happening == "invasion" then
      Session.Say(session, `INVASION: something has come out of the deep {where}, and means to stay`)
    elseif event.happening == "sighting" then
      Session.Say(session, `SEEN {where}: ` .. (if event.what == "captain" then `{event.name}, a pirate captain`
        elseif event.what == "derelict" then "a derelict hull, adrift" else `a wandering trader, {event.name}`))
    elseif event.happening == "disaster" then
      Session.Say(session, `NEWS: ` .. (if event.what == "gate" then `the gate to {event.name} is closed for repairs, {where}`
        else `{event.name} is out of use {where}`))
    elseif event.happening == "windfall" then
      Session.Say(session, `NEWS: a rich belt has been found {where}`)
    end
  elseif kind == "HappeningStage" and (event.system == Core.Query.Player(session.game).system or event.system == session.destination) then
    local name = session.game.state.galaxy.systems[event.system].name
    Session.Say(session, if event.stage == 2 then `The invaders in {name} are landed, and dug in`
      else `The invaders in {name} are at its stations: every works there has stopped`)
  elseif kind == "HappeningEnded" and (event.kills > 0 or event.system == Core.Query.Player(session.game).system) then
    local name = session.game.state.galaxy.systems[event.system].name
    if event.happening == "surge" then
      Session.Say(session, (if event.outcome == "broken" then `The surge in {name} is broken` else `The surge in {name} is over`)
        .. (if event.kills > 0 then `: {event.kills} pirates were destroyed there` else ""))
    elseif event.happening == "invasion" then
      Session.Say(session, if event.outcome == "beaten" then `The invasion of {name} is beaten: what is left of them has gone back`
        else `The invaders have left {name}, in their own time`)
    elseif event.happening == "sighting" and event.what == "captain" and event.outcome == "taken" then
      Session.Say(session, `{event.name} is destroyed: what they carried is in the wreck`)
    elseif event.happening == "sighting" and event.what == "captain" then
      Session.Say(session, `{event.name} has moved on`)
    elseif event.happening == "sighting" and event.what == "trader" then
      Session.Say(session, `{event.name} has moved on, and their stock with them`)
    end
  elseif kind == "TowerRaided" then
    local body = Core.Query.Body(session.game, event.station)
    local name = if body then body.name else "your tower"
    if event.outcome == "robbed" then
      Session.Say(session, `RAIDED: pirates got in at {name}`
        .. (if event.taken > 0 then ` and carried off {event.taken} units of what its drill brought up` else "")
        .. `. Its defence was {event.defence} against {event.strength}`)
    elseif event.outcome == "beaten" then
      Session.Say(session, `Pirates came for {name} and were beaten off: its defence was {event.defence} against {event.strength}`)
    elseif event.outcome == "siege" then
      Session.Say(session, if event.back then `SIEGE: they are back for {name}, {event.strength} strong against its {event.defence}`
        else `SIEGE: pirates have come to bring {name} down, {event.strength} strong against its {event.defence}`)
    elseif event.outcome == "lost" then
      -- (said by the loss itself)
      return
    else
      Session.Say(session, `Pirates have come for {name}`)
    end
  elseif kind == "TowerSealed" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your tower"} has SEALED itself for {event.hours} {if event.hours == 1 then "hour" else "hours"}: `
      .. `nothing can touch it, and they will be back when it opens`)
  elseif kind == "TowerOpened" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "Your tower"} has opened` .. (if event.siege then ": they are coming back for it" else ""))
  elseif kind == "TowerLost" then
    Session.Say(session, `LOST: {event.name} has been brought down, with what was anchored on it and what was in its hangars`)
  elseif kind == "SiegeBroken" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `The siege of {if body then body.name else "your tower"} is broken: nobody of them is left`)
  elseif kind == "StarbaseCharged" then
    Session.Say(session, `Sealing charges aboard: {event.charges}`)
  elseif kind == "ReactionSet" then
    Session.Say(session, if event.type == "" then "The reactor is making nothing" else `The reactor is making {Types.Info(event.type).name}`)
  elseif kind == "ReactorIdle" then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has not the {Types.Info(event.want).name} for more {Types.Info(event.type).name}: `
      .. `its reactor stands idle`)
  elseif kind == "KeepSighted" then
    local moon = Core.Query.Body(session.game, event.moon)
    Session.Say(session, `Pirates hold {if moon then moon.name else "a moon here"} with a tower of their own: nobody anchors there until it is brought down`)
  elseif kind == "KeepCalled" then
    Session.Say(session, `{event.name} is calling for help: a pack is coming`)
  elseif kind == "KeepSealed" then
    Session.Say(session, `{event.name} has SEALED itself for {event.hours} {if event.hours == 1 then "hour" else "hours"}: `
      .. `nothing can touch it until it opens, and a day after that it is resupplied`)
  elseif kind == "KeepOpened" then
    Session.Say(session, `{event.name} has opened: it has nothing to seal with again until it is resupplied`)
  elseif kind == "KeepRestocked" then
    Session.Say(session, `{event.name} has been resupplied: it is whole again`)
  elseif kind == "KeepLost" then
    Session.Say(session, `{event.name} is brought down: {event.moonName} is nobody's now, and takes a tower`)
  elseif kind == "MoonDrilled" and event.full then
    local body = Core.Query.Body(session.game, event.station)
    Session.Say(session, `{if body then body.name else "A tower"} has no room for more {Types.Info(event.type).name}: its drill stands idle`)
  elseif kind == "PilotPromoted" then
    Session.Say(session, `{event.name} is a grade {event.skill} pilot now, and is paid as one`)
  elseif kind == "WingmanLost" then
    Session.Say(session, `{event.name}'s ship has been destroyed: they got out, and are without one`)
  elseif kind == "PilotLeft" then
    Session.Say(session, if (event.reason :: string) == "unpaid" then `{event.name} could not be paid and has left: their ship is at your home station`
      elseif (event.reason :: string) == "lost" then `{event.name} has lost one ship too many under you, and has left`
      else `{event.name} has been let go`)
  elseif kind == "PilotUnpaid" then
    Session.Say(session, `{event.name} could not be paid today: they stay, and think the less of it ({Fleet.Mood(event.loyalty)})`)
  elseif kind == "ColonyShipMoved" then
    Session.Say(session, `{event.name} has gone on to {session.game.state.galaxy.systems[event.to].name}, and you with it`)
  elseif kind == "Cloaked" and event.ball == mine then
    Session.Say(session, "Cloaked: nobody can target you, and you can target nobody")
  elseif kind == "Decloaked" and event.ball == mine then
    Session.Say(session, if event.spent then "Decloaked: the capacitor will not carry the cloak"
      elseif event.by == "" then "Decloaked" else `Decloaked: too near {event.by}`)
  elseif kind == "Decloaked" then
    -- (somebody who came unseen, where the pilot is: Core/Tactical/Pirates)
    local state = session.game.state
    local me, it, whose = state.balls[mine], state.balls[event.ball], state.ships[event.ball]
    if me and it and whose and whose.owner == "pirates" and it.system == me.system and it.grid == me.grid and me.grid ~= 0 then
      Session.Say(session, `{it.name} has come out from under a cloak`)
    end
  elseif (kind == "ShipScanned" or kind == "CargoScanned") and event.ball == mine then
    local rows = {}
    local volume = 0
    for _, each in event.items do
      local info = Types.Get(each.type)
      table.insert(rows, { type = each.type, label = if info then info.name else each.type, value = Format.Whole(each.quantity) })
      volume += (if info then info.volume else 0) * each.quantity
    end
    local hull = Types.Get(event.hull)
    local ship = kind == "ShipScanned"
    session.scanned = { serial = (if session.scanned then session.scanned.serial else 0) + 1,
      title = `{event.name}{if hull then ` ({hull.name})` else ""}`,
      note = if ship then `{#rows} {if #rows == 1 then "kind" else "kinds"} of module fitted`
        else `{#rows} {if #rows == 1 then "kind" else "kinds"} in the hold, {Format.Whole(volume)} m3`, rows = rows }
    Session.Say(session, if ship then `Ship scan of {event.name}: {#rows} kinds of module` else `Cargo scan of {event.name}: {#rows} kinds of goods`)
  elseif kind == "Surveyed" and event.ball == mine then
    local rows = {}
    for _, rock in event.rocks do
      local info = Types.Get(rock.variety)
      table.insert(rows, { type = rock.variety, label = `{if info then info.name else rock.variety}, {Format.Distance(rock.distance)}`,
        value = `{Format.Whole(rock.left)} units` })
    end
    session.scanned = { serial = (if session.scanned then session.scanned.serial else 0) + 1, title = "Survey",
      note = `{#rows} {if #rows == 1 then "rock" else "rocks"} in reach, the nearest first`, rows = rows }
    Session.Say(session, `Survey: {#rows} {if #rows == 1 then "rock" else "rocks"} in reach`)
  elseif kind == "BubbleDropped" and event.ball == mine then
    Session.Say(session, `Interdiction field up: nobody else warps out of {Format.Distance(event.radius)} round it for two minutes`)
  elseif kind == "MicroJumped" and event.ball == mine then
    Session.Say(session, `Micro jump: {Format.Distance(event.distance)} on. Your locks are broken`)
  elseif kind == "Tractored" and event.ball == mine then
    Session.Say(session, "The wreck is pulled in")
  elseif kind == "Jammed" and event.ball == mine then
    Session.Say(session, "Jammed: your locks are broken")
  elseif kind == "Held" and event.ball == mine then
    Session.Say(session, if event.scrambled and event.entangle < 1 then "Entangled and warp scrambled: you are held"
      elseif event.scrambled then "Warp scrambled: you cannot warp"
      elseif event.entangle < 1 then "Entangled: your speed is cut"
      else "You are free of them")
  elseif kind == "TrailFound" then
    Session.Say(session, `The den's records give away a stronghold: {event.name}, in {session.game.state.galaxy.systems[event.system].name}`)
  elseif kind == "Scanned" and event.ball == mine then
    Session.Say(session, if event.found > 0 then `Scan: {event.found} found` .. (if event.signals > 0 then `, {event.signals} still to resolve` else "")
      elseif event.signals > 0 and (event.faint or 0) >= event.signals then "Scan: too faint for the ship's scanner. Put probes over it on the system map"
      elseif event.signals > 0 then `Scan: {event.signals} {if event.signals == 1 then "signal" else "signals"}, nearer`
      else "Scan: nothing new")
  elseif kind == "ProbeLaunched" and event.ball == mine then
    Session.Say(session, `{event.count or 1} {if (event.count or 1) == 1 then "probe" else "probes"} out ({event.out} in all). They last an hour`)
  elseif kind == "ProbesRecalled" and event.ball == mine then
    Session.Say(session, `{event.count} {if event.count == 1 then "probe is" else "probes are"} back in the hold`)
  elseif kind == "HackStarted" then
    Session.Say(session, "Hacking: pick codes from the matrix to get the keys into the buffer")
  elseif kind == "HackKey" then
    Session.Say(session, `The key of the {string.lower(event.name)} is in`)
  elseif kind == "HackDone" then
    local reason = event.reason :: string
    local wreck = session.game.state.wrecks[event.wreck]
    -- (a vault's lock is its own: on a clock, and all or nothing)
    local vault = wreck ~= nil and wreck.lock == "vault"
    local late = if reason == "out of time" then " The time ran out." else ""
    Session.Say(session, if reason == "left" then `The lock is left as it was: the {if vault then "vault" else "hold"} is still sealed`
      elseif wreck ~= nil and wreck.locked then `Too far off: the hack is dropped, and the {if vault then "vault" else "hold"} still sealed`
      elseif event.success then `The {if vault then "vault" else "hold"} is open, whole: {event.keys} of 3 keys were in.{late}`
      elseif vault then `The vault has wiped itself: the key of the safeguards was not in.{late}`
      else "The hold is open with half of what was in it burnt: the key of the safeguards was not in")
  elseif kind == "BoosterTaken" then
    local booster = Boosters.byId[event.booster]
    local minutes = math.floor((event.seconds or Boosters.SECONDS) / 60 + 0.5)
    Session.Say(session, `{booster.name}: at work for {minutes} minutes. `
      .. (if event.wrong then `It sits badly: {string.lower(string.sub(booster.cost, 1, 1))}{string.sub(booster.cost, 2)}` else "It sits well: no ill effect."))
  elseif kind == "BoosterSpent" then
    Session.Say(session, `{Types.Info(event.booster).name} has worn off`)
  elseif kind == "TrainingCredited" then
    -- (said only where there was training for the time to go to)
    if event.trained > 0 or event.queued > 0 then
      Session.Say(session, `Away {Format.Duration(event.seconds)}: `
        .. (if event.trained == 0 then "your training went on" elseif event.trained == 1 then "a skill level was trained"
          else `{event.trained} skill levels were trained`))
    end
  elseif kind == "Injected" then
    Session.Say(session, `{Format.Duration(event.seconds)} of training injected`
      .. (if event.trained == 1 then ": a skill level was trained" elseif event.trained > 1 then `: {event.trained} skill levels were trained` else ""))
  elseif kind == "ProbeLost" then
    Session.Say(session, "A probe has run down, and is gone")
  elseif kind == "StandingChanged" and event.by < 0 then
    local faction = Factions.byId[event.faction]
    Session.Say(session, string.format("%s standing %.1f: now %.1f%s", if faction then faction.name else "?", event.by, event.standing,
      if event.standing <= -5 then " (their patrols will fire on you)" else ""))
  elseif kind == "MissionAccepted" then
    Session.Say(session, `Job taken: {event.title}`)
  elseif kind == "MissionCompleted" then
    -- (and what whoever gave it thinks of the pilot now, where it was somebody)
    local thinks = if event.agent and event.agent ~= "" and (event.regard or 0) ~= 0
      then string.format("; %s %.1f", event.agent, event.regard) else ""
    -- (a job that paid with one of the people's own makes says which: it is in the hangar there)
    if event.prize then
      Session.Say(session, string.format("Job done: paid with a %s (in the hangar here), +%d loyalty points, standing %.1f%s",
        Types.Info(event.prize).name, event.loyalty or 0, event.standing, thinks))
    else
      Session.Say(session, string.format("Job done: +%d credits, +%d loyalty points, standing %.1f%s", event.reward, event.loyalty or 0,
        event.standing, thinks))
    end
  elseif kind == "Painted" and event.ship == session.game.state.player.ship then
    -- (what was being tried on is over with: the ship is what it is)
    session.trying = {}
    if event.stripped then
      Session.Say(session, "The ship is stripped back to how it left the yard")
    else
      local design = if event.design then Paints.designById[event.design] else nil
      local paint = if event.paint then Paints.paintById[event.paint] else nil
      Session.Say(session, `The ship is painted: {if paint then paint.name else "no paint"}{if design then `, with {design.name}` else ""}`)
    end
  elseif kind == "PaintUnlocked" then
    Session.Say(session, `{Paints.ItemName(event.type)} is yours for good{if event.with then `, and {Paints.ItemName(event.with)} with it` else ""}: `
      .. "on the fitting screen's list")
  elseif kind == "Mutated" then
    -- (how each figure came out: what it gives, its fitting, its draw, its reach)
    local rolls = event.rolls :: { number }
    local function signed(n: number): string
      return if n >= 0 then `+{n}%` else `{n}%`
    end
    Session.Say(session, `Mutated: {Types.Info(event.from).name} came out giving {signed(rolls[1])}, fitting {signed(rolls[2])}, `
      .. `draw {signed(rolls[3])}, reach {signed(rolls[4])} (more is better of each)`)
  elseif kind == "MissionExpired" then
    Session.Say(session, `A job has lapsed: {event.title}. It was kept too long`)
  elseif kind == "LoyaltyRedeemed" then
    Session.Say(session, `{Types.Info(event.type).name} is in the hangar: {event.left} loyalty points left`)
  elseif kind == "PoliceArrived" then
    Session.Say(session, "The police are here, and they are here for you")
  elseif kind == "ColonyFleetArrived" then
    Session.Say(session, `{event.name} has come through the gate, with {event.ships - 1} ships of its fleet`)
  elseif kind == "Marked" then
    Session.Say(session, "You have fired on a ship that is no pirate's: the patrols will fire on you")
  elseif kind == "PortalOpened" and event.ship == mine then
    local to = session.game.state.galaxy.systems[event.to]
    Session.Say(session, `Jump portal open to {if to then to.name else "?"}: your fleet near you goes through`)
  elseif kind == "Deployed" and event.ship == mine then
    Session.Say(session, `{Types.Info(event.type).name} put out`)
  elseif kind == "Scooped" and event.ship == mine then
    Session.Say(session, `{Types.Info(event.type).name} picked up`)
  elseif kind == "TractorLooted" then
    Session.Say(session, `A tractor post of yours took {event.quantity} out of a wreck`)
  elseif kind == "DeployableSpent" then
    Session.Say(session, `A {Types.Info(event.type).name} of yours is spent: what was in it is left in space`, "bad")
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
  -- (a character's training goes by real time, a second at a time,
  -- whatever the game's clock is doing: Core/Character/Characters)
  if session.game.state.trainingByClock then
    local gone = math.floor(Host.Clock() - session.credited)
    if gone >= 1 then
      session.credited += gone
      Core.Credit(session.game, gone)
    end
  end
  -- (time runs faster only at a station: out of one, it is as it is)
  local clock = session.clock
  if clock.scale > 1 and not clock.forced and Core.Query.Player(session.game).docked == 0 then
    clock.scale = 1
  end
  for _ = 1, Clock.Advance(session.clock, frameSeconds) do
    Core.Step(session.game)
    for _, event in Core.TakeEvents(session.game) do
      table.insert(session.events, event)
      Session.Notice(session, event)
    end
  end
end

-- The way from one system to another (Galaxy.Route), which is not to be
-- changed by who asks. The map and the readouts ask for the same few
-- ways every frame, and in a large galaxy a way is some work to find:
-- one found is kept for the tick it was found in.
local ways: { [string]: { number } } = {}
local waysOf = ""

function Session.Way(session: Session, from: number, to: number, safest: boolean?): { number }
  local stamp = `{session.epoch}:{session.game.state.tick}`
  if stamp ~= waysOf then
    ways, waysOf = {}, stamp
  end
  local key = `{from}:{to}:{safest == true}`
  local way = ways[key]
  if way == nil then
    way = Galaxy.Route(session.game.state.galaxy, from, to, safest, Core.Query.Closed(session.game))
    ways[key] = way
  end
  return way
end

-- The way from where the pilot is to where they mean to go: the systems
-- in order, the first the one they are in. Empty with nowhere to go.
function Session.Route(session: Session): { number }
  local galaxy = session.game.state.galaxy
  if session.destination == 0 or galaxy.systems[session.destination] == nil then
    return {}
  end
  return Session.Way(session, Core.Query.Player(session.game).system, session.destination, session.safest)
end

-- The autopilot's turn, once a frame: when the ship has nothing to do,
-- it is sent through the next gate of the route. It undocks to set off,
-- and stops when it is there. Any order the pilot gives by hand takes
-- the ship back (Session.Order).
function Session.Autopilot(session: Session)
  if not session.autopilot then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  -- (there, with a place marked to go on to: docked at it if it is a
  -- station, or warped to)
  if session.goal ~= 0 and session.destination ~= 0 and player.system == session.destination then
    local mark = game.state.bookmarks[session.goal]
    if mark == nil or mark.system ~= player.system then
      session.goal = 0
      return
    end
    if #game.state.queue > 0 then
      return
    end
    local ball = Core.Query.Ball(game, player.ship)
    -- (nor while it goes through a stargate: it is nobody's to order till it is out)
    if player.docked == 0 and (ball == nil or ball.warp ~= nil or ball.intent ~= nil or ball.transit ~= nil) then
      return
    end
    local done = player.docked ~= 0 and player.docked == mark.object
    local command: State.Command? = nil
    if not done then
      if player.docked ~= 0 then
        command = { kind = "Undock", actor = player.ship }
      elseif mark.what == "station" and mark.object then
        command = { kind = "Dock", actor = player.ship, target = mark.object }
      else
        command = { kind = "WarpTo", actor = player.ship, target = mark.id }
      end
    end
    if command then
      local ok, reason = Core.Submit(game, command)
      if command.kind == "Undock" and ok then
        return
      end
      if not ok then
        Session.Say(session, `Autopilot: {tostring(reason)}`)
      end
    end
    Session.Say(session, if done then `Autopilot: arrived at {mark.name}` else `Autopilot: on to {mark.name}`)
    session.autopilot, session.destination, session.goal = false, 0, 0
    return
  end
  if session.destination == 0 or player.system == session.destination then
    if session.destination ~= 0 then
      Session.Say(session, `Autopilot: arrived in {player.systemName}`)
    end
    session.autopilot, session.destination, session.goal = false, 0, 0
    return
  end
  if #game.state.queue > 0 then
    return
  end
  local command: State.Command? = nil
  if player.docked ~= 0 then
    command = { kind = "Undock", actor = player.ship }
  else
    local ball = Core.Query.Ball(game, player.ship)
    if ball and ball.warp == nil and ball.intent == nil and ball.transit == nil then
      local next = Session.Route(session)[2]
      for _, object in Core.Query.Objects(game, player.system) do
        if object.kind == "gate" and object.to == next then
          command = { kind = "Jump", actor = player.ship, target = object.id }
        end
      end
      if command == nil then
        session.autopilot = false
        Session.Say(session, "Autopilot: no gate leads that way")
      end
    end
  end
  if command then
    local ok, reason = Core.Submit(game, command)
    if not ok then
      session.autopilot = false
      Session.Say(session, `Autopilot: {tostring(reason)}`)
    end
  end
end

-- Give the player's ship an order. Returns whether it was accepted; if
-- not, the reason is shown. (An order given by hand takes the ship back
-- from the autopilot.)
function Session.Order(session: Session, kind: string, target: number?, range: number?): boolean
  session.autopilot = false
  if (kind == "WarpTo" or kind == "FleetWarp") and target then
    -- (a world or a sun is warped to from well off it: a distance asked
    -- for is that much farther off again)
    local body = Core.Query.Body(session.game, target)
    local standoff = if body then STANDOFF[body.kind] else nil
    if body and standoff then
      range = standoff * body.radius + (range or 0)
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
  -- Whose game it is: their character's id and name ("" in a save from
  -- before there were characters); and the universe it is in, its seed
  -- and how many systems (0 in a save from before that was noted).
  character: string, pilot: string, seed: number, systems: number,
}

-- Save to save/<slot>/state.bin, by way of a temporary file so a crash
-- cannot leave half a save, with a few lines beside it (meta.txt) for
-- the list of saves to show. 'quiet' says nothing to the player.
function Session.Save(session: Session, slot: string, quiet: boolean?): boolean
  local dir = `{SAVE_DIR}/{slot}`
  if not (Host.MakeDir(SAVE_DIR) and Host.MakeDir(dir)) then
    return false
  end
  -- (what the game has made of its pilot is their character's first)
  keepPilot(session)
  local data, length = Core.Save(session.game)
  local ok = Host.WriteFile(dir .. "/state.tmp", data, length) and Host.Rename(dir .. "/state.tmp", dir .. "/state.bin")
  if ok then
    local player = Core.Query.Player(session.game)
    local id = session.game.state.character or ""
    local character = if id ~= "" then Session.Character(id) else nil
    local meta = `system={player.systemName}\nship={player.hull.name}\ndocked={if player.docked ~= 0 then 1 else 0}\n`
      .. `wallet={session.game.state.wallet}\ntick={session.game.state.tick}\ntime={math.floor(Host.Time())}\n`
      .. `character={id}\npilot={if character then character.name else ""}\n`
      .. `seed={session.game.state.galaxySeed}\nsystems={#session.game.state.galaxy.systems}\n`
    Host.WriteFile(dir .. "/meta.txt", meta)
    if Session.IsOwn(slot) then
      markTaken(string.sub(slot, #Session.OWN + 1))
    end
  end
  if not quiet then
    Session.Say(session, if ok then `Saved to {dir}` else `Could not save to {dir}`)
  end
  return ok
end

-- A character's game (the owner, 2026-11-17: "One save per character":
-- a character is its game; picking it continues it, and a new galaxy for
-- it takes the place of the old). Its save's slot, by the character's
-- id; and the slot the game in play saves to: its character's, or
-- "quick" for a game nobody plays as (a script's, before it has one).
Session.OWN = "pilot-"
function Session.SlotOf(id: string): string
  return Session.OWN .. id
end
function Session.Own(session: Session): string
  return if session.character ~= "" then Session.SlotOf(session.character) else "quick"
end
-- Whether a slot is a character's own (and not a save from before each
-- character had one).
function Session.IsOwn(slot: string): boolean
  return string.sub(slot, 1, #Session.OWN) == Session.OWN
end

-- A character's game, if it has one.
function Session.GameOf(id: string): SaveInfo?
  local slot = Session.SlotOf(id)
  for _, info in Session.Saves() do
    if info.slot == slot then
      return info
    end
  end
  return nil
end

-- Saves from before each character had one of its own: a character
-- that has never had one of its own takes up the newest of those that
-- were its, as its game (copied: the old save stays where it was until
-- it is thrown away). Once only: a character whose game has been
-- thrown away does not take an old one up again (a mark is left in its
-- slot, TAKEN, when it is first saved or takes one up). Returns how
-- many were taken up.
function Session.TakeUpOld(): number
  local taken = 0
  local had: { [string]: boolean } = {}
  local saves = Session.Saves()
  for _, info in saves do
    if Session.IsOwn(info.slot) then
      had[string.sub(info.slot, #Session.OWN + 1)] = true
    end
  end
  for _, character in Session.Characters() do
    if Host.Exists(`{SAVE_DIR}/{Session.SlotOf(character.id)}/{TAKEN}`) then
      had[character.id] = true
    end
  end
  -- (the newest first: the first old save of each character is the one)
  for _, info in saves do
    if not Session.IsOwn(info.slot) and info.character ~= "" and not had[info.character] and Session.Character(info.character) then
      local from, to = `{SAVE_DIR}/{info.slot}`, `{SAVE_DIR}/{Session.SlotOf(info.character)}`
      local data, meta = Host.ReadFile(from .. "/state.bin"), Host.ReadFile(from .. "/meta.txt")
      if data and Host.MakeDir(to) and Host.WriteFile(to .. "/state.tmp", data) and Host.Rename(to .. "/state.tmp", to .. "/state.bin") then
        if meta then
          Host.WriteFile(to .. "/meta.txt", meta)
        end
        markTaken(info.character)
        had[info.character] = true
        taken += 1
      end
    end
  end
  return taken
end

-- The saves there are, the newest first.
function Session.Saves(): { SaveInfo }
  local found: { SaveInfo } = {}
  for _, name in Host.ListDir(SAVE_DIR) do
    if string.sub(name, -1) == "/" then
      local slot = string.sub(name, 1, -2)
      if Host.Exists(`{SAVE_DIR}/{slot}/state.bin`) then
        local info: SaveInfo = { slot = slot, system = "", ship = "", docked = false, wallet = 0, tick = 0, time = 0, character = "", pilot = "", seed = 0, systems = 0 }
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
            elseif key == "character" then
              info.character = value
            elseif key == "pilot" then
              info.pilot = value
            elseif key == "seed" then
              info.seed = tonumber(value) or 0
            elseif key == "systems" then
              info.systems = tonumber(value) or 0
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

-- The pilot's target (the project owner's, 2026-11-13: "you should be
-- able to lock multiple targets at once (ship class defines max, along
-- with skills), and then click to choose which one you are actively
-- targeting. The camera would track to the targeted one."). A ship has
-- as many things locked as its hull and its pilot's skill allow; one of
-- them is the pilot's target. It is the one they pick out: a locked
-- thing they select, by a click on it or on its panel in the row of
-- targets, or by a key. Until they pick, it is the first thing they
-- locked; and when it is locked no longer (destroyed, gone, let go) it
-- is the selected thing, if that is locked, else the one locked last.
-- Called once a frame; says what the target is now.
function Session.Aim(session: Session): number
  local ball = Core.Query.Ball(session.game, session.game.state.player.ship)
  if ball == nil then
    session.target, session.aimed, session.aimedAt = 0, {}, session.selected
    return 0
  end
  local now: { [number]: boolean } = {}
  local last, fresh = 0, 0
  for _, lock in ball.vitals.locks do
    now[lock.target] = true
    last = lock.target
    if not session.aimed[lock.target] then
      fresh = lock.target
    end
  end
  if not now[session.target] then
    session.target = 0
  end
  if session.selected ~= session.aimedAt and now[session.selected] then
    session.target = session.selected
  elseif session.target == 0 then
    session.target = if fresh ~= 0 then fresh elseif now[session.selected] then session.selected else last
  end
  session.aimed, session.aimedAt = now, session.selected
  return session.target
end

-- Replace the running game with a new one, of so many systems (three,
-- if nobody says).
function Session.Restart(session: Session, galaxySeed: number, historySeed: number, systems: number?)
  -- (a galaxy that has been going a while: its prices have come apart across the map)
  session.game = Core.New({ galaxySeed = galaxySeed, historySeed = historySeed, systems = systems, traffic = true,
    settled = Commerce.SETTLED, wars = true, starter = true })
  session.selected = 0
  session.target, session.aimed, session.aimedAt = 0, {}, 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.destination, session.autopilot, session.goal = 0, false, 0
  session.clock.pending = 0
  session.clock.paused = false
  session.clock.scale = 1
  session.message = ""
  -- (the game is the chosen character's: and a script's run, with none
  -- chosen, has one made for it, as a player is asked to make one)
  if session.character == "" and Host.scripted then
    local made = Session.MakeCharacter("Pilot", "portrait:1")
    if made then
      Session.Choose(session, made.id)
    end
  end
  local character = Session.Character(session.character)
  if character then
    embody(session, character)
  end
end

-- When a save was made (seconds since 1970); 0 if it does not say.
local function savedAt(slot: string): number
  local meta = Host.ReadFile(`{SAVE_DIR}/{slot}/meta.txt`)
  local time = if meta then string.match(buffer.tostring(meta), "time=(%d+)") else nil
  return tonumber(time) or 0
end

-- Replace the running game with a save. Returns false if there is none
-- or it cannot be read.
--
-- The time since the save was made is given to the pilot's training
-- (Core.Away): 'away' says how long that is, for a script; without it,
-- it is the real time since, and none in a scripted run (which has to
-- play out the same every time).
function Session.Load(session: Session, slot: string, away: number?): boolean
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
  session.target, session.aimed, session.aimedAt = 0, {}, 0
  session.events = { { kind = "Loaded" } }
  session.epoch += 1
  session.destination, session.autopilot, session.goal = 0, false, 0
  session.clock.pending = 0
  Session.Say(session, `Loaded {SAVE_DIR}/{slot}`)
  local made = savedAt(slot)
  -- The game is its character's. One saved before there were characters
  -- gives its pilot to a new one, as of when it was saved (and so does
  -- one whose character has been thrown away).
  local state = session.game.state
  local character = if state.character then Session.Character(state.character :: string) else nil
  if character == nil then
    local id = state.character or ""
    local name = if id ~= "" then id else "Pilot"
    local adopted = Characters.Adopt(state, "", name, if made > 0 then made else math.floor(Host.Time()))
    local fresh = Session.MakeCharacter(name, adopted.portrait)
    if fresh then
      adopted.id, adopted.made = fresh.id, fresh.made
      Session.KeepCharacter(adopted)
      character = Session.Character(fresh.id)
      Session.Say(session, `This game's pilot is a character now: {name}`)
    end
  end
  if character then
    -- (the time since: real time, or what a script says)
    local trained = if away and away > 0 then Characters.CatchUp(character, character.at + away) else {}
    if not Host.scripted then
      -- (Session.Character has caught them up to now already: what they
      -- know better than the game did when it was saved)
      for skill, level in character.skills do
        if level > (state.skills[skill] or -1) then
          table.insert(trained, { skill = skill, level = level })
        end
      end
    end
    Session.Choose(session, character.id)
    embody(session, character)
    if #trained > 0 then
      Session.Notice(session, { kind = "TrainingCredited", seconds = away or math.max(0, math.floor(Host.Time()) - made), trained = #trained,
        queued = #state.training })
    end
  elseif away and away >= 1 then
    Core.Away(session.game, away)
  end
  for _, event in Core.TakeEvents(session.game) do
    table.insert(session.events, event)
    Session.Notice(session, event)
  end
  return true
end

return Session
