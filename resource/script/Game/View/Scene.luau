--!strict
-- Shows the Core's space with engine objects. The Core is the truth; this
-- module only mirrors it, and could be thrown away and rebuilt from the
-- state at any moment.
--
-- What is drawn:
--   - everything on the player's grid, as real objects at real size and
--     distance: ships, the station, gate or asteroids of the grid;
--   - the system's planets and moons, in scaled space: each is drawn in
--     its true direction at a distance the renderer can reach, shrunk by
--     the same factor, so it covers exactly the right part of the sky;
--   - the sun, as the direction light comes from;
--   - a station as what it is made of (Game/View/Starbase): its control
--     tower, the modules anchored round it, and its field;
--   - on a hull of our own design, what is fitted to its hardpoints
--     (Game/View/Arms): the turrets turn to what they are shooting at,
--     and their shots leave from their mouths.
--
-- The engine's positions lose precision far from zero, and its far plane
-- is at 1e6. So the scene's origin is the anchor of the player's grid
-- (or, in warp, the ship itself), and everything is placed relative to
-- that, worked out in doubles first.
--
-- Between ticks ships are drawn where the Core's own formulas put them
-- (Tactical/Motion): the state at a tick fixes the next second of flight.

local Arms = require("@lt/Game/View/Arms")
local Clock = require("@lt/Game/Clock")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Core = require("@lt/Core/Api")
local Effects = require("@lt/Game/View/Effects")
local Horizon = require("@lt/Game/View/Horizon")
local Hull = require("@lt/Game/View/Hull")
local Movers = require("@lt/Game/View/Movers")
local Planet = require("@lt/Game/View/Planet")
local Plates = require("@lt/Game/View/Plates")
local Star = require("@lt/Game/View/Star")
local Starbase = require("@lt/Game/View/Starbase")
local Citadel = require("@lt/Game/View/Citadel")
local Deployables = require("@lt/Core/Data/Deployables")
local Structures = require("@lt/Core/Data/Structures")
local Modules = require("@lt/Core/Data/Modules")
local Paints = require("@lt/Core/Data/Paints")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Motion = require("@lt/Core/Tactical/Motion")
local Ores = require("@lt/Core/Data/Ores")
local Session = require("@lt/Game/Session")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local SystemData = require("@lt/Core/Describe/System")

local Scene = {}

-- Whether a faction's own ships are drawn in its livery, and its police
-- in theirs (Core/Data/Paints, Paints.Dress), where nobody has painted
-- them otherwise. (A first shot, the owner's of 2026-11-15: false has
-- every such ship as it left the yard, as they all were before.)
Scene.LIVERIES = true

export type Placed = { object: Object, x: number, y: number, z: number, radius: number }

