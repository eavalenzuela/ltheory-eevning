--!strict
-- The career agents: a window of its own (Game/UI/Windows), of what the
-- docked screen held. The station's that a new pilot starts at: opened
-- from the panel beside the corner's there, shut when the pilot undocks.
--
-- Seven people who teach a way of making a living each
-- (Core/Character/Careers): the list of them on the left, the one
-- picked out on the right. Game/UI/Careers draws both, as it did in the
-- tab. "Careers", the tab's name, opens it.

local Careers = require("@lt/Game/UI/Careers")
local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local School = {}

School.ID = "careers"

local current: Session.Session? = nil

function School.Open()
  Windows.Open(School.ID)
  Windows.Raise(School.ID)
end

function School.Close()
  Windows.Close(School.ID)
end

function School.IsOpen(): boolean
  return Windows.IsOpen(School.ID)
end

local function drawCareers(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Careers(game)
  local left, right = x + 16, x + 480
  Im.Heading("CAREER AGENTS", left, y + 78, 16, Theme.DIM)
  Im.Text("Seven people who teach a way of making a living each, and pay for the learning.", left, y + 104, 13, Theme.DIM)
  Im.Text("A lesson from each can be in hand at once. The Guide, on the dock, shows them in space (its Lessons page).", left, y + 122, 13, Theme.DIM)
  Careers.List(status, left - 8, y + 152, 448)
  Careers.Detail(session, status, right, y + 78, 444)
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked where the agents are (it is shut anywhere else).
function School.Frame(session: Session.Session, here: boolean)
  current = session
  Windows.Berthed(School.ID, here)
end

Windows.Kind(School.ID, function(_: Windows.Window, x: number, y: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  if Core.Query.Careers(game).station ~= Core.Query.Player(game).docked then
    Im.Text("The career agents are at the station a new pilot starts at.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local was = Im.Plain(true)
  drawCareers(session, game, x - 4, y - 66)
  Im.Plain(was)
end)
Windows.Make(School.ID, School.ID, "Career agents", 534, 130, 932, 544, 932, 544, nil)
Windows.Icon(School.ID, "guide")

return School
