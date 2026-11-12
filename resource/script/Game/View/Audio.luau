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
-- Everything is played flat (not placed in space by the engine) at a
-- loudness worked out here: what is far off is quiet, by how far it is
-- from the pilot's ship. Some are the game's own sounds, made from
-- written descriptions (resource/sound/made, by script/soundgen), where
-- the owner's ear preferred them: projectile guns, railguns and missiles,
-- what lands on the shield and the hull, a ship blowing up, and the surge
-- of a gate (joined to the old jump sound for its clap). The rest is the
-- engine's old sound, which for lasers and the warp drive is the better
-- one, and for everything else has not been looked at yet.
--
-- A script hears nothing: sound is off when a harness drives the app
-- (Host.scripted), unless the script asks for it (GameDebug.Sound), and
-- then it may ask for it at no loudness at all, which runs all of this
-- without a noise.

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Music = require("@lt/Game/View/Music")
local Session = require("@lt/Game/Session")

local Audio = {}

export type Audio = {
  enabled: boolean,
  master: number,                 -- every loudness but the music's is times this
  musicLevel: number,             -- and the music's times this
  time: number,                   -- seconds since it began, for spacing sounds out
  last: { [string]: number },     -- when a sound of a key was last played
  place: Sound?,                  -- the loops
  placeIs: string,
  engine: Sound?,
  warp: Sound?,
  engineNow: number,              -- their loudness now, eased toward what the game asks
  warpNow: number,
  played: number,                 -- sounds started so far, for a script to see that it works
  music: Music.Music,
}

-- The hum of a place. (Space had a chiming loop of the engine's, which
-- passed for music and was not much liked as that: it has music now,
-- and no loop of its own.)
local PLACE: { [string]: string } = { station = "station/ambiance_ship_loops_14.wav" }

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
  Scanned = { "ui/scanneropen.wav", 0.16 },
}
local SHIP: { [string]: { any } } = {
  Jumped = { "made/gate/jump.ogg", 0.28 }, Docked = { "ui/confirm.ogg", 0.18 }, Undocked = { "ui/activate.ogg", 0.18 },
}
local ANY: { [string]: { any } } = {
  JobStarted = { "productionlab/initiate.ogg", 0.18 }, ResearchStarted = { "productionlab/initiate.ogg", 0.18 },
  JobDone = { "productionlab/complete.ogg", 0.22 }, ResearchDone = { "productionlab/complete.ogg", 0.22 },
  SkillTrained = { "ui/objective_complete.ogg", 0.22 }, CommandRejected = { "ui/cancel.ogg", 0.14 },
  PiratesArrived = { "ui/scanneropen.wav", 0.18 }, Marked = { "ui/targetlost.ogg", 0.2 },
  StarbaseAnchored = { "ui/equip.wav", 0.2 }, ColonyDeployed = { "ui/equip.wav", 0.2 },
}

function Audio.New(): Audio
  return {
    enabled = not Host.scripted, master = 1, musicLevel = 1, time = 0, last = {}, place = nil, placeIs = "", engine = nil, warp = nil,
    engineNow = 0, warpNow = 0, played = 0, music = Music.New(),
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
    -- (Sound_Delete takes nothing for an answer)
    Sound_Delete(audio.place)
    Sound_Delete(audio.engine)
    Sound_Delete(audio.warp)
    audio.place, audio.engine, audio.warp, audio.placeIs = nil, nil, nil, ""
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
    if kind == "Shot" then
      local from = state.balls[event.from]
      local weapon = WEAPON[event.family] or WEAPON.projectile
      if from and shots < 4 then
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
      play(audio, if me.vitals.shield > 1 then SHIELD_HIT else HULL_HIT, 0.14, "struck", 0.15)
    elseif kind == "BallDestroyed" then
      local far = if me and event.system == me.system then math.sqrt((event.x - me.x) ^ 2 + (event.y - me.y) ^ 2 + (event.z - me.z) ^ 2)
        else 1e9
      -- (a bigger ship goes up lower and louder)
      local size = math.clamp((event.radius or 40) / 400, 0.1, 1)
      play(audio, "made/explosion/ship1.ogg", (0.3 + 0.3 * size) * reach(far, 12000), nil, 0.2, 1.1 - 0.5 * size)
    elseif OWN[kind] and event.ball == mine then
      play(audio, OWN[kind][1], OWN[kind][2])
    elseif SHIP[kind] and event.ship == mine then
      play(audio, SHIP[kind][1], SHIP[kind][2])
    elseif ANY[kind] and not (kind == "PiratesArrived" and event.away) then
      -- (pirates who have come for a hired pilot somewhere else are not heard)
      play(audio, ANY[kind][1], ANY[kind][2], nil, 0.3)
    end
  end
  if Im.Clicked() then
    play(audio, "ui/click_on.wav", 0.10, "click", 0.04)
  end

  -- The loops. The place: a station's hum, or the quiet of space.
  local player = Core.Query.Player(game)
  local where = if player.docked ~= 0 then "station" else "space"
  if where ~= audio.placeIs then
    if audio.place then
      Sound_Delete(audio.place)
    end
    audio.place = if PLACE[where] then Sound_Play2DLooped(PLACE[where], 0.10 * audio.master) else nil
    audio.placeIs = where
  end
  -- The engines, by how fast the ship is going of what it can.
  local ease = math.min(1, 4 * frameSeconds)
  local burn = 0
  if me and not session.clock.paused then
    burn = math.clamp(math.sqrt(me.vx ^ 2 + me.vy ^ 2 + me.vz ^ 2) / math.max(1, me.maxVelocity), 0, 1)
  end
  audio.engineNow += (0.16 * burn - audio.engineNow) * ease
  audio.warpNow += (0.22 * math.clamp(warp, 0, 1) - audio.warpNow) * ease
  if audio.engine == nil then
    audio.engine = Sound_Play2DLooped("thruster/loop1.ogg", 0)
    audio.warp = Sound_Play2DLooped("warpnode/drone1.ogg", 0)
  end
  -- (every frame, so that turning the sound up or down is heard at once)
  if audio.place then
    Sound_SetVolume(audio.place, 0.10 * audio.master)
  end
  Sound_SetVolume(audio.engine, audio.engineNow * audio.master)
  Sound_SetVolume(audio.warp, audio.warpNow * audio.master)

  Music.Update(audio.music, session, audio.time, frameSeconds, audio.musicLevel)
end

return Audio
