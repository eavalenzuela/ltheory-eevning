--!strict
-- The scanner window: what the ship's scanner shows of the system, the
-- signals it has not resolved yet, and the scanning of them.
--
-- Open in space, from the Scan button on the overview. Drawn every
-- frame with Game/UI/Im; it reads the Core through queries and acts on
-- it only through the Session. Its buttons' names, for a script
-- (Im.Press): "Scanner:close", "Scan", and "SiteWarp:<n>" for the nth
-- site listed.

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")

local Scanner = {}

Scanner.WIDTH = 468
Scanner.HEIGHT = 440

local GOOD = vector.create(0.45, 0.85, 0.55)
local KINDS: { [string]: string } = { combat = "pirate den", ore = "hidden belt", relic = "derelict" }

local open = false

function Scanner.Open()
  open = true
end

function Scanner.Close()
  open = false
end

function Scanner.IsOpen(): boolean
  return open
end

function Scanner.Draw(session: Session.Session, x: number, y: number)
  if not open then
    return
  end
  local game = session.game
  local width, height = Scanner.WIDTH, Scanner.HEIGHT
  local left, right = x + 16, x + width - 16
  Im.Panel(x, y, width, height)
  Im.Heading("SCANNER", left, y + 12, 16, Im.DIM)
  if Im.Button("x", x + width - 38, y + 10, 24, 24, true, "Scanner:close") then
    open = false
    return
  end
  local sites, wait, probes = Core.Query.Sites(game)
  local scan: State.Command = { kind = "Scan", actor = 0 }
  local can, whyNot = Session.CanDo(session, scan)
  if Im.Button("Scan", left, y + 44, 110, 28, can, "Scan") then
    Session.Do(session, scan)
  end
  Im.Text(if wait > 0 then `cycling: {math.ceil(wait)} s` elseif can then "ready" else tostring(whyNot), left + 122, y + 51, 13,
    if can then GOOD else Im.DIM)
  Im.TextRight(`{#sites} in this system`, right, y + 51, 13, Im.DIM)
  -- The probes: one put out where the ship is, and all of them called in.
  local launch: State.Command = { kind = "LaunchProbe", actor = 0 }
  local canLaunch, whyNotLaunch = Session.CanDo(session, launch)
  if Im.Button("Launch probe", left, y + 78, 110, 24, canLaunch, "Probe:launch") then
    Session.Do(session, launch)
  end
  local recall: State.Command = { kind = "RecallProbes", actor = 0 }
  if Im.Button("Recall", left + 116, y + 78, 70, 24, (Session.CanDo(session, recall)), "Probe:recall") then
    Session.Do(session, recall)
  end
  Im.Text(if probes.out > 0 or canLaunch then `{probes.here} out here, {probes.carried} in the hold` else tostring(whyNotLaunch), left + 196,
    y + 83, 12, Im.DIM)

  local line = y + 116
  if #sites == 0 then
    Im.Text("Nothing but what is on the charts.", left, line, 13, Im.DIM, 0.8)
  end
  for index, site in sites do
    if index > 7 then
      break
    end
    Im.Text(site.name, left, line, 14, if site.found then Im.TEXT else Im.DIM)
    -- (what it is; or which planet it is by, and whether it wants a probe taken there)
    local about = if site.found then KINDS[site.kind] or site.kind
      elseif site.faint then `too faint: wants a probe by {site.near}`
      elseif site.near ~= "" then `by {site.near}` .. (if site.probes > 0 then `, {site.probes} {if site.probes == 1 then "probe" else "probes"} on it` else "")
      else "unresolved"
    Im.Text(about, left, line + 17, 12, if site.faint then Im.WARN else Im.DIM)
    -- how far the scanner has got with it
    Im.Fill(left + 190, line + 8, 110, 5, Im.DIM, 0.25)
    Im.Fill(left + 190, line + 8, 110 * math.clamp(site.strength, 0, 1), 5, if site.found then GOOD else Im.ACCENT, 0.95)
    Im.Text(`{math.floor(site.strength * 100)}%`, left + 308, line + 2, 12, Im.DIM)
    if site.found then
      Im.TextRight(Format.Distance(site.distance), right - 66, line + 18, 11, Im.DIM)
      if Im.Button("Warp", right - 58, line + 2, 58, 24, (Session.Can(session, "WarpTo", site.id, 0)), `SiteWarp:{index}`) then
        session.selected = site.id
        Session.Order(session, "WarpTo", site.id, 0)
      end
    end
    line += 38
  end
  Im.Text("Every scan brings each signal nearer to found, and a probe", left, y + height - 46, 12, Im.DIM, 0.8)
  Im.Text("put out by the planet it is near makes each scan worth more.", left, y + height - 30, 12, Im.DIM, 0.8)
end

return Scanner
