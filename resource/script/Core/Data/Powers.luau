--!strict
-- The powers of the galaxy, what their navies are made of, and every
-- number the faction layer is tuned by. (docs/roadmap.md §6; the rules
-- that use these are in Core/Strategic.)
--
-- Time is in ticks of ten game seconds unless a name says otherwise.
-- Money is in credits; rates of money are per game hour.

local Powers = {}

-- Personality, each from 0 to 1.
export type Traits = { aggressive: number, greedy: number, sociable: number }
export type PowerDef = { name: string, traits: Traits }

Powers.list = {
  { name = "Vessari Compact", traits = { aggressive = 0.3, greedy = 0.9, sociable = 0.6 } },
  { name = "Talmar League", traits = { aggressive = 0.2, greedy = 0.7, sociable = 0.8 } },
  { name = "Orun Hegemony", traits = { aggressive = 0.8, greedy = 0.6, sociable = 0.2 } },
  { name = "Sable Concord", traits = { aggressive = 0.5, greedy = 0.5, sociable = 0.4 } },
  { name = "Kethri Union", traits = { aggressive = 0.9, greedy = 0.4, sociable = 0.2 } },
  { name = "Dominion of Ash", traits = { aggressive = 0.7, greedy = 0.3, sociable = 0.4 } },
  { name = "Meridian Trust", traits = { aggressive = 0.5, greedy = 0.8, sociable = 0.5 } },
  { name = "Halcyon Reach", traits = { aggressive = 0.2, greedy = 0.4, sociable = 0.9 } },
} :: { PowerDef }

Powers.PIRATES = "the Unbound"

-- Where two powers' relations settle if nothing happens between them:
-- sociable pairs get on, aggressive pairs do not.
function Powers.Natural(a: Traits, b: Traits): number
  return 10 + 20 * (a.sociable + b.sociable) - 25 * (a.aggressive + b.aggressive)
end

-- ---------------------------------------------------------------------
-- Timing

Powers.JUMP_TICKS = 6        -- one gate jump: a minute
Powers.ROUND_TICKS = 6       -- a round of fighting, and a step of the economy: a minute
Powers.PERIOD_TICKS = 60     -- taxes, upkeep, order and diplomacy: ten minutes
Powers.PERIOD_HOURS = Powers.PERIOD_TICKS / 360

-- ---------------------------------------------------------------------
-- Ships
--
-- A navy buys its hulls and their fittings on the market where it is
-- built, at that market's prices, so a shortage of alloys reaches the
-- shipyards. 'strength' is what a ship is worth in a fight; 'supply' is
-- the fuel and ammunition it uses in an hour on active service.

export type ShipClass = {
  id: string,
  name: string,
  hull: string,        -- the class of goods its hull is
  modules: number,     -- units of ship modules to fit it
  strength: number,
  supply: number,      -- units of supply an hour
  buildTicks: number,
}

Powers.ships = {
  { id = "frigate", name = "Frigate", hull = "hulls.frigate", modules = 4, strength = 1, supply = 1, buildTicks = 60 },
  { id = "cruiser", name = "Cruiser", hull = "hulls.cruiser", modules = 12, strength = 8, supply = 7, buildTicks = 240 },
  { id = "battleship", name = "Battleship", hull = "hulls.battleship", modules = 30, strength = 40, supply = 28,
    buildTicks = 720 },
} :: { ShipClass }

-- A unit of supply: what a frigate uses in an hour.
Powers.SUPPLY_FUEL = 1
Powers.SUPPLY_AMMUNITION = 0.5
-- What a fleet can carry, in hours of its own use. Past its own borders
-- it lives on this, so this is how long an offensive can last.
Powers.SUPPLY_HOURS = 24
-- A fleet with nothing left fights at this share of its strength.
Powers.UNSUPPLIED = 0.5
-- Crews, per unit of strength an hour: on active service, and laid up.
Powers.PAY = 15
Powers.PAY_RESERVE = 4
-- Bringing a laid-up ship back: this share of its price, and this long.
Powers.REACTIVATE_SHARE = 0.05
Powers.REACTIVATE_TICKS = 180
-- A yard works on this many ships at once.
Powers.YARD_SLOTS = 3

-- What each power starts with, at its homeworld.
Powers.HOME_FLEET = { 20, 5, 0 }  -- by ship class: 60 strength
Powers.STARTING_CREDITS = 150000

-- ---------------------------------------------------------------------
-- Fighting

-- What a side loses in a round: this share of the strength facing it.
Powers.ROUND_LOSS = 0.05
-- Each side's strength in a round is rolled within this much of itself.
Powers.COMBAT_SPREAD = 0.25
-- A side under this share of what faces it withdraws.
Powers.RETREAT_BELOW = 0.5
-- Nobody attacks, or claims, with less than this much over the defence.
Powers.ATTACK_ODDS = 3
-- A system's own defences: this times the square root of its
-- population, and less where the owner's hold is weak. A homeworld's
-- are ten times that: a power can lose its provinces in a bad war, but
-- its heart falls only to an enemy that dwarfs it. They come back at
-- this share of full an hour.
Powers.DEFENCE = 5
Powers.DEFENCE_HOME = 10
Powers.DEFENCE_REPAIR = 0.25

