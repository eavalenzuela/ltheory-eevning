--!strict
-- Sound: what the pilot hears of what happens.
--
-- The same events that drive the effects (Session's 'events') drive the
-- sounds: weapons by their kind, hits on the pilot's own ship, ships
-- blowing up, the warp drive, a gate, docking, a lock, a job done, and a
-- click for a button. Under them run three loops whose loudness follows
-- the game: a station's hum while docked, the pilot's engines by how
-- hard they burn, and the warp. And under all of it, music (Game/View/Music).
--
-- And a place has its air: a loop or two of its own, very quiet, that
-- come in when the pilot gets there and fade when they leave.
--
-- Where people live there is comms chatter: the background noise of
-- an inhabited place, and nobody's in particular (the owner's ruling,
-- 2026-11-12: "background noise when near inhabited planets and
-- stations, not faction specific"). So it is heard at any station, and
-- near any planet people live on, whoever's space it is and whatever
-- tongue the voices are in. How much of it follows from how busy the
-- place is: a good deal at a homeworld, some elsewhere in secure
-- space, a little where order is thin or there is none; and where
-- there is more than a little, a burst of other voices is heard over
-- it now and then. (A pilot's own tower is nobody's home: it has none
-- of its own.)
--
-- A stargate hums. A belt ticks and groans. A vapour field hisses. A
-- derelict creaks, over a dead channel. A listening post has its old
-- transmissions, and a pirates' den or camp their talk.
--
-- The owner makes sounds of their own (resource/sound/atmosphere, as
-- the wav files they are: a file put there again is what is heard next
-- time): the chatter, the creaking of wrecks, a missile landing on the
-- pilot's own ship, and a small ship blowing up. The rest of the air is
-- made from descriptions (resource/sound/made/atmosphere).
--
-- Everything is played flat (not placed in space by the engine) at a
-- loudness worked out here: what is far off is quiet, by how far it is
-- from the pilot's ship. Some are the game's own sounds, made from
-- written descriptions (resource/sound/made, by script/soundgen), where
-- the owner's ear preferred them: projectile guns, railguns and missiles,
-- what lands on the shield and the hull, a ship blowing up, the surge of
-- a gate (joined to the old jump sound for its clap), a button's click,
-- the scanner's ping, the warning that pirates have come, the notice
-- that something is put down, and the three loops. The rest is the
-- engine's old sound, where that is the better one: lasers, the warp
-- drive going in and coming out, docking and undocking, a lock made and
-- lost, an order refused, a job begun and done, a skill trained.
--
-- The made sounds are all brought to one loudness, and the old ones are
-- as loud as they happened to be (some of them very quiet): the figures
-- here make up the difference, so they say little side by side.
--
-- A script hears nothing: sound is off when a harness drives the app
-- (Host.scripted), unless the script asks for it (GameDebug.Sound), and
-- then it may ask for it at no loudness at all, which runs all of this
-- without a noise.

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Modules = require("@lt/Core/Data/Modules")
local Music = require("@lt/Game/View/Music")
local Planet = require("@lt/Game/View/Planet")
local Session = require("@lt/Game/Session")

local Audio = {}

-- A loop of a place's air: which place's it is and which of that
-- place's loops, how loud it is now, and how loud it is wanted (nothing,
-- for one on its way out).
type Air = { sound: Sound, key: string, layer: number, now: number, want: number }

export type Audio = {
  enabled: boolean,
  master: number,                 -- every loudness but the music's is times this
  musicLevel: number,             -- and the music's times this
  time: number,                   -- seconds since it began, for spacing sounds out
  last: { [string]: number },     -- when a sound of a key was last played
  place: Sound?,                  -- the loops
  placeIs: string,
  -- The air of the place: the loop that is wanted, and any that are
  -- still fading out; and which place's it is ("" where there is none).
  air: { Air },
  airIs: string,
  airAsked: number,               -- when where the pilot is was last looked at
  passing: number,                -- when somebody else's traffic is next heard, and how many times it has been
  passed: number,
  engine: Sound?,
  warp: Sound?,
  mining: Sound?,                 -- a mining laser's loop, once one has run
  miningNow: number,
  critical: boolean,              -- whether the hull's warning has been given since the hull was last sound
  struck: number,                 -- missiles that have landed on the pilot's ship, for taking the sounds of it in turn
  engineNow: number,              -- their loudness now, eased toward what the game asks
  warpNow: number,
  played: number,                 -- sounds started so far, for a script to see that it works
  music: Music.Music,
}