-- What stands on one mount of a ship.
type Arm = {
  piece: Arms.Piece?,       -- nil for the cover on an empty hardpoint
  base: Object?,
  gun: Object?,             -- nil on a hull whose guns are built into it (Hull's 'inbuilt'): nothing stands there
  mount: Hull.Mount,
  yaw: number,              -- where a turret has swung to: radians round from rest,
  lift: number,             -- and up from level
}

-- A hardpoint and what is fitted to it: the same weapon on each of its
-- two mounts, on opposite sides of the hull (Game/View/Hull).
type Point = {
  item: number,             -- the fitted module, or 0 if the hardpoint is empty
  arms: { Arm },
  off: number,              -- how far the gun that faces the target is from pointing at it, in radians (-1 with none)
}

-- And all of a ship's. 'key' is the fit they were made for.
type Armed = { key: string, points: { Point }, built: Hull.Built }

-- A wreck as drawn: the pieces of the hull it was (Hull.Wreck), each
-- turning slowly about its own middle as they drift apart.
type Wrecked = {
  pieces: { { object: Object, middle: vector, away: vector, axis: vector, spin: number } },
  right: vector,            -- the way the ship lay when it died
  up: vector,
  look: vector,
  scale: number,            -- metres to one of the hull's own units
  seen: number,             -- when (scene time) it was first drawn
  still: boolean?,          -- a citadel's hulk: it does not come apart
}

-- The ship shown on the fitting screen, as it is in space (the project
-- owner's, 2026-11-13: "can the ships not display in the fitting
-- window as they do in space?", and "eventually we'll want to apply
-- paints there, which means we'll need full rendering"). It is a thing
-- of the scene itself: the hull and what stands on it, put far below
-- where the scene's own camera is (farther than that camera sees, and
-- than this one sees back), with a camera of its own on it, whose
-- picture the fitting screen shows in its wheel. So it is lit by the
-- sun of the system the pilot is in and drawn with the hull's own
-- material, by the same passes as everything else.
type Showcase = {
  container: Object,
  key: string,                        -- the fit it is of (Scene.Dressed's)
  pieces: { { object: Object, part: Part } },
  camera: Camera,
  passes: any,
  drawn: number,                      -- scene.time when it was last shown
  turn: number,
  -- How many frames it has been asked for. A camera just made is not
  -- where it is told to be until the scene has next been stepped: what
  -- it sees before that is whatever lies at the middle of the system.
  frames: number,
}

-- A gun on a citadel (Game/View/Starbase's Arm): what it is, and where
-- it stands from the citadel's middle, m.
type CitadelGun = { type: string, at: vector, pds: boolean? }

export type Scene = {
  camera: Camera,
  system: number,                     -- the system shown; 0 before the first frame
  container: Object?,
  star: Object?,
  sunShade: number,                   -- how much of the sun a lightless sphere hides (sunInHole)
  key: string,                        -- which grid the scene is built for
  ox: number,                         -- the scene origin, in system space
  oy: number,
  oz: number,
  eyeX: number,                       -- where the player is, in system space
  eyeY: number,
  eyeZ: number,
  proxies: { [number]: Object },      -- on-grid bodies by id
  celestials: { [number]: Object },   -- planets and moons by id
  worlds: { [number]: Planet.World }, -- those of them that turn (Planet.Turn), by id
  passing: number,                    -- ships drawn this frame that are in warp, coming or going
  screen: { [number]: vector },       -- where each drawn body is in the scene, this frame
  focus: Object?,
  yaw: number,
  pitch: number,
  zoom: number,                       -- camera distance, in focus radii
  zoomTarget: number,
  -- What the camera keeps in view past the ship (the id of something on
  -- the grid), or 0: it looks where it was last left.
  tracking: number,
  warp: number,                       -- 0 out of warp, rising to 1 in the middle of one
  warpLeft: number,                   -- metres still to go
  warpSeconds: number,                -- and seconds
  time: number,                       -- seconds the scene has been running, for effects
  -- The way each ship's hull points, by its id, and the game's time when
  -- they were last turned: a hull comes round to the way it is going at
  -- a rate of its own, and does not snap to it.
  headings: { [number]: vector },
  turned: number,
  fx: Effects.Fx?,                    -- weapon fire and the like, in this system's container
  mining: { [number]: number },       -- when each mining module's beam was last begun, by its item
  tethers: { [number]: number },      -- when each tethered ship's beam was last begun, by its ship
  -- A citadel's observatory or mining turret, working (Game/View/Starbase's Layout 'special'), by its station; the
  -- rock an asteroid miner is drawing in, and when its beam was last begun.
  citadelSpecial: { [number]: { kind: string, at: vector } },
  citadelRocks: { [number]: { object: Object, from: vector, born: number, size: number } },
  citadelBeams: { [number]: number },
  citadelGuns: { [number]: { CitadelGun } },  -- a citadel's guns where they are on it, by its station
  wreckage: { [number]: Wrecked },    -- the pieces of each wreck on the grid
  bubbles: { [number]: Object },      -- the interdiction fields in the system, by their ids
  works: { [number]: { Object } },    -- what stands round each station's tower: its modules, their guns, its field
  -- Where each of those stands from the station's middle, in the order
  -- of 'works' and after the tower's own (the first): to move them by.
  offsets: { [number]: { vector } },
  moving: { [number]: { Starbase.Moving } },  -- what moves of each station's tower (they are among its works)
  -- What turns of each stargate (its pieces are among its works), and
  -- how fast it turns now: 1 at rest, more while ships go through it.
  gateTurns: { [number]: GateTurning },
  -- Ships going through the gates in sight, by id: the stage of their
  -- passage last seen (its 'startTick'), and whether the horizon has
  -- rippled yet for their going in and their coming out.
  crossings: { [number]: { start: number, went: boolean, came: boolean } },
  -- The described bodies there are proxies of (rocks, stations, gates), by id.
  statics: { [number]: SystemData.Object },
  -- The clouds of gas among them: how big each puff of one is when the
  -- cloud is whole (the cloud's own first), and how much of the cloud
  -- was left when it was last sized.
  clouds: { [number]: { sizes: { number }, shown: number } },
  -- Whose bodies are in the scene: the grid the ship is on, or in warp
  -- the one it left and the one it is coming to (the ids, as one word).
  sites: string,
  left: number,                       -- the grid the ship was last on in this system; 0: none yet
  -- A jump through a gate, as it is shown. The Core has the ship in the
  -- next system at once; the scene holds the one it left for a moment
  -- while the view rushes and whites out ('jump': when that began, in
  -- scene time, or -1), makes the next one behind the white, and comes
  -- out of it there ('arrived': when, or -1).
  jump: number,
  arrived: number,
  lit: boolean,                       -- the gate the pilot came out of has had its light (once an arrival)
  gates: number,                      -- how many times a gate has been lit by somebody going through it
  veil: number,                       -- how much of the view is whited out, 0 to 1 (the interface draws it)
  veilColor: vector,                  -- and in what: white out of a wormhole or a drive, black through a stargate
  -- The pilot's own passage through a stargate as it is shown (Core's
  -- State.Transit; the owner, 2026-11-21: an approach, the crossing,
  -- "a rapid acceleration to black", a black tunnel that hides the
  -- making of the next system, and out through the far gate with the
  -- system seen through it and black all round). Nil when there is none.
  passage: Passage?,
  -- The way the camera is kept behind the ship along, while it is not
  -- the pilot's to turn (a passage); nil when it is.
  chase: vector?,
  eyeAt: vector,                      -- where the camera was put last, in the scene
  rush: number,                       -- how far the view is opened out by a jump, 0 to 1
  standing: { [number]: string },     -- what a pilot's starbase was made of when it was put up here
  epoch: number,                      -- the game (Session's 'epoch') the scene was made for
  volleys: number,                    -- shots of a station's batteries shown so far
  docked: boolean,                    -- the pilot is docked: the camera is on the station
  showcases: { [string]: Showcase },  -- a ship shown in a window, as a thing of the scene, by the window (Scene.Showcase)
  zoomAway: number,                   -- the zoom there was before docking, to go back to
  arms: { [number]: Armed },          -- what is on the hardpoints of each ship of our own design
  -- (and its moving parts: Game/View/Movers, 2026-11-20)
  movers: { [number]: { pieces: { Movers.Piece }, built: Hull.Built } },
  armsTick: number,                   -- the tick the arms were last checked against the fits
  ghosts: { [number]: boolean },      -- the ships drawn cloaked now (Hull.Ghost in place of the hull)
  -- Ships stood somewhere for a picture (Scene.Pose): the way each is
  -- to point while it stands still.
  poses: { [number]: vector },
  armsTime: number,                   -- when (scene time) the turrets were last swung
}

-- A shot to show: who at whom, how it went, and when (scene time). A
-- missile takes 'flight' seconds to arrive; anything else is instant.



-- A ship in warp is on no grid, and is drawn all the same while it is
-- within this of the pilot: so that one leaving is seen to go, drawing
-- its trail out behind it, and one arriving is seen to come in. (A
-- frigate is this far off two or three seconds into its warp, and is
-- that long again and more coming down from it at the other end. The
-- far plane cuts the ship itself off long before: what is seen out
-- there is its trail.)
local PASSING = 20000000
-- The seconds of its way a ship in warp trails behind it, at least, and
-- the colour of the trail of one whose hull has no engines to give it one.
local WAKE = 1.4
local WAKE_COLOR = vector.create(0.55, 0.78, 1.0)

-- In warp, what is on the grid the ship has left, and on the one it is
-- coming to, is drawn as it is while it is nearer than this: so that a
-- belt's rocks fall away behind and come up ahead, and are not there
-- one moment and gone the next. (Under FAR: past that a place is only
-- a mark in its direction.)
local NEAR = 550000

-- Bodies beyond the renderer's reach are drawn this far away, or a
-- little farther to stand behind a nearer one, but never past FARTHEST
-- (the renderer draws nothing beyond a million).
local FAR = 600000
local FARTHEST = 950000

-- The sun has its flare while its disc spans less than this (the sine of
-- the angle its radius spans: about a degree and a half).
local FLARE_UNDER = 0.026

-- The size of a living world's cube map in the game: smaller than the
-- viewer's, since a system may hold several (about 28 MB each).
local WORLD_MAP = 768
local MOON_MAP = 512

-- How a hull type looks, until hulls have their own generator specs: the
-- seed of the old generator. Its size comes from the hull's radius. The
-- generator sizes a hull by its "value" (radius grows as the square root;
-- 0.0675 m per root-credit, measured), and an instance must not be
-- rescaled afterwards: the engine stops drawing a ship whose scale has
-- been changed.
local HULL_SEED: { [string]: number } = {
  ["frigate.courier"] = 55,
}
local hullItems: { [string]: Item } = {}

-- A passage through a stargate, shown (Scene's 'passage'):
--   leave  through the gate: the ship goes on and away into the black
--          and the camera lags behind it ('since': when it crossed; 'at'
--          and 'way' where and which way; 'speed' how fast)
--   load   the screen black, the next system made a piece a frame
--          ('steps'), the far side made ready and the Core told so
--   out    out of the far gate ('at', 'way': its middle and the way out),
--          the black clearing; a tube of black behind it till the
--          camera is through
-- ('tube': the black tube behind the gate, while it stands.) Through a
-- sphere (a wormhole, a jump bridge's or a wormhole station's: 'sphere'
-- its radius, 0 for a gate) there is no tube: the sphere is lightless
-- inside and hides the ship, which slows to a stop within it.
type Passage = { stage: string, since: number, at: vector, way: vector, speed: number, tube: Object?,
  steps: { () -> () }?, settle: number, asked: boolean, eye: vector, sphere: number }

function Scene.New(camera: Camera): Scene
  return {
    camera = camera, system = 0, container = nil, star = nil, key = "",
    ox = 0, oy = 0, oz = 0, eyeX = 0, eyeY = 0, eyeZ = 0,
    proxies = {}, celestials = {}, worlds = {}, passing = 0, screen = {}, focus = nil,
    yaw = 0.6, pitch = 1.25, zoom = 6, zoomTarget = 6, tracking = 0,
    warp = 0, warpLeft = 0, warpSeconds = 0, time = 0, fx = nil, mining = {}, tethers = {}, citadelGuns = {},
    citadelSpecial = {}, citadelRocks = {}, citadelBeams = {},
    wreckage = {}, bubbles = {}, works = {}, offsets = {}, moving = {}, gateTurns = {}, crossings = {}, statics = {}, clouds = {}, sites = "", left = 0, jump = -1, arrived = -1, lit = true, gates = 0, veil = 0, rush = 0,
    veilColor = vector.create(0.80, 0.92, 1.0), sunShade = 0, passage = nil, chase = nil, eyeAt = vector.create(0, 0, 0),
    standing = {}, showcases = {}, epoch = 1, volleys = 0, docked = false, zoomAway = 6, arms = {}, movers = {}, armsTick = -1, armsTime = 0, ghosts = {}, poses = {}, headings = {}, turned = 0,
  }
end

-- Put an object so that the middle of its bounds is at 'at'. A generated
-- model's own origin can be well off-centre (a station's is at one end),
-- and the Core's position for a body is the centre of its sphere.
-- Where a citadel's gun is in 'scene.screen', by its station and its
-- place among the citadel's guns.
local function citadelGunKey(station: number, n: number): number
  return -(2 ^ 42 + station * 1024 + n)
end

-- Where a citadel's observatory or mining turret is in 'scene.screen', and
-- where its mining beam ends.
local function specialKey(station: number): number
  return -(2 ^ 42 + station * 1024 + 1000)
end
local function beamEndKey(station: number): number
  return -(2 ^ 42 + station * 1024 + 1001)
end

-- A citadel's core (Core/Assets/Starbases) is where its station is drawn:
-- its guns fire from there, and its tethers hold from there.
local function citadelCores(scene: Scene, state: any)
  -- (a faction's citadel's too, since 2026-11-20: Core/Assets/Citadels)
  for _, key in state.citadelIds or {} do
    local record = state.citadels[key]
    local at = scene.screen[record.station]
    if at and record.core and not scene.screen[record.core] then
      scene.screen[record.core] = at
    end
    if at then
      for n, gun in scene.citadelGuns[record.station] or {} :: { CitadelGun } do
        scene.screen[citadelGunKey(record.station, n)] = at + gun.at
      end
    end
  end
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local at = scene.screen[id]
    if at and starbase.core ~= 0 and not scene.screen[starbase.core] then
      scene.screen[starbase.core] = at
    end
    -- (and each of its guns, where it stands on it)
    if at then
      for n, gun in scene.citadelGuns[id] or {} :: { CitadelGun } do
        scene.screen[citadelGunKey(id, n)] = at + gun.at
      end
    end
  end
end

-- Which of a citadel's guns fired a shot (Core/Tactical/CitadelGuns: the
-- 'mount'th of its weapons of that type, or of its point defence turrets
-- for "pds"), as its place in 'scene.screen'.
local function citadelGun(scene: Scene, state: any, core: number, type: string, mount: number?): number?
  -- (whose citadel's core it is: a pilot's, or a faction's, Core/Assets/Citadels)
  local stations: { number } = {}
  for _, id in state.starbaseIds do
    if state.starbases[id].core == core then
      table.insert(stations, id)
    end
  end
  for _, key in state.citadelIds or {} do
    if state.citadels[key].core == core then
      table.insert(stations, state.citadels[key].station)
    end
  end
  for _, id in stations do
    do
      local count = 0
      for n, gun in scene.citadelGuns[id] or {} :: { CitadelGun } do
        if (type == "pds" and gun.pds) or (type ~= "pds" and gun.type == type and not gun.pds) then
          count += 1
          if count == (mount or 1) then
            return citadelGunKey(id, n)
          end
        end
      end
    end
  end
  return nil
end

local function place(object: Object, at: vector)
  object:SetPos(at)
  object:SetPos(at + (at - object:GetCenter()))
end

-- The proxies that are hulls of our own design (Game/View/Hull), which
-- are scenery and are turned by Object_SetAxes; the rest are the
-- engine's ships.
local designed: { [Object]: Hull.Built } = setmetatable({} :: any, { __mode = "k" })

-- ('pirate': it is a pirate's, and looks it. 'paint' and 'design': what
-- its pilot has had it painted in: Core/Assets/Paintwork.)
local function makeShip(type: string, radius: number, pirate: boolean, rank: number?, paint: string?, design: string?): Object
  local built = Hull.Build(type, pirate, rank, paint, design)
  if built then
    local object = Object_Scenery({})
    Object_SetRenderable(object, built.model)
    local size = radius / built.radius
    object:SetScale(vector.create(size, size, size))
    designed[object] = built
    return object
  end
  local item: Item? = hullItems[type]
  if not item then
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or HULL_SEED[(string.gsub(type, "%.ii$", ""))] or 55, 1, 1, 1, 1, 1, 1)
    hullItems[type] = made
    return made:Instantiate()
  end
  return item:Instantiate()
end

-- The model of a hull type of this radius, for the interface to draw.
function Scene.Preview(type: string, radius: number): Renderable | Model
  local built = Hull.Build(type)
  if built then
    return built.model
  end
  local item: Item? = hullItems[type]
  if not item then
    local made = Item_ShipType((radius / 0.0675) ^ 2, HULL_SEED[type] or HULL_SEED[(string.gsub(type, "%.ii$", ""))] or 55, 1, 1, 1, 1, 1, 1)
    hullItems[type] = made
    item = made
  end
  return (item :: Item):GetRenderable()
end

-- Which weapon goes on which hardpoint: a ship's fitted weapons in the
-- order of their slots, each on the next hardpoint of its kind, and
-- nothing (nil) on every hardpoint left over. 'each' is told of every
-- hardpoint the hull has.
local function assign(fitted: { State.Item }, built: Hull.Built, each: (hardpoint: Hull.Hardpoint, item: State.Item?) -> ())
  local turrets, launchers = 0, 0
  for _, item in fitted do
    local module = Modules.byId[item.type]
    if module and item.place == "high" and module.hardpoint == "turret" then
      turrets += 1
      if built.turrets[turrets] then
        each(built.turrets[turrets], item)
      end
    elseif module and item.place == "high" and module.hardpoint == "launcher" then
      launchers += 1
      if built.launchers[launchers] then
        each(built.launchers[launchers], item)
      end
    end
  end
  for at = turrets + 1, #built.turrets do
    each(built.turrets[at], nil)
  end
  for at = launchers + 1, #built.launchers do
    each(built.launchers[at], nil)
  end
end

-- One thing to draw of a ship shown in the interface: a model, and how
-- it stands on the hull, in the hull's own units.
-- ('at', 'look', 'up' and 'size' are the same again, apart: for what
-- stands it in the scene, Scene.Showcase.)
export type Part = { model: Renderable | Model, transform: Transform, at: vector, look: vector, up: vector, size: number }

-- (by key: the fitting window's ship and the information window's hull are each kept)
local dressedBy: { [string]: { Part } } = {}
local dressedCount = 0

-- A ship stood somewhere for a picture: the way it is to point while
-- it stands still. And the way a ship is drawn pointing now (straight
-- ahead along z, if it has never moved).
function Scene.Pose(scene: Scene, ship: number, heading: vector)
  scene.poses[ship] = vector.normalize(heading)
end

function Scene.Heading(scene: Scene, ship: number): vector
  return scene.headings[ship] or vector.create(0, 0, 1)
end

-- A paint and a design being tried on the ship the fitting screen
-- shows, before either is bought: the ship is shown in them, and is
-- not painted. Nothing of either, to show it as it is.
local tried: { paint: string?, design: string? } = {}

function Scene.Try(paint: string?, design: string?)
  tried.paint, tried.design = paint, design
end

function Scene.Trying(): (string?, string?)
  return tried.paint, tried.design
end

-- A ship as it is fitted, for the interface to draw: its hull, and on a
-- hull of our own design what stands on its hardpoints, at rest, with a
-- cover on each one left empty. 'radius' is the hull's, in metres. (The
-- last one asked for is kept, and made again only when the fit changes.)
-- The hull of a ship as the interface shows it: in the paint it has,
-- and the design on that; or in what is being tried on it before it is
-- bought (Scene.Try). And what it is painted in, so shown.
local function hullOf(game: Core.Game, ship: number, type: string): (Hull.Built?, string?, string?)
  local own = game.state.ships[ship]
  -- (a ship of 0 is a hull in its base paint: what is being tried on the pilot's is not on it)
  local paint: string? = if ship == 0 then nil else tried.paint or (if own then own.paint else nil)
  local design: string? = if ship == 0 then nil else tried.design or (if own then own.design else nil)
  return Hull.Build(type, nil, nil, paint, design), paint, design
end

function Scene.Dressed(game: Core.Game, ship: number, type: string, radius: number): ({ Part }, string)
  local built, paint, design = hullOf(game, ship, type)
  if built == nil then
    return { { model = Scene.Preview(type, radius), transform = Transform_Identity(), at = vector.create(0, 0, 0),
      look = vector.create(0, 0, 1), up = vector.create(0, 1, 0), size = 1 } }, ""
  end
  local fitted = Core.Query.Fitted(game, ship)
  local key = `{ship}:{type}:{paint or ""}:{design or ""}`
  for _, item in fitted do
    if item.place == "high" then
      key ..= ` {item.id}:{item.type}`
    end
  end
  local known = dressedBy[key]
  if known then
    return known, key
  end
  local parts: { Part } = { { model = built.model, transform = Transform_Identity(), at = vector.create(0, 0, 0),
    look = vector.create(0, 0, 1), up = vector.create(0, 1, 0), size = 1 } }
  local unit = built.radius / radius      -- one metre, in the hull's own units
  local function stand(model: Model, at: vector, look: vector, up: vector, size: number)
    local transform = Transform_LookUp(at, look, up)
    transform.scale = vector.create(size, size, size)
    table.insert(parts, { model = model, transform = transform, at = at, look = look, up = up, size = size })
  end
  assign(fitted, built, function(hardpoint: Hull.Hardpoint, item: State.Item?)
    local piece = if item then Arms.Build(item.type) else nil
    for _, mount in hardpoint do
      local fore = mount.fore or vector.create(0, 0, 1)
      local level = fore - mount.up * vector.dot(fore, mount.up)
      level = if vector.magnitude(level) > 1e-4 then vector.normalize(level) else vector.normalize(vector.cross(mount.up, vector.create(1, 0, 0)))
      if piece then
        local size = piece.scale * unit
        if piece.base then
          stand(piece.base, mount.at, level, mount.up, size)
        end
        local right = vector.cross(mount.up, level)
        stand(piece.gun, mount.at + (right * piece.pivot.x + mount.up * piece.pivot.y + level * piece.pivot.z) * size, level, mount.up, size)
      elseif not built.inbuilt then
        stand(Arms.Blank(), mount.at, level, mount.up, (Arms.SIZE[Arms.SizeOf(built.fit[1] or "")] or 1) * unit)
      end
    end
  end)
  -- (its moving parts, at rest)
  for _, rest in Movers.Rest(built.movers) do
    stand(rest.model, rest.at, rest.look, rest.up, 1)
  end
  -- (a few at a time: what was dressed long ago is let go)
  dressedCount += 1
  if dressedCount > 8 then
    table.clear(dressedBy)
    dressedCount = 1
  end
  dressedBy[key] = parts
  return parts, key
end

-- How far below the scene's own camera the fitting screen's ship is
-- put, metres: beyond what either camera sees of the other's.
local SHOWCASE_BELOW = 3000000
local SHOWCASE_FOV = 26

-- Take a window's ship out of the scene (or every window's, with no slot named).
local function dropShowcase(scene: Scene, slot: string?)
  for name, show in scene.showcases do
    if slot == nil or name == slot then
      for _, piece in show.pieces do
        Object_Delete(piece.object)
      end
      Object_Delete(show.camera)
      scene.showcases[name] = nil
    end
  end
end
-- (where each window's ship stands, below the eye: apart, so that one window's camera does not see the other's ship)
local SHOWCASE_SLOTS: { [string]: number } = { fitting = 0, info = 1 }

-- Show a ship as it is fitted, in a round window of the interface whose
-- middle is (cx, cy), as it would be seen in space where the pilot is:
-- turning slowly, the sun over the viewer's shoulder. False if it
-- cannot be (a hull with no design of ours, or before the scene has a
-- system): the fitting screen then draws it its old way.
--
-- ('slot': which window it is for, "fitting" unless said: each has its
-- own. 'aspect': as much wider than high as it is drawn, for a window
-- that is not round. A ship of 0 is a hull of the type in its base
-- paint, with nothing fitted: the information window's.)
function Scene.Showcase(scene: Scene, game: Core.Game, ship: number, type: string, radius: number, cx: number, cy: number,
  round: number, slot: string?, aspect: number?): boolean
  local name = slot or "fitting"
  local container = scene.container
  -- (the hull as it is painted: a painted one is not drawn the size a bare one is)
  local built = hullOf(game, ship, type)
  if container == nil or built == nil then
    return false
  end
  local parts, key = Scene.Dressed(game, ship, type, radius)
  local show = scene.showcases[name]
  if show == nil or show.container ~= container or show.key ~= key then
    local turn = if show then show.turn else 0.6
    dropShowcase(scene, name)
    local pieces: { { object: Object, part: Part } } = {}
    for _, part in parts do
      local object = Object_Scenery({})
      Object_SetRenderable(object, part.model)
      container:AddInterior(object)
      table.insert(pieces, { object = object, part = part })
    end
    local camera = Camera_Create()
    container:AddInterior(camera)
    local passes = New.Vector_Reference_RenderPassT()
    passes:Append(RenderPass_Clear(0))
    passes:Append(RenderPass_Camera(camera))
    show = { container = container, key = key, pieces = pieces, camera = camera, passes = passes, drawn = scene.time, turn = turn,
      frames = 0 }
    scene.showcases[name] = show
  end
  local shown = show :: Showcase
  shown.drawn = scene.time
  shown.turn += 0.25 * FrameTimer_Get()
  -- Where it stands, and turned about its own upright.
  local metre = radius / built.radius     -- a unit of the hull's, in metres
  local base = vector.create(scene.eyeX - scene.ox + (SHOWCASE_SLOTS[name] or 2) * SHOWCASE_BELOW, scene.eyeY - scene.oy - SHOWCASE_BELOW,
    scene.eyeZ - scene.oz)
  local c, s = math.cos(shown.turn), math.sin(shown.turn)
  local function turned(v: vector): vector
    return vector.create(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
  end
  for _, piece in shown.pieces do
    local part = piece.part
    local size = part.size * metre
    piece.object:SetPos(base + turned(part.at) * metre)
    Object_SetAxes(piece.object, turned(part.look), turned(part.up))
    piece.object:SetScale(vector.create(size, size, size))
  end
  -- The eye: off the side the sun is on, a little round from it and a
  -- little above, far enough off to have the whole hull in the window.
  local toSun = vector.create(1, 0.2, 0.3)
  for _, object in Core.Query.Objects(game, scene.system) do
    if object.kind == "sun" then
      local away = vector.create(object.x - scene.eyeX, object.y - scene.eyeY, object.z - scene.eyeZ)
      if vector.magnitude(away) > 1 then
        toSun = away
      end
    end
  end
  toSun = vector.normalize(toSun)
  local up = vector.create(0, 1, 0)
  local side = vector.cross(up, toSun)
  side = if vector.magnitude(side) > 1e-3 then vector.normalize(side) else vector.create(1, 0, 0)
  local toEye = vector.normalize(toSun * 0.7 + side * 0.6 + up * 0.38)
  -- (a model is not always about its own origin: it is its middle that is looked at)
  local bound = Renderable_GetBound(built.model)
  local middle = base + turned((bound.lower + bound.upper) * 0.5) * metre
  -- (a box is filled more closely than the wheel's round)
  -- (and what stands out past its hull at rest, the capsule's antennas, is taken in)
  local framed = radius * math.max(1, (built.reach or built.radius) / built.radius)
  local distance = framed * (if aspect then 0.8 else 1.12) / math.tan(math.rad(SHOWCASE_FOV) / 2)
  local camera = shown.camera
  camera:SetTarget(shown.pieces[1].object)
  camera:SetRelativePos(middle + toEye * distance)
  camera:SetRelativeLookAt(middle)
  camera:SetRigidity(100000)
  camera:SetFov(SHOWCASE_FOV)
  -- (not in the frame it is made, nor the next: its camera is not yet where it looks from)
  shown.frames += 1
  if shown.frames > 2 then
    local wide = round * (aspect or 1)
    -- (round for the fitting window's wheel; a box for a window that says how wide)
    WidgetRenderer_DrawPasses(shown.passes, vector.create(cx - wide, cy - round), vector.create(2 * wide, 2 * round), 1, aspect == nil)
  end
  return true
end

-- Show the station the pilot is docked at, as it stands in space, in a
-- round window of the interface whose middle is (cx, cy): a camera of
-- its own goes slowly round it, the sun over the viewer's shoulder (the
-- citadel's window, 2026-11-19: "it should look like the regular ship
-- fitting window"). False if it cannot be (no scene yet, or the station
-- is not drawn).
function Scene.ShowStation(scene: Scene, station: number, cx: number, cy: number, round: number): boolean
  local name = "station"
  local container = scene.container
  local found: Object? = scene.proxies[station]
  if container == nil or found == nil then
    return false
  end
  local focus = found :: Object
  local key = `station:{station}`
  local show = scene.showcases[name]
  if show == nil or show.container ~= container or show.key ~= key then
    local turn = if show then show.turn else 0.6
    dropShowcase(scene, name)
    local camera = Camera_Create()
    container:AddInterior(camera)
    local passes = New.Vector_Reference_RenderPassT()
    passes:Append(RenderPass_Clear(0))
    passes:Append(RenderPass_Camera(camera))
    show = { container = container, key = key, pieces = {}, camera = camera, passes = passes, drawn = scene.time, turn = turn, frames = 0 }
    scene.showcases[name] = show
  end
  local shown = show :: Showcase
  shown.drawn = scene.time
  shown.turn += 0.05 * FrameTimer_Get()
  local center = focus:GetCenter()
  -- (the eye a little above, going round; far enough off to have the whole of it in the window)
  local toEye = vector.normalize(vector.create(math.cos(shown.turn), 0.45, math.sin(shown.turn)))
  local distance = focus:GetRadius() * 1.15 / math.tan(math.rad(SHOWCASE_FOV) / 2)
  local camera = shown.camera
  camera:SetTarget(focus)
  camera:SetRelativePos(center + toEye * distance)
  camera:SetRelativeLookAt(center)
  camera:SetRigidity(100000)
  camera:SetFov(SHOWCASE_FOV)
  shown.frames += 1
  if shown.frames > 2 then
    WidgetRenderer_DrawPasses(shown.passes, vector.create(cx - round, cy - round), vector.create(2 * round, 2 * round), 1, true)
  end
  return true
end

-- Take what is on a ship's hardpoints away (and its moving parts).
local function dropArms(scene: Scene, id: number)
  local moving = scene.movers[id]
  if moving then
    for _, piece in moving.pieces do
      Object_Delete(piece.object)
      local head, glow = piece.head, piece.glow
      if head then
        Object_Delete(head)
      end
      if glow then
        Object_Delete(glow)
      end
      for _, part in piece.parts do
        Object_Delete(part)
      end
    end
    scene.movers[id] = nil
  end
  local armed = scene.arms[id]
  if armed then
    for _, point in armed.points do
      for _, arm in point.arms do
        if arm.base then
          Object_Delete(arm.base)
        end
        if arm.gun then
          Object_Delete(arm.gun)
        end
      end
    end
    scene.arms[id] = nil
  end
end

-- Take a wreck's pieces away.
local function dropWreck(scene: Scene, id: number)
  local wrecked = scene.wreckage[id]
  if wrecked then
    for _, piece in wrecked.pieces do
      Object_Delete(piece.object)
    end
    scene.wreckage[id] = nil
  end
end

-- Take away what stands round a station's tower.
local function dropWorks(scene: Scene, id: number)
  local works = scene.works[id]
  if works then
    for _, object in works do
      Object_Delete(object)
    end
    scene.works[id] = nil
  end
  scene.offsets[id] = nil
  scene.moving[id] = nil
  scene.gateTurns[id] = nil
  scene.standing[id] = nil
  scene.citadelSpecial[id] = nil
  local rock = scene.citadelRocks[id]
  if rock then
    Object_Delete(rock.object)
    scene.citadelRocks[id] = nil
  end
end

-- A number from 0 to 1 that follows from 'n'.
local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- 'v' turned by 'angle' about the axis 'k' (of length 1).
local function about(v: vector, k: vector, angle: number): vector
  local c, s = math.cos(angle), math.sin(angle)
  return v * c + vector.cross(k, v) * s + k * (vector.dot(k, v) * (1 - c))
end

-- Make the pieces of a wreck, lying as the ship lay ('look' and 'up').
-- (A citadel's hulk is the citadel, dark, upright where it stood, and
-- does not come apart: its rings, if it has any, lie still in it.)
local function makeWreck(scene: Scene, id: number, wreck: State.Wreck, look: vector, up: vector, container: Object)
  -- (a deployable of the pilot's, put out in space: drawn as the starbase module it is made like, Core/Data/Deployables)
  local deployed = if wreck.deploy then Deployables.byId[wreck.deploy] else nil
  if deployed then
    local made = Starbase.Module(deployed.model)
    local scale = wreck.radius / made.radius
    local object = Object_Scenery({})
    Object_SetRenderable(object, made.model)
    object:SetScale(vector.create(scale, scale, scale))
    container:AddInterior(object)
    scene.wreckage[id] = { pieces = { { object = object, middle = vector.create(0, 0, 0), away = vector.create(0, 1, 0),
      axis = vector.create(0, 1, 0), spin = 0 } }, right = vector.create(-1, 0, 0), up = vector.create(0, 1, 0),
      look = vector.create(0, 0, 1), scale = scale, seen = scene.time, still = true }
    return
  end
  local tower = if wreck.hulk then Structures.towerById[wreck.hulk] else nil
  if tower then
    local made = Citadel.Hulk(tower.kind, tower.size, if tower.faction ~= "" then tower.faction else nil)
    local scale = wreck.radius / made.radius
    local middle = (made.lower + made.upper) * 0.5
    local still: Wrecked = { pieces = {}, right = vector.create(-1, 0, 0), up = vector.create(0, 1, 0), look = vector.create(0, 0, 1),
      scale = scale, seen = scene.time, still = true }
    local models = { made.model }
    local movers: { Citadel.Mover } = made.movers or {}
    for _, mover in movers do
      table.insert(models, mover.model)
    end
    for _, model in models do
      local object = Object_Scenery({})
      Object_SetRenderable(object, model)
      object:SetScale(vector.create(scale, scale, scale))
      container:AddInterior(object)
      table.insert(still.pieces, { object = object, middle = middle, away = vector.create(0, 1, 0), axis = vector.create(0, 1, 0), spin = 0 })
    end
    scene.wreckage[id] = still
    return
  end
  local wreckage = Hull.Wreck(wreck.hull)
  local scale = wreck.radius / wreckage.radius
  local wrecked: Wrecked = { pieces = {}, right = vector.cross(up, look), up = up, look = look, scale = scale, seen = scene.time }
  for index, piece in wreckage.pieces do
    local object = Object_Scenery({})
    Object_SetRenderable(object, piece.model)
    object:SetScale(vector.create(scale, scale, scale))
    container:AddInterior(object)
    local n = id * 7 + index * 31
    -- (each goes off the way it was already out from the middle, more
    -- or less, and turns about an axis of its own)
    local out = piece.middle + vector.create(dice(n) - 0.5, dice(n + 1) - 0.5, dice(n + 2) - 0.5) * 0.6
    local axis = vector.create(dice(n + 3) - 0.5, dice(n + 4) - 0.5, dice(n + 5) - 0.5)
    table.insert(wrecked.pieces, {
      object = object, middle = piece.middle,
      away = if vector.magnitude(out) > 1e-3 then vector.normalize(out) else vector.create(0, 1, 0),
      axis = if vector.magnitude(axis) > 1e-3 then vector.normalize(axis) else vector.create(0, 1, 0),
      spin = (0.02 + 0.05 * dice(n + 6)) * (if dice(n + 7) < 0.5 then -1 else 1),
    })
  end
  scene.wreckage[id] = wrecked
end

-- Put a wreck's pieces where they have got to: 'at' is the wreck, and
-- 'radius' the radius of the ship it was.
local function placeWreck(scene: Scene, wrecked: Wrecked, at: vector, radius: number)
  if wrecked.still then
    -- (a hulk: its middle where it is, upright, as the citadel stood)
    for _, piece in wrecked.pieces do
      piece.object:SetPos(at - piece.middle * wrecked.scale)
      Object_SetAxes(piece.object, wrecked.look, wrecked.up)
    end
    return
  end
  local since = scene.time - wrecked.seen
  -- (they part quickly at first and all but stop within a minute)
  local spread = radius * (0.05 + 0.30 * (1 - math.exp(-since / 20)))
  for _, piece in wrecked.pieces do
    local m = piece.middle
    local middle = at + (wrecked.right * m.x + wrecked.up * m.y + wrecked.look * m.z) * wrecked.scale
      + (wrecked.right * piece.away.x + wrecked.up * piece.away.y + wrecked.look * piece.away.z) * spread
    local angle = piece.spin * since
    local look = about(wrecked.look, piece.axis, angle)
    local up = about(wrecked.up, piece.axis, angle)
    local right = vector.cross(up, look)
    -- (the object is placed by its own origin: its middle is that far from it, turned as it now is)
    piece.object:SetPos(middle - (right * m.x + up * m.y + look * m.z) * wrecked.scale)
    Object_SetAxes(piece.object, look, up)
  end
end

-- Put on a ship's hardpoints what is fitted to it (on both mounts of
-- each hardpoint), and covers on every hardpoint left empty. Nothing is
-- done if they are there already.
local function armShip(scene: Scene, game: Core.Game, id: number, built: Hull.Built, container: Object)
  local fitted = Core.Query.Fitted(game, id)
  local key = ""
  for _, item in fitted do
    if item.place == "high" then
      key ..= `{item.id}:{item.type} `
    end
  end
  local armed = scene.arms[id]
  if armed and armed.key == key then
    return
  end
  dropArms(scene, id)
  local points: { Point } = {}
  local function fill(hardpoint: Hull.Hardpoint, item: State.Item?)
    local piece = if item then Arms.Build(item.type) else nil
    local arms: { Arm } = {}
    for _, mount in hardpoint do
      local base: Object? = nil
      if piece and piece.base then
        local made = Object_Scenery({})
        Object_SetRenderable(made, piece.base)
        container:AddInterior(made)
        base = made
      end
      -- (a gun built into the hull is part of its model, and has nothing put on its mount, not even a cover)
      local gun: Object? = nil
      if piece or not built.inbuilt then
        local made = Object_Scenery({})
        Object_SetRenderable(made, if piece then piece.gun else Arms.Blank())
        container:AddInterior(made)
        gun = made
      end
      table.insert(arms, { piece = piece, base = base, gun = gun, mount = mount, yaw = 0, lift = 0 })
    end
    table.insert(points, { item = if item and (piece or built.inbuilt) then item.id else 0, arms = arms, off = -1 })
  end
  assign(fitted, built, fill)
  scene.arms[id] = { key = key, points = points, built = built }
end

local FORE = vector.create(0, 0, 1)

-- How near the eye a ship's moving parts move (and are drawn), m: beyond
-- it they are too small to see, and cost what they cost for nothing.
local MOVERS_NEAR = 40000

-- What a ship is doing, for its moving parts (Game/View/Movers): in warp,
-- a scanner or an analyzer running, electronic warfare aimed (the way to
-- its target, in the hull's own axes, from 'at' along 'right', 'up' and
-- 'look'), and a mode running (a siege, triage or industrial core
-- module, or a jump portal held open, or a jump just made).
local function doing(scene: Scene, game: Core.Game, ball: State.Ball, at: vector, right: vector, up: vector, look: vector): Movers.State
  local state = game.state
  local out: Movers.State = { warp = ball.warp ~= nil, scan = false, aim = nil, mode = nil }
  for _, run in ball.vitals.running do
    local item = state.items[run.item]
    local module = if item then Modules.byId[item.type] else nil
    if module then
      if module.scanner or module.analyzer then
        out.scan = true
      end
      if (module.hex and not Modules.Friendly(module)) or module.burstJam then
        local there: vector? = scene.screen[run.target]
        if there and vector.magnitude(there - at) > 1 then
          local w = there - at
          out.aim = vector.create(vector.dot(w, right), vector.dot(w, up), vector.dot(w, look))
        end
      end
      if module.triage then
        out.mode = "triage"
      elseif module.core then
        out.mode = "core"
      elseif module.immobile then
        out.mode = "siege"
      end
    end
  end
  local ship = state.ships[ball.id]
  if ship and out.mode == nil then
    local portal = ship.portal
    if (portal and state.tick < portal.ends) or (ship.jumped and (state.tick - ship.jumped) * Constants.TICK < 8) then
      out.mode = "jump"
    end
  end
  return out
end

-- Make a ship's moving parts if they are not made, and pose them where
-- its hull now is: only near the eye (beyond, they are put away).
local function moveParts(scene: Scene, game: Core.Game, id: number, built: Hull.Built, proxy: Object, at: vector, ball: State.Ball,
  container: Object, seconds: number)
  local movers = built.movers
  if movers == nil or #movers == 0 then
    return
  end
  local eye = vector.create(scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz)
  local near = vector.magnitude(at - eye) < math.max(MOVERS_NEAR, ball.radius * 40)
  local moving: { pieces: { Movers.Piece }, built: Hull.Built }? = scene.movers[id]
  if moving and (moving.built ~= built or not near) then
    for _, piece in moving.pieces do
      Object_Delete(piece.object)
      local head, glow = piece.head, piece.glow
      if head then
        Object_Delete(head)
      end
      if glow then
        Object_Delete(glow)
      end
      for _, part in piece.parts do
        Object_Delete(part)
      end
    end
    scene.movers[id] = nil
    moving = nil
  end
  if not near then
    return
  end
  local pieces: { Movers.Piece }
  if moving then
    pieces = moving.pieces
  else
    pieces = Movers.Make(movers, function(model: Model): Object
      local made = Object_Scenery({})
      Object_SetRenderable(made, model)
      container:AddInterior(made)
      return made
    end)
    scene.movers[id] = { built = built, pieces = pieces }
  end
  local right, up, look = proxy:GetRight(), proxy:GetUp(), proxy:GetLook()
  Movers.Animate(pieces, { at = at, right = right, up = up, look = look, unit = ball.radius / built.radius }, scene.time,
    seconds, doing(scene, game, ball, at, right, up, look))
end

-- Stand a ship's arms on its hull where the hull now is, and swing its
-- turrets (for 'seconds', at their own rates). Of the two on a
-- hardpoint, each turns to the target if it can see it, and one that
-- has the hull in the way goes back to rest; the one that faces the
-- target the more squarely is the one that fires, and where its shots
-- leave from is noted: scene.screen holds that under the module's item
-- id, negated.
local function placeArms(scene: Scene, armed: Armed, proxy: Object, at: vector, radius: number, running: { State.Running }, seconds: number)
  local right, up, look = proxy:GetRight(), proxy:GetUp(), proxy:GetLook()
  local unit = radius / armed.built.radius
  -- (an empty hardpoint's cover is the size of the weapons the hull is drawn for)
  local cover = Arms.SIZE[Arms.SizeOf(armed.built.fit[1] or "")] or 1
  for _, point in armed.points do
    local target: vector? = nil
    if point.item ~= 0 then
      for _, run in running do
        if run.item == point.item and run.target ~= 0 then
          target = scene.screen[run.target]
        end
      end
    end
    local best = -2
    point.off = -1
    for index, arm in point.arms do
      local mount = arm.mount
      local fore = mount.fore or FORE
      local origin = at + (right * mount.at.x + up * mount.at.y + look * mount.at.z) * unit
      local mountUp = right * mount.up.x + up * mount.up.y + look * mount.up.z
      local mountFore = right * fore.x + up * fore.y + look * fore.z
      local piece = arm.piece
      local gun = arm.gun
      if piece and gun then
        local aim: vector? = nil
        local facing = 0
        if target and vector.magnitude(target - origin) > 1 then
          local toward = vector.normalize(target - origin)
          facing = vector.dot(toward, mountUp)
          if Arms.Sees(facing) then
            aim = toward
          end
        end
        local direction: vector
        arm.yaw, arm.lift, direction = Arms.Swing(piece, mountUp, mountFore, aim, arm.yaw, arm.lift, seconds)
        local muzzle = Arms.Place(piece, arm.base, gun, origin, mountUp, mountFore, direction, 1)
        if (target ~= nil and facing > best) or (target == nil and index == 1) then
          best = facing
          scene.screen[-point.item] = muzzle
          point.off = if aim and piece.turns then math.acos(math.clamp(vector.dot(direction, aim), -1, 1)) else -1
        end
      elseif gun then
        local level = mountFore - mountUp * vector.dot(mountFore, mountUp)
        gun:SetPos(origin)
        Object_SetAxes(gun, if vector.magnitude(level) > 1e-4 then level else right, mountUp)
        gun:SetScale(vector.create(cover, cover, cover))
      elseif point.item ~= 0 then
        -- (a gun built into the hull: its shots leave from the mouth that faces the target the more squarely)
        local facing = if target and vector.magnitude(target - origin) > 1 then vector.dot(vector.normalize(target - origin), mountUp) else 0
        if (target ~= nil and facing > best) or (target == nil and index == 1) then
          best = facing
          scene.screen[-point.item] = origin
        end
      end
    end
  end
end

-- For checking (GameDebug.Movers): a ship's moving parts that are made,
-- by kind, as words ("antenna 4, dish 2"), and how far the first antenna
-- leans now and the first dish's head is turned (radians), for seeing them
-- answer what the ship does.
function Scene.Movers(scene: Scene, ship: number): (string, number, number)
  local moving = scene.movers[ship]
  if moving == nil then
    return "", 0, 0
  end
  local counts: { [string]: number } = {}
  local order: { string } = {}
  local lean, yaw = -1, 0
  for _, piece in moving.pieces do
    local kind = piece.mover.kind
    if counts[kind] == nil then
      table.insert(order, kind)
    end
    counts[kind] = (counts[kind] or 0) + 1
    if kind == "antenna" and lean < 0 then
      lean = piece.lean
    end
    if (kind == "dish" or kind == "lattice" or kind == "radar") and yaw == 0 then
      yaw = piece.yaw
    end
  end
  local words: { string } = {}
  for _, kind in order do
    table.insert(words, `{kind} {counts[kind]}`)
  end
  return table.concat(words, ", "), lean, yaw
end

-- For checking (GameDebug.Arms): how many weapon models stand on a
-- ship's mounts (two to a fitted weapon), and how far from its target
-- the worst-pointed of its firing turrets still is, in radians (-1 if
-- none has a target).
function Scene.Arms(scene: Scene, ship: number): (number, number)
  local armed = scene.arms[ship]
  local count, off = 0, -1
  if armed then
    for _, point in armed.points do
      for _, arm in point.arms do
        if arm.piece then
          count += 1
        end
      end
      off = math.max(off, point.off)
    end
  end
  return count, off
end

-- What a wormhole is drawn with (Core/Tactical/Wormholes): a unit
-- sphere, to be scaled, with its shader (wormhole.jsl): a lightless
-- sphere, the sky's light bent round it (the owner, 2026-11-17: the old
-- one did not "look like a lightless sphere"). Blended over what is
-- behind it, not added to it: the dark of it hides what is there.
local hole: Model? = nil
local function wormhole(): Model
  local kept = hole
  if kept then
    return kept
  end
  local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "wormhole.jsl"))
  ShaderInstance_SetState(shader, "BlendModeAlpha")
  ShaderInstance_SetState(shader, "ZWritableOff")
  ShaderInstance_SetState(shader, "CullModeDisabled")
  ShaderInstance_SetVec3(shader, "holeCore", vector.create(0, 0, 0))
  ShaderInstance_SetVec3(shader, "holeRing", vector.create(0.55, 0.62, 0.75))
  ShaderInstance_Link(shader)
  local made = Model_Create()
  Model_AddShell(made, Mesh_BoxSphere(16, true), shader)
  hole = made
  return made
end

local function makeStatic(object: SystemData.Object): Object
  local made: Object
  if object.kind == "asteroid" then
    -- (An asteroid cannot be named: the engine object has no such part.)
    made = Object_Asteroid(object.seed)
    -- (a chunk of an ice field is ice to look at, in place of rock: soft
    -- and deep blue, or sharp and pale blue, by its ice. 2026-11-17)
    if Ores.Ice(object.variety) then
      Object_SetRenderable(made, if Ores.byId[object.variety].look == "shard" then Renderable_IceShard(object.seed)
        else Renderable_IceDeep(object.seed))
    end
    made:SetScale(vector.create(object.radius, object.radius, object.radius))
  elseif object.kind == "wormhole" then
    made = Object_Scenery({})
    Object_SetRenderable(made, wormhole())
    made:SetScale(vector.create(object.radius, object.radius, object.radius))
    made:SetName(object.name)
  else
    -- A gate that is not a stargate (a camp's or a deadspace room's): the
    -- old ring, facing out of the system, the way its jump goes. (A
    -- stargate is makeGate; a station is a tower and what is anchored
    -- round it: makeStation.)
    local gate = Starbase.Gate()
    made = Object_Scenery({})
    Object_SetRenderable(made, gate.model)
    local size = object.radius / gate.radius
    made:SetScale(vector.create(size, size, size))
    local out = vector.create(object.x, 0, object.z)
    if vector.magnitude(out) > 1 then
      Object_SetAxes(made, vector.normalize(out), vector.create(0, 1, 0))
    end
    made:SetName(object.name)
  end
  return made
end

-- What a puff of each gas is drawn with: a unit sphere, to be scaled.
local puffs: { [string]: Model } = {}
local TINTS: { [string]: vector } = {
  ["gas.amber"] = vector.create(1.0, 0.62, 0.22), ["gas.verdant"] = vector.create(0.40, 0.95, 0.50),
  ["gas.azure"] = vector.create(0.35, 0.62, 1.0),
}
local function puff(gas: string): Model
  local kept: Model? = puffs[gas]
  if kept then
    return kept
  end
  local made: Model
  do
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "cloud.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "cloudTint", TINTS[gas] or vector.create(0.7, 0.7, 0.7))
    ShaderInstance_SetFloat(shader, "cloudGlow", 0.26)
    ShaderInstance_Link(shader)
    made = Model_Create()
    Model_AddShell(made, Mesh_SetU(Mesh_BoxSphere(24, true), 1), shader)
    puffs[gas] = made
  end
  return made
end

-- A cloud of gas (Core/Data/Ores): a big puff the size of the cloud,
-- which is the cloud's own object, and lesser ones laid over it and
-- hanging off it, each a little different, the same every time for the
-- same cloud. (A grey box of a cloud: nothing drifts in it.)
local PUFFS = 6
local function makeCloud(scene: Scene, object: SystemData.Object, at: vector, container: Object): Object
  local model = puff(object.variety)
  local roll = object.seed % 2147483647
  local function next(): number
    roll = (roll * 48271 + 11) % 2147483647
    return roll / 2147483647
  end
  local function one(size: number, offset: vector): Object
    local made = Object_Scenery({})
    Object_SetRenderable(made, model)
    container:AddInterior(made)
    made:SetScale(vector.create(size, size, size))
    made:SetPos(at + offset)
    return made
  end
  local middle = one(object.radius, vector.zero)
  local lobes: { Object } = {}
  local sizes: { number } = { object.radius }
  local offsets: { vector } = { vector.zero }
  for _ = 1, PUFFS do
    local angle, lift = next() * 2 * math.pi, (next() - 0.5) * 0.9
    local out = (0.35 + 0.45 * next()) * object.radius
    local size = (0.45 + 0.35 * next()) * object.radius
    local offset = vector.create(math.cos(angle) * out, lift * out, math.sin(angle) * out)
    table.insert(lobes, one(size, offset))
    table.insert(sizes, size)
    table.insert(offsets, offset)
  end
  scene.works[object.id] = lobes
  scene.offsets[object.id] = offsets
  scene.clouds[object.id] = { sizes = sizes, shown = 1 }
  return middle
end

-- A stargate: the design its end of the gate is built as (Core's
-- Galaxy.GateDesign), facing out of the system, the way its jump goes,
-- its mouth as wide as every gate's (Starbase.GATE_OPENING); what of it
-- stands still the gate's own object, and what turns its works.
-- Its event horizon across its mouth (Game/View/Horizon), a picture of
-- a sky of the family of the system it leads to.
export type GateTurning = { moving: Starbase.GateMoving, design: string, pace: number, at: number, horizon: Horizon.Made }
-- (how much faster than at rest a gate turns while a ship goes through it, by its design; and how many seconds
-- it takes to come up to that, and to settle again)
local GATE_BUSY: { [string]: number } = { dial = 8, gyre = 6, orrery = 6, bell = 1 }
local GATE_RISE = 1.2
local GATE_SETTLE = 4
local function makeGate(scene: Scene, game: Core.Game, object: SystemData.Object, at: vector, container: Object): Object
  local design = Galaxy.GateDesign(game.state.galaxy, scene.system, object.to)
  local made = Starbase.GateNamed(design)
  local size = Starbase.GATE_OPENING * object.radius / made.opening
  local out = vector.create(object.x, 0, object.z)
  local look = if vector.magnitude(out) > 1 then vector.normalize(out) else vector.create(0, 0, 1)
  local up = vector.create(0, 1, 0)
  local function add(model: Model): Object
    local thing = Object_Scenery({})
    Object_SetRenderable(thing, model)
    thing:SetScale(vector.create(size, size, size))
    thing:SetPos(at)
    container:AddInterior(thing)
    return thing
  end
  local still: Object? = nil
  if made.model then
    still = add(made.model :: Model)
    Object_SetAxes(still :: Object, look, up)
  end
  local moving = Starbase.GateMovers(made, add, look, up)
  local works = table.clone(moving.objects)
  local proxy = still or table.remove(works, 1) :: Object
  local horizon = Horizon.Make(Horizon.Family(game.state.galaxySeed * 7919 + object.to), Starbase.GATE_OPENING * object.radius, at,
    look, up)
  container:AddInterior(horizon.object)
  table.insert(works, horizon.object)
  proxy:SetName(object.name)
  local offsets: { vector } = { vector.zero }
  for _ in works do
    table.insert(offsets, vector.zero)
  end
  scene.works[object.id] = works
  scene.offsets[object.id] = offsets
  scene.gateTurns[object.id] = { moving = moving, design = design, pace = 1, at = scene.time, horizon = horizon }
  scene.statics[object.id] = object
  return proxy
end

-- Turn the stargates on, each faster while a ship is going into it or
-- has just come out of it (the owner's, 2026-11-21: the dial's inner
-- ring "should spin slowly at rest, then speed up as ships approach to
-- jump"; the gyre's gimbals spin up when a ship jumps, and settle; the
-- bell rolls on as it always does). And their horizons: the water moves,
-- a ring of ripples runs out from the middle as a ship goes through,
-- going or coming; a dial's opens from the middle as it spins up, and
-- shuts as it settles (the owner's), the others' are always open.
-- (when a ship coming out of a gate is through its horizon: it comes from
-- the gate's radius behind it, seconds into its coming out)
local THROUGH = 0.35
local function turnGates(scene: Scene, state: State.State, since: number)
  if next(scene.gateTurns) == nil then
    return
  end
  local busy: { [number]: boolean } = {}
  local rippled: { [number]: boolean } = {}
  -- (the gate the pilot is coming out of, while the passage is shown)
  local mine = state.balls[state.player.ship]
  local comingOut = if scene.passage and scene.passage.stage ~= "leave" and mine and mine.transit then mine.transit.arrival else 0
  for _, id in state.ballIds do
    local transit = state.balls[id].transit
    if transit then
      local t = (state.tick - transit.startTick) * Constants.TICK + since
      if transit.stage == "in" or transit.stage == "tunnel" then
        busy[transit.gate] = true
      elseif transit.stage == "out" and t < 2.5 then
        busy[transit.arrival] = true
      end
      local crossing = scene.crossings[id]
      if crossing == nil or crossing.start ~= transit.startTick then
        -- (a passage first seen past the gate it went in by: nothing to ripple there)
        crossing = { start = transit.startTick, went = transit.stage ~= "in", came = false }
        scene.crossings[id] = crossing
      end
      if not crossing.went and (transit.stage ~= "in" or t >= Space.TRANSIT_IN) then
        crossing.went = true
        rippled[transit.gate] = true
      end
      if transit.stage == "out" and not crossing.came and t >= THROUGH then
        crossing.came = true
        rippled[transit.arrival] = true
      end
    else
      scene.crossings[id] = nil
    end
  end
  for id, turning in scene.gateTurns do
    local dt = math.clamp(scene.time - turning.at, 0, 0.25)
    turning.at = scene.time
    local target = if busy[id] then GATE_BUSY[turning.design] or 1 else 1
    local tau = if target > turning.pace then GATE_RISE else GATE_SETTLE
    turning.pace += (target - turning.pace) * math.min(1, dt / tau)
    Starbase.AnimateGate(turning.moving, dt, turning.pace)
    if rippled[id] then
      Horizon.Ripple(turning.horizon, scene.time)
    end
    local open = 1
    if turning.design == "dial" then
      local busiest = GATE_BUSY.dial
      local x = math.clamp((turning.pace - 1.4) / (busiest - 2.4), 0, 1)
      open = x * x * (3 - 2 * x)
    end
    Horizon.Update(turning.horizon, scene.time, open, id == comingOut)
  end
end

-- A station: its tower, which is the station's own object, with its
-- modules and its field round it, at 'at'. The station's radius is the
-- radius of its field.
--
-- A pilot's own starbase is not always what it was: its modules come
-- and go, and its field with its fuel. What stands there is written
-- down ('standing'), so that it is put up again when that changes.
-- (And any station's batteries stand in space as things to shoot at
-- while the pilot is on its grid, drawn as those, and are part of what
-- is put up here when they are not: Core/Tactical/Batteries. Which of
-- the two it is, and which of them are down, is written down too.)
local function standing(game: Core.Game, id: number): string?
  local posted, down = Core.Query.Batteries(game, id)
  local parts = { if posted then "posted" else "laid", table.concat(down, ",") }
  local status = Core.Query.Starbase(game, id)
  if status then
    table.insert(parts, status.tower.id)
    -- (a citadel has no field: it is lit or dark)
    table.insert(parts, if status.field or (status.tower.citadel and status.lit) then "field" else "dark")
    for _, module in status.modules do
      table.insert(parts, module.type)
    end
  end
  return table.concat(parts, " ")
end

local function makeStation(scene: Scene, game: Core.Game, object: SystemData.Object, at: vector, container: Object): Object
  local makeup = Core.Query.Station(game, object.id)
  local status = Core.Query.Starbase(game, object.id)
  -- (a tower that has sealed itself keeps its field: Core/Tactical/Fields)
  -- (and a citadel, which has no field, is dark when it is not lit)
  local dark = status ~= nil and not (status.field or (status.tower.citadel == true and status.lit))
  local posted, down = Core.Query.Batteries(game, object.id)
  -- (a faction's citadel is in its people's colours)
  local owner = Core.Query.CitadelOwner(game, object.id)
  local layout = Starbase.Layout(object.variety, object.radius, object.seed, owner, makeup, dark, posted, down)
  local raised, moving = Starbase.Raise(layout, container, at, 1)
  -- (a citadel's guns, each where it is on it, for its shots to leave from: Core/Tactical/CitadelGuns)
  local guns: { CitadelGun } = {}
  for _, arm in layout.arms or {} :: { Starbase.Arm } do
    if not arm.twin then
      table.insert(guns, { type = arm.type, at = arm.at, pds = arm.pds })
    end
  end
  if #guns > 0 then
    scene.citadelGuns[object.id] = guns
  else
    scene.citadelGuns[object.id] = nil :: any
  end
  local special = layout.special
  if special then
    scene.citadelSpecial[object.id] = special
  else
    scene.citadelSpecial[object.id] = nil :: any
  end
  if layout.special == nil or layout.special.kind ~= "miner" then
    local rock = scene.citadelRocks[object.id]
    if rock then
      Object_Delete(rock.object)
      scene.citadelRocks[object.id] = nil
    end
  end
  if #moving > 0 then
    scene.moving[object.id] = moving
  end
  local tower = table.remove(raised, 1) :: Object
  tower:SetName(object.name)
  scene.works[object.id] = raised
  local offsets: { vector } = { tower:GetPos() - at }
  for _, work in raised do
    table.insert(offsets, work:GetPos() - at)
  end
  scene.offsets[object.id] = offsets
  scene.statics[object.id] = object
  local made = standing(game, object.id)
  if made then
    scene.standing[object.id] = made
  end
  return tower
end

local function clear(scene: Scene, objects: { [number]: Object })
  for _, object in objects do
    Object_Delete(object)
  end
  table.clear(objects)
end

-- Throw away everything and start a container for 'system'.
-- What making a system for the scene is, a piece at a time: the system
-- itself first (what there was thrown away), then each world and the
-- sun. (A passage through a stargate makes them one a frame behind the
-- black, so that the screen goes on being drawn: a world takes a tenth of
-- a second or so. Measured 2026-11-21.)
local function enterSteps(scene: Scene, game: Core.Game, system: number): { () -> () }
  local steps: { () -> () } = {}
  table.insert(steps, function()
    -- (the fitting screen's ship is of the system that is being left)
    dropShowcase(scene)
    for id in scene.arms do
      dropArms(scene, id)
    end
    for id in scene.wreckage do
      dropWreck(scene, id)
    end
    for id in scene.works do
      dropWorks(scene, id)
    end
    clear(scene, scene.proxies)
    clear(scene, scene.bubbles)
    table.clear(scene.headings)
    clear(scene, scene.celestials)
    table.clear(scene.worlds)
    if scene.container then
      Object_Delete(scene.container)
    end
    if scene.fx then
      Effects.Clear(scene.fx, true)
    end
    table.clear(scene.mining)
    table.clear(scene.statics)
    table.clear(scene.offsets)
    table.clear(scene.moving)
    table.clear(scene.clouds)
    scene.focus = nil
    scene.star = nil
    scene.key = ""
    scene.sites = ""
    scene.left = 0
    scene.system = system

    local container = Object_System(vector.create(0, 0, 0), game.state.galaxySeed * 7919 + system)
    -- (the camera goes into the new system now, while the old one is still
    -- there to be left: the engine moves it only when it next draws, and
    -- by then the old one may have been thrown away under it)
    container:AddInterior(scene.camera)
    scene.container = container
    scene.fx = Effects.New(container)
    local interior = container:GetInteriorObjects()
    while interior:HasMore() do
      if interior:Get():IsStar() then
        scene.star = interior:Get()
      end
      interior:Advance()
    end
  end)
  for _, object in Core.Query.Objects(game, system) do
    if object.kind == "planet" or object.kind == "moon" or object.kind == "sun" then
      table.insert(steps, function()
        local container = scene.container :: Object
        if object.kind == "planet" or object.kind == "moon" then
          local body: Object
          -- The kinds built from their own heights (Game/View/Planet); the
          -- rest are still the engine's old planet.
          local kind = Planet.KindOf(object.kind, object.variety)
          if kind then
            local world = Planet.New(kind, object.seed, if object.kind == "moon" then MOON_MAP else WORLD_MAP)
            -- (nobody lives in uncharted space: a world of a kind people
            -- live on has no cities' lights there, Core/Describe/Galaxy)
            local its = Planet.kinds[kind]
            if its and (its.settings.cityLights or 0) > 0 and game.state.galaxy.systems[system].uncharted then
              Planet.Set(world, "cityLights", 0)
            end
            scene.worlds[object.id] = world
            body = world.body
          else
            body = Item_PlanetType(object.seed):Instantiate()
          end
          body:SetName(object.name)
          container:AddInterior(body)
          scene.celestials[object.id] = body
        elseif object.kind == "sun" then
          -- The sun's disc and corona. Its light, and the flare drawn for
          -- that, are the engine's star, which takes the colour of the
          -- star's class.
          local body = Star.New(object.variety, object.seed)
          body:SetName(object.name)
          container:AddInterior(body)
          scene.celestials[object.id] = body
          if scene.star then
            Star_SetColor(scene.star, Star.Light(object.variety))
            scene.sunShade = 0
          end
        end
      end)
    end
  end
  return steps
end

local function enterSystem(scene: Scene, game: Core.Game, system: number)
  for _, step in enterSteps(scene, game, system) do
    step()
  end
end

-- What to draw for a shot whose weapon is not known, by its family.
local FALLBACK: { [string]: string } = { laser = "laser.pulse", projectile = "autocannon", hybrid = "blaster", missile = "launcher" }

-- Which of a ship's layers a shot lands on.
local function struck(ball: State.Ball): string
  local vitals = ball.vitals
  return if vitals.shield > 1 then "shield" elseif vitals.armor > 1 then "armor" else "hull"
end

-- Where a ball is 'since' seconds after the state's tick, and its velocity.
local function ballAt(ball: State.Ball, tick: number, since: number): (number, number, number, number, number, number)
  local transit = ball.transit
  if transit then
    return Space.TransitAt(transit, (tick - transit.startTick) * Constants.TICK + since)
  end
  local warp = ball.warp
  if warp and warp.stage == "warp" then
    local plan = warp.plan :: Motion.WarpPlan
    local d, speed = Motion.WarpAt(plan, (tick - warp.startTick) * Constants.TICK + since)
    return warp.fx + warp.ux * d, warp.fy + warp.uy * d, warp.fz + warp.uz * d,
      warp.ux * speed, warp.uy * speed, warp.uz * speed
  end
  return Motion.Step(ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz,
    ball.tvx, ball.tvy, ball.tvz, ball.tau, since)
end

-- Docked, the camera stands this many of the tower's radii off, and
-- looks this far to one side of it (as a share of that distance): the
-- station's screens fill the middle of the window, and the tower is to
-- stand in the clear beside them.
local DOCKED_ZOOM = 2.3
local DOCKED_ASIDE = 0.62

-- A jump takes this long to leave by, and this long to come out of
-- (seconds, of the clock on the wall: time run faster does not hurry it).
-- (The leaving is as long as a gate's sound takes to come to its clap:
-- resource/sound/made/gate/jump.)
local JUMP_OUT = 1.12
local JUMP_IN = 1.5
local JUMP_LIGHT = vector.create(0.72, 0.90, 1.0)

-- What the modules of the expansion of 2026-11-16 look like at work
-- (made 2026-11-17, at the owner's asking for the effects they need,
-- "I leave it to you to decide what looks good": every look mine).
-- A smartbomb is a sphere of its damage's colour as wide as it reaches,
-- with a flash at its heart; a micro jump a flash of jump light where
-- the ship comes out, and a ring; an interdiction bubble a ring as wide
-- as its field coming up; a capacitor charge a small warm flash; a
-- jammed ship crackles pale blue, and a drained one flickers magenta.
local SMARTBOMB_COLOR: { [string]: vector } = {
  em = vector.create(0.45, 0.70, 1.0), thermal = vector.create(1.0, 0.50, 0.20),
  kinetic = vector.create(0.88, 0.88, 0.82), explosive = vector.create(1.0, 0.76, 0.30),
}
local BUBBLE_COLOR = vector.create(0.70, 0.40, 1.0)
local JAMMED_COLOR = vector.create(0.65, 0.88, 1.0)
local DRAINED_COLOR = vector.create(0.95, 0.35, 0.85)
local CHARGE_COLOR = vector.create(1.0, 0.92, 0.55)
local MODULE_FX: { [string]: boolean } = { Smartbombed = true, MicroJumped = true, BubbleDropped = true, CapacitorBoosted = true,
  Jammed = true, Drained = true }

local function moduleFx(scene: Scene, fx: Effects.Fx, state: any, event: any)
  local id = if event.kind == "Drained" then event.target else event.ball
  local ball = state.balls[id]
  local at: vector? = scene.screen[id]
  if ball == nil or at == nil then
    return
  end
  local now = scene.time
  if event.kind == "Smartbombed" then
    local item = state.items[event.item]
    local module = if item then Modules.byId[item.type] else nil
    local reach = if module and module.smartbomb then module.smartbomb.range else 5000
    local color = SMARTBOMB_COLOR.em
    for name, each in SMARTBOMB_COLOR do
      if item and string.find(item.type, name, 1, true) then
        color = each
      end
    end
    -- (as wide as it reaches would be past the edges of the screen at
    -- any zoom a pilot flies at: a pulse some tens of the ship across,
    -- and never past its reach)
    local wide = math.min(reach, 30 * ball.radius)
    Effects.Flash(fx, id, vector.create(0, 0, 0), color, wide, 3, 1.1, now)
    Effects.Flash(fx, id, vector.create(0, 0, 0), color, wide * 0.45, 0, 0.6, now)
    Effects.Flash(fx, id, vector.create(0, 0, 0), color, 4 * ball.radius, 0, 0.5, now)
  elseif event.kind == "MicroJumped" then
    Effects.Flash(fx, id, vector.create(0, 0, 0), JUMP_LIGHT, 3 * ball.radius, 0, 0.6, now)
    Effects.Flash(fx, id, vector.create(0, 0, 0), JUMP_LIGHT, 8 * ball.radius, 1, 0.9, now)
  elseif event.kind == "BubbleDropped" then
    -- (its field is drawn as the shell it is: Game/View/Starbase.Bubble.
    -- This is the probe going off)
    Effects.Flash(fx, id, vector.create(0, 0, 0), BUBBLE_COLOR, math.min(event.radius or 5000, 30 * ball.radius), 3, 1.6, now)
    Effects.Flash(fx, id, vector.create(0, 0, 0), BUBBLE_COLOR, 3 * ball.radius, 0, 0.6, now)
  elseif event.kind == "CapacitorBoosted" then
    Effects.Flash(fx, id, vector.create(0, 0, 0), CHARGE_COLOR, 1.6 * ball.radius, 0, 0.35, now)
  elseif event.kind == "Jammed" then
    Effects.Flash(fx, id, vector.create(0, 0, 0), JAMMED_COLOR, 1.8 * ball.radius, 1, 0.5, now)
  elseif event.kind == "Drained" then
    Effects.Flash(fx, id, vector.create(0, 0, 0), DRAINED_COLOR, 1.4 * ball.radius, 0, 0.4, now)
  end
end

-- A module coming on that shows round its ship: a command burst a ring
-- going out over the fleet; a siege, triage or industrial core a slow
-- ring and a glow as it locks down; a jump beacon a column of jump light.
local STARTED: { { prefix: string, color: vector, ring: number, size: number, life: number } } = {
  { prefix = "burst.", color = vector.create(0.55, 0.85, 1.0), ring = 3, size = 40, life = 1.4 },
  { prefix = "siege.", color = vector.create(1.0, 0.70, 0.30), ring = 1, size = 4, life = 1.8 },
  { prefix = "triage.", color = vector.create(0.50, 1.0, 0.60), ring = 1, size = 4, life = 1.8 },
  { prefix = "industrial.core", color = vector.create(1.0, 0.85, 0.40), ring = 1, size = 4, life = 1.8 },
  { prefix = "beacon.jump", color = JUMP_LIGHT, ring = 0, size = 6, life = 2.5 },
}

local function startedFx(scene: Scene, fx: Effects.Fx, state: any, event: any)
  local item = state.items[event.item]
  local ball = state.balls[event.ball]
  local at: vector? = scene.screen[event.ball]
  if item == nil or ball == nil or at == nil then
    return
  end
  for _, one in STARTED do
    if string.sub(item.type, 1, #one.prefix) == one.prefix then
      Effects.Flash(fx, event.ball, vector.create(0, 0, 0), one.color, one.size * ball.radius, one.ring, one.life, scene.time)
      Effects.Flash(fx, event.ball, vector.create(0, 0, 0), one.color, 1.5 * ball.radius, 0, one.life * 0.6, scene.time)
      return
    end
  end
end

-- A gate lights when a ship goes through it, either way: a flash at it
-- as big as the gate, and a ring thrown out from it.
-- ('scale': smaller, for the pilot's own passage, with the camera right at the gate)
local function lightGate(scene: Scene, fx: Effects.Fx, id: number, life: number, scale: number?)
  local at: vector? = scene.screen[id]
  local gate = scene.statics[id]
  if at and gate and gate.kind == "gate" then
    local size = scale or 1
    Effects.Burst(fx, at, JUMP_LIGHT, 2.2 * gate.radius * size, 0, life, scene.time)
    Effects.Burst(fx, at, JUMP_LIGHT, 7 * gate.radius * size, 1, life * 1.4, scene.time)
    scene.gates += 1
  end
end

-- The gate of the scene nearest a place in it, within 'reach' (0: none).
local function gateNear(scene: Scene, at: vector, reach: number): number
  local found, least = 0, reach
  for id, object in scene.statics do
    local where: vector? = scene.screen[id]
    if object.kind == "gate" and where then
      local far = vector.magnitude(where - at)
      if far < least or (far == least and id < found) then
        found, least = id, far
      end
    end
  end
  return found
end

-- Bring the engine's objects into line with the Core for this frame.
-- A passage through a stargate, as the pilot sees it (Scene's 'passage').
-- How long the ship is seen going on into the black after it is through,
-- how hard it is thrown on (m/s/s), and how long the black takes to clear
-- on the far side (seconds of the clock on the wall).
local LEAVE = 1.8
local LEAVE_PUSH = 2600
local CLEAR = 0.7
local BLACK = vector.create(0, 0, 0)
local WHITE = vector.create(0.80, 0.92, 1.0)

-- The tube of black behind a gate's opening, the way through it: a unit
-- tube along +z from its mouth, 24 long and shut at its end, seen from
-- within (Plates.Revolve's profile run up its wall and in across its end,
-- whose faces look in). Unlit black: the engine's sky goes behind it.
local tubeModel: Model? = nil
local function tubeOf(): Model
  if tubeModel == nil then
    local b = Plates.New(7.3, 0.11)
    local profile: { vector } = {}
    for i = 0, 12 do
      table.insert(profile, vector.create(1, i * 2, 0))
    end
    for i = 1, 8 do
      table.insert(profile, vector.create(math.max(1e-4, 1 - i / 8), 24, 0))
    end
    Plates.Revolve(b, Plates.GLOW, profile, 64)
    local black = { 0, 0, 0 }
    tubeModel = (Plates.Finish(b, { plating = black, patch = black, frame = black, glow = black, trim = black, wear = 0, rust = 0,
      sheets = 1 }, nil))
  end
  return tubeModel :: Model
end

-- Put a gate's tube in the scene: its mouth at 'at' (the middle of the
-- gate whose 'radius' it is), running off along 'way'.
local function makeTube(scene: Scene, at: vector, way: vector, radius: number): Object
  -- (a little narrower than the gate's mouth, every design's the same:
  -- makeGate; so as not to lie in the faces of the ring round it)
  local opening = 0.97 * Starbase.GATE_OPENING * radius
  local tube = Object_Scenery({})
  Object_SetRenderable(tube, tubeOf())
  tube:SetScale(vector.create(opening, opening, opening))
  tube:SetPos(at)
  local up = if math.abs(way.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0)
  Object_SetAxes(tube, way, vector.normalize(up - way * vector.dot(up, way)))
  local container = scene.container :: Object
  container:AddInterior(tube)
  return tube
end

local function dropTube(passage: Passage)
  if passage.tube then
    Object_Delete(passage.tube)
    passage.tube = nil
  end
end

-- (the tick the passage now waiting beyond was told the far side is ready at, once)
local emergeAsked = -1

-- The pilot's passage through a stargate (or a wormhole, or a jump
-- bridge: a sphere, and no tube), shown: true while the rest of
-- Sync is to wait (the system left still standing, or the next one being
-- made behind the black).
local function sailThrough(scene: Scene, session: Session.Session, me: State.Ball?, since: number): boolean
  local game = session.game
  local state = game.state
  local player = Core.Query.Player(game)
  local transit = if me then me.transit else nil
  local passage = scene.passage

  -- Through the gate: the Core has the ship beyond already, and the
  -- system left stands while the ship goes on into the black.
  if me and transit and transit.stage ~= "in" and passage == nil and player.system ~= scene.system and scene.system ~= 0
    and scene.fx and transit.gate ~= 0 then
    local gate = vector.create(transit.gx - scene.ox, transit.gy - scene.oy, transit.gz - scene.oz)
    local way = vector.normalize(vector.create(transit.gx - transit.ax, transit.gy - transit.ay, transit.gz - transit.az))
    local body = Core.Query.Body(game, transit.gate) :: any
    local radius = if body then body.radius else 1500
    local sphere = Space.Sphere(state, transit.gate) or 0
    local next: Passage = { stage = "leave", since = scene.time, at = gate, way = way, speed = transit.speed, tube = nil, steps = nil,
      settle = 0, asked = false, eye = scene.eyeAt, sphere = sphere }
    if sphere <= 0 then
      next.tube = makeTube(scene, gate, way, radius)
    end
    passage = next
    scene.passage = next
    scene.veilColor = BLACK
    -- (the surface broken: the horizon ripples out from the middle, which
    -- turnGates sees to. No light of the gate's: with the camera right
    -- behind the ship, even a small one whited the screen out. It counts
    -- as lit all the same.)
    scene.gates += 1
  end

  if passage == nil then
    -- Flying in, or come out (a game loaded with the ship between gates):
    -- the camera behind it, and the Core told the far side is ready.
    if me and transit then
      local x, y, z, vx, vy, vz = ballAt(me, state.tick, since)
      local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
      scene.chase = if speed > 1e-3 then vector.create(vx / speed, vy / speed, vz / speed) else scene.chase
      -- (going in, the camera is behind the ship on the line to the gate's
      -- middle, so the gate is ahead the whole way, whichever way the ship
      -- swings round to it; the last few hundred metres, along its way)
      local toward = vector.create(transit.gx - x, transit.gy - y, transit.gz - z)
      if transit.stage == "in" and vector.magnitude(toward) > 400 then
        scene.chase = vector.normalize(toward)
      end
      if transit.stage == "tunnel" and player.system == scene.system and emergeAsked ~= transit.startTick then
        emergeAsked = transit.startTick
        Core.Submit(game, { kind = "Emerge", actor = player.ship })
      end
    else
      scene.chase = nil
    end
    return false
  end

  if passage.stage == "leave" then
    -- On into the black, faster and faster, the camera falling behind.
    local t = scene.time - passage.since
    local d = passage.speed * t + 0.5 * LEAVE_PUSH * t * t
    if passage.sphere > 0 then
      -- (in a sphere: on, slowing, to stop halfway out from its middle,
      -- and never out of the far side of it)
      local stop = 0.5 * passage.sphere
      d = stop * (1 - math.exp(-passage.speed * t / stop))
    end
    local proxy: Object? = scene.proxies[player.ship]
    if proxy then
      proxy:SetPos(passage.at + passage.way * d)
    end
    scene.chase = passage.way
    local share = math.min(1, t / LEAVE)
    scene.rush = share * share
    local dark = math.clamp((share - 0.55) / 0.45, 0, 1)
    scene.veil = dark * dark * (3 - 2 * dark)
    if scene.fx then
      Effects.Update(scene.fx, scene.time, scene.screen)
    end
    -- (and the gate left behind turns on, its horizon rippling)
    turnGates(scene, state, since)
    if t < LEAVE then
      return true
    end
    -- All black: the next system is made, a piece a frame.
    dropTube(passage)
    passage.stage, passage.since = "load", scene.time
    passage.steps = enterSteps(scene, game, player.system)
    scene.veil, scene.rush = 1, 0
    return true
  end

  if passage.stage == "load" then
    scene.veil, scene.rush = 1, 0
    local steps = passage.steps
    if steps and #steps > 0 then
      local step = table.remove(steps, 1) :: () -> ()
      step()
      return true
    end
    -- Made: the rest of Sync puts in what is on the grid the ship is
    -- waiting on, and the sky is made the first time it is drawn. A few
    -- frames on, the tube behind the far gate, and the Core is told.
    passage.settle += 1
    if transit and passage.settle == 2 then
      local far = Core.Query.Body(game, transit.arrival) :: any
      if far then
        passage.at = vector.create(far.x - scene.ox, far.y - scene.oy, far.z - scene.oz)
        passage.way = vector.create(transit.ux, transit.uy, transit.uz)
        -- (out of a sphere, nothing behind it: its own black is the way through)
        passage.sphere = Space.Sphere(state, transit.arrival) or 0
        if passage.sphere <= 0 then
          passage.tube = makeTube(scene, passage.at, -passage.way, far.radius)
        end
      end
    end
    if transit and passage.settle >= 4 and not passage.asked and transit.stage == "tunnel" then
      passage.asked = true
      Core.Submit(game, { kind = "Emerge", actor = player.ship })
    end
    scene.chase = vector.create(transit and transit.ux or 0, transit and transit.uy or 0, transit and transit.uz or 1)
    if transit == nil or transit.stage == "out" then
      -- (and no light from the far gate: from inside it, it fills the opening)
      passage.stage, passage.since = "out", scene.time
      scene.lit = true
    end
    return false
  end

  -- Out of the far gate: the black clears, and once the camera is through
  -- the gate too, the tube behind it goes.
  local t = scene.time - passage.since
  local clear = math.max(0, 1 - t / CLEAR)
  scene.veil, scene.rush = clear * clear, 0
  scene.chase = passage.way
  if passage.tube and vector.dot(scene.eyeAt - passage.at, passage.way) > 0 then
    dropTube(passage)
  end
  if transit == nil then
    dropTube(passage)
    scene.passage, scene.chase = nil, nil
    scene.veil, scene.veilColor = 0, WHITE
  end
  return false
end

-- How much of the sun (at 'sun', in the system) a lightless sphere hides
-- from the eye, 0 to 1: a wormhole's, or the one the pilot is passing
-- through. In front of it, where the sphere's middle is lightless
-- (wormhole.jsl's kHorizon of it); or round the eye, by how far the line
-- to the sun runs through it (as wormhole.jsl darkens it, seen from in it).
local HOLE_DARK = 0.62
local function sunInHole(scene: Scene, sun: vector): number
  local eye = vector.create(scene.eyeX, scene.eyeY, scene.eyeZ)
  local way = sun - eye
  if vector.magnitude(way) < 1 then
    return 0
  end
  way = vector.normalize(way)
  local function hides(middle: vector, radius: number): number
    local to = middle - eye
    local along = vector.dot(to, way)
    local far = vector.magnitude(to)
    if far < radius then
      -- (from within: how far on the line runs before it is out of it)
      local off = far * far - along * along
      local through = along + math.sqrt(math.max(0, radius * radius - off))
      return 1 - math.exp(-4 * through / radius)
    end
    if along <= 0 then
      return 0
    end
    local b = vector.magnitude(to - way * along) / radius
    return 1 - math.clamp((b - (HOLE_DARK - 0.06)) / 0.08, 0, 1)
  end
  local most = 0
  for _, static in scene.statics do
    if static.kind == "wormhole" then
      most = math.max(most, hides(vector.create(static.x, static.y, static.z), static.radius))
    end
  end
  local passage = scene.passage
  if passage and passage.sphere > 0 then
    most = math.max(most, hides(passage.at + vector.create(scene.ox, scene.oy, scene.oz), passage.sphere))
  end
  return most
end

function Scene.Sync(scene: Scene, session: Session.Session)
  local game = session.game
  local state = game.state
  local since = Clock.SinceTick(session.clock)
  local player = Core.Query.Player(game)
  -- (another game, from a save or begun anew: nothing made for the last
  -- one stands, though it be the same system by number)
  if session.epoch ~= scene.epoch then
    scene.epoch = session.epoch
    scene.system = 0
    scene.key = ""
    scene.docked = false
    scene.jump, scene.arrived, scene.veil, scene.rush = -1, -1, 0, 0
    -- (and no passage through a gate is being shown: one the ship is in
    -- the middle of is taken up where the Core has it)
    if scene.passage then
      dropTube(scene.passage :: Passage)
    end
    scene.passage, scene.chase, scene.veilColor = nil, nil, WHITE
  end
  -- (the fitting screen's ship is in the scene only while that screen
  -- shows it: left there, it would be wherever the scene's origin next
  -- put it, for anybody to fly past)
  for name, show in scene.showcases do
    if scene.time - show.drawn > 1 then
      dropShowcase(scene, name)
    end
  end
  -- (through a stargate, the pilot's own passage: sailThrough)
  if sailThrough(scene, session, state.balls[player.ship], since) then
    return
  end
  if player.system ~= scene.system and scene.passage == nil then
    -- Flown through a gate (and not put somewhere else by a save, a new
    -- game or a new clone): the system left stands a moment longer,
    -- with a flash where the ship was and the view rushing into it.
    -- (Through a wormhole or by a drive, now: a stargate is a passage.)
    scene.veilColor = WHITE
    local through = scene.system ~= 0 and state.balls[player.ship] ~= nil and scene.fx ~= nil
    if through and scene.jump < 0 then
      scene.jump = scene.time
      local at: vector? = scene.screen[player.ship]
      local radius = state.balls[player.ship].radius
      if at and scene.fx then
        Effects.Burst(scene.fx, at, JUMP_LIGHT, 60 * radius, 0, JUMP_OUT * 1.2, scene.time)
        Effects.Burst(scene.fx, at, JUMP_LIGHT, 220 * radius, 1, JUMP_OUT * 1.2, scene.time)
        -- (and the gate it went through lights)
        lightGate(scene, scene.fx, gateNear(scene, at, 50000), JUMP_OUT)
      end
    end
    if through and scene.time - scene.jump < JUMP_OUT then
      local t = (scene.time - scene.jump) / JUMP_OUT
      scene.veil, scene.rush = t * t, t * t
      if scene.fx then
        Effects.Update(scene.fx, scene.time, scene.screen)
      end
      return
    end
    -- (the next system is made behind the white)
    scene.arrived = if through then scene.time else -1
    scene.lit = not through
    scene.jump = -1
    enterSystem(scene, game, player.system)
  end
  if scene.arrived >= 0 then
    -- Out of it on the far side: the white clears and the view closes in.
    local t = (scene.time - scene.arrived) / JUMP_IN
    if t >= 1 then
      scene.arrived, scene.veil, scene.rush = -1, 0, 0
    else
      scene.veil, scene.rush = (1 - t) ^ 2, (1 - t) ^ 3
    end
  elseif scene.jump < 0 then
    scene.veil, scene.rush = 0, 0
  end
  local container = scene.container :: Object
  local objects = Core.Query.Objects(game, player.system)
  local me = state.balls[player.ship]

  -- Where the player is, and which grid to show.
  local grid = 0
  -- (docked in a colony ship: what it lies by, for the camera to be on
  -- until the ship itself is there to be on)
  local beside = 0
  scene.warp = 0
  if me then
    scene.eyeX, scene.eyeY, scene.eyeZ = ballAt(me, state.tick, since)
    grid = me.grid
    local warp = me.warp
    if warp and warp.stage == "warp" then
      -- How deep into the warp, for the camera: eased in over the first
      -- second and a half and out over the last two.
      local plan = warp.plan :: Motion.WarpPlan
      local elapsed = (state.tick - warp.startTick) * Constants.TICK + since
      local travelled = Motion.WarpAt(plan, elapsed)
      scene.warp = math.clamp(math.min(elapsed / 1.5, (plan.total - elapsed) / 2), 0, 1)
      scene.warpLeft = plan.distance - travelled
      scene.warpSeconds = math.max(0, plan.total - elapsed)
    end
  else
    -- (a colony ship of the nomads is a station of no system's list: it
    -- is where its ship is, on whatever grid that is)
    local roaming = Core.Query.Carrier(game, player.docked)
    local station = if roaming then Core.Query.Body(game, player.docked) :: any else objects[player.docked % Constants.STRUCTURE_ID_SPAN]
    scene.eyeX, scene.eyeY, scene.eyeZ = station.x, station.y, station.z
    grid = if roaming then station.site else station.id
    beside = if roaming then station.parent else 0
    if not scene.docked then
      -- Just docked (or the game has begun docked): bring the camera in
      -- on the tower, from the side the sun is on and a little round
      -- from it, so that it is seen lit and in the round.
      scene.docked = true
      scene.zoomAway = scene.zoomTarget
      scene.zoom, scene.zoomTarget = DOCKED_ZOOM, DOCKED_ZOOM
      scene.pitch = 1.32
      for _, object in objects do
        if object.kind == "sun" then
          scene.yaw = math.atan2(object.z - station.z, object.x - station.x) + 0.7
        end
      end
    end
  end
  if me and scene.docked then
    scene.docked = false
    scene.zoom, scene.zoomTarget = scene.zoomAway, scene.zoomAway
  end

  -- The origin: the grid's anchor, or the ship itself in warp.
  local key = tostring(grid)
  if grid == 0 then
    scene.ox, scene.oy, scene.oz = scene.eyeX, scene.eyeY, scene.eyeZ
  elseif key ~= scene.key then
    local open = state.grids[grid]
    if open then
      scene.ox, scene.oy, scene.oz = open.x, open.y, open.z
    else
      local anchor = objects[grid % Constants.STRUCTURE_ID_SPAN]
      scene.ox, scene.oy, scene.oz = anchor.x, anchor.y, anchor.z
    end
  end

  -- Whose bodies are in the scene: the grid the ship is on. In warp, the
  -- grid it has left and the one it is coming to (the one its landing
  -- place belongs to, as the Core will find: Space.AssignGrid), each
  -- for as long as it is near enough to be drawn.
  local inScene: { [number]: boolean } = {}
  local sites = ""
  if grid ~= 0 then
    inScene[grid] = true
    sites = `{grid} `
    scene.left = grid
  elseif me and me.warp and me.warp.stage == "warp" then
    local warp = me.warp
    local coming, nearest = 0, Constants.GRID_RADIUS
    for _, object in objects do
      if object.site == object.id then
        local d = math.sqrt((object.x - warp.tx) ^ 2 + (object.y - warp.ty) ^ 2 + (object.z - warp.tz) ^ 2)
        if d < nearest then
          coming, nearest = object.id, d
        end
      end
    end
    if coming == 0 then
      for _, id in state.gridIds do
        local open = state.grids[id]
        if open.system == player.system then
          local d = math.sqrt((open.x - warp.tx) ^ 2 + (open.y - warp.ty) ^ 2 + (open.z - warp.tz) ^ 2)
          if d < nearest then
            coming, nearest = id, d
          end
        end
      end
    end
    for _, id in { scene.left, coming } do
      if id ~= 0 and not inScene[id] then
        local open = state.grids[id]
        local anchor: { x: number, y: number, z: number }? = open
        if anchor == nil and id < Constants.FIRST_DYNAMIC_ID then
          anchor = objects[id % Constants.STRUCTURE_ID_SPAN]
        end
        if anchor and (anchor.x - scene.eyeX) ^ 2 + (anchor.y - scene.eyeY) ^ 2 + (anchor.z - scene.eyeZ) ^ 2 < NEAR ^ 2 then
          inScene[id] = true
          sites ..= `{id} `
        end
      end
    end
  end

  -- Another grid, or another origin: every trail has had the origin
  -- moved under it.
  local moved = key ~= scene.key
  if moved then
    scene.key = key
    if scene.fx then
      Effects.Still(scene.fx)
    end
  end
  -- Other bodies than were there: take away what is no longer wanted,
  -- and make what is. Ships are kept, since a hull is costly to make
  -- and the player's comes along.
  if sites ~= scene.sites then
    scene.sites = sites
    local gone: { number } = {}
    for id in scene.proxies do
      if state.balls[id] == nil then
        local static = scene.statics[id]
        local wreck = state.wrecks[id]
        local site = if static then static.site elseif wreck then wreck.grid else 0
        if not inScene[site] then
          table.insert(gone, id)
        end
      end
    end
    for _, id in gone do
      dropArms(scene, id)
      dropWreck(scene, id)
      dropWorks(scene, id)
      Object_Delete(scene.proxies[id])
      scene.proxies[id] = nil
      scene.statics[id] = nil
    end
    for _, object in objects do
      if inScene[object.site] and not scene.proxies[object.id] then
        if object.kind == "station" then
          scene.proxies[object.id] = makeStation(scene, game, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
        elseif object.kind == "asteroid" and Ores.gasById[object.variety] then
          scene.proxies[object.id] = makeCloud(scene, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
          scene.statics[object.id] = object
        elseif object.kind == "wormhole" and (Core.Query.Wormhole(game, object.id) == nil
          or (Core.Query.Wormhole(game, object.id) :: Core.WormholeInfo).held) then
          -- (a wormhole that has closed: the place is kept, and nothing is
          -- there; one a wormhole station holds open at its heart is the
          -- sphere drawn there, Citadel)
        elseif object.kind == "gate" and object.variety == "" and object.to ~= 0 then
          scene.proxies[object.id] = makeGate(scene, game, object,
            vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
        elseif object.kind ~= "belt" then
          local made = makeStatic(object)
          container:AddInterior(made)
          place(made, vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz))
          scene.proxies[object.id] = made
          scene.statics[object.id] = object
        end
      end
    end
    moved = true
  end
  -- In warp the origin is the ship, and goes with it: everything that
  -- stands still is somewhere else each frame. (And once more when the
  -- origin is a grid's again.)
  if moved or grid == 0 then
    for id, object in scene.statics do
      local at = vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz)
      local proxy = scene.proxies[id]
      local offsets = scene.offsets[id]
      if offsets then
        proxy:SetPos(at + offsets[1])
        for index, work in scene.works[id] do
          work:SetPos(at + offsets[index + 1])
        end
      else
        place(proxy, at)
      end
    end
  end

  turnGates(scene, state, since)

  -- What moves of a station's tower: rings turn, dishes sweep, panels
  -- face the sun, hazard lamps blink (Starbase.Animate).
  for id, moving in scene.moving do
    local proxy: Object? = scene.proxies[id]
    local star = scene.star
    if proxy then
      local sun = if star then star:GetPos() - proxy:GetPos() else vector.create(0, 1, 0)
      Starbase.Animate(moving, scene.time, if vector.magnitude(sun) > 1 then vector.normalize(sun) else vector.create(0, 1, 0),
        scene.eyeAt)
    end
  end

  -- A cloud is as big as what is left in it: it thins as it is drawn
  -- off, and with nothing left there is nothing to see.
  for id, cloud in scene.clouds do
    local proxy: Object? = scene.proxies[id]
    local lobes = scene.works[id]
    if not proxy or lobes == nil then
      scene.clouds[id] = nil
    else
      local left = Core.Query.Left(game, id)
      if left ~= cloud.shown then
        cloud.shown = left
        local share = if left <= 0 then 0.001 else 0.4 + 0.6 * left
        proxy:SetScale(vector.create(cloud.sizes[1] * share, cloud.sizes[1] * share, cloud.sizes[1] * share))
        for index, lobe in lobes do
          local size = cloud.sizes[index + 1] * share
          lobe:SetScale(vector.create(size, size, size))
        end
      end
    end
  end

  -- A wormhole that has closed is gone from where it was.
  for id, static in scene.statics do
    if static.kind == "wormhole" and Core.Query.Wormhole(game, id) == nil then
      local proxy: Object? = scene.proxies[id]
      if proxy then
        Object_Delete(proxy)
      end
      scene.proxies[id] = nil
      scene.statics[id] = nil
    end
  end

  -- A starbase that is not what it was when it was put up here.
  local changed: { number } = {}
  for id, was in scene.standing do
    if standing(game, id) ~= was then
      table.insert(changed, id)
    end
  end
  for _, id in changed do
    local object = objects[id % Constants.STRUCTURE_ID_SPAN]
    local old = scene.proxies[id]
    dropWorks(scene, id)
    if old then
      Object_Delete(old)
    end
    scene.proxies[id] = makeStation(scene, game, object,
      vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz), container)
  end

  table.clear(scene.screen)
  if next(inScene) then
    for _, object in objects do
      if inScene[object.site] then
        scene.screen[object.id] = vector.create(object.x - scene.ox, object.y - scene.oy, object.z - scene.oz)
      end
    end
  end

  -- Ships on the grid (in warp, the player's own, and those where it
  -- has been and is going while they are near).
  scene.passing = 0
  -- (how much of the game's time has gone by since their hulls were last
  -- turned: none in a game that is paused, and no more than a moment's
  -- worth after a jump or a load)
  local gameNow = (state.tick + since) * Constants.TICK
  local turnedFor = math.clamp(gameNow - scene.turned, 0, 2)
  scene.turned = gameNow
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local shown = ball.system == player.system and (id == player.ship or inScene[ball.grid] == true)
    -- (a starbase's core, what stands for it under fire, is not drawn: the station is, and the core is where it is
    -- drawn, citadelCores. Drawn as a ship it was an old-style hull of the station's size, in the middle of it.)
    if state.ships[id] and (state.ships[id].owner == "starbase" or state.ships[id].stands ~= nil) then
      shown = false
    end
    -- (between gates a ship is nowhere to be seen; nor, coming out, while
    -- it is still behind the far gate's opening)
    local transit = ball.transit
    if transit and id ~= player.ship and (transit.stage == "tunnel"
      or (transit.stage == "out" and (state.tick - transit.startTick) * Constants.TICK + since < 0.35)) then
      shown = false
    end
    -- (a cloaked ship is seen by nobody but its own pilot)
    local cloaked = Core.Query.Cloaked(game, id)
    if cloaked and id ~= player.ship then
      shown = false
    end
    -- (and those in warp that are near, going or coming; not while the
    -- pilot's own ship is in warp, when the scene goes with it. A ship
    -- that has gone unseen stays so.)
    if not shown and grid ~= 0 and ball.system == player.system and ball.warp and ball.warp.stage == "warp"
      and not cloaked then
      local x, y, z = ballAt(ball, state.tick, since)
      if (x - scene.eyeX) ^ 2 + (y - scene.eyeY) ^ 2 + (z - scene.eyeZ) ^ 2 < PASSING ^ 2 then
        shown = true
        scene.passing += 1
      end
    end
    local existing: Object? = scene.proxies[id]
    if shown then
      local proxy: Object
      if existing then
        proxy = existing
      else
        -- (a pirate's is in the pirates' paint, and a veteran's or a captain's in their own)
        local theirs = state.ships[id].owner == "pirates"
        -- (and one nobody has painted is in its faction's livery, or its police's: Paints.Dress)
        local paint, figure = state.ships[id].paint, state.ships[id].design
        -- (a ship, that is: a battery or a store that stands where it was put is as it was built)
        if paint == nil and Scene.LIVERIES and not theirs and string.sub(state.ships[id].type, 1, 6) ~= "works." then
          local record = state.traffic[id]
          paint, figure = Paints.Dress(state.ships[id].owner, record ~= nil and record.kind == "police")
        end
        proxy = makeShip(state.ships[id].type, ball.radius, theirs, if theirs then Pirates.Rank(state.ships[id].name) else nil,
          paint, figure)
        proxy:SetName(ball.name)
        container:AddInterior(proxy)
        scene.proxies[id] = proxy
        scene.ghosts[id] = nil
      end
      -- (to its own pilot a cloaked hull is the light bending round it:
      -- the same shape, drawn another way, with nothing mounted on it)
      local made = designed[proxy]
      if made and cloaked ~= (scene.ghosts[id] == true) then
        Object_SetRenderable(proxy, if cloaked then Hull.Ghost(made) else made.model)
        scene.ghosts[id] = if cloaked then true else nil :: any
        dropArms(scene, id)
      end
      local x, y, z, vx, vy, vz = ballAt(ball, state.tick, since)
      local at = vector.create(x - scene.ox, y - scene.oy, z - scene.oz)
      proxy:SetPos(at)
      local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
      local beyond = ball.transit ~= nil and ball.transit.stage ~= "in"
      if beyond then
        -- (beyond a gate, waiting or coming out, it faces the way out: the
        -- gate lines it up, and it does not swing round from the way it
        -- went in, 2026-11-22)
        local passing = ball.transit :: State.Transit
        local heading = vector.create(passing.ux, passing.uy, passing.uz)
        scene.headings[id] = heading
        if designed[proxy] then
          Object_SetAxes(proxy, heading, if math.abs(heading.y) < 0.98 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
        else
          proxy:SetLook(heading)
        end
      elseif speed > 1 then
        -- The hull comes round to the way the ship is going, and does not
        -- snap to it: a ship at rest that is sent somewhere is moving
        -- that way at once (it has no way on to turn from), and it was
        -- drawn pointing there at once. (The owner's, 2026-11-15.) It
        -- turns as fast as it answers its helm: half a turn in about
        -- the time it takes to align, a big hull slowly.
        local wanted = vector.create(vx / speed, vy / speed, vz / speed)
        local had: vector? = scene.headings[id]
        local heading: vector = had or wanted
        if had then
          local angle = math.acos(math.clamp(vector.dot(heading, wanted), -1, 1))
          -- (through a gate it is lined up at once: it is the gate that takes it)
          local step = turnedFor * math.pi / (if ball.transit then 0.3 else math.clamp(ball.tau * 1.5, 1, 14))
          if angle <= step or angle < 1e-4 then
            heading = wanted
          else
            local axis = vector.cross(heading, wanted)
            if vector.magnitude(axis) < 1e-5 then
              -- (straight about: round by its own upright, or by its side if it is on end)
              axis = vector.cross(heading, if math.abs(heading.y) < 0.98 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
            end
            heading = vector.normalize(about(heading, vector.normalize(axis), step))
          end
        end
        scene.headings[id] = heading
        if designed[proxy] then
          Object_SetAxes(proxy, heading, if math.abs(heading.y) < 0.98 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
        else
          proxy:SetLook(heading)
        end
      elseif scene.poses[id] and designed[proxy] then
        -- (stood there for a picture: it points the way it was stood)
        local heading = scene.poses[id]
        scene.headings[id] = heading
        Object_SetAxes(proxy, heading, if math.abs(heading.y) < 0.98 then vector.create(0, 1, 0) else vector.create(1, 0, 0))
      end
      scene.screen[id] = at
    elseif existing then
      dropArms(scene, id)
      Object_Delete(existing)
      scene.proxies[id] = nil
      scene.ghosts[id] = nil
      scene.headings[id] = nil
    end
  end
  -- Wrecks on the grid: the hull each was, in pieces (Hull.Wreck). The
  -- wreck's own object is a bare point for the rest to refer to.
  if next(inScene) then
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      if wreck.system == player.system and inScene[wreck.grid] then
        local at = vector.create(wreck.x - scene.ox, wreck.y - scene.oy, wreck.z - scene.oz)
        if scene.proxies[id] then
          scene.proxies[id]:SetPos(at)
        else
          local anchor = Object_Scenery({})
          container:AddInterior(anchor)
          anchor:SetPos(at)
          scene.proxies[id] = anchor
          -- It lies as the ship lay, if the ship is still here to ask
          -- (it is, on the frame it dies); else any way up.
          local look = vector.normalize(vector.create(dice(id) - 0.5, (dice(id + 1) - 0.5) * 0.4, dice(id + 2) - 0.5))
          local up = vector.create(0, 1, 0)
          for other, proxy in scene.proxies do
            if other >= Constants.FIRST_DYNAMIC_ID and state.balls[other] == nil and state.wrecks[other] == nil
              and vector.magnitude(proxy:GetPos() - at) < wreck.radius then
              look, up = proxy:GetLook(), proxy:GetUp()
            end
          end
          up = vector.normalize(up - look * vector.dot(up, look))
          makeWreck(scene, id, wreck, look, up, container)
        end
        placeWreck(scene, scene.wreckage[id], at, wreck.radius)
        scene.screen[id] = at
      end
    end
  end
  -- Interdiction fields: a shell of their width where each was dropped,
  -- while it lasts (module expansion, 2026-11-16).
  local fields: { [number]: boolean } = {}
  local dropped: { State.Bubble } = state.bubbles or {}
  for _, field in dropped do
    if field.system == player.system then
      fields[field.id] = true
      local at = vector.create(field.x - scene.ox, field.y - scene.oy, field.z - scene.oz)
      if not scene.bubbles[field.id] then
        local made = Object_Scenery({})
        Object_SetRenderable(made, Starbase.Bubble())
        container:AddInterior(made)
        made:SetScale(vector.create(field.radius, field.radius, field.radius))
        scene.bubbles[field.id] = made
      end
      scene.bubbles[field.id]:SetPos(at)
    end
  end
  for id, shell in scene.bubbles do
    if not fields[id] then
      Object_Delete(shell)
      scene.bubbles[id] = nil
    end
  end
  for id, proxy in scene.proxies do
    if id >= Constants.FIRST_DYNAMIC_ID and state.balls[id] == nil and state.wrecks[id] == nil then
      dropArms(scene, id)
      dropWreck(scene, id)
      Object_Delete(proxy)
      scene.proxies[id] = nil
    end
  end

  -- Their engines: a glare at each mouth and fire behind it, by how
  -- fast the ship means to go of what it can (so they light when it
  -- sets off, before it has got anywhere), and a little by how fast it
  -- is going.
  local fx = scene.fx :: Effects.Fx
  -- How hard the engines of a ship in warp are seen to burn, by how far
  -- off it is: the fire dims with every tenfold of distance, from all of
  -- it within a thousandth of as far as such a ship is drawn to none at
  -- the end of that. A ship's distance in warp grows and shrinks tenfold
  -- in equal times, so it fades out as it goes and in as it comes, and
  -- does not blink.
  local eye = vector.create(scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz)
  local function wake(at: vector): number
    return math.clamp(1 - math.log10(math.max(vector.magnitude(at - eye), 1) / (PASSING / 1000)) / 3, 0, 1)
  end
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local built = if proxy then designed[proxy] else nil
    local at: vector? = scene.screen[id]
    -- (a cloaked ship shows no fire)
    if proxy and built and at and not scene.ghosts[id] then
      local ball = state.balls[id]
      local warp = ball.warp
      local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
      local wanted = math.sqrt(ball.tvx * ball.tvx + ball.tvy * ball.tvy + ball.tvz * ball.tvz)
      local throttle = if warp and warp.stage == "warp" then 1 else (0.65 * wanted + 0.35 * speed) / math.max(ball.maxVelocity, 1)
      local right, up, look = proxy:GetRight(), proxy:GetUp(), proxy:GetLook()
      local unit = ball.radius / built.radius
      local color = vector.create(built.glow[1], built.glow[2], built.glow[3])
      -- (a trail three ship-lengths long at full speed; none in warp,
      -- where the scene goes with the ship and it has not moved)
      local trail: number? = math.clamp(6 * ball.radius / math.max(ball.maxVelocity, 1), 0.8, 20)
      -- (And none behind a carrier or anything bigger: the project
      -- owner's, 2026-11-13. A hull that size is too slow to draw one out
      -- behind it, and what was drawn was where its stern had swung as
      -- it turned, kilometres off to one side. Its engines glow, and
      -- that is all.)
      local flown = state.ships[id]
      local hull = if flown then Ships.byId[flown.type] else nil
      if hull and Ships.Capital(hull.class) then
        trail = nil
      end
      -- (a ship of somebody else's in warp draws its trail out behind it
      -- for a second and more, however small it is, and however big:
      -- that is what is seen of it going)
      if warp and warp.stage == "warp" and id ~= player.ship then
        trail = math.max(trail or 0, WAKE)
        throttle = wake(at)
      end
      for index, engine in built.engines do
        -- (and none while the pilot's own ship is in warp: the scene goes
        -- with that ship then, and every other one is somewhere else in
        -- it each frame)
        Effects.Thrust(fx, id * 16 + index, at + (right * engine.at.x + up * engine.at.y + look * engine.at.z) * unit, -look,
          engine.radius * unit, throttle, color, scene.time, if grid == 0 then nil else trail)
      end
    end
  end

  -- (A hull that is not of our own design has no engines to show, and
  -- one of ours may have none: in warp it draws a trail all the same,
  -- from its stern.)
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local at: vector? = scene.screen[id]
    local ball = state.balls[id]
    if proxy and at and id ~= player.ship and grid ~= 0 and ball.warp and ball.warp.stage == "warp" then
      local built = designed[proxy]
      if built == nil or (#built.engines == 0 and not built.quiet) then
        local look = proxy:GetLook()
        Effects.Thrust(fx, id * 16 + 15, at - look * ball.radius, -look, 0.3 * ball.radius, wake(at), WAKE_COLOR, scene.time, WAKE)
      end
    end
  end

  -- What is on the hardpoints of the hulls of our own design. (After
  -- every ship has been placed: a turret points at where its target is
  -- this frame. The fits are looked at once a tick, and when a ship is
  -- first seen.)
  local seconds = math.clamp(scene.time - scene.armsTime, 0, 0.25)
  scene.armsTime = scene.time
  local check = scene.armsTick ~= state.tick
  scene.armsTick = state.tick
  for _, id in state.ballIds do
    local proxy: Object? = scene.proxies[id]
    local built = if proxy then designed[proxy] else nil
    local at: vector? = scene.screen[id]
    -- (nor anything on its hardpoints)
    if proxy and built and at and not scene.ghosts[id] then
      if check or scene.arms[id] == nil then
        armShip(scene, game, id, built, container)
      end
      local ball = state.balls[id]
      placeArms(scene, scene.arms[id], proxy, at, ball.radius, ball.vitals.running, seconds)
      moveParts(scene, game, id, built, proxy, at, ball, container, seconds)
    end
  end

  -- The gate the pilot has just come out of lights, as the white clears.
  if not scene.lit then
    local at: vector? = scene.screen[player.ship]
    if at then
      scene.lit = true
      lightGate(scene, fx, gateNear(scene, at, 50000), JUMP_IN)
    end
  end

  -- What just happened, as effects (Game/View/Effects).
  for _, event in session.events do
    if event.kind == "Jumped" and event.ship ~= player.ship and grid ~= 0 then
      -- Somebody else through a gate that is in sight: out of this
      -- system by one of its gates, or into it by one.
      if event.from == player.system then
        lightGate(scene, fx, event.gate, 0.7)
        -- (and one that went by its own drive, or in the field of
        -- another's: a light where it was)
        local was: vector? = scene.screen[event.ship]
        if event.drive and was then
          local size = event.radius or 300
          Effects.Burst(fx, was, JUMP_LIGHT, 2.2 * size, 0, 0.7, scene.time)
          Effects.Burst(fx, was, JUMP_LIGHT, 6 * size, 1, 1.0, scene.time)
        end
      end
      -- (into it: by a drive, a light there now; through a stargate, as it comes out, below)
      if event.to == player.system and event.gate == 0 then
        lightGate(scene, fx, event.arrival, 0.7)
      end
    elseif event.kind == "JumpEmerged" and event.ship ~= player.ship and grid ~= 0 then
      lightGate(scene, fx, event.gate, 0.7)
    elseif (event.kind == "BallAdded" or event.kind == "BallRemoved") and event.gate and grid ~= 0 then
      -- (and the system's own traffic, which comes in by a gate and goes
      -- out by one as far as anybody can see: Tactical/Traffic)
      lightGate(scene, fx, event.gate, 0.7)
    elseif event.kind == "Shot" then
      -- (a beam that leapt is drawn from the ship it leapt from: Core/Tactical/Combat; and a vertical launcher's
      -- salvo at what is too near is never launched)
      local from, to = state.balls[event.leap or event.from], state.balls[event.to]
      citadelCores(scene, state)
      if from and to and event.outcome ~= "too close" then
        local item = state.items[event.item]
        -- (from the mouth of the gun, if it is one that is shown)
        -- (a gun that is part of a hull, and no item, says what it looks like firing: Core/Tactical/Combat)
        Effects.Fire(fx, if item then item.type elseif event.look then event.look else FALLBACK[event.family] or "autocannon", from.id, to.id, from.radius, to.radius,
          event.outcome, event.flight or 0, struck(to), scene.time,
          if event.look and state.ships[from.id] and (state.ships[from.id].owner == "starbase" or state.ships[from.id].stands ~= nil) then citadelGun(scene, state, from.id, event.look, event.mount)
          elseif event.leap == nil and scene.screen[-event.item] then -event.item else nil,
          if event.volley then { n = event.volley, path = event.path or "zig", delay = event.delay or 0,
            up = if scene.proxies[from.id] then scene.proxies[from.id]:GetUp() else nil }
          elseif event.path == "plasma" then { n = 1, path = "plasma", delay = 0, charge = if item then item.charge else nil }
          else nil, event.missile)
      end
    elseif event.kind == "PointDefence" then
      -- (a point defence turret's stream at a missile, or at a drone: Core/Tactical/PointDefence)
      local from = state.balls[event.from]
      if from then
        -- (a citadel's, from the turret of its that it was: Core/Tactical/CitadelGuns)
        local citadel = event.mount and state.ships[from.id] and (state.ships[from.id].owner == "starbase"
          or state.ships[from.id].stands ~= nil)
        if citadel then
          citadelCores(scene, state)
        end
        local mount = if citadel then citadelGun(scene, state, from.id, "pds", event.mount) else nil
        Effects.Tracers(fx, from.id, if mount then 0 else from.radius, event.missile, event.to, event.rounds or 0, event.down == true,
          scene.time, mount or (if scene.screen[-event.item] then -event.item else nil))
      end
    elseif event.kind == "MissileDowned" then
      Effects.Down(fx, event.missile, scene.time)
    elseif event.kind == "MissileHit" and event.missile then
      Effects.Land(fx, event.missile, scene.time)
    elseif event.kind == "MissileExpired" and event.missile then
      Effects.Down(fx, event.missile, scene.time, true)
    elseif event.kind == "BatteryFired" then
      -- (from the battery that fired, where it stands outside the
      -- field: Core/Tactical/Batteries. A colony ship's are aboard it,
      -- and a gate's are the gate's: from that, then.)
      local to = state.balls[event.to]
      local station = objects[event.station % Constants.STRUCTURE_ID_SPAN]
      local from = state.balls[event.from]
      if to and from and scene.screen[event.from] then
        scene.volleys += 1
        -- (a gun battery fires like its people's guns: Core/Tactical/Batteries)
        Effects.Fire(fx, if event.missile then "launcher.cruise" else event.look or "artillery.large", event.from, event.to, from.radius, to.radius,
          "hit", 0, struck(to), scene.time, nil)
      elseif to and station and scene.screen[event.station] then
        scene.volleys += 1
        Effects.Fire(fx, if event.missile then "launcher.cruise" else event.look or "artillery.large", event.station, event.to, station.radius * 0.35,
          to.radius, "hit", 0, struck(to), scene.time, nil)
      end
    elseif (event.kind == "WarpStarted" or event.kind == "WarpEnded") and event.ball ~= player.ship and grid ~= 0 then
      -- Somebody else going into warp, or coming out of it, where it can
      -- be seen: a flash where they are (and a ring, coming out).
      local at: vector? = scene.screen[event.ball]
      local ball = state.balls[event.ball]
      if at and ball then
        Effects.Burst(fx, at, WAKE_COLOR, 5 * ball.radius, if event.kind == "WarpEnded" then 1 else 0, 0.5, scene.time)
      end
    elseif MODULE_FX[event.kind] and grid ~= 0 then
      moduleFx(scene, fx, state, event)
    elseif event.kind == "ModuleStarted" and grid ~= 0 then
      startedFx(scene, fx, state, event)
    elseif event.kind == "BallDestroyed" and event.system == player.system and grid ~= 0 then
      local at = vector.create(event.x - scene.ox, event.y - scene.oy, event.z - scene.oz)
      local boom = Object_Explosion(0, 0, 3)
      container:AddInterior(boom)
      boom:SetPos(at)
      Effects.Explode(fx, at, event.radius or 25, scene.time)
    end
  end
  -- (and, a second of the Core's gone by, each missile in the air drawn as far through its flight as the Core has
  -- it: Core/Tactical/Combat's missiles fly after their targets)
  if #session.events > 0 then
    for _, missile in state.missiles do
      local at, born = missile.at, missile.born or 0
      if missile.id and missile.x and at and at >= born then
        local eta = math.max(0, missile.impact - at)
        Effects.Track(fx, missile.id, (at - born) / math.max(at - born + eta, 1e-6), eta, scene.time)
      end
    end
  end
  -- A mining laser's beam, a salvager's, and that of whatever runs on
  -- another ship, for as long as the module runs: begun again each time
  -- the last one is nearly out.
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if scene.screen[id] and ball.system == player.system then
      for _, running in ball.vitals.running do
        local item = state.items[running.item]
        local rock = if running.target ~= 0 then Core.Query.Body(game, running.target) else nil
        if item and rock and Effects.Held(item.type) and scene.screen[running.target]
          and scene.time - (scene.mining[running.item] or -1) > 0.42 then
          scene.mining[running.item] = scene.time
          Effects.Fire(fx, item.type, id, running.target, ball.radius, rock.radius, "hit", 0, "", scene.time,
            if scene.screen[-running.item] then -running.item else nil)
        end
      end
    end
  end

  -- A citadel's tether to each ship of its side held by it (Core/Assets/Starbases' Tether): a beam from the
  -- citadel to the ship, begun again each time the last one is nearly out.
  for _, id in state.ballIds do
    local ship = state.ships[id]
    local tether = if ship then ship.tether else nil
    local starbase = if tether then state.starbases[tether] else nil
    local core = if starbase then state.balls[starbase.core] else nil
    local ball = state.balls[id]
    -- (from the citadel as it is drawn: the station)
    if tether and core and ball and scene.screen[id] and scene.screen[tether] and ball.system == player.system
      and scene.time - (scene.tethers[id] or -1) > 0.42 then
      scene.tethers[id] = scene.time
      Effects.Fire(fx, "tether", tether, id, core.radius, ball.radius, "hit", 0, "", scene.time)
    end
  end

  -- A citadel's observatory and its miners (Core/Assets/CitadelWorks): the telescope turned to the signal it is
  -- finding; a moon or planet miner's gun turned to its moon or planet with its beam held on it; an asteroid
  -- miner's drawing a rock in from the way the belts are, which comes in and wears away as it is processed, and
  -- then the next. (Nothing is taken from a belt: the rock is only to be seen.)
  for id, special in scene.citadelSpecial do
    local starbase = state.starbases[id]
    local here = scene.screen[id]
    local station = objects[id % Constants.STRUCTURE_ID_SPAN]
    if starbase and here and station then
      local mount = here + special.at
      scene.screen[specialKey(id)] = mount
      local aim: vector? = nil
      local reach: vector? = nil
      local function online(works: string): boolean
        for _, fitted in starbase.modules do
          local module = Structures.moduleById[fitted.type]
          if module and module.works == works and state.tick >= fitted.ready and starbase.fuel > 0 then
            return true
          end
        end
        return false
      end
      if special.kind == "observatory" then
        local site = state.sites[starbase.observing or 0]
        local where = if site and online("observatory") then objects[site.id % Constants.STRUCTURE_ID_SPAN] else nil
        if where then
          aim = vector.create(where.x - station.x, where.y - station.y, where.z - station.z)
        end
      else
        local body = objects[(station.parent or 0) % Constants.STRUCTURE_ID_SPAN]
        if body and (body.kind == "moon" or body.kind == "planet") and online(body.kind) then
          -- (its beam held on the moon or the planet: drawn out toward it, as far as is seen)
          local way = vector.normalize(vector.create(body.x - station.x, body.y - station.y, body.z - station.z))
          aim = way
          reach = mount + way * 25000
        elseif online("asteroid") then
          local rock = scene.citadelRocks[id]
          local cycle = 40
          if rock == nil or scene.time - rock.born >= cycle then
            if rock then
              Object_Delete(rock.object)
            end
            -- (from the way of the nearest belt, a little to one side, eight kilometres out)
            local way = vector.create(1, 0, 0)
            local nearest = math.huge
            for _, other in objects do
              if other.kind == "belt" then
                local d = vector.create(other.x - station.x, other.y - station.y, other.z - station.z)
                if vector.magnitude(d) < nearest then
                  nearest, way = vector.magnitude(d), d
                end
              end
            end
            local turn = (dice(scene.time) - 0.5) * 0.8
            way = about(vector.normalize(way), vector.create(0, 1, 0), turn)
            local made = Object_Asteroid(math.floor(scene.time * 7919) % 100000 + 1)
            local into = scene.container
            if into then
              into:AddInterior(made)
            end
            rock = { object = made, from = way * 8000 + vector.create(0, (dice(scene.time + 1) - 0.5) * 2000, 0), born = scene.time,
              size = 160 + 160 * dice(scene.time + 2) }
            scene.citadelRocks[id] = rock
          end
          local drawn = rock :: { object: Object, from: vector, born: number, size: number }
          local t = math.clamp((scene.time - drawn.born) / cycle, 0, 1)
          -- (drawn in over most of its time, and worn away over the last of it, at the mouth of the turret)
          local inward = 1 - (1 - math.min(1, t / 0.75)) ^ 2
          local at = mount + drawn.from * (1 - inward)
          local size = drawn.size * (if t < 0.75 then 1 else math.max(0.02, 1 - (t - 0.75) / 0.25))
          drawn.object:SetPos(at)
          drawn.object:SetScale(vector.create(size, size, size))
          aim = at - mount
          reach = at
        end
      end
      if aim then
        local pieces: { Starbase.Moving } = scene.moving[id] or {}
        for _, piece in pieces do
          if piece.motion.special == special.kind then
            piece.aim = vector.normalize(aim)
            -- (its beam leaves from its muzzle, wherever that is turned to now)
            if piece.tip then
              scene.screen[specialKey(id)] = piece.tip
            end
          end
        end
      end
      if reach then
        scene.screen[beamEndKey(id)] = reach
        if scene.time - (scene.citadelBeams[id] or -1) > 0.42 then
          scene.citadelBeams[id] = scene.time
          Effects.Fire(fx, "miner", id, beamEndKey(id), 0, 0, "hit", 0, "", scene.time, specialKey(id))
        end
      end
    end
  end

  -- The sun, the planets and the moons in scaled space: each drawn in
  -- its true direction, near enough for the renderer to reach, and
  -- shrunk to span the angle it truly spans.
  --
  -- They cannot all be drawn at one distance: of two that overlap on the
  -- screen the larger would then hide the smaller whichever was in
  -- front, and a moon crossing the face of its planet would vanish. So
  -- they are taken nearest first, and each is put far enough out that
  -- the side of it facing the eye lies beyond the limb of the one
  -- before.
  local ex, ey, ez = scene.eyeX - scene.ox, scene.eyeY - scene.oy, scene.eyeZ - scene.oz
  local bodies: { { object: SystemData.Object, distance: number } } = {}
  for _, object in objects do
    local dx, dy, dz = object.x - scene.eyeX, object.y - scene.eyeY, object.z - scene.eyeZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if object.kind == "planet" or object.kind == "moon" or object.kind == "sun" then
      table.insert(bodies, { object = object, distance = distance })
      if object.kind == "sun" and scene.star and distance > 0 then
        -- (the light itself, far off in the sun's direction, so that it
        -- falls on every body from nearly the right side)
        local out = 60000000 / distance
        scene.star:SetPos(vector.create(ex + dx * out, ey + dy * out, ez + dz * out))
      end
    elseif not scene.screen[object.id] and object.kind ~= "asteroid" then
      -- Somewhere to warp to: a station, gate or belt on another grid.
      local shrink = FAR / math.max(distance, FAR)
      scene.screen[object.id] = vector.create(ex + dx * shrink, ey + dy * shrink, ez + dz * shrink)
    end
  end
  table.sort(bodies, function(a, b)
    if a.distance ~= b.distance then
      return a.distance < b.distance
    end
    return a.object.id < b.object.id
  end)
  local limb = 0      -- how far off the limb of the body before lies
  for _, placed in bodies do
    local object, distance = placed.object, math.max(placed.distance, 1)
    -- (the sine of the angle its radius spans)
    local sine = math.min(object.radius / distance, 0.999)
    local out = math.min(math.max(math.min(distance, FAR), limb / (1 - sine)), FARTHEST)
    limb = out * math.sqrt(1 - sine * sine) * 1.002
    local shrink = out / distance
    local at = vector.create(ex + (object.x - scene.eyeX) * shrink, ey + (object.y - scene.eyeY) * shrink,
      ez + (object.z - scene.eyeZ) * shrink)
    local body = scene.celestials[object.id]
    body:SetPos(at)
    local radius = object.radius * shrink
    body:SetScale(vector.create(radius, radius, radius))
    -- (a world turns on its axis, as far as the game's time says)
    local world = scene.worlds[object.id]
    if world then
      Planet.Turn(world, state.tick * Constants.TICK + since)
    end
    scene.screen[object.id] = at
    if object.kind == "sun" and scene.star then
      -- The flare is the glare of a star too small to show a face. It
      -- is taken to lie just this side of the disc, so that a planet in
      -- front of the sun hides it and the disc does not; once the disc
      -- is big enough to see, the flare is left behind it, and goes.
      Star_SetFlareDepth(scene.star, if sine < FLARE_UNDER then out * (1 - sine) * 0.98 else 0)
      -- (and a lightless sphere in front of it, or round the eye, hides
      -- it: its light, and so its flare, go as it is hidden. sunInHole)
      local shade = sunInHole(scene, vector.create(object.x, object.y, object.z))
      if math.abs(shade - scene.sunShade) > 0.005 then
        scene.sunShade = shade
        Star_SetColor(scene.star, Star.Light(object.variety) * (1 - shade))
      end
    end
  end

  -- The pilot's own ship in warp: the place going by it, in lines.
  local warping = if me then me.warp else nil
  local own: vector? = scene.screen[player.ship]
  if me and warping and warping.stage == "warp" and own then
    Effects.Rush(fx, scene.warp, own, vector.create(warping.ux, warping.uy, warping.uz), me.radius, scene.time)
  else
    Effects.Rush(fx, 0, vector.create(0, 0, 0), vector.create(0, 0, 1), 1, scene.time)
  end

  citadelCores(scene, state)
  Effects.Update(fx, scene.time, scene.screen)

  -- (docked in a colony ship, it is that ship the camera is on)
  -- (the ship itself, when it is in space to be seen: until then, and
  -- the moment a pilot is put aboard one, the gate it lies by. The
  -- camera is never left on something of a system that is gone.)
  local _, carrier = Core.Query.Carrier(game, player.docked)
  scene.focus = scene.proxies[if me then player.ship elseif carrier ~= 0 then carrier else player.docked]
    or (if me == nil then scene.proxies[beside] else nil)
end

-- Have the camera keep something in view past the ship (by its id),
-- or with 0 or nothing, stop.
function Scene.Track(scene: Scene, id: number?)
  scene.tracking = id or 0
end

-- How near the eye may come to 'focus' from the way 'look' (out from its
-- middle), in its radii: where that line leaves the box it is drawn in,
-- and a sixth again, and NEAR_CLEAR metres more. (Without a model: two and
-- a half, as it always was.)
-- (The eye's near plane is not the engine's 5 cm: the shaders' log depth,
-- common/vert.jsl, is not scaled by w, so the clip test cuts away what is
-- nearer than about 0.65 m. Closer, the capsule's ball was cut open and
-- looked into, 2026-11-27.)
local NEAR_CLEAR = 0.8
local function nearestZoom(focus: Object, look: vector, radius: number): number
  local renderable = focus:GetRenderable()
  if not renderable or radius <= 0 then
    return 2.5
  end
  local bound = renderable:GetBound()
  local half = (bound.upper - bound.lower) * focus:GetScale() * 0.5
  local along = vector.create(math.abs(vector.dot(look, focus:GetRight())), math.abs(vector.dot(look, focus:GetUp())),
    math.abs(vector.dot(look, focus:GetLook())))
  local out = math.huge
  for _, pair in { { along.x, half.x }, { along.y, half.y }, { along.z, half.z } } do
    if pair[1] > 1e-6 then
      out = math.min(out, pair[2] / pair[1])
    end
  end
  if out == math.huge then
    return 2.5
  end
  return math.clamp((out * 1.15 + NEAR_CLEAR) / radius, 0.2, 2.5)
end

-- Orbit the camera around the focus. 'input' is false while the cursor is
-- over the interface.
function Scene.UpdateCamera(scene: Scene, frameSeconds: number, input: boolean)
  local focus = scene.focus
  if focus == nil then
    return
  end
  -- (through a stargate the camera is not the pilot's to turn: it sits
  -- behind the ship, the way it goes)
  local chase = scene.chase
  local radius = focus:GetRadius()
  local look = vector.create(
    math.sin(scene.pitch) * math.cos(scene.yaw), math.cos(scene.pitch), math.sin(scene.pitch) * math.sin(scene.yaw))
  -- (as near as it comes, in focus radii: a little outside the hull's own
  -- box on the line the eye looks from, so that it can come in close to a
  -- long hull's side or a small ball, and never into either; the radius is
  -- half the box's diagonal, which kept the eye far off: the owner's, 2026-11-27)
  local nearest = nearestZoom(focus, look, radius)
  if input then
    scene.zoomTarget = math.clamp(scene.zoomTarget * (1 - 0.12 * Mouse_GetScrollDelta()), nearest, 4000)
    if Mouse_LeftDown() and chase == nil then
      local delta = Cursor_GetDelta()
      scene.yaw -= 0.008 * delta.x
      scene.pitch = math.clamp(scene.pitch - 0.008 * delta.y, 0.08, math.pi - 0.08)
      -- (a hand on the camera takes it back from whatever it was following)
      if delta.x ~= 0 or delta.y ~= 0 then
        scene.tracking = 0
      end
    end
  end
  -- Following something: the camera swings round, a little each frame,
  -- to sit on the far side of the ship from it, a little above the line
  -- through the two so that the ship does not hide it.
  local followed: vector? = if scene.tracking ~= 0 then scene.screen[scene.tracking] else nil
  if chase then
    local away = -chase
    local pitch = math.clamp(math.acos(math.clamp(away.y, -1, 1)) - 0.10, 0.05, math.pi - 0.05)
    local yaw = math.atan2(away.z, away.x)
    local ease = 1 - Float_ExpDecay(frameSeconds, 0.12)
    local turn = (yaw - scene.yaw + math.pi) % (2 * math.pi) - math.pi
    scene.yaw += turn * ease
    scene.pitch += (pitch - scene.pitch) * ease
    scene.tracking = 0
  elseif followed then
    local away = focus:GetPos() - followed
    if vector.magnitude(away) > 1 then
      away = vector.normalize(away)
      local pitch = math.clamp(math.acos(math.clamp(away.y, -1, 1)) - 0.16, 0.05, math.pi - 0.05)
      local yaw = math.atan2(away.z, away.x)
      local ease = 1 - Float_ExpDecay(frameSeconds, 0.25)
      -- (round the short way)
      local turn = (yaw - scene.yaw + math.pi) % (2 * math.pi) - math.pi
      scene.yaw += turn * ease
      scene.pitch += (pitch - scene.pitch) * ease
    end
  elseif scene.tracking ~= 0 then
    -- (it has gone from the grid, or the ship has)
    scene.tracking = 0
  end
  scene.zoom += (scene.zoomTarget - scene.zoom) * (1 - Float_ExpDecay(frameSeconds, 0.12))
  look = vector.create(
    math.sin(scene.pitch) * math.cos(scene.yaw), math.cos(scene.pitch), math.sin(scene.pitch) * math.sin(scene.yaw))
  -- (turned round to where the box reaches further, it stands off it)
  nearest = nearestZoom(focus, look, radius)
  -- The engine camera's "relative" positions are in fact scene
  -- coordinates (src/liblt/Game/Camera.cpp), so orbit the focus's own
  -- position. It eases toward where it is told to be; with a ship moving
  -- at hundreds of metres a second that would trail behind, so the easing
  -- is made effectively instant and the smoothing done on the zoom above.
  local camera = scene.camera
  local center = focus:GetCenter()
  -- (through a gate, near enough to stay inside its opening)
  local distance = (if chase then math.min(scene.zoom, 10) else math.max(scene.zoom, nearest)) * radius
  if scene.docked then
    -- (the eye and what it looks at go aside together, and the tower
    -- goes the other way across the window)
    local across = vector.cross(look, vector.create(0, 1, 0))
    if vector.magnitude(across) > 1e-3 then
      center += vector.normalize(across) * (distance * DOCKED_ASIDE)
    end
  end
  local eye = center + look * distance
  -- (gone through a gate, the camera falls behind as the ship is thrown
  -- on into the black: it comes on at a little over half the pace the
  -- ship went in at)
  local passage = scene.passage
  if passage and passage.stage == "leave" then
    eye = passage.eye + passage.way * (passage.speed * 0.6 * (scene.time - passage.since))
  end
  scene.eyeAt = eye
  camera:SetTarget(focus)
  camera:SetRelativePos(eye)
  camera:SetRelativeLookAt(center)
  camera:SetRigidity(100000)
  -- In warp the view opens out; and through a gate, farther.
  local eased = scene.warp * scene.warp * (3 - 2 * scene.warp)
  camera:SetFov(62 + 30 * eased + 44 * scene.rush)
end

-- Advance the engine's own effects (lights, trails, particles).
function Scene.Update(scene: Scene, frameSeconds: number)
  scene.time += frameSeconds
  local container = scene.container
  if container then
    container:Update(frameSeconds)
  end
end

return Scene
