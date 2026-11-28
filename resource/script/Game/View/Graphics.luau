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

local Plates = require("@lt/Game/View/Plates")

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

-- How hulls are drawn (the owner's word of 2026-11-17, after a trial of
-- cel shading in the viewer: "add both the first-pass and 2nd pass
-- styles, as toggleable options", as radio buttons "Standard, Cel V1,
-- Cel v2"). Standard is the game as it was; the two cel looks are
-- shaded in flat tones and inked about their edges, V1 over the worn
-- paint, V2 over flat paint (light/global.jsl, material/hull.jsl). The
-- engine knows them as two switches: "Smooth Shading" off is cel, and
-- "Flat Paint" on (as it is unless switched off) is V2.
export type Look = { id: string, label: string }
Graphics.LOOKS = {
  { id = "standard", label = "Standard" },
  { id = "cel1", label = "Cel V1" },
  { id = "cel2", label = "Cel V2" },
} :: { Look }

-- The stages that are off, by id, and the look. And a look drawn in
-- for a while in place of the person's, which is not theirs and is not
-- kept (the menu's showcase, in Cel V2: Game/Showcase).
local off: { [string]: true } = {}
local look = "standard"
local lent: string? = nil

local function tell()
  for _, stage in Graphics.STAGES do
    RenderPass_SetEnabled(stage.pass, off[stage.id] == nil)
  end
  local drawn = lent or look
  RenderPass_SetEnabled("Smooth Shading", drawn == "standard")
  RenderPass_SetEnabled("Flat Paint", drawn ~= "cel1")
end

-- Draw in a look for a while, whatever the person has chosen (nil: in
-- theirs again). Graphics.Look stays theirs, and so do the settings.
function Graphics.Lend(id: string?)
  lent = id
  tell()
end

-- The look hulls are drawn in (an id of Graphics.LOOKS).
function Graphics.Look(): string
  return look
end

-- Draw in a look. False for an id that is no look's.
function Graphics.SetLook(id: string): boolean
  for _, one in Graphics.LOOKS do
    if one.id == id then
      look = id
      tell()
      return true
    end
  end
  return false
end

-- Whether the seams between a hull's sheets of plating are drawn (the
-- owner's, 2026-11-28: on cruisers and bigger they are drawn as big as
-- the hull is, which does not look right; a switch to see them without).
-- Off unless switched on (2026-11-28), kept in the settings as "seams" when on.
function Graphics.Seams(): boolean
  return Plates.seams
end
function Graphics.SetSeams(on: boolean)
  Plates.Seams(on)
end

-- Whether an unpainted hull's bare metal is panelled (its own texture:
-- rectangles and greebles, as big on any hull: 2026-11-28). Off unless
-- switched on (the owner's, 2026-11-28: "panels off too"), kept in the
-- settings as "panels" when on.
function Graphics.Panels(): boolean
  return Plates.panels
end
function Graphics.SetPanels(on: boolean)
  Plates.Panels(on)
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

-- Every stage on again (the look is left as it is).
function Graphics.StagesOn()
  off = {}
  tell()
end

-- What is off, as the settings keep it: the ids, in the order of the
-- list, with commas between ("" when everything is on); and after them
-- the look, "look:" and its id, unless it is the standard one.
function Graphics.Off(): string
  local ids: { string } = {}
  for _, stage in Graphics.STAGES do
    if off[stage.id] then
      table.insert(ids, stage.id)
    end
  end
  if look ~= "standard" then
    table.insert(ids, `look:{look}`)
  end
  if Plates.seams then
    table.insert(ids, "seams")
  end
  if Plates.panels then
    table.insert(ids, "panels")
  end
  return table.concat(ids, ",")
end

-- For running a fault down inside the anti-aliasing, which is three
-- steps in one pass: what the pass shows (its picture, the edges its
-- first step found, or the weights its second made of them), and
-- whether its last step blends in the plain way of the method's
-- authors in place of this program's own. Neither is kept: a game
-- starts with the picture and its own blend. (The owner found, with
-- the switches above, that the dark specks on their graphics card come
-- of this pass: 2026-11-15.)
Graphics.VIEWS = { "The picture", "Its edges", "Its weights" }

local view, plain = 1, false

function Graphics.View(): number
  return view
end

function Graphics.Plain(): boolean
  return plain
end

-- Show a view (1 to #Graphics.VIEWS) and blend the plain way or not.
function Graphics.AntiAliasing(shown: number, plainBlend: boolean)
  view, plain = math.clamp(math.floor(shown), 1, #Graphics.VIEWS), plainBlend
  RenderPass_SMAASet(view - 1, plain)
end

-- Set every stage from what the settings kept (Graphics.Off's): what
-- is named is off and everything else is on. A name that is no
-- stage's is passed over.
function Graphics.Apply(kept: string)
  off = {}
  look = "standard"
  -- (seams are off unless the settings say "seams": the owner's, 2026-11-28)
  Plates.Seams(string.find(kept, "%f[%w]seams%f[%W]") ~= nil)
  Plates.Panels(string.find(kept, "%f[%w]panels%f[%W]") ~= nil)
  for id: string in string.gmatch(kept, "[^,%s]+") :: any do
    local named = string.match(id, "^look:(.+)$")
    for _, one in Graphics.LOOKS do
      if one.id == named then
        look = one.id
      end
    end
    for _, stage in Graphics.STAGES do
      if stage.id == id then
        off[id] = true
      end
    end
  end
  tell()
end

return Graphics