-- The hum of a place. (Space had a chiming loop of the engine's, which
-- passed for music and was not much liked as that: it has music now,
-- and no loop of its own.)
local PLACE: { [string]: string } = { station = "made/loop/station.ogg" }
local PLACE_LEVEL = 0.03

-- The air of a place: its loop, and how loud it is. (Quiet: these are
-- under everything, and nobody has yet said how loud they should be.)
-- (Each place: its loops, a file and a loudness each.)
local AIR: { [string]: { { any } } } = {
  ["chatter.thin"] = { { "atmosphere/very_light_comm_chatter_loop_1.wav", 0.06 } },
  ["chatter.light"] = { { "atmosphere/light_comm_chatter_loop_01.wav", 0.05 } },
  ["chatter.busy"] = { { "atmosphere/medium_comm_chatter_loop_01.wav", 0.09 } },
  gate = { { "made/atmosphere/gate.ogg", 0.03 } },
  belt = { { "made/atmosphere/belt.ogg", 0.025 } },
  gas = { { "made/atmosphere/vapour.ogg", 0.03 } },
  -- (a derelict is one of two, by which it is: each of the owner's two
  -- creakings, over the dead channel)
  relic = { { "atmosphere/metallic_creaking_wrecks_01.wav", 0.07 }, { "made/atmosphere/derelict.ogg", 0.02 } },
  ["relic.b"] = { { "atmosphere/metallic_creaking_wrecks_02.wav", 0.16 }, { "made/atmosphere/derelict.ogg", 0.02 } },
  data = { { "made/atmosphere/listening.ogg", 0.05 } },
  pirates = { { "made/atmosphere/pirates.ogg", 0.04 } },
  -- (space no chart shows, where the place has no air of its own: made 2026-11-15, and heard by nobody yet)
  deep = { { "made/atmosphere/deep.ogg", 0.035 } },
}
-- More voices, heard over the chatter of a place that has more than a
-- little of it, now and then: one of these, once, and the next a
-- minute or two after. (Chatter like the rest, in another tongue: it is
-- nobody's in particular.)
local PASSING: { { any } } = {
  { "atmosphere/japanese_medium_comm_chatter_02.wav", 0.05 }, { "atmosphere/japanese_medium_comm_chatter_03.wav", 0.035 },
}
local PASSING_FIRST, PASSING_GAP = 25, 70
-- A missile landing on the pilot's own ship, and a small ship blowing
-- up (one no bigger than a destroyer): the owner's.
local MISSILE_HIT = { "atmosphere/missile_impact_player_01.wav", "atmosphere/missile_impact_player_02.wav" }
local SMALL_BLAST, SMALL = "atmosphere/small_hull_explosion_01.wav", 100
-- Seconds one takes to come in, and to fade.
local AIR_FADE = 2.5
local SITES: { [string]: string } = {
  ["site.gas"] = "gas", ["site.relic"] = "relic", ["site.data"] = "data", ["site.combat"] = "pirates", ["site.ore"] = "belt",
  ["site.keep"] = "pirates", ["site.fortress"] = "pirates", ["site.habitat"] = "pirates",
}

-- How near a planet people live on its chatter is heard: within this
-- many of its radii of its surface. (A warp to a planet ends well
-- inside that, and a station at one of its moons is usually outside it.)
local NEAR_WORLD = 1.5

-- Which air the place the pilot is at has ("": none): by what the
-- place is; and where people live, comms chatter, by how busy the
-- system is.
local function whereOf(game: Core.Game): string
  local state = game.state
  local player = Core.Query.Player(game)
  local me = state.balls[state.player.ship]
  local at = if player.docked ~= 0 then player.docked
    elseif me and not (me.warp and me.warp.stage == "warp") then me.grid
    else 0
  local place: any = if at ~= 0 then Core.Query.Body(game, at) else nil
  -- People live at a station (not at a tower a pilot put up for
  -- themselves), and on some kinds of planet: there, or near one of
  -- those, there is chatter.
  local inhabited = place ~= nil and place.kind == "station" and state.starbases[at] == nil
  -- (and nobody lives in uncharted space, whatever kind of planet is there)
  if not inhabited and me and not (me.warp and me.warp.stage == "warp") and not player.uncharted then
    for _, object in Core.Query.Objects(game, player.system) do
      if object.kind == "planet" and Planet.Inhabited(object.variety) then
        local far = math.sqrt((object.x - me.x) ^ 2 + (object.y - me.y) ^ 2 + (object.z - me.z) ^ 2) - object.radius
        inhabited = inhabited or far < NEAR_WORLD * object.radius
      end
    end
  end
  -- (a gate or a belt that happens to be near such a planet keeps its own air)
  if inhabited and (place == nil or place.kind == "station") then
    local node = state.galaxy.systems[player.system]
    local _, band = Core.Query.Security(game, player.system)
    return if node and node.home then "chatter.busy" elseif band == "secure" then "chatter.light" else "chatter.thin"
  elseif place == nil then
    return ""
  elseif place.kind == "gate" then
    return "gate"
  elseif place.kind ~= "belt" then
    return ""
  elseif place.variety == "site.relic" then
    return if at % 2 == 0 then "relic" else "relic.b"
  elseif place.variety == "site.mission" then
    -- (a place made for a job: a camp of the pirates', or a pocket of ore)
    for _, id in state.missionIds do
      local mission = state.missions[id]
      if mission.kind == "mining" and (mission.site == at or table.find(mission.rooms, at) ~= nil) then
        return "belt"
      end
    end
    return "pirates"
  end
  return SITES[place.variety] or "belt"
end

function Audio.Where(game: Core.Game): string
  local air = whereOf(game)
  -- (in space no chart shows, wherever nothing else is heard: its own)
  if air == "" then
    local player = Core.Query.Player(game)
    if player.uncharted and player.docked == 0 then
      return "deep"
    end
  end
  return air
end

-- The loops of the pilot's own ship, and how loud each is at its most:
-- the engines at full burn, and deep in warp.
local ENGINE, ENGINE_LEVEL = "made/loop/engine.ogg", 0.12
local WARP, WARP_LEVEL = "made/loop/warp.ogg", 0.10

-- A weapon's sound by its family: the files, how loud, and its pitch.
local WEAPON: { [string]: { files: { string }, volume: number, pitch: number } } = {
  laser = { files = { "weapon/pulse/1/Pulse1.1.ogg", "weapon/pulse/1/Pulse1.2.ogg", "weapon/pulse/1/Pulse1.3.ogg",
    "weapon/pulse/1/Pulse1.4.ogg" }, volume = 0.10, pitch = 1 },
  projectile = { files = { "made/weapon/projectile1.ogg", "made/weapon/projectile2.ogg" }, volume = 0.10, pitch = 1 },
  hybrid = { files = { "made/weapon/hybrid1.ogg" }, volume = 0.10, pitch = 1 },
  missile = { files = { "made/weapon/missile1.ogg" }, volume = 0.13, pitch = 1 },
}

-- What lands on the pilot's own ship, on its shield and on its hull.
local SHIELD_HIT, HULL_HIT = "made/impact/shield1.ogg", "made/impact/hull1.ogg"

-- What an event of the pilot's own sounds like: the file and how loud.
local OWN: { [string]: { any } } = {
  WarpStarted = { "jumpdrive/activate.ogg", 0.25 }, WarpEnded = { "jumpdrive/deactivate.ogg", 0.22 },
  LockCompleted = { "ui/targetacquired.ogg", 0.18 }, LockLost = { "ui/targetlost.ogg", 0.14 },
  -- (a cloak going on, and one broken by something come too near; a
  -- salvager's cut: made 2026-11-15 with the rest of that night's, and
  -- heard by nobody yet. The cloak's were two of the engine's old
  -- interface sounds before, picked by their names.)
  Cloaked = { "made/ui/cloak.ogg", 0.14 }, Decloaked = { "made/ui/decloak.ogg", 0.16 },
  Scanned = { "made/ui/scan.ogg", 0.07 },
  Salvaged = { "made/module/salvage.ogg", 0.10 },
}
-- What mends the pilot's own ship, each time it does, by what it mends
-- (quiet, and not one on top of another: a repairer runs for minutes).
local MENDED: { [string]: { any } } = {
  armor = { "made/module/repair.ogg", 0.06 }, shield = { "made/module/shield.ogg", 0.06 }, hull = { "made/module/repair.ogg", 0.06 },
}
-- A drive lit on the pilot's own ship (an afterburner, a microwarpdrive).
local DRIVE, DRIVE_LEVEL = "made/module/drive.ogg", 0.12
-- A module of the pilot's own switched on, by the start of its type
-- (the expansion of 2026-11-16's, made 2026-11-17 at the owner's asking
-- for the sounds it needs, and heard by nobody yet: the descriptions
-- and the loudness here mine). 'against': heard too, quieter, when
-- somebody else's is switched on at the pilot's own ship.
local MODULE_ON: { { prefix: string, file: string, level: number, against: boolean? } } = {
  { prefix = "projector.entanglement", file = "made/ewar/web.ogg", level = 0.12, against = true },
  { prefix = "disruptor.", file = "made/ewar/disrupt.ogg", level = 0.11, against = true },
  { prefix = "jammer.", file = "made/ewar/jam.ogg", level = 0.10 },
  { prefix = "damper.", file = "made/ewar/damp.ogg", level = 0.09, against = true },
  { prefix = "painter.", file = "made/ewar/paint.ogg", level = 0.08, against = true },
  { prefix = "ewar.", file = "made/ewar/tracking.ogg", level = 0.09, against = true },
  { prefix = "neutraliser.", file = "made/ewar/neut.ogg", level = 0.11, against = true },
  { prefix = "drain.", file = "made/ewar/drain.ogg", level = 0.10, against = true },
  { prefix = "remote.shield", file = "made/module/remote-shield.ogg", level = 0.09, against = true },
  { prefix = "remote.armor", file = "made/module/remote-armor.ogg", level = 0.09, against = true },
  { prefix = "remote.capacitor", file = "made/module/remote-cap.ogg", level = 0.09, against = true },
  { prefix = "remote.sensor", file = "made/module/hardener.ogg", level = 0.07 },
  { prefix = "tractor.", file = "made/module/tractor.ogg", level = 0.09 },
  { prefix = "jump.micro", file = "made/module/mjd-spool.ogg", level = 0.12 },
  { prefix = "burst.", file = "made/module/burst.ogg", level = 0.11 },
  { prefix = "siege.", file = "made/module/siege.ogg", level = 0.14 },
  { prefix = "triage.", file = "made/module/siege.ogg", level = 0.14 },
  { prefix = "industrial.core", file = "made/module/siege.ogg", level = 0.14 },
  { prefix = "shield.hardener", file = "made/module/hardener.ogg", level = 0.07 },
  { prefix = "armor.hardener", file = "made/module/hardener.ogg", level = 0.07 },
  { prefix = "beacon.jump", file = "made/module/beacon.ogg", level = 0.13 },
}
local function moduleOn(type: string): { prefix: string, file: string, level: number, against: boolean? }?
  for _, one in MODULE_ON do
    if string.sub(type, 1, #one.prefix) == one.prefix then
      return one
    end
  end
  return nil
end
-- Something going on that the pilot has word of, by its kind: an
-- invasion is graver than the rest, and a surge is the pirates' alert.
local WORD: { [string]: { any } } = {
  invasion = { "made/ui/invasion.ogg", 0.15 }, surge = { "made/ui/alert.ogg", 0.11 }, sighting = { "made/ui/news.ogg", 0.12 },
  disaster = { "made/ui/news.ogg", 0.12 }, windfall = { "made/ui/news.ogg", 0.12 },
}
-- A ship this big across or bigger breaks up long and deep (a capital).
local GREAT_BLAST, GREAT = "made/explosion/large1.ogg", 900
-- The pilot's hull down to this share of itself: a warning, once, until
-- it has been above the other again.
local CRITICAL, CRITICAL_OVER = 0.3, 0.5
local MINING, MINING_LEVEL = "made/loop/mining.ogg", 0.07
-- How loud somebody else's warp drive is, right beside the pilot; and a
-- gate that somebody else goes through.
local OTHERS_WARP = 0.12
local OTHERS_GATE = 0.12
local SHIP: { [string]: { any } } = {
  Jumped = { "made/gate/jump.ogg", 0.28 }, Docked = { "ui/confirm.ogg", 0.18 }, Moored = { "ui/confirm.ogg", 0.18 }, Undocked = { "ui/activate.ogg", 0.18 },
  Looted = { "made/ui/loot.ogg", 0.14 },
}
local ANY: { [string]: { any } } = {
  JobStarted = { "productionlab/initiate.ogg", 0.18 }, ResearchStarted = { "productionlab/initiate.ogg", 0.18 },
  JobDone = { "productionlab/complete.ogg", 0.22 }, ResearchDone = { "productionlab/complete.ogg", 0.22 },
  CopyDone = { "productionlab/complete.ogg", 0.22 },
  SkillTrained = { "ui/objective_complete.ogg", 0.22 }, CommandRejected = { "ui/cancel.ogg", 0.14 },
  PiratesArrived = { "made/ui/alert.ogg", 0.13 }, Marked = { "ui/targetlost.ogg", 0.2 },
  TowerRaided = { "made/ui/alert.ogg", 0.13 },
  StarbaseAnchored = { "made/ui/placed.ogg", 0.2 }, ColonyDeployed = { "made/ui/placed.ogg", 0.2 },
  LessonReady = { "made/ui/placed.ogg", 0.2 }, LessonDone = { "ui/objective_complete.ogg", 0.22 },
  -- (the night of 2026-11-15's: a module out of a mutator, a deal done
  -- on a market, a coat of paint, a lock in a derelict's hold opened)
  Mutated = { "made/ui/mutate.ogg", 0.18 }, Bought = { "made/ui/trade.ogg", 0.13 }, Sold = { "made/ui/trade.ogg", 0.13 },
  OrderFilled = { "made/ui/trade.ogg", 0.10 }, Painted = { "made/ui/paint.ogg", 0.16 }, HackKey = { "made/ui/hack-pick.ogg", 0.12 },
}

function Audio.New(): Audio
  return {
    enabled = not Host.scripted, master = 1, musicLevel = 1, time = 0, last = {}, place = nil, placeIs = "", engine = nil, warp = nil,
    engineNow = 0, warpNow = 0, mining = nil, miningNow = 0, critical = false, played = 0, struck = 0, music = Music.New(), air = {}, airIs = "", airAsked = -10,
    passing = 0, passed = 0,
  }
end

-- Switch sound on or off, and set how loud it is: 'master' for
-- everything but the music, 'music' for the music (as loud as the rest,
-- if only the one is said, which is how a script asks for silence).
function Audio.Set(audio: Audio, enabled: boolean, master: number?, music: number?)
  audio.enabled = enabled
  audio.master = master or audio.master
  audio.musicLevel = music or master or audio.musicLevel
  if not enabled then
    -- (only what is going: the engine stopped on being handed no sound
    -- to be rid of, which is what a game started with the sound off
    -- has. The owner's machine, 2026-11-15.)
    if audio.place then
      Sound_Delete(audio.place)
    end
    if audio.engine then
      Sound_Delete(audio.engine)
    end
    if audio.warp then
      Sound_Delete(audio.warp)
    end
    if audio.mining then
      Sound_Delete(audio.mining)
    end
    audio.place, audio.engine, audio.warp, audio.mining, audio.placeIs = nil, nil, nil, nil, ""
    for _, air in audio.air do
      Sound_Delete(air.sound)
    end
    audio.air, audio.airIs, audio.airAsked = {}, "", -10
    Music.Stop(audio.music)
  end
end

-- Play a sound once, if one of its key has not just been played.
local function play(audio: Audio, file: string, volume: number, key: string?, gap: number?, pitch: number?)
  if volume * audio.master < 0.004 and audio.master > 0 then
    return
  end
  local name = key or file
  if audio.time - (audio.last[name] or -10) < (gap or 0.05) then
    return
  end
  audio.last[name] = audio.time
  audio.played += 1
  local sound = Sound_Play2D(file, volume * audio.master)
  if pitch and pitch ~= 1 then
    Sound_SetPitch(sound, pitch)
  end
end

-- A sound of the program's own, that no event of the game brings: the
-- splash's. Heard if the sound is on.
function Audio.Once(audio: Audio, file: string, volume: number)
  if audio.enabled then
    play(audio, file, volume)
  end
end

-- How much of a sound made 'far' metres off reaches the pilot: all of
-- it near, half at 'half' metres, and less with the square beyond.
local function reach(far: number, half: number): number
  return 1 / (1 + (far / half) ^ 2)
end

-- Once a frame, after the game has been stepped: 'warp' is how deep in
-- warp the pilot's ship is, from 0 to 1 (the scene's own figure).
function Audio.Update(audio: Audio, session: Session.Session, warp: number, frameSeconds: number)
  audio.time += frameSeconds
  if not audio.enabled then
    return
  end
  local game = session.game
  local state = game.state
  local mine = state.player.ship
  local me = state.balls[mine]

  local shots = 0
  for _, event in session.events do
    local kind = event.kind
    if kind == "PointDefence" and (event.rounds or 0) > 0 then
      -- (a point defence turret's stream: a short burst of the small guns, higher)
      local from = state.balls[event.from]
      if from and shots < 4 then
        local weapon = WEAPON.projectile
        local far = if me then math.sqrt((from.x - me.x) ^ 2 + (from.y - me.y) ^ 2 + (from.z - me.z) ^ 2) else 1e9
        local index = (event.item + math.floor(audio.time * 11)) % #weapon.files + 1
        play(audio, weapon.files[index], weapon.volume * 0.6 * reach(far, 6000), `pds{event.item}`, 0.08, weapon.pitch * 1.5)
        shots += 1
      end
    end
    if kind == "Shot" then
      local from = state.balls[event.from]
      local weapon = WEAPON[event.family] or WEAPON.projectile
      -- (a volley is heard once, and a salvo too near to launch not at all: Core's Data/Modules 'volley')
      if from and shots < 4 and (event.volley or 1) == 1 and event.outcome ~= "too close" then
        local far = if me then math.sqrt((from.x - me.x) ^ 2 + (from.y - me.y) ^ 2 + (from.z - me.z) ^ 2) else 1e9
        local index = (event.item + math.floor(audio.time * 7)) % #weapon.files + 1
        play(audio, weapon.files[index], weapon.volume * reach(far, 6000), `shot{event.from}`, 0.12, weapon.pitch)
        shots += 1
      end
      -- (and what lands on the pilot's own ship is heard from inside it)
      if event.to == mine and event.outcome ~= "miss" and me and event.family ~= "missile" then
        local shielded = me.vitals.shield > 1
        play(audio, if shielded then SHIELD_HIT else HULL_HIT, if shielded then 0.10 else 0.14, "struck", 0.15)
      end
    elseif kind == "BatteryFired" then
      local weapon = if event.missile then WEAPON.missile else WEAPON.projectile
      play(audio, weapon.files[event.battery % #weapon.files + 1], weapon.volume * 0.8, `battery{event.battery}`, 0.2, 0.55)
      if event.to == mine and me then
        play(audio, if me.vitals.shield > 1 then SHIELD_HIT else HULL_HIT, 0.14, "struck", 0.15)
      end
    elseif kind == "MissileHit" and event.to == mine and me then
      -- (the owner's: one and then the other, and not one on top of another)
      audio.struck += 1
      play(audio, MISSILE_HIT[audio.struck % #MISSILE_HIT + 1], 0.16, "missile", 0.6)
    elseif kind == "BallDestroyed" then
      local far = if me and event.system == me.system then math.sqrt((event.x - me.x) ^ 2 + (event.y - me.y) ^ 2 + (event.z - me.z) ^ 2)
        else 1e9
      -- (a bigger ship goes up lower and louder)
      local size = math.clamp((event.radius or 40) / 400, 0.1, 1)
      if (event.radius or 40) <= SMALL then
        -- (a small one: the owner's, as it is)
        play(audio, SMALL_BLAST, 0.3 * reach(far, 12000), "blast", 0.2)
      elseif (event.radius or 40) >= GREAT then
        -- (a capital: long and deep, and heard from further off)
        play(audio, GREAT_BLAST, 0.6 * reach(far, 30000), "great", 1.0)
      else
        play(audio, "made/explosion/ship1.ogg", (0.3 + 0.3 * size) * reach(far, 12000), nil, 0.2, 1.1 - 0.5 * size)
      end
    elseif OWN[kind] and event.ball == mine then
      play(audio, OWN[kind][1], OWN[kind][2], nil, 0.4)
    elseif kind == "Repaired" and event.ball == mine and MENDED[event.layer] then
      play(audio, MENDED[event.layer][1], MENDED[event.layer][2], "mended", 2.5)
    elseif kind == "ModuleStarted" and event.ball == mine then
      local item = state.items[event.item]
      if item and (string.sub(item.type, 1, 12) == "afterburner." or string.sub(item.type, 1, 4) == "mwd.") then
        play(audio, DRIVE, DRIVE_LEVEL, "drive", 1.0)
      else
        local on = if item then moduleOn(item.type) else nil
        if on then
          play(audio, on.file, on.level, `on:{event.item}`, 1.0)
        end
      end
    elseif kind == "ModuleStarted" and event.target == mine and mine ~= 0 then
      -- (somebody else's, switched on at the pilot's own ship)
      local item = state.items[event.item]
      local on = if item then moduleOn(item.type) else nil
      if on and on.against then
        play(audio, on.file, on.level * 0.7, "against", 1.5, 0.92)
      end
    elseif (kind == "Smartbombed" or kind == "MicroJumped" or kind == "BubbleDropped") and me then
      -- (heard from wherever it is, quieter the farther off)
      local ball = state.balls[event.ball]
      if ball and ball.system == me.system then
        local far = math.sqrt((ball.x - me.x) ^ 2 + (ball.y - me.y) ^ 2 + (ball.z - me.z) ^ 2)
        local file = if kind == "Smartbombed" then "made/module/smartbomb.ogg" elseif kind == "MicroJumped" then "made/module/mjd-jump.ogg"
          else "made/module/bubble-launch.ogg"
        play(audio, file, (if kind == "Smartbombed" then 0.18 else 0.15) * reach(far, 8000), `{kind}:{event.ball}`, 0.5)
      end
    elseif kind == "CapacitorBoosted" and event.ball == mine then
      play(audio, "made/module/capbooster.ogg", 0.09, "capbooster", 0.3)
    elseif kind == "Jammed" and event.ball == mine then
      play(audio, "made/ewar/jammed.ogg", 0.13, "jammed", 3)
    elseif kind == "Jumped" and event.ship == mine and event.drive then
      -- (the pilot's own jump drive: not the gate's)
      play(audio, "made/drive/jump.ogg", 0.3)
    elseif kind == "FleetSpooling" and me and event.system == me.system then
      -- (a fleet's jump drives spooling up near by)
      local ball = state.balls[event.ship]
      local far = if ball then math.sqrt((ball.x - me.x) ^ 2 + (ball.y - me.y) ^ 2 + (ball.z - me.z) ^ 2) else 1e9
      play(audio, "made/drive/jump-spool.ogg", 0.2 * reach(far, 20000), "spool", 4)
    elseif kind == "HappeningBegan" then
      -- (only what the pilot has word of: what begins too far off to be told of is not sounded)
      local word = WORD[event.happening]
      if word and (event.jumps or -1) >= 0 then
        play(audio, word[1], word[2], "word", 0.5)
      end
    elseif kind == "HackDone" then
      -- (not one that was left, or drifted out of reach: those were not lost at the lock)
      if event.success then
        play(audio, "made/ui/hack-won.ogg", 0.16)
      elseif event.reason ~= "left" and event.reason ~= "out of reach" then
        play(audio, "made/ui/hack-lost.ogg", 0.13)
      end
    elseif kind == "DroneLaunched" and event.owner == mine then
      play(audio, "made/drone/launch.ogg", 0.10, "drone", 0.15)
    elseif kind == "DroneScooped" and event.owner == mine then
      play(audio, "made/drone/return.ogg", 0.10, "drone", 0.15)
    elseif me and ((kind == "Jumped" and event.ship ~= mine and (event.from == me.system or event.to == me.system))
      or ((kind == "BallAdded" or kind == "BallRemoved") and event.gate)) then
      -- Somebody else through a gate near by, either way, or the
      -- system's own traffic coming in by one or going out: the gate's
      -- surge, a good deal quieter than the pilot's own jump, and
      -- quieter the farther off the gate is. (Not one on top of another.)
      local id = if kind ~= "Jumped" then event.gate elseif event.from == me.system then event.gate else event.arrival
      local gate: any = Core.Query.Body(session.game, id)
      if gate then
        local far = math.sqrt((gate.x - me.x) ^ 2 + (gate.y - me.y) ^ 2 + (gate.z - me.z) ^ 2)
        play(audio, "made/gate/surge.ogg", OTHERS_GATE * reach(far, 15000), "gate:other", 1.5, 1.1)
      end
    elseif (kind == "WarpStarted" or kind == "WarpEnded") and me then
      -- Somebody else's drive, going in or coming out near by: the same
      -- sound as the pilot's own, a little higher and a good deal
      -- quieter, and quieter the farther off. (Not on top of one
      -- another: a busy station has somebody coming or going all the time.)
      local other = Core.Query.Ball(session.game, event.ball)
      if other and other.system == me.system then
        local far = math.sqrt((other.x - me.x) ^ 2 + (other.y - me.y) ^ 2 + (other.z - me.z) ^ 2)
        local file = if kind == "WarpStarted" then "jumpdrive/activate.ogg" else "jumpdrive/deactivate.ogg"
        play(audio, file, OTHERS_WARP * reach(far, 8000), "warp:" .. kind, 0.8, 1.25)
      end
    elseif SHIP[kind] and event.ship == mine then
      play(audio, SHIP[kind][1], SHIP[kind][2])
    elseif ANY[kind] and not (kind == "PiratesArrived" and event.away) then
      -- (pirates who have come for a hired pilot somewhere else are not heard)
      play(audio, ANY[kind][1], ANY[kind][2], nil, 0.3)
    end
  end
  if Im.Clicked() then
    play(audio, "made/ui/click.ogg", 0.045, "click", 0.04)
  end

  -- The loops. The place: a station's hum, or the quiet of space.
  local player = Core.Query.Player(game)
  local where = if player.docked ~= 0 then "station" else "space"
  if where ~= audio.placeIs then
    if audio.place then
      Sound_Delete(audio.place)
    end
    audio.place = if PLACE[where] then Sound_Play2DLooped(PLACE[where], PLACE_LEVEL * audio.master) else nil
    audio.placeIs = where
  end
  -- The air of the place, looked for a few times a second: what is
  -- wanted comes in, and whatever else there was fades out under it.
  if audio.time - audio.airAsked >= 0.25 then
    audio.airAsked = audio.time
    local air = Audio.Where(game)
    if air ~= audio.airIs then
      audio.airIs = air
      local back = false
      for _, each in audio.air do
        -- (back before it had quite gone: it is not begun twice)
        each.want = if each.key == air then AIR[air][each.layer][2] else 0
        back = back or each.key == air
      end
      if not back then
        local layers: { { any } } = AIR[air] or {}
        for layer, loop in layers do
          table.insert(audio.air, { sound = Sound_Play2DLooped(loop[1], 0), key = air, layer = layer, now = 0, want = loop[2] })
        end
      end
      -- (and more voices are first heard a while after getting to a place with chatter)
      audio.passing = audio.time + PASSING_FIRST
    end
  end
  if (audio.airIs == "chatter.busy" or audio.airIs == "chatter.light") and audio.time >= audio.passing then
    audio.passed += 1
    audio.passing = audio.time + PASSING_GAP + (audio.passed * 37) % 60
    local burst = PASSING[audio.passed % #PASSING + 1]
    play(audio, burst[1], burst[2], "passing", 5)
  end
  for index = #audio.air, 1, -1 do
    local each = audio.air[index]
    local step = AIR[each.key][each.layer][2] * frameSeconds / AIR_FADE
    each.now = if each.now < each.want then math.min(each.want, each.now + step) else math.max(each.want, each.now - step)
    if each.want == 0 and each.now <= 0 then
      Sound_Delete(each.sound)
      table.remove(audio.air, index)
    else
      Sound_SetVolume(each.sound, each.now * audio.master)
    end
  end

  -- The engines, by how fast the ship is going of what it can.
  local ease = math.min(1, 4 * frameSeconds)
  local burn = 0
  if me and not session.clock.paused then
    burn = math.clamp(math.sqrt(me.vx ^ 2 + me.vy ^ 2 + me.vz ^ 2) / math.max(1, me.maxVelocity), 0, 1)
  end
  audio.engineNow += (ENGINE_LEVEL * burn - audio.engineNow) * ease
  audio.warpNow += (WARP_LEVEL * math.clamp(warp, 0, 1) - audio.warpNow) * ease
  if audio.engine == nil then
    audio.engine = Sound_Play2DLooped(ENGINE, 0)
    audio.warp = Sound_Play2DLooped(WARP, 0)
  end
  -- A mining laser of the pilot's own at work: its loop, while one runs.
  local cutting = 0
  if me and not session.clock.paused then
    for _, running in me.vitals.running do
      local item = state.items[running.item]
      local module = if item then Modules.byId[item.type] else nil
      if module and module.miner then
        cutting = 1
        break
      end
    end
  end
  audio.miningNow += (MINING_LEVEL * cutting - audio.miningNow) * ease
  if audio.mining == nil and cutting > 0 then
    audio.mining = Sound_Play2DLooped(MINING, 0)
  end
  if audio.mining then
    Sound_SetVolume(audio.mining, audio.miningNow * audio.master)
  end
  -- The pilot's hull nearly gone: a warning, once each time it comes to that.
  if me then
    local share = me.vitals.hull / math.max(1, me.vitals.hullMax)
    if share < CRITICAL and not audio.critical then
      audio.critical = true
      play(audio, "made/ui/critical.ogg", 0.16, "critical", 5)
    elseif share > CRITICAL_OVER then
      audio.critical = false
    end
  end
  -- (every frame, so that turning the sound up or down is heard at once)
  if audio.place then
    Sound_SetVolume(audio.place, PLACE_LEVEL * audio.master)
  end
  Sound_SetVolume(audio.engine, audio.engineNow * audio.master)
  Sound_SetVolume(audio.warp, audio.warpNow * audio.master)

  Music.Update(audio.music, session, audio.time, frameSeconds, audio.musicLevel)
end

return Audio