-- A siege, in stages: the system is cut off; its defences are fought
-- down; it is occupied. About an hour in all, so that someone who hears
-- of it can get there.
Powers.SIEGE_BLOCKADE = 60
Powers.SIEGE_ASSAULT = 180
Powers.SIEGE_OCCUPY = 120
-- Bringing an independent system in is quicker.
Powers.CLAIM_ASSAULT = 60
Powers.CLAIM_OCCUPY = 60
-- Defences count as beaten below this share of full.
Powers.DEFENCE_BEATEN = 0.1
-- Construction kits to set up an administration: this, plus this per
-- unit of population.
Powers.CLAIM_KITS = 3
Powers.CLAIM_KITS_PER_HEAD = 1.5

-- ---------------------------------------------------------------------
-- Money
--
-- A power's income is what it levies on what its people spend. Nothing
-- else counts as income.

-- The share of its people's spending a power collects, where its hold
-- is complete.
Powers.LEVY = 0.01
-- Holding a system, an hour: more for each jump from the capital, and
-- more again, as the square, for every system held. So an empire has a
-- natural size, past which the next system costs more than it brings
-- in; at SOV_SCALE systems each costs twice the base, at three times
-- that many ten times, and nothing the galaxy holds pays for half of it.
Powers.SOV_BASE = 70
Powers.SOV_DISTANCE = 0.08
Powers.SOV_SCALE = 35
-- Policing a system at full effort, an hour: this times one plus its
-- population.
Powers.POLICE = 25
-- A power that cannot pay its costs is in arrears. After this many
-- periods in a row it loses its hold on a system each period: the one
-- it holds least firmly.
Powers.ARREARS_GRACE = 6

-- ---------------------------------------------------------------------
-- Order: how firmly a system is held, how much piracy it suffers, and
-- so how safe it is.

Powers.CONTROL_NEW = 0.2          -- right after a claim or a capture
Powers.CONTROL_BASE = 0.3
Powers.CONTROL_POLICE = 0.35      -- at full policing
Powers.CONTROL_NEAR = 0.3         -- at the capital, fading with each jump...
Powers.CONTROL_FADE = 0.8         -- ...by this factor
Powers.CONTROL_GARRISON = 0.15    -- with a garrison of GARRISON strength
Powers.CONTROL_PRESSURE = 0.5     -- lost to pirate pressure of 1
Powers.CONTROL_RISE = 0.1         -- an hour
Powers.CONTROL_FALL = 0.3
Powers.GARRISON = 10
-- Occupied ground. Every system lies in some power's natural part of
-- the map (the atlas's). Another power that holds it, while the first
-- still lives, never gets more than this share of the hold it would
-- have at home: so conquests pay half, and are easier to take back.
Powers.OCCUPIED = 0.5
-- Order in a system nobody owns.
Powers.LOCAL_ORDER = 0.3
-- A system next to an enemy's, or under siege, is this much less safe.
Powers.FRONT = 0.7
Powers.SECURITY_PRESSURE = 0.6

-- Pirate pressure, from 0 to 1. An hour: a den adds DEN, lawlessness
-- adds LAWLESS per unit of insecurity, it spreads toward its neighbours'
-- level at SPREAD, and it falls by itself, under policing and under a
-- garrison.
Powers.PRESSURE_DEN = 1.0
Powers.PRESSURE_LAWLESS = 0.15
Powers.PRESSURE_SPREAD = 0.5
Powers.PRESSURE_DECAY = 0.3
Powers.PRESSURE_POLICED = 1.5
Powers.PRESSURE_GARRISON = 1.0
-- The share of goods on a lane that pirates take, at pressure 1, and
-- how much of a lane's haulage they scare off.
Powers.THEFT = 0.02
Powers.PRESSURE_HAULAGE = 0.5

-- ---------------------------------------------------------------------
-- Pirates

Powers.PIRATE_CREDITS = 60000
Powers.DENS = 6                   -- at the start
Powers.DENS_MOST = 10
Powers.DEN_DEFENCE = 15
Powers.DEN_COST = 120000
Powers.DEN_TICKS = 180            -- to build one, with an escort holding the site
Powers.DEN_SPACING = 4            -- jumps between dens, and from any power's space
-- What reaches the organisation, as a share of the goods' normal
-- price: of a raid's loot, and of what is taken on the lanes (most of
-- that enriches whoever took it).
Powers.FENCE = 0.4
Powers.TITHE = 0.06
-- A pirate frigate, crewed.
Powers.PIRATE_FRIGATE = 7000
Powers.BAND = 12                  -- frigates a den keeps...
Powers.BAND_WEALTH = 250000       -- ...and one more for each this many credits the pirates hold,
Powers.BAND_MOST = 36             -- up to this
-- What the pirates hold beyond this hoard they squander, this share of
-- the excess a period. And whoever destroys a den takes its share of
-- the hoard.
Powers.HOARD = 3000000
Powers.SQUANDER = 0.05
-- A raid: a band fights the defences down to this share, takes what it
-- can carry of the goods worth stealing (this many credits' worth per
-- unit of its strength, and never more than this share of what is
-- there), and goes.
Powers.RAID_BEATEN = 0.5
Powers.RAID_HAUL = 2500
Powers.RAID_SHARE = 0.05
Powers.RAID_PRESSURE = 0.4
Powers.RAID_CONTROL = 0.15
Powers.RAID_RANGE = 4
Powers.RAID_EVERY = 720           -- ticks between a den's raids, at the least
Powers.RAID_SPARED = 2880         -- ticks before the same system is raided again

