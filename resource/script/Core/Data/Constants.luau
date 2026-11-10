--!strict
-- Numbers the rules share. Units are SI: metres, seconds, kilograms.

local Constants = {}

-- Seconds of game time per tactical tick. Every duration in the rules is
-- in seconds and is compared against tick * TICK, so this is the one
-- place the tick length lives.
Constants.TICK = 1

Constants.AU = 149597870700

-- Warp (docs/roadmap.md §3, EVE's model). A ship enters warp once it
-- moves within WARP_ALIGN_ANGLE of the destination at WARP_ALIGN_SPEED of
-- its top speed. Warps shorter than WARP_MIN_DISTANCE are refused.
Constants.WARP_ALIGN_COS = math.cos(math.rad(5))
Constants.WARP_ALIGN_SPEED = 0.75
Constants.WARP_MIN_DISTANCE = 150000
-- A ship leaves warp at this speed, or half its top speed if that is less.
Constants.WARP_DROPOUT_SPEED = 100
-- The deceleration rate is a third of the warp speed, capped here (per s).
Constants.WARP_MAX_DECELERATION = 2

-- Distances are measured between surfaces. A ship can dock or jump when
-- its surface is within this of the station's or gate's.
Constants.DOCK_RANGE = 2500
Constants.JUMP_RANGE = 2500

-- A ship arriving from a jump appears this far from the gate.
Constants.JUMP_ARRIVAL_DISTANCE = 12000
-- A ship leaves a station this far from its surface, at top speed.
Constants.UNDOCK_DISTANCE = 1500

-- Balls within this distance of a grid's anchor are on that grid.
Constants.GRID_RADIUS = 1000000

-- Ids of things described by the galaxy generator are
-- system * STRUCTURE_ID_SPAN + index; ids made during play start at
-- FIRST_DYNAMIC_ID. The two ranges cannot meet.
Constants.STRUCTURE_ID_SPAN = 10000
Constants.FIRST_DYNAMIC_ID = 1000000000

return Constants
