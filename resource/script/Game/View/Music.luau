--!strict
-- Music: what plays under the game, by where the pilot is and what is
-- happening to them.
--
-- There are four moods. Docked, at a station. In a fight: while there
-- is a pirate on the pilot's grid, or shots are passing between the
-- pilot's ship and anybody, and for a while after. The deep: space no
-- chart shows, on the far side of a wormhole, when there is no fight.
-- And space, which is everything else. Each has its pieces (resource/sound/made/music, made
-- by script/soundgen in the manner the owner chose: strings, a warm
-- drone, the occasional piano key).
--
-- One piece plays at a time. When the mood changes, the piece playing
-- fades out and one of the new mood's fades in over it, sooner into a
-- fight than out of one; when a piece is nearly over and its mood has
-- another, that one takes over the same way, and a mood with one piece
-- plays it round (each piece comes out of silence and goes back into
-- it at its ends). A mood left and come back to goes on to its next
-- piece.
--
-- It is the sound's (Game/View/Audio owns it): no louder than the sound
-- silent when the sound is off, and as loud as the pilot has set music
-- to be. Set to nothing (as a script has it), nothing is played, but
-- the mood and the piece are followed all the same, for the script to
-- ask about; turned up from nothing, the piece of the moment begins.

local Core = require("@lt/Core/Api")
local Session = require("@lt/Game/Session")

local Music = {}

type Piece = { file: string, seconds: number }

local PIECES: { [string]: { Piece } } = {
  space = { { file = "made/music/space1.ogg", seconds = 120 }, { file = "made/music/space2.ogg", seconds = 120 },
    { file = "made/music/space3.ogg", seconds = 120 }, { file = "made/music/space4.ogg", seconds = 120 } },
  docked = { { file = "made/music/docked1.ogg", seconds = 120 }, { file = "made/music/docked2.ogg", seconds = 120 } },
  combat = { { file = "made/music/combat1.ogg", seconds = 120 }, { file = "made/music/combat2.ogg", seconds = 120 } },
  -- (space3, space4, docked2, combat2 and deep1 were made on the night of
  -- 2026-11-15 and are in until the owner's ear says otherwise)
  deep = { { file = "made/music/deep1.ogg", seconds = 120 } },
}

-- How loud music is, of what the sound is set to.
Music.LEVEL = 0.45
-- A fight is over this long after the last sign of one (seconds).
Music.HOLD = 20
-- How long a piece takes to come in and to go out (seconds); into a
-- fight, sooner.
local FADE_IN, FADE_OUT, FADE_FIGHT = 4, 5, 1.5
-- A piece gives way to the next this long before its end.
local LEAD = 5

type Playing = { sound: Sound?, level: number }

export type Music = {
  mood: string,                 -- "docked", "space", "deep", "combat"; "" before the first frame
  file: string,                 -- the piece playing; "" for none
  seconds: number,              -- how long that piece is
  began: number,                -- when it began (the sound's own time)
  now: Playing?,                -- the piece playing
  going: { Playing },           -- pieces fading out
  turn: { [string]: number },   -- which of a mood's pieces was played last
  threat: number,               -- when there was last a sign of a fight
  tick: number,                 -- the tick the grid was last looked over for pirates
  changes: number,              -- pieces begun so far
}

function Music.New(): Music
  return { mood = "", file = "", seconds = 0, began = 0, now = nil, going = {}, turn = {}, threat = -1e9, tick = -1, changes = 0 }
end

-- Stop everything at once (the sound has been switched off).
function Music.Stop(music: Music)
  -- (a piece followed but not played has no sound to be rid of)
  if music.now and music.now.sound then
    Sound_Delete(music.now.sound)
  end
  for _, playing in music.going do
    if playing.sound then
      Sound_Delete(playing.sound)
    end
  end
  music.now, music.going = nil, {}
  music.mood, music.file = "", ""
end

-- A piece as a sound, silent as yet. (One piece that comes round plays
-- as a loop; one of several plays once, and the next takes over before
-- it is done.)
local function sounding(mood: string, file: string): Sound
  return if #PIECES[mood] == 1 then Sound_Play2DLooped(file, 0) else Sound_Play2D(file, 0)
end

-- Begin the next piece of a mood, over whatever is playing.
local function begin(music: Music, mood: string, time: number, master: number)
  local pieces = PIECES[mood]
  local turn = (music.turn[mood] or 0) % #pieces + 1
  music.turn[mood] = turn
  local piece = pieces[turn]
  if music.now then
    table.insert(music.going, music.now)
  end
  music.now = { sound = if master > 0 then sounding(mood, piece.file) else nil, level = 0 }
  music.mood, music.file, music.seconds, music.began = mood, piece.file, piece.seconds, time
  music.changes += 1
end

-- Once a frame, from the sound: 'time' is the sound's own clock,
-- 'master' how loud the sound is set (0: follow the game, play nothing).
function Music.Update(music: Music, session: Session.Session, time: number, frameSeconds: number, master: number)
  local game = session.game
  local state = game.state
  local player = Core.Query.Player(game)
  local mine = state.player.ship
  local me = state.balls[mine]

  -- Signs of a fight: a shot at the pilot's ship or from it, and (looked
  -- for once a tick) a pirate on the grid the pilot is on.
  for _, event in session.events do
    if event.kind == "Shot" and (event.to == mine or event.from == mine) then
      music.threat = time
    end
  end
  if me and state.tick ~= music.tick then
    music.tick = state.tick
    if me.grid ~= 0 then
      for _, id in state.ballIds do
        local ball = state.balls[id]
        local ship = state.ships[id]
        if ship and ship.owner == "pirates" and ball.system == me.system and ball.grid == me.grid then
          music.threat = time
          break
        end
      end
    end
  end

  local node = state.galaxy.systems[player.system]
  local mood = if player.docked ~= 0 then "docked" elseif time - music.threat < Music.HOLD then "combat"
    elseif node and node.uncharted then "deep" else "space"
  if mood ~= music.mood then
    begin(music, mood, time, master)
  elseif #PIECES[mood] > 1 and time - music.began > music.seconds - LEAD then
    begin(music, mood, time, master)
  end

  -- The piece playing comes up to its loudness; the others go down to
  -- nothing and are done with.
  local playing = music.now
  if playing then
    -- (the music has been turned up from nothing: the piece begins)
    if playing.sound == nil and master > 0 then
      playing.sound = sounding(music.mood, music.file)
      music.began = time
    end
    local rise = frameSeconds / (if music.mood == "combat" then FADE_FIGHT else FADE_IN)
    playing.level = math.min(1, playing.level + rise)
    if playing.sound then
      Sound_SetVolume(playing.sound, playing.level * Music.LEVEL * master)
    end
  end
  local fall = frameSeconds / (if music.mood == "combat" then FADE_FIGHT else FADE_OUT)
  for index = #music.going, 1, -1 do
    local going = music.going[index]
    going.level -= fall
    if going.level <= 0 then
      if going.sound then
        Sound_Delete(going.sound)
      end
      table.remove(music.going, index)
    elseif going.sound then
      Sound_SetVolume(going.sound, going.level * Music.LEVEL * master)
    end
  end
end

return Music