-- ---------------------------------------------------------------------
-- Diplomacy
--
-- Relations run from -100 to 100 and move by these amounts an hour.

Powers.WAR_BELOW = -50
-- A pair's relations close this share of the gap to their usual level
-- an hour. Against that, neighbours rub: FRICTION an hour for a wholly
-- aggressive, unsociable pair with a long border, less for a short one,
-- less again (NEAR) for two who only face each other across a system
-- neither owns, and LAND_HUNGER times as much when one of them has
-- nowhere left to grow. So each pair settles at a level its friction
-- sets, and the quarrelsome ones settle below the threshold of war.
Powers.DRIFT = 0.05
Powers.FRICTION = 3
Powers.CONTACT_NEAR = 0.4
Powers.LAND_HUNGER = 2
-- Incidents. Neighbours' relations are also knocked about at random:
-- by up to this much either way in an hour (less in a shorter time, as
-- the root of it). Against the drift that leaves a pair wandering some
-- fifteen points around where it would settle, so that which quarrels
-- turn into wars, and when, differs from one history to the next.
Powers.INCIDENTS = 8
-- A power cannot declare war within this long of declaring one, or of
-- one of its wars ending: a day.
Powers.WAR_COOLDOWN = 8640
-- After a peace neither may attack the other for TRUCE (two days); one
-- that took systems or money by it may not for TRUCE_WON (three).
Powers.TRUCE = 17280
Powers.TRUCE_WON = 25920
Powers.AFTER_PEACE = -15          -- relations right after one

-- Grudges. Every system taken or ceded lowers the level the pair's
-- relations settle at by this much; the grudge fades by this share an
-- hour. So powers that have fought are likelier to fight again, for a
-- few days.
Powers.GRUDGE = 3
Powers.GRUDGE_FADE = 0.01

-- Coalitions. A power that begins a war against one this much weaker,
-- while itself this much above the average, is an aggressor. The others
-- come to fear it (FEAR an hour, for one at twice the average power)
-- and to side with its victim (SOLIDARITY). As their relations with it
-- fall they close their borders to it, then pay its victim, then join
-- the war: unless they are in no state to.
Powers.AGGRESSOR_RATIO = 1.2
Powers.AGGRESSOR_SIZE = 1.15
Powers.FEAR = 10
Powers.SOLIDARITY = 3
Powers.EMBARGO_BELOW = -20
Powers.SUBSIDY_BELOW = -35
Powers.SUBSIDY = 0.05             -- of the giver's income

-- Peace. A war has a score, from the declarer's side: what each has
-- taken, as a share of the smaller's worth, and the share of its fleet
-- each has lost. Each side tires with time (wholly, after WAR_LONGEST),
-- with losses and with an empty treasury. The side that is behind, or
-- tired, offers terms in proportion to the score; the other takes them
-- if they are worth more to it than fighting on.
Powers.WAR_LONGEST = 8640         -- a day
Powers.REPARATIONS = 0.4          -- of the loser's credits, at a score of 1
Powers.CEDED_MOST = 3             -- systems handed over, at a score of 1

-- ---------------------------------------------------------------------
-- How the powers' governments think (Strategic/Mind)

-- Hours of running costs kept in hand before spending on growth.
Powers.RESERVE_HOURS = 6
-- The share of what is left after fixed costs that goes on the fleet.
-- On top of that a treasury above TREASURY_HOURS of costs is spent down
-- on the fleet, and one below it is rebuilt at the fleet's expense, over
-- SPEND_HOURS.
Powers.FLEET_SHARE = 0.55
Powers.TREASURY_HOURS = 24
Powers.SPEND_HOURS = 48
-- The share of its strength a power keeps at home whatever happens.
Powers.HOME_GUARD = 0.3
-- How long a power gathers a force for an attack before giving up.
Powers.PLAN_PATIENCE = 540
-- A power at peace gives up a system that loses it more than this an
-- hour. At war it will fight for one that loses it up to twice that
-- (wars are not fought for profit alone), and let it go afterwards:
-- which is how ground taken from a neighbour drifts back to it.
Powers.RELEASE_BELOW = -150

return Powers
