--!strict
-- Graphics: the stages the picture is made in, each of which can be
-- switched off. (The owner's list of 2026-11-15, "visual improvements?
-- (anti-aliasing, reflections, shadows, etc etc, etc)", and their yes
-- the same day to beginning it with a page of switches.)
--
-- The engine draws a frame in passes, one after another: the light of
-- the sun, the lights near things, what is see-through, particles,
-- flares, and then what is done to the whole picture (bloom, tone
-- mapping, grading, smoothing of edges, dither). Each of those listed
-- here is one pass, known to the engine by its name
-- (RenderPass_SetEnabled): off, it is left out of every frame. (The
-- two kinds of light are parts of passes that do more besides, which
-- the rest of the frame needs: the engine has a name for each part.)
--
-- All on is the game as it is meant to look. A switch is for seeing
-- what a stage does, for a machine that wants less, and for finding
-- which stage a fault in the picture comes from: on a graphics card
-- that draws something wrong, the stage that makes it go away when it
-- is switched off is the one to look in.
--
-- What is off is kept in the settings (Game/Settings) as the ids
-- below, with commas between: "" is all on. The engine keeps nothing
-- of it, so the game says it again at each start (Graphics.Apply).
--
-- The passes without which there is no picture at all (what is in
-- view, depth, and the surfaces themselves) have no switch.

local Graphics = {}

export type Stage = { id: string, label: string, note: string, pass: string }

Graphics.STAGES = {
  { id = "sun", label = "Sun and sky light", note = "the star's light and the sky's: without it only lamps, glows and stars show", pass = "Global Light" },
  { id = "lights", label = "Lights near things", note = "engines, lamps and blasts lighting what is by them", pass = "Local Lights" },
  { id = "blended", label = "Glows and beams", note = "what is see-through: engine glow, beams, trails, shields", pass = "Blended" },
  { id = "particles", label = "Particles", note = "sparks, smoke and dust", pass = "Particles" },
  { id = "flares", label = "Lens flares", note = "the streaks and rings of a bright light in the lens", pass = "Lens Flares" },
  { id = "bloom", label = "Bloom", note = "bright things spilling light about them", pass = "Bloom" },
  { id = "tonemap", label = "Tone mapping", note = "bright and dark brought into what a screen can show", pass = "Effect <post/tonemap.jsl>" },
  { id = "grade", label = "Colour grading", note = "the last turn of the colours", pass = "Effect <post/colorgrade1D.jsl>" },
  { id = "smoothing", label = "Anti-aliasing", note = "edges smoothed", pass = "SMAA" },
  { id = "dither", label = "Dither", note = "fine grain that hides bands in dark sky", pass = "Effect <post/dither.jsl>" },
} :: { Stage }

-- The stages that are off, by id.
local off: { [string]: true } = {}

local function tell()
  for _, stage in Graphics.STAGES do
    RenderPass_SetEnabled(stage.pass, off[stage.id] == nil)
  end
end

function Graphics.IsOn(id: string): boolean
  return off[id] == nil
end

-- Switch a stage on or off. False for an id that is no stage's.
function Graphics.Switch(id: string, on: boolean): boolean
  for _, stage in Graphics.STAGES do
    if stage.id == id then
      if on then
        off[id] = nil
      else
        off[id] = true
      end
      RenderPass_SetEnabled(stage.pass, on)
      return true
    end
  end
  return false
end

-- Whether every stage is on.
function Graphics.AllOn(): boolean
  return next(off) == nil
end

-- What is off, as the settings keep it: the ids, in the order of the
-- list, with commas between ("" when everything is on).
function Graphics.Off(): string
  local ids: { string } = {}
  for _, stage in Graphics.STAGES do
    if off[stage.id] then
      table.insert(ids, stage.id)
    end
  end
  return table.concat(ids, ",")
end

-- Set every stage from what the settings kept (Graphics.Off's): what
-- is named is off and everything else is on. A name that is no
-- stage's is passed over.
function Graphics.Apply(kept: string)
  off = {}
  for id: string in string.gmatch(kept, "[^,%s]+") :: any do
    for _, stage in Graphics.STAGES do
      if stage.id == id then
        off[id] = true
      end
    end
  end
  tell()
end

return Graphics
